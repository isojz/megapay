import 'package:web/web.dart' as web;

/// 現在のアプリURLを基準に、割り勘コード入りの共有リンクを作る。
String buildSplitBillPaymentLink(String billCode) {
  final current = Uri.parse(web.window.location.href);
  final parameters = Map<String, String>.from(current.queryParameters)
    ..['split_code'] = billCode;
  return current.replace(queryParameters: parameters, fragment: '').toString();
}

/// 現在URLから指定したクエリパラメータだけを、画面遷移せずに削除する。
void removeQueryParameter(String key) {
  final current = Uri.parse(web.window.location.href);
  final parameters = Map<String, String>.from(current.queryParameters)
    ..remove(key);
  final updated = Uri(
    scheme: current.scheme,
    userInfo: current.userInfo,
    host: current.host,
    port: current.hasPort ? current.port : null,
    path: current.path,
    queryParameters: parameters.isEmpty ? null : parameters,
    fragment: current.fragment.isEmpty ? null : current.fragment,
  );
  web.window.history.replaceState(null, '', updated.toString());
}
