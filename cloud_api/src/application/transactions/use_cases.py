from datetime import datetime

from src.domain.transactions.entities import Transaction, TransactionType
from src.domain.transactions.interfaces import ITransactionRepository


class CreateTransactionUseCase:
    def __init__(self, repo: ITransactionRepository) -> None:
        self._repo = repo

    async def execute(
        self,
        description: str,
        amount: float,
        type: TransactionType,
        category_id: int | None,
        org_id: int,
        user_id: int,
        notes: str | None = None,
    ) -> Transaction:
        if amount <= 0:
            raise ValueError("O valor da transação deve ser positivo.")
        tx = Transaction(
            id=None,
            description=description,
            amount=amount,
            type=type,
            category_id=category_id,
            organization_id=org_id,
            user_id=user_id,
            notes=notes,
        )
        return await self._repo.create(tx)


class ListTransactionsUseCase:
    def __init__(self, repo: ITransactionRepository) -> None:
        self._repo = repo

    async def execute(
        self,
        org_id: int,
        start_date: datetime | None = None,
        end_date: datetime | None = None,
    ) -> list[Transaction]:
        return await self._repo.list_by_organization(org_id, start_date, end_date)


class DeleteTransactionUseCase:
    def __init__(self, repo: ITransactionRepository) -> None:
        self._repo = repo

    async def execute(self, transaction_id: int) -> None:
        tx = await self._repo.get_by_id(transaction_id)
        if not tx:
            raise LookupError(f"Transação {transaction_id} não encontrada.")
        await self._repo.delete(transaction_id)
