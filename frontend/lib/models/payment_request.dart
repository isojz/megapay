/// 請求（payment request）のモデル。
/// 金額は桁落ち防止のため API 上は文字列で受け渡しする（表示時のみ数値化）。
library;

class PaymentRequest {
  const PaymentRequest({
    required this.requestCode,
    required this.direction,
    required this.requesterUserId,
    required this.requesterName,
    required this.payerUserId,
    required this.payerName,
    required this.currency,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.paymentMethod = 'balance',
    this.memo,
    this.paidAt,
    this.cancelledAt,
  });

  /// 支払い時に入力するコード（RQ-XXXXXXXX）
  final String requestCode;

  /// 自分から見た向き: "requested"（自分が請求した） / "billed"（自分が請求された）
  final String direction;

  final String requesterUserId; // 請求した人（受け取る側）
  final String requesterName;
  final String payerUserId; // 請求された人（支払う側）
  final String payerName;
  final String currency;
  final String amount;
  final String? memo;

  /// "pending"（未払い） / "paid"（支払い済み） / "cancelled"（取り消し済み）
  final String status;

  /// "balance"（残高から送金） / "cash"（現金で受け渡し）
  final String paymentMethod;

  final DateTime createdAt;
  final DateTime? paidAt;
  final DateTime? cancelledAt;

  bool get isRequestedByMe => direction == 'requested';
  bool get isPending => status == 'pending';
  bool get isPaid => status == 'paid';
  bool get isPaidByCash => paymentMethod == 'cash';

  /// 一覧やダイアログで表示する状態のラベル
  String get statusLabel => switch (status) {
        'paid' => '支払い済み',
        'cancelled' => '取り消し済み',
        _ => '未払い',
      };

  /// 自分から見た相手（請求した側なら支払う人、請求された側なら請求元）
  String get counterpartName => isRequestedByMe ? payerName : requesterName;
  String get counterpartUserId =>
      isRequestedByMe ? payerUserId : requesterUserId;

  factory PaymentRequest.fromJson(Map<String, dynamic> json) => PaymentRequest(
        requestCode: json['request_code'] as String,
        direction: json['direction'] as String,
        requesterUserId: json['requester_user_id'] as String,
        requesterName: json['requester_name'] as String? ?? '',
        payerUserId: json['payer_user_id'] as String,
        payerName: json['payer_name'] as String? ?? '',
        currency: json['currency'] as String,
        amount: json['amount'] as String,
        memo: json['memo'] as String?,
        status: json['status'] as String,
        paymentMethod: json['payment_method'] as String? ?? 'balance',
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        paidAt: json['paid_at'] == null
            ? null
            : DateTime.parse(json['paid_at'] as String).toLocal(),
        cancelledAt: json['cancelled_at'] == null
            ? null
            : DateTime.parse(json['cancelled_at'] as String).toLocal(),
      );
}
