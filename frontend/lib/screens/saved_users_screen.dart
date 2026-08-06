import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import 'request_create_screen.dart';
import 'transfer_screen.dart';

class SavedUsersScreen extends StatefulWidget {
  const SavedUsersScreen({super.key, required this.balances});

  final List<Balance> balances;

  @override
  State<SavedUsersScreen> createState() => _SavedUsersScreenState();
}

class _SavedUsersScreenState extends State<SavedUsersScreen> {
  final _searchController = TextEditingController();
  late Future<List<SavedUser>> _future;
  RecipientInfo? _searchResult;
  bool _searching = false;
  bool _saving = false;

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

  void _reload() => setState(
        () => _future = ApiClient.instance.fetchSavedUsers(),
      );

  void _showError(Object error) {
    final message = error is ApiException ? error.message : error.toString();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _search() async {
    final userId = _searchController.text.trim();
    if (userId.isEmpty) {
      _showError('ユーザーIDを入力してください');
      return;
    }
    setState(() => _searching = true);
    try {
      final result = await ApiClient.instance.lookupRecipient(userId);
      if (mounted) setState(() => _searchResult = result);
    } catch (error) {
      if (mounted) setState(() => _searchResult = null);
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _save(RecipientInfo user) async {
    setState(() => _saving = true);
    try {
      await ApiClient.instance.saveUser(user.userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${user.displayName} さんを保存しました')),
      );
      _reload();
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sendTo(RecipientInfo user) async {
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TransferScreen(
          balances: widget.balances,
          initialRecipient: user,
        ),
      ),
    );
    if (sent == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _requestFrom(RecipientInfo user) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RequestCreateScreen(initialPayer: user),
      ),
    );
  }

  /// 相手を選んだあとに、送金と請求のどちらを行うかを選ぶ。
  Future<void> _selectAction(RecipientInfo user) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('${user.displayName} さん'),
              subtitle: Text(user.userId),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.send_outlined),
              title: const Text('送金する'),
              subtitle: const Text('この相手にお金を送る'),
              onTap: () => Navigator.of(context).pop('send'),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('請求する'),
              subtitle: const Text('この相手に支払いをお願いする'),
              onTap: () => Navigator.of(context).pop('request'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'send') {
      await _sendTo(user);
    } else {
      await _requestFrom(user);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ユーザー一覧')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('ユーザーIDから検索',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        labelText: 'ユーザーID',
                        hintText: 'MP-12345678',
                        hintStyle: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.45),
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: '検索',
                    onPressed: _searching ? null : _search,
                    icon: _searching
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search),
                  ),
                ],
              ),
              if (_searchResult != null) ...[
                const SizedBox(height: 8),
                _UserTile(
                  user: _searchResult!,
                  onSelect: () => _selectAction(_searchResult!),
                  trailing: IconButton(
                    tooltip: '保存',
                    onPressed: _saving ? null : () => _save(_searchResult!),
                    icon: const Icon(Icons.bookmark_add_outlined),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Text('保存済みユーザー', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              FutureBuilder<List<SavedUser>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return ListTile(
                      leading: const Icon(Icons.error_outline),
                      title: Text(snapshot.error.toString()),
                      trailing: IconButton(
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh),
                      ),
                    );
                  }
                  final users = snapshot.data!;
                  if (users.isEmpty) {
                    return const Card(
                      child: ListTile(title: Text('保存済みユーザーはいません')),
                    );
                  }
                  return Column(
                    children: users
                        .map((user) => _UserTile(
                              user: user,
                              onSelect: () => _selectAction(user),
                            ))
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user, required this.onSelect, this.trailing});

  final RecipientInfo user;

  /// タップ時に送金・請求の選択肢を出す
  final VoidCallback onSelect;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text(
            user.displayName.isEmpty ? '?' : user.displayName.characters.first,
          ),
        ),
        title: Text('${user.displayName} さん'),
        subtitle: Text(user.userId),
        trailing: trailing ?? const Icon(Icons.chevron_right),
        onTap: onSelect,
      ),
    );
  }
}
