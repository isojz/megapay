import 'package:flutter/material.dart';

import '../models/payment_request.dart';
import '../services/api_client.dart';
import '../utils/browser_url.dart';
import '../utils/money.dart';
import '../widgets/payment_method_selector.dart';
import 'home_screen.dart';

/// 割り勘の支払い画面。
///
/// 残高払いと現金払いは実際に請求の状態を更新する。
///   - 残高から支払う: 送金が実行され、残高と履歴が動く
///   - 現金で支払った: その場で現金を渡した記録。残高・履歴は動かさず支払い済みにする
/// PayPay やカードは決済連携が未実装のためモック（請求の状態は変わらない）。
class SplitBillPaymentMockScreen extends StatefulWidget {
  const SplitBillPaymentMockScreen({
    super.key,
    required this.requestCode,
    this.initialPaymentMethod = PaymentMethod.balance,
    this.openedFromSharedLink = false,
  });

  /// 参加時に発行された自分あての請求コード（RQ-XXXXXXXX）
  final String requestCode;
  final PaymentMethod initialPaymentMethod;
  final bool openedFromSharedLink;

  @override
  State<SplitBillPaymentMockScreen> createState() =>
      _SplitBillPaymentMockScreenState();
}

class _SplitBillPaymentMockScreenState
    extends State<SplitBillPaymentMockScreen> {
  PaymentMethod _selectedMethod = PaymentMethod.balance;
  late Future<PaymentRequest> _future;
  bool _isPaying = false;
  bool _isPaid = false;

  @override
  void initState() {
    super.initState();
    _selectedMethod = widget.initialPaymentMethod;
    _future = _loadRequest();
  }

  Future<PaymentRequest> _loadRequest() async {
    final request =
        await ApiClient.instance.lookupPaymentRequest(widget.requestCode);
    if (mounted && _isPaid != request.isPaid) {
      setState(() => _isPaid = request.isPaid);
    }
    return request;
  }

  Future<void> _goHome() async {
    removeQueryParameter('split_code');
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
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

  /// 実際に請求の状態を更新できる支払い方法か（残高払い・現金払いのみ）
  bool _isSupported(PaymentMethod method) =>
      method == PaymentMethod.balance || method == PaymentMethod.cash;

  Future<void> _pay(PaymentRequest request) async {
    final method = _selectedMethod;
    final isCash = method == PaymentMethod.cash;

    if (!_isSupported(method)) {
      _showError('${method.label}での支払いはまだ利用できません');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isCash ? '現金支払いの確認' : '支払い内容の確認'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailRow(label: '割り勘', value: request.memo ?? '—'),
            _DetailRow(label: '請求者', value: '${request.requesterName} さん'),
            _DetailRow(
              label: '金額',
              value: formatMoney(request.currency, request.amount),
            ),
            _DetailRow(label: '支払い方法', value: method.label),
            const SizedBox(height: 12),
            Text(
              isCash
                  ? '現金で渡した記録だけを残します。アプリ内の残高は動きません。'
                  : '支払うと送金が実行されます。取り消せません。',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(isCash ? '現金で支払った' : '支払う'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isPaying = true);
    try {
      final api = ApiClient.instance;
      final paid = isCash
          ? await api.payPaymentRequestByCash(request.requestCode)
          : await api.payPaymentRequest(request.requestCode);
      if (!mounted) return;
      setState(() {
        _isPaid = true;
        _future = Future.value(paid);
      });
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
          title: const Text('支払いが完了しました'),
          content: Text(
            isCash
                ? '${paid.requesterName} さんへ '
                    '${formatMoney(paid.currency, paid.amount)} を現金で支払った記録を残しました。'
                : '${paid.requesterName} さんへ '
                    '${formatMoney(paid.currency, paid.amount)} を支払いました。',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('支払い済み画面へ'),
            ),
          ],
        ),
      );
    } on ApiException catch (err) {
      _showError(err.message);
    } finally {
      if (mounted) setState(() => _isPaying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('割り勘の支払い'),
        leading: widget.openedFromSharedLink && _isPaid
            ? IconButton(
                tooltip: 'ホーム画面へ',
                onPressed: _goHome,
                icon: const Icon(Icons.arrow_back),
              )
            : null,
      ),
      body: FutureBuilder<PaymentRequest>(
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

          final request = snapshot.data!;
          final paid = request.isPaid;
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('請求内容', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    _RequestCard(request: request),
                    const SizedBox(height: 16),
                    if (paid)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Card(
                            color: Colors.green.shade50,
                            child: ListTile(
                              leading: const Icon(Icons.check_circle,
                                  color: Colors.green),
                              title: const Text('支払い済みです'),
                              subtitle: Text(
                                request.isPaidByCash
                                    ? '支払い方法: 現金'
                                    : '支払い方法: MegaPay残高',
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: _goHome,
                            icon: const Icon(Icons.home_outlined),
                            label: const Text('ホーム画面へ移動'),
                          ),
                        ],
                      )
                    else ...[
                      Text('支払い方法', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      PaymentMethodSelector(
                        methods: PaymentMethod.values,
                        selected: _selectedMethod,
                        onSelected: _isPaying
                            ? null
                            : (method) =>
                                setState(() => _selectedMethod = method),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _isPaying ? null : () => _pay(request),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        icon: _isPaying
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(_selectedMethod.icon),
                        label: Text(
                          _selectedMethod == PaymentMethod.cash
                              ? '現金で支払った'
                              : '${formatMoney(request.currency, request.amount)} を'
                                  '${_selectedMethod == PaymentMethod.balance ? '支払う' : '${_selectedMethod.label}で支払う'}',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isSupported(_selectedMethod)
                            ? (_selectedMethod == PaymentMethod.cash
                                ? '現金払いは残高を動かさず、支払い済みの記録だけを残します。'
                                : 'MegaPay残高から集金者へ送金されます。')
                            : '${_selectedMethod.label}は決済連携が未実装のため、まだ支払えません。',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
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

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request});

  final PaymentRequest request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paid = request.isPaid;
    return Card(
      child: ListTile(
        leading: Icon(Icons.groups_outlined, color: theme.colorScheme.primary),
        title: Text(request.memo?.isNotEmpty == true ? request.memo! : '割り勘'),
        subtitle: Text(
          '請求者: ${request.requesterName} さん\n請求コード: ${request.requestCode}',
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatMoney(request.currency, request.amount),
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              paid ? (request.isPaidByCash ? '現金で支払い済み' : '支払い済み') : '未払い',
              style: theme.textTheme.labelSmall?.copyWith(
                color: paid ? Colors.green.shade700 : Colors.orange.shade800,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
