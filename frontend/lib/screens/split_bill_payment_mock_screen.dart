import 'package:flutter/material.dart';

import '../widgets/payment_method_selector.dart';

/// 支払い者が割り勘の請求を受け取った場合の画面モック。
/// API 呼び出しや実際の決済、残高更新は行わない。
class SplitBillPaymentMockScreen extends StatefulWidget {
  const SplitBillPaymentMockScreen({super.key});

  @override
  State<SplitBillPaymentMockScreen> createState() =>
      _SplitBillPaymentMockScreenState();
}

class _SplitBillPaymentMockScreenState
    extends State<SplitBillPaymentMockScreen> {
  PaymentMethod _selectedMethod = PaymentMethod.balance;
  bool _completed = false;

  Future<void> _completeMockPayment() async {
    final method = _selectedMethod;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(method == PaymentMethod.cash ? '現金支払いの確認' : '支払い内容の確認'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _DetailRow(label: '割り勘タイトル', value: '歓迎会 2026'),
            const _DetailRow(label: '請求者', value: '山田 太郎 さん'),
            const _DetailRow(label: '金額', value: '¥4,500'),
            _DetailRow(label: '支払い方法', value: method.label),
            const SizedBox(height: 12),
            const Text(
              'これは画面確認用のモックです。実際の決済や請求状態の更新は行われません。',
              style: TextStyle(fontSize: 12),
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
            child: Text(method == PaymentMethod.cash ? '現金で支払った' : '支払う（モック）'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() => _completed = true);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
          title: const Text('支払いが完了しました'),
          content: Text(
            '${method.label}での支払いを完了しました。\n'
            'これはモックのため、実際の決済データは変更されていません。',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('メイン画面へ'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('割り勘の支払い')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('請求内容', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                const _SplitBillRequestCard(),
                const SizedBox(height: 16),
                Text('支払い方法', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                PaymentMethodSelector(
                  methods: PaymentMethod.values,
                  selected: _selectedMethod,
                  onSelected: _completed
                      ? null
                      : (method) => setState(() => _selectedMethod = method),
                ),
                const SizedBox(height: 16),
                if (_completed)
                  Card(
                    color: Colors.green.shade50,
                    child: ListTile(
                      leading:
                          const Icon(Icons.check_circle, color: Colors.green),
                      title: const Text('支払い済みにしました（モック）'),
                      subtitle: Text('支払い方法: ${_selectedMethod.label}'),
                    ),
                  )
                else
                  FilledButton.icon(
                    onPressed: _completeMockPayment,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: Icon(_selectedMethod.icon),
                    label: Text(_selectedMethod == PaymentMethod.cash
                        ? '現金で支払った'
                        : '${_selectedMethod.label}で支払う（モック）'),
                  ),
                const SizedBox(height: 8),
                Text(
                  'デモ画面のため、実際の残高・決済・支払い状況は変更されません。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SplitBillRequestCard extends StatelessWidget {
  const _SplitBillRequestCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: Icon(Icons.groups_outlined, color: theme.colorScheme.primary),
        title: const Text('歓迎会 2026'),
        subtitle: const Text('請求者: 山田 太郎 さん\n割り勘コード: SB-WELCOME'),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '¥4,500',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '未払い',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.orange.shade800,
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
