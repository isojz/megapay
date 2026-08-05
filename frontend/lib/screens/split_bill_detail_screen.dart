import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/split_bill.dart';
import '../services/api_client.dart';
import '../utils/money.dart';
import 'split_bill_payment_mock_screen.dart';

class _DetailData {
  const _DetailData(this.bill, this.participants);

  final SplitBill bill;
  final List<SplitBillParticipant> participants;
}

/// グループ画面：割り勘の内容と、参加者ごとの支払い状況を一覧で表示する。
/// 自分が未払いの場合はここから支払いに進める。
class SplitBillDetailScreen extends StatefulWidget {
  const SplitBillDetailScreen({super.key, required this.billCode});

  final String billCode;

  @override
  State<SplitBillDetailScreen> createState() => _SplitBillDetailScreenState();
}

class _SplitBillDetailScreenState extends State<SplitBillDetailScreen> {
  late Future<_DetailData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DetailData> _load() async {
    final api = ApiClient.instance;
    final results = await Future.wait([
      api.lookupSplitBill(widget.billCode),
      api.fetchSplitBillParticipants(widget.billCode),
    ]);
    return _DetailData(
      results[0] as SplitBill,
      results[1] as List<SplitBillParticipant>,
    );
  }

  Future<void> _reload() {
    final future = _load();
    if (mounted) setState(() => _future = future);
    // エラーは FutureBuilder 側で表示するためここでは握りつぶす
    return future.then((_) {}, onError: (_) {});
  }

  Future<void> _copyCode(SplitBill bill) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: bill.billCode));
    messenger.showSnackBar(
      const SnackBar(content: Text('請求コードをコピーしました')),
    );
  }

  Future<void> _pay(SplitBill bill) async {
    final code = bill.myRequestCode;
    if (code == null) return;
    // 割り勘は現金でのやり取りもあるため、支払い方法を選べる画面へ進む
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SplitBillPaymentMockScreen(requestCode: code),
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('割り勘グループ')),
      body: FutureBuilder<_DetailData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 12),
                    Text(snapshot.error.toString(), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                      label: const Text('再読み込み'),
                    ),
                  ],
                ),
              ),
            );
          }

          final bill = snapshot.data!.bill;
          final participants = snapshot.data!.participants;
          return RefreshIndicator(
            onRefresh: _reload,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    _SummaryCard(bill: bill, onCopyCode: () => _copyCode(bill)),
                    if (bill.joined && !bill.isPaidByMe) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _pay(bill),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        icon: const Icon(Icons.payments),
                        label: Text(
                          '${formatMoney(bill.currency, bill.shareAmount)} を支払う',
                        ),
                      ),
                    ],
                    if (bill.joined && bill.isPaidByMe) ...[
                      const SizedBox(height: 16),
                      Card(
                        color: Colors.green.shade50,
                        child: const ListTile(
                          leading: Icon(Icons.check_circle, color: Colors.green),
                          title: Text('あなたは支払い済みです'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '参加者',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${bill.paidCount} / ${participants.length} 人が支払い済み',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (participants.isEmpty)
                      const Card(
                        child: ListTile(
                          title: Text('まだ誰も参加していません'),
                          subtitle: Text('請求コードを参加者に伝えてください'),
                        ),
                      ),
                    ...participants.map(
                      (p) => _ParticipantTile(
                        participant: p,
                        currency: bill.currency,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.bill, required this.onCopyCode});

  final SplitBill bill;
  final VoidCallback onCopyCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              bill.title,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '集金者: ${bill.organizerName} さん'
              '${bill.isOrganizer ? '（あなた）' : ''}',
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: 24),
            _SummaryRow(
              label: '1人あたり',
              value: formatMoney(bill.currency, bill.shareAmount),
              emphasize: true,
            ),
            _SummaryRow(
              label: '合計金額',
              value: formatMoney(bill.currency, bill.totalAmount),
            ),
            _SummaryRow(
              label: '参加人数',
              value: '${bill.participantCount} 人（集金者を含む）',
            ),
            _SummaryRow(
              label: '集金済み',
              value: '${formatMoney(bill.currency, bill.collectedAmount)}'
                  ' / ${formatMoney(bill.currency, bill.expectedTotal)}',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '請求コード: ${bill.billCode}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontFamily: 'monospace'),
                  ),
                ),
                IconButton(
                  tooltip: '請求コードをコピー',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: onCopyCode,
                ),
              ],
            ),
            Text(
              bill.isFull
                  ? '参加人数の上限に達しています'
                  : 'このコードを参加者に伝えると、グループに参加して支払えます',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: emphasize
                  ? theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)
                  : theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({required this.participant, required this.currency});

  final SplitBillParticipant participant;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paid = participant.isPaid;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: paid
              ? Colors.green.shade100
              : theme.colorScheme.surfaceContainerHighest,
          child: Icon(
            paid
                ? (participant.isPaidByCash
                    ? Icons.payments_outlined
                    : Icons.check)
                : Icons.schedule,
            color: paid ? Colors.green.shade800 : theme.colorScheme.outline,
          ),
        ),
        title: Text(
          '${participant.displayName} さん'
          '${participant.isMe ? '（あなた）' : ''}',
        ),
        subtitle: Text(
          paid && participant.paidAt != null
              ? '${participant.userId}\n'
                  '${formatDateTime(participant.paidAt!)} に'
                  '${participant.isPaidByCash ? '現金で' : ''}支払い'
              : participant.userId,
        ),
        isThreeLine: paid && participant.paidAt != null,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatMoney(currency, participant.amount),
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              participant.statusLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: paid ? Colors.green.shade700 : Colors.orange.shade800,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
