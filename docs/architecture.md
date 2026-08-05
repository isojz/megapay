# 設計資料（MVP）

## システム構成

```mermaid
graph TB
    subgraph クライアント
        F[Flutter Web アプリ<br>スマホ最適化 UI]
    end
    subgraph バックエンド
        API[FastAPI<br>REST API]
    end
    subgraph Supabase
        AUTH[Supabase Auth<br>メール+パスワード]
        DB[(PostgreSQL<br>RLS 有効)]
    end

    F -->|サインアップ / ログイン| AUTH
    AUTH -->|アクセストークン JWT| F
    F -->|"API 呼び出し（Bearer JWT）"| API
    API -->|JWT を HS256 で検証| API
    API -->|ユーザーの JWT を転送| DB
```

### 設計上のポイント

1. **バックエンドは service_role キーを持たない**
   FastAPI はユーザーの JWT をそのまま PostgREST へ転送する。RLS が「本人」として効くため、
   バックエンドにバグや侵入があっても他ユーザーのデータには到達できない。
2. **送金は DB 関数で原子的に実行**
   `execute_transfer`（SECURITY DEFINER）が残高チェック → 減算 → 加算 → 履歴記録を
   1 トランザクションで行う。行ロックは常に `profile_id` 順で取得し、相互送金の同時実行でも
   デッドロックしない。
3. **金額に浮動小数点を使わない**
   DB: `numeric(30,8)` / API: 文字列 ⇔ Python `Decimal`。通貨は限定せず
   `^[A-Z0-9]{3,10}$` の任意コードを受け付ける（同一通貨間の送金のみ。為替変換はバックログ）。
4. **書き込み経路の一本化**
   テーブルへの insert/update ポリシーは定義していないため、クライアント・バックエンドとも
   直接書き込みできず、必ず検証つきの DB 関数を経由する。

## ER 図

```mermaid
erDiagram
    auth_users ||--|| profiles : "1:1（トリガーで自動作成）"
    profiles ||--o{ balances : "通貨ごとに1行"
    profiles ||--o{ transfers : "送金/受取"
    profiles ||--o{ payment_requests : "請求した/された"
    transfers ||--o| payment_requests : "支払い成立時に紐づく"
    profiles ||--o{ split_bills : "集金する"
    split_bills ||--o{ split_bill_participants : "参加者"
    payment_requests ||--|| split_bill_participants : "参加時に発行される請求"

    profiles {
        uuid id PK "auth.users.id"
        text user_id UK "公開ID MP-XXXXXXXX"
        text display_name
        timestamptz created_at
    }
    balances {
        bigint id PK
        uuid profile_id FK
        text currency "ISO 4217 等の任意コード"
        numeric amount "30,8 / 0以上"
        timestamptz updated_at
    }
    transfers {
        uuid id PK
        uuid sender_id FK
        uuid recipient_id FK
        text currency
        numeric amount "0より大"
        text memo
        timestamptz created_at
    }
    payment_requests {
        uuid id PK
        text request_code UK "支払い用コード RQ-XXXXXXXX"
        uuid requester_id FK "請求した人（受け取る側）"
        uuid payer_id FK "請求された人（支払う側）"
        text currency
        numeric amount "0より大"
        text memo
        text status "pending/paid/cancelled"
        uuid transfer_id FK "成立した送金"
        timestamptz created_at
        timestamptz paid_at
        timestamptz cancelled_at
    }
    split_bills {
        uuid id PK
        text bill_code UK "参加用コード SP-XXXXXXXX"
        uuid organizer_id FK "集金者"
        text title "イベント名"
        text currency
        numeric total_amount "合計金額"
        int participant_count "集金者を含む人数"
        numeric share_amount "1人あたり（端数切り上げ）"
        timestamptz created_at
    }
    split_bill_participants {
        uuid id PK
        uuid split_bill_id FK
        uuid participant_id FK "支払い者"
        uuid payment_request_id FK "参加時に発行された請求"
        timestamptz joined_at
    }
```

