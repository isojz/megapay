from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, Field, field_validator


class ProfileResponse(BaseModel):
    user_id: str
    display_name: str
    email: str
    created_at: datetime | None = None


class BalanceResponse(BaseModel):
    currency: str
    amount: str  # 金額は桁落ち防止のため API 上は常に文字列で扱う


class RecipientResponse(BaseModel):
    user_id: str
    display_name: str


class TransferCreate(BaseModel):
    recipient_user_id: str = Field(min_length=1, max_length=32)
    currency: str = Field(pattern=r"^[A-Za-z0-9]{3,10}$")
    amount: Decimal = Field(gt=0)
    memo: str | None = Field(default=None, max_length=200)

    @field_validator("amount")
    @classmethod
    def validate_scale(cls, value: Decimal) -> Decimal:
        exponent = value.as_tuple().exponent
        if isinstance(exponent, int) and exponent < -8:
            raise ValueError("金額は小数第8位までで指定してください")
        return value


class TransferResponse(BaseModel):
    id: str
    recipient_user_id: str
    currency: str
    amount: str
    memo: str | None = None
    created_at: datetime


class TransferHistoryItem(BaseModel):
    id: str
    direction: str  # "sent"（送金） / "received"（受取）
    counterpart_user_id: str
    counterpart_name: str
    currency: str
    amount: str
    memo: str | None = None
    created_at: datetime
