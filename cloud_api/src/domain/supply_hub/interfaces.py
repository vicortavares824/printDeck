from abc import ABC, abstractmethod
from .entities import SupplyItem, StockMovement


class ISupplyItemRepository(ABC):
    @abstractmethod
    async def get_by_id(self, item_id: int) -> SupplyItem | None: ...

    @abstractmethod
    async def list_all(self, active_only: bool = True) -> list[SupplyItem]: ...

    @abstractmethod
    async def list_low_stock(self) -> list[SupplyItem]: ...

    @abstractmethod
    async def create(self, item: SupplyItem) -> SupplyItem: ...

    @abstractmethod
    async def update(self, item: SupplyItem) -> SupplyItem: ...

    @abstractmethod
    async def delete(self, item_id: int) -> None: ...


class IStockMovementRepository(ABC):
    @abstractmethod
    async def list_by_item(self, item_id: int) -> list[StockMovement]: ...

    @abstractmethod
    async def create(self, movement: StockMovement) -> StockMovement: ...
