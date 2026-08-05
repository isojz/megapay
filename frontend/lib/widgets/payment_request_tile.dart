import 'package:flutter/material.dart';

import '../models/payment_request.dart';
import '../utils/money.dart';

/// 請求 1 件を表示するカード。請求一覧と支払い画面で共用する。
class PaymentRequestTile extends StatelessWidget {
  const PaymentRequestTile({super.key, required this.request, this.actions});

  final PaymentRequest request;

  /// カード下部に並べるボタン（一覧での「支払う」「取り消す」など）
  final List<Widget>? actions;

  Color _statusColor(BuildContext context) => switch (request.status) {
        'paid' => Colors.green.shade700,
        'cancelled' => Theme.of(context).colorScheme.outline,
        _ => Colors.orange.shade800,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final requestedByMe = request.isRequestedByMe;
    final statusColor = _statusColor(context);

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Icon(
              requestedByMe ? Icons.receipt_long : Icons.request_quote,
              color: theme.colorScheme.primary,
            ),
            title: Text(
              requestedByMe
                  ? '${request.payerName} さんへ請求'
                  : '${request.requesterName} さんから請求',
            ),
            subtitle: Text(
              [
                request.requestCode,
                formatDateTime(request.createdAt),
                if (request.memo != null && request.memo!.isNotEmpty)
                  'メモ: ${request.memo}',
              ].join('\n'),
            ),
            isThreeLine: true,
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatMoney(request.currency, request.amount),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  request.statusLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (actions != null && actions!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: actions!,
              ),
            ),
        ],
      ),
    );
  }
}
