import 'dart:math';

/// キリのよい基本額と、ルーレットで1人が負担する余り。
class RemainderSplitPreview {
  const RemainderSplitPreview({
    required this.totalAmount,
    required this.participantCount,
    required this.roundingUnit,
    required this.baseAmount,
    required this.remainderAmount,
  });

  final int totalAmount;
  final int participantCount;
  final int roundingUnit;
  final int baseAmount;
  final int remainderAmount;

  bool get needsRoulette => remainderAmount > 0;
  int get baseTotal => baseAmount * participantCount;
}

/// ルーレット確定後の個人別支払額。
class RemainderRouletteResult {
  const RemainderRouletteResult({
    required this.preview,
    required this.winnerIndex,
    required this.payments,
  });

  final RemainderSplitPreview preview;
  final int? winnerIndex;
  final List<int> payments;

  int get paymentTotal => payments.fold(0, (sum, amount) => sum + amount);
}

/// 全員の金額を[roundingUnit]単位で切り捨て、正の余りを求める。
RemainderSplitPreview calculateRemainderSplitPreview({
  required int totalAmount,
  required int participantCount,
  required int roundingUnit,
}) {
  if (totalAmount <= 0) {
    throw ArgumentError.value(totalAmount, 'totalAmount', '1円以上で指定してください');
  }
  if (participantCount < 2) {
    throw ArgumentError.value(
      participantCount,
      'participantCount',
      '2人以上で指定してください',
    );
  }
  if (roundingUnit <= 0) {
    throw ArgumentError.value(roundingUnit, 'roundingUnit', '1円以上で指定してください');
  }

  final evenShare = totalAmount ~/ participantCount;
  final baseAmount = (evenShare ~/ roundingUnit) * roundingUnit;
  final remainderAmount = totalAmount - baseAmount * participantCount;
  return RemainderSplitPreview(
    totalAmount: totalAmount,
    participantCount: participantCount,
    roundingUnit: roundingUnit,
    baseAmount: baseAmount,
    remainderAmount: remainderAmount,
  );
}

/// winnerだけへ余りを加え、入力合計と必ず一致する支払額を返す。
RemainderRouletteResult applyRemainderWinner({
  required RemainderSplitPreview preview,
  int? winnerIndex,
}) {
  if (preview.needsRoulette && winnerIndex == null) {
    throw ArgumentError.notNull('winnerIndex');
  }
  if (preview.needsRoulette &&
      (winnerIndex! < 0 || winnerIndex >= preview.participantCount)) {
    throw RangeError.range(
      winnerIndex,
      0,
      preview.participantCount - 1,
      'winnerIndex',
    );
  }
  if (!preview.needsRoulette && winnerIndex != null) {
    throw ArgumentError.value(winnerIndex, 'winnerIndex', '余りが0円のため当選者は不要です');
  }

  final payments = List<int>.filled(
    preview.participantCount,
    preview.baseAmount,
  );
  if (winnerIndex != null) {
    payments[winnerIndex] += preview.remainderAmount;
  }
  final result = RemainderRouletteResult(
    preview: preview,
    winnerIndex: winnerIndex,
    payments: List.unmodifiable(payments),
  );
  if (result.paymentTotal != preview.totalAmount) {
    throw StateError('支払額の合計が入力金額と一致しません');
  }
  return result;
}

/// UIから乱数生成を分離し、テストでは[nextInt]を固定できるようにする。
class RemainderWinnerSelector {
  RemainderWinnerSelector({int Function(int max)? nextInt})
      : _nextInt = nextInt ?? Random().nextInt;

  final int Function(int max) _nextInt;

  int select(int participantCount) {
    if (participantCount < 2) {
      throw ArgumentError.value(participantCount, 'participantCount');
    }
    final winner = _nextInt(participantCount);
    if (winner < 0 || winner >= participantCount) {
      throw StateError('乱数生成結果が参加者の範囲外です');
    }
    return winner;
  }
}

/// セグメント中央が上部ポインターに一致する停止角度を返す。
double calculateRouletteStopRotation({
  required double currentRotation,
  required int winnerIndex,
  required int participantCount,
  int fullTurns = 7,
}) {
  if (winnerIndex < 0 || winnerIndex >= participantCount) {
    throw RangeError.index(winnerIndex, List.filled(participantCount, 0));
  }
  if (fullTurns < 0) throw ArgumentError.value(fullTurns, 'fullTurns');
  const twoPi = pi * 2;
  final sweep = twoPi / participantCount;
  final normalized = ((currentRotation % twoPi) + twoPi) % twoPi;
  final winnerStop = (((-winnerIndex * sweep) % twoPi) + twoPi) % twoPi;
  final delta = (winnerStop - normalized + twoPi) % twoPi;
  return currentRotation + fullTurns * twoPi + delta;
}

/// 現在ポインターの中央にある参加者。停止角度と内部winnerの照合に使う。
int rouletteIndexAtPointer({
  required double rotation,
  required int participantCount,
}) {
  if (participantCount < 2) {
    throw ArgumentError.value(participantCount, 'participantCount');
  }
  final sweep = pi * 2 / participantCount;
  return ((-rotation / sweep).round() % participantCount + participantCount) %
      participantCount;
}
