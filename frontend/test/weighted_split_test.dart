import 'package:flutter_test/flutter_test.dart';
import 'package:megapay_app/utils/weighted_split.dart';

/// 配分結果の合計が入力金額と一致することを確かめる。
void expectTotalMatches(SplitResult result, int expected) {
  final sum = result.groups.fold(0, (s, g) => s + g.totalAmount);
  expect(sum, expected, reason: '配分の合計が入力金額と一致していません');
  expect(result.totalAmount, expected);
}

void main() {
  group('calculateWeightedSplit', () {
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
      expect(result.hasRounding, isFalse);
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

    test('端数は重みの大きいグループから割り当てられる', () {
      final result = calculateWeightedSplit(
        totalAmount: 10001,
        groups: const [
          SplitGroup(name: '軽い', count: 2, weight: 1),
          SplitGroup(name: '重い', count: 2, weight: 2),
        ],
      );
      // 端数は重みの大きい「重い」グループが先に負担する
      expect(result.groups[1].extraPersonCount, greaterThan(0));
      expectTotalMatches(result, 10001);
    });

    test('等分（全員同じ重み）でも合計が一致する', () {
      final result = calculateWeightedSplit(
        totalAmount: 10000,
        groups: const [SplitGroup(name: '全員', count: 3, weight: 1)],
      );
      expect(result.groups[0].amountPerPerson, 3333);
      expect(result.groups[0].extraPersonCount, 1); // 端数1円を1人が負担
      expectTotalMatches(result, 10000);
    });

    test('重みを変えても合計は変わらない', () {
      const groups = [
        SplitGroup(name: 'A', count: 2, weight: 1),
        SplitGroup(name: 'B', count: 3, weight: 1),
      ];
      for (final weight in [1.0, 1.5, 2.0, 2.5, 3.0]) {
        final result = calculateWeightedSplit(
          totalAmount: 12345,
          groups: [groups[0].copyWith(weight: weight), groups[1]],
        );
        expectTotalMatches(result, 12345);
      }
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

    test('端数が出やすい金額でも常に一致する（総当たり）', () {
      for (var amount = 1000; amount <= 1100; amount++) {
        final result = calculateWeightedSplit(
          totalAmount: amount,
          groups: const [
            SplitGroup(name: 'A', count: 3, weight: 1.7),
            SplitGroup(name: 'B', count: 4, weight: 1.0),
          ],
        );
        expectTotalMatches(result, amount);
      }
    });

    test('小数の重みでも合計が一致する', () {
      final result = calculateWeightedSplit(
        totalAmount: 7777,
        groups: const [
          SplitGroup(name: 'A', count: 2, weight: 1.33),
          SplitGroup(name: 'B', count: 3, weight: 0.77),
        ],
      );
      expectTotalMatches(result, 7777);
    });

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
  });

  group('validateSplitGroups', () {
    test('正しい入力は null を返す', () {
      expect(
        validateSplitGroups(const [
          SplitGroup(name: 'A', count: 1, weight: 1),
          SplitGroup(name: 'B', count: 1, weight: 2),
        ]),
        isNull,
      );
    });

    test('空・名前なし・人数0・重み0 はメッセージを返す', () {
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

    test('合計1人だけの場合はメッセージを返す', () {
      expect(
        validateSplitGroups(const [SplitGroup(name: 'A', count: 1, weight: 1)]),
        isNotNull,
      );
    });
  });

  group('splitPresets', () {
    test('すべてのプリセットが計算できる', () {
      for (final preset in splitPresets) {
        // プリセットは人数1人ずつなので、人数を足して現実的な構成にする
        final groups = preset.groups
            .map((g) => g.copyWith(count: g.count + 1))
            .toList();
        expect(validateSplitGroups(groups), isNull, reason: preset.label);
        final result =
            calculateWeightedSplit(totalAmount: 20000, groups: groups);
        expectTotalMatches(result, 20000);
      }
    });
  });
}
