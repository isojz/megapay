alter table public.profiles
add column if not exists avatar_key text default 'avatar_01';

comment on column public.profiles.avatar_key is
  'プロフィールアイコンID';