import 'package:flutter/material.dart';

import '../models/models.dart';
import '../screens/pay_request_screen.dart';
import '../screens/request_create_screen.dart';
import '../screens/request_list_screen.dart';

/// ホーム画面に置く請求機能の入口（請求する／コードで支払う／請求状況）。
class PaymentRequestActions extends StatelessWidget {
  const PaymentRequestActions({
    super.key,
    required this.balances,
    required this.onChanged,
  });

  final List<Balance> balances;

  /// 画面から戻ったときに残高・履歴を再取得するためのコールバック
  final Future<void> Function() onChanged;

  Future<void> _open(BuildContext context, Widget screen) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
    await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            _ActionItem(
              icon: Icons.receipt_long,
              label: '請求する',
              onTap: () => _open(
                context,
                RequestCreateScreen(balances: balances),
              ),
            ),
            _ActionItem(
              icon: Icons.password,
              label: 'コードで支払う',
              onTap: () => _open(context, const PayRequestScreen()),
            ),
            _ActionItem(
              icon: Icons.fact_check_outlined,
              label: '請求状況',
              onTap: () => _open(context, const RequestListScreen()),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  const _ActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
