/// 割り勘（split bill）のモデル。
/// 金額は桁落ち防止のため API 上は文字列で受け渡しする（表示時のみ数値化）。
library;

class SplitBill {
  const SplitBill({
    required this.billCode,
    required this.title,
    required this.currency,
    required this.totalAmount,
    required this.participantCount,
    required this.shareAmount,
    required this.organizerUserId,
    required this.organizerName,
    required this.isOrganizer,
    required this.joined,
    required this.joinedCount,
    required this.paidCount,
    required this.collectedAmount,
    required this.createdAt,
    this.myRequestCode,
    this.myStatus,
  });

  /// 参加用の請求コード（SP-XXXXXXXX）
  final String billCode;
  final String title;
  final String currency;
  final String totalAmount;

  /// 集金者を含む参加人数
  final int participantCount;

  /// 1人あたりの金額（端数は切り上げ）
  final String shareAmount;

  final String organizerUserId;
  final String organizerName;

  /// 閲覧者が集金者か
  final bool isOrganizer;

  /// 閲覧者が参加済みか
  final bool joined;

  /// 参加済みなら自分あての請求コードと状態
  final String? myRequestCode;
  final String? myStatus; // "pending" / "paid" / "cancelled"

  final int joinedCount;
  final int paidCount;
  final String collectedAmount;
  final DateTime createdAt;

  /// 集金者は自分の分を立て替えているため、請求を受けるのは参加人数 - 1 人
  int get expectedPayerCount => participantCount - 1;

  bool get isPaidByMe => myStatus == 'paid';
  bool get isFull => joinedCount >= expectedPayerCount;

  /// 集めるべき金額（1人あたり × 集金者を除く人数）
  String get expectedTotal {
    final share = double.tryParse(shareAmount);
    if (share == null) return totalAmount;
    final total = share * expectedPayerCount;
    return total == total.roundToDouble()
        ? total.toStringAsFixed(0)
        : total.toString();
  }

  factory SplitBill.fromJson(Map<String, dynamic> json) => SplitBill(
        billCode: json['bill_code'] as String,
        title: json['title'] as String,
        currency: json['currency'] as String,
        totalAmount: json['total_amount'] as String,
        participantCount: json['participant_count'] as int,
        shareAmount: json['share_amount'] as String,
        organizerUserId: json['organizer_user_id'] as String,
        organizerName: json['organizer_name'] as String? ?? '',
        isOrganizer: json['is_organizer'] as bool,
        joined: json['joined'] as bool,
        myRequestCode: json['my_request_code'] as String?,
        myStatus: json['my_status'] as String?,
        joinedCount: json['joined_count'] as int,
        paidCount: json['paid_count'] as int,
        collectedAmount: json['collected_amount'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );
}

/// グループ画面に並べる参加者 1 人分の支払い状況。
class SplitBillParticipant {
  const SplitBillParticipant({
    required this.userId,
    required this.displayName,
    required this.requestCode,
    required this.amount,
    required this.status,
    required this.isMe,
    required this.joinedAt,
    this.paidAt,
  });

  final String userId;
  final String displayName;
  final String requestCode;
  final String amount;
  final String status; // "pending"（未払い） / "paid"（支払い済み）
  final DateTime? paidAt;
  final bool isMe;
  final DateTime joinedAt;

  bool get isPaid => status == 'paid';
  String get statusLabel => isPaid ? '支払い済み' : '未払い';

  factory SplitBillParticipant.fromJson(Map<String, dynamic> json) =>
      SplitBillParticipant(
        userId: json['user_id'] as String,
        displayName: json['display_name'] as String? ?? '',
        requestCode: json['request_code'] as String,
        amount: json['amount'] as String,
        status: json['status'] as String,
        paidAt: json['paid_at'] == null
            ? null
            : DateTime.parse(json['paid_at'] as String).toLocal(),
        isMe: json['is_me'] as bool,
        joinedAt: DateTime.parse(json['joined_at'] as String).toLocal(),
      );
}
