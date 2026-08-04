from fastapi import APIRouter, Depends, HTTPException, status
from postgrest.exceptions import APIError

from .. import db
from ..auth import AuthUser, get_current_user
from ..errors import to_http_exception
from ..schemas import ProfileResponse

router = APIRouter(prefix="/api/v1", tags=["profile"])


@router.get("/me", response_model=ProfileResponse)
def get_me(user: AuthUser = Depends(get_current_user)) -> ProfileResponse:
    try:
        profile = db.fetch_profile(user.token, user.id)
    except APIError as err:
        raise to_http_exception(err) from err

    if profile is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "プロフィールが見つかりません")

    return ProfileResponse(
        user_id=profile["user_id"],
        display_name=profile["display_name"],
        email=user.email,
        created_at=profile.get("created_at"),
    )
