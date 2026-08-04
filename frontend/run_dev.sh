#!/usr/bin/env bash
# backend/.env の Supabase 接続情報を流用して Flutter Web を開発モードで起動する（macOS / Linux 用）
# 使い方: frontend ディレクトリで ./run_dev.sh
# （Windows の場合は run_dev.ps1 を使うこと）

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
env_file="$script_dir/../backend/.env"

if [[ ! -f "$env_file" ]]; then
  echo "backend/.env が見つかりません。README のセットアップ（バックエンド）を先に行ってください。" >&2
  exit 1
fi

# .env から値を取り出す（CRLF 改行にも対応）
get_var() {
  grep -E "^[[:space:]]*$1=" "$env_file" | head -n1 | cut -d= -f2- | tr -d '\r'
}

SUPABASE_URL="$(get_var SUPABASE_URL)"
SUPABASE_ANON_KEY="$(get_var SUPABASE_ANON_KEY)"

flutter run -d chrome --web-port 3000 \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=API_BASE_URL=http://localhost:8000
