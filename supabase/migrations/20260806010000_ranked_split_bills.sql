-- Ranked split bills. Equal split bills remain backward compatible.
alter table public.split_bills
  add column allocation_mode text not null default 'equal'
  check (allocation_mode in ('equal', 'ranked'));

create table public.split_bill_ranks (
  id uuid primary key default gen_random_uuid(),
  split_bill_id uuid not null references public.split_bills(id) on delete cascade,
  rank_code text not null,
  label text not null,
  amount numeric(30, 8) not null check (amount > 0),
  display_order int not null,
  unique (split_bill_id, rank_code)
);

alter table public.split_bill_participants
  add column rank_id uuid references public.split_bill_ranks(id);

alter table public.split_bill_ranks enable row level security;

create or replace function public.generate_ranked_split_bill_code()
returns text language plpgsql as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code text;
begin
  loop
    v_code := 'SR-';
    for i in 1..8 loop
      v_code := v_code || substr(v_alphabet, floor(random() * length(v_alphabet))::int + 1, 1);
    end loop;
    exit when not exists (select 1 from public.split_bills where bill_code = v_code);
  end loop;
  return v_code;
end;
$$;

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
      'rank_code', r.rank_code, 'label', r.label,
      'amount', r.amount::text, 'display_order', r.display_order
    ) order by r.display_order), '[]'::json) items
    from public.split_bill_ranks r where r.split_bill_id = p_bill.id
  ) ranks
  left join public.split_bill_participants mine
    on mine.split_bill_id = p_bill.id and mine.participant_id = p_viewer
  left join public.payment_requests mine_req on mine_req.id = mine.payment_request_id
  where org.id = p_bill.organizer_id;
$$;

create or replace function public.create_ranked_split_bill_test(
  p_title text, p_participant_count int
)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_organizer uuid := auth.uid();
  v_bill public.split_bills;
begin
  if v_organizer is null then raise exception 'UNAUTHENTICATED'; end if;
  if p_title is null or length(trim(p_title)) = 0 then raise exception 'INVALID_TITLE'; end if;
  if p_participant_count is null or p_participant_count < 2 or p_participant_count > 100 then
    raise exception 'INVALID_PARTICIPANT_COUNT';
  end if;

  insert into public.split_bills
    (bill_code, organizer_id, title, currency, total_amount, participant_count, share_amount, allocation_mode)
  values
    (public.generate_ranked_split_bill_code(), v_organizer, trim(p_title), 'JPY',
     3000 * p_participant_count, p_participant_count, 3000, 'ranked')
  returning * into v_bill;

  insert into public.split_bill_ranks(split_bill_id, rank_code, label, amount, display_order)
  values (v_bill.id, 'A', 'Aランク', 5000, 1),
         (v_bill.id, 'B', 'Bランク', 3000, 2),
         (v_bill.id, 'C', 'Cランク', 1000, 3);
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

-- Do not allow an SR code to bypass rank selection through the equal-split join RPC.
create or replace function public.join_split_bill(p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_participant uuid := auth.uid();
  v_bill public.split_bills;
  v_joined int;
  v_request public.payment_requests;
begin
  if v_participant is null then raise exception 'UNAUTHENTICATED'; end if;
  select * into v_bill from public.split_bills
   where bill_code = upper(trim(p_code)) for update;
  if v_bill.id is null then raise exception 'SPLIT_BILL_NOT_FOUND'; end if;
  if v_bill.allocation_mode <> 'equal' then raise exception 'INVALID_SPLIT_BILL_RANK'; end if;
  if v_bill.organizer_id = v_participant then raise exception 'ORGANIZER_CANNOT_JOIN'; end if;
  if exists (select 1 from public.split_bill_participants
             where split_bill_id = v_bill.id and participant_id = v_participant) then
    return public.split_bill_json(v_bill, v_participant);
  end if;
  select count(*) into v_joined from public.split_bill_participants where split_bill_id = v_bill.id;
  if v_joined >= v_bill.participant_count - 1 then raise exception 'SPLIT_BILL_FULL'; end if;
  insert into public.payment_requests
    (request_code, requester_id, payer_id, currency, amount, memo)
  values
    (public.generate_request_code(), v_bill.organizer_id, v_participant,
     v_bill.currency, v_bill.share_amount, v_bill.title)
  returning * into v_request;
  insert into public.split_bill_participants
    (split_bill_id, participant_id, payment_request_id)
  values (v_bill.id, v_participant, v_request.id);
  return public.split_bill_json(v_bill, v_participant);
end;
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
    'rank_code', rank_code, 'label', label, 'amount', amount::text,
    'display_order', display_order) order by display_order), '[]'::json)
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

create or replace function public.list_split_bill_participants(p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_viewer uuid := auth.uid();
  v_bill public.split_bills;
  v_result json;
begin
  if v_viewer is null then raise exception 'UNAUTHENTICATED'; end if;
  select * into v_bill from public.split_bills where bill_code = upper(trim(p_code));
  if v_bill.id is null then raise exception 'SPLIT_BILL_NOT_FOUND'; end if;
  if v_bill.organizer_id <> v_viewer and not exists (
    select 1 from public.split_bill_participants
     where split_bill_id = v_bill.id and participant_id = v_viewer
  ) then raise exception 'SPLIT_BILL_NOT_FOUND'; end if;
  select coalesce(json_agg(row_to_json(x) order by x.joined_at), '[]'::json) into v_result
  from (
    select p.user_id, p.display_name, pr.request_code, pr.amount::text as amount,
           pr.status, pr.payment_method, pr.paid_at,
           (sbp.participant_id = v_viewer) as is_me, sbp.joined_at,
           r.rank_code, r.label as rank_label, r.amount::text as rank_amount
      from public.split_bill_participants sbp
      join public.profiles p on p.id = sbp.participant_id
      join public.payment_requests pr on pr.id = sbp.payment_request_id
      left join public.split_bill_ranks r on r.id = sbp.rank_id
     where sbp.split_bill_id = v_bill.id
  ) x;
  return v_result;
end;
$$;

revoke execute on function public.generate_ranked_split_bill_code() from public;
revoke execute on function public.create_ranked_split_bill_test(text, int) from public;
grant execute on function public.create_ranked_split_bill_test(text, int) to authenticated;
revoke execute on function public.join_ranked_split_bill(text, text) from public;
grant execute on function public.join_ranked_split_bill(text, text) to authenticated;
grant execute on function public.find_public_split_bill(text) to anon, authenticated;
