from datetime import datetime
from pydantic import BaseModel


class FinancialReportResponse(BaseModel):
    total_income: float
    total_expense: float
    net_balance: float
    transaction_count: int
    period_start: datetime | None
    period_end: datetime | None
