import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/split_bill_link_flow_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!AppConfig.isConfigured) {
    runApp(const ConfigErrorApp());
    return;
  }

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    // レガシー anon キー / 新方式 publishable キーのどちらでも動く
    publishableKey: AppConfig.supabaseAnonKey,
  );
  runApp(const MegaPayApp());
}

class MegaPayApp extends StatelessWidget {
  const MegaPayApp({super.key});

  @override
  Widget build(BuildContext context) {
    final splitCode = Uri.base.queryParameters['split_code']?.trim();
    final rankedSplitCode =
        Uri.base.queryParameters['ranked_split_code']?.trim();
    return MaterialApp(
      title: 'MegaPay',
      debugShowCheckedModeBanner: false,
      // 配色・角丸・余白・意味色などのデザインは theme.dart に一元化する。
      theme: buildMegaPayTheme(),
      home: rankedSplitCode != null && rankedSplitCode.isNotEmpty
          ? SplitBillLinkFlowScreen(
              billCode: rankedSplitCode,
              ranked: true,
            )
          : splitCode != null && splitCode.isNotEmpty
              ? SplitBillLinkFlowScreen(billCode: splitCode)
              : const AuthGate(),
    );
  }
}

/// ログイン状態に応じてログイン画面とホーム画面を切り替える。
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) {
          return const HomeScreen();
        }
        return const LoginScreen();
      },
    );
  }
}

/// --dart-define の設定が無いまま起動したときに手順を案内する画面。
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'MegaPay - 設定エラー',
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.settings_suggest, size: 48),
                SizedBox(height: 16),
                Text(
                  'Supabase の接続設定がありません。\n'
                  '--dart-define=SUPABASE_URL=... と\n'
                  '--dart-define=SUPABASE_ANON_KEY=... を付けて起動してください。\n'
                  '（詳細はリポジトリの README を参照）',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
