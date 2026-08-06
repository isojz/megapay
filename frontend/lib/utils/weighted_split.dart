/// 割り勘の傾斜（重み付け）配分の計算。
///
/// 画面から切り離した純粋な計算処理なので、UI なしで単体テストできる。
/// 合計金額が 1 円もずれないことを保証するのがこの計算の役目。
library;

/// 傾斜配分の 1 グループ分の設定。
///
/// 例: 「先輩」が 2 人で重み 2.0、「後輩」が 3 人で重み 1.0
class SplitGroup {
  const SplitGroup({
    required this.name,
    required this.count,
    required this.weight,
  });

  final String name;

  /// このグループの人数
  final int count;

  /// 1 人あたりの負担の重み（1.0 を基準にする）
  final double weight;

  SplitGroup copyWith({String? name, int? count, double? weight}) => SplitGroup(
        name: name ?? this.name,
        count: count ?? this.count,
        weight: weight ?? this.weight,
      );
}

/// 1 グループ分の配分結果。
class SplitGroupResult {
  const SplitGroupResult({
    required this.group,
    required this.amountPerPerson,
    required this.extraAmount,
  });

  final SplitGroup group;

  /// このグループの 1 人あたりの金額（割り振り単位で丸めた額）
  final int amountPerPerson;

  /// 端数を引き受ける人が上乗せで負担する額。
  /// 端数は重みがいちばん大きいグループの 1 人にまとめて寄せるため、
  /// このグループが端数の引き受け先でなければ 0 になる。
  final int extraAmount;

  /// このグループの合計金額
  int get totalAmount => amountPerPerson * group.count + extraAmount;

  /// このグループに端数の引き受け役がいるか
  bool get hasExtra => extraAmount > 0;

  /// 端数を引き受ける人の金額
  int get amountWithExtra => amountPerPerson + extraAmount;
}

/// 傾斜配分の計算結果。
class SplitResult {
  const SplitResult({
    required this.groups,
    required this.totalAmount,
    required this.unit,
  });

  final List<SplitGroupResult> groups;

  /// 配分後の合計金額（入力した合計金額と必ず一致する）
  final int totalAmount;

  /// 割り振りに使った単位（1 / 100 / 500 / 1000 円など）
  final int unit;

  int get totalCount =>
      groups.fold(0, (sum, result) => sum + result.group.count);

  /// 端数の上乗せが発生しているか（発生していれば UI で補足を出す）
  bool get hasExtra => groups.any((result) => result.hasExtra);

  /// 端数を引き受けたグループ（いなければ null）
  SplitGroupResult? get extraBearer {
    for (final result in groups) {
      if (result.hasExtra) return result;
    }
    return null;
  }

  /// 単位が大きすぎて 1 人あたり 0 円になったグループがあるか
  bool get hasZeroAmount =>
      groups.any((result) => result.amountPerPerson <= 0);
}

/// 割り振りの単位として選べる金額。
const splitUnits = <int>[1, 100, 500, 1000];

/// 傾斜配分の入力が正しいかを判定する。問題がなければ null を返す。
String? validateSplitGroups(List<SplitGroup> groups) {
  if (groups.isEmpty) return 'グループを1つ以上追加してください';
  for (final group in groups) {
    if (group.name.trim().isEmpty) return 'グループ名を入力してください';
    if (group.count < 1) return '各グループの人数は1人以上にしてください';
    if (group.weight <= 0) return '重みは0より大きい値にしてください';
  }
  final totalCount = groups.fold(0, (sum, group) => sum + group.count);
  if (totalCount < 2) return '合計人数は2人以上にしてください';
  return null;
}

