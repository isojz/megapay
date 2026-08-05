import 'package:flutter/material.dart';

import '../models/payment_request.dart';
import '../services/api_client.dart';
import '../utils/money.dart';
import '../widgets/payment_request_tile.dart';
import '../widgets/payment_method_selector.dart';
import 'split_bill_list_screen.dart';

/// 請求コードを入力して支払う画面。
/// 一覧から開く場合は [initialCode] を渡すと自動で内容を取得する。
class PayRequestScreen extends StatefulWidget {
  const PayRequestScreen({super.key, this.initialCode});

  final String? initialCode;

  @override
  State<PayRequestScreen> createState() => _PayRequestScreenState();
}

class _PayRequestScreenState extends State<PayRequestScreen> {
  final _codeController = TextEditingController();

  PaymentRequest? _request;
  PaymentMethod _paymentMethod = PaymentMethod.balance;
  bool _isLookingUp = false;
  bool _isPaying = false;

  @override
  void initState() {
    super.initState();
    final initialCode = widget.initialCode;
    if (initialCode != null && initialCode.isNotEmpty) {
      _codeController.text = initialCode;
      // 初回ビルド後に検索する（initState 中に setState を呼ばないため）
      WidgetsBinding.instance.addPostFrameCallback((_) => _lookup());
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
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

  Future<void> _lookup() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      _showError('請求コードを入力してください');
      return;
    }
    setState(() => _isLookingUp = true);
    try {
      final request = await ApiClient.instance.lookupPaymentRequest(code);
      if (mounted) setState(() => _request = request);
    } on ApiException catch (err) {
      if (mounted) setState(() => _request = null);
      _showError(err.message);
    } finally {
      if (mounted) setState(() => _isLookingUp = false);
    }
  }

  Future<void> _pay() async {
    final request = _request;
    if (request == null) return;

    if (_paymentMethod != PaymentMethod.balance) {
      await _payWithMock(request);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('支払い内容の確認'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${request.requesterName} さんへ'),
            const SizedBox(height: 4),
            Text(
              formatMoney(request.currency, request.amount),
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (request.memo != null && request.memo!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('メモ: ${request.memo}'),
            ],
            const SizedBox(height: 8),
            const _ConfirmRow(label: '支払い方法', value: 'MegaPay残高'),
            const SizedBox(height: 8),
            const Text(
              '支払うと送金が実行されます。取り消せません。',
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
            child: const Text('支払う'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isPaying = true);
    try {
      final paid =
          await ApiClient.instance.payPaymentRequest(request.requestCode);
      if (!mounted) return;
      setState(() => _request = paid);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
          title: const Text('支払いが完了しました'),
          content: Text(
            '${paid.requesterName} さんへ '
            '${formatMoney(paid.currency, paid.amount)} を支払いました。',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('閉じる'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on ApiException catch (err) {
      _showError(err.message);
    } finally {
      if (mounted) setState(() => _isPaying = false);
    }
  }

  Future<void> _payWithMock(PaymentRequest request) async {
    final method = _paymentMethod;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('モック決済の確認'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${request.requesterName} さんへ'),
            const SizedBox(height: 4),
            Text(
              formatMoney(request.currency, request.amount),
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _ConfirmRow(label: '支払い方法', value: method.label),
            const SizedBox(height: 12),
            const Text(
              'デモ用の画面です。実際の決済、残高更新、請求状態の更新は行われません。',
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
            child: const Text('モック決済を実行'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isPaying = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _isPaying = false);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.check_circle_outline,
            color: Colors.green, size: 48),
        title: const Text('モック決済が完了しました'),
        content: Text(
          '${method.label}での支払い画面を確認しました。\n'
          '実際の決済データは変更されていません。',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final request = _request;
    final openedFromRequestList =
        widget.initialCode != null && widget.initialCode!.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(openedFromRequestList ? '請求の支払い' : '請求コードで支払う'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!openedFromRequestList) ...[
                  Text('請求コード', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      // 割り勘の支払いは請求コードごとに画面が変わるため、
                      // ここからは一覧に進み、支払う割り勘を選んでもらう
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SplitBillListScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.groups_outlined),
                      label: const Text('割り勘'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _codeController,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: '相手から伝えられたコード',
                            hintText: 'RQ-ABCD2345',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) {
                            if (_request != null) {
                              setState(() => _request = null);
                            }
                          },
                          onSubmitted: (_) => _lookup(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 56,
                        child: OutlinedButton(
                          onPressed: _isLookingUp ? null : _lookup,
                          child: _isLookingUp
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('確認'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
                if (request != null) ...[
                  Text('請求内容', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  PaymentRequestTile(request: request),
                  const SizedBox(height: 16),
                  if (request.isRequestedByMe)
                    const _NoticeCard(
                      icon: Icons.info_outline,
                      message: 'これはあなたが作成した請求です。支払うのは相手の方です。',
                    )
                  else if (!request.isPending)
                    _NoticeCard(
                      icon: Icons.info_outline,
                      message: 'この請求は${request.statusLabel}のため支払えません。',
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('支払い方法',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        PaymentMethodSelector(
                          methods: PaymentMethod.values
                              .where((method) => method != PaymentMethod.cash)
                              .toList(),
                          selected: _paymentMethod,
                          onSelected: _isPaying
                              ? null
                              : (method) =>
                                  setState(() => _paymentMethod = method),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _isPaying ? null : _pay,
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
                              : Icon(_paymentMethod.icon),
                          label: Text(
                            _paymentMethod == PaymentMethod.balance
                                ? '残高から ${formatMoney(request.currency, request.amount)} を支払う'
                                : '${_paymentMethod.label}で支払う（モック）',
                          ),
                        ),
                      ],
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
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
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        leading: Icon(icon),
        title: Text(message, style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }
}
