import 'package:flutter/material.dart';

import '../models/payment_request.dart';
import '../services/api_client.dart';
import '../widgets/payment_request_tile.dart';
import 'pay_request_screen.dart';

/// 請求状況の確認画面：自分が請求した／請求された一覧を新しい順に表示する。
class RequestListScreen extends StatefulWidget {
  const RequestListScreen({super.key});

  @override
  State<RequestListScreen> createState() => _RequestListScreenState();
}

/// 請求状況の絞り込み。PaymentRequest.status の値に対応する。
enum _RequestFilter { all, pending, paid, cancelled }

class _RequestListScreenState extends State<RequestListScreen> {
  late Future<List<PaymentRequest>> _future;
  _RequestFilter _filter = _RequestFilter.all;

  @override
  void initState() {
    super.initState();
    _future = ApiClient.instance.fetchPaymentRequests();
  }

  List<PaymentRequest> _applyFilter(List<PaymentRequest> requests) {
    switch (_filter) {
      case _RequestFilter.all:
        return requests;
      case _RequestFilter.pending:
        return requests.where((r) => r.status == 'pending').toList();
      case _RequestFilter.paid:
        return requests.where((r) => r.status == 'paid').toList();
      case _RequestFilter.cancelled:
        return requests.where((r) => r.status == 'cancelled').toList();
    }
  }

  Future<void> _reload() {
    final future = ApiClient.instance.fetchPaymentRequests();
    if (mounted) setState(() => _future = future);
    // エラーは FutureBuilder 側で表示するためここでは握りつぶす
    return future.then((_) {}, onError: (_) {});
  }

  Future<void> _openPayScreen(PaymentRequest request) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PayRequestScreen(initialCode: request.requestCode),
      ),
    );
    await _reload();
  }

  Future<void> _cancel(PaymentRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('請求の取り消し'),
        content: Text('${request.payerName} さんへの請求を取り消しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('やめる'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('取り消す'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ApiClient.instance.cancelPaymentRequest(request.requestCode);
      await _reload();
    } on ApiException catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('請求状況')),
      body: FutureBuilder<List<PaymentRequest>>(
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

          final all = snapshot.data ?? const <PaymentRequest>[];
          final requests = _applyFilter(all);
          return RefreshIndicator(
            onRefresh: _reload,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: SingleChildScrollView(
                        // 状態が4つあり狭い画面では収まらないため横スクロールさせる
                        scrollDirection: Axis.horizontal,
                        child: SegmentedButton<_RequestFilter>(
                          segments: const [
                            ButtonSegment(
                              value: _RequestFilter.all,
                              label: Text('すべて'),
                            ),
                            ButtonSegment(
                              value: _RequestFilter.pending,
                              label: Text('未払い'),
                            ),
                            ButtonSegment(
                              value: _RequestFilter.paid,
                              label: Text('支払い済み'),
                            ),
                            ButtonSegment(
                              value: _RequestFilter.cancelled,
                              label: Text('取り消し済み'),
                            ),
                          ],
                          selected: {_filter},
                          showSelectedIcon: false,
                          onSelectionChanged: (selected) =>
                              setState(() => _filter = selected.first),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (requests.isEmpty)
                            Card(
                              child: ListTile(
                                title: Text(
                                  _filter == _RequestFilter.all
                                      ? 'まだ請求はありません'
                                      : '該当する請求がありません',
                                ),
                                subtitle: _filter == _RequestFilter.all
                                    ? const Text('「請求する」から作成できます')
                                    : null,
                              ),
                            ),
                          ...requests.map(
                            (r) => PaymentRequestTile(
                              request: r,
                              actions: [
                                if (r.isPending && r.isRequestedByMe)
                                  TextButton(
                                    onPressed: () => _cancel(r),
                                    child: const Text('取り消す'),
                                  ),
                                if (r.isPending && !r.isRequestedByMe)
                                  FilledButton(
                                    onPressed: () => _openPayScreen(r),
                                    child: const Text('支払う'),
                                  ),
                              ],
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
