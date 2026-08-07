import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../utils/money.dart';

class WithdrawScreen extends StatefulWidget {
  const WithdrawScreen({
    super.key,
    required this.balances,
  });

  final List<Balance> balances;

  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  /// 現在は日本円のみ出金できる。
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

  void _goNext() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_selectedMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('出金方法を選択してください'),
        ),
      );
      return;
    }

    final amount = _amountController.text.trim();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${formatMoney(_currency, amount)} を$_selectedMethodで出金します',
        ),
      ),
    );

    // TODO: 選択した出金方法ごとの次画面へ遷移する
  }

  @override
  Widget build(BuildContext context) {
    final selectedBalance = _selectedBalance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('出金'),
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
                          '現在の残高',
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
                  '出金額',
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
                    final balance = _selectedBalance;
                    if (balance != null &&
                        (double.tryParse(balance.amount) ?? 0) < amount) {
                      return '残高が不足しています';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  '出金方法',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _WithdrawMethodButton(
                  icon: Icons.account_balance_outlined,
                  label: '指定口座',
                  selected: _selectedMethod == '指定口座',
                  onPressed: () => _selectMethod('指定口座'),
                ),
                const SizedBox(height: 12),
                _WithdrawMethodButton(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'PayPay',
                  selected: _selectedMethod == 'PayPay',
                  onPressed: () => _selectMethod('PayPay'),
                ),
                const SizedBox(height: 12),
                _WithdrawMethodButton(
                  icon: Icons.stars_outlined,
                  label: 'ポイントに変換',
                  selected: _selectedMethod == 'ポイントに変換',
                  onPressed: () => _selectMethod('ポイントに変換'),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _goNext,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('次へ'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WithdrawMethodButton extends StatelessWidget {
  const _WithdrawMethodButton({
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
