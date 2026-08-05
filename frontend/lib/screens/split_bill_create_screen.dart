import 'package:flutter/material.dart';

import '../utils/money.dart';

/// 割り勘は日本円のみ対応する。
const _currency = 'JPY';

/// 割り勘作成画面：合計金額と参加者を入力し、均等に割った金額を算出する。
class SplitBillCreateScreen extends StatefulWidget {
  const SplitBillCreateScreen({super.key});

  @override
  State<SplitBillCreateScreen> createState() => _SplitBillCreateScreenState();
}

class _SplitBillCreateScreenState extends State<SplitBillCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final List<TextEditingController> _participantControllers = [
    TextEditingController(),
    TextEditingController(),
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    for (final c in _participantControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addParticipant() {
    setState(() => _participantControllers.add(TextEditingController()));
  }

  void _removeParticipant(int index) {
    setState(() => _participantControllers.removeAt(index).dispose());
  }

  /// 合計金額を参加者数で均等に分ける。余りは先頭の参加者から1円ずつ多く割り当てる。
  List<String> _splitAmount(int total, int count) {
    final base = total ~/ count;
    final remainder = total % count;
    return List.generate(
      count,
      (i) => (base + (i < remainder ? 1 : 0)).toString(),
    );
  }

  Future<void> _create() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final names = _participantControllers
        .map((c) => c.text.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    if (names.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('参加者を2人以上入力してください')),
      );
      return;
    }

    final total = int.parse(_amountController.text.trim());
    final shares = _splitAmount(total, names.length);

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _SplitResultDialog(
        title: _titleController.text.trim(),
        total: total.toString(),
        names: names,
        shares: shares,
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('割り勘')),
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
                  TextFormField(
                    controller: _titleController,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: '件名（任意）',
                      hintText: '例: 飲み会',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('金額', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '合計金額',
                      suffixText: '円',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final amount = int.tryParse(value?.trim() ?? '');
                      if (amount == null || amount <= 0) {
                        return '正しい金額を入力してください';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '参加者',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _addParticipant,
                        icon: const Icon(Icons.add),
                        label: const Text('追加'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < _participantControllers.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _participantControllers[i],
                              decoration: InputDecoration(
                                labelText: '参加者${i + 1}',
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                          if (_participantControllers.length > 2)
                            IconButton(
                              tooltip: '削除',
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => _removeParticipant(i),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _create,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: const Icon(Icons.call_split),
                    label: const Text('割り勘を作成'),
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

/// 割り勘の計算結果を一人ずつ表示する。
class _SplitResultDialog extends StatelessWidget {
  const _SplitResultDialog({
    required this.title,
    required this.total,
    required this.names,
    required this.shares,
  });

  final String title;
  final String total;
  final List<String> names;
  final List<String> shares;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: const Icon(Icons.call_split, color: Colors.green, size: 48),
      title: Text(title.isEmpty ? '割り勘の結果' : title),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '合計 ${formatMoney(_currency, total)} を'
              '${names.length}人で割り勘しました。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < names.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        names[i],
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      formatMoney(_currency, shares[i]),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
      ],
    );
  }
}
