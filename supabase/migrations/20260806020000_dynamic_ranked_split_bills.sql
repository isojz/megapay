-- Connect the weighted-split editor to persisted ranked split bills.
alter table public.split_bill_ranks
  add column capacity int check (capacity is null or capacity > 0);

create or replace function public.create_ranked_split_bill(
  p_title text,
  p_currency text,
  p_ranks jsonb
)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_organizer uuid := auth.uid();
  v_currency text := upper(trim(p_currency));
  v_payer_count int;
  v_total numeric;
  v_bill public.split_bills;
begin
  if v_organizer is null then raise exception 'UNAUTHENTICATED'; end if;
  if p_title is null or length(trim(p_title)) = 0 then raise exception 'INVALID_TITLE'; end if;
  if v_currency !~ '^[A-Z0-9]{3,10}$' then raise exception 'INVALID_CURRENCY'; end if;
  if p_ranks is null or jsonb_typeof(p_ranks) <> 'array' or jsonb_array_length(p_ranks) < 1 then
    raise exception 'INVALID_SPLIT_BILL_RANK';
  end if;

  select sum(x.capacity), sum(x.amount * x.capacity)
    into v_payer_count, v_total
    from jsonb_to_recordset(p_ranks) as x(label text, amount numeric, capacity int)
   where length(trim(x.label)) > 0 and x.amount > 0 and x.capacity > 0;

  if v_payer_count is null or v_payer_count < 1 or v_payer_count > 99
     or v_total is null or v_total <= 0
     or (select count(*) from jsonb_array_elements(p_ranks)) <>
        (select count(*) from jsonb_to_recordset(p_ranks)
          as x(label text, amount numeric, capacity int)
         where length(trim(x.label)) > 0 and x.amount > 0 and x.capacity > 0) then
    raise exception 'INVALID_SPLIT_BILL_RANK';
  end if;

  insert into public.split_bills
    (bill_code, organizer_id, title, currency, total_amount,
     participant_count, share_amount, allocation_mode)
  values
    (public.generate_ranked_split_bill_code(), v_organizer, trim(p_title),
     v_currency, v_total, v_payer_count + 1, 1, 'ranked')
  returning * into v_bill;

  insert into public.split_bill_ranks
    (split_bill_id, rank_code, label, amount, capacity, display_order)
  select v_bill.id,
         'G' || item.ordinality,
         trim(item.value->>'label'),
         (item.value->>'amount')::numeric,
         (item.value->>'capacity')::int,
         item.ordinality::int
    from jsonb_array_elements(p_ranks) with ordinality as item(value, ordinality)
   order by item.ordinality;

  return public.split_bill_json(v_bill, v_organizer);
end;
$$;

create or replace function public.join_ranked_split_bill(p_code text, p_rank_code text)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_participant uuid := auth.uid();
  v_bill public.split_bills;
  v_rank public.split_bill_ranks;
  v_joined int;
  v_rank_joined int;
  v_request public.payment_requests;
begin
  if v_participant is null then raise exception 'UNAUTHENTICATED'; end if;
  select * into v_bill from public.split_bills
   where bill_code = upper(trim(p_code)) and allocation_mode = 'ranked' for update;
  if v_bill.id is null then raise exception 'SPLIT_BILL_NOT_FOUND'; end if;
  if v_bill.organizer_id = v_participant then raise exception 'ORGANIZER_CANNOT_JOIN'; end if;
  if exists (select 1 from public.split_bill_participants
             where split_bill_id = v_bill.id and participant_id = v_participant) then
    return public.split_bill_json(v_bill, v_participant);
  end if;
  select * into v_rank from public.split_bill_ranks
   where split_bill_id = v_bill.id and rank_code = upper(trim(p_rank_code));
  if v_rank.id is null then raise exception 'INVALID_SPLIT_BILL_RANK'; end if;
  select count(*) into v_joined from public.split_bill_participants where split_bill_id = v_bill.id;
  if v_joined >= v_bill.participant_count - 1 then raise exception 'SPLIT_BILL_FULL'; end if;
  if v_rank.capacity is not null then
    select count(*) into v_rank_joined from public.split_bill_participants where rank_id = v_rank.id;
    if v_rank_joined >= v_rank.capacity then raise exception 'SPLIT_BILL_RANK_FULL'; end if;
  end if;
  insert into public.payment_requests
    (request_code, requester_id, payer_id, currency, amount, memo)
  values
    (public.generate_request_code(), v_bill.organizer_id, v_participant,
     v_bill.currency, v_rank.amount, v_bill.title || '（' || v_rank.label || '）')
  returning * into v_request;
  insert into public.split_bill_participants
    (split_bill_id, participant_id, payment_request_id, rank_id)
  values (v_bill.id, v_participant, v_request.id, v_rank.id);
  return public.split_bill_json(v_bill, v_participant);
end;
$$;

revoke execute on function public.create_ranked_split_bill(text, text, jsonb) from public;
grant execute on function public.create_ranked_split_bill(text, text, jsonb) to authenticated;
