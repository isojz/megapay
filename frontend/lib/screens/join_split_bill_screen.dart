import 'package:flutter/material.dart';

import '../models/split_bill.dart';
import '../services/api_client.dart';
import '../utils/money.dart';
import 'split_bill_detail_screen.dart';
import '../utils/input_formatters.dart';

/// 割り勘への参加画面：集金者から伝えられた請求コードを入力してグループに参加する。
/// 参加すると同時に「集金者 → 自分」の請求（割り勘後の金額）が作成される。
class JoinSplitBillScreen extends StatefulWidget {
  const JoinSplitBillScreen({super.key});

  @override
  State<JoinSplitBillScreen> createState() => _JoinSplitBillScreenState();
}

class _JoinSplitBillScreenState extends State<JoinSplitBillScreen> {
  final _codeController = TextEditingController();

  SplitBill? _bill;
  bool _isLookingUp = false;
  bool _isJoining = false;

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
      final bill = await ApiClient.instance.lookupSplitBill(code);
      if (mounted) setState(() => _bill = bill);
    } on ApiException catch (err) {
      if (mounted) setState(() => _bill = null);
      _showError(err.message);
    } finally {
      if (mounted) setState(() => _isLookingUp = false);
    }
  }

  Future<void> _join() async {
    final bill = _bill;
    if (bill == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('参加の確認'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('「${bill.title}」に参加します。'),
            const SizedBox(height: 8),
            Text(
              formatMoney(bill.currency, bill.shareAmount),
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '${bill.organizerName} さんからこの金額の請求が届きます。'
              '支払いはグループ画面から行えます。',
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
            child: const Text('参加する'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isJoining = true);
    try {
      final joined = await ApiClient.instance.joinSplitBill(bill.billCode);
      if (!mounted) return;
      // 参加後はそのままグループ画面へ移動する
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SplitBillDetailScreen(billCode: joined.billCode),
        ),
      );
    } on ApiException catch (err) {
      _showError(err.message);
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  Future<void> _openDetail(SplitBill bill) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SplitBillDetailScreen(billCode: bill.billCode),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bill = _bill;
    return Scaffold(
      appBar: AppBar(title: const Text('割り勘に参加')),
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
                          labelText: '集金者から伝えられたコード',
                          hintText: 'SP-ABCD2345',
                          border: OutlineInputBorder(),
                        ),
                        inputFormatters: codeInputFormatters,
                        onChanged: (_) {
                          if (_bill != null) setState(() => _bill = null);
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
                if (bill != null) ...[
                  Text('内容', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bill.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text('集金者: ${bill.organizerName} さん'),
                          const SizedBox(height: 12),
                          Text(
                            'あなたの支払い額',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            formatMoney(bill.currency, bill.shareAmount),
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '合計 ${formatMoney(bill.currency, bill.totalAmount)}'
                            ' を ${bill.participantCount} 人で割り勘'
                            '（現在 ${bill.joinedCount} / ${bill.expectedPayerCount} 人が参加）',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (bill.isOrganizer)
                    _NoticeCard(
                      message: 'これはあなたが集金する割り勘です。'
                          'グループ画面で支払い状況を確認できます。',
                      actionLabel: 'グループ画面を開く',
                      onAction: () => _openDetail(bill),
                    )
                  else if (bill.joined)
                    _NoticeCard(
                      message: 'すでに参加済みです。'
                          '${bill.isPaidByMe ? '支払いも完了しています。' : 'グループ画面から支払えます。'}',
                      actionLabel: 'グループ画面を開く',
                      onAction: () => _openDetail(bill),
                    )
                  else if (bill.isFull)
                    const _NoticeCard(message: '参加人数の上限に達しているため参加できません。')
                  else
                    FilledButton.icon(
                      onPressed: _isJoining ? null : _join,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: _isJoining
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.group_add),
                      label: const Text('このグループに参加する'),
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
  const _NoticeCard({required this.message, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
