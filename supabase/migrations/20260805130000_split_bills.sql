-- ============================================================================
-- 割り勘（split bills）機能
--
-- 流れ:
--   1. 集金者が「イベント名・参加人数・合計金額」を登録すると請求コード（SP-XXXXXXXX）が 1 つ発行される
--   2. 支払い者がそのコードを入力するとグループに参加し、
--      同時に「集金者 → 支払い者」の請求（割り勘後の金額）が自動で作成される
--   3. 支払いは既存の請求機能（pay_payment_request）でそのまま行える
--   4. 集金者・参加者はグループ画面で全員の支払い状況を確認できる
--
-- 用語:
--   participant_count は集金者を含む総人数。集金者は自分の分を立て替えている扱いのため、
--   グループに参加できる（＝請求を受ける）のは participant_count - 1 人まで。
-- ============================================================================

-- ---------------------------------------------------------------------------
-- テーブル
-- ---------------------------------------------------------------------------

-- 割り勘イベント
create table public.split_bills (
  id                uuid primary key default gen_random_uuid(),
  bill_code         text not null unique,        -- 参加用の請求コード（SP-XXXXXXXX）
  organizer_id      uuid not null references public.profiles (id),  -- 集金者
  title             text not null check (length(trim(title)) > 0),
  currency          text not null check (currency ~ '^[A-Z0-9]{3,10}$'),
  total_amount      numeric(30, 8) not null check (total_amount > 0),
  participant_count int not null check (participant_count between 2 and 100),
  share_amount      numeric(30, 8) not null check (share_amount > 0),  -- 1人あたり（端数は切り上げ）
  created_at        timestamptz not null default now()
);

-- 参加者（1人につき 1 件の請求が紐づく）
create table public.split_bill_participants (
  id                 uuid primary key default gen_random_uuid(),
  split_bill_id      uuid not null references public.split_bills (id) on delete cascade,
  participant_id     uuid not null references public.profiles (id),
  payment_request_id uuid not null references public.payment_requests (id),
  joined_at          timestamptz not null default now(),
  unique (split_bill_id, participant_id)
);

create index split_bills_organizer_idx      on public.split_bills (organizer_id, created_at desc);
create index split_bill_participants_pid_idx on public.split_bill_participants (participant_id);

-- ---------------------------------------------------------------------------
-- RLS（参照は当事者のみ。書き込みは下の SECURITY DEFINER 関数経由に限定）
-- ---------------------------------------------------------------------------

alter table public.split_bills             enable row level security;
alter table public.split_bill_participants enable row level security;

-- 参照系は下の SECURITY DEFINER 関数を通すため、ポリシーは自分の行だけに限定する。
-- （2つのテーブルのポリシーが互いを参照すると RLS が無限再帰になるため、単純な条件にしている）
create policy "split_bills_select_own" on public.split_bills
  for select using (auth.uid() = organizer_id);

create policy "split_bill_participants_select_own" on public.split_bill_participants
  for select using (auth.uid() = participant_id);

-- ---------------------------------------------------------------------------
-- 関数
-- ---------------------------------------------------------------------------

-- 参加用コードを重複しないように生成する（請求コードと同じく紛らわしい文字を除く）
create or replace function public.generate_split_bill_code()
returns text
language plpgsql
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code     text;
begin
  loop
    v_code := 'SP-';
    for i in 1..8 loop
      v_code := v_code || substr(v_alphabet, floor(random() * length(v_alphabet))::int + 1, 1);
    end loop;
    exit when not exists (select 1 from public.split_bills where bill_code = v_code);
  end loop;
  return v_code;
end;
$$;