## 送金シーケンス

```mermaid
sequenceDiagram
    participant U as ユーザー（太郎）
    participant F as Flutter Web
    participant A as FastAPI
    participant D as Supabase PostgreSQL

    U->>F: 宛先ID・通貨・金額を入力
    F->>A: GET /api/v1/recipients/MP-XXXX（Bearer JWT）
    A->>D: rpc find_recipient
    D-->>A: {user_id, display_name}
    A-->>F: 宛先の表示名
    U->>F: 内容を確認して「送金する」
    F->>A: POST /api/v1/transfers
    A->>A: JWT 検証・入力バリデーション（Decimal）
    A->>D: rpc execute_transfer（JWT 転送）
    Note over D: 1トランザクション<br>行ロック（profile_id順）→ 残高チェック<br>→ 減算 → 加算 → 履歴 insert
    D-->>A: 送金結果 JSON
    A-->>F: 201 Created
    F-->>U: 完了ダイアログ → 残高・履歴を再取得
```

## 請求シーケンス

```mermaid
sequenceDiagram
    participant R as 請求する人（太郎）
    participant P as 請求される人（花子）
    participant A as FastAPI
    participant D as Supabase PostgreSQL

    R->>A: POST /payment-requests（相手ID・通貨・金額）
    A->>D: rpc create_payment_request
    D-->>A: 請求コード RQ-XXXXXXXX
    A-->>R: 201 Created（コードを画面に表示）
    R-->>P: コードを口頭 / チャットなどで伝える

    P->>A: GET /payment-requests/RQ-XXXXXXXX
    A->>D: rpc find_payment_request
    Note over D: 当事者以外には<br/>存在自体を知らせない
    D-->>A: 請求内容
    A-->>P: 金額・請求元を表示

    P->>A: POST /payment-requests/RQ-XXXXXXXX/pay
    A->>D: rpc pay_payment_request
    Note over D: 1トランザクション<br/>請求を行ロック（二重支払い防止）<br/>→ internal_move_funds で資金移動<br/>→ status=paid・transfer_id 記録
    D-->>A: 支払い済みの請求
    A-->>P: 200 OK（完了ダイアログ）
```

送金（`execute_transfer`）と請求の支払い（`pay_payment_request`）は、
どちらも共通の `internal_move_funds` を呼ぶ。資金移動のロジックが 1 箇所にまとまるため、
残高チェック・ロック順序・履歴記録の扱いが両者でずれない。

## 割り勘シーケンス

```mermaid
sequenceDiagram
    participant O as 集金者（太郎）
    participant P as 支払い者（花子）
    participant A as FastAPI
    participant D as Supabase PostgreSQL

    O->>A: POST /split-bills（イベント名・人数・合計金額）
    A->>D: rpc create_split_bill
    Note over D: 1人あたり = 合計 ÷ 人数（端数は切り上げ）
    D-->>A: 請求コード SP-XXXXXXXX
    A-->>O: 201 Created
    O-->>P: 請求コードを伝える

    P->>A: POST /split-bills/SP-XXXXXXXX/join
    A->>D: rpc join_split_bill
    Note over D: 1トランザクション<br/>割り勘を行ロック（定員超過を防ぐ）<br/>→ 参加者を登録<br/>→ 集金者→参加者の請求を自動発行
    D-->>A: 参加後の状態（自分あての請求コード RQ-XXXXXXXX）
    A-->>P: 200 OK

    P->>A: POST /payment-requests/RQ-XXXXXXXX/pay
    Note over A,D: 支払いは既存の請求機能をそのまま利用
    A-->>P: 200 OK（送金が実行される）

    O->>A: GET /split-bills/SP-XXXXXXXX/participants
    A-->>O: 誰が支払い済みか / 未払いかの一覧
```

