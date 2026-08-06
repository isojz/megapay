import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import '../utils/input_formatters.dart';

/// ログイン / アカウント開設（サインアップ）画面。
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.onAuthenticated});

  /// ディープリンクなど、認証後に元のフローへ戻す場合に使用する。
  final VoidCallback? onAuthenticated;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _savedEmailKey = 'saved_login_email';

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  bool _isSignUp = false;
  bool _isLoading = false;
  bool _rememberLogin = true;

  /// パスワードは既定で伏せ、目のボタンで表示を切り替える。
  bool _passwordVisible = false;

  @override
  void initState() {
    super.initState();
    _restoreLoginInfo();
  }

  Future<void> _restoreLoginInfo() async {
    final preferences = await SharedPreferences.getInstance();
    final savedEmail = preferences.getString(_savedEmailKey);
    if (!mounted || savedEmail == null) return;
    setState(() {
      _emailController.text = savedEmail;
      _rememberLogin = true;
    });
  }

  Future<void> _saveLoginInfo(String email) async {
    final preferences = await SharedPreferences.getInstance();
    if (_rememberLogin) {
      await preferences.setString(_savedEmailKey, email);
    } else {
      await preferences.remove(_savedEmailKey);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);

    final auth = Supabase.instance.client.auth;
    final email = _emailController.text.trim();
    try {
      if (_isSignUp) {
        await auth.signUp(
          email: email,
          password: _passwordController.text,
          data: {'display_name': _displayNameController.text.trim()},
        );
      } else {
        await auth.signInWithPassword(
          email: email,
          password: _passwordController.text,
        );
      }
      await _saveLoginInfo(email);
      if (auth.currentSession != null) {
        widget.onAuthenticated?.call();
      } else if (_isSignUp) {
        // 登録は成功しているので、エラー（赤帯）ではなく通常の通知で知らせる
        _showMessage('確認メールを送信しました。確認後にログインしてください。');
      }
      // 成功時は AuthGate が自動的にホーム画面へ切り替える
    } on AuthException catch (err) {
      _showError(err.message);
    } catch (_) {
      _showError('通信に失敗しました。時間をおいて再度お試しください。');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  /// 成功・案内など、エラーではない通知を出す。
  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 背景がグレーなので、白いアイコンはブランドカラーの円に載せる
                  const CircleAvatar(
                    radius: 40,
                    backgroundColor: megaPayBrandColor,
                    child: Icon(
                      Icons.currency_exchange,
                      size: 44,
                      color: megaPayOnBrandColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'MegaPay',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'いつでもどこでも手軽に割り勘',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 32),
                  if (_isSignUp) ...[
                    TextFormField(
                      controller: _displayNameController,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      decoration: const InputDecoration(
                        labelText: 'お名前（表示名）',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                              ? 'お名前を入力してください'
                              : null,
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    inputFormatters: emailInputFormatters,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [
                      AutofillHints.username,
                      AutofillHints.email,
                    ],
                    decoration: const InputDecoration(
                      labelText: 'メールアドレス',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        (value == null || !value.contains('@'))
                            ? 'メールアドレスを入力してください'
                            : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: !_passwordVisible,
                    textInputAction: TextInputAction.done,
                    autofillHints: [
                      _isSignUp
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    decoration: InputDecoration(
                      labelText: 'パスワード（6文字以上）',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: _passwordVisible ? 'パスワードを隠す' : 'パスワードを表示',
                        icon: Icon(
                          _passwordVisible
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () => setState(
                          () => _passwordVisible = !_passwordVisible,
                        ),
                      ),
                    ),
                    validator: (value) => (value == null || value.length < 6)
                        ? 'パスワードは6文字以上で入力してください'
                        : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (!_isSignUp) ...[
                    const SizedBox(height: 4),
                    CheckboxListTile(
                      value: _rememberLogin,
                      onChanged: _isLoading
                          ? null
                          : (value) => setState(
                                () => _rememberLogin = value ?? false,
                              ),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('ログイン情報を保存する'),
                      subtitle: const Text('次回、メールアドレスを自動入力します'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _isLoading ? null : _submit,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_isSignUp ? 'アカウント開設（無料）' : 'ログイン'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () => setState(() => _isSignUp = !_isSignUp),
                    child:
                        Text(_isSignUp ? 'アカウントをお持ちの方はログイン' : '初めての方はアカウント開設'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
