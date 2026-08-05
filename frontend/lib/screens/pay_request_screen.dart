import 'package:flutter/material.dart';

import '../models/payment_request.dart';
import '../services/api_client.dart';
import '../utils/money.dart';
import '../widgets/payment_request_tile.dart';

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
      final paid = await ApiClient.instance.payPaymentRequest(request.requestCode);
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
      Navigator.of(context).pop();
    } on ApiException catch (err) {
      _showError(err.message);
    } finally {
      if (mounted) setState(() => _isPaying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = _request;
    return Scaffold(
      appBar: AppBar(title: const Text('請求コードで支払う')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('請求コード', style: Theme.of(context).textTheme.titleMedium),
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
                          if (_request != null) setState(() => _request = null);
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
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('確認'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
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
                    FilledButton.icon(
                      onPressed: _isPaying ? null : _pay,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: _isPaying
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.payments),
                      label: Text(
                        '${formatMoney(request.currency, request.amount)} を支払う',
                      ),
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
