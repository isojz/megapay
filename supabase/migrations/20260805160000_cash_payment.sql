-- ============================================================================
-- 現金払いの記録
--
-- 割り勘では「その場で現金を渡す」ことがあるため、アプリ内の残高を動かさずに
-- 請求を支払い済みにできるようにする。
--   - 残高払い（balance）: これまでどおり送金が実行され、transfer_id が入る
--   - 現金払い（cash）  : 残高は動かさず、支払い済みとしてのみ記録する（transfer_id は null）
--
-- 記録するのは支払い者本人（自己申告）。集金者は参加者一覧で支払い方法を確認できる。
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 支払い方法の列を追加（既存行はすべて残高払い扱い）
-- ---------------------------------------------------------------------------

alter table public.payment_requests
  add column if not exists payment_method text not null default 'balance'
    check (payment_method in ('balance', 'cash'));

-- ---------------------------------------------------------------------------
-- 既存関数の更新（支払い方法を返す / 記録する）
-- ---------------------------------------------------------------------------

-- 請求 1 件の JSON に payment_method を追加する
create or replace function public.payment_request_json(
  p_request public.payment_requests,
  p_viewer  uuid
)
returns json
language sql
stable
security definer
set search_path = public
as $$
  select json_build_object(
    'request_code',      p_request.request_code,
    'direction',         case when p_request.requester_id = p_viewer then 'requested' else 'billed' end,
    'requester_user_id', rq.user_id,
    'requester_name',    rq.display_name,
    'payer_user_id',     py.user_id,
    'payer_name',        py.display_name,
    'currency',          p_request.currency,
    'amount',            p_request.amount::text,
    'memo',              p_request.memo,
    'status',            p_request.status,
    'payment_method',    p_request.payment_method,
    'created_at',        p_request.created_at,
    'paid_at',           p_request.paid_at,
    'cancelled_at',      p_request.cancelled_at
  )
  from public.profiles rq, public.profiles py
  where rq.id = p_request.requester_id
    and py.id = p_request.payer_id;
$$;

-- 残高払い。支払い方法を明示的に balance として記録する以外は従来どおり。
create or replace function public.pay_payment_request(p_code text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payer    uuid := auth.uid();
  v_request  public.payment_requests;
  v_transfer public.transfers;
begin
  if v_payer is null then
    raise exception 'UNAUTHENTICATED';
  end if;

  -- 同じコードで二重に支払われないよう行ロックを取る
  select * into v_request
    from public.payment_requests
   where request_code = upper(trim(p_code))
     for update;

  if v_request.id is null or v_request.payer_id <> v_payer then
    raise exception 'REQUEST_NOT_FOUND';
  end if;
  if v_request.status = 'paid' then
    raise exception 'REQUEST_ALREADY_PAID';
  end if;
  if v_request.status = 'cancelled' then
    raise exception 'REQUEST_CANCELLED';
  end if;

  v_transfer := public.internal_move_funds(
    v_payer,
    v_request.requester_id,
    v_request.currency,
    v_request.amount,
    coalesce(nullif(v_request.memo, ''), '請求 ' || v_request.request_code)
  );

  update public.payment_requests
     set status = 'paid',
         paid_at = now(),
         transfer_id = v_transfer.id,
         payment_method = 'balance'
   where id = v_request.id
  returning * into v_request;

  return public.payment_request_json(v_request, v_payer);
end;
$$;

-- ---------------------------------------------------------------------------
-- 現金払い
-- ---------------------------------------------------------------------------

-- 現金で支払ったことを記録する（残高・送金履歴は一切変更しない）
create or replace function public.pay_payment_request_by_cash(p_code text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payer   uuid := auth.uid();
  v_request public.payment_requests;
begin
  if v_payer is null then
    raise exception 'UNAUTHENTICATED';
  end if;

  -- 残高払いと同時に実行されても二重計上しないよう行ロックを取る
  select * into v_request
    from public.payment_requests
   where request_code = upper(trim(p_code))
     for update;

  if v_request.id is null or v_request.payer_id <> v_payer then
    raise exception 'REQUEST_NOT_FOUND';
  end if;
  if v_request.status = 'paid' then
    raise exception 'REQUEST_ALREADY_PAID';
  end if;
  if v_request.status = 'cancelled' then
    raise exception 'REQUEST_CANCELLED';
  end if;

  update public.payment_requests
     set status = 'paid',
         paid_at = now(),
         payment_method = 'cash'
   where id = v_request.id
  returning * into v_request;

  return public.payment_request_json(v_request, v_payer);
end;
$$;

revoke execute on function public.pay_payment_request_by_cash(text) from anon;

-- ---------------------------------------------------------------------------
-- 割り勘の参加者一覧にも支払い方法を含める（集金者が現金分を把握できるように）
-- ---------------------------------------------------------------------------

create or replace function public.list_split_bill_participants(p_code text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer uuid := auth.uid();
  v_bill   public.split_bills;
  v_result json;
begin
  if v_viewer is null then
    raise exception 'UNAUTHENTICATED';
  end if;

  select * into v_bill
    from public.split_bills
   where bill_code = upper(trim(p_code));

  if v_bill.id is null then
    raise exception 'SPLIT_BILL_NOT_FOUND';
  end if;

  if v_bill.organizer_id <> v_viewer and not exists (
    select 1 from public.split_bill_participants
     where split_bill_id = v_bill.id and participant_id = v_viewer
  ) then
    raise exception 'SPLIT_BILL_NOT_FOUND';  -- 部外者には存在自体を知らせない
  end if;

  select coalesce(json_agg(row_to_json(x) order by x.joined_at), '[]'::json)
    into v_result
  from (
    select p.user_id,
           p.display_name,
           pr.request_code,
           pr.amount::text as amount,
           pr.status,
           pr.payment_method,
           pr.paid_at,
           (sbp.participant_id = v_viewer) as is_me,
           sbp.joined_at
      from public.split_bill_participants sbp
      join public.profiles p          on p.id = sbp.participant_id
      join public.payment_requests pr on pr.id = sbp.payment_request_id
     where sbp.split_bill_id = v_bill.id
  ) x;

  return v_result;
end;
$$;
