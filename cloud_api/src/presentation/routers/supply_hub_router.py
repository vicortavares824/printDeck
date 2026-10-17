from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from src.application.supply_hub.use_cases import (
    CreateSupplyItemUseCase,
    GetSupplyItemUseCase,
    ListLowStockUseCase,
    ListSupplyItemsUseCase,
    UpdateStockMovementUseCase,
)
from src.infrastructure.database.connection import get_db
from src.infrastructure.database.repositories.supply_hub_repository import (
    SQLStockMovementRepository,
    SQLSupplyItemRepository,
)
from src.infrastructure.security import get_current_user
from src.domain.auth.entities import User
from src.presentation.schemas.supply_hub_schemas import (
    CreateSupplyItemRequest,
    StockMovementRequest,
    StockMovementResponse,
    SupplyItemResponse,
)

router = APIRouter(prefix="/supply-hub", tags=["Supply Hub (Almoxarifado)"])


def _map_item(item) -> SupplyItemResponse:
    return SupplyItemResponse(
        id=item.id,
        name=item.name,
        description=item.description,
        sku=item.sku,
        unit=item.unit,
        quantity=item.quantity,
        min_quantity=item.min_quantity,
        unit_cost=item.unit_cost,
        supplier=item.supplier,
        location=item.location,
        is_active=item.is_active,
        is_low_stock=item.is_low_stock,
        created_at=item.created_at,
        updated_at=item.updated_at,
    )


# ── PUBLIC endpoints (sem autenticação) ─────────────────────────

@router.get("/items", response_model=list[SupplyItemResponse], summary="[Pública] Listar insumos")
async def list_supply_items(
    active_only: bool = True,
    db: AsyncSession = Depends(get_db),
) -> list[SupplyItemResponse]:
    """Retorna o catálogo completo de insumos do almoxarifado. Acesso público."""
    repo = SQLSupplyItemRepository(db)
    items = await ListSupplyItemsUseCase(repo).execute(active_only=active_only)
    return [_map_item(i) for i in items]


@router.get("/items/low-stock", response_model=list[SupplyItemResponse], summary="[Pública] Itens abaixo do mínimo")
async def list_low_stock(db: AsyncSession = Depends(get_db)) -> list[SupplyItemResponse]:
    """Lista insumos com estoque abaixo do mínimo. Acesso público."""
    repo = SQLSupplyItemRepository(db)
    items = await ListLowStockUseCase(repo).execute()
    return [_map_item(i) for i in items]


@router.get("/items/{item_id}", response_model=SupplyItemResponse, summary="[Pública] Detalhe do insumo")
async def get_supply_item(item_id: int, db: AsyncSession = Depends(get_db)) -> SupplyItemResponse:
    """Retorna os detalhes de um insumo específico. Acesso público."""
    repo = SQLSupplyItemRepository(db)
    try:
        item = await GetSupplyItemUseCase(repo).execute(item_id)
    except LookupError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
    return _map_item(item)


# ── PROTECTED endpoints (requer autenticação) ────────────────────

@router.post("/items", response_model=SupplyItemResponse, status_code=status.HTTP_201_CREATED, summary="Criar insumo")
async def create_supply_item(
    body: CreateSupplyItemRequest,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
) -> SupplyItemResponse:
    """Cadastra um novo insumo no almoxarifado. Requer autenticação."""
    repo = SQLSupplyItemRepository(db)
    item = await CreateSupplyItemUseCase(repo).execute(
        name=body.name,
        unit=body.unit,
        quantity=body.quantity,
        min_quantity=body.min_quantity,
        description=body.description,
        sku=body.sku,
        unit_cost=body.unit_cost,
        supplier=body.supplier,
        location=body.location,
    )
    return _map_item(item)


@router.post(
    "/items/{item_id}/movements",
    response_model=StockMovementResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Registrar movimentação de estoque",
)
async def register_movement(
    item_id: int,
    body: StockMovementRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> StockMovementResponse:
    """Registra entrada (+) ou saída (-) de estoque. Requer autenticação."""
    item_repo = SQLSupplyItemRepository(db)
    movement_repo = SQLStockMovementRepository(db)
    try:
        mv = await UpdateStockMovementUseCase(item_repo, movement_repo).execute(
            item_id=item_id,
            quantity_delta=body.quantity_delta,
            reason=body.reason,
            user_id=current_user.id,
        )
    except (LookupError, ValueError) as e:
        status_code = status.HTTP_404_NOT_FOUND if isinstance(e, LookupError) else status.HTTP_422_UNPROCESSABLE_ENTITY
        raise HTTPException(status_code=status_code, detail=str(e))
    return StockMovementResponse(
        id=mv.id,
        supply_item_id=mv.supply_item_id,
        quantity_delta=mv.quantity_delta,
        reason=mv.reason,
        user_id=mv.user_id,
        created_at=mv.created_at,
    )


@router.get("/items/{item_id}/movements", response_model=list[StockMovementResponse], summary="Histórico de movimentações")
async def list_movements(
    item_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
) -> list[StockMovementResponse]:
    """Retorna o histórico de movimentações de um insumo. Requer autenticação."""
    repo = SQLStockMovementRepository(db)
    movements = await repo.list_by_item(item_id)
    return [
        StockMovementResponse(
            id=m.id, supply_item_id=m.supply_item_id, quantity_delta=m.quantity_delta,
            reason=m.reason, user_id=m.user_id, created_at=m.created_at,
        )
        for m in movements
    ]
