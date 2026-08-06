import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/split_bill.dart';
import '../services/api_client.dart';
import '../utils/money.dart';
import '../utils/browser_url.dart';
import 'split_bill_detail_screen.dart';
import '../utils/input_formatters.dart';

/// 割り勘は日本円のみ対応する。
const _currency = 'JPY';

/// 件名を省略した場合に使う既定のイベント名。
const _defaultTitle = '割り勘';

/// 割り勘作成画面：合計金額と人数を入力して割り勘を登録し、参加用の請求コードを発行する。
/// 発行したコードを参加者が入力すると、割り勘後の金額が自動で請求される。
class SplitBillCreateScreen extends StatefulWidget {
  const SplitBillCreateScreen({super.key});

  @override
  State<SplitBillCreateScreen> createState() => _SplitBillCreateScreenState();
}

class _SplitBillCreateScreenState extends State<SplitBillCreateScreen> {
  /// 1件の割り勘に参加できる人数の上限（バックエンド側の制限に合わせる）。
  static const _maxParticipants = 100;

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _countController = TextEditingController();

  bool _isCreating = false;

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _countController.dispose();
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

  Future<void> _create() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final title = _titleController.text.trim();
    final total = _amountController.text.trim();
    final count = int.parse(_countController.text.trim());

    setState(() => _isCreating = true);
    try {
      final bill = await ApiClient.instance.createSplitBill(
        title: title.isEmpty ? _defaultTitle : title,
        currency: _currency,
        totalAmount: total,
        participantCount: count,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _SplitBillCreatedDialog(bill: bill),
      );
      if (!mounted) return;
      // 作成後はそのままグループ画面へ移動し、参加状況を確認できるようにする
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SplitBillDetailScreen(billCode: bill.billCode),
        ),
      );
    } on ApiException catch (err) {
      _showError(err.message);
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
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
                    maxLength: 100,
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
                    inputFormatters: integerAmountInputFormatters,
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
                  Text('参加者', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _countController,
                    keyboardType: TextInputType.number,
                    inputFormatters: integerAmountInputFormatters,
                    decoration: const InputDecoration(
                      labelText: '人数',
                      suffixText: '人',
                      helperText: '自分を含めた人数。端数は切り上げます',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final count = int.tryParse(value?.trim() ?? '');
                      if (count == null || count < 2) {
                        return '2以上の人数を入力してください';
                      }
                      if (count > _maxParticipants) {
                        return '人数は$_maxParticipants人までです';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _isCreating ? null : _create,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: _isCreating
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.call_split),
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

/// 作成した割り勘の参加用コードを大きく表示してコピーできるようにする。
class _SplitBillCreatedDialog extends StatelessWidget {
  const _SplitBillCreatedDialog({required this.bill});

  final SplitBill bill;

  Future<void> _copyCode(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: bill.billCode));
    messenger.showSnackBar(
      const SnackBar(content: Text('請求コードをコピーしました')),
    );
  }

  String get _paymentLink => buildSplitBillPaymentLink(bill.billCode);

  Future<void> _copyLink(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: _paymentLink));
    messenger.showSnackBar(
      const SnackBar(content: Text('支払いリンクをコピーしました')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      scrollable: true,
      icon: const Icon(Icons.call_split, color: Colors.green, size: 48),
      title: const Text('割り勘を作成しました'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${bill.title}\n'
            '合計 ${formatMoney(bill.currency, bill.totalAmount)} を'
            '${bill.participantCount}人で割り勘します。',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text('1人あたり', style: theme.textTheme.bodySmall),
          Text(
            formatMoney(bill.currency, bill.shareAmount),
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Divider(height: 32),
          Text('請求コード', style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          SelectableText(
            bill.billCode,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => _copyCode(context),
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('コードをコピー'),
          ),
          const SizedBox(height: 20),
          Text('支払いリンク', style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          SelectableText(
            _paymentLink,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => _copyLink(context),
            icon: const Icon(Icons.link, size: 18),
            label: const Text('リンクをコピー'),
          ),
          const SizedBox(height: 12),
          Text(
            'このコードを参加者に伝えてください。'
            '参加者が「割り勘に参加」でコードを入力すると、'
            '${formatMoney(bill.currency, bill.shareAmount)} の請求が届きます。',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
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
