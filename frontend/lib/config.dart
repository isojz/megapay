/// アプリの接続設定。
///
/// デフォルト値はチーム共有の開発用 Supabase プロジェクトを指しており、
/// 何も指定せず `flutter run -d chrome` するだけで動く。
/// anon キーは RLS 前提で公開可能なキーのため、リポジトリに含めている
/// （service_role 等の秘密キーは一切含めない）。
///
/// 本番や別プロジェクトに向ける場合は `--dart-define` で上書きする（render.yaml 参照）:
/// ```
/// flutter run -d chrome \
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
/// ```
class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://xjiwxiyzuujyaitheuwg.supabase.co',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhqaXd4aXl6dXVqeWFpdGhldXdnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU4MTM4NjUsImV4cCI6MjEwMTM4OTg2NX0.LqDs6sKOLEsKNTbSGpcbre8NhKicK1_Xy3MRnGfmomM',
  );
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
