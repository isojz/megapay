"""割り勘機能のリクエスト / レスポンススキーマ。

金額は桁落ち防止のため API 上は常に文字列で扱う（送金・請求と同じ方針）。
"""

from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, Field, field_validator


class SplitBillCreate(BaseModel):
    """集金者が割り勘を登録するときの入力。"""

    title: str = Field(min_length=1, max_length=100)  # イベント名
    currency: str = Field(pattern=r"^[A-Za-z0-9]{3,10}$")
    total_amount: Decimal = Field(gt=0)  # 合計金額
    participant_count: int = Field(ge=2, le=100)  # 集金者を含む参加人数

    @field_validator("total_amount")
    @classmethod
    def validate_scale(cls, value: Decimal) -> Decimal:
        exponent = value.as_tuple().exponent
        if isinstance(exponent, int) and exponent < -8:
            raise ValueError("金額は小数第8位までで指定してください")
        return value


class SplitBillResponse(BaseModel):
    bill_code: str  # 参加用の請求コード（SP-XXXXXXXX）
    title: str
    currency: str
    total_amount: str
    participant_count: int
    share_amount: str  # 1人あたりの金額（端数切り上げ）
    organizer_user_id: str
    organizer_name: str
    is_organizer: bool  # 閲覧者が集金者か
    joined: bool  # 閲覧者が参加済みか
    my_request_code: str | None = None  # 参加済みなら自分の請求コード
    my_status: str | None = None  # "pending" / "paid" / "cancelled"
    joined_count: int  # 参加済み人数
    paid_count: int  # 支払い済み人数
    collected_amount: str  # 集まった金額
    created_at: datetime


class SplitBillParticipant(BaseModel):
    """グループ画面に並べる参加者 1 人分の支払い状況。"""

    user_id: str
    display_name: str
    request_code: str
    amount: str
    status: str  # "pending"（未払い） / "paid"（支払い済み）
    paid_at: datetime | None = None
    is_me: bool
    joined_at: datetime
