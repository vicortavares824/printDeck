from datetime import datetime

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from src.application.reports.use_cases import GenerateFinancialReportUseCase
from src.infrastructure.database.connection import get_db
from src.infrastructure.database.repositories.transaction_repository import SQLTransactionRepository
from src.infrastructure.security import get_current_user
from src.domain.auth.entities import User
from src.presentation.schemas.report_schemas import FinancialReportResponse

router = APIRouter(prefix="/reports", tags=["Reports"])


@router.get("/financial/org/{org_id}", response_model=FinancialReportResponse)
async def financial_report(
    org_id: int,
    start_date: datetime | None = Query(default=None),
    end_date: datetime | None = Query(default=None),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
) -> FinancialReportResponse:
    """Gera relatório financeiro consolidado de uma organização. Requer autenticação."""
    repo = SQLTransactionRepository(db)
    summary = await GenerateFinancialReportUseCase(repo).execute(org_id, start_date, end_date)
    return FinancialReportResponse(
        total_income=summary.total_income,
        total_expense=summary.total_expense,
        net_balance=summary.net_balance,
        transaction_count=summary.transaction_count,
        period_start=summary.period_start,
        period_end=summary.period_end,
    )
