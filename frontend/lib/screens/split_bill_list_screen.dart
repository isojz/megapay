import 'package:flutter/material.dart';

import '../models/split_bill.dart';
import '../services/api_client.dart';
import '../utils/money.dart';
import 'split_bill_detail_screen.dart';

/// 割り勘一覧：自分が集金する分と、参加している分をまとめて表示する。
class SplitBillListScreen extends StatefulWidget {
  const SplitBillListScreen({super.key});

  @override
  State<SplitBillListScreen> createState() => _SplitBillListScreenState();
}

class _SplitBillListScreenState extends State<SplitBillListScreen> {
  late Future<List<SplitBill>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiClient.instance.fetchSplitBills();
  }

  Future<void> _reload() {
    final future = ApiClient.instance.fetchSplitBills();
    if (mounted) setState(() => _future = future);
    // エラーは FutureBuilder 側で表示するためここでは握りつぶす
    return future.then((_) {}, onError: (_) {});
  }

  Future<void> _openDetail(SplitBill bill) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SplitBillDetailScreen(billCode: bill.billCode),
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('割り勘一覧')),
      body: FutureBuilder<List<SplitBill>>(
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

          final bills = snapshot.data ?? const <SplitBill>[];
          return RefreshIndicator(
            onRefresh: _reload,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (bills.isEmpty)
                      const Card(
                        child: ListTile(
                          title: Text('まだ割り勘はありません'),
                          subtitle: Text('請求コードを受け取ったら「割り勘に参加」から参加できます'),
                        ),
                      ),
                    ...bills.map(
                      (b) => _SplitBillTile(
                        bill: b,
                        onTap: () => _openDetail(b),
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

class _SplitBillTile extends StatelessWidget {
  const _SplitBillTile({required this.bill, required this.onTap});

  final SplitBill bill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 集金者は集金の進み具合、参加者は自分の支払い状況を右側に出す
    final trailingLabel = bill.isOrganizer
        ? '${bill.paidCount} / ${bill.expectedPayerCount} 人'
        : (bill.isPaidByMe ? '支払い済み' : '未払い');
    final trailingColor = bill.isOrganizer
        ? theme.colorScheme.outline
        : (bill.isPaidByMe ? Colors.green.shade700 : Colors.orange.shade800);

    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundColor: theme.colorScheme.onPrimaryContainer,
          child: Icon(bill.isOrganizer ? Icons.groups : Icons.group_outlined),
        ),
        title: Text(bill.title),
        subtitle: Text(
          [
            bill.isOrganizer ? '集金者: あなた' : '集金者: ${bill.organizerName} さん',
            '1人あたり ${formatMoney(bill.currency, bill.shareAmount)}',
            formatDateTime(bill.createdAt),
          ].join('\n'),
        ),
        isThreeLine: true,
        trailing: Text(
          trailingLabel,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: trailingColor, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
