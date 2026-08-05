"""請求 API の単体テスト。

送金のテストと同様、Supabase への実アクセスは行わず、認証依存と
DB アクセス層（app.db_payment_requests）を差し替えて検証する。
"""

from decimal import Decimal

import pytest
from fastapi.testclient import TestClient
from postgrest.exceptions import APIError

from app import db_payment_requests as db
from app.auth import AuthUser, get_current_user
from app.main import app

TEST_USER = AuthUser(
    id="00000000-0000-0000-0000-000000000001",
    email="taro@example.com",
    token="dummy-token",
)

BASE = "/api/v1/payment-requests"


def _request_json(**overrides) -> dict:
    data = {
        "request_code": "RQ-ABCD2345",
        "direction": "requested",
        "requester_user_id": "MP-11112222",
        "requester_name": "太郎",
        "payer_user_id": "MP-99990000",
        "payer_name": "花子",
        "currency": "JPY",
        "amount": "3000",
        "memo": "飲み会代",
        "status": "pending",
        "payment_method": "balance",
        "created_at": "2026-08-05T09:00:00+00:00",
        "paid_at": None,
        "cancelled_at": None,
    }
    data.update(overrides)
    return data


@pytest.fixture
def client():
    app.dependency_overrides[get_current_user] = lambda: TEST_USER
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def _api_error(message: str) -> APIError:
    return APIError({"message": message, "code": "P0001", "hint": None, "details": None})


def test_requires_auth():
    with TestClient(app) as test_client:
        assert test_client.get(BASE).status_code == 401
        assert test_client.post(BASE, json={}).status_code == 401


def test_create_request_normalizes_input(client, monkeypatch):
    captured = {}

    def fake_create(token, payer_user_id, currency, amount, memo):
        captured.update(
            payer_user_id=payer_user_id, currency=currency, amount=amount, memo=memo
        )
        return _request_json(currency=currency)

    monkeypatch.setattr(db, "create_request", fake_create)
    res = client.post(
        BASE,
        json={
            "payer_user_id": " MP-99990000 ",
            "currency": "jpy",
            "amount": "3000",
            "memo": "飲み会代",
        },
    )
    assert res.status_code == 201
    # 通貨は大文字化、宛先IDは前後空白除去、金額は Decimal で渡ること
    assert captured["currency"] == "JPY"
    assert captured["payer_user_id"] == "MP-99990000"
    assert captured["amount"] == Decimal("3000")
    body = res.json()
    assert body["request_code"] == "RQ-ABCD2345"
    assert body["status"] == "pending"


@pytest.mark.parametrize(
    "payload",
    [
        {"payer_user_id": "MP-99990000", "currency": "JPY", "amount": "-5"},  # 負の金額
        {"payer_user_id": "MP-99990000", "currency": "JPY", "amount": "0"},  # ゼロ
        {"payer_user_id": "MP-99990000", "currency": "日本円", "amount": "100"},  # 通貨コード不正
        {"payer_user_id": "", "currency": "JPY", "amount": "100"},  # 請求先なし
        {"payer_user_id": "MP-99990000", "currency": "JPY", "amount": "0.000000001"},  # 小数9桁
    ],
)
def test_create_request_rejects_invalid_payload(client, payload):
    assert client.post(BASE, json=payload).status_code == 422


@pytest.mark.parametrize(
    ("db_message", "expected_status"),
    [
        ("SELF_REQUEST", 400),
        ("RECIPIENT_NOT_FOUND", 404),
        ("INVALID_AMOUNT", 400),
        ("something unexpected", 502),
    ],
)
def test_create_request_maps_db_errors(client, monkeypatch, db_message, expected_status):
    def fake_create(*args, **kwargs):
        raise _api_error(db_message)

    monkeypatch.setattr(db, "create_request", fake_create)
    res = client.post(
        BASE, json={"payer_user_id": "MP-99990000", "currency": "JPY", "amount": "100"}
    )
    assert res.status_code == expected_status


def test_lookup_request(client, monkeypatch):
    monkeypatch.setattr(
        db, "find_request", lambda token, code: _request_json(direction="billed")
    )
    res = client.get(f"{BASE}/RQ-ABCD2345")
    assert res.status_code == 200
    assert res.json()["direction"] == "billed"
    assert res.json()["requester_name"] == "太郎"


