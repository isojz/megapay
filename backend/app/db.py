"""Supabase (PostgREST) アクセス層。

ユーザーの JWT をそのまま Supabase に転送することで、RLS と
SECURITY DEFINER 関数内の auth.uid() をユーザー本人として効かせる。
service_role キーは使わない（バックエンドが乗っ取られても全件操作できない）。
"""

from decimal import Decimal
from typing import Any

from supabase import Client, create_client

from .config import get_settings


def _client(token: str) -> Client:
    settings = get_settings()
    client = create_client(settings.supabase_url, settings.supabase_anon_key)
    client.postgrest.auth(token)
    return client


def _amount_str(value: Any) -> str:
    """PostgREST が返す数値を桁落ちのない表示用文字列に整える。"""
    return format(Decimal(str(value)).normalize(), "f")


def fetch_profile(token: str, profile_id: str) -> dict[str, Any] | None:
    res = (
        _client(token)
        .table("profiles")
        .select("user_id, display_name, created_at")
        .eq("id", profile_id)
        .limit(1)
        .execute()
    )
    return res.data[0] if res.data else None


def fetch_balances(token: str, profile_id: str) -> list[dict[str, Any]]:
    res = (
        _client(token)
        .table("balances")
        .select("currency, amount")
        .eq("profile_id", profile_id)
        .order("currency")
        .execute()
    )
    return [
        {"currency": row["currency"], "amount": _amount_str(row["amount"])}
        for row in res.data
    ]


def find_recipient(token: str, recipient_user_id: str) -> dict[str, Any]:
    res = _client(token).rpc("find_recipient", {"p_user_id": recipient_user_id}).execute()
    return res.data


def execute_transfer(
    token: str,
    recipient_user_id: str,
    currency: str,
    amount: Decimal,
    memo: str | None,
) -> dict[str, Any]:
    res = (
        _client(token)
        .rpc(
            "execute_transfer",
            {
                "p_recipient_user_id": recipient_user_id,
                "p_currency": currency,
                # float を経由させると精度が落ちるため文字列で渡す（numeric にキャストされる）
                "p_amount": str(amount),
                "p_memo": memo,
            },
        )
        .execute()
    )
    return res.data


def list_transfers(token: str, limit: int = 50) -> list[dict[str, Any]]:
    res = _client(token).rpc("list_my_transfers", {"p_limit": limit}).execute()
    return res.data
