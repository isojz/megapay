import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../models/payment_request.dart';
import '../services/api_client.dart';
import '../utils/money.dart';
import '../widgets/saved_user_picker.dart';

/// 請求作成画面：相手のユーザーIDを指定して請求し、支払い用の請求コードを発行する。
class RequestCreateScreen extends StatefulWidget {
  const RequestCreateScreen({super.key, this.initialPayer});

  /// ユーザー一覧から開いたときに、請求先をあらかじめ埋めておく
  final RecipientInfo? initialPayer;

  @override
  State<RequestCreateScreen> createState() => _RequestCreateScreenState();
}

class _RequestCreateScreenState extends State<RequestCreateScreen> {
  static const _currency = 'JPY';

  final _formKey = GlobalKey<FormState>();
  final _payerController = TextEditingController();
  final _amountController = TextEditingController();
  final _memoController = TextEditingController();

  RecipientInfo? _verifiedPayer;
  bool _isLookingUp = false;
  bool _isCreating = false;

  /// 自分自身への請求を送信前に弾くために保持する。
  String? _myUserId;

  @override
  void initState() {
    super.initState();
    final payer = widget.initialPayer;
    if (payer != null) {
      _payerController.text = payer.userId;
      _verifiedPayer = payer;
    }
    _loadMyUserId();
  }

  Future<void> _loadMyUserId() async {
    try {
      final profile = await ApiClient.instance.fetchProfile();
      if (mounted) setState(() => _myUserId = profile.userId);
    } on ApiException {
      // 取得できなくてもサーバー側で弾かれるため、ここでは何もしない
    }
  }

  /// 入力されたユーザーIDが自分自身かどうか。
  /// ユーザーIDは大文字で扱われるため、比較時に揃える。
  bool _isMyself(String userId) {
    final myUserId = _myUserId;
    return myUserId != null &&
        userId.trim().toUpperCase() == myUserId.toUpperCase();
  }

  @override
  void dispose() {
    _payerController.dispose();
    _amountController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  /// ユーザー一覧から請求先を選ぶ。保存済みユーザーは表示名も分かっているため、
  /// 選んだ時点で確認済みとして扱う。
  Future<void> _pickFromSavedUsers() async {
    final picked = await SavedUserPicker.show(context);
    if (picked == null || !mounted) return;
    setState(() {
      _payerController.text = picked.userId;
      _verifiedPayer = picked;
    });
  }

  /// 請求先のユーザーIDから相手を検索して表示名を確認する。
  Future<RecipientInfo?> _lookupPayer() async {
    final payerId = _payerController.text.trim();

    if (payerId.isEmpty) {
      _showError('請求先のユーザーIDを入力してください');
      return null;
    }

    if (_isMyself(payerId)) {
      _showError('自分自身には請求できません');
      return null;
    }

    setState(() => _isLookingUp = true);

    try {
      final payer = await ApiClient.instance.lookupRecipient(payerId);

      if (mounted) {
        setState(() => _verifiedPayer = payer);
      }

      return payer;
    } on ApiException catch (err) {
      if (mounted) {
        setState(() => _verifiedPayer = null);
      }

      _showError(err.message);
      return null;
    } finally {
      if (mounted) {
        setState(() => _isLookingUp = false);
      }
    }
  }

  Future<void> _create() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // 請求先が未確認ならここで確認する
    final payer = _verifiedPayer ?? await _lookupPayer();

    if (payer == null || !mounted) return;

    const currency = _currency;
    final amount = _amountController.text.trim();
    final memo = _memoController.text.trim();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('請求内容の確認'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ConfirmRow(
              label: '請求先',
              value: '${payer.displayName} さん',
            ),
            _ConfirmRow(
              label: 'ユーザーID',
              value: payer.userId,
            ),
            _ConfirmRow(
              label: '金額',
              value: formatMoney(currency, amount),
            ),
            if (memo.isNotEmpty)
              _ConfirmRow(
                label: 'メモ',
                value: memo,
              ),
            const SizedBox(height: 8),
            const Text(
              '請求コードが発行されます。'
              '相手がコードを入力すると支払いが完了します。',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('請求する'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isCreating = true);

    try {
      final request = await ApiClient.instance.createPaymentRequest(
        payerUserId: payer.userId,
        currency: currency,
        amount: amount,
        memo: memo.isEmpty ? null : memo,
      );

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) => _RequestCreatedDialog(
          request: request,
        ),
      );

      if (!mounted) return;

      Navigator.of(context).pop();
    } on ApiException catch (err) {
      _showError(err.message);
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('請求'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '請求先',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _payerController,
                          decoration: InputDecoration(
                            labelText: '相手のユーザーID',
                            hintText: 'MP-12345678',
                            hintStyle: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.45),
                            ),
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (_) {
                            if (_verifiedPayer != null) {
                              setState(() => _verifiedPayer = null);
                            }
                          },
                          validator: (value) {
                            final userId = value?.trim() ?? '';

                            if (userId.isEmpty) {
                              return '請求先のユーザーIDを入力してください';
                            }

                            if (_isMyself(userId)) {
                              return '自分自身には請求できません';
                            }

                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 56,
                        child: OutlinedButton(
                          onPressed: _isLookingUp ? null : _lookupPayer,
                          child: _isLookingUp
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('確認'),
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _pickFromSavedUsers,
                      icon: const Icon(Icons.people_outline),
                      label: const Text('ユーザー一覧から選ぶ'),
                    ),
                  ),
                  if (_verifiedPayer != null)
                    Card(
                      color: Colors.green.shade50,
                      child: ListTile(
                        leading: const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                        ),
                        title: Text(
                          '${_verifiedPayer!.displayName} さん',
                        ),
                        subtitle: Text(_verifiedPayer!.userId),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    '金額',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: '請求金額',
                      suffixText: '円',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final amount = double.tryParse(
                        value?.trim() ?? '',
                      );

                      if (amount == null || amount <= 0) {
                        return '正しい金額を入力してください';
                      }

                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _memoController,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'メモ（任意）',
                      hintText: '例: 飲み会代',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _isCreating ? null : _create,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                      ),
                    ),
                    icon: _isCreating
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.receipt_long),
                    label: const Text('請求する'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 請求作成後に、発行された請求コードを大きく表示してコピーできるようにする。
class _RequestCreatedDialog extends StatelessWidget {
  const _RequestCreatedDialog({
    required this.request,
  });

  final PaymentRequest request;

  Future<void> _copyCode(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    await Clipboard.setData(
      ClipboardData(text: request.requestCode),
    );

    messenger.showSnackBar(
      const SnackBar(
        content: Text('請求コードをコピーしました'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      icon: const Icon(
        Icons.receipt_long,
        color: Colors.green,
        size: 48,
      ),
      title: const Text('請求を作成しました'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${request.payerName} さんへ '
            '${formatMoney(request.currency, request.amount)} を請求しました。',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            '請求コード',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          SelectableText(
            request.requestCode,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => _copyCode(context),
            icon: const Icon(
              Icons.copy,
              size: 18,
            ),
            label: const Text('コードをコピー'),
          ),
          const SizedBox(height: 12),
          Text(
            'このコードを相手に伝えてください。'
            '相手がコードを入力して支払うと請求が成立します。',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
      ],
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
