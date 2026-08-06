import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';

/// 送金・請求の宛先を「ユーザー一覧」から選ぶモーダル。
///
/// [show] でボトムシートを開き、選ばれたユーザーを返す（閉じただけなら null）。
/// 返る [SavedUser] は表示名も持つため、呼び出し側は改めて
/// lookupRecipient で確認する必要がない。
class SavedUserPicker extends StatefulWidget {
  const SavedUserPicker._();

  static Future<RecipientInfo?> show(BuildContext context) {
    return showModalBottomSheet<RecipientInfo>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const SavedUserPicker._(),
    );
  }

  @override
  State<SavedUserPicker> createState() => _SavedUserPickerState();
}

class _SavedUserPickerState extends State<SavedUserPicker> {
  final _searchController = TextEditingController();
  late Future<List<SavedUser>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiClient.instance.fetchSavedUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _retry() {
    setState(() => _future = ApiClient.instance.fetchSavedUsers());
  }

  List<SavedUser> _filter(List<SavedUser> users) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return users;
    return users
        .where((u) =>
            u.userId.toLowerCase().contains(query) ||
            u.displayName.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        // 検索時にキーボードで隠れないよう、その分だけ持ち上げる
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'ユーザー一覧から選ぶ',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '名前・ユーザーIDで絞り込む',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(child: _buildList(theme)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(ThemeData theme) {
    return FutureBuilder<List<SavedUser>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          final message = snapshot.error is ApiException
              ? (snapshot.error as ApiException).message
              : 'ユーザー一覧を取得できませんでした';
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 40),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('再読み込み'),
                ),
              ],
            ),
          );
        }

        final all = snapshot.data ?? const <SavedUser>[];
        if (all.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: Text(
                'まだユーザーが保存されていません。\n'
                '履歴の相手を保存すると、ここから選べます。',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final matched = _filter(all);
        if (matched.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('該当するユーザーがいません')),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 8),
          itemCount: matched.length,
          itemBuilder: (context, index) {
            final user = matched[index];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.secondaryContainer,
                foregroundColor: theme.colorScheme.onSecondaryContainer,
                child: Text(
                  user.displayName.isNotEmpty
                      ? user.displayName.characters.first
                      : '?',
                ),
              ),
              title: Text(
                user.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                user.userId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.of(context).pop(user),
            );
          },
        );
      },
    );
  }
}
