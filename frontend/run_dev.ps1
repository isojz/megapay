# backend/.env の Supabase 接続情報を流用して Flutter Web を開発モードで起動する
# 使い方: frontend ディレクトリで .\run_dev.ps1

$envFile = Join-Path $PSScriptRoot "..\backend\.env"
if (-not (Test-Path $envFile)) {
    Write-Error "backend/.env が見つかりません。README のセットアップ（バックエンド）を先に行ってください。"
    exit 1
}

$config = @{}
foreach ($line in Get-Content $envFile) {
    if ($line -match '^\s*([^#][^=]*)=(.*)$') {
        $config[$Matches[1].Trim()] = $Matches[2].Trim()
    }
}

flutter run -d chrome --web-port 3000 `
    "--dart-define=SUPABASE_URL=$($config['SUPABASE_URL'])" `
    "--dart-define=SUPABASE_ANON_KEY=$($config['SUPABASE_ANON_KEY'])" `
    "--dart-define=API_BASE_URL=http://localhost:8000"
