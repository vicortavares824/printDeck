from datetime import datetime
from pydantic import BaseModel, Field
from src.domain.transactions.entities import TransactionType


class CreateTransactionRequest(BaseModel):
    description: str = Field(..., min_length=2, max_length=300)
    amount: float = Field(..., gt=0)
    type: TransactionType
    category_id: int | None = None
    notes: str | None = None


class TransactionResponse(BaseModel):
    id: int
    description: str
    amount: float
    type: TransactionType
    category_id: int | None
    organization_id: int
    user_id: int
    notes: str | None
    created_at: datetime

    model_config = {"from_attributes": True}
