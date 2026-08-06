import 'package:flutter/material.dart';

enum PaymentMethod {
  balance('残高から支払う', Icons.account_balance_wallet_outlined, false),
  payPay('PayPay', Icons.qr_code_2, true),
  visa('Visa', Icons.credit_card, true),
  mastercard('Mastercard', Icons.credit_card, true),
  jcb('JCB', Icons.credit_card, true),
  amex('American Express', Icons.credit_card, true),
  // 現金は「その場で渡した記録」を実際に残せるためモックではない
  cash('現金で支払った', Icons.payments_outlined, false);

  const PaymentMethod(this.label, this.icon, this.isMock);

  final String label;
  final IconData icon;
  final bool isMock;
}

/// 個人請求と割り勘請求で共通利用する支払い方法の選択UI。
class PaymentMethodSelector extends StatelessWidget {
  const PaymentMethodSelector({
    super.key,
    required this.methods,
    required this.selected,
    this.onSelected,
  });

  final List<PaymentMethod> methods;
  final PaymentMethod selected;
  final ValueChanged<PaymentMethod>? onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: methods.map((method) {
        return ChoiceChip(
          selected: selected == method,
          onSelected: onSelected == null ? null : (_) => onSelected!(method),
          avatar: Icon(method.icon, size: 18),
          label: Text(method.label),
        );
      }).toList(),
    );
  }
}
