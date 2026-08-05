import 'package:flutter/material.dart';

import '../screens/join_split_bill_screen.dart';
import '../models/models.dart';
import '../screens/pay_request_screen.dart';
import '../screens/request_create_screen.dart';
import '../screens/request_list_screen.dart';
import '../screens/split_bill_create_screen.dart';
import '../screens/withdraw_screen.dart';
import '../screens/split_bill_list_screen.dart';

/// ホーム画面の主要機能をカテゴリ別にまとめたメニュー。
class PaymentRequestActions extends StatelessWidget {
  const PaymentRequestActions({
    super.key,
    required this.balances,
    required this.onChanged,
    required this.onTransfer,
    required this.onSavedUsers,
  });

  final List<Balance> balances;

  /// 画面から戻ったときに残高・履歴を再取得するためのコールバック
  final Future<void> Function() onChanged;
  final VoidCallback onTransfer;
  final VoidCallback onSavedUsers;

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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ActionSection(
              title: '請求',
              children: [
                _ActionItem(
                  icon: Icons.receipt_long,
                  label: '請求する',
                  onTap: () => _open(
                    context,
                    const RequestCreateScreen(),
                  ),
                ),
                _ActionItem(
                  icon: Icons.password,
                  label: 'コードで支払う',
                  onTap: () => _open(
                    context,
                    const PayRequestScreen(),
                  ),
                ),
                _ActionItem(
                  icon: Icons.fact_check_outlined,
                  label: '請求状況',
                  onTap: () => _open(
                    context,
                    const RequestListScreen(),
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            _ActionSection(
              title: '割り勘',
              children: [
                _ActionItem(
                  icon: Icons.call_split,
                  label: '割り勘を作成',
                  onTap: () => _open(
                    context,
                    const SplitBillCreateScreen(),
                  ),
                ),
                _ActionItem(
                  icon: Icons.group_add,
                  label: '割り勘に参加',
                  onTap: () => _open(context, const JoinSplitBillScreen()),
                ),
                _ActionItem(
                  icon: Icons.groups,
                  label: '割り勘一覧',
                  onTap: () => _open(context, const SplitBillListScreen()),
                ),
              ],
            ),
            const Divider(height: 32),
            _ActionSection(
              title: '送金・出金',
              children: [
                _ActionItem(
                  icon: Icons.send_outlined,
                  label: '送金する',
                  onTap: onTransfer,
                ),
                _ActionItem(
                  icon: Icons.account_balance_wallet_outlined,
                  label: '出金',
                  onTap: () => _open(
                    context,
                    WithdrawScreen(balances: balances),
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            _ActionSection(
              title: 'ユーザー',
              children: [
                _ActionItem(
                  icon: Icons.people_outline,
                  label: 'ユーザー一覧',
                  onTap: onSavedUsers,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionSection extends StatelessWidget {
  const _ActionSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: children,
        ),
      ],
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

    return SizedBox(
      width: 104,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 8,
            horizontal: 4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                child: Icon(icon),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
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
