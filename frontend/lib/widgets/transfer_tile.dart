import 'package:flutter/material.dart';

import '../models/models.dart';
import '../utils/money.dart';

/// 送金・受取 1 件分の表示。ホームの直近履歴と履歴一覧画面で共用する。
class TransferTile extends StatelessWidget {
  const TransferTile({super.key, required this.record, required this.onSave});

  final TransferRecord record;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sent = record.isSent;
    final sign = sent ? '-' : '+';
    final color = sent ? theme.colorScheme.onSurface : Colors.green.shade700;
    return Card(
      child: ListTile(
        leading: Icon(
          sent ? Icons.arrow_upward : Icons.arrow_downward,
          color: sent ? theme.colorScheme.primary : Colors.green.shade700,
        ),
        title: Text(
          sent
              ? '${record.counterpartName} さんへ送金'
              : '${record.counterpartName} さんから受取',
        ),
        subtitle: Text(
          [
            record.counterpartUserId,
            formatDateTime(record.createdAt),
            if (record.memo != null && record.memo!.isNotEmpty)
              'メモ: ${record.memo}',
          ].join('\n'),
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$sign${formatMoney(record.currency, record.amount)}',
              maxLines: 1,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold, color: color),
            ),
            SizedBox(
              height: 24,
              child: IconButton(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                tooltip: 'ユーザーを保存',
                onPressed: onSave,
                icon: const Icon(Icons.bookmark_add_outlined, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
