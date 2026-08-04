-- ============================================================================
-- MegaPay MVP 初期スキーマ
--
-- 適用方法（どちらか）:
--   A. Supabase Dashboard > SQL Editor にこのファイルを貼り付けて実行
--   B. Supabase CLI: `supabase link` 後に `supabase db push`
-- ============================================================================

-- ---------------------------------------------------------------------------
-- テーブル
-- ---------------------------------------------------------------------------

-- ユーザープロフィール（auth.users と 1:1）
create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  user_id      text not null unique,   -- 送金先指定に使う公開ID（例: MP-12345678）
  display_name text not null default '',
  created_at   timestamptz not null default now()
);

-- 通貨別残高（1ユーザーが複数通貨を保有できる）
create table public.balances (
  id         bigint generated always as identity primary key,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  currency   text not null check (currency ~ '^[A-Z0-9]{3,10}$'),
  amount     numeric(30, 8) not null default 0 check (amount >= 0),
  updated_at timestamptz not null default now(),
  unique (profile_id, currency)
);

-- 送金履歴
create table public.transfers (
  id           uuid primary key default gen_random_uuid(),
  sender_id    uuid not null references public.profiles (id),
  recipient_id uuid not null references public.profiles (id),
  currency     text not null check (currency ~ '^[A-Z0-9]{3,10}$'),
  amount       numeric(30, 8) not null check (amount > 0),
  memo         text,
  created_at   timestamptz not null default now(),
  check (sender_id <> recipient_id)
);

create index transfers_sender_idx    on public.transfers (sender_id, created_at desc);
create index transfers_recipient_idx on public.transfers (recipient_id, created_at desc);

-- ---------------------------------------------------------------------------
-- RLS（Row Level Security）
-- 参照は本人のデータのみ。書き込みは全て SECURITY DEFINER 関数経由で行うため、
-- insert/update/delete のポリシーは意図的に定義しない（= クライアントから直接不可）。
-- ---------------------------------------------------------------------------

alter table public.profiles  enable row level security;
alter table public.balances  enable row level security;
alter table public.transfers enable row level security;

create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = id);

create policy "balances_select_own" on public.balances
  for select using (auth.uid() = profile_id);

create policy "transfers_select_own" on public.transfers
  for select using (auth.uid() = sender_id or auth.uid() = recipient_id);

-- ---------------------------------------------------------------------------
-- 関数・トリガー
-- ---------------------------------------------------------------------------

-- 公開ID（MP-数字8桁）を重複しないように生成する
create or replace function public.generate_user_id()
returns text
language plpgsql
as $$
declare
  v_id text;
begin
  loop
    v_id := 'MP-' || lpad(floor(random() * 100000000)::bigint::text, 8, '0');
    exit when not exists (select 1 from public.profiles where user_id = v_id);
  end loop;
  return v_id;
end;
$$;

