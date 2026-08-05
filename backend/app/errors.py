from fastapi import HTTPException, status
from postgrest.exceptions import APIError

# DB 関数が raise するエラーキーワード → HTTP レスポンスの対応表
_DB_ERROR_MAP: dict[str, tuple[int, str]] = {
    "INSUFFICIENT_FUNDS": (status.HTTP_400_BAD_REQUEST, "残高が不足しています"),
    "RECIPIENT_NOT_FOUND": (status.HTTP_404_NOT_FOUND, "送金先のユーザーIDが見つかりません"),
    "SELF_TRANSFER": (status.HTTP_400_BAD_REQUEST, "自分自身には送金できません"),
    "INVALID_AMOUNT": (status.HTTP_400_BAD_REQUEST, "金額が不正です"),
    "INVALID_CURRENCY": (status.HTTP_400_BAD_REQUEST, "通貨コードが不正です"),
    # 請求機能
    "SELF_REQUEST": (status.HTTP_400_BAD_REQUEST, "自分自身には請求できません"),
    "REQUEST_NOT_FOUND": (status.HTTP_404_NOT_FOUND, "請求コードが見つかりません"),
    "REQUEST_ALREADY_PAID": (status.HTTP_409_CONFLICT, "この請求はすでに支払い済みです"),
    "REQUEST_CANCELLED": (status.HTTP_409_CONFLICT, "この請求は取り消されています"),
    "UNAUTHENTICATED": (status.HTTP_401_UNAUTHORIZED, "認証が必要です"),
}


def to_http_exception(err: APIError) -> HTTPException:
    """Supabase (PostgREST) のエラーをユーザー向けの HTTPException に変換する。"""
    message = err.message or ""
    for keyword, (status_code, detail) in _DB_ERROR_MAP.items():
        if keyword in message:
            return HTTPException(status_code, detail)
    return HTTPException(status.HTTP_502_BAD_GATEWAY, "データベース処理でエラーが発生しました")
