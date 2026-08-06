-- ============================================================================
-- 外部決済（PayPay・クレジットカード）での支払い
--
-- 支払い方法は3種類になる。
--   - 残高払い（balance） : 支払い者の残高が減り、集金者の残高が増える
--   - 現金払い（cash）    : どちらの残高も動かさず、支払い済みの記録だけ残す
--   - 外部決済（external）: 支払い者の残高は減らさず、集金者の残高だけ増える
--
-- 外部決済で支払い者の残高が減らないのは、実際の引き落としが PayPay やカード会社
-- 側で行われる想定のため。アプリ内の残高は「MegaPay に預けてある残高」であり、
-- 外部決済はそこを通らない。集金者から見れば入金されたことに変わりはないので、
-- 受け取り側の残高と送金履歴には反映する。
--
-- 注意: 外部決済の連携は未実装。そのため実際には引き落としが起きないまま
-- 集金者の残高が増える。デモ用の挙動であり、本番では決済代行の入金確認を
-- 受けてから残高を増やすこと。
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 支払い方法に external を追加する
-- ---------------------------------------------------------------------------

alter table public.payment_requests
  drop constraint if exists payment_requests_payment_method_check;

alter table public.payment_requests
  add constraint payment_requests_payment_method_check
    check (payment_method in ('balance', 'cash', 'external'));

-- ---------------------------------------------------------------------------
-- 受け取り側だけに入金する（送金元の残高は減らさない）
-- ---------------------------------------------------------------------------

create or replace function public.internal_credit_funds(
  p_sender_id    uuid,
  p_recipient_id uuid,
  p_currency     text,
  p_amount       numeric,
  p_memo         text
)
returns public.transfers
language plpgsql
security definer
set search_path = public
as $$
declare
  v_currency text := upper(trim(p_currency));
  v_transfer public.transfers;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'INVALID_AMOUNT';
  end if;
  if v_currency !~ '^[A-Z0-9]{3,10}$' then
    raise exception 'INVALID_CURRENCY';
  end if;
  if p_sender_id = p_recipient_id then
    raise exception 'SELF_TRANSFER';
  end if;

  -- 受取側の残高行がなければ 0 で作成しておく（初めて受け取る通貨に対応）
  insert into public.balances (profile_id, currency, amount)
  values (p_recipient_id, v_currency, 0)
  on conflict (profile_id, currency) do nothing;

  perform 1 from public.balances
   where profile_id = p_recipient_id and currency = v_currency
     for update;

  -- 減算が無いので残高不足の判定は不要。増やす側だけを更新する。
  update public.balances
     set amount = amount + p_amount, updated_at = now()
   where profile_id = p_recipient_id and currency = v_currency;

  -- 双方の履歴に出したいので送金レコードは残す
  -- （list_my_transfers は sender_id / recipient_id の両方から引く）
  insert into public.transfers (sender_id, recipient_id, currency, amount, memo)
  values (p_sender_id, p_recipient_id, v_currency, p_amount, p_memo)
  returning * into v_transfer;

  return v_transfer;
end;
$$;

revoke execute on function
  public.internal_credit_funds(uuid, uuid, text, numeric, text)
  from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 外部決済で支払う
-- ---------------------------------------------------------------------------

create or replace function public.pay_payment_request_by_external(p_code text)
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

  -- 他の支払い方法と同時に実行されても二重計上しないよう行ロックを取る
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

  v_transfer := public.internal_credit_funds(
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
         payment_method = 'external'
   where id = v_request.id
  returning * into v_request;

  return public.payment_request_json(v_request, v_payer);
end;
$$;

revoke execute on function public.pay_payment_request_by_external(text) from anon;
