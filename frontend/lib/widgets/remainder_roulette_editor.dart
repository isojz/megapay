import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/money.dart';
import '../utils/remainder_roulette_calculator.dart';
import '../utils/weighted_split.dart';
import 'roulette_wheel.dart';

class RemainderRouletteSubmission {
  const RemainderRouletteSubmission({
    required this.names,
    required this.result,
  });

  final List<String> names;
  final RemainderRouletteResult result;

  /// 参加者0は集金者本人。既存APIへは自己負担分を送らない。
  int get organizerIndex => 0;
}

typedef CreateRemainderRoulette = Future<void> Function(
  RemainderRouletteSubmission submission,
);

/// 等分でキリのよい基本額を選び、余りがある場合だけ抽選を展開する。
class RemainderRouletteEditor extends StatefulWidget {
  const RemainderRouletteEditor({
    super.key,
    required this.currency,
    required this.totalAmount,
    required this.participantCount,
    required this.rouletteActive,
    required this.isCreating,
    required this.onCreate,
    required this.onRouletteActiveChanged,
    this.winnerSelector,
    this.animationDuration = const Duration(milliseconds: 4200),
  });

  final String currency;
  final int? totalAmount;
  final int participantCount;
  final bool rouletteActive;
  final bool isCreating;
  final CreateRemainderRoulette onCreate;
  final ValueChanged<bool> onRouletteActiveChanged;
  final RemainderWinnerSelector? winnerSelector;
  final Duration animationDuration;

  @override
  State<RemainderRouletteEditor> createState() =>
      _RemainderRouletteEditorState();
}

