import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../utils/money.dart';

/// 送金画面：宛先（ユーザーID）・通貨・金額を指定して送金する。
class TransferScreen extends StatefulWidget {
  const TransferScreen({
    super.key,
    required this.balances,
    this.initialRecipient,
  });

  final List<Balance> balances;
  final RecipientInfo? initialRecipient;

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final _formKey = GlobalKey<FormState>();
  final _recipientController = TextEditingController();
  final _amountController = TextEditingController();
  final _memoController = TextEditingController();

  String? _currency;
  RecipientInfo? _verifiedRecipient;
  bool _isLookingUp = false;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    if (widget.balances.isNotEmpty) {
      _currency = widget.balances.first.currency;
    }
    final recipient = widget.initialRecipient;
    if (recipient != null) {
      _recipientController.text = recipient.userId;
      _verifiedRecipient = recipient;
    }
  }

  @override
  void dispose() {
    _recipientController.dispose();
    _amountController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  Balance? get _selectedBalance {
    for (final balance in widget.balances) {
      if (balance.currency == _currency) return balance;
    }
    return null;
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

  /// 宛先IDから相手を検索して表示名を確認する。
  Future<RecipientInfo?> _lookupRecipient() async {
    final recipientId = _recipientController.text.trim();
    if (recipientId.isEmpty) {
      _showError('送金先のユーザーIDを入力してください');
      return null;
    }
    setState(() => _isLookingUp = true);
    try {
      final recipient = await ApiClient.instance.lookupRecipient(recipientId);
      if (mounted) setState(() => _verifiedRecipient = recipient);
      return recipient;
    } on ApiException catch (err) {
      if (mounted) setState(() => _verifiedRecipient = null);
      _showError(err.message);
      return null;
    } finally {
      if (mounted) setState(() => _isLookingUp = false);
    }
  }

  Future<void> _send() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // 宛先が未確認なら先に確認する
    final recipient = _verifiedRecipient ?? await _lookupRecipient();
    if (recipient == null || !mounted) return;

    final currency = _currency!;
    final amount = _amountController.text.trim();
    final memo = _memoController.text.trim();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('送金内容の確認'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ConfirmRow(label: '宛先', value: '${recipient.displayName} さん'),
            _ConfirmRow(label: 'ユーザーID', value: recipient.userId),
            _ConfirmRow(label: '金額', value: formatMoney(currency, amount)),
            if (memo.isNotEmpty) _ConfirmRow(label: 'メモ', value: memo),
            const SizedBox(height: 8),
            const Text(
              '送金は取り消せません。内容をご確認ください。',
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
            child: const Text('送金する'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSending = true);
    try {
      await ApiClient.instance.sendTransfer(
        recipientUserId: recipient.userId,
        currency: currency,
        amount: amount,
        memo: memo.isEmpty ? null : memo,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
          title: const Text('送金が完了しました'),
          content: Text(
            '${recipient.displayName} さんへ ${formatMoney(currency, amount)} を送金しました。',
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
      Navigator.of(context).pop(true); // ホーム画面へ戻って残高を更新
    } on ApiException catch (err) {
      _showError(err.message);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedBalance = _selectedBalance;
    return Scaffold(
      appBar: AppBar(title: const Text('送金')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('送金先', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _recipientController,
                          decoration: const InputDecoration(
                            labelText: '相手のユーザーID',
                            hintText: 'MP-12345678',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) {
                            if (_verifiedRecipient != null) {
                              setState(() => _verifiedRecipient = null);
                            }
                          },
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                                  ? '送金先のユーザーIDを入力してください'
                                  : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 56,
                        child: OutlinedButton(
                          onPressed: _isLookingUp ? null : _lookupRecipient,
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
                  if (_verifiedRecipient != null) ...[
                    const SizedBox(height: 8),
                    Card(
                      color: Colors.green.shade50,
                      child: ListTile(
                        leading:
                            const Icon(Icons.check_circle, color: Colors.green),
                        title: Text('${_verifiedRecipient!.displayName} さん'),
                        subtitle: Text(_verifiedRecipient!.userId),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text('金額', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _currency,
                    decoration: const InputDecoration(
                      labelText: '通貨',
                      border: OutlineInputBorder(),
                    ),
                    items: widget.balances
                        .map((b) => DropdownMenuItem(
                              value: b.currency,
                              child: Text(b.currency),
                            ))
                        .toList(),
                    onChanged: (value) => setState(() => _currency = value),
                    validator: (value) => value == null ? '通貨を選択してください' : null,
                  ),
                  if (selectedBalance != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '利用可能残高: ${formatMoney(selectedBalance.currency, selectedBalance.amount)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '送金金額',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final amount = double.tryParse(value?.trim() ?? '');
                      if (amount == null || amount <= 0) {
                        return '正しい金額を入力してください';
                      }
                      final balance = _selectedBalance;
                      if (balance != null &&
                          (double.tryParse(balance.amount) ?? 0) < amount) {
                        return '残高が不足しています';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _memoController,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'メモ（任意）',
                      hintText: '例: ランチ代',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _isSending ? null : _send,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: _isSending
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: const Text('送金する'),
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

class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
