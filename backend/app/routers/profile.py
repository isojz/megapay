from fastapi import APIRouter, Depends, HTTPException, status
from postgrest.exceptions import APIError

from .. import db
from ..auth import AuthUser, get_current_user
from ..errors import to_http_exception
from ..schemas import ProfileAvatarUpdate, ProfileResponse

router = APIRouter(prefix="/api/v1", tags=["profile"])


def _to_profile_response(
    profile: dict,
    email: str,
) -> ProfileResponse:
    return ProfileResponse(
        user_id=profile["user_id"],
        display_name=profile["display_name"],
        email=email,
        avatar_key=profile.get("avatar_key") or "avatar_01",
        created_at=profile.get("created_at"),
    )


@router.get("/me", response_model=ProfileResponse)
def get_me(user: AuthUser = Depends(get_current_user)) -> ProfileResponse:
    try:
        profile = db.fetch_profile(user.token, user.id)
    except APIError as err:
        raise to_http_exception(err) from err

    if profile is None:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND,
            "プロフィールが見つかりません",
        )

    return _to_profile_response(profile, user.email)


@router.patch("/me/avatar", response_model=ProfileResponse)
def update_my_avatar(
    payload: ProfileAvatarUpdate,
    user: AuthUser = Depends(get_current_user),
) -> ProfileResponse:
    try:
        profile = db.update_avatar_key(
            token=user.token,
            profile_id=user.id,
            avatar_key=payload.avatar_key,
        )
    except APIError as err:
        raise to_http_exception(err) from err

    if profile is None:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND,
            "プロフィールが見つかりません",
        )

    return _to_profile_response(profile, user.email)