割り勘は「1つのイベントに対して、参加者ごとに 1 件の請求を作る」構造にしている。
支払い・残高の移動は既存の請求機能（`pay_payment_request` → `internal_move_funds`）を
そのまま通るため、資金移動のロジックは 1 箇所のままになっている。

## API 仕様（v1）

すべて `Authorization: Bearer <Supabase アクセストークン>` が必要（`/health` を除く）。
金額はリクエスト・レスポンスとも**文字列**。

| メソッド | パス | 説明 | 主なエラー |
| --- | --- | --- | --- |
| GET | `/health` | 死活監視 | - |
| GET | `/api/v1/me` | 自分のプロフィール（`user_id`, `display_name`, `email`） | 401 |
| GET | `/api/v1/balances` | 通貨別残高一覧 | 401 |
| GET | `/api/v1/recipients/{user_id}` | 宛先確認（表示名の取得） | 404 宛先なし |
| POST | `/api/v1/transfers` | 送金実行 `{recipient_user_id, currency, amount, memo?}` | 400 残高不足・自分宛て / 404 宛先なし / 422 入力不正 |
| GET | `/api/v1/transfers?limit=50` | 送金・受取履歴（新しい順） | 401 |
| POST | `/api/v1/payment-requests` | 請求作成 `{payer_user_id, currency, amount, memo?}` → 請求コード発行 | 400 自分宛て / 404 相手なし / 422 入力不正 |
| GET | `/api/v1/payment-requests?limit=50` | 請求状況の一覧（した／された） | 401 |
| GET | `/api/v1/payment-requests/{code}` | 請求コードから内容取得（支払い前の確認） | 404 コードなし・当事者以外 |
| POST | `/api/v1/payment-requests/{code}/pay` | 請求コードを指定して支払う | 400 残高不足 / 404 コードなし / 409 支払い済み・取り消し済み |
| POST | `/api/v1/payment-requests/{code}/cancel` | 請求を取り消す（請求者・未払いのみ） | 404 コードなし / 409 支払い済み |
| POST | `/api/v1/split-bills` | 割り勘を登録 `{title, currency, total_amount, participant_count}` → 請求コード発行 | 400 入力不正 / 422 入力不正 |
| GET | `/api/v1/split-bills?limit=50` | 自分が関わる割り勘の一覧 | 401 |
| GET | `/api/v1/split-bills/{code}` | 請求コードから割り勘の内容を取得（参加前の確認） | 404 コードなし |
| POST | `/api/v1/split-bills/{code}/join` | グループに参加（同時に自分あての請求が発行される） | 400 集金者本人 / 404 コードなし / 409 定員超過 |
| GET | `/api/v1/split-bills/{code}/participants` | 参加者と支払い状況の一覧 | 404 コードなし・部外者 |
| GET | `/api/v1/saved-users` | 保存済みユーザー一覧 | 401 |
| POST | `/api/v1/saved-users` | ユーザーを保存 `{user_id}` | 400 自分自身 / 404 宛先なし / 422 入力不正 |

エラーレスポンスは `{"detail": "<日本語メッセージ>"}` 形式。
DB 関数の `INSUFFICIENT_FUNDS` 等のエラーキーワードは `backend/app/errors.py` で HTTP ステータスへ変換する。

## セキュリティ（MVP での対応と積み残し）

| 項目 | MVP | 今後 |
| --- | --- | --- |
| 認証 | Supabase Auth（JWT を JWKS 公開鍵で検証。ES256/RS256/HS256 対応） | 2FA・生体認証 |
| 認可 | RLS + SECURITY DEFINER 関数のみ書き込み可 | 監査ログ・異常検知 |
| 金額精度 | numeric / Decimal / 文字列受け渡し | - |
| 通信 | 本番 HTTPS 前提・CORS 制限 | レートリミット・WAF |
| 送金制御 | 残高チェック・自分宛て禁止 | 限度額・冪等キー・不正検知・KYC |
