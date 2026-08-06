import 'package:flutter_test/flutter_test.dart';
import 'package:megapay_app/utils/weighted_split.dart';

/// 配分結果の合計が入力金額と一致することを確かめる。
void expectTotalMatches(SplitResult result, int expected) {
  final sum = result.groups.fold(0, (s, g) => s + g.totalAmount);
  expect(sum, expected, reason: '配分の合計が入力金額と一致していません');
  expect(result.totalAmount, expected);
}

/// 端数を負担するグループ以外は、単位どおりの金額になっていることを確かめる。
void expectAmountsFitUnit(SplitResult result) {
  for (final group in result.groups) {
    if (group.hasExtra) continue;
    expect(
      group.amountPerPerson % result.unit,
      0,
      reason: '${group.group.name} の1人あたり金額が単位で割り切れていません',
    );
  }
}

/// 端数の負担がグループ内で 1 円以内に収まっていることを確かめる。
void expectExtraSpreadEvenly(SplitResult result) {
  final bearer = result.extraBearer;
  if (bearer == null) return;
  final diff = bearer.amountWithExtraPlusOne - bearer.amountWithExtra;
  expect(diff, 1, reason: '端数の負担差が1円を超えています');
  expect(
    bearer.extraExtraCount,
    lessThan(bearer.group.count),
    reason: '1円多く負担する人数がグループ人数以上になっています',
  );
}

