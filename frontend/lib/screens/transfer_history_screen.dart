import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../widgets/transfer_tile.dart';
import '../widgets/app_bar_title.dart';

/// 履歴一覧画面：送金・受取の履歴を新しい順にまとめて表示する。
///
/// ホーム画面には直近数件だけを出し、全件はこの画面で見る。
class TransferHistoryScreen extends StatefulWidget {
  const TransferHistoryScreen({super.key});

  @override
  State<TransferHistoryScreen> createState() => _TransferHistoryScreenState();
}

enum _HistoryFilter { all, sent, received }

class _TransferHistoryScreenState extends State<TransferHistoryScreen> {
  final _searchController = TextEditingController();
  late Future<List<TransferRecord>> _future;
  _HistoryFilter _filter = _HistoryFilter.all;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = ApiClient.instance.fetchTransfers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() {
    final future = ApiClient.instance.fetchTransfers();
    if (mounted) setState(() => _future = future);
    // エラーは FutureBuilder 側で表示するためここでは握りつぶす
    return future.then((_) {}, onError: (_) {});
  }

  Future<void> _saveCounterpart(TransferRecord record) async {
    try {
      await ApiClient.instance.saveUser(record.counterpartUserId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${record.counterpartName} さんを保存しました')),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  List<TransferRecord> _applyFilter(List<TransferRecord> records) {
    final byDirection = switch (_filter) {
      _HistoryFilter.all => records,
      _HistoryFilter.sent => records.where((r) => r.isSent).toList(),
      _HistoryFilter.received => records.where((r) => !r.isSent).toList(),
    };

    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return byDirection;

    // 相手の名前とユーザーIDのどちらでも引けるようにする
    return byDirection
        .where((r) =>
            r.counterpartName.toLowerCase().contains(query) ||
            r.counterpartUserId.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle(icon: Icons.history, title: '履歴一覧'),
      ),
      body: FutureBuilder<List<TransferRecord>>(
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

          final all = snapshot.data ?? const <TransferRecord>[];
          final records = _applyFilter(all);
          return RefreshIndicator(
            onRefresh: _reload,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          labelText: '相手を検索',
                          hintText: '名前・ユーザーIDで絞り込む',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'クリア',
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _query = '');
                                  },
                                ),
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (value) => setState(() => _query = value),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: SegmentedButton<_HistoryFilter>(
                        segments: const [
                          ButtonSegment(
                            value: _HistoryFilter.all,
                            label: Text('すべて'),
                          ),
                          ButtonSegment(
                            value: _HistoryFilter.sent,
                            label: Text('送金'),
                          ),
                          ButtonSegment(
                            value: _HistoryFilter.received,
                            label: Text('受取'),
                          ),
                        ],
                        selected: {_filter},
                        onSelectionChanged: (selected) =>
                            setState(() => _filter = selected.first),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (records.isEmpty)
                            const Card(
                              child: ListTile(title: Text('該当する履歴がありません')),
                            ),
                          ...records.map(
                            (r) => TransferTile(
                              record: r,
                              onSave: () => _saveCounterpart(r),
                            ),
                          ),
                        ],
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
