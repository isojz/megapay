import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/money.dart';
import '../utils/weighted_split.dart';

/// 傾斜配分の入力と結果表示をまとめたウィジェット。
///
/// グループ（名前・人数・1人あたり金額）を編集すると、その場で配分結果が更新される。
/// 合計金額は入力額とかならず一致する。
class WeightedSplitEditor extends StatelessWidget {
  const WeightedSplitEditor({
    super.key,
    required this.currency,
    required this.totalAmount,
    required this.groups,
    required this.onChanged,
    required this.unit,
    required this.onUnitChanged,
    required this.organizerGroupIndex,
    required this.onOrganizerGroupChanged,
    required this.lockedGroupIndices,
    required this.onLockedGroupIndicesChanged,
  });

  final String currency;

  /// 入力済みの合計金額。未入力・不正な場合は null（結果は出さない）
  final int? totalAmount;

  final List<SplitGroup> groups;
  final ValueChanged<List<SplitGroup>> onChanged;

  /// 割り振りの単位（1 / 100 / 500 / 1000 円）
  final int unit;
  final ValueChanged<int> onUnitChanged;

  /// 集金者（自分）が属するグループ。null なら割り勘に加わらない。
  final int? organizerGroupIndex;
  final ValueChanged<int?> onOrganizerGroupChanged;
  final Set<int> lockedGroupIndices;
  final ValueChanged<Set<int>> onLockedGroupIndicesChanged;

  void _updateAt(int index, SplitGroup group) {
    final next = [...groups];
    next[index] = group;
    onChanged(next);
  }

  void _removeAt(int index) {
    final next = [...groups]..removeAt(index);
    onLockedGroupIndicesChanged({
      for (final locked in lockedGroupIndices)
        if (locked < index) locked else if (locked > index) locked - 1,
    });
    if (organizerGroupIndex == index) {
      onOrganizerGroupChanged(null);
    } else if (organizerGroupIndex != null && organizerGroupIndex! > index) {
      onOrganizerGroupChanged(organizerGroupIndex! - 1);
    }
    onChanged(next);
  }

  void _add() {
    // 直前のグループより 1 段軽い重みを初期値にする
    final lastWeight = groups.isEmpty ? 1.0 : groups.last.weight;
    final weight = lastWeight > 0.5 ? lastWeight - 0.5 : 0.5;
    onChanged([
      ...groups,
      SplitGroup(name: '役職${groups.length + 1}', count: 1, weight: weight),
    ]);
  }

