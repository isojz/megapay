import 'package:intl/intl.dart';

/// 金額文字列を通貨コード付きで表示用に整形する。
/// 例: formatMoney('JPY', '500000') => '500,000 JPY'
///     formatMoney('USD', '120.5')  => '120.50 USD'
String formatMoney(String currency, String amount) {
  final value = double.tryParse(amount);
  if (value == null) {
    return '$amount $currency';
  }
  // JPY など小数を使わない通貨は整数表示、それ以外は 2〜8 桁の小数表示
  final pattern = currency == 'JPY' ? '#,##0' : '#,##0.00######';
  return '${NumberFormat(pattern).format(value)} $currency';
}

/// 日本円を通貨コードなしで表示する。例: formatYen('500000') => '500,000 円'
/// 日本円のみを扱う画面で、'JPY' の代わりに使う。
String formatYen(String amount) {
  final value = double.tryParse(amount);
  if (value == null) {
    return '$amount 円';
  }
  return '${NumberFormat('#,##0').format(value)} 円';
}

/// 履歴一覧などで使う日時表示。例: 2026/08/04 09:30
String formatDateTime(DateTime dateTime) {
  return DateFormat('yyyy/MM/dd HH:mm').format(dateTime);
}