-- サインアップ時にプロフィールと初期残高を自動作成する
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
begin
  v_name := coalesce(
    nullif(new.raw_user_meta_data ->> 'display_name', ''),
    split_part(coalesce(new.email, ''), '@', 1)
  );

  insert into public.profiles (id, user_id, display_name)
  values (new.id, public.generate_user_id(), v_name);

  -- デモ用ウェルカム残高。本番リリース時はこの insert を削除し、入金機能に置き換える
  insert into public.balances (profile_id, currency, amount)
  values
    (new.id, 'JPY', 500000),
    (new.id, 'USD', 3000),
    (new.id, 'EUR', 2000);

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 送金先の存在確認（公開IDから表示名を取得。送金前の宛先確認に使う）
create or replace function public.find_recipient(p_user_id text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result json;
begin
  if auth.uid() is null then
    raise exception 'UNAUTHENTICATED';
  end if;

  select json_build_object('user_id', user_id, 'display_name', display_name)
    into v_result
    from public.profiles
   where user_id = upper(trim(p_user_id));

  if v_result is null then
    raise exception 'RECIPIENT_NOT_FOUND';
  end if;

  return v_result;
end;
$$;

-- 送金を 1 トランザクションで実行する（残高チェック → 減算 → 加算 → 履歴記録）
create or replace function public.execute_transfer(
  p_recipient_user_id text,
  p_currency          text,
  p_amount            numeric,
  p_memo              text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sender_id      uuid := auth.uid();
  v_recipient_id   uuid;
  v_currency       text := upper(trim(p_currency));
  v_sender_balance numeric;
  v_first          uuid;
  v_second         uuid;
  v_transfer       public.transfers;
begin
  if v_sender_id is null then
    raise exception 'UNAUTHENTICATED';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'INVALID_AMOUNT';
  end if;
  if v_currency !~ '^[A-Z0-9]{3,10}$' then
    raise exception 'INVALID_CURRENCY';
  end if;

  select id into v_recipient_id
    from public.profiles
   where user_id = upper(trim(p_recipient_user_id));

  if v_recipient_id is null then
    raise exception 'RECIPIENT_NOT_FOUND';
  end if;
  if v_recipient_id = v_sender_id then
    raise exception 'SELF_TRANSFER';
  end if;

  -- 受取側の残高行がなければ 0 で作成しておく（初めて受け取る通貨に対応）
  insert into public.balances (profile_id, currency, amount)
  values (v_recipient_id, v_currency, 0)
  on conflict (profile_id, currency) do nothing;

  -- 相互送金が同時に走ってもデッドロックしないよう、常に profile_id 順にロックする
  if v_sender_id < v_recipient_id then
    v_first := v_sender_id;  v_second := v_recipient_id;
  else
    v_first := v_recipient_id;  v_second := v_sender_id;
  end if;
  perform 1 from public.balances where profile_id = v_first  and currency = v_currency for update;
  perform 1 from public.balances where profile_id = v_second and currency = v_currency for update;

  select amount into v_sender_balance
    from public.balances
   where profile_id = v_sender_id and currency = v_currency;

  if v_sender_balance is null or v_sender_balance < p_amount then
    raise exception 'INSUFFICIENT_FUNDS';
  end if;

  update public.balances
     set amount = amount - p_amount, updated_at = now()
   where profile_id = v_sender_id and currency = v_currency;

  update public.balances
     set amount = amount + p_amount, updated_at = now()
   where profile_id = v_recipient_id and currency = v_currency;

  insert into public.transfers (sender_id, recipient_id, currency, amount, memo)
  values (v_sender_id, v_recipient_id, v_currency, p_amount, p_memo)
  returning * into v_transfer;

  return json_build_object(
    'id',                v_transfer.id,
    'recipient_user_id', upper(trim(p_recipient_user_id)),
    'currency',          v_transfer.currency,
    'amount',            v_transfer.amount::text,
    'memo',              v_transfer.memo,
    'created_at',        v_transfer.created_at
  );
end;
$$;

-- 自分の送金履歴（相手の公開ID・表示名つき）を新しい順に返す
create or replace function public.list_my_transfers(p_limit int default 50)
returns json
language sql
security definer
set search_path = public
as $$
  select coalesce(json_agg(row_to_json(x)), '[]'::json)
  from (
    select t.id,
           case when t.sender_id = auth.uid() then 'sent' else 'received' end as direction,
           p.user_id      as counterpart_user_id,
           p.display_name as counterpart_name,
           t.currency,
           t.amount::text as amount,
           t.memo,
           t.created_at
      from public.transfers t
      join public.profiles p
        on p.id = case when t.sender_id = auth.uid() then t.recipient_id else t.sender_id end
     where t.sender_id = auth.uid() or t.recipient_id = auth.uid()
     order by t.created_at desc
     limit least(coalesce(p_limit, 50), 200)
  ) x;
$$;

-- ---------------------------------------------------------------------------
-- 権限の整理（未ログイン(anon)からは業務関数を呼べないようにする）
-- ---------------------------------------------------------------------------

revoke execute on function public.find_recipient(text)                       from anon;
revoke execute on function public.execute_transfer(text, text, numeric, text) from anon;
revoke execute on function public.list_my_transfers(int)                     from anon;
revoke execute on function public.generate_user_id()                         from anon, authenticated;
