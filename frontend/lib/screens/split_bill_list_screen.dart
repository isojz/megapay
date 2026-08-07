import 'package:flutter/material.dart';

import '../models/split_bill.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../utils/money.dart';
import '../widgets/app_bar_title.dart';
import 'split_bill_detail_screen.dart';

/// 割り勘一覧：自分が集金する分と、参加している分をまとめて表示する。
class SplitBillListScreen extends StatefulWidget {
  const SplitBillListScreen({super.key});

  @override
  State<SplitBillListScreen> createState() => _SplitBillListScreenState();
}

class _SplitBillListScreenState extends State<SplitBillListScreen>
    with SingleTickerProviderStateMixin {
  late Future<List<SplitBill>> _future;
  _ListStatus _status = _ListStatus.inProgress;

  /// 選択中のタブでアイコンを塗りつぶしに変えるため、自前で持って監視する。
  /// DefaultTabController のままだと切り替えを検知できない。
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    _future = ApiClient.instance.fetchSplitBills();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

  bool _isCompleted(SplitBill bill) => bill.isOrganizer
      ? bill.paidCount >= bill.expectedPayerCount
      : bill.isPaidByMe;

  Widget _buildRoleList(List<SplitBill> bills, {required bool organizer}) {
    final roleBills =
        bills.where((bill) => bill.isOrganizer == organizer).toList();
    final inProgressCount =
        roleBills.where((bill) => !_isCompleted(bill)).length;
    final completedCount = roleBills.where(_isCompleted).length;
    final visibleBills = roleBills
        .where(
          (bill) => _status == _ListStatus.completed
              ? _isCompleted(bill)
              : !_isCompleted(bill),
        )
        .toList();

    return RefreshIndicator(
      onRefresh: _reload,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<_ListStatus>(
                segments: [
                  ButtonSegment(
                    value: _ListStatus.inProgress,
                    icon: const Icon(Icons.schedule),
                    label: Text('進行中 $inProgressCount'),
                  ),
                  ButtonSegment(
                    value: _ListStatus.completed,
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text('完了 $completedCount'),
                  ),
                ],
                selected: {_status},
                onSelectionChanged: (selection) {
                  setState(() => _status = selection.first);
                },
              ),
              const SizedBox(height: 16),
              if (visibleBills.isEmpty)
                Card(
                  child: ListTile(
                    leading: Icon(
                      _status == _ListStatus.completed
                          ? Icons.check_circle_outline
                          : Icons.info_outline,
                    ),
                    title: Text(
                      _status == _ListStatus.completed
                          ? '完了した割り勘はありません'
                          : '進行中の割り勘はありません',
                    ),
                    subtitle: Text(
                      organizer ? '作成した割り勘がここに表示されます' : '参加した割り勘がここに表示されます',
                    ),
                  ),
                ),
              ...visibleBills.map(
                (bill) => _SplitBillTile(
                  bill: bill,
                  onTap: () => _openDetail(bill),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _tabController.index;
    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle(icon: Icons.groups, title: '割り勘一覧'),
        // タブは赤いヘッダーの上ではなく、一覧のカードと同じ明るい面に載せる。
        // 赤地に白文字だと選択中と未選択が見分けにくいため。
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: TabBar(
                controller: _tabController,
                // 選択中は塗りつぶしになるので、下線とタブ間の余白は消す
                indicatorPadding: EdgeInsets.zero,
                splashBorderRadius: BorderRadius.circular(megaPayControlRadius),
                tabs: [
                  Tab(
                    height: 44,
                    // 選択中は塗りつぶしのアイコンにして、色以外の手がかりも足す
                    icon: Icon(
                      selectedIndex == 0 ? Icons.groups : Icons.groups_outlined,
                      size: 20,
                    ),
                    iconMargin: EdgeInsets.zero,
                    text: '集金者',
                  ),
                  Tab(
                    height: 44,
                    icon: Icon(
                      selectedIndex == 1 ? Icons.person : Icons.person_outline,
                      size: 20,
                    ),
                    iconMargin: EdgeInsets.zero,
                    text: '支払者',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
                    Text(snapshot.error.toString(),
                        textAlign: TextAlign.center),
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

          final bills = List<SplitBill>.from(
            snapshot.data ?? const <SplitBill>[],
          )..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return TabBarView(
            controller: _tabController,
            children: [
              _buildRoleList(bills, organizer: true),
              _buildRoleList(bills, organizer: false),
            ],
          );
        },
      ),
    );
  }
}

enum _ListStatus { inProgress, completed }

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
            bill.isRanked
                ? 'ランク別の支払い金額'
                : '1人あたり ${formatMoney(bill.currency, bill.shareAmount)}',
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
