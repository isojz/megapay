"""割り勘機能の Supabase アクセス層。

送金・請求と同じく、ユーザーの JWT をそのまま転送して RLS / auth.uid() を効かせる
（認証済みクライアントの生成は db.py と共通のものを使う）。
"""

from decimal import Decimal
from typing import Any

from supabase import create_client

from .config import get_settings
from .db import _client


def find_public_split_bill(code: str) -> dict[str, Any]:
    settings = get_settings()
    client = create_client(settings.supabase_url, settings.supabase_anon_key)
    res = client.rpc("find_public_split_bill", {"p_code": code}).execute()
    return res.data


def create_split_bill(
    token: str,
    title: str,
    currency: str,
    total_amount: Decimal,
    participant_count: int,
) -> dict[str, Any]:
    res = (
        _client(token)
        .rpc(
            "create_split_bill",
            {
                "p_title": title,
                "p_currency": currency,
                # float を経由させると精度が落ちるため文字列で渡す（numeric にキャストされる）
                "p_total_amount": str(total_amount),
                "p_participant_count": participant_count,
            },
        )
        .execute()
    )
    return res.data


def create_ranked_split_bill_test(
    token: str, title: str, participant_count: int
) -> dict[str, Any]:
    res = _client(token).rpc(
        "create_ranked_split_bill_test",
        {"p_title": title, "p_participant_count": participant_count},
    ).execute()
    return res.data


def find_split_bill(token: str, code: str) -> dict[str, Any]:
    res = _client(token).rpc("find_split_bill", {"p_code": code}).execute()
    return res.data


def join_split_bill(token: str, code: str) -> dict[str, Any]:
    res = _client(token).rpc("join_split_bill", {"p_code": code}).execute()
    return res.data


def join_ranked_split_bill(
    token: str, code: str, rank_code: str
) -> dict[str, Any]:
    res = _client(token).rpc(
        "join_ranked_split_bill",
        {"p_code": code, "p_rank_code": rank_code},
    ).execute()
    return res.data


def list_participants(token: str, code: str) -> list[dict[str, Any]]:
    res = _client(token).rpc("list_split_bill_participants", {"p_code": code}).execute()
    return res.data


def list_my_split_bills(token: str, limit: int = 50) -> list[dict[str, Any]]:
    res = _client(token).rpc("list_my_split_bills", {"p_limit": limit}).execute()
    return res.data
