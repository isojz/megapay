import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models/models.dart';
import '../models/payment_request.dart';

/// バックエンド API 呼び出しで発生したエラー。
/// message はそのままユーザーに表示できる日本語文言。
class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

/// FastAPI バックエンドへの HTTP クライアント。
/// Supabase Auth のアクセストークンを Authorization ヘッダに付与する。
class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  Map<String, String> get _headers {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Uri _uri(String path) => Uri.parse('${AppConfig.apiBaseUrl}$path');

  Future<dynamic> _get(String path) async {
    final http.Response res;
    try {
      res = await http.get(_uri(path), headers: _headers);
    } catch (_) {
      throw ApiException(0, 'サーバーに接続できませんでした');
    }
    return _decode(res);
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final http.Response res;
    try {
      res = await http.post(_uri(path), headers: _headers, body: jsonEncode(body));
    } catch (_) {
      throw ApiException(0, 'サーバーに接続できませんでした');
    }
    return _decode(res);
  }

  dynamic _decode(http.Response res) {
    final dynamic body =
        res.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, _errorMessage(body, res.statusCode));
    }
    return body;
  }

  String _errorMessage(dynamic body, int statusCode) {
    if (body is Map<String, dynamic>) {
      final detail = body['detail'];
      if (detail is String) return detail;
      // FastAPI のバリデーションエラー（422）は detail がリストで返る
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map<String, dynamic> && first['msg'] is String) {
          return '入力内容に誤りがあります（${first['msg']}）';
        }
        return '入力内容に誤りがあります';
      }
    }
    return 'エラーが発生しました（コード: $statusCode）';
  }

  Future<Profile> fetchProfile() async =>
      Profile.fromJson(await _get('/api/v1/me') as Map<String, dynamic>);

  Future<List<Balance>> fetchBalances() async => (await _get('/api/v1/balances') as List)
      .map((e) => Balance.fromJson(e as Map<String, dynamic>))
      .toList();

  Future<RecipientInfo> lookupRecipient(String recipientUserId) async =>
      RecipientInfo.fromJson(
        await _get('/api/v1/recipients/${Uri.encodeComponent(recipientUserId)}')
            as Map<String, dynamic>,
      );

  // ---------------- 請求（payment requests） ----------------

  /// 請求を作成し、支払い用の請求コードを発行する
  Future<PaymentRequest> createPaymentRequest({
    required String payerUserId,
    required String currency,
    required String amount,
    String? memo,
  }) async =>
      PaymentRequest.fromJson(
        await _post('/api/v1/payment-requests', {
          'payer_user_id': payerUserId,
          'currency': currency,
          'amount': amount,
          if (memo != null && memo.isNotEmpty) 'memo': memo,
        }) as Map<String, dynamic>,
      );

  /// 請求コードから内容を取得する（支払い前の確認用）
  Future<PaymentRequest> lookupPaymentRequest(String requestCode) async =>
      PaymentRequest.fromJson(
        await _get('/api/v1/payment-requests/${Uri.encodeComponent(requestCode)}')
            as Map<String, dynamic>,
      );

  /// 請求コードを指定して支払う（送金が実行される）
  Future<PaymentRequest> payPaymentRequest(String requestCode) async =>
      PaymentRequest.fromJson(
        await _post(
          '/api/v1/payment-requests/${Uri.encodeComponent(requestCode)}/pay',
          const {},
        ) as Map<String, dynamic>,
      );

  /// 請求を取り消す（請求した本人・未払いのもののみ）
  Future<PaymentRequest> cancelPaymentRequest(String requestCode) async =>
      PaymentRequest.fromJson(
        await _post(
          '/api/v1/payment-requests/${Uri.encodeComponent(requestCode)}/cancel',
          const {},
        ) as Map<String, dynamic>,
      );

  /// 自分が請求した / 請求された一覧（請求状況の確認）
  Future<List<PaymentRequest>> fetchPaymentRequests() async =>
      (await _get('/api/v1/payment-requests') as List)
          .map((e) => PaymentRequest.fromJson(e as Map<String, dynamic>))
          .toList();

  // ---------------- 送金 ----------------

  Future<void> sendTransfer({
    required String recipientUserId,
    required String currency,
    required String amount,
    String? memo,
  }) async {
    await _post('/api/v1/transfers', {
      'recipient_user_id': recipientUserId,
      'currency': currency,
      'amount': amount,
      if (memo != null && memo.isNotEmpty) 'memo': memo,
    });
  }

  Future<List<TransferRecord>> fetchTransfers() async =>
      (await _get('/api/v1/transfers') as List)
          .map((e) => TransferRecord.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<List<SavedUser>> fetchSavedUsers() async =>
      (await _get('/api/v1/saved-users') as List)
          .map((e) => SavedUser.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<RecipientInfo> saveUser(String userId) async =>
      RecipientInfo.fromJson(
        await _post('/api/v1/saved-users', {'user_id': userId})
            as Map<String, dynamic>,
      );
}
