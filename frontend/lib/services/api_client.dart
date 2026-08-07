import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models/models.dart';
import '../models/payment_request.dart';
import '../models/split_bill.dart';

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
      res = await http.get(
        _uri(path),
        headers: _headers,
      );
    } catch (_) {
      throw ApiException(0, 'サーバーに接続できませんでした');
    }

    return _decode(res);
  }

  Future<dynamic> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final http.Response res;

    try {
      res = await http.post(
        _uri(path),
        headers: _headers,
        body: jsonEncode(body),
      );
    } catch (_) {
      throw ApiException(0, 'サーバーに接続できませんでした');
    }

    return _decode(res);
  }

  Future<dynamic> _patch(
    String path,
    Map<String, dynamic> body,
  ) async {
    final http.Response res;

    try {
      res = await http.patch(
        _uri(path),
        headers: _headers,
        body: jsonEncode(body),
      );
    } catch (_) {
      throw ApiException(0, 'サーバーに接続できませんでした');
    }

    return _decode(res);
  }

  dynamic _decode(http.Response res) {
    final dynamic body = res.bodyBytes.isEmpty
        ? null
        : jsonDecode(
            utf8.decode(res.bodyBytes),
          );

    if (res.statusCode >= 400) {
      throw ApiException(
        res.statusCode,
        _errorMessage(body, res.statusCode),
      );
    }

    return body;
  }

  String _errorMessage(
    dynamic body,
    int statusCode,
  ) {
    if (body is Map<String, dynamic>) {
      final detail = body['detail'];

      if (detail is String) {
        return detail;
      }

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

  Future<Profile> fetchProfile() async => Profile.fromJson(
        await _get('/api/v1/me') as Map<String, dynamic>,
      );

  Future<Profile> updateAvatar(String avatarKey) async => Profile.fromJson(
        await _patch(
          '/api/v1/me/avatar',
          {
            'avatar_key': avatarKey,
          },
        ) as Map<String, dynamic>,
      );

  Future<List<Balance>> fetchBalances() async =>
      (await _get('/api/v1/balances') as List)
          .map(
            (e) => Balance.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList();

  Future<RecipientInfo> lookupRecipient(
    String recipientUserId,
  ) async =>
      RecipientInfo.fromJson(
        await _get(
          '/api/v1/recipients/${Uri.encodeComponent(recipientUserId)}',
        ) as Map<String, dynamic>,
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
        await _post(
          '/api/v1/payment-requests',
          {
            'payer_user_id': payerUserId,
            'currency': currency,
            'amount': amount,
            if (memo != null && memo.isNotEmpty) 'memo': memo,
          },
        ) as Map<String, dynamic>,
      );

  /// 請求コードから内容を取得する（支払い前の確認用）
  Future<PaymentRequest> lookupPaymentRequest(
    String requestCode,
  ) async =>
      PaymentRequest.fromJson(
        await _get(
          '/api/v1/payment-requests/${Uri.encodeComponent(requestCode)}',
        ) as Map<String, dynamic>,
      );

  /// 請求コードを指定して支払う（送金が実行される）
  Future<PaymentRequest> payPaymentRequest(
    String requestCode,
  ) async =>
      PaymentRequest.fromJson(
        await _post(
          '/api/v1/payment-requests/'
          '${Uri.encodeComponent(requestCode)}/pay',
          const {},
        ) as Map<String, dynamic>,
      );

  /// PayPay・カードなどの外部決済で支払う。
  /// 引き落としは外部の決済事業者側で行われる想定のため、自分の残高は減らない。
  /// 集金者の残高と、双方の送金履歴には反映される。
  Future<PaymentRequest> payPaymentRequestByExternal(
          String requestCode) async =>
      PaymentRequest.fromJson(
        await _post(
          '/api/v1/payment-requests/${Uri.encodeComponent(requestCode)}/pay-external',
          const {},
        ) as Map<String, dynamic>,
      );

  /// 現金で支払ったことを記録する（残高・送金履歴は変更されない）
  Future<PaymentRequest> payPaymentRequestByCash(
    String requestCode,
  ) async =>
      PaymentRequest.fromJson(
        await _post(
          '/api/v1/payment-requests/'
          '${Uri.encodeComponent(requestCode)}/pay-cash',
          const {},
        ) as Map<String, dynamic>,
      );

  /// 請求を取り消す（請求した本人・未払いのもののみ）
  Future<PaymentRequest> cancelPaymentRequest(
    String requestCode,
  ) async =>
      PaymentRequest.fromJson(
        await _post(
          '/api/v1/payment-requests/'
          '${Uri.encodeComponent(requestCode)}/cancel',
          const {},
        ) as Map<String, dynamic>,
      );

  /// 自分が請求した / 請求された一覧（請求状況の確認）
  Future<List<PaymentRequest>> fetchPaymentRequests() async =>
      (await _get('/api/v1/payment-requests') as List)
          .map(
            (e) => PaymentRequest.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList();

  // ---------------- 割り勘（split bills） ----------------

  /// 割り勘を登録し、参加用の請求コードを発行する（集金者）
  Future<SplitBill> createSplitBill({
    required String title,
    required String currency,
    required String totalAmount,
    required int participantCount,
  }) async =>
      SplitBill.fromJson(
        await _post(
          '/api/v1/split-bills',
          {
            'title': title,
            'currency': currency,
            'total_amount': totalAmount,
            'participant_count': participantCount,
          },
        ) as Map<String, dynamic>,
      );

  Future<SplitBill> createRankedSplitBillTest({
    required String title,
    required int participantCount,
  }) async =>
      SplitBill.fromJson(
        await _post('/api/v1/split-bills/ranked-test', {
          'title': title,
          'participant_count': participantCount,
        }) as Map<String, dynamic>,
      );

  Future<SplitBill> createRankedSplitBill({
    required String title,
    required String currency,
    required List<Map<String, dynamic>> ranks,
  }) async =>
      SplitBill.fromJson(
        await _post('/api/v1/split-bills/ranked', {
          'title': title,
          'currency': currency,
          'ranks': ranks,
        }) as Map<String, dynamic>,
      );

  /// 割り勘リンク用の限定情報を取得する（ログイン不要）
  Future<PublicSplitBill> lookupPublicSplitBill(
    String billCode,
  ) async =>
      PublicSplitBill.fromJson(
        await _get(
          '/api/v1/split-bills/public/'
          '${Uri.encodeComponent(billCode)}',
        ) as Map<String, dynamic>,
      );

  /// 請求コードから割り勘の内容を取得する（参加前の確認）
  Future<SplitBill> lookupSplitBill(
    String billCode,
  ) async =>
      SplitBill.fromJson(
        await _get(
          '/api/v1/split-bills/'
          '${Uri.encodeComponent(billCode)}',
        ) as Map<String, dynamic>,
      );

  /// 請求コードでグループに参加する（同時に自分あての請求が作成される）
  Future<SplitBill> joinSplitBill(
    String billCode,
  ) async =>
      SplitBill.fromJson(
        await _post(
          '/api/v1/split-bills/'
          '${Uri.encodeComponent(billCode)}/join',
          const {},
        ) as Map<String, dynamic>,
      );

  Future<SplitBill> joinRankedSplitBill(
    String billCode,
    String rankCode,
  ) async =>
      SplitBill.fromJson(
        await _post(
          '/api/v1/split-bills/${Uri.encodeComponent(billCode)}/join-ranked',
          {'rank_code': rankCode},
        ) as Map<String, dynamic>,
      );

  /// グループの参加者と支払い状況の一覧
  Future<List<SplitBillParticipant>> fetchSplitBillParticipants(
    String billCode,
  ) async =>
      (await _get(
        '/api/v1/split-bills/'
        '${Uri.encodeComponent(billCode)}/participants',
      ) as List)
          .map(
            (e) => SplitBillParticipant.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList();

  /// 自分が関わる割り勘の一覧（集金した分・参加した分）
  Future<List<SplitBill>> fetchSplitBills() async =>
      (await _get('/api/v1/split-bills') as List)
          .map(
            (e) => SplitBill.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList();

  // ---------------- 送金 ----------------

  Future<void> sendTransfer({
    required String recipientUserId,
    required String currency,
    required String amount,
    String? memo,
  }) async {
    await _post(
      '/api/v1/transfers',
      {
        'recipient_user_id': recipientUserId,
        'currency': currency,
        'amount': amount,
        if (memo != null && memo.isNotEmpty) 'memo': memo,
      },
    );
  }

  Future<List<TransferRecord>> fetchTransfers() async =>
      (await _get('/api/v1/transfers') as List)
          .map(
            (e) => TransferRecord.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList();

  Future<List<SavedUser>> fetchSavedUsers() async =>
      (await _get('/api/v1/saved-users') as List)
          .map(
            (e) => SavedUser.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList();

  Future<RecipientInfo> saveUser(
    String userId,
  ) async =>
      RecipientInfo.fromJson(
        await _post(
          '/api/v1/saved-users',
          {
            'user_id': userId,
          },
        ) as Map<String, dynamic>,
      );
}
