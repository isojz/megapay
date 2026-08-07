import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// 入金・出金のモック。
///
/// バックエンドに入出金の API がないため、増減額をこの端末にだけ保存し、
/// サーバーから取得した残高に上乗せして表示する。
///
/// 注意: サーバー上の残高は変わらない。そのため送金や請求の支払いなど、
/// サーバー側で残高を判定する処理には反映されない（表示だけのモック）。
class MockFunding {
  MockFunding._();

  static const _offsetKey = 'mock_funding_offset_jpy';

  /// 端末に保存されている増減額（円）。入金でプラス、出金でマイナスに動く。
  static Future<int> offset() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getInt(_offsetKey) ?? 0;
  }

  /// 入金分を加算する。
  static Future<void> deposit(int amount) => _add(amount);

  /// 出金分を減算する。
  static Future<void> withdraw(int amount) => _add(-amount);

  static Future<void> _add(int amount) async {
    final preferences = await SharedPreferences.getInstance();
    final current = preferences.getInt(_offsetKey) ?? 0;
    await preferences.setInt(_offsetKey, current + amount);
  }

  /// 残高一覧に増減額を反映する。
  ///
  /// 日本円の行がまだ無い場合でも、入金済みなら行を作って表示する。
  static List<Balance> apply(
      List<Balance> balances, int offset, String currency) {
    if (offset == 0) return balances;

    var found = false;
    final applied = balances.map((balance) {
      if (balance.currency != currency) return balance;
      found = true;
      final base = double.tryParse(balance.amount) ?? 0;
      // 引き出しすぎでマイナスにならないよう 0 で止める
      final total = (base + offset).clamp(0, double.infinity);
      return Balance(currency: currency, amount: total.toStringAsFixed(0));
    }).toList();

    if (!found && offset > 0) {
      applied.add(Balance(currency: currency, amount: offset.toString()));
    }
    return applied;
  }
}
