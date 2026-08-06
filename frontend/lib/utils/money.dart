import 'package:intl/intl.dart';

/// 金額文字列を表示用に整形する。
/// 日本円は通貨コードではなく「円」で表示する。
/// 例: formatMoney('JPY', '500000') => '500,000 円'
///     formatMoney('USD', '120.5')  => '120.50 USD'
String formatMoney(String currency, String amount) {
  // 通貨コード（API とのやり取りに使う値）はそのまま、表示だけ「円」にする
  final unit = currency == 'JPY' ? '円' : currency;
  final value = double.tryParse(amount);
  if (value == null) {
    return '$amount $unit';
  }
  // JPY など小数を使わない通貨は整数表示、それ以外は 2〜8 桁の小数表示
  final pattern = currency == 'JPY' ? '#,##0' : '#,##0.00######';
  return '${NumberFormat(pattern).format(value)} $unit';
}

/// 日本円と分かっている場面で通貨コードを渡さずに使う。
/// 例: formatYen('500000') => '500,000 円'
String formatYen(String amount) => formatMoney('JPY', amount);

/// 履歴一覧などで使う日時表示。例: 2026/08/04 09:30
String formatDateTime(DateTime dateTime) {
  return DateFormat('yyyy/MM/dd HH:mm').format(dateTime);
}
