from fastapi import APIRouter, Depends, Query, status
from postgrest.exceptions import APIError

from .. import db
from ..auth import AuthUser, get_current_user
from ..errors import to_http_exception
from ..schemas import (
    RecipientResponse,
    TransferCreate,
    TransferHistoryItem,
    TransferResponse,
)

router = APIRouter(prefix="/api/v1", tags=["transfers"])


@router.get("/recipients/{recipient_user_id}", response_model=RecipientResponse)
def lookup_recipient(
    recipient_user_id: str,
    user: AuthUser = Depends(get_current_user),
) -> RecipientResponse:
    """送金前の宛先確認。公開IDから表示名を返す。"""
    try:
        data = db.find_recipient(user.token, recipient_user_id.strip())
    except APIError as err:
        raise to_http_exception(err) from err
    return RecipientResponse(**data)


@router.post("/transfers", response_model=TransferResponse, status_code=status.HTTP_201_CREATED)
def create_transfer(
    body: TransferCreate,
    user: AuthUser = Depends(get_current_user),
) -> TransferResponse:
    try:
        data = db.execute_transfer(
            user.token,
            body.recipient_user_id.strip(),
            body.currency.upper(),
            body.amount,
            body.memo,
        )
    except APIError as err:
        raise to_http_exception(err) from err
    return TransferResponse(**data)


@router.get("/transfers", response_model=list[TransferHistoryItem])
def get_transfer_history(
    limit: int = Query(default=50, ge=1, le=200),
    user: AuthUser = Depends(get_current_user),
) -> list[TransferHistoryItem]:
    try:
        data = db.list_transfers(user.token, limit)
    except APIError as err:
        raise to_http_exception(err) from err
    return [TransferHistoryItem(**item) for item in data]
