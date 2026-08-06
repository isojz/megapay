import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/split_bill.dart';
import '../services/api_client.dart';
import '../utils/browser_url.dart';
import '../utils/money.dart';
import '../widgets/payment_method_selector.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'split_bill_payment_mock_screen.dart';

/// 共有リンクから「内容確認 → 認証 → 参加・支払い」を行う画面。
class SplitBillLinkFlowScreen extends StatefulWidget {
  const SplitBillLinkFlowScreen({super.key, required this.billCode});

  final String billCode;

  @override
  State<SplitBillLinkFlowScreen> createState() =>
      _SplitBillLinkFlowScreenState();
}

class _SplitBillLinkFlowScreenState extends State<SplitBillLinkFlowScreen> {
  late Future<PublicSplitBill> _future;
  PaymentMethod _paymentMethod = PaymentMethod.balance;
  bool _isContinuing = false;

  @override
  void initState() {
    super.initState();
    _future = ApiClient.instance.lookupPublicSplitBill(widget.billCode);
  }

  void _showError(Object error) {
    if (!mounted) return;
    final message = error is ApiException ? error.message : error.toString();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<bool> _ensureAuthenticated() async {
    if (Supabase.instance.client.auth.currentSession != null) return true;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (loginContext) => LoginScreen(
          onAuthenticated: () => Navigator.of(loginContext).pop(true),
        ),
      ),
    );
    return result == true;
  }

  Future<void> _continueToPayment() async {
    if (!await _ensureAuthenticated() || !mounted) return;

    setState(() => _isContinuing = true);
    try {
      final joined = await ApiClient.instance.joinSplitBill(widget.billCode);
      final requestCode = joined.myRequestCode;
      if (requestCode == null || requestCode.isEmpty) {
        throw ApiException(409, '支払い用の請求を取得できませんでした');
      }
      if (!mounted) return;
      final paid = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => SplitBillPaymentMockScreen(
            requestCode: requestCode,
            initialPaymentMethod: _paymentMethod,
            openedFromSharedLink: true,
          ),
        ),
      );
      if (paid == true && mounted) {
        removeQueryParameter('split_code');
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } on ApiException catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _isContinuing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('割り勘の支払い')),
      body: FutureBuilder<PublicSplitBill>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 12),
                    Text(snapshot.error.toString(),
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            );
          }

          final bill = snapshot.data!;
          final authenticated =
              Supabase.instance.client.auth.currentSession != null;
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('請求情報', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Card(
                      child: ListTile(
                        leading: Icon(Icons.groups_outlined,
                            color: theme.colorScheme.primary),
                        title: Text(bill.title),
                        subtitle: Text(
                          '請求者: ${bill.organizerName} さん\n'
                          '${bill.participantCount}人で割り勘',
                        ),
                        isThreeLine: true,
                        trailing: Text(
                          formatMoney(bill.currency, bill.shareAmount),
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('支払い方法', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    PaymentMethodSelector(
                      methods: PaymentMethod.values,
                      selected: _paymentMethod,
                      onSelected: _isContinuing
                          ? null
                          : (method) => setState(() => _paymentMethod = method),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _isContinuing ? null : _continueToPayment,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: _isContinuing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(authenticated
                              ? Icons.arrow_forward
                              : Icons.login),
                      label:
                          Text(authenticated ? '支払いへ進む' : 'ログインもしくは登録して支払いへ進む'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      authenticated
                          ? '参加登録後、支払い内容の確認へ進みます。'
                          : '選択した支払い方法はログイン後も引き継がれます。',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
