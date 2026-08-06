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
    required this.extraPerPerson,
    required this.extraExtraCount,
    required this.organizerCount,
  });

  final SplitGroup group;

  /// このグループの 1 人あたりの金額（割り振り単位で丸めた額）
  final int amountPerPerson;

  /// 端数をこのグループで調整する場合の 1 人あたりの増減額。
  /// 四捨五入で足りなければプラス、集めすぎならマイナスになる。
  /// 調整は重みがいちばん大きいグループの人たちで 1 円単位に分けるため、
  /// このグループが調整先でなければ 0 になる。
  final int extraPerPerson;

  /// 上の調整をさらに 1 円だけ多く負担する人数（端数が人数で割り切れないとき）
  final int extraExtraCount;

  /// このグループに含まれる集金者の人数（0 か 1）
  final int organizerCount;

  /// 端数の調整が発生しているか（増額・減額どちらも含む）
  bool get hasExtra => extraPerPerson != 0 || extraExtraCount != 0;

  /// このグループの基本の 1 人あたり金額（端数の上乗せ込み）
  int get amountWithExtra => amountPerPerson + extraPerPerson;

  /// 端数を 1 円多く負担する人の金額
  int get amountWithExtraPlusOne => amountWithExtra + 1;

  /// グループ内で金額が 2 種類になるか（1 円差が出るか）
  bool get hasOddYen => extraExtraCount > 0 && extraExtraCount < group.count;

  /// 端数の調整で減額になっているか（四捨五入で集めすぎたとき）
  bool get isDiscount => extraPerPerson < 0;

  /// このグループの合計金額
  int get totalAmount =>
      (amountPerPerson + extraPerPerson) * group.count + extraExtraCount;

  /// 集金者を除いた、実際に集金する人数
  int get payerCount => group.count - organizerCount;

  /// 集金者が自分で負担する金額（集金者がいなければ 0）。
  /// 端数の 1 円は集金者から先に引き受けるため、集金者がいる場合は多い方の額になる。
  int get organizerAmount {
    if (organizerCount == 0) return 0;
    return extraExtraCount > 0 ? amountWithExtraPlusOne : amountWithExtra;
  }

  /// このグループから集金する金額（集金者の分を除く）
  int get collectAmount => totalAmount - organizerAmount;
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

  /// 集金者を含めた総人数
  int get totalCount =>
      groups.fold(0, (sum, result) => sum + result.group.count);

  /// 集金者を除いた、実際に集金する人数
  int get payerCount =>
      groups.fold(0, (sum, result) => sum + result.payerCount);

  /// 集金者が自分で負担する金額
  int get organizerAmount =>
      groups.fold(0, (sum, result) => sum + result.organizerAmount);

  /// 実際に集金する金額（合計から集金者の自己負担を引いた額）
  int get collectAmount => totalAmount - organizerAmount;

  /// 集金者が割り勘に含まれているか
  bool get includesOrganizer =>
      groups.any((result) => result.organizerCount > 0);

  /// 端数の上乗せが発生しているか（発生していれば UI で補足を出す）
  bool get hasExtra => groups.any((result) => result.hasExtra);

  /// 端数を負担したグループ（いなければ null）
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
///
/// [organizerGroupIndex] を渡すと、集金者を含めたうえで
/// 「集金する相手が 1 人以上いるか」まで確認する。
String? validateSplitGroups(
  List<SplitGroup> groups, {
  int? organizerGroupIndex,
}) {
  if (groups.isEmpty) return 'グループを1つ以上追加してください';
  for (final group in groups) {
    if (group.name.trim().isEmpty) return 'グループ名を入力してください';
    if (group.count < 1) return '各グループの人数は1人以上にしてください';
    if (group.weight <= 0) return '重みは0より大きい値にしてください';
  }
  final totalCount = groups.fold(0, (sum, group) => sum + group.count);
  if (totalCount < 2) return '合計人数は2人以上にしてください';
  if (organizerGroupIndex != null) {
    if (organizerGroupIndex < 0 || organizerGroupIndex >= groups.length) {
      return '集金者のグループを選んでください';
    }
    // 集金者を除いた人数が 0 だと集金する相手がいない
    if (totalCount - 1 < 1) return '集金する相手が1人以上必要です';
  }
  return null;
}

