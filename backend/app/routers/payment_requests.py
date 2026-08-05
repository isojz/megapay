from fastapi import APIRouter, Depends, Query, status
from postgrest.exceptions import APIError

from .. import db_payment_requests as db
from ..auth import AuthUser, get_current_user
from ..errors import to_http_exception
from ..schemas_payment_requests import PaymentRequestCreate, PaymentRequestResponse

router = APIRouter(prefix="/api/v1/payment-requests", tags=["payment-requests"])


@router.post("", response_model=PaymentRequestResponse, status_code=status.HTTP_201_CREATED)
def create_payment_request(
    body: PaymentRequestCreate,
    user: AuthUser = Depends(get_current_user),
) -> PaymentRequestResponse:
    """請求を作成し、支払い用の請求コードを発行する。"""
    try:
        data = db.create_request(
            user.token,
            body.payer_user_id.strip(),
            body.currency.upper(),
            body.amount,
            body.memo,
        )
    except APIError as err:
        raise to_http_exception(err) from err
    return PaymentRequestResponse(**data)


@router.get("", response_model=list[PaymentRequestResponse])
def list_payment_requests(
    limit: int = Query(default=50, ge=1, le=200),
    user: AuthUser = Depends(get_current_user),
) -> list[PaymentRequestResponse]:
    """自分が請求した / 請求された一覧を新しい順に返す（請求状況の確認）。"""
    try:
        data = db.list_requests(user.token, limit)
    except APIError as err:
        raise to_http_exception(err) from err
    return [PaymentRequestResponse(**item) for item in data]


@router.get("/{request_code}", response_model=PaymentRequestResponse)
def get_payment_request(
    request_code: str,
    user: AuthUser = Depends(get_current_user),
) -> PaymentRequestResponse:
    """請求コードから内容を取得する（支払い前の確認用）。"""
    try:
        data = db.find_request(user.token, request_code.strip())
    except APIError as err:
        raise to_http_exception(err) from err
    return PaymentRequestResponse(**data)


@router.post("/{request_code}/pay", response_model=PaymentRequestResponse)
def pay_payment_request(
    request_code: str,
    user: AuthUser = Depends(get_current_user),
) -> PaymentRequestResponse:
    """請求コードを指定して支払う（送金が実行され、請求が成立する）。"""
    try:
        data = db.pay_request(user.token, request_code.strip())
    except APIError as err:
        raise to_http_exception(err) from err
    return PaymentRequestResponse(**data)


@router.post("/{request_code}/cancel", response_model=PaymentRequestResponse)
def cancel_payment_request(
    request_code: str,
    user: AuthUser = Depends(get_current_user),
) -> PaymentRequestResponse:
    """請求を取り消す（請求した本人・未払いのもののみ）。"""
    try:
        data = db.cancel_request(user.token, request_code.strip())
    except APIError as err:
        raise to_http_exception(err) from err
    return PaymentRequestResponse(**data)
