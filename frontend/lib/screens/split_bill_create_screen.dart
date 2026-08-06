import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/split_bill.dart';
import '../services/api_client.dart';
import '../utils/money.dart';
import '../utils/browser_url.dart';
import '../utils/weighted_split.dart';
import '../widgets/weighted_split_editor.dart';
import 'split_bill_detail_screen.dart';

/// 割り勘は日本円のみ対応する。
const _currency = 'JPY';

/// 件名を省略した場合に使う既定のイベント名。
const _defaultTitle = '割り勘';

/// 分け方。既定は等分で、傾斜はグループごとに重みを設定する。
enum _SplitMode { even, weighted }

/// 割り勘作成画面：合計金額と人数を入力して割り勘を登録し、参加用の請求コードを発行する。
/// 発行したコードを参加者が入力すると、割り勘後の金額が自動で請求される。
class SplitBillCreateScreen extends StatefulWidget {
  const SplitBillCreateScreen({super.key});

  @override
  State<SplitBillCreateScreen> createState() => _SplitBillCreateScreenState();
}

class _SplitBillCreateScreenState extends State<SplitBillCreateScreen> {
  /// 1件の割り勘に参加できる人数の上限（バックエンド側の制限に合わせる）。
  static const _maxParticipants = 100;

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _countController = TextEditingController();

  bool _isCreating = false;

  /// 分け方。既定は等分で、必要なときだけ傾斜に切り替える。
  _SplitMode _mode = _SplitMode.even;

  /// 傾斜のグループ設定（傾斜を選んだときだけ使う）
  List<SplitGroup> _groups = const [
    SplitGroup(name: '多めに払う人', count: 1, weight: 1.5),
    SplitGroup(name: '少なめに払う人', count: 1, weight: 1.0),
  ];

  /// 合計金額の入力欄の現在値（傾斜の割り振り表示に使う）
  int? get _enteredAmount => int.tryParse(_amountController.text.trim());

  @override
  void initState() {
    super.initState();
    // 金額を打つたびに傾斜の割り振りを計算し直す
    _amountController.addListener(_onAmountChanged);
  }

  void _onAmountChanged() {
    if (_mode == _SplitMode.weighted && mounted) setState(() {});
  }

  @override
  void dispose() {
    _amountController.removeListener(_onAmountChanged);
    _titleController.dispose();
    _amountController.dispose();
    _countController.dispose();
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

  Future<void> _create() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_mode == _SplitMode.weighted) {
      await _createWeighted();
      return;
    }

    final title = _titleController.text.trim();
    final total = _amountController.text.trim();
    final count = int.parse(_countController.text.trim());