class _RemainderRouletteEditorState extends State<RemainderRouletteEditor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final RemainderWinnerSelector _winnerSelector;
  late final AudioPlayer _roulettePlayer;
  late List<String> _names;
  var _unit = 500;
  var _soundEnabled = true;
  var _rotation = 0.0;
  var _startRotation = 0.0;
  var _targetRotation = 0.0;
  var _pointerWobble = 0.0;
  int? _pendingWinner;
  int? _winnerIndex;
  int? _lastPointerIndex;
  RemainderRouletteResult? _result;

  int get _participantCount => widget.participantCount.clamp(2, 100);
  bool get _isSpinning => _controller.isAnimating;

  RemainderSplitPreview? get _preview {
    final amount = widget.totalAmount;
    if (amount == null || amount <= 0) return null;
    return calculateRemainderSplitPreview(
      totalAmount: amount,
      participantCount: _participantCount,
      roundingUnit: _unit,
    );
  }

  @override
  void initState() {
    super.initState();
    _names = _defaultNames(_participantCount);
    _winnerSelector = widget.winnerSelector ?? RemainderWinnerSelector();
    _roulettePlayer = AudioPlayer();
    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    )
      ..addListener(_onAnimationTick)
      ..addStatusListener(_onAnimationStatus);
  }

  @override
  void didUpdateWidget(covariant RemainderRouletteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.participantCount != widget.participantCount) {
      final nextCount = _participantCount;
      if (nextCount > _names.length) {
        _names = [
          ..._names,
          for (var index = _names.length; index < nextCount; index++)
            '参加者${index + 1}',
        ];
      } else {
        _names = _names.take(nextCount).toList();
      }
      _clearResult();
    }
    if (oldWidget.totalAmount != widget.totalAmount) _clearResult();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onAnimationTick)
      ..removeStatusListener(_onAnimationStatus)
      ..dispose();
    unawaited(_roulettePlayer.dispose());
    super.dispose();
  }

  void _onAnimationTick() {
    final progress = Curves.easeOutQuint.transform(_controller.value);
    _rotation = _startRotation + (_targetRotation - _startRotation) * progress;
    _pointerWobble = math.sin(_controller.value * math.pi * 36) *
        (1 - _controller.value) *
        0.07;
    final pointerIndex = rouletteIndexAtPointer(
      rotation: _rotation,
      participantCount: _participantCount,
    );
    if (_lastPointerIndex != pointerIndex) _lastPointerIndex = pointerIndex;
    if (mounted) setState(() {});
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    final preview = _preview;
    final winner = _pendingWinner;
    if (preview == null || winner == null) {
      setState(_clearResult);
      return;
    }
    setState(() {
      _rotation = _targetRotation;
      _pointerWobble = 0;
      _winnerIndex = winner;
      _result = applyRemainderWinner(preview: preview, winnerIndex: winner);
    });
    if (_soundEnabled) unawaited(_roulettePlayer.stop());
  }

  void _clearResult() {
    _pendingWinner = null;
    _winnerIndex = null;
    _result = null;
  }

  void _changeUnit(int? value) {
    if (value == null || _isSpinning) return;
    setState(() {
      _unit = value;
      _clearResult();
    });
    if (!(_preview?.needsRoulette ?? false)) _setRouletteActive(false);
  }

  void _changeName(int index, String value) {
    setState(() {
      _names[index] = value;
      _clearResult();
    });
  }

  void _setRouletteActive(bool active) {
    if (_isSpinning || widget.rouletteActive == active) return;
    setState(() {
      if (!active) _clearResult();
    });
    widget.onRouletteActiveChanged(active);
  }

  Future<void> _spin() async {
    final preview = _preview;
    if (_isSpinning || preview == null || !preview.needsRoulette) return;
    FocusScope.of(context).unfocus();
    final winner = _winnerSelector.select(_participantCount);
    setState(() {
      _pendingWinner = winner;
      _winnerIndex = null;
      _result = null;
      _startRotation = _rotation;
      _targetRotation = calculateRouletteStopRotation(
        currentRotation: _rotation,
        winnerIndex: winner,
        participantCount: _participantCount,
      );
      _lastPointerIndex = null;
    });
    if (_soundEnabled) {
      try {
        await _playSound(
          _roulettePlayer,
          'sounds/roulette/rouletteSound.wav',
          volume: 0.7,
        );
      } catch (_) {
        if (mounted) {
          setState(() => _soundEnabled = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ルーレット音を再生できませんでした。音なしで続行します'),
            ),
          );
        }
      }
    }
    await _controller.forward(from: 0);
  }

  Future<void> _playSound(
    AudioPlayer player,
    String asset, {
    required double volume,
  }) async {
    await player.stop();
    await player.play(AssetSource(asset), volume: volume);
  }

  Future<void> _createResult() async {
    final result = _result;
    if (result == null) return;
    await widget.onCreate(
      RemainderRouletteSubmission(
        names: List.unmodifiable(_names),
        result: result,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _preview;
    final validNames = _names.every((name) => name.trim().isNotEmpty);
    final wheelSize = MediaQuery.sizeOf(context).width <= 360 ? 250.0 : 310.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<int>(
              key: const Key('roulette-unit-selector'),
              initialValue: _unit,
              decoration: const InputDecoration(
                labelText: 'キリよく割る',
                helperText: '全員の基本額を選んだ単位で揃えます',
              ),
              items: [
                for (final unit in splitUnits)
                  DropdownMenuItem(value: unit, child: Text('$unit円単位')),
              ],
              onChanged: _isSpinning ? null : _changeUnit,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _PreviewCard(currency: widget.currency, preview: preview),
        if (preview != null &&
            preview.needsRoulette &&
            !widget.rouletteActive) ...[
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('端数を楽しく決めますか？', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    '${formatMoney(widget.currency, preview.remainderAmount.toString())}を'
                    '追加で払う1人をルーレットで決められます',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('roulette-enable-button'),
                    onPressed: () => _setRouletteActive(true),
                    icon: const Icon(Icons.casino_outlined),
                    label: const Text('端数をルーレットで決める'),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (preview != null && !preview.needsRoulette) ...[
          const SizedBox(height: 14),
          Card(
            color: MegaPaySemantics.of(context).successContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: MegaPaySemantics.of(context).success,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'ぴったり割れました。ルーレットは必要ありません',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (preview != null &&
            preview.needsRoulette &&
            widget.rouletteActive) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text('端数ルーレット', style: theme.textTheme.titleMedium),
              ),
              TextButton(
                key: const Key('roulette-disable-button'),
                onPressed: _isSpinning ? null : () => _setRouletteActive(false),
                child: const Text('等分に戻る'),
              ),
              Tooltip(
                message: _soundEnabled ? '効果音をオフにする' : '効果音をオンにする',
                child: IconButton(
                  key: const Key('roulette-sound-toggle'),
                  onPressed: _isSpinning
                      ? null
                      : () => setState(() => _soundEnabled = !_soundEnabled),
                  icon: Icon(
                    _soundEnabled ? Icons.volume_up : Icons.volume_off,
                  ),
                ),
              ),
            ],
          ),
          ExpansionTile(
            key: const Key('roulette-participant-names'),
            tilePadding: const EdgeInsets.symmetric(horizontal: 4),
            childrenPadding: const EdgeInsets.only(top: 16),
            title: const Text('参加者名'),
            subtitle: Text('集金者を含む$_participantCount人'),
            children: [
              for (var index = 0; index < _participantCount; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextFormField(
                    key: ValueKey('roulette-name-$index-${_names.length}'),
                    initialValue: _names[index],
                    enabled: !_isSpinning,
                    readOnly: index == 0,
                    maxLength: 30,
                    decoration: InputDecoration(
                      labelText: index == 0 ? '集金者' : '参加者$index',
                      counterText: '',
                    ),
                    onChanged: (value) => _changeName(index, value),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? '名前を入力してください'
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: AnimatedScale(
              scale: _isSpinning
                  ? 1 + math.sin(_controller.value * math.pi) * 0.018
                  : 1,
              duration: const Duration(milliseconds: 80),
              child: SizedBox(
                width: wheelSize,
                height: wheelSize,
                child: RouletteWheel(
                  names: _names,
                  rotation: _rotation,
                  winnerIndex: _winnerIndex,
                  pointerWobble: _pointerWobble,
                ),
              ),
            ),
          ),
          if (_participantCount > 20) ...[
            const SizedBox(height: 8),
            Text(
              '人数が多いため、名前は抽選結果の一覧に表示します',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const Key('roulette-spin-button'),
            onPressed: !_isSpinning && validNames ? _spin : null,
            icon: _isSpinning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.casino_outlined),
            label: Text(
              _isSpinning
                  ? 'ルーレット回転中…'
                  : _result == null
                      ? 'ルーレットを回す'
                      : 'もう一度回す',
            ),
          ),
        ],
        if (widget.rouletteActive)
          if (_result case final result?) ...[
            const SizedBox(height: 20),
            _ResultCard(
                currency: widget.currency, names: _names, result: result),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('roulette-create-result-button'),
              onPressed: widget.isCreating ? null : _createResult,
              icon: widget.isCreating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.call_split),
              label: const Text('この結果で割り勘を作成'),
            ),
          ],
      ],
    );
  }
}

List<String> _defaultNames(int count) => [
      'あなた',
      for (var index = 1; index < count; index++) '参加者$index',
    ];

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.currency, required this.preview});

  final String currency;
  final RemainderSplitPreview? preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = preview;
    return Card(
      color: scheme.primaryContainer.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: value == null
            ? const Text('合計金額と人数を入力すると、端数をプレビューできます')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${value.participantCount}人でキリよく割ると',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 14),
                  _AmountLine(
                    label: '基本',
                    value:
                        '${formatMoney(currency, value.baseAmount.toString())} / 人',
                  ),
                  const Divider(height: 24),
                  Text('端数', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 2),
                  Text(
                    formatMoney(currency, value.remainderAmount.toString()),
                    key: const Key('roulette-remainder-amount'),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.currency,
    required this.names,
    required this.result,
  });

  final String currency;
  final List<String> names;
  final RemainderRouletteResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final winner = result.winnerIndex!;
    final winnerName = winner == 0 ? 'あなた（${names[winner]}）' : names[winner];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.celebration, color: scheme.primary, size: 38),
            const SizedBox(height: 4),
            Text(
              '決定！',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            Text(
              winnerName,
              key: const Key('roulette-winner-name'),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              '+${formatMoney(currency, result.preview.remainderAmount.toString())}を担当！',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text('今回のお会計', style: theme.textTheme.titleSmall),
            const Divider(),
            for (var index = 0; index < names.length; index++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    if (index == winner) ...[
                      Icon(
                        Icons.casino_outlined,
                        color: scheme.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        names[index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: index == winner
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    Text(
                      formatMoney(currency, result.payments[index].toString()),
                      style: TextStyle(
                        fontWeight: index == winner
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(),
            _AmountLine(
              label: '合計',
              value: formatMoney(currency, result.paymentTotal.toString()),
              bold: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountLine extends StatelessWidget {
  const _AmountLine({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.w700,
            ),
          ),
        ],
      );
}
