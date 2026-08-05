-- ユーザーが送金相手を保存するための一覧。
create table public.saved_users (
  owner_id         uuid not null references public.profiles (id) on delete cascade,
  saved_profile_id uuid not null references public.profiles (id) on delete cascade,
  created_at       timestamptz not null default now(),
  primary key (owner_id, saved_profile_id),
  check (owner_id <> saved_profile_id)
);

create index saved_users_owner_created_idx
  on public.saved_users (owner_id, created_at desc);

alter table public.saved_users enable row level security;

create policy "saved_users_select_own" on public.saved_users
  for select using (auth.uid() = owner_id);
create policy "saved_users_insert_own" on public.saved_users
  for insert with check (auth.uid() = owner_id);
create policy "saved_users_delete_own" on public.saved_users
  for delete using (auth.uid() = owner_id);

create or replace function public.list_my_saved_users()
returns json
language sql
security definer
set search_path = public
as $$
  select coalesce(json_agg(row_to_json(x)), '[]'::json)
  from (
    select p.user_id, p.display_name, s.created_at
      from public.saved_users s
      join public.profiles p on p.id = s.saved_profile_id
     where s.owner_id = auth.uid()
     order by s.created_at desc
  ) x;
$$;

create or replace function public.save_user(p_user_id text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_saved public.profiles;
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;

  select * into v_saved from public.profiles
   where user_id = upper(trim(p_user_id));
  if v_saved.id is null then raise exception 'RECIPIENT_NOT_FOUND'; end if;
  if v_saved.id = auth.uid() then raise exception 'SELF_SAVE'; end if;

  insert into public.saved_users (owner_id, saved_profile_id)
  values (auth.uid(), v_saved.id)
  on conflict (owner_id, saved_profile_id) do nothing;

  return json_build_object(
    'user_id', v_saved.user_id,
    'display_name', v_saved.display_name
  );
end;
$$;

revoke execute on function public.list_my_saved_users() from anon;
revoke execute on function public.save_user(text) from anon;
