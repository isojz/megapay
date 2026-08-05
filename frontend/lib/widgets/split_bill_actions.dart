import 'package:flutter/material.dart';

import '../screens/join_split_bill_screen.dart';
import '../screens/split_bill_list_screen.dart';

/// ホーム画面に置く割り勘機能の入口。
///
/// 割り勘の「作成」はメイン画面のメニュー（PaymentRequestActions）側の担当のため、
/// ここでは参加と一覧だけを扱う。
class SplitBillActions extends StatelessWidget {
  const SplitBillActions({super.key, required this.onChanged});

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
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '割り勘',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
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
    return SizedBox(
      width: 104,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
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