  Future<void> _selectPreset(BuildContext context) async {
    final preset = await showModalBottomSheet<SplitPreset>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('利用シーンから選ぶ'),
              subtitle: Text('役職と人数、1人あたり金額は選択後に調整できます'),
            ),
            const Divider(height: 1),
            for (final preset in splitPresets)
              ListTile(
                leading: Icon(
                  preset.label == '会社の飲み会'
                      ? Icons.business_center_outlined
                      : preset.label == 'サークル'
                          ? Icons.groups_outlined
                          : Icons.sports_outlined,
                ),
                title: Text(preset.label),
                subtitle: Text(
                  preset.groups.map((group) => group.name).join(' / '),
                ),
                onTap: () => Navigator.of(context).pop(preset),
              ),
          ],
        ),
      ),
    );
    if (preset == null) return;
    // 人数は現在の入力を引き継がず、1 人ずつから調整してもらう
    onLockedGroupIndicesChanged(<int>{});
    onOrganizerGroupChanged(null);
    onChanged(preset.groups.map((g) => g.copyWith()).toList());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // グループを減らしたときに範囲外を指さないようにする
    final organizerIndex = organizerGroupIndex != null &&
            organizerGroupIndex! >= 0 &&
            organizerGroupIndex! < groups.length
        ? organizerGroupIndex
        : null;
    final error = validateSplitGroups(
      groups,
      organizerGroupIndex: organizerIndex,
    );
    final amount = totalAmount;
    final result = (error == null && amount != null && amount > 0)
        ? calculateWeightedSplit(
            totalAmount: amount,
            groups: groups,
            unit: unit,
            organizerGroupIndex: organizerIndex,
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _UnitSelector(
          unit: unit,
          onChanged: onUnitChanged,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text('役職別の支払い設定', style: theme.textTheme.titleMedium),
            ),
            TextButton.icon(
              onPressed: () => _selectPreset(context),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('パターンから選ぶ'),
            ),
          ],
        ),
        Text(
          '同じ役職の人をまとめ、1人あたり金額を調整します',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 8),
        if (amount == null || amount <= 0) ...[
          Card(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '合計金額を入力してください',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        for (var i = 0; i < groups.length; i++)
          _GroupRow(
            key: ValueKey('split-group-$i'),
            group: groups[i],
            currency: currency,
            totalAmount: amount,
            unit: unit,
            amountPerPerson: result?.groups[i].amountPerPerson,
            adjustmentPerPerson: result?.groups[i].extraPerPerson,
            isLocked: lockedGroupIndices.contains(i),
            canRemove: groups.length > 1,
            onChanged: (group) => _updateAt(i, group),
            onLockChanged: (locked) {
              final next = {...lockedGroupIndices};
              locked ? next.add(i) : next.remove(i);
              onLockedGroupIndicesChanged(next);
            },
            onAmountChanged: amount == null ||
                    amount <= 0 ||
                    lockedGroupIndices.contains(i) ||
                    groups.length - lockedGroupIndices.length < 2
                ? null
                : (value) => onChanged(
                      adjustSplitGroupAmount(
                        totalAmount: amount,
                        groups: groups,
                        changedIndex: i,
                        amountPerPerson: value,
                        unit: unit,
                        lockedIndices: lockedGroupIndices,
                      ),
                    ),
            onRemove: () => _removeAt(i),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: groups.length >= 10 ? null : _add,
            icon: const Icon(Icons.add),
            label: const Text('役職を追加'),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(
            error,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        Text('集金者（あなた）の扱い', style: theme.textTheme.titleMedium),
        Text(
          '割り勘に加わる役職を選ぶと、その分だけ他の人の負担が軽くなります。'
          'あなた自身への請求は作られません',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              selected: organizerGroupIndex == organizerNotParticipatingIndex,
              onSelected: (_) => onOrganizerGroupChanged(
                organizerNotParticipatingIndex,
              ),
              label: const Text('加わらない'),
            ),
            for (var i = 0; i < groups.length; i++)
              ChoiceChip(
                selected: organizerIndex == i,
                onSelected: (_) => onOrganizerGroupChanged(i),
                label: Text(
                  groups[i].name.trim().isEmpty ? '役職${i + 1}' : groups[i].name,
                ),
              ),
          ],
        ),
        if (organizerGroupIndex == null) ...[
          const SizedBox(height: 8),
          Text(
            '集金者（あなた）の扱いを選択してください',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
        if (amount != null && amount > 0) ...[
          const SizedBox(height: 16),
          Text('割り振り', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (result == null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.calculate_outlined),
                title: Text(
                  '役職の設定を見直してください',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            )
          else
            _ResultCard(currency: currency, result: result),
        ],
      ],
    );
  }
}

class _UnitSelector extends StatelessWidget {
  const _UnitSelector({required this.unit, required this.onChanged});

  final int unit;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final example = switch (unit) {
      1 => '例：5,333円（1円単位のため端数調整なし）',
      100 => '例：5,300円 + 端数33円',
      500 => '例：5,500円 - 端数167円',
      1000 => '例：5,000円 + 端数333円',
      _ => '例：丸めた金額との差額を一番上のランクで調整します',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('割り振りの単位', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          unit == 1
              ? '1円単位では、表示された金額どおりに割り振ります'
              : '$unit円単位に丸め、合計との差額は一番上のランクで調整します',
          style: theme.textTheme.bodySmall?.copyWith(
            color: unit == 1
                ? theme.colorScheme.outline
                : theme.colorScheme.primary,
            fontWeight: unit == 1 ? null : FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final value in splitUnits)
              ChoiceChip(
                selected: unit == value,
                onSelected: (_) => onChanged(value),
                label: Text(value == 1 ? '1円単位' : '$value円単位'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    unit == 1 ? example : '$example として一番上のランクで調整します',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// グループ1行分の入力（名前・人数・1人あたり金額）。
class _GroupRow extends StatefulWidget {
  const _GroupRow({
    super.key,
    required this.group,
    required this.currency,
    required this.totalAmount,
    required this.unit,
    required this.amountPerPerson,
    required this.adjustmentPerPerson,
    required this.isLocked,
    required this.canRemove,
    required this.onChanged,
    required this.onLockChanged,
    required this.onAmountChanged,
    required this.onRemove,
  });

  final SplitGroup group;
  final String currency;
  final int? totalAmount;
  final int unit;
  final int? amountPerPerson;
  final int? adjustmentPerPerson;
  final bool isLocked;
  final bool canRemove;
  final ValueChanged<SplitGroup> onChanged;
  final ValueChanged<bool> onLockChanged;
  final ValueChanged<int>? onAmountChanged;
  final VoidCallback onRemove;

  @override
  State<_GroupRow> createState() => _GroupRowState();
}

class _GroupRowState extends State<_GroupRow> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.group.name);
  }

  @override
  void didUpdateWidget(_GroupRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // プリセット選択などで外から名前が変わったときだけ入力欄を更新する
    if (widget.group.name != _nameController.text) {
      _nameController.text = widget.group.name;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _nameController,
                    maxLength: 20,
                    decoration: const InputDecoration(
                      labelText: '役職名',
                      isDense: true,
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) =>
                        widget.onChanged(group.copyWith(name: value)),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 104,
                  child: _NumberField(
                    label: '人数',
                    suffix: '人',
                    value: group.count.toString(),
                    onSubmitted: (text) {
                      final count = int.tryParse(text);
                      if (count != null && count >= 1 && count <= 99) {
                        widget.onChanged(group.copyWith(count: count));
                      }
                    },
                    keyboardType: TextInputType.number,
                    formatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                IconButton(
                  tooltip: 'この役職を削除',
                  onPressed: widget.canRemove ? widget.onRemove : null,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: widget.isLocked,
              onChanged: (value) => widget.onLockChanged(value ?? false),
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('このランクの1人あたり金額を固定'),
            ),
            _AmountSlider(
              currency: widget.currency,
              totalAmount: widget.totalAmount,
              unit: widget.unit,
              value: widget.amountPerPerson,
              adjustment: widget.adjustmentPerPerson,
              onChanged: widget.onAmountChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountSlider extends StatelessWidget {
  const _AmountSlider({
    required this.currency,
    required this.totalAmount,
    required this.unit,
    required this.value,
    required this.adjustment,
    required this.onChanged,
  });

  final String currency;
  final int? totalAmount;
  final int unit;
  final int? value;
  final int? adjustment;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final total = totalAmount;
    final current = value;
    if (total == null || total <= 0 || current == null) {
      return const SizedBox.shrink();
    }
    // 全ランクで同じ横軸にするため、スライダーの最大値は合計金額で統一する。
    final max = total;
    final sliderValue = current.clamp(1, max).toDouble();
    final amountLabel = _formatAmountBreakdown(
      currency,
      current,
      adjustment ?? 0,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('1人あたり', style: Theme.of(context).textTheme.labelLarge),
            const Spacer(),
            Text(
              amountLabel,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        Slider(
          value: sliderValue,
          min: 1,
          max: max.toDouble(),
          label: amountLabel,
          onChanged: onChanged == null
              ? null
              : (raw) {
                  final step = unit.clamp(1, max);
                  final rounded = ((raw / step).round() * step).clamp(1, max);
                  onChanged!(rounded);
                },
        ),
      ],
    );
  }
}

/// 人数を直接入力する数値欄。
class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.label,
    required this.suffix,
    required this.value,
    required this.onSubmitted,
    required this.keyboardType,
    required this.formatters,
  });

  final String label;
  final String suffix;
  final String value;
  final ValueChanged<String> onSubmitted;
  final TextInputType keyboardType;
  final List<TextInputFormatter> formatters;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      textAlign: TextAlign.center,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.formatters,
      decoration: InputDecoration(
        labelText: widget.label,
        suffixText: widget.suffix,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onChanged: widget.onSubmitted,
    );
  }
}

/// 計算結果（グループごとの金額と合計）。
class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.currency, required this.result});

  final String currency;
  final SplitResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final group in result.groups) ...[
              _ResultRow(currency: currency, result: group),
              const SizedBox(height: 12),
            ],
            const Divider(height: 8),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '合計 ${result.totalCount} 人',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  formatMoney(currency, result.totalAmount.toString()),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (result.includesOrganizer) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'うち集金する分（${result.payerCount}人）',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    formatMoney(currency, result.collectAmount.toString()),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'あなたの負担（請求は作られません）',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    formatMoney(currency, result.organizerAmount.toString()),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ],
            if (result.hasZeroAmount) ...[
              const SizedBox(height: 8),
              Text(
                '単位が大きすぎて0円になる役職があります。単位を小さくしてください',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ] else if (result.hasExtra) ...[
              const SizedBox(height: 8),
              Text(
                '四捨五入で生じたずれは「${result.extraBearer!.group.name}」の'
                '${result.extraBearer!.group.count}人で1円単位に'
                '${result.extraBearer!.isDiscount ? '差し引いて' : '足して'}調整します'
                '（合計はぴったり一致します）',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.currency, required this.result});

  final String currency;
  final SplitGroupResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final group = result.group;
    final amountText = _formatAmountBreakdown(
      currency,
      result.amountPerPerson,
      result.extraPerPerson,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                group.name,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Text(
              '${group.count}人'
              '${result.organizerCount > 0 ? '（うちあなた1人）' : ''}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text('1人あたり', style: theme.textTheme.bodySmall),
        Text(
          amountText,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (result.extraPerPerson != 0)
          Text('端数調整を含みます', style: theme.textTheme.bodySmall),
        // 端数が人数で割り切れず、1円だけ多い人がいる場合に補足する
        if (result.hasOddYen)
          Text(
            'うち${result.extraExtraCount}人は '
            '${formatMoney(currency, result.amountWithExtraPlusOne.toString())}'
            '（端数の1円）',
            style: theme.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        const SizedBox(height: 4),
        Text(
          'ランク合計 ${formatMoney(currency, result.totalAmount.toString())}',
          textAlign: TextAlign.end,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

String _formatAmountBreakdown(
  String currency,
  int baseAmount,
  int adjustment,
) {
  final base = formatMoney(currency, baseAmount.toString());
  if (adjustment == 0) return base;
  final extra = formatMoney(currency, adjustment.abs().toString());
  final operator = adjustment > 0 ? '+' : '-';
  if (currency == 'JPY') {
    return '${base.replaceFirst(' 円', '')} $operator '
        '${extra.replaceFirst(' 円', '')} 円';
  }
  return '$base $operator $extra';
}
