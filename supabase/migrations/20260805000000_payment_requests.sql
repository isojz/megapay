-- ============================================================================
-- 請求（payment requests）機能
--
-- 流れ:
--   1. 請求する人が「相手のユーザーID・通貨・金額」を指定して請求を作成
--   2. 請求コード（RQ-XXXXXXXX）が発行される
--   3. 請求された人がそのコードを入力すると送金が実行され、請求が成立する
--
-- 適用方法は初期スキーマと同じ（SQL Editor に貼り付け、または supabase db push）
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 送金処理の共通化
--
-- 請求の支払いも通常の送金と同じ資金移動を行うため、既存 execute_transfer から
-- 資金移動部分を internal_move_funds として切り出し、双方から呼ぶ。
-- （初期スキーマのファイルは変更せず、ここで create or replace して差し替える）
-- ---------------------------------------------------------------------------

-- 残高チェック → 減算 → 加算 → 履歴記録を 1 トランザクションで行う内部関数。
-- 呼び出し元が本人確認を済ませている前提のため、クライアントからは実行できない。
create or replace function public.internal_move_funds(
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
  v_currency       text := upper(trim(p_currency));
  v_sender_balance numeric;
  v_first          uuid;
  v_second         uuid;
  v_transfer       public.transfers;
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

  -- 相互送金が同時に走ってもデッドロックしないよう、常に profile_id 順にロックする
  if p_sender_id < p_recipient_id then
    v_first := p_sender_id;  v_second := p_recipient_id;
  else
    v_first := p_recipient_id;  v_second := p_sender_id;
  end if;
  perform 1 from public.balances where profile_id = v_first  and currency = v_currency for update;
  perform 1 from public.balances where profile_id = v_second and currency = v_currency for update;

  select amount into v_sender_balance
    from public.balances
   where profile_id = p_sender_id and currency = v_currency;

  if v_sender_balance is null or v_sender_balance < p_amount then
    raise exception 'INSUFFICIENT_FUNDS';
  end if;

  update public.balances
     set amount = amount - p_amount, updated_at = now()
   where profile_id = p_sender_id and currency = v_currency;

  update public.balances
     set amount = amount + p_amount, updated_at = now()
   where profile_id = p_recipient_id and currency = v_currency;

  insert into public.transfers (sender_id, recipient_id, currency, amount, memo)
  values (p_sender_id, p_recipient_id, v_currency, p_amount, p_memo)
  returning * into v_transfer;

  return v_transfer;
end;
$$;

revoke execute on function public.internal_move_funds(uuid, uuid, text, numeric, text)
  from anon, authenticated;

-- 既存の送金 API。入出力・エラーはこれまでと同じで、資金移動のみ共通関数に委譲する。
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
  v_sender_id    uuid := auth.uid();
  v_recipient_id uuid;
  v_transfer     public.transfers;
begin
  if v_sender_id is null then
    raise exception 'UNAUTHENTICATED';
  end if;

  select id into v_recipient_id
    from public.profiles
   where user_id = upper(trim(p_recipient_user_id));

  if v_recipient_id is null then
    raise exception 'RECIPIENT_NOT_FOUND';
  end if;

  v_transfer := public.internal_move_funds(
    v_sender_id, v_recipient_id, p_currency, p_amount, p_memo
  );

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

-- ---------------------------------------------------------------------------
-- 請求テーブル
-- ---------------------------------------------------------------------------

create table public.payment_requests (
  id           uuid primary key default gen_random_uuid(),
  request_code text not null unique,                    -- 支払い時に入力するコード（RQ-XXXXXXXX）
  requester_id uuid not null references public.profiles (id),  -- 請求した人（受け取る側）
  payer_id     uuid not null references public.profiles (id),  -- 請求された人（支払う側）
  currency     text not null check (currency ~ '^[A-Z0-9]{3,10}$'),
  amount       numeric(30, 8) not null check (amount > 0),
  memo         text,
  status       text not null default 'pending'
                 check (status in ('pending', 'paid', 'cancelled')),
  transfer_id  uuid references public.transfers (id),   -- 支払い成立時の送金
  created_at   timestamptz not null default now(),
  paid_at      timestamptz,
  cancelled_at timestamptz,
  check (requester_id <> payer_id)
);

create index payment_requests_requester_idx on public.payment_requests (requester_id, created_at desc);
create index payment_requests_payer_idx     on public.payment_requests (payer_id, created_at desc);

-- 参照は当事者のみ。書き込みは下の SECURITY DEFINER 関数経由に限定する。
alter table public.payment_requests enable row level security;

create policy "payment_requests_select_own" on public.payment_requests
  for select using (auth.uid() = requester_id or auth.uid() = payer_id);

-- ---------------------------------------------------------------------------
-- 関数
-- ---------------------------------------------------------------------------

-- 請求コードを重複しないように生成する。
-- 見間違えやすい文字（O/0, I/1）を除いた英数字を使う。
create or replace function public.generate_request_code()
returns text
language plpgsql
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code     text;
begin
  loop
    v_code := 'RQ-';
    for i in 1..8 loop
      v_code := v_code || substr(v_alphabet, floor(random() * length(v_alphabet))::int + 1, 1);
    end loop;
    exit when not exists (select 1 from public.payment_requests where request_code = v_code);
  end loop;
  return v_code;
end;
$$;

-- 請求 1 件を API 向けの JSON に整形する。
-- direction は閲覧者から見た向き: requested=自分が請求した / billed=自分が請求された
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
    'created_at',        p_request.created_at,
    'paid_at',           p_request.paid_at,
    'cancelled_at',      p_request.cancelled_at
  )
  from public.profiles rq, public.profiles py
  where rq.id = p_request.requester_id
    and py.id = p_request.payer_id;
