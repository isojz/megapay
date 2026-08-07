import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:megapay_app/utils/remainder_roulette_calculator.dart';

void main() {
  group('calculateRemainderSplitPreview', () {
    test('12700円・4人・500円は基本3000円、余り700円', () {
      final preview = calculateRemainderSplitPreview(
        totalAmount: 12700,
        participantCount: 4,
        roundingUnit: 500,
      );

      expect(preview.baseAmount, 3000);
      expect(preview.baseTotal, 12000);
      expect(preview.remainderAmount, 700);
      expect(preview.needsRoulette, isTrue);
    });

    test('12000円・4人・500円は余り0円', () {
      final preview = calculateRemainderSplitPreview(
        totalAmount: 12000,
        participantCount: 4,
        roundingUnit: 500,
      );

      expect(preview.baseAmount, 3000);
      expect(preview.remainderAmount, 0);
      expect(preview.needsRoulette, isFalse);
    });

    test('10123円・4人の100円単位と1000円単位', () {
      final hundred = calculateRemainderSplitPreview(
        totalAmount: 10123,
        participantCount: 4,
        roundingUnit: 100,
      );
      final thousand = calculateRemainderSplitPreview(
        totalAmount: 10123,
        participantCount: 4,
        roundingUnit: 1000,
      );

      expect((hundred.baseAmount, hundred.remainderAmount), (2500, 123));
      expect((thousand.baseAmount, thousand.remainderAmount), (2000, 2123));
    });

    test('1円単位でも人数割りの端数を返す', () {
      final preview = calculateRemainderSplitPreview(
        totalAmount: 10001,
        participantCount: 4,
        roundingUnit: 1,
      );
      expect((preview.baseAmount, preview.remainderAmount), (2500, 1));
    });

    test('2人と100人でも成立する', () {
      final two = calculateRemainderSplitPreview(
        totalAmount: 2501,
        participantCount: 2,
        roundingUnit: 100,
      );
      final many = calculateRemainderSplitPreview(
        totalAmount: 999999,
        participantCount: 100,
        roundingUnit: 500,
      );
      expect((two.baseAmount, two.remainderAmount), (1200, 101));
      expect(many.baseAmount, 9500);
      expect(many.remainderAmount, 49999);
    });
  });

  group('applyRemainderWinner', () {
    late RemainderSplitPreview preview;

    setUp(() {
      preview = calculateRemainderSplitPreview(
        totalAmount: 12700,
        participantCount: 4,
        roundingUnit: 500,
      );
    });

    test('winner先頭へ余りを加算する', () {
      final result = applyRemainderWinner(preview: preview, winnerIndex: 0);
      expect(result.payments, [3700, 3000, 3000, 3000]);
      expect(result.paymentTotal, 12700);
    });

    test('winner末尾へ余りを加算する', () {
      final result = applyRemainderWinner(preview: preview, winnerIndex: 3);
      expect(result.payments, [3000, 3000, 3000, 3700]);
      expect(result.paymentTotal, 12700);
    });

    test('余り0ならwinnerなしで全員同額', () {
      final exact = calculateRemainderSplitPreview(
        totalAmount: 12000,
        participantCount: 4,
        roundingUnit: 500,
      );
      final result = applyRemainderWinner(preview: exact);
      expect(result.payments, [3000, 3000, 3000, 3000]);
      expect(result.paymentTotal, 12000);
    });

    test('不正なwinnerを拒否する', () {
      expect(
        () => applyRemainderWinner(preview: preview, winnerIndex: 4),
        throwsRangeError,
      );
    });
  });

  test('乱数生成を固定できる', () {
    final selector = RemainderWinnerSelector(nextInt: (_) => 2);
    expect(selector.select(4), 2);
  });

  test('停止角度と内部winnerが先頭・末尾で一致する', () {
    for (final winner in [0, 3]) {
      final stop = calculateRouletteStopRotation(
        currentRotation: pi / 7,
        winnerIndex: winner,
        participantCount: 4,
      );
      expect(
        rouletteIndexAtPointer(rotation: stop, participantCount: 4),
        winner,
      );
      expect(stop, greaterThan(pi / 7 + 6 * pi * 2));
    }
  });
}