void main() {
  group('端数の分け方（上のグループ内で1円単位）', () {
    test('1人あたりの金額は単位に四捨五入される', () {
      final result = calculateWeightedSplit(
        totalAmount: 30000,
        unit: 500,
        groups: const [
          SplitGroup(name: '多め', count: 2, weight: 2),
          SplitGroup(name: '少なめ', count: 3, weight: 1),
        ],
      );
      // 重み付き人数 = 7 → 多め 8571.4 → 8500、少なめ 4285.7 → 4500（切り上げ）
      expect(result.groups[0].amountPerPerson, 8500);
      expect(result.groups[1].amountPerPerson, 4500);
      expectTotalMatches(result, 30000);
    });

    test('四捨五入で集めすぎたときは上のグループが減額で調整する', () {
      final result = calculateWeightedSplit(
        totalAmount: 30000,
        unit: 500,
        groups: const [
          SplitGroup(name: '多め', count: 2, weight: 2),
          SplitGroup(name: '少なめ', count: 3, weight: 1),
        ],
      );
      // 8500×2 + 4500×3 = 30,500 で 500 円集めすぎ → 多めが 500 円ぶん減る
      expect(result.groups[0].isDiscount, isTrue);
      expect(result.extraBearer?.group.name, '多め');
      expectTotalMatches(result, 30000);
    });

    test('割り切れない端数は1円だけ多く負担する人が出る', () {
      final result = calculateWeightedSplit(
        totalAmount: 30001,
        unit: 500,
        groups: const [
          SplitGroup(name: '多め', count: 2, weight: 2),
          SplitGroup(name: '少なめ', count: 3, weight: 1),
        ],
      );
      final top = result.groups[0];
      expect(top.hasOddYen, isTrue);
      expect(top.amountWithExtraPlusOne - top.amountWithExtra, 1);
      expectTotalMatches(result, 30001);
      expectExtraSpreadEvenly(result);
    });

    test('端数の差は必ず1円以内に収まる（総当たり）', () {
      for (var amount = 20000; amount <= 20200; amount++) {
        final result = calculateWeightedSplit(
          totalAmount: amount,
          unit: 500,
          groups: const [
            SplitGroup(name: 'A', count: 3, weight: 1.7),
            SplitGroup(name: 'B', count: 4, weight: 1.0),
          ],
        );
        expectTotalMatches(result, amount);
        expectExtraSpreadEvenly(result);
        expectAmountsFitUnit(result);
      }
    });

    test('端数を負担するのは重みがいちばん大きいグループ', () {
      final result = calculateWeightedSplit(
        totalAmount: 10001,
        groups: const [
          SplitGroup(name: '軽い', count: 2, weight: 1),
          SplitGroup(name: '重い', count: 2, weight: 2),
        ],
      );
      expect(result.extraBearer?.group.name, '重い');
      expect(result.groups[0].hasExtra, isFalse);
      expectTotalMatches(result, 10001);
    });
  });

  group('集金者を計算に含める', () {
    test('集金者もグループの人数として計算に入る', () {
      // 多め2人（うち1人が集金者）+ 少なめ3人 = 5人で 30,000 円を割る
      final result = calculateWeightedSplit(
        totalAmount: 30000,
        unit: 500,
        organizerGroupIndex: 0,
        groups: const [
          SplitGroup(name: '多め', count: 2, weight: 2),
          SplitGroup(name: '少なめ', count: 3, weight: 1),
        ],
      );
      expect(result.includesOrganizer, isTrue);
      expect(result.totalCount, 5);
      // 集金者の分は請求しないので、集金するのは4人
      expect(result.payerCount, 4);
      expectTotalMatches(result, 30000);
    });

    test('集金者の自己負担を除いた額が集金額になる', () {
      final result = calculateWeightedSplit(
        totalAmount: 30000,
        unit: 500,
        organizerGroupIndex: 0,
        groups: const [
          SplitGroup(name: '多め', count: 2, weight: 2),
          SplitGroup(name: '少なめ', count: 3, weight: 1),
        ],
      );
      // 四捨五入で 多め 8,500 円、少なめ 4,500 円 → 500 円集めすぎのため
      // 多め2人が 250 円ずつ減額され 8,250 円になる
      expect(result.organizerAmount, 8250);
      expect(result.collectAmount, 30000 - 8250);
      expect(result.organizerAmount + result.collectAmount, 30000);
    });

    test('集金者が少ないランクに属する場合も正しく計算される', () {
      final result = calculateWeightedSplit(
        totalAmount: 30000,
        unit: 500,
        organizerGroupIndex: 1,
        groups: const [
          SplitGroup(name: '多め', count: 2, weight: 2),
          SplitGroup(name: '少なめ', count: 3, weight: 1),
        ],
      );
      expect(result.groups[0].organizerCount, 0);
      expect(result.groups[1].organizerCount, 1);
      // 集金者は少なめグループなので、その1人あたり金額が自己負担になる
      expect(result.organizerAmount, result.groups[1].amountWithExtra);
      expect(result.organizerAmount + result.collectAmount, 30000);
      expect(result.payerCount, 4);
      expectTotalMatches(result, 30000);
    });

    test('集金者を含めないと1人あたりの負担が増える', () {
      const groups = [
        SplitGroup(name: '多め', count: 2, weight: 2),
        SplitGroup(name: '少なめ', count: 3, weight: 1),
      ];
      final withOrganizer = calculateWeightedSplit(
        totalAmount: 30000,
        unit: 500,
        organizerGroupIndex: 0,
        groups: groups,
      );
      final withoutOrganizer = calculateWeightedSplit(
        totalAmount: 30000,
        unit: 500,
        groups: groups,
      );
      // 金額の割り振り自体は同じ。違いは「誰に請求するか」だけ
      expect(
        withOrganizer.groups[0].amountWithExtra,
        withoutOrganizer.groups[0].amountWithExtra,
      );
      expect(withOrganizer.collectAmount, lessThan(withoutOrganizer.collectAmount));
      expect(withoutOrganizer.collectAmount, 30000);
      expect(withoutOrganizer.payerCount, 5);
    });

    test('端数を負担するグループに集金者がいる場合、集金者が1円多い方を引き受ける', () {
      final result = calculateWeightedSplit(
        totalAmount: 30001,
        unit: 500,
        organizerGroupIndex: 0,
        groups: const [
          SplitGroup(name: '多め', count: 2, weight: 2),
          SplitGroup(name: '少なめ', count: 3, weight: 1),
        ],
      );
      final top = result.groups[0];
      expect(top.hasOddYen, isTrue);
      expect(result.organizerAmount, top.amountWithExtraPlusOne);
      expect(result.organizerAmount + result.collectAmount, 30001);
    });

    test('集金者のグループ指定が範囲外なら例外になる', () {
      expect(
        () => calculateWeightedSplit(
          totalAmount: 10000,
          organizerGroupIndex: 5,
          groups: const [SplitGroup(name: 'A', count: 2, weight: 1)],
        ),
        throwsArgumentError,
      );
    });
  });

  group('基本の割り振り', () {
    test('割り切れる場合はグループ内が同額になる', () {
      final result = calculateWeightedSplit(
        totalAmount: 10000,
        groups: const [
          SplitGroup(name: 'A', count: 1, weight: 2),
          SplitGroup(name: 'B', count: 2, weight: 1),
        ],
      );
      expect(result.groups[0].amountWithExtra, 5000);
      expect(result.groups[1].amountWithExtra, 2500);
      expect(result.hasExtra, isFalse);
      expectTotalMatches(result, 10000);
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
        result.groups[0].amountWithExtra,
        greaterThan(result.groups[1].amountWithExtra),
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
        organizerGroupIndex: 0,
        groups: const [
          SplitGroup(name: 'A', count: 1, weight: 3),
          SplitGroup(name: 'B', count: 2, weight: 2),
          SplitGroup(name: 'C', count: 3, weight: 1),
          SplitGroup(name: 'D', count: 4, weight: 0.5),
        ],
      );
      expect(result.totalCount, 10);
      expect(result.payerCount, 9);
      expectTotalMatches(result, 9999);
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

    test('単位が大きすぎると0円のグループが出ることを検知できる', () {
      final result = calculateWeightedSplit(
        totalAmount: 3000,
        unit: 1000,
        groups: const [
          SplitGroup(name: '多め', count: 1, weight: 3),
          SplitGroup(name: '少なめ', count: 5, weight: 1),
        ],
      );
      expect(result.hasZeroAmount, isTrue);
      expectTotalMatches(result, 3000);
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
          unit: 0,
          groups: const [SplitGroup(name: 'A', count: 2, weight: 1)],
        ),
        throwsArgumentError,
      );
    });

    test('validateSplitGroups は正しい入力に null を返す', () {
      expect(
        validateSplitGroups(
          const [
            SplitGroup(name: 'A', count: 1, weight: 1),
            SplitGroup(name: 'B', count: 1, weight: 2),
          ],
          organizerGroupIndex: 0,
        ),
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

    test('集金者のグループ指定が範囲外ならメッセージを返す', () {
      expect(
        validateSplitGroups(
          const [SplitGroup(name: 'A', count: 2, weight: 1)],
          organizerGroupIndex: 3,
        ),
        isNotNull,
      );
    });
  });

  group('splitPresets', () {
    test('すべてのプリセットが各単位・集金者ありで計算できる', () {
      for (final preset in splitPresets) {
        final groups =
            preset.groups.map((g) => g.copyWith(count: g.count + 1)).toList();
        expect(validateSplitGroups(groups), isNull, reason: preset.label);
        for (final unit in splitUnits) {
          final result = calculateWeightedSplit(
            totalAmount: 20000,
            unit: unit,
            organizerGroupIndex: 0,
            groups: groups,
          );
          expectTotalMatches(result, 20000);
          expectExtraSpreadEvenly(result);
          expect(result.organizerAmount + result.collectAmount, 20000);
        }
      }
    });
  });
}
