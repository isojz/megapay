-- 割り勘リンクを開いた未ログイン利用者向けの限定プレビュー。
-- 参加者一覧や支払い状況、内部IDは公開しない。
create or replace function public.find_public_split_bill(p_code text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bill public.split_bills;
  v_organizer_name text;
begin
  select * into v_bill
    from public.split_bills
   where bill_code = upper(trim(p_code));

  if v_bill.id is null then
    raise exception 'SPLIT_BILL_NOT_FOUND';
  end if;

  select display_name into v_organizer_name
    from public.profiles
   where id = v_bill.organizer_id;

  return json_build_object(
    'bill_code',         v_bill.bill_code,
    'title',             v_bill.title,
    'currency',          v_bill.currency,
    'total_amount',      v_bill.total_amount::text,
    'participant_count', v_bill.participant_count,
    'share_amount',      v_bill.share_amount::text,
    'organizer_name',    v_organizer_name
  );
end;
$$;

revoke execute on function public.find_public_split_bill(text) from public;
grant execute on function public.find_public_split_bill(text) to anon, authenticated;
