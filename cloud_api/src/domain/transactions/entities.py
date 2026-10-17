from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum


class TransactionType(str, Enum):
    INCOME = "income"
    EXPENSE = "expense"


@dataclass
class Transaction:
    id: int | None
    description: str
    amount: float
    type: TransactionType
    category_id: int | None
    organization_id: int
    user_id: int
    notes: str | None = None
    created_at: datetime = field(default_factory=datetime.utcnow)
