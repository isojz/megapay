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
    required this.extraPersonCount,
  });

  final SplitGroup group;

  /// このグループの 1 人あたりの金額（端数調整前の基本額）
  final int amountPerPerson;

  /// 端数調整で 1 円だけ多く払う人数（0 ならグループ内は全員同額）
  final int extraPersonCount;

  /// このグループの合計金額
  int get totalAmount => amountPerPerson * group.count + extraPersonCount;

  /// グループ内で金額に差が出ているか
  bool get hasRounding => extraPersonCount > 0;

  /// 端数を多く負担する人の金額
  int get amountWithExtra => amountPerPerson + 1;
}

/// 傾斜配分の計算結果。
class SplitResult {
  const SplitResult({required this.groups, required this.totalAmount});

  final List<SplitGroupResult> groups;

  /// 配分後の合計金額（入力した合計金額と必ず一致する）
  final int totalAmount;

  int get totalCount =>
      groups.fold(0, (sum, result) => sum + result.group.count);

  /// 端数調整が発生しているか（発生していれば UI で補足を出す）
  bool get hasRounding => groups.any((result) => result.hasRounding);
}

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
/// 1 人あたりの金額は「合計 × 重み ÷ 重み付き人数の合計」を切り捨てた額を基本とし、
/// 切り捨てで余った分は重みの大きいグループから 1 円ずつ割り当てる。
/// これにより配分後の合計は必ず [totalAmount] と一致する。
///
/// [groups] が不正な場合は [ArgumentError] を投げる（事前に [validateSplitGroups] で確認する）。
SplitResult calculateWeightedSplit({
  required int totalAmount,
  required List<SplitGroup> groups,
}) {
  if (totalAmount <= 0) {
    throw ArgumentError.value(totalAmount, 'totalAmount', '合計金額は1以上である必要があります');
  }
  final error = validateSplitGroups(groups);
  if (error != null) throw ArgumentError(error);

  // 重み付きの人数（例: 2人×2.0 + 3人×1.0 = 7.0）
  final weightedCount = groups.fold<double>(
    0,
    (sum, group) => sum + group.count * group.weight,
  );

  // 1. 各グループの基本額（切り捨て）
  final baseAmounts = groups
      .map((group) => (totalAmount * group.weight / weightedCount).floor())
      .toList();

  // 2. 切り捨てで足りない分を求める
  var assigned = 0;
  for (var i = 0; i < groups.length; i++) {
    assigned += baseAmounts[i] * groups[i].count;
  }
  var remainder = totalAmount - assigned;

  // 3. 余りを重みの大きいグループから 1 人 1 円ずつ割り当てる
  //    （重みが同じなら先に並んでいるグループを優先）
  final extras = List.filled(groups.length, 0);
  final order = List.generate(groups.length, (i) => i)
    ..sort((a, b) {
      final byWeight = groups[b].weight.compareTo(groups[a].weight);
      return byWeight != 0 ? byWeight : a.compareTo(b);
    });
  for (final i in order) {
    if (remainder <= 0) break;
    final add = remainder < groups[i].count ? remainder : groups[i].count;
    extras[i] = add;
    remainder -= add;
  }

  return SplitResult(
    groups: [
      for (var i = 0; i < groups.length; i++)
        SplitGroupResult(
          group: groups[i],
          amountPerPerson: baseAmounts[i],
          extraPersonCount: extras[i],
        ),
    ],
    totalAmount: totalAmount,
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
