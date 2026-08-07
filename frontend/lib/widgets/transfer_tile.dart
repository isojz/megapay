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
        // ListTile は trailing の高さを 56px までに制限する。金額と保存ボタンを
        // 縦に積むと合計がこの上限を超えやすく、端末やブラウザの文字サイズを
        // 大きくしている環境ではみ出していた。横に並べれば高さは合計ではなく
        // 「大きい方」で決まるため、文字が拡大されても崩れない。
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                '$sign${formatMoney(record.currency, record.amount)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold, color: color),
              ),
            ),
            const SizedBox(width: 4),
            // 以前は高さ 24px しかなく指で押しづらかった。横並びにしたことで
            // 高さに余裕ができたので、押しやすい 40px を確保する。
            SizedBox(
              height: 40,
              width: 40,
              child: IconButton(
                padding: EdgeInsets.zero,
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
