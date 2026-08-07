-- Return rank capacities so clients can label vacant participant slots.
create or replace function public.split_bill_json(p_bill public.split_bills, p_viewer uuid)
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'bill_code', p_bill.bill_code,
    'title', p_bill.title,
    'currency', p_bill.currency,
    'total_amount', p_bill.total_amount::text,
    'participant_count', p_bill.participant_count,
    'share_amount', p_bill.share_amount::text,
    'allocation_mode', p_bill.allocation_mode,
    'ranks', coalesce(ranks.items, '[]'::json),
    'organizer_user_id', org.user_id,
    'organizer_name', org.display_name,
    'is_organizer', (p_bill.organizer_id = p_viewer),
    'joined', (mine.id is not null),
    'my_request_code', mine_req.request_code,
    'my_status', mine_req.status,
    'joined_count', stats.joined_count,
    'paid_count', stats.paid_count,
    'collected_amount', stats.collected_amount::text,
    'created_at', p_bill.created_at
  )
  from public.profiles org
  cross join lateral (
    select count(*) as joined_count,
           count(*) filter (where pr.status = 'paid') as paid_count,
           coalesce(sum(pr.amount) filter (where pr.status = 'paid'), 0) as collected_amount
      from public.split_bill_participants sbp
      join public.payment_requests pr on pr.id = sbp.payment_request_id
     where sbp.split_bill_id = p_bill.id
  ) stats
  cross join lateral (
    select coalesce(json_agg(json_build_object(
      'rank_code', r.rank_code,
      'label', r.label,
      'amount', r.amount::text,
      'display_order', r.display_order,
      'capacity', r.capacity
    ) order by r.display_order), '[]'::json) items
    from public.split_bill_ranks r where r.split_bill_id = p_bill.id
  ) ranks
  left join public.split_bill_participants mine
    on mine.split_bill_id = p_bill.id and mine.participant_id = p_viewer
  left join public.payment_requests mine_req on mine_req.id = mine.payment_request_id
  where org.id = p_bill.organizer_id;
$$;

create or replace function public.find_public_split_bill(p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_bill public.split_bills;
  v_organizer_name text;
  v_ranks json;
begin
  select * into v_bill from public.split_bills where bill_code = upper(trim(p_code));
  if v_bill.id is null then raise exception 'SPLIT_BILL_NOT_FOUND'; end if;
  select display_name into v_organizer_name from public.profiles where id = v_bill.organizer_id;
  select coalesce(json_agg(json_build_object(
    'rank_code', rank_code,
    'label', label,
    'amount', amount::text,
    'display_order', display_order,
    'capacity', capacity
  ) order by display_order), '[]'::json)
    into v_ranks from public.split_bill_ranks where split_bill_id = v_bill.id;
  return json_build_object(
    'bill_code', v_bill.bill_code, 'title', v_bill.title,
    'currency', v_bill.currency, 'total_amount', v_bill.total_amount::text,
    'participant_count', v_bill.participant_count, 'share_amount', v_bill.share_amount::text,
    'organizer_name', v_organizer_name, 'allocation_mode', v_bill.allocation_mode,
    'ranks', v_ranks
  );
end;
$$;
