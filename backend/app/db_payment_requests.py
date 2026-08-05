"""請求機能の Supabase アクセス層。

送金と同じく、ユーザーの JWT をそのまま転送して RLS / auth.uid() を効かせる
（認証済みクライアントの生成は db.py と共通のものを使う）。
"""

from decimal import Decimal
from typing import Any

from .db import _client


def create_request(
    token: str,
    payer_user_id: str,
    currency: str,
    amount: Decimal,
    memo: str | None,
) -> dict[str, Any]:
    res = (
        _client(token)
        .rpc(
            "create_payment_request",
            {
                "p_payer_user_id": payer_user_id,
                "p_currency": currency,
                # float を経由させると精度が落ちるため文字列で渡す（numeric にキャストされる）
                "p_amount": str(amount),
                "p_memo": memo,
            },
        )
        .execute()
    )
    return res.data


def find_request(token: str, code: str) -> dict[str, Any]:
    res = _client(token).rpc("find_payment_request", {"p_code": code}).execute()
    return res.data


def pay_request(token: str, code: str) -> dict[str, Any]:
    res = _client(token).rpc("pay_payment_request", {"p_code": code}).execute()
    return res.data


def pay_request_by_cash(token: str, code: str) -> dict[str, Any]:
    """現金で支払ったことを記録する（残高・送金履歴は変更されない）。"""
    res = _client(token).rpc("pay_payment_request_by_cash", {"p_code": code}).execute()
    return res.data


def cancel_request(token: str, code: str) -> dict[str, Any]:
    res = _client(token).rpc("cancel_payment_request", {"p_code": code}).execute()
    return res.data


def list_requests(token: str, limit: int = 50) -> list[dict[str, Any]]:
    res = _client(token).rpc("list_my_payment_requests", {"p_limit": limit}).execute()
    return res.data
