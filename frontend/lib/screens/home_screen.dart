import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../utils/browser_url.dart';
import '../widgets/balance_hero_card.dart';
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
    removeQueryParameter('ranked_split_code');
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

  Future<void> _selectAvatar(Profile profile) async {
    const avatarKeys = [
      'avatar_01',
      'avatar_02',
      'avatar_03',
      'avatar_04',
      'avatar_05',
      'avatar_06',
    ];

    final selectedAvatar = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('プロフィールアイコンを選択'),
          content: SizedBox(
            width: 320,
            child: GridView.builder(
              shrinkWrap: true,
              itemCount: avatarKeys.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemBuilder: (context, index) {
                final avatarKey = avatarKeys[index];
                final selected = avatarKey == profile.avatarKey;

                return InkWell(
                  onTap: () => Navigator.of(dialogContext).pop(avatarKey),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        width: selected ? 3 : 1,
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/avatars/$avatarKey.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('キャンセル'),
            ),
          ],
        );
      },
    );

    if (selectedAvatar == null || selectedAvatar == profile.avatarKey) {
  return;
}

try {
  final updatedProfile =
      await ApiClient.instance.updateAvatar(selectedAvatar);

  if (!mounted) return;

  setState(() {
    _future = _future.then(
      (data) => _HomeData(
        updatedProfile,
        data.balances,
        data.transfers,
      ),
    );
  });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('プロフィールアイコンを変更しました'),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
        ),
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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.currency_exchange,
              size: 28,
              color: megaPayOnBrandColor,
            ),
            const SizedBox(width: 8),
            Text(
              'MegaPay',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: megaPayOnBrandColor,
                    fontFamily: 'NotoSansJP',
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
            ),
          ],
        ),
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
                  // 下端の 96px はボトムバーを置く想定の名残で、実際には
                  // 何も無く空白が伸びて見えていたため詰める。
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    _ProfileGreeting(
                      profile: data.profile,
                      onAvatarTap: () => _selectAvatar(data.profile),
                    ),
                    SizedBox(height: tightGap),
                    // 残高はこの画面の主役。見出しやユーザーIDもカードに
                    // 内包させ、開いた瞬間に「いくらあるか」が目に入るようにする。
                    BalanceHeroCard(
                      balance:
                          data.balances.isEmpty ? null : data.balances.first,
                      userId: data.profile.userId,
                    ),
                    SizedBox(height: gap),
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

/// 画面上部の挨拶行。
///
/// 以前はここに大きな色付きのカードを置き、名前・メール・ユーザーIDを
/// まとめて出していた。しかしプロフィールは毎回確認する情報ではないのに
/// 画面で一番目立ってしまい、肝心の残高が埋もれていた。
/// そのため表示は「アイコン＋名前」だけに絞り、ユーザーIDは残高カード側へ
/// 移した。アイコンを押すと変更できる導線はそのまま残している。
class _ProfileGreeting extends StatelessWidget {
  const _ProfileGreeting({
    required this.profile,
    required this.onAvatarTap,
  });

  final Profile profile;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Tooltip(
          message: 'プロフィールアイコンを変更',
          child: InkWell(
            onTap: onAvatarTap,
            borderRadius: BorderRadius.circular(999),
            child: CircleAvatar(
              radius: 22,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              child: ClipOval(
                child: Image.asset(
                  'assets/avatars/${profile.avatarKey}.png',
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Text(
                        profile.displayName.isNotEmpty
                            ? profile.displayName.characters.first
                            : '?',
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '${profile.displayName} さん',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium,
          ),
        ),
      ],
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
