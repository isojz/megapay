from dataclasses import dataclass
from functools import lru_cache

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .config import get_settings

_bearer = HTTPBearer(auto_error=False)

# Supabase が発行しうる署名アルゴリズム
_ASYMMETRIC_ALGS = {"ES256", "RS256", "EdDSA"}


@dataclass
class AuthUser:
    """Supabase Auth の JWT から取り出したログインユーザー情報。"""

    id: str
    email: str
    token: str  # Supabase へそのまま転送する（RLS / auth.uid() を効かせるため）


@lru_cache
def _jwks_client() -> jwt.PyJWKClient:
    """Supabase の公開鍵(JWKS)クライアント。鍵はライブラリ側でキャッシュされる。"""
    jwks_url = f"{get_settings().supabase_url}/auth/v1/.well-known/jwks.json"
    return jwt.PyJWKClient(jwks_url)


def _decode_token(token: str) -> dict:
    """JWT を検証してペイロードを返す。

    - 新方式プロジェクト: ECC/RSA 署名キー → JWKS の公開鍵で検証
    - レガシープロジェクト: HS256 → SUPABASE_JWT_SECRET で検証
    """
    header = jwt.get_unverified_header(token)
    alg = header.get("alg", "")

    if alg == "HS256":
        secret = get_settings().supabase_jwt_secret
        if not secret:
            raise jwt.InvalidTokenError("HS256 token but SUPABASE_JWT_SECRET is not set")
        return jwt.decode(token, secret, algorithms=["HS256"], audience="authenticated")

    if alg in _ASYMMETRIC_ALGS:
        signing_key = _jwks_client().get_signing_key_from_jwt(token)
        return jwt.decode(token, signing_key.key, algorithms=[alg], audience="authenticated")

    raise jwt.InvalidTokenError(f"unsupported alg: {alg}")


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
) -> AuthUser:
    if credentials is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "認証トークンがありません")

    token = credentials.credentials
    try:
        payload = _decode_token(token)
    except jwt.PyJWTError as err:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "認証トークンが不正です") from err

    return AuthUser(id=payload["sub"], email=payload.get("email", ""), token=token)
