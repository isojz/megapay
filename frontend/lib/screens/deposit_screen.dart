import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../services/mock_funding.dart';
import '../utils/money.dart';

/// 入金画面：入金方法を選ぶところまで。出金画面と対になる構成。
class DepositScreen extends StatefulWidget {
  const DepositScreen({
    super.key,
    required this.balances,
  });

  final List<Balance> balances;

  @override
  State<DepositScreen> createState() => _DepositScreenState();
}

class _DepositScreenState extends State<DepositScreen> {
  /// 現在は日本円のみ入金できる。
  static const _currency = 'JPY';

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();

  String? _selectedMethod;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Balance? get _selectedBalance {
    for (final balance in widget.balances) {
      if (balance.currency == _currency) {
        return balance;
      }
    }

    return null;
  }

  void _selectMethod(String method) {
    setState(() {
      _selectedMethod = method;
    });
  }

  Future<void> _goNext() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final method = _selectedMethod;
    if (method == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('入金方法を選択してください'),
        ),
      );
      return;
    }

    final amount = int.parse(_amountController.text.trim());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('入金内容の確認'),
        content: Text(
          '${formatMoney(_currency, amount.toString())} を$methodから入金します。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('入金する'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await MockFunding.deposit(amount);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${formatMoney(_currency, amount.toString())} を入金しました'),
      ),
    );
    // ホーム画面へ戻って残高を更新する
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final selectedBalance = _selectedBalance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('入金'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '現在の残高（日本円）',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          selectedBalance == null
                              ? '残高がありません'
                              : formatMoney(
                                  selectedBalance.currency,
                                  selectedBalance.amount,
                                ),
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '入金額',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '金額',
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
                Text(
                  '入金方法',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _DepositMethodButton(
                  icon: Icons.account_balance_outlined,
                  label: '指定口座',
                  selected: _selectedMethod == '指定口座',
                  onPressed: () => _selectMethod('指定口座'),
                ),
                const SizedBox(height: 12),
                _DepositMethodButton(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'PayPay',
                  selected: _selectedMethod == 'PayPay',
                  onPressed: () => _selectMethod('PayPay'),
                ),
                const SizedBox(height: 12),
                _DepositMethodButton(
                  icon: Icons.credit_card,
                  label: 'クレジットカード',
                  selected: _selectedMethod == 'クレジットカード',
                  onPressed: () => _selectMethod('クレジットカード'),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _goNext,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('入金する'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DepositMethodButton extends StatelessWidget {
  const _DepositMethodButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
          side: BorderSide(
            width: selected ? 2 : 1,
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
          ),
          backgroundColor: selected ? theme.colorScheme.primaryContainer : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.left,
              ),
            ),
            if (selected)
              Icon(
                Icons.check_circle,
                color: theme.colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}
