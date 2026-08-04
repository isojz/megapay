"""API の単体テスト。

Supabase への実アクセスは行わず、認証依存（get_current_user）と
DB アクセス層（app.db）を差し替えて、ルーティング・バリデーション・
エラーマッピングを検証する。
"""

from decimal import Decimal

import pytest
from fastapi.testclient import TestClient
from postgrest.exceptions import APIError

from app import db
from app.auth import AuthUser, get_current_user
from app.main import app

TEST_USER = AuthUser(
    id="00000000-0000-0000-0000-000000000001",
    email="taro@example.com",
    token="dummy-token",
)


@pytest.fixture
def client():
    app.dependency_overrides[get_current_user] = lambda: TEST_USER
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def _api_error(message: str) -> APIError:
    return APIError({"message": message, "code": "P0001", "hint": None, "details": None})


def test_health():
    with TestClient(app) as test_client:
        res = test_client.get("/health")
    assert res.status_code == 200
    assert res.json() == {"status": "ok"}


def test_me_requires_auth():
    with TestClient(app) as test_client:
        assert test_client.get("/api/v1/me").status_code == 401


def test_me_returns_profile(client, monkeypatch):
    monkeypatch.setattr(
        db,
        "fetch_profile",
        lambda token, profile_id: {
            "user_id": "MP-11112222",
            "display_name": "太郎",
            "created_at": "2026-08-04T00:00:00+00:00",
        },
    )
    res = client.get("/api/v1/me")
    assert res.status_code == 200
    body = res.json()
    assert body["user_id"] == "MP-11112222"
    assert body["display_name"] == "太郎"
    assert body["email"] == "taro@example.com"


def test_balances_returns_list(client, monkeypatch):
    monkeypatch.setattr(
        db,
        "fetch_balances",
        lambda token, profile_id: [
            {"currency": "JPY", "amount": "500000"},
            {"currency": "USD", "amount": "3000"},
        ],
    )
    res = client.get("/api/v1/balances")
    assert res.status_code == 200
    assert res.json() == [
        {"currency": "JPY", "amount": "500000"},
        {"currency": "USD", "amount": "3000"},
    ]


def test_transfer_success_normalizes_input(client, monkeypatch):
    captured = {}

    def fake_execute(token, recipient_user_id, currency, amount, memo):
        captured.update(
            recipient_user_id=recipient_user_id, currency=currency, amount=amount, memo=memo
        )
        return {
            "id": "11111111-1111-1111-1111-111111111111",
            "recipient_user_id": "MP-99990000",
            "currency": currency,
            "amount": "1000",
            "memo": memo,
            "created_at": "2026-08-04T09:00:00+00:00",
        }

    monkeypatch.setattr(db, "execute_transfer", fake_execute)
    res = client.post(
        "/api/v1/transfers",
        json={"recipient_user_id": " MP-99990000 ", "currency": "jpy", "amount": "1000"},
    )
    assert res.status_code == 201
    # 通貨は大文字化、宛先IDは前後空白除去、金額は Decimal で渡ること
    assert captured["currency"] == "JPY"
    assert captured["recipient_user_id"] == "MP-99990000"
    assert captured["amount"] == Decimal("1000")
    assert res.json()["amount"] == "1000"


@pytest.mark.parametrize(
    "payload",
    [
        {"recipient_user_id": "MP-99990000", "currency": "JPY", "amount": "-5"},  # 負の金額
        {"recipient_user_id": "MP-99990000", "currency": "JPY", "amount": "0"},  # ゼロ
        {"recipient_user_id": "MP-99990000", "currency": "日本円", "amount": "100"},  # 通貨コード不正
        {"recipient_user_id": "", "currency": "JPY", "amount": "100"},  # 宛先なし
        {"recipient_user_id": "MP-99990000", "currency": "JPY", "amount": "0.000000001"},  # 小数9桁
    ],
)
def test_transfer_rejects_invalid_payload(client, payload):
    res = client.post("/api/v1/transfers", json=payload)
    assert res.status_code == 422


@pytest.mark.parametrize(
    ("db_message", "expected_status"),
    [
        ("INSUFFICIENT_FUNDS", 400),
        ("RECIPIENT_NOT_FOUND", 404),
        ("SELF_TRANSFER", 400),
        ("something unexpected", 502),
    ],
)
def test_transfer_maps_db_errors(client, monkeypatch, db_message, expected_status):
    def fake_execute(*args, **kwargs):
        raise _api_error(db_message)

    monkeypatch.setattr(db, "execute_transfer", fake_execute)
    res = client.post(
        "/api/v1/transfers",
        json={"recipient_user_id": "MP-99990000", "currency": "JPY", "amount": "100"},
    )
    assert res.status_code == expected_status


def test_recipient_lookup(client, monkeypatch):
    monkeypatch.setattr(
        db,
        "find_recipient",
        lambda token, user_id: {"user_id": "MP-99990000", "display_name": "花子"},
    )
    res = client.get("/api/v1/recipients/MP-99990000")
    assert res.status_code == 200
    assert res.json() == {"user_id": "MP-99990000", "display_name": "花子"}


def test_recipient_not_found(client, monkeypatch):
    def fake_find(*args, **kwargs):
        raise _api_error("RECIPIENT_NOT_FOUND")

    monkeypatch.setattr(db, "find_recipient", fake_find)
    assert client.get("/api/v1/recipients/MP-00000000").status_code == 404


def test_transfer_history(client, monkeypatch):
    monkeypatch.setattr(
        db,
        "list_transfers",
        lambda token, limit: [
            {
                "id": "22222222-2222-2222-2222-222222222222",
                "direction": "sent",
                "counterpart_user_id": "MP-99990000",
                "counterpart_name": "花子",
                "currency": "USD",
                "amount": "120.5",
                "memo": "ランチ代",
                "created_at": "2026-08-04T09:00:00+00:00",
            }
        ],
    )
    res = client.get("/api/v1/transfers")
    assert res.status_code == 200
    body = res.json()
    assert len(body) == 1
    assert body[0]["direction"] == "sent"
    assert body[0]["amount"] == "120.5"
