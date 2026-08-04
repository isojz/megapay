from fastapi import APIRouter, Depends
from postgrest.exceptions import APIError

from .. import db
from ..auth import AuthUser, get_current_user
from ..errors import to_http_exception
from ..schemas import BalanceResponse

router = APIRouter(prefix="/api/v1", tags=["balances"])


@router.get("/balances", response_model=list[BalanceResponse])
def get_balances(user: AuthUser = Depends(get_current_user)) -> list[BalanceResponse]:
    try:
        balances = db.fetch_balances(user.token, user.id)
    except APIError as err:
        raise to_http_exception(err) from err
    return [BalanceResponse(**row) for row in balances]
