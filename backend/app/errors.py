from fastapi import HTTPException, status
from postgrest.exceptions import APIError

# DB 関数が raise するエラーキーワード → HTTP レスポンスの対応表
_DB_ERROR_MAP: dict[str, tuple[int, str]] = {
    "INSUFFICIENT_FUNDS": (status.HTTP_400_BAD_REQUEST, "残高が不足しています"),
    "RECIPIENT_NOT_FOUND": (status.HTTP_404_NOT_FOUND, "送金先のユーザーIDが見つかりません"),
    "SELF_TRANSFER": (status.HTTP_400_BAD_REQUEST, "自分自身には送金できません"),
    "SELF_SAVE": (status.HTTP_400_BAD_REQUEST, "自分自身は保存できません"),
    "INVALID_AMOUNT": (status.HTTP_400_BAD_REQUEST, "金額が不正です"),
    "INVALID_CURRENCY": (status.HTTP_400_BAD_REQUEST, "通貨コードが不正です"),
    # 請求機能
    "SELF_REQUEST": (status.HTTP_400_BAD_REQUEST, "自分自身には請求できません"),
    "REQUEST_NOT_FOUND": (status.HTTP_404_NOT_FOUND, "請求コードが見つかりません"),
    "REQUEST_ALREADY_PAID": (status.HTTP_409_CONFLICT, "この請求はすでに支払い済みです"),
    "REQUEST_CANCELLED": (status.HTTP_409_CONFLICT, "この請求は取り消されています"),
    # 割り勘機能
    "SPLIT_BILL_NOT_FOUND": (status.HTTP_404_NOT_FOUND, "請求コードが見つかりません"),
    "SPLIT_BILL_FULL": (status.HTTP_409_CONFLICT, "参加人数の上限に達しています"),
    "ORGANIZER_CANNOT_JOIN": (status.HTTP_400_BAD_REQUEST, "集金者はグループに参加できません"),
    "INVALID_PARTICIPANT_COUNT": (status.HTTP_400_BAD_REQUEST, "参加人数が不正です"),
    "INVALID_TITLE": (status.HTTP_400_BAD_REQUEST, "イベント名を入力してください"),
    "UNAUTHENTICATED": (status.HTTP_401_UNAUTHORIZED, "認証が必要です"),
}


def to_http_exception(err: APIError) -> HTTPException:
    """Supabase (PostgREST) のエラーをユーザー向けの HTTPException に変換する。"""
    message = err.message or ""
    for keyword, (status_code, detail) in _DB_ERROR_MAP.items():
        if keyword in message:
            return HTTPException(status_code, detail)

    # 呼び出そうとした DB 関数が存在しない場合。マイグレーションの適用漏れで
    # 起きるため、DB の一般的なエラーとは区別して原因が分かるようにする。
    if "Could not find the function" in message or "PGRST202" in message:
        return HTTPException(
            status.HTTP_501_NOT_IMPLEMENTED,
            "この機能はまだ利用できません（データベースの更新が必要です）",
        )

    return HTTPException(status.HTTP_502_BAD_GATEWAY, "データベース処理でエラーが発生しました")
