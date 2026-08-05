"""割り勘 API の単体テスト。

Supabase への実アクセスは行わず、認証依存と DB アクセス層（app.db_split_bills）を
差し替えて、ルーティング・バリデーション・エラーマッピングを検証する。
"""

from decimal import Decimal

import pytest
from fastapi.testclient import TestClient
from postgrest.exceptions import APIError

from app import db_split_bills as db
from app.auth import AuthUser, get_current_user
from app.main import app

TEST_USER = AuthUser(
    id="00000000-0000-0000-0000-000000000001",
    email="taro@example.com",
    token="dummy-token",
)

BASE = "/api/v1/split-bills"


def _bill_json(**overrides) -> dict:
    data = {
        "bill_code": "SP-ABCD2345",
        "title": "歓迎会",
        "currency": "JPY",
        "total_amount": "50000",
        "participant_count": 10,
        "share_amount": "5000",
        "organizer_user_id": "MP-11112222",
        "organizer_name": "太郎",
        "is_organizer": True,
        "joined": False,
        "my_request_code": None,
        "my_status": None,
        "joined_count": 0,
        "paid_count": 0,
        "collected_amount": "0",
        "created_at": "2026-08-05T09:00:00+00:00",
    }
    data.update(overrides)
    return data


def _participant_json(**overrides) -> dict:
    data = {
        "user_id": "MP-99990000",
        "display_name": "花子",
        "request_code": "RQ-ZZZZ9999",
        "amount": "5000",
        "status": "pending",
        "payment_method": "balance",
        "paid_at": None,
        "is_me": False,
        "joined_at": "2026-08-05T09:30:00+00:00",
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
        assert test_client.post(f"{BASE}/SP-ABCD2345/join").status_code == 401


def test_create_split_bill_normalizes_input(client, monkeypatch):
    captured = {}

    def fake_create(token, title, currency, total_amount, participant_count):
        captured.update(
            title=title,
            currency=currency,
            total_amount=total_amount,
            participant_count=participant_count,
        )
        return _bill_json(currency=currency)

    monkeypatch.setattr(db, "create_split_bill", fake_create)
    res = client.post(
        BASE,
        json={
            "title": "  歓迎会  ",
            "currency": "jpy",
            "total_amount": "50000",
            "participant_count": 10,
        },
    )
    assert res.status_code == 201
    # 通貨は大文字化、タイトルは前後空白除去、金額は Decimal で渡ること
    assert captured["currency"] == "JPY"
    assert captured["title"] == "歓迎会"
    assert captured["total_amount"] == Decimal("50000")
    assert captured["participant_count"] == 10
    body = res.json()
    assert body["bill_code"] == "SP-ABCD2345"
    assert body["share_amount"] == "5000"


@pytest.mark.parametrize(
    "payload",
    [
        {"title": "", "currency": "JPY", "total_amount": "5000", "participant_count": 5},
        {"title": "歓迎会", "currency": "JPY", "total_amount": "0", "participant_count": 5},
        {"title": "歓迎会", "currency": "JPY", "total_amount": "-1", "participant_count": 5},
        {"title": "歓迎会", "currency": "日本円", "total_amount": "5000", "participant_count": 5},
        {"title": "歓迎会", "currency": "JPY", "total_amount": "5000", "participant_count": 1},
        {"title": "歓迎会", "currency": "JPY", "total_amount": "5000", "participant_count": 101},
        {"title": "歓迎会", "currency": "JPY", "total_amount": "0.000000001", "participant_count": 5},
    ],
)
def test_create_split_bill_rejects_invalid_payload(client, payload):
    assert client.post(BASE, json=payload).status_code == 422


@pytest.mark.parametrize(
    ("db_message", "expected_status"),
    [
        ("INVALID_PARTICIPANT_COUNT", 400),
        ("INVALID_TITLE", 400),
        ("INVALID_AMOUNT", 400),
        ("something unexpected", 502),
    ],
)
def test_create_split_bill_maps_db_errors(client, monkeypatch, db_message, expected_status):
    def fake_create(*args, **kwargs):
        raise _api_error(db_message)

    monkeypatch.setattr(db, "create_split_bill", fake_create)
    res = client.post(
        BASE,
        json={
            "title": "歓迎会",
            "currency": "JPY",
            "total_amount": "50000",
            "participant_count": 10,
        },
    )
    assert res.status_code == expected_status


def test_get_split_bill(client, monkeypatch):
    monkeypatch.setattr(
        db,
        "find_split_bill",
        lambda token, code: _bill_json(is_organizer=False, joined=False),
    )
    res = client.get(f"{BASE}/SP-ABCD2345")
    assert res.status_code == 200
    body = res.json()
    assert body["title"] == "歓迎会"
    assert body["share_amount"] == "5000"
    assert body["is_organizer"] is False


def test_get_unknown_split_bill_is_404(client, monkeypatch):
    def fake_find(*args, **kwargs):
        raise _api_error("SPLIT_BILL_NOT_FOUND")

    monkeypatch.setattr(db, "find_split_bill", fake_find)
    assert client.get(f"{BASE}/SP-XXXXXXXX").status_code == 404


def test_join_split_bill(client, monkeypatch):
    captured = {}

    def fake_join(token, code):
        captured["code"] = code
        return _bill_json(
            is_organizer=False,
            joined=True,
            my_request_code="RQ-ZZZZ9999",
            my_status="pending",
            joined_count=1,
        )

    monkeypatch.setattr(db, "join_split_bill", fake_join)
    res = client.post(f"{BASE}/SP-ABCD2345/join")
    assert res.status_code == 200
    assert captured["code"] == "SP-ABCD2345"
    body = res.json()
    # 参加すると自分あての請求コードが払い出される
    assert body["joined"] is True
    assert body["my_request_code"] == "RQ-ZZZZ9999"
    assert body["my_status"] == "pending"


@pytest.mark.parametrize(
    ("db_message", "expected_status"),
    [
        ("SPLIT_BILL_NOT_FOUND", 404),
        ("SPLIT_BILL_FULL", 409),
        ("ORGANIZER_CANNOT_JOIN", 400),
    ],
)
def test_join_split_bill_maps_db_errors(client, monkeypatch, db_message, expected_status):
    def fake_join(*args, **kwargs):
        raise _api_error(db_message)

    monkeypatch.setattr(db, "join_split_bill", fake_join)
    assert client.post(f"{BASE}/SP-ABCD2345/join").status_code == expected_status


def test_list_participants(client, monkeypatch):
    monkeypatch.setattr(
        db,
        "list_participants",
        lambda token, code: [
            _participant_json(),
            _participant_json(
                user_id="MP-33334444",
                display_name="次郎",
                request_code="RQ-YYYY8888",
                status="paid",
                paid_at="2026-08-05T10:00:00+00:00",
                is_me=True,
            ),
        ],
    )
    res = client.get(f"{BASE}/SP-ABCD2345/participants")
    assert res.status_code == 200
    body = res.json()
    assert len(body) == 2
    assert [p["status"] for p in body] == ["pending", "paid"]
    assert body[1]["is_me"] is True
    assert body[1]["paid_at"] is not None


def test_list_participants_shows_payment_method(client, monkeypatch):
    """集金者が「誰が現金で払ったか」を判別できること。"""
    monkeypatch.setattr(
        db,
        "list_participants",
        lambda token, code: [
            _participant_json(status="paid", payment_method="cash"),
            _participant_json(
                user_id="MP-33334444", status="paid", payment_method="balance"
            ),
        ],
    )
    body = client.get(f"{BASE}/SP-ABCD2345/participants").json()
    assert [p["payment_method"] for p in body] == ["cash", "balance"]


def test_list_participants_of_other_group_is_404(client, monkeypatch):
    def fake_list(*args, **kwargs):
        raise _api_error("SPLIT_BILL_NOT_FOUND")

    monkeypatch.setattr(db, "list_participants", fake_list)
    assert client.get(f"{BASE}/SP-ABCD2345/participants").status_code == 404


def test_list_my_split_bills(client, monkeypatch):
    monkeypatch.setattr(
        db,
        "list_my_split_bills",
        lambda token, limit: [
            _bill_json(),
            _bill_json(bill_code="SP-ZZZZ9999", is_organizer=False, joined=True),
        ],
    )
    res = client.get(BASE)
    assert res.status_code == 200
    body = res.json()
    assert len(body) == 2
    assert [b["is_organizer"] for b in body] == [True, False]


def test_list_my_split_bills_rejects_bad_limit(client):
    assert client.get(f"{BASE}?limit=0").status_code == 422
    assert client.get(f"{BASE}?limit=999").status_code == 422