    setState(() => _isCreating = true);
    try {
      final bill = await ApiClient.instance.createSplitBill(
        title: title.isEmpty ? _defaultTitle : title,
        currency: _currency,
        totalAmount: total,
        participantCount: count,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _SplitBillCreatedDialog(bill: bill),
      );
      if (!mounted) return;
      // 作成後はそのままグループ画面へ移動し、参加状況を確認できるようにする
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SplitBillDetailScreen(billCode: bill.billCode),
        ),
      );
    } on ApiException catch (err) {
      _showError(err.message);
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _createRankedTest() async {
    final count = int.tryParse(_countController.text.trim());
    if (count == null || count < 2 || count > _maxParticipants) {
      _showError('参加人数は2〜$_maxParticipants人で入力してください');
      return;
    }
    final title = _titleController.text.trim();
    setState(() => _isCreating = true);
    try {
      final bill = await ApiClient.instance.createRankedSplitBillTest(
        title: title.isEmpty ? 'ランク別割り勘（テスト）' : title,
        participantCount: count,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _SplitBillCreatedDialog(bill: bill),
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SplitBillDetailScreen(billCode: bill.billCode),
        ),
      );
    } on ApiException catch (err) {
      _showError(err.message);
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }

/// 傾斜つきの割り勘を作成する。
  ///
  /// 割り振りの計算はこの画面（フロント）で完結している。
  /// 作成後のリンク発行・保存は別途実装されるため、ここでは確定した割り振りを
  /// 確認できる状態にして、結果を呼び出し元へ返すところまでを行う。
  Future<void> _createWeighted() async {
    final amount = _enteredAmount;
    final error = validateSplitGroups(_groups);
    if (amount == null || amount <= 0) {
      _showError('合計金額を入力してください');
      return;
    }
    if (error != null) {
      _showError(error);
      return;
    }

    final title = _titleController.text.trim();
    final result = calculateWeightedSplit(totalAmount: amount, groups: _groups);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('割り振りの確認'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.isEmpty ? _defaultTitle : title),
            const SizedBox(height: 12),
            for (final group in result.groups)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${group.group.name}（${group.group.count}人）',
                      ),
                    ),
                    Text(
                      formatMoney(_currency, group.totalAmount.toString()),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            const Divider(),
            Row(
              children: [
                Expanded(child: Text('合計 ${result.totalCount} 人')),
                Text(
                  formatMoney(_currency, result.totalAmount.toString()),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('この割り振りで作成'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // TODO(team): 傾斜つき割り勘の作成・リンク発行はここに実装する。
    //   result（グループごとの金額と合計）と title をそのまま渡せばよい。
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('割り勘')),
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
                  TextFormField(
                    controller: _titleController,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: '件名（任意）',
                      hintText: '例: 飲み会',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('金額', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: '合計金額',
                      suffixText: '円',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final amount = int.tryParse(value?.trim() ?? '');
                      if (amount == null || amount <= 0) {
                        return '正しい金額を入力してください';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  Text('分け方', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SegmentedButton<_SplitMode>(
                    segments: const [
                      ButtonSegment(
                        value: _SplitMode.even,
                        icon: Icon(Icons.balance),
                        label: Text('等分'),
                      ),
                      ButtonSegment(
                        value: _SplitMode.weighted,
                        icon: Icon(Icons.tune),
                        label: Text('傾斜をつける'),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (selection) {
                      setState(() => _mode = selection.first);
                    },
                  ),
                  const SizedBox(height: 16),
                  if (_mode == _SplitMode.even) ...[
                    Text('参加者',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _countController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: '人数',
                        suffixText: '人',
                        helperText: '自分を含めた人数。端数は切り上げます',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        // 傾斜のときはこの欄を使わないので検証しない
                        if (_mode != _SplitMode.even) return null;
                        final count = int.tryParse(value?.trim() ?? '');
                        if (count == null || count < 2) {
                          return '2以上の人数を入力してください';
                        }
                        if (count > _maxParticipants) {
                          return '人数は$_maxParticipants人までです';
                        }
                        return null;
                      },
                    ),
                  ] else
                    WeightedSplitEditor(
                      currency: _currency,
                      totalAmount: _enteredAmount,
                      groups: _groups,
                      onChanged: (groups) => setState(() => _groups = groups),
                    ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _isCreating ? null : _create,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: _isCreating
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.call_split),
                    label: const Text('割り勘を作成'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _isCreating ? null : _createRankedTest,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: const Icon(Icons.workspace_premium_outlined),
                    label: const Text('ランクごとのリンク作成（テスト）'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'テスト設定: Aランク 5,000円 / Bランク 3,000円 / Cランク 1,000円',
                    textAlign: TextAlign.center,
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

/// 作成した割り勘の参加用コードを大きく表示してコピーできるようにする。
class _SplitBillCreatedDialog extends StatelessWidget {
  const _SplitBillCreatedDialog({required this.bill});

  final SplitBill bill;

  Future<void> _copyCode(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: bill.billCode));
    messenger.showSnackBar(
      const SnackBar(content: Text('請求コードをコピーしました')),
    );
  }

  String get _paymentLink => buildSplitBillPaymentLink(
        bill.billCode,
        ranked: bill.isRanked,
      );

  Future<void> _copyLink(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: _paymentLink));
    messenger.showSnackBar(
      const SnackBar(content: Text('支払いリンクをコピーしました')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      scrollable: true,
      icon: const Icon(Icons.call_split, color: Colors.green, size: 48),
      title: const Text('割り勘を作成しました'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            bill.isRanked
                ? '${bill.title}\n${bill.participantCount}人・ランク別割り勘'
                : '${bill.title}\n'
                    '合計 ${formatMoney(bill.currency, bill.totalAmount)} を'
                    '${bill.participantCount}人で割り勘します。',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(bill.isRanked ? '支払いランク' : '1人あたり',
              style: theme.textTheme.bodySmall),
          Text(
            bill.isRanked
                ? bill.ranks
                    .map((rank) =>
                        '${rank.label} ${formatMoney(bill.currency, rank.amount)}')
                    .join(' / ')
                : formatMoney(bill.currency, bill.shareAmount),
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Divider(height: 32),
          Text('請求コード', style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          SelectableText(
            bill.billCode,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => _copyCode(context),
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('コードをコピー'),
          ),
          const SizedBox(height: 20),
          Text('支払いリンク', style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          SelectableText(
            _paymentLink,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => _copyLink(context),
            icon: const Icon(Icons.link, size: 18),
            label: const Text('リンクをコピー'),
          ),
          const SizedBox(height: 12),
          Text(
            'このコードを参加者に伝えてください。'
            '参加者が「割り勘に参加」でコードを入力すると、'
            '${formatMoney(bill.currency, bill.shareAmount)} の請求が届きます。',
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
