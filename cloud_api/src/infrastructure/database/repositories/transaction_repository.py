from datetime import datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.domain.transactions.entities import Transaction, TransactionType
from src.domain.transactions.interfaces import ITransactionRepository
from src.infrastructure.database.models.transaction_models import TransactionModel


class SQLTransactionRepository(ITransactionRepository):
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    def _to_entity(self, model: TransactionModel) -> Transaction:
        return Transaction(
            id=model.id,
            description=model.description,
            amount=model.amount,
            type=TransactionType(model.type),
            category_id=model.category_id,
            organization_id=model.organization_id,
            user_id=model.user_id,
            notes=model.notes,
            created_at=model.created_at,
        )

    async def get_by_id(self, transaction_id: int) -> Transaction | None:
        result = await self._session.execute(select(TransactionModel).where(TransactionModel.id == transaction_id))
        model = result.scalars().first()
        return self._to_entity(model) if model else None

    async def list_by_organization(
        self,
        org_id: int,
        start_date: datetime | None = None,
        end_date: datetime | None = None,
    ) -> list[Transaction]:
        query = select(TransactionModel).where(TransactionModel.organization_id == org_id)
        if start_date:
            query = query.where(TransactionModel.created_at >= start_date)
        if end_date:
            query = query.where(TransactionModel.created_at <= end_date)
        query = query.order_by(TransactionModel.created_at.desc())
        result = await self._session.execute(query)
        return [self._to_entity(m) for m in result.scalars().all()]

    async def create(self, transaction: Transaction) -> Transaction:
        model = TransactionModel(
            description=transaction.description,
            amount=transaction.amount,
            type=transaction.type.value,
            category_id=transaction.category_id,
            organization_id=transaction.organization_id,
            user_id=transaction.user_id,
            notes=transaction.notes,
        )
        self._session.add(model)
        await self._session.commit()
        await self._session.refresh(model)
        return self._to_entity(model)

    async def delete(self, transaction_id: int) -> None:
        result = await self._session.execute(select(TransactionModel).where(TransactionModel.id == transaction_id))
        model = result.scalars().first()
        if model:
            await self._session.delete(model)
            await self._session.commit()
