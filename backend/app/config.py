from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """アプリ設定。環境変数・backend/.env があればそちらが優先される。

    デフォルト値はチーム共有の開発用 Supabase プロジェクト。
    anon キーは RLS 前提で公開可能なキーのため、リポジトリに含めている
    （service_role 等の秘密キーは一切含めない）。本番では環境変数で上書きすること。
    """

    supabase_url: str = "https://xjiwxiyzuujyaitheuwg.supabase.co"
    supabase_anon_key: str = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhqaXd4aXl6dXVqeWFpdGhldXdnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU4MTM4NjUsImV4cCI6MjEwMTM4OTg2NX0.LqDs6sKOLEsKNTbSGpcbre8NhKicK1_Xy3MRnGfmomM"
    supabase_jwt_secret: str = ""
    cors_origins: str = "*"

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