-- 割り勘 1 件を API 向けの JSON に整形する（閲覧者から見た状態を含む）
create or replace function public.split_bill_json(
  p_bill   public.split_bills,
  p_viewer uuid
)
returns json
language sql
stable
security definer
set search_path = public
as $$
  select json_build_object(
    'bill_code',         p_bill.bill_code,
    'title',             p_bill.title,
    'currency',          p_bill.currency,
    'total_amount',      p_bill.total_amount::text,
    'participant_count', p_bill.participant_count,
    'share_amount',      p_bill.share_amount::text,
    'organizer_user_id', org.user_id,
    'organizer_name',    org.display_name,
    'is_organizer',      (p_bill.organizer_id = p_viewer),
    'joined',            (mine.id is not null),
    'my_request_code',   mine_req.request_code,
    'my_status',         mine_req.status,
    'joined_count',      stats.joined_count,
    'paid_count',        stats.paid_count,
    'collected_amount',  stats.collected_amount::text,
    'created_at',        p_bill.created_at
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
  left join public.split_bill_participants mine
    on mine.split_bill_id = p_bill.id and mine.participant_id = p_viewer
  left join public.payment_requests mine_req
    on mine_req.id = mine.payment_request_id
  where org.id = p_bill.organizer_id;
$$;

-- 割り勘を作成する（集金者。支払い登録画面から呼ばれる）
create or replace function public.create_split_bill(
  p_title             text,
  p_currency          text,
  p_total_amount      numeric,
  p_participant_count int
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_organizer uuid := auth.uid();
  v_currency  text := upper(trim(p_currency));
  v_factor    numeric;
  v_share     numeric;
  v_bill      public.split_bills;
begin
  if v_organizer is null then
    raise exception 'UNAUTHENTICATED';
  end if;
  if p_title is null or length(trim(p_title)) = 0 then
    raise exception 'INVALID_TITLE';
  end if;
  if p_total_amount is null or p_total_amount <= 0 then
    raise exception 'INVALID_AMOUNT';
  end if;
  if v_currency !~ '^[A-Z0-9]{3,10}$' then
    raise exception 'INVALID_CURRENCY';
  end if;
  if p_participant_count is null or p_participant_count < 2 or p_participant_count > 100 then
    raise exception 'INVALID_PARTICIPANT_COUNT';
  end if;

  -- 1人あたりの金額。端数は切り上げる（JPY は 1 単位、それ以外は小数第2位まで）
  v_factor := power(10::numeric, case when v_currency = 'JPY' then 0 else 2 end);
  v_share  := ceil(p_total_amount / p_participant_count * v_factor) / v_factor;

  insert into public.split_bills
    (bill_code, organizer_id, title, currency, total_amount, participant_count, share_amount)
  values
    (public.generate_split_bill_code(), v_organizer, trim(p_title), v_currency,
     p_total_amount, p_participant_count, v_share)
  returning * into v_bill;

  return public.split_bill_json(v_bill, v_organizer);
end;
$$;

-- 請求コードから割り勘の内容を取得する（参加前のプレビューにも使うため、認証済みなら誰でも可）
create or replace function public.find_split_bill(p_code text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer uuid := auth.uid();
  v_bill   public.split_bills;
begin
  if v_viewer is null then
    raise exception 'UNAUTHENTICATED';
  end if;

  select * into v_bill
    from public.split_bills
   where bill_code = upper(trim(p_code));

  if v_bill.id is null then
    raise exception 'SPLIT_BILL_NOT_FOUND';
  end if;

  return public.split_bill_json(v_bill, v_viewer);
end;
$$;

-- 請求コードでグループに参加する。
-- 同時に「集金者 → 参加者」の請求（割り勘後の金額）を作成する。
-- 参加済みの場合は何もせず現在の状態を返す（何度押しても二重請求されない）。
create or replace function public.join_split_bill(p_code text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_participant uuid := auth.uid();
  v_bill        public.split_bills;
  v_joined      int;
  v_request     public.payment_requests;
begin
  if v_participant is null then
    raise exception 'UNAUTHENTICATED';
  end if;

  -- 同時参加で定員を超えないよう、割り勘の行をロックする
  select * into v_bill
    from public.split_bills
   where bill_code = upper(trim(p_code))
     for update;

  if v_bill.id is null then
    raise exception 'SPLIT_BILL_NOT_FOUND';
  end if;
  if v_bill.organizer_id = v_participant then
    raise exception 'ORGANIZER_CANNOT_JOIN';
  end if;

  -- 参加済みならそのまま現在の状態を返す（冪等）
  if exists (
    select 1 from public.split_bill_participants
     where split_bill_id = v_bill.id and participant_id = v_participant
  ) then
    return public.split_bill_json(v_bill, v_participant);
  end if;

  select count(*) into v_joined
    from public.split_bill_participants
   where split_bill_id = v_bill.id;

  -- 集金者は自分の分を立て替えているため、参加できるのは participant_count - 1 人まで
  if v_joined >= v_bill.participant_count - 1 then
    raise exception 'SPLIT_BILL_FULL';
  end if;

  insert into public.payment_requests
    (request_code, requester_id, payer_id, currency, amount, memo)
  values
    (public.generate_request_code(), v_bill.organizer_id, v_participant,
     v_bill.currency, v_bill.share_amount, v_bill.title)
  returning * into v_request;

  insert into public.split_bill_participants
    (split_bill_id, participant_id, payment_request_id)
  values
    (v_bill.id, v_participant, v_request.id);

  return public.split_bill_json(v_bill, v_participant);
end;
$$;

-- グループの参加者と支払い状況の一覧（集金者・参加者のみ閲覧できる）
create or replace function public.list_split_bill_participants(p_code text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer uuid := auth.uid();
  v_bill   public.split_bills;
  v_result json;
begin
  if v_viewer is null then
    raise exception 'UNAUTHENTICATED';
  end if;

  select * into v_bill
    from public.split_bills
   where bill_code = upper(trim(p_code));

  if v_bill.id is null then
    raise exception 'SPLIT_BILL_NOT_FOUND';
  end if;

  if v_bill.organizer_id <> v_viewer and not exists (
    select 1 from public.split_bill_participants
     where split_bill_id = v_bill.id and participant_id = v_viewer
  ) then
    raise exception 'SPLIT_BILL_NOT_FOUND';  -- 部外者には存在自体を知らせない
  end if;

  select coalesce(json_agg(row_to_json(x) order by x.joined_at), '[]'::json)
    into v_result
  from (
    select p.user_id,
           p.display_name,
           pr.request_code,
           pr.amount::text as amount,
           pr.status,
           pr.paid_at,
           (sbp.participant_id = v_viewer) as is_me,
           sbp.joined_at
      from public.split_bill_participants sbp
      join public.profiles p           on p.id = sbp.participant_id
      join public.payment_requests pr  on pr.id = sbp.payment_request_id
     where sbp.split_bill_id = v_bill.id
  ) x;

  return v_result;
end;
$$;

-- 自分が関わる割り勘の一覧（集金した分・参加した分）を新しい順に返す
create or replace function public.list_my_split_bills(p_limit int default 50)
returns json
language sql
security definer
set search_path = public
as $$
  -- split_bill_json はテーブルの行型を受け取るため、対象を id で絞ってから
  -- テーブル別名(sb)のまま渡す。件数の絞り込みは集約前に済ませる。
  select coalesce(
           json_agg(public.split_bill_json(sb, auth.uid()) order by sb.created_at desc),
           '[]'::json
         )
    from public.split_bills sb
   where sb.id in (
           select t.id
             from (
               select sb2.id, sb2.created_at
                 from public.split_bills sb2
                where sb2.organizer_id = auth.uid()
                   or exists (
                        select 1
                          from public.split_bill_participants sbp
                         where sbp.split_bill_id = sb2.id
                           and sbp.participant_id = auth.uid()
                      )
                order by sb2.created_at desc
                limit least(coalesce(p_limit, 50), 200)
             ) t
         );
$$;

-- ---------------------------------------------------------------------------
-- 権限の整理（未ログイン(anon)からは業務関数を呼べないようにする）
-- ---------------------------------------------------------------------------

revoke execute on function public.generate_split_bill_code()                      from anon, authenticated;
revoke execute on function public.split_bill_json(public.split_bills, uuid)       from anon, authenticated;
revoke execute on function public.create_split_bill(text, text, numeric, int)     from anon;
revoke execute on function public.find_split_bill(text)                           from anon;
revoke execute on function public.join_split_bill(text)                           from anon;
revoke execute on function public.list_split_bill_participants(text)              from anon;
revoke execute on function public.list_my_split_bills(int)                        from anon;
