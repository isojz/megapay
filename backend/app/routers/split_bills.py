from fastapi import APIRouter, Depends, Query, status
from postgrest.exceptions import APIError

from .. import db_split_bills as db
from ..auth import AuthUser, get_current_user
from ..errors import to_http_exception
from ..schemas_split_bills import (
    PublicSplitBillResponse,
    SplitBillCreate,
    SplitBillParticipant,
    SplitBillResponse,
)

router = APIRouter(prefix="/api/v1/split-bills", tags=["split-bills"])


@router.get("/public/{bill_code}", response_model=PublicSplitBillResponse)
def get_public_split_bill(bill_code: str) -> PublicSplitBillResponse:
    """割り勘リンク用プレビュー。認証不要で限定情報だけを返す。"""
    try:
        data = db.find_public_split_bill(bill_code.strip())
    except APIError as err:
        raise to_http_exception(err) from err
    return PublicSplitBillResponse(**data)


@router.post("", response_model=SplitBillResponse, status_code=status.HTTP_201_CREATED)
def create_split_bill(
    body: SplitBillCreate,
    user: AuthUser = Depends(get_current_user),
) -> SplitBillResponse:
    """割り勘を登録し、参加用の請求コードを発行する（集金者）。"""
    try:
        data = db.create_split_bill(
            user.token,
            body.title.strip(),
            body.currency.upper(),
            body.total_amount,
            body.participant_count,
        )
    except APIError as err:
        raise to_http_exception(err) from err
    return SplitBillResponse(**data)


@router.get("", response_model=list[SplitBillResponse])
def list_my_split_bills(
    limit: int = Query(default=50, ge=1, le=200),
    user: AuthUser = Depends(get_current_user),
) -> list[SplitBillResponse]:
    """自分が関わる割り勘の一覧（集金した分・参加した分）。"""
    try:
        data = db.list_my_split_bills(user.token, limit)
    except APIError as err:
        raise to_http_exception(err) from err
    return [SplitBillResponse(**item) for item in data]


@router.get("/{bill_code}", response_model=SplitBillResponse)
def get_split_bill(
    bill_code: str,
    user: AuthUser = Depends(get_current_user),
) -> SplitBillResponse:
    """請求コードから割り勘の内容を取得する（参加前の確認にも使う）。"""
    try:
        data = db.find_split_bill(user.token, bill_code.strip())
    except APIError as err:
        raise to_http_exception(err) from err
    return SplitBillResponse(**data)


@router.post("/{bill_code}/join", response_model=SplitBillResponse)
def join_split_bill(
    bill_code: str,
    user: AuthUser = Depends(get_current_user),
) -> SplitBillResponse:
    """請求コードでグループに参加する。

    参加と同時に「集金者 → 自分」の請求（割り勘後の金額）が作成される。
    参加済みの場合は現在の状態を返すだけで、二重に請求されることはない。
    """
    try:
        data = db.join_split_bill(user.token, bill_code.strip())
    except APIError as err:
        raise to_http_exception(err) from err
    return SplitBillResponse(**data)


@router.get("/{bill_code}/participants", response_model=list[SplitBillParticipant])
def list_split_bill_participants(
    bill_code: str,
    user: AuthUser = Depends(get_current_user),
) -> list[SplitBillParticipant]:
    """グループの参加者と支払い状況の一覧（集金者・参加者のみ）。"""
    try:
        data = db.list_participants(user.token, bill_code.strip())
    except APIError as err:
        raise to_http_exception(err) from err
    return [SplitBillParticipant(**item) for item in data]
