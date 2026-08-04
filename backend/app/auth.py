from dataclasses import dataclass

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .config import get_settings

_bearer = HTTPBearer(auto_error=False)


@dataclass
class AuthUser:
    """Supabase Auth の JWT から取り出したログインユーザー情報。"""

    id: str
    email: str
    token: str  # Supabase へそのまま転送する（RLS / auth.uid() を効かせるため）


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
) -> AuthUser:
    if credentials is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "認証トークンがありません")

    token = credentials.credentials
    try:
        payload = jwt.decode(
            token,
            get_settings().supabase_jwt_secret,
            algorithms=["HS256"],
            audience="authenticated",
        )
    except jwt.PyJWTError as err:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "認証トークンが不正です") from err

    return AuthUser(id=payload["sub"], email=payload.get("email", ""), token=token)