def test_lookup_unknown_code_is_404(client, monkeypatch):
    def fake_find(*args, **kwargs):
        raise _api_error("REQUEST_NOT_FOUND")

    monkeypatch.setattr(db, "find_request", fake_find)
    assert client.get(f"{BASE}/RQ-XXXXXXXX").status_code == 404


def test_pay_request(client, monkeypatch):
    captured = {}

    def fake_pay(token, code):
        captured["code"] = code
        return _request_json(
            status="paid", direction="billed", paid_at="2026-08-05T10:00:00+00:00"
        )

    monkeypatch.setattr(db, "pay_request", fake_pay)
    res = client.post(f"{BASE}/RQ-ABCD2345/pay")
    assert res.status_code == 200
    assert captured["code"] == "RQ-ABCD2345"
    assert res.json()["status"] == "paid"
    assert res.json()["paid_at"] is not None


@pytest.mark.parametrize(
    ("db_message", "expected_status"),
    [
        ("REQUEST_ALREADY_PAID", 409),
        ("REQUEST_CANCELLED", 409),
        ("REQUEST_NOT_FOUND", 404),
        ("INSUFFICIENT_FUNDS", 400),
    ],
)
def test_pay_request_maps_db_errors(client, monkeypatch, db_message, expected_status):
    def fake_pay(*args, **kwargs):
        raise _api_error(db_message)

    monkeypatch.setattr(db, "pay_request", fake_pay)
    assert client.post(f"{BASE}/RQ-ABCD2345/pay").status_code == expected_status


def test_pay_request_by_cash(client, monkeypatch):
    captured = {}

    def fake_pay_cash(token, code):
        captured["code"] = code
        return _request_json(
            status="paid",
            payment_method="cash",
            direction="billed",
            paid_at="2026-08-05T10:00:00+00:00",
        )

    monkeypatch.setattr(db, "pay_request_by_cash", fake_pay_cash)
    res = client.post(f"{BASE}/RQ-ABCD2345/pay-cash")
    assert res.status_code == 200
    assert captured["code"] == "RQ-ABCD2345"
    body = res.json()
    assert body["status"] == "paid"
    # 現金払いは残高を動かさず、支払い方法として記録される
    assert body["payment_method"] == "cash"
    assert body["paid_at"] is not None


@pytest.mark.parametrize(
    ("db_message", "expected_status"),
    [
        ("REQUEST_ALREADY_PAID", 409),
        ("REQUEST_CANCELLED", 409),
        ("REQUEST_NOT_FOUND", 404),
    ],
)
def test_pay_by_cash_maps_db_errors(client, monkeypatch, db_message, expected_status):
    def fake_pay_cash(*args, **kwargs):
        raise _api_error(db_message)

    monkeypatch.setattr(db, "pay_request_by_cash", fake_pay_cash)
    assert client.post(f"{BASE}/RQ-ABCD2345/pay-cash").status_code == expected_status


def test_pay_by_cash_requires_auth():
    with TestClient(app) as test_client:
        assert test_client.post(f"{BASE}/RQ-ABCD2345/pay-cash").status_code == 401


def test_cancel_request(client, monkeypatch):
    monkeypatch.setattr(
        db,
        "cancel_request",
        lambda token, code: _request_json(
            status="cancelled", cancelled_at="2026-08-05T11:00:00+00:00"
        ),
    )
    res = client.post(f"{BASE}/RQ-ABCD2345/cancel")
    assert res.status_code == 200
    assert res.json()["status"] == "cancelled"


def test_cancel_paid_request_is_409(client, monkeypatch):
    def fake_cancel(*args, **kwargs):
        raise _api_error("REQUEST_ALREADY_PAID")

    monkeypatch.setattr(db, "cancel_request", fake_cancel)
    assert client.post(f"{BASE}/RQ-ABCD2345/cancel").status_code == 409


def test_list_requests(client, monkeypatch):
    monkeypatch.setattr(
        db,
        "list_requests",
        lambda token, limit: [
            _request_json(),
            _request_json(request_code="RQ-ZZZZ9999", direction="billed", status="paid"),
        ],
    )
    res = client.get(BASE)
    assert res.status_code == 200
    body = res.json()
    assert len(body) == 2
    assert [r["direction"] for r in body] == ["requested", "billed"]


def test_list_requests_rejects_bad_limit(client):
    assert client.get(f"{BASE}?limit=0").status_code == 422
    assert client.get(f"{BASE}?limit=999").status_code == 422
