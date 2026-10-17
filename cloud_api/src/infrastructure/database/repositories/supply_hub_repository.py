from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.domain.supply_hub.entities import StockMovement, StockUnit, SupplyItem
from src.domain.supply_hub.interfaces import IStockMovementRepository, ISupplyItemRepository
from src.infrastructure.database.models.supply_hub_models import StockMovementModel, SupplyItemModel


class SQLSupplyItemRepository(ISupplyItemRepository):
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    def _to_entity(self, model: SupplyItemModel) -> SupplyItem:
        return SupplyItem(
            id=model.id,
            name=model.name,
            description=model.description,
            sku=model.sku,
            unit=StockUnit(model.unit),
            quantity=model.quantity,
            min_quantity=model.min_quantity,
            unit_cost=model.unit_cost,
            supplier=model.supplier,
            location=model.location,
            is_active=model.is_active,
            created_at=model.created_at,
            updated_at=model.updated_at,
        )

    async def get_by_id(self, item_id: int) -> SupplyItem | None:
        result = await self._session.execute(select(SupplyItemModel).where(SupplyItemModel.id == item_id))
        model = result.scalars().first()
        return self._to_entity(model) if model else None

    async def list_all(self, active_only: bool = True) -> list[SupplyItem]:
        query = select(SupplyItemModel).order_by(SupplyItemModel.name)
        if active_only:
            query = query.where(SupplyItemModel.is_active.is_(True))
        result = await self._session.execute(query)
        return [self._to_entity(m) for m in result.scalars().all()]

    async def list_low_stock(self) -> list[SupplyItem]:
        result = await self._session.execute(
            select(SupplyItemModel)
            .where(SupplyItemModel.is_active.is_(True))
            .where(SupplyItemModel.quantity <= SupplyItemModel.min_quantity)
            .order_by(SupplyItemModel.name)
        )
        return [self._to_entity(m) for m in result.scalars().all()]

    async def create(self, item: SupplyItem) -> SupplyItem:
        model = SupplyItemModel(
            name=item.name,
            description=item.description,
            sku=item.sku,
            unit=item.unit.value,
            quantity=item.quantity,
            min_quantity=item.min_quantity,
            unit_cost=item.unit_cost,
            supplier=item.supplier,
            location=item.location,
            is_active=item.is_active,
        )
        self._session.add(model)
        await self._session.commit()
        await self._session.refresh(model)
        return self._to_entity(model)

    async def update(self, item: SupplyItem) -> SupplyItem:
        result = await self._session.execute(select(SupplyItemModel).where(SupplyItemModel.id == item.id))
        model = result.scalars().first()
        if not model:
            raise LookupError(f"SupplyItem {item.id} not found.")
        model.name = item.name
        model.description = item.description
        model.sku = item.sku
        model.unit = item.unit.value
        model.quantity = item.quantity
        model.min_quantity = item.min_quantity
        model.unit_cost = item.unit_cost
        model.supplier = item.supplier
        model.location = item.location
        model.is_active = item.is_active
        await self._session.commit()
        await self._session.refresh(model)
        return self._to_entity(model)

    async def delete(self, item_id: int) -> None:
        result = await self._session.execute(select(SupplyItemModel).where(SupplyItemModel.id == item_id))
        model = result.scalars().first()
        if model:
            await self._session.delete(model)
            await self._session.commit()


class SQLStockMovementRepository(IStockMovementRepository):
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    def _to_entity(self, model: StockMovementModel) -> StockMovement:
        return StockMovement(
            id=model.id,
            supply_item_id=model.supply_item_id,
            quantity_delta=model.quantity_delta,
            reason=model.reason,
            user_id=model.user_id,
            created_at=model.created_at,
        )

    async def list_by_item(self, item_id: int) -> list[StockMovement]:
        result = await self._session.execute(
            select(StockMovementModel)
            .where(StockMovementModel.supply_item_id == item_id)
            .order_by(StockMovementModel.created_at.desc())
        )
        return [self._to_entity(m) for m in result.scalars().all()]

    async def create(self, movement: StockMovement) -> StockMovement:
        model = StockMovementModel(
            supply_item_id=movement.supply_item_id,
            quantity_delta=movement.quantity_delta,
            reason=movement.reason,
            user_id=movement.user_id,
        )
        self._session.add(model)
        await self._session.commit()
        await self._session.refresh(model)
        return self._to_entity(model)
