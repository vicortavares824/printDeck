from datetime import datetime
from dataclasses import dataclass

from src.domain.transactions.entities import TransactionType
from src.domain.transactions.interfaces import ITransactionRepository


@dataclass
class FinancialSummary:
    total_income: float
    total_expense: float
    net_balance: float
    transaction_count: int
    period_start: datetime | None
    period_end: datetime | None


class GenerateFinancialReportUseCase:
    def __init__(self, tx_repo: ITransactionRepository) -> None:
        self._repo = tx_repo

    async def execute(
        self,
        org_id: int,
        start_date: datetime | None = None,
        end_date: datetime | None = None,
    ) -> FinancialSummary:
        transactions = await self._repo.list_by_organization(org_id, start_date, end_date)
        income = sum(t.amount for t in transactions if t.type == TransactionType.INCOME)
        expense = sum(t.amount for t in transactions if t.type == TransactionType.EXPENSE)
        return FinancialSummary(
            total_income=income,
            total_expense=expense,
            net_balance=income - expense,
            transaction_count=len(transactions),
            period_start=start_date,
            period_end=end_date,
        )
