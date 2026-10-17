from abc import ABC, abstractmethod
from datetime import datetime
from .entities import Transaction


class ITransactionRepository(ABC):
    @abstractmethod
    async def get_by_id(self, transaction_id: int) -> Transaction | None: ...

    @abstractmethod
    async def list_by_organization(
        self,
        org_id: int,
        start_date: datetime | None = None,
        end_date: datetime | None = None,
    ) -> list[Transaction]: ...

    @abstractmethod
    async def create(self, transaction: Transaction) -> Transaction: ...

    @abstractmethod
    async def delete(self, transaction_id: int) -> None: ...
