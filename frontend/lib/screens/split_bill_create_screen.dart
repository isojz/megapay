import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/split_bill.dart';
import '../services/api_client.dart';
import '../utils/money.dart';
import '../utils/browser_url.dart';
import '../utils/weighted_split.dart';
import '../widgets/remainder_roulette_editor.dart';
import '../widgets/weighted_split_editor.dart';
import 'split_bill_detail_screen.dart';
import '../utils/input_formatters.dart';

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
  bool _useRemainderRoulette = false;

  /// 分け方。既定は等分で、必要なときだけ傾斜に切り替える。
  _SplitMode _mode = _SplitMode.even;

  /// 傾斜のグループ設定（傾斜を選んだときだけ使う）
  final _groupsNotifier = ValueNotifier<List<SplitGroup>>(const [
    SplitGroup(name: '多めに払う人', count: 1, weight: 1.5),
    SplitGroup(name: '少なめに払う人', count: 1, weight: 1.0),
  ]);

  /// 割り振りの単位。きりのよい金額にしやすいよう既定を 500 円にする。
  final _unitNotifier = ValueNotifier<int>(500);

  /// 金額を自動再配分するときも維持するグループ。
  final _lockedGroupsNotifier = ValueNotifier<Set<int>>(<int>{});

  /// 集金者（自分）の扱い。null は未選択、-1 は「加わらない」。
  final _organizerGroupNotifier = ValueNotifier<int?>(null);

  /// 合計金額の入力欄の現在値（傾斜の割り振り表示に使う）
  int? get _enteredAmount => int.tryParse(_amountController.text.trim());

  @override
  void dispose() {
    _groupsNotifier.dispose();
    _unitNotifier.dispose();
    _lockedGroupsNotifier.dispose();
    _organizerGroupNotifier.dispose();
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

  /// 傾斜つきの割り勘を作成する。
  ///
  /// 割り振りの計算はこの画面（フロント）で完結している。
  /// 作成後のリンク発行・保存は別途実装されるため、ここでは確定した割り振りを
  /// 確認できる状態にして、結果を呼び出し元へ返すところまでを行う。
  Future<void> _createWeighted() async {
    final amount = _enteredAmount;
    final groups = _groupsNotifier.value;
    final unit = _unitNotifier.value;
    final organizerSelection = _organizerGroupNotifier.value;
    if (organizerSelection == null) {
      _showError('集金者（あなた）の扱いを選択してください');
      return;
    }
    final organizerIndex = organizerSelection == organizerNotParticipatingIndex
        ? null
        : organizerSelection >= 0 && organizerSelection < groups.length
            ? organizerSelection
            : null;
    if (organizerSelection != organizerNotParticipatingIndex &&
        organizerIndex == null) {
      _showError('集金者の役職を選び直してください');
      return;
    }
    final error =
        validateSplitGroups(groups, organizerGroupIndex: organizerIndex);
    if (amount == null || amount <= 0) {
      _showError('合計金額を入力してください');
      return;
    }
    if (error != null) {
      _showError(error);
      return;
    }

    final title = _titleController.text.trim();
    final result = calculateWeightedSplit(
      totalAmount: amount,
      groups: groups,
      unit: unit,
      organizerGroupIndex: organizerIndex,
    );
    if (result.totalCount > _maxParticipants - 1) {
      _showError('支払い者は${_maxParticipants - 1}人までです');
      return;
    }
    if (result.hasZeroAmount) {
      _showError('0円のグループがあります。割り振り単位を小さくしてください');
      return;
    }

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
            if (result.includesOrganizer) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(child: Text('請求する分（${result.payerCount}人）')),
                  Text(
                    formatMoney(_currency, result.collectAmount.toString()),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Text(
                'あなたの負担 '
                '${formatMoney(_currency, result.organizerAmount.toString())}'
                'は請求されません',
                style: const TextStyle(fontSize: 12),
              ),
            ],
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

    // 集金者は自分に請求しないため、ランク（請求先の枠）から除く。
    // 端数の 1 円を負担する枠も、集金者がいる場合は集金者が引き受ける。
    final ranks = <Map<String, dynamic>>[];
    for (final group in result.groups) {
      final label = group.group.name.trim();
      // 1 円多く払う人数（集金者がいるグループなら集金者が 1 人分を引き受ける）
      final oddYenCount = (group.extraExtraCount - group.organizerCount)
          .clamp(0, group.payerCount);
      final normalCount = group.payerCount - oddYenCount;
      if (normalCount > 0) {
        ranks.add({
          'label': label,
          'amount': group.amountWithExtra.toString(),
          'capacity': normalCount,
        });
      }
      if (oddYenCount > 0) {
        ranks.add({
          'label': '$label（端数調整）',
          'amount': group.amountWithExtraPlusOne.toString(),
          'capacity': oddYenCount,
        });
      }
    }

    await _persistRankedBill(
      title: title.isEmpty ? _defaultTitle : title,
      ranks: ranks,
    );
  }

  /// 個人名は作成確定前の表示に使い、既存APIには金額別の枠として保存する。
  Future<void> _createRemainderRoulette(
    RemainderRouletteSubmission submission,
  ) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final result = submission.result;
    final external = [
      for (var index = 0; index < result.payments.length; index++)
        if (index != submission.organizerIndex)
          (index: index, amount: result.payments[index]),
    ];
    if (external.isEmpty) {
      _showError('請求する相手が1人以上必要です');
      return;
    }
    if (external.any((payment) => payment.amount <= 0)) {
      _showError('0円の参加者がいます。キリよく割る単位を小さくしてください');
      return;
    }

    final ranks = <Map<String, dynamic>>[];
    final winnerIndex = result.winnerIndex;
    final externalWinner = winnerIndex == null
        ? <({int index, int amount})>[]
        : external.where((payment) => payment.index == winnerIndex).toList();
    final regular = winnerIndex == null
        ? external
        : external.where((payment) => payment.index != winnerIndex).toList();
    if (externalWinner.isNotEmpty) {
      final name = submission.names[externalWinner.first.index].trim();
      final shortName = name.length > 20 ? name.substring(0, 20) : name;
      ranks.add({
        'label': '端数担当：$shortName',
        'amount': externalWinner.first.amount.toString(),
        'capacity': 1,
      });
    }
    if (regular.isNotEmpty) {
      ranks.add({
        'label': winnerIndex == null ? '全員同額' : '基本金額',
        'amount': regular.first.amount.toString(),
        'capacity': regular.length,
      });
    }

    final title = _titleController.text.trim();
    await _persistRankedBill(
      title: title.isEmpty ? _defaultTitle : title,
      ranks: ranks,
    );
  }

  Future<void> _persistRankedBill({
    required String title,
    required List<Map<String, dynamic>> ranks,
  }) async {
    setState(() => _isCreating = true);
    try {
      final bill = await ApiClient.instance.createRankedSplitBill(
        title: title,
        currency: _currency,
        ranks: ranks,
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
                    inputFormatters: integerAmountInputFormatters,
                    decoration: const InputDecoration(
                      labelText: '合計金額',
                      suffixText: '円',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (_useRemainderRoulette) {
                        setState(() => _useRemainderRoulette = false);
                      }
                    },
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
                      setState(() {
                        _mode = selection.first;
                        _useRemainderRoulette = false;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  if (_mode == _SplitMode.even) ...[
                    Text('参加者', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _countController,
                      keyboardType: TextInputType.number,
                      inputFormatters: integerAmountInputFormatters,
                      decoration: const InputDecoration(
                        labelText: '人数',
                        suffixText: '人',
                        helperText: '自分を含めた人数。端数は切り上げます',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        if (_useRemainderRoulette) {
                          setState(() => _useRemainderRoulette = false);
                        }
                      },
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
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _amountController,
                      builder: (context, amountValue, _) =>
                          ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _countController,
                        builder: (context, countValue, _) {
                          final amount = int.tryParse(amountValue.text.trim());
                          final count = int.tryParse(countValue.text.trim());
                          if (count == null ||
                              count < 2 ||
                              count > _maxParticipants) {
                            return const SizedBox.shrink();
                          }
                          return RemainderRouletteEditor(
                            currency: _currency,
                            totalAmount: amount,
                            participantCount: count,
                            rouletteActive: _useRemainderRoulette,
                            isCreating: _isCreating,
                            onCreate: _createRemainderRoulette,
                            onRouletteActiveChanged: (active) {
                              if (mounted && _useRemainderRoulette != active) {
                                setState(() => _useRemainderRoulette = active);
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ] else if (_mode == _SplitMode.weighted)
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _amountController,
                      builder: (context, amountValue, _) {
                        final amount = int.tryParse(amountValue.text.trim());
                        return ValueListenableBuilder<List<SplitGroup>>(
                          valueListenable: _groupsNotifier,
                          builder: (context, groups, _) {
                            return ValueListenableBuilder<int>(
                              valueListenable: _unitNotifier,
                              builder: (context, unit, _) =>
                                  ValueListenableBuilder<int?>(
                                valueListenable: _organizerGroupNotifier,
                                builder: (context, organizerIndex, _) =>
                                    ValueListenableBuilder<Set<int>>(
                                  valueListenable: _lockedGroupsNotifier,
                                  builder: (context, lockedGroups, _) =>
                                      WeightedSplitEditor(
                                    currency: _currency,
                                    totalAmount: amount,
                                    groups: groups,
                                    onChanged: (value) =>
                                        _groupsNotifier.value = value,
                                    unit: unit,
                                    onUnitChanged: (value) =>
                                        _unitNotifier.value = value,
                                    organizerGroupIndex: organizerIndex,
                                    onOrganizerGroupChanged: (value) =>
                                        _organizerGroupNotifier.value = value,
                                    lockedGroupIndices: lockedGroups,
                                    onLockedGroupIndicesChanged: (value) =>
                                        _lockedGroupsNotifier.value = value,
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  if (!_useRemainderRoulette) ...[
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
                      label: Text(
                        _mode == _SplitMode.weighted
                            ? '傾斜つき割り勘リンクを作成'
                            : '割り勘を作成',
                      ),
                    ),
                  ],
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
            '${bill.isRanked ? '選択した区分に応じた金額' : formatMoney(bill.currency, bill.shareAmount)}'
            ' の請求が届きます。',
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
