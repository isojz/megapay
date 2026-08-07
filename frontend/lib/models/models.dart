/// バックエンド API のレスポンスに対応するモデル群。
/// 金額は桁落ち防止のため API 上は文字列で受け渡しする（表示時のみ数値化）。
library;

class Profile {
  const Profile({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.avatarKey,
  });

  final String userId;
  final String displayName;
  final String email;
  final String avatarKey;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        userId: json['user_id'] as String,
        displayName: json['display_name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        avatarKey: json['avatar_key'] as String? ?? 'avatar_01',
      );
}

class Balance {
  const Balance({
    required this.currency,
    required this.amount,
  });

  final String currency;
  final String amount;

  factory Balance.fromJson(Map<String, dynamic> json) => Balance(
        currency: json['currency'] as String,
        amount: json['amount'] as String,
      );
}

class RecipientInfo {
  const RecipientInfo({
    required this.userId,
    required this.displayName,
  });

  final String userId;
  final String displayName;

  factory RecipientInfo.fromJson(Map<String, dynamic> json) => RecipientInfo(
        userId: json['user_id'] as String,
        displayName: json['display_name'] as String? ?? '',
      );
}

class SavedUser extends RecipientInfo {
  const SavedUser({
    required super.userId,
    required super.displayName,
    required this.createdAt,
  });

  final DateTime createdAt;

  factory SavedUser.fromJson(Map<String, dynamic> json) => SavedUser(
        userId: json['user_id'] as String,
        displayName: json['display_name'] as String? ?? '',
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );
}

class TransferRecord {
  const TransferRecord({
    required this.id,
    required this.direction,
    required this.counterpartUserId,
    required this.counterpartName,
    required this.currency,
    required this.amount,
    required this.createdAt,
    this.memo,
  });

  final String id;
  final String direction; // "sent"（送金） / "received"（受取）
  final String counterpartUserId;
  final String counterpartName;
  final String currency;
  final String amount;
  final String? memo;
  final DateTime createdAt;

  bool get isSent => direction == 'sent';

  factory TransferRecord.fromJson(Map<String, dynamic> json) => TransferRecord(
        id: json['id'] as String,
        direction: json['direction'] as String,
        counterpartUserId: json['counterpart_user_id'] as String,
        counterpartName: json['counterpart_name'] as String? ?? '',
        currency: json['currency'] as String,
        amount: json['amount'] as String,
        memo: json['memo'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );
}