/// 合計金額をグループの重みに応じて配分する。
///
/// 1 人あたりの金額は「合計 × 重み ÷ 重み付き人数の合計」を [unit] 単位に四捨五入した額。
/// 500 円単位なら 249 円は切り捨てて 0 円に、250 円は切り上げて 500 円になる。
/// 四捨五入で生じたずれ（足りない分・集めすぎた分）は、重みがいちばん大きいグループの
/// 人たちで 1 円単位に分けて調整するため、配分後の合計は必ず [totalAmount] と一致する。
///
/// [organizerGroupIndex] に集金者が属するグループを指定すると、集金者もグループの人数に
/// 含めて計算する（＝集金者の分だけ他の人の負担が軽くなる）。集金者は自分に請求しないため、
/// 実際に集金するのは [SplitResult.collectAmount]。null なら集金者は割り勘に含めない。
///
/// 例: 30,000 円 / 多め2人(重み2) + 少なめ3人(重み1) / 500 円単位
///   多め   9,000 円（端数 1,000 円を 2 人で 500 円ずつ負担）
///   少なめ 4,000 円
///   合計 30,000 円
///
/// [groups] が不正な場合は [ArgumentError] を投げる（事前に [validateSplitGroups] で確認する）。
SplitResult calculateWeightedSplit({
  required int totalAmount,
  required List<SplitGroup> groups,
  int unit = 1,
  int? organizerGroupIndex,
}) {
  if (totalAmount <= 0) {
    throw ArgumentError.value(totalAmount, 'totalAmount', '合計金額は1以上である必要があります');
  }
  if (unit < 1) {
    throw ArgumentError.value(unit, 'unit', '割り振りの単位は1以上である必要があります');
  }
  final error = validateSplitGroups(groups);
  if (error != null) throw ArgumentError(error);
  if (organizerGroupIndex != null &&
      (organizerGroupIndex < 0 || organizerGroupIndex >= groups.length)) {
    throw ArgumentError.value(
      organizerGroupIndex,
      'organizerGroupIndex',
      '集金者のグループ指定が範囲外です',
    );
  }

  // 重み付きの人数（例: 2人×2.0 + 3人×1.0 = 7.0）
  final weightedCount = groups.fold<double>(
    0,
    (sum, group) => sum + group.count * group.weight,
  );

  // 1. 各グループの 1 人あたりの金額を unit 単位に四捨五入する
  //    （500 円単位なら 249 円は 0 円、250 円は 500 円になる）
  final baseAmounts = groups.map((group) {
    final ideal = totalAmount * group.weight / weightedCount;
    return (ideal / unit).round() * unit;
  }).toList();

  // 2. 四捨五入で生じたずれを求める。
  //    足りなければプラス、集めすぎならマイナスになる。
  var assigned = 0;
  for (var i = 0; i < groups.length; i++) {
    assigned += baseAmounts[i] * groups[i].count;
  }
  final remainder = totalAmount - assigned;

  // 3. ずれは重みがいちばん大きいグループの人たちで 1 円単位に分けて調整する
  //    （重みが同じなら先に並んでいるグループ）
  var topIndex = 0;
  for (var i = 1; i < groups.length; i++) {
    if (groups[i].weight > groups[topIndex].weight) topIndex = i;
  }
  final topCount = groups[topIndex].count;
  // マイナスでも正しく分けるため floor で求める（Dart の ~/ は 0 方向に丸めるため使わない）
  final extraPerPerson = (remainder / topCount).floor();
  // 均等に割れなかった 1 円は、そのグループの一部の人が引き受ける
  final extraExtraCount = remainder - extraPerPerson * topCount;

  return SplitResult(
    groups: [
      for (var i = 0; i < groups.length; i++)
        SplitGroupResult(
          group: groups[i],
          amountPerPerson: baseAmounts[i],
          extraPerPerson: i == topIndex ? extraPerPerson : 0,
          extraExtraCount: i == topIndex ? extraExtraCount : 0,
          organizerCount: i == organizerGroupIndex ? 1 : 0,
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
