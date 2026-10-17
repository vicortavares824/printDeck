from src.domain.supply_hub.entities import SupplyItem, StockMovement, StockUnit
from src.domain.supply_hub.interfaces import ISupplyItemRepository, IStockMovementRepository


class ListSupplyItemsUseCase:
    """Pública: qualquer cliente pode listar o catálogo de insumos."""

    def __init__(self, repo: ISupplyItemRepository) -> None:
        self._repo = repo

    async def execute(self, active_only: bool = True) -> list[SupplyItem]:
        return await self._repo.list_all(active_only=active_only)


class GetSupplyItemUseCase:
    """Pública: consulta detalhada de um insumo específico."""

    def __init__(self, repo: ISupplyItemRepository) -> None:
        self._repo = repo

    async def execute(self, item_id: int) -> SupplyItem:
        item = await self._repo.get_by_id(item_id)
        if not item:
            raise LookupError(f"Insumo {item_id} não encontrado.")
        return item


class ListLowStockUseCase:
    """Pública: lista itens abaixo do estoque mínimo."""

    def __init__(self, repo: ISupplyItemRepository) -> None:
        self._repo = repo

    async def execute(self) -> list[SupplyItem]:
        return await self._repo.list_low_stock()


class CreateSupplyItemUseCase:
    def __init__(self, repo: ISupplyItemRepository) -> None:
        self._repo = repo

    async def execute(
        self,
        name: str,
        unit: StockUnit,
        quantity: float,
        min_quantity: float,
        description: str | None = None,
        sku: str | None = None,
        unit_cost: float | None = None,
        supplier: str | None = None,
        location: str | None = None,
    ) -> SupplyItem:
        item = SupplyItem(
            id=None,
            name=name,
            description=description,
            sku=sku,
            unit=unit,
            quantity=quantity,
            min_quantity=min_quantity,
            unit_cost=unit_cost,
            supplier=supplier,
            location=location,
        )
        return await self._repo.create(item)


class UpdateStockMovementUseCase:
    """Registra entrada ou saída de estoque e atualiza a quantidade do item."""

    def __init__(
        self,
        item_repo: ISupplyItemRepository,
        movement_repo: IStockMovementRepository,
    ) -> None:
        self._items = item_repo
        self._movements = movement_repo

    async def execute(
        self,
        item_id: int,
        quantity_delta: float,
        reason: str,
        user_id: int | None = None,
    ) -> StockMovement:
        item = await self._items.get_by_id(item_id)
        if not item:
            raise LookupError(f"Insumo {item_id} não encontrado.")
        new_qty = item.quantity + quantity_delta
        if new_qty < 0:
            raise ValueError("Estoque insuficiente para a movimentação solicitada.")
        item.quantity = new_qty
        await self._items.update(item)
        movement = StockMovement(
            id=None,
            supply_item_id=item_id,
            quantity_delta=quantity_delta,
            reason=reason,
            user_id=user_id,
        )
        return await self._movements.create(movement)
