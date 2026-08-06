import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';
import '../utils/money.dart';

/// 送金・受取 1 件分の表示。ホームの直近履歴と履歴一覧画面で共用する。
class TransferTile extends StatelessWidget {
  const TransferTile({super.key, required this.record, required this.onSave});

  final TransferRecord record;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantics = MegaPaySemantics.of(context);
    final sent = record.isSent;
    final sign = sent ? '-' : '+';
    final color = sent ? semantics.negativeAmount : semantics.positiveAmount;
    return Card(
      child: ListTile(
        leading: Icon(
          sent ? Icons.arrow_upward : Icons.arrow_downward,
          color: sent ? theme.colorScheme.primary : semantics.positiveAmount,
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
            // 高さ 24px では指で押しづらく誤タップも起きるため、
            // アイコンの見た目は変えずに当たり判定だけ広げる。
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 40,
                minHeight: 40,
              ),
              tooltip: 'ユーザーを保存',
              onPressed: onSave,
              icon: const Icon(Icons.bookmark_add_outlined, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
