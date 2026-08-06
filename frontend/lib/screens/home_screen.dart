import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../utils/money.dart';
import '../utils/browser_url.dart';
import '../widgets/payment_request_actions.dart';
import '../widgets/transfer_tile.dart';
import 'saved_users_screen.dart';
import 'transfer_history_screen.dart';
import 'transfer_screen.dart';

/// 現在は日本円のみを扱う。デモ用に作られる USD / EUR の残高は表示しない。
const _supportedCurrency = 'JPY';

/// ホームに出す履歴の件数。これを超える分は履歴一覧画面で見る。
const _recentTransferCount = 3;

class _HomeData {
  const _HomeData(this.profile, this.balances, this.transfers);

  final Profile profile;
  final List<Balance> balances;
  final List<TransferRecord> transfers;
}

/// ホーム画面：プロフィール（ユーザーID）・残高一覧・送金履歴を表示する。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<_HomeData> _future;

  @override
  void initState() {
    super.initState();
    removeQueryParameter('split_code');
    _future = _load();
  }

  Future<_HomeData> _load() async {
    final api = ApiClient.instance;
    final results = await Future.wait([
      api.fetchProfile(),
      api.fetchBalances(),
      api.fetchTransfers(),
    ]);
    final balances = (results[1] as List<Balance>)
        .where((b) => b.currency == _supportedCurrency)
        .toList();
    return _HomeData(
      results[0] as Profile,
      balances,
      results[2] as List<TransferRecord>,
    );
  }

  Future<void> _reload() {
    final future = _load();
    if (mounted) {
      setState(() => _future = future);
    }
    // エラーは FutureBuilder 側で表示するためここでは握りつぶす
    return future.then((_) {}, onError: (_) {});
  }

  Future<void> _openTransferScreen(List<Balance> balances) async {
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TransferScreen(balances: balances)),
    );
    if (sent == true && mounted) {
      await _reload();
    }
  }

  Future<void> _openSavedUsers(List<Balance> balances) async {
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SavedUsersScreen(balances: balances)),
    );
    if (sent == true && mounted) await _reload();
  }

  Future<void> _openHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TransferHistoryScreen()),
    );
    await _reload();
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

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ログアウト'),
        content: const Text('ログアウトしますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ログアウト'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await Supabase.instance.client.auth.signOut();
      // 画面遷移は AuthGate が行う
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MegaPay'),
        actions: [
          IconButton(
            tooltip: 'ログアウト',
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
      ),
      body: FutureBuilder<_HomeData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }
          final data = snapshot.data!;
          // 画面が低い端末ではセクション間の余白を詰め、
          // メニュー（ユーザー一覧まで）が一画面に収まりやすいようにする。
          final density =
              ((MediaQuery.sizeOf(context).height - 640) / 260).clamp(0.0, 1.0);
          // アカウント〜残高〜メニューは続けて見せたいので詰める
          final tightGap = 8 + density * 6;
          // 履歴は別のまとまりなので少し離す
          final gap = 12 + density * 12;
          return RefreshIndicator(
            onRefresh: _reload,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                  children: [
                    _ProfileCard(profile: data.profile),
                    SizedBox(height: tightGap),
                    Text('残高', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    ...data.balances.map((b) => _BalanceTile(balance: b)),
                    if (data.balances.isEmpty)
                      const Card(
                        child: ListTile(title: Text('残高がありません')),
                      ),
                    SizedBox(height: tightGap),
                    PaymentRequestActions(
                      balances: data.balances,
                      onChanged: _reload,
                      onTransfer: () => _openTransferScreen(data.balances),
                      onSavedUsers: () => _openSavedUsers(data.balances),
                    ),
                    SizedBox(height: gap),
                    Text(
                      '最近の履歴',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (data.transfers.isEmpty)
                      const Card(
                        child: ListTile(title: Text('まだ送金履歴がありません')),
                      ),
                    ...data.transfers.take(_recentTransferCount).map(
                          (t) => TransferTile(
                            record: t,
                            onSave: () => _saveCounterpart(t),
                          ),
                        ),
                    if (data.transfers.length > _recentTransferCount) ...[
                      const SizedBox(height: 4),
                      OutlinedButton.icon(
                        onPressed: _openHistory,
                        icon: const Icon(Icons.history),
                        label: Text('すべて見る（全 ${data.transfers.length} 件）'),
                      ),
                    ],
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

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile});

  final Profile profile;

  Future<void> _copyUserId(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: profile.userId));
    messenger.showSnackBar(
      const SnackBar(content: Text('ユーザーIDをコピーしました')),
    );
  }

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
            Row(
              children: [
                CircleAvatar(
                  child: Text(
                    profile.displayName.isNotEmpty
                        ? profile.displayName.characters.first
                        : '?',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${profile.displayName} さん',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(profile.email, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'ユーザーID: ${profile.userId}',
                    // monospace は日本語グリフを持たないため、ラベル部分の
                    // フォールバック先に同梱フォントを指定する
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontFamilyFallback: const ['NotoSansJP'],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'ユーザーIDをコピー',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () => _copyUserId(context),
                ),
              ],
            ),
            Text(
              'このIDを相手に伝えると送金を受け取れます',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceTile extends StatefulWidget {
  const _BalanceTile({required this.balance});

  final Balance balance;

  @override
  State<_BalanceTile> createState() => _BalanceTileState();
}

class _BalanceTileState extends State<_BalanceTile> {
  /// 人に見られないよう既定では伏せ、目のボタンで表示を切り替える。
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        // 金額は title に置いて左揃えにし、目のボタンを trailing（右）に置く
        title: Text(
          _visible ? formatYen(widget.balance.amount) : '•••••• 円',
          style: theme.textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        trailing: IconButton(
          tooltip: _visible ? '残高を隠す' : '残高を表示',
          icon: Icon(
            _visible
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
          onPressed: () => setState(() => _visible = !_visible),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('再読み込み'),
            ),
          ],
        ),
      ),
    );
  }
}
