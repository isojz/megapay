# チーム開発ルール

アジャイル（スクラム想定）で開発するための最小限のルールです。チームで合意のうえ随時更新してください。

## ブランチ戦略（GitHub Flow）

- `main` は常にデプロイ可能な状態を保つ（直接 push 禁止・PR 必須）
- 作業は `main` から分岐したトピックブランチで行う
  - 命名: `feat/transfer-qr` `fix/balance-rounding` `docs/setup-guide` など
- PR は **1 人以上のレビュー承認 + CI グリーン** でマージする（squash merge 推奨）

## コミットメッセージ（Conventional Commits）

```
<type>: <要約（日本語可）>

例:
feat: QRコードで送金先を指定できるようにする
fix: JPY残高の小数表示を修正する
```

type: `feat` / `fix` / `docs` / `refactor` / `test` / `chore`

## タスク管理

- バックログは [docs/backlog.md](docs/backlog.md) と GitHub Issues で管理する
- 着手時に Issue を自分にアサインし、PR に `Closes #<番号>` を書く

## コーディング規約

- **Python**: 型ヒント必須。フォーマットは今後 `ruff format` を導入予定
- **Dart**: `flutter analyze` の警告ゼロを維持する（CI でチェック）
- 金額を `float` / `double` で計算しない（API・DB 上は文字列 / numeric、表示時のみ数値化）
- シークレット（`.env`、Supabase キー）は絶対にコミットしない

## テスト

- バックエンドの新規エンドポイントには必ずテストを追加する（`backend/tests/`）
- 送金まわりの変更は README のデモシナリオを手動確認してから PR を出す
