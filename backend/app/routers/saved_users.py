from fastapi import APIRouter, Depends, status
from postgrest.exceptions import APIError

from .. import db
from ..auth import AuthUser, get_current_user
from ..errors import to_http_exception
from ..schemas import RecipientResponse, SavedUserCreate, SavedUserResponse

router = APIRouter(prefix="/api/v1/saved-users", tags=["saved-users"])


@router.get("", response_model=list[SavedUserResponse])
def get_saved_users(
    user: AuthUser = Depends(get_current_user),
) -> list[SavedUserResponse]:
    try:
        data = db.list_saved_users(user.token)
    except APIError as err:
        raise to_http_exception(err) from err
    return [SavedUserResponse(**item) for item in data]


@router.post("", response_model=RecipientResponse, status_code=status.HTTP_201_CREATED)
def save_user(
    body: SavedUserCreate,
    user: AuthUser = Depends(get_current_user),
) -> RecipientResponse:
    try:
        data = db.save_user(user.token, body.user_id.strip())
    except APIError as err:
        raise to_http_exception(err) from err
    return RecipientResponse(**data)
