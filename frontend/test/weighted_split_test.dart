import 'package:flutter_test/flutter_test.dart';
import 'package:megapay_app/utils/weighted_split.dart';

/// 配分結果の合計が入力金額と一致することを確かめる。
void expectTotalMatches(SplitResult result, int expected) {
  final sum = result.groups.fold(0, (s, g) => s + g.totalAmount);
  expect(sum, expected, reason: '配分の合計が入力金額と一致していません');
  expect(result.totalAmount, expected);
}

/// 端数を引き受ける1人を除き、全員の金額が単位で割り切れることを確かめる。
void expectAmountsFitUnit(SplitResult result) {
  for (final group in result.groups) {
    expect(
      group.amountPerPerson % result.unit,
      0,
      reason: '${group.group.name} の1人あたり金額が単位で割り切れていません',
    );
  }
}

void main() {
  group('calculateWeightedSplit（1円単位）', () {
    test('割り切れる場合はグループ内が同額になる', () {
      final result = calculateWeightedSplit(
        totalAmount: 10000,
        groups: const [
          SplitGroup(name: 'A', count: 1, weight: 2),
          SplitGroup(name: 'B', count: 2, weight: 1),
        ],
      );
      // 重み付き人数 = 1×2 + 2×1 = 4 → 1重みあたり 2500 円
      expect(result.groups[0].amountPerPerson, 5000);
      expect(result.groups[1].amountPerPerson, 2500);
      expect(result.hasExtra, isFalse);
      expectTotalMatches(result, 10000);
    });

    test('端数が出ても合計は一致する', () {
      final result = calculateWeightedSplit(
        totalAmount: 10000,
        groups: const [
          SplitGroup(name: 'A', count: 2, weight: 2),
          SplitGroup(name: 'B', count: 3, weight: 1),
        ],
      );
      expectTotalMatches(result, 10000);
    });

    test('端数は重みがいちばん大きいグループの1人がまとめて負担する', () {
      final result = calculateWeightedSplit(
        totalAmount: 10001,
        groups: const [
          SplitGroup(name: '軽い', count: 2, weight: 1),
          SplitGroup(name: '重い', count: 2, weight: 2),
        ],
      );
      // 端数は「重い」グループだけに乗る
      expect(result.groups[0].extraAmount, 0);
      expect(result.groups[1].extraAmount, greaterThan(0));
      expect(result.extraBearer?.group.name, '重い');
      expectTotalMatches(result, 10001);
    });

    test('重みが大きいグループの方が1人あたり高くなる', () {
      final result = calculateWeightedSplit(
        totalAmount: 30000,
        groups: const [
          SplitGroup(name: '多め', count: 2, weight: 2),
          SplitGroup(name: '少なめ', count: 2, weight: 1),
        ],
      );
      expect(
        result.groups[0].amountPerPerson,
        greaterThan(result.groups[1].amountPerPerson),
      );
      expectTotalMatches(result, 30000);
    });

    test('重みを変えても合計は変わらない', () {
      for (final weight in [1.0, 1.5, 2.0, 2.5, 3.0]) {
        final result = calculateWeightedSplit(
          totalAmount: 12345,
          groups: [
            SplitGroup(name: 'A', count: 2, weight: weight),
            const SplitGroup(name: 'B', count: 3, weight: 1),
          ],
        );
        expectTotalMatches(result, 12345);
      }
    });

    test('グループ数が3つ以上でも合計が一致する', () {
      final result = calculateWeightedSplit(
        totalAmount: 9999,
        groups: const [
          SplitGroup(name: 'A', count: 1, weight: 3),
          SplitGroup(name: 'B', count: 2, weight: 2),
          SplitGroup(name: 'C', count: 3, weight: 1),
          SplitGroup(name: 'D', count: 4, weight: 0.5),
        ],
      );
      expect(result.totalCount, 10);
      expectTotalMatches(result, 9999);
    });
  });

  group('calculateWeightedSplit（単位あり）', () {
    test('500円単位で割り振り、端数は上のグループの1人が負担する', () {
      final result = calculateWeightedSplit(
        totalAmount: 30000,
        unit: 500,
        groups: const [
          SplitGroup(name: '多め', count: 2, weight: 2),
          SplitGroup(name: '少なめ', count: 3, weight: 1),
        ],
      );
      // 重み付き人数 = 2×2 + 3×1 = 7
      //   多め   30000×2/7 = 8571.4 → 8500（500円単位）
      //   少なめ 30000×1/7 = 4285.7 → 4000
      //   割当 = 8500×2 + 4000×3 = 29000、端数 1000 は多めの1人が負担
      expect(result.groups[0].amountPerPerson, 8500);
      expect(result.groups[1].amountPerPerson, 4000);
      expect(result.groups[0].extraAmount, 1000);
      expect(result.groups[0].amountWithExtra, 9500);
      expect(result.groups[1].extraAmount, 0);
      expectTotalMatches(result, 30000);
      expectAmountsFitUnit(result);
    });

    test('1000円単位でも合計が一致する', () {
      final result = calculateWeightedSplit(
        totalAmount: 50000,
        unit: 1000,
        groups: const [
          SplitGroup(name: '先輩', count: 3, weight: 2),
          SplitGroup(name: '後輩', count: 5, weight: 1),
        ],
      );
      expectTotalMatches(result, 50000);
      expectAmountsFitUnit(result);
    });

    test('100円単位でも合計が一致する', () {
      final result = calculateWeightedSplit(
        totalAmount: 17800,
        unit: 100,
        groups: const [
          SplitGroup(name: 'A', count: 2, weight: 1.5),
          SplitGroup(name: 'B', count: 4, weight: 1),
        ],
      );
      expectTotalMatches(result, 17800);
      expectAmountsFitUnit(result);
    });

    test('合計が単位で割り切れなくても、端数を引き受けて合計は一致する', () {
      final result = calculateWeightedSplit(
        totalAmount: 30300,
        unit: 500,
        groups: const [
          SplitGroup(name: '多め', count: 2, weight: 2),
          SplitGroup(name: '少なめ', count: 3, weight: 1),
        ],
      );
      // 端数を引き受ける1人だけは単位で割り切れない額になりうる
      expectTotalMatches(result, 30300);
      expectAmountsFitUnit(result);
      expect(result.extraBearer?.group.name, '多め');
    });

    test('端数を引き受ける以外の全員は単位どおりの金額になる（総当たり）', () {
      for (var amount = 20000; amount <= 20100; amount++) {
        final result = calculateWeightedSplit(
          totalAmount: amount,
          unit: 500,
          groups: const [
            SplitGroup(name: 'A', count: 3, weight: 1.7),
            SplitGroup(name: 'B', count: 4, weight: 1.0),
          ],
        );
        expectTotalMatches(result, amount);
        expectAmountsFitUnit(result);
      }
    });

    test('単位が大きすぎると0円のグループが出ることを検知できる', () {
      final result = calculateWeightedSplit(
        totalAmount: 3000,
        unit: 1000,
        groups: const [
          SplitGroup(name: '多め', count: 1, weight: 3),
          SplitGroup(name: '少なめ', count: 5, weight: 1),
        ],
      );
      // 少なめの理想額は 3000×1/8 = 375 円 → 1000 円単位では 0 円になる
      expect(result.hasZeroAmount, isTrue);
      expectTotalMatches(result, 3000);
    });

    test('単位に0以下は指定できない', () {
      expect(
        () => calculateWeightedSplit(
          totalAmount: 1000,
          unit: 0,
          groups: const [SplitGroup(name: 'A', count: 2, weight: 1)],
        ),
        throwsArgumentError,
      );
    });
  });

  group('入力チェック', () {
    test('不正な入力は例外になる', () {
      expect(
        () => calculateWeightedSplit(
          totalAmount: 0,
          groups: const [SplitGroup(name: 'A', count: 2, weight: 1)],
        ),
        throwsArgumentError,
      );
      expect(
        () => calculateWeightedSplit(totalAmount: 1000, groups: const []),
        throwsArgumentError,
      );
      expect(
        () => calculateWeightedSplit(
          totalAmount: 1000,
          groups: const [SplitGroup(name: 'A', count: 2, weight: 0)],
        ),
        throwsArgumentError,
      );
    });

    test('validateSplitGroups は正しい入力に null を返す', () {
      expect(
        validateSplitGroups(const [
          SplitGroup(name: 'A', count: 1, weight: 1),
          SplitGroup(name: 'B', count: 1, weight: 2),
        ]),
        isNull,
      );
    });

    test('validateSplitGroups は空・名前なし・人数0・重み0 を弾く', () {
      expect(validateSplitGroups(const []), isNotNull);
      expect(
        validateSplitGroups(const [SplitGroup(name: '  ', count: 2, weight: 1)]),
        isNotNull,
      );
      expect(
        validateSplitGroups(const [SplitGroup(name: 'A', count: 0, weight: 1)]),
        isNotNull,
      );
      expect(
        validateSplitGroups(const [SplitGroup(name: 'A', count: 2, weight: 0)]),
        isNotNull,
      );
    });

    test('合計1人だけの場合は弾く', () {
      expect(
        validateSplitGroups(const [SplitGroup(name: 'A', count: 1, weight: 1)]),
        isNotNull,
      );
    });
  });

  group('splitPresets', () {
    test('すべてのプリセットが各単位で計算できる', () {
      for (final preset in splitPresets) {
        final groups =
            preset.groups.map((g) => g.copyWith(count: g.count + 1)).toList();
        expect(validateSplitGroups(groups), isNull, reason: preset.label);
        for (final unit in splitUnits) {
          final result = calculateWeightedSplit(
            totalAmount: 20000,
            unit: unit,
            groups: groups,
          );
          expectTotalMatches(result, 20000);
          expectAmountsFitUnit(result);
        }
      }
    });
  });
}
