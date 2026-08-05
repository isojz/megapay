"""請求機能のリクエスト / レスポンススキーマ。

送金機能（schemas.py）と同様、金額は桁落ち防止のため API 上は常に文字列で扱う。
"""

from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, Field, field_validator


class PaymentRequestCreate(BaseModel):
    payer_user_id: str = Field(min_length=1, max_length=32)  # 請求先（支払う人）のユーザーID
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


class PaymentRequestResponse(BaseModel):
    request_code: str  # 支払い時に入力するコード（RQ-XXXXXXXX）
    direction: str  # "requested"（自分が請求した） / "billed"（自分が請求された）
    requester_user_id: str
    requester_name: str
    payer_user_id: str
    payer_name: str
    currency: str
    amount: str
    memo: str | None = None
    status: str  # "pending" / "paid" / "cancelled"
    payment_method: str = "balance"  # "balance"（残高から送金） / "cash"（現金で受け渡し）
    created_at: datetime
    paid_at: datetime | None = None
    cancelled_at: datetime | None = None
