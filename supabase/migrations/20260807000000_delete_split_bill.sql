-- ============================================================================
-- 割り勘の削除
--
-- 作成した割り勘を、集金者本人が取り消せるようにする。
--
-- 誰か 1 人でも支払い済みなら削除できない。支払いは残高を実際に動かしており、
-- 割り勘を消すと入金の理由がたどれなくなるため。まだ誰も払っていない場合に
-- 限り、参加者あての請求ごと取り消す。
-- ============================================================================

create or replace function public.delete_split_bill(p_code text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user        uuid := auth.uid();
  v_bill        public.split_bills;
  v_paid_count  int;
  v_request_ids uuid[];
begin
  if v_user is null then
    raise exception 'UNAUTHENTICATED';
  end if;

  -- 削除の判定中に参加や支払いが割り込まないよう、割り勘の行をロックする
  select * into v_bill
    from public.split_bills
   where bill_code = upper(trim(p_code))
     for update;

  if v_bill.id is null then
    raise exception 'SPLIT_BILL_NOT_FOUND';
  end if;

  -- 集金者以外には存在自体を知らせない（参加者も削除はできない）
  if v_bill.organizer_id <> v_user then
    raise exception 'SPLIT_BILL_NOT_FOUND';
  end if;

  select count(*) into v_paid_count
    from public.split_bill_participants sbp
    join public.payment_requests pr on pr.id = sbp.payment_request_id
   where sbp.split_bill_id = v_bill.id
     and pr.status = 'paid';

  if v_paid_count > 0 then
    raise exception 'SPLIT_BILL_ALREADY_PAID';
  end if;

  -- 参加者あての請求も一緒に取り消す。残したままだと、割り勘が消えたのに
  -- 参加者側に支払い先の分からない請求だけが残ってしまう。
  select array_agg(payment_request_id) into v_request_ids
    from public.split_bill_participants
   where split_bill_id = v_bill.id;

  -- split_bill_participants が payment_requests を参照しているため、
  -- 参加者 → 請求 の順に消す。
  delete from public.split_bill_participants where split_bill_id = v_bill.id;

  if v_request_ids is not null then
    delete from public.payment_requests where id = any (v_request_ids);
  end if;

  -- ランク（傾斜）の設定は split_bills への外部キーが on delete cascade のため
  -- ここで一緒に消える。
  delete from public.split_bills where id = v_bill.id;

  return json_build_object(
    'bill_code', v_bill.bill_code,
    'title',     v_bill.title,
    'deleted',   true
  );
end;
$$;

revoke execute on function public.delete_split_bill(text) from anon;
