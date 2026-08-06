import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/money.dart';
import '../utils/weighted_split.dart';

/// 傾斜配分の入力と結果表示をまとめたウィジェット。
///
/// グループ（名前・人数・重み）を編集すると、その場で配分結果が更新される。
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
  });

  final String currency;

  /// 入力済みの合計金額。未入力・不正な場合は null（結果は出さない）
  final int? totalAmount;

  final List<SplitGroup> groups;
  final ValueChanged<List<SplitGroup>> onChanged;

  /// 割り振りの単位（1 / 100 / 500 / 1000 円）
  final int unit;
  final ValueChanged<int> onUnitChanged;

  void _updateAt(int index, SplitGroup group) {
    final next = [...groups];
    next[index] = group;
    onChanged(next);
  }

  void _removeAt(int index) {
    final next = [...groups]..removeAt(index);
    onChanged(next);
  }

  void _add() {
    // 直前のグループより 1 段軽い重みを初期値にする
    final lastWeight = groups.isEmpty ? 1.0 : groups.last.weight;
    final weight = lastWeight > 0.5 ? lastWeight - 0.5 : 0.5;
    onChanged([
      ...groups,
      SplitGroup(name: 'グループ${groups.length + 1}', count: 1, weight: weight),
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
              title: Text('傾斜のパターンを選ぶ'),
              subtitle: Text('選んだあとに人数と重みを調整できます'),
            ),
            const Divider(height: 1),
            for (final preset in splitPresets)
              ListTile(
                leading: const Icon(Icons.tune),
                title: Text(preset.label),
                subtitle: Text(
                  preset.groups
                      .map((g) => '${g.name} ×${_formatWeight(g.weight)}')
                      .join(' / '),
                ),
                onTap: () => Navigator.of(context).pop(preset),
              ),
          ],
        ),
      ),
    );
    if (preset == null) return;
    // 人数は現在の入力を引き継がず、1 人ずつから調整してもらう
    onChanged(preset.groups.map((g) => g.copyWith()).toList());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = validateSplitGroups(groups);
    final amount = totalAmount;
    final result = (error == null && amount != null && amount > 0)
        ? calculateWeightedSplit(
            totalAmount: amount,
            groups: groups,
            unit: unit,
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('グループ', style: theme.textTheme.titleMedium),
            ),
            TextButton.icon(
              onPressed: () => _selectPreset(context),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('パターンから選ぶ'),
            ),
          ],
        ),
        Text(
          '同じ負担にする人をまとめて、人数と重みを決めます',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < groups.length; i++)
          _GroupRow(
            key: ValueKey('split-group-$i'),
            group: groups[i],
            canRemove: groups.length > 1,
            onChanged: (group) => _updateAt(i, group),
            onRemove: () => _removeAt(i),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: groups.length >= 10 ? null : _add,
            icon: const Icon(Icons.add),
            label: const Text('グループを追加'),
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
        Text('割り振りの単位', style: theme.textTheme.titleMedium),
        Text(
          'この単位できりよく割り振り、端数は重みがいちばん大きいグループの1人が負担します',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final value in splitUnits)
              ChoiceChip(
                selected: unit == value,
                onSelected: (_) => onUnitChanged(value),
                label: Text(value == 1 ? '1円単位' : '$value円単位'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text('割り振り', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (result == null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.calculate_outlined),
              title: Text(
                amount == null || amount <= 0
                    ? '合計金額を入力すると割り振りが表示されます'
                    : 'グループの設定を見直してください',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          )
        else
          _ResultCard(currency: currency, result: result),
      ],
    );
  }
}

/// グループ1行分の入力（名前・人数・重み）。
class _GroupRow extends StatefulWidget {
  const _GroupRow({
    super.key,
    required this.group,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final SplitGroup group;
  final bool canRemove;
  final ValueChanged<SplitGroup> onChanged;
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
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    maxLength: 20,
                    decoration: const InputDecoration(
                      labelText: 'グループ名',
                      isDense: true,
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) =>
                        widget.onChanged(group.copyWith(name: value)),
                  ),
                ),
                IconButton(
                  tooltip: 'このグループを削除',
                  onPressed: widget.canRemove ? widget.onRemove : null,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _StepperField(
                    label: '人数',
                    suffix: '人',
                    value: group.count.toString(),
                    onDecrease: group.count > 1
                        ? () => widget.onChanged(
                            group.copyWith(count: group.count - 1))
                        : null,
                    onIncrease: group.count < 99
                        ? () => widget.onChanged(
                            group.copyWith(count: group.count + 1))
                        : null,
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
                const SizedBox(width: 8),
                Expanded(
                  child: _StepperField(
                    label: '重み',
                    suffix: '倍',
                    value: _formatWeight(group.weight),
                    onDecrease: group.weight > 0.5
                        ? () => widget.onChanged(
                            group.copyWith(weight: group.weight - 0.5))
                        : null,
                    onIncrease: group.weight < 10
                        ? () => widget.onChanged(
                            group.copyWith(weight: group.weight + 0.5))
                        : null,
                    onSubmitted: (text) {
                      final weight = double.tryParse(text);
                      if (weight != null && weight > 0 && weight <= 10) {
                        widget.onChanged(group.copyWith(weight: weight));
                      }
                    },
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    formatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 「− 値 ＋」の形で数値を調整できる入力欄。直接入力もできる。
class _StepperField extends StatefulWidget {
  const _StepperField({
    required this.label,
    required this.suffix,
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
    required this.onSubmitted,
    required this.keyboardType,
    required this.formatters,
  });

  final String label;
  final String suffix;
  final String value;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;
  final ValueChanged<String> onSubmitted;
  final TextInputType keyboardType;
  final List<TextInputFormatter> formatters;

  @override
  State<_StepperField> createState() => _StepperFieldState();
}

class _StepperFieldState extends State<_StepperField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_StepperField oldWidget) {
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
    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: widget.onDecrease,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Expanded(
          child: TextField(
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
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: widget.onIncrease,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
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
            if (result.hasZeroAmount) ...[
              const SizedBox(height: 8),
              Text(
                '単位が大きすぎて0円になるグループがあります。単位を小さくしてください',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ] else if (result.hasExtra) ...[
              const SizedBox(height: 8),
              Text(
                '端数 ${formatMoney(currency, result.extraBearer!.extraAmount.toString())} は'
                '「${result.extraBearer!.group.name}」の1人が負担します（合計はぴったり一致します）',
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
    final perPerson = formatMoney(currency, result.amountPerPerson.toString());

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.name,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                '${group.count}人 × 重み ${_formatWeight(group.weight)}',
                style: theme.textTheme.bodySmall,
              ),
              Text('1人あたり $perPerson', style: theme.textTheme.bodySmall),
              // 端数の引き受け役がいるグループだけ、その人の金額も出す
              if (result.hasExtra)
                Text(
                  'うち1人は '
                  '${formatMoney(currency, result.amountWithExtra.toString())}'
                  '（端数を負担）',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
            ],
          ),
        ),
        Text(
          formatMoney(currency, result.totalAmount.toString()),
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

/// 重みの表示（1.5 → "1.5"、2.0 → "2"）
String _formatWeight(double weight) {
  return weight == weight.roundToDouble()
      ? weight.toStringAsFixed(0)
      : weight.toString();
}
