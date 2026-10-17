from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from src.application.transactions.use_cases import (
    CreateTransactionUseCase,
    DeleteTransactionUseCase,
    ListTransactionsUseCase,
)
from src.infrastructure.database.connection import get_db
from src.infrastructure.database.repositories.transaction_repository import SQLTransactionRepository
from src.infrastructure.security import get_current_user
from src.domain.auth.entities import User
from src.presentation.schemas.transaction_schemas import CreateTransactionRequest, TransactionResponse

router = APIRouter(prefix="/transactions", tags=["Transactions"])


@router.get("/org/{org_id}", response_model=list[TransactionResponse])
async def list_transactions(
    org_id: int,
    start_date: datetime | None = Query(default=None),
    end_date: datetime | None = Query(default=None),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
) -> list[TransactionResponse]:
    """Lista transações de uma organização com filtros opcionais de período."""
    repo = SQLTransactionRepository(db)
    txs = await ListTransactionsUseCase(repo).execute(org_id, start_date, end_date)
    return [
        TransactionResponse(
            id=t.id, description=t.description, amount=t.amount, type=t.type,
            category_id=t.category_id, organization_id=t.organization_id,
            user_id=t.user_id, notes=t.notes, created_at=t.created_at,
        )
        for t in txs
    ]


@router.post("/org/{org_id}", response_model=TransactionResponse, status_code=status.HTTP_201_CREATED)
async def create_transaction(
    org_id: int,
    body: CreateTransactionRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> TransactionResponse:
    """Cria uma nova transação. Requer autenticação."""
    repo = SQLTransactionRepository(db)
    try:
        tx = await CreateTransactionUseCase(repo).execute(
            description=body.description,
            amount=body.amount,
            type=body.type,
            category_id=body.category_id,
            org_id=org_id,
            user_id=current_user.id,
            notes=body.notes,
        )
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(e))
    return TransactionResponse(
        id=tx.id, description=tx.description, amount=tx.amount, type=tx.type,
        category_id=tx.category_id, organization_id=tx.organization_id,
        user_id=tx.user_id, notes=tx.notes, created_at=tx.created_at,
    )


@router.delete("/{transaction_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_transaction(
    transaction_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
) -> None:
    """Remove uma transação. Requer autenticação."""
    repo = SQLTransactionRepository(db)
    try:
        await DeleteTransactionUseCase(repo).execute(transaction_id)
    except LookupError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
