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
    final colorScheme = ColorScheme.fromSeed(seedColor: megaPayBrandColor);
    return MaterialApp(
      title: 'MegaPay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        // 同梱の日本語フォントを既定にする（pubspec.yaml の fonts 参照）。
        // 指定しないと CanvasKit が gstatic からの遅延取得に頼り、
        // 取得が終わるまで日本語が豆腐（□）になる。
        fontFamily: 'NotoSansJP',
        // カードを白のまま浮かせたいので、背景はグレーにする
        scaffoldBackgroundColor: megaPayBackgroundColor,
        // ヘッダーはイメージカラー。上に載る文字とアイコンは白で統一する
        appBarTheme: const AppBarTheme(
          backgroundColor: megaPayBrandColor,
          foregroundColor: megaPayOnBrandColor,
          elevation: 0,
        ),
        // タブは赤地に白だと選択中と未選択の区別が付きにくい。
        // カードと同じ明るい面に載せ、文字色で選択状態を示す。
        tabBarTheme: TabBarThemeData(
          labelColor: megaPayBrandColor,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
          indicatorColor: megaPayBrandColor,
          dividerColor: Colors.transparent,
        ),
        // 入力例（hintText）は既定色だと入力済みの文字と紛らわしいため薄くする。
        // 画面ごとに指定すると濃さがばらつくので、ここで一元管理する。
        inputDecorationTheme: InputDecorationTheme(
          hintStyle: TextStyle(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
      home: splitCode != null && splitCode.isNotEmpty
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