$$;

-- 請求を作成する（請求先はユーザーIDで指定）
create or replace function public.create_payment_request(
  p_payer_user_id text,
  p_currency      text,
  p_amount        numeric,
  p_memo          text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_requester_id uuid := auth.uid();
  v_payer_id     uuid;
  v_currency     text := upper(trim(p_currency));
  v_request      public.payment_requests;
begin
  if v_requester_id is null then
    raise exception 'UNAUTHENTICATED';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'INVALID_AMOUNT';
  end if;
  if v_currency !~ '^[A-Z0-9]{3,10}$' then
    raise exception 'INVALID_CURRENCY';
  end if;

  select id into v_payer_id
    from public.profiles
   where user_id = upper(trim(p_payer_user_id));

  if v_payer_id is null then
    raise exception 'RECIPIENT_NOT_FOUND';
  end if;
  if v_payer_id = v_requester_id then
    raise exception 'SELF_REQUEST';
  end if;

  insert into public.payment_requests (request_code, requester_id, payer_id, currency, amount, memo)
  values (public.generate_request_code(), v_requester_id, v_payer_id, v_currency, p_amount, p_memo)
  returning * into v_request;

  return public.payment_request_json(v_request, v_requester_id);
end;
$$;

-- 請求コードから内容を取得する（当事者以外には存在自体を知らせない）
create or replace function public.find_payment_request(p_code text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer  uuid := auth.uid();
  v_request public.payment_requests;
begin
  if v_viewer is null then
    raise exception 'UNAUTHENTICATED';
  end if;

  select * into v_request
    from public.payment_requests
   where request_code = upper(trim(p_code));

  if v_request.id is null or (v_viewer <> v_request.payer_id and v_viewer <> v_request.requester_id) then
    raise exception 'REQUEST_NOT_FOUND';
  end if;

  return public.payment_request_json(v_request, v_viewer);
end;
$$;

-- 請求コードを入力して支払う（請求された本人のみ）
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
     set status = 'paid', paid_at = now(), transfer_id = v_transfer.id
   where id = v_request.id
  returning * into v_request;

  return public.payment_request_json(v_request, v_payer);
end;
$$;

-- 請求を取り消す（請求した本人のみ・未払いのもののみ）
create or replace function public.cancel_payment_request(p_code text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_requester uuid := auth.uid();
  v_request   public.payment_requests;
begin
  if v_requester is null then
    raise exception 'UNAUTHENTICATED';
  end if;

  select * into v_request
    from public.payment_requests
   where request_code = upper(trim(p_code))
     for update;

  if v_request.id is null or v_request.requester_id <> v_requester then
    raise exception 'REQUEST_NOT_FOUND';
  end if;
  if v_request.status = 'paid' then
    raise exception 'REQUEST_ALREADY_PAID';
  end if;

  update public.payment_requests
     set status = 'cancelled', cancelled_at = now()
   where id = v_request.id
  returning * into v_request;

  return public.payment_request_json(v_request, v_requester);
end;
$$;

-- 自分に関係する請求（した／された）を新しい順に返す
create or replace function public.list_my_payment_requests(p_limit int default 50)
returns json
language sql
security definer
set search_path = public
as $$
  -- payment_request_json はテーブルの行型を受け取るため、
  -- 対象を id で絞り込んだうえでテーブル別名(pr)のまま渡す
  select coalesce(
           json_agg(public.payment_request_json(pr, auth.uid()) order by pr.created_at desc),
           '[]'::json
         )
    from public.payment_requests pr
   where pr.id in (
           select id
             from public.payment_requests
            where requester_id = auth.uid() or payer_id = auth.uid()
            order by created_at desc
            limit least(coalesce(p_limit, 50), 200)
         );
$$;

-- ---------------------------------------------------------------------------
-- 権限の整理（未ログイン(anon)からは業務関数を呼べないようにする）
-- ---------------------------------------------------------------------------

revoke execute on function public.generate_request_code()                                from anon, authenticated;
revoke execute on function public.payment_request_json(public.payment_requests, uuid)    from anon, authenticated;
revoke execute on function public.create_payment_request(text, text, numeric, text)      from anon;
revoke execute on function public.find_payment_request(text)                             from anon;
revoke execute on function public.pay_payment_request(text)                              from anon;
revoke execute on function public.cancel_payment_request(text)                           from anon;
revoke execute on function public.list_my_payment_requests(int)                          from anon;