/// 合計金額をグループの重みに応じて配分する。
///
/// 1 人あたりの金額は「合計 × 重み ÷ 重み付き人数の合計」を [unit] 単位に切り捨てた額。
/// 切り捨てで余った分（端数）は、重みがいちばん大きいグループの 1 人がまとめて負担する。
/// これにより、ほとんどの人はきりのよい金額になり、配分後の合計は必ず [totalAmount] と一致する。
///
/// 例: 30,000 円 / 多め2人(重み2) + 少なめ3人(重み1) / 500 円単位
///   多め   8,500 円（うち1人は 9,500 円）
///   少なめ 4,000 円
///   合計 30,000 円
///
/// [groups] が不正な場合は [ArgumentError] を投げる（事前に [validateSplitGroups] で確認する）。
SplitResult calculateWeightedSplit({
  required int totalAmount,
  required List<SplitGroup> groups,
  int unit = 1,
}) {
  if (totalAmount <= 0) {
    throw ArgumentError.value(totalAmount, 'totalAmount', '合計金額は1以上である必要があります');
  }
  if (unit < 1) {
    throw ArgumentError.value(unit, 'unit', '割り振りの単位は1以上である必要があります');
  }
  final error = validateSplitGroups(groups);
  if (error != null) throw ArgumentError(error);

  // 重み付きの人数（例: 2人×2.0 + 3人×1.0 = 7.0）
  final weightedCount = groups.fold<double>(
    0,
    (sum, group) => sum + group.count * group.weight,
  );

  // 1. 各グループの 1 人あたりの金額を unit 単位に切り捨てる
  final baseAmounts = groups.map((group) {
    final ideal = totalAmount * group.weight / weightedCount;
    return (ideal / unit).floor() * unit;
  }).toList();

  // 2. 切り捨てで足りない分（端数）を求める。切り捨てなので必ず 0 以上になる。
  var assigned = 0;
  for (var i = 0; i < groups.length; i++) {
    assigned += baseAmounts[i] * groups[i].count;
  }
  final remainder = totalAmount - assigned;

  // 3. 端数は重みがいちばん大きいグループの 1 人がまとめて引き受ける
  //    （重みが同じなら先に並んでいるグループ）
  var topIndex = 0;
  for (var i = 1; i < groups.length; i++) {
    if (groups[i].weight > groups[topIndex].weight) topIndex = i;
  }

  return SplitResult(
    groups: [
      for (var i = 0; i < groups.length; i++)
        SplitGroupResult(
          group: groups[i],
          amountPerPerson: baseAmounts[i],
          extraAmount: i == topIndex ? remainder : 0,
        ),
    ],
    totalAmount: totalAmount,
    unit: unit,
  );
}

/// 傾斜のプリセット。作成画面で「まずこれを試す」提案として使う。
class SplitPreset {
  const SplitPreset({required this.label, required this.groups});

  final String label;
  final List<SplitGroup> groups;
}

/// よくある傾斜のパターン。人数は入力してもらう前提で 1 人ずつ入れておく。
const splitPresets = <SplitPreset>[
  SplitPreset(
    label: '2段階（多め・少なめ）',
    groups: [
      SplitGroup(name: '多めに払う人', count: 1, weight: 1.5),
      SplitGroup(name: '少なめに払う人', count: 1, weight: 1.0),
    ],
  ),
  SplitPreset(
    label: '3段階（多め・普通・少なめ）',
    groups: [
      SplitGroup(name: '多めに払う人', count: 1, weight: 2.0),
      SplitGroup(name: '普通', count: 1, weight: 1.5),
      SplitGroup(name: '少なめに払う人', count: 1, weight: 1.0),
    ],
  ),
  SplitPreset(
    label: '先輩・後輩',
    groups: [
      SplitGroup(name: '先輩', count: 1, weight: 2.0),
      SplitGroup(name: '後輩', count: 1, weight: 1.0),
    ],
  ),
  SplitPreset(
    label: '飲む人・飲まない人',
    groups: [
      SplitGroup(name: '飲む人', count: 1, weight: 1.5),
      SplitGroup(name: '飲まない人', count: 1, weight: 1.0),
    ],
  ),
];
