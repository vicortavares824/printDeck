from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query, Header
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, update as sa_update

from app.core.database import get_db
from app.core.config import settings
from app.models.supply_item import SupplyItem
from app.schemas.supply import (
    SupplyItemCreate,
    SupplyItemUpdate,
    SupplyItemResponse,
    SupplyItemListResponse,
)

router = APIRouter(prefix="/api/supplies", tags=["SupplyHub"])


def verify_write_key(x_api_key: Optional[str] = Header(default=None)):
    if settings.CLOUD_API_KEY and settings.CLOUD_API_KEY != "disabled":
        if x_api_key != settings.CLOUD_API_KEY:
            raise HTTPException(status_code=401, detail="Chave de API inválida ou ausente")


@router.get("/", response_model=SupplyItemListResponse)
async def list_supplies(
    db: AsyncSession = Depends(get_db),
    category: Optional[str] = Query(None),
    search: Optional[str] = Query(None),
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=1000),
    active_only: bool = Query(True),
):
    """
    Lista todos os insumos do almoxarifado (acesso público para leitura).
    Suporta filtros por categoria, busca por texto, paginação e itens ativos.
    """
    query = select(SupplyItem)

    if active_only:
        query = query.where(SupplyItem.is_active == True)  # noqa: E712

    if category:
        query = query.where(SupplyItem.category == category)

    if search:
        search_pattern = f"%{search}%"
        query = query.where(
            SupplyItem.name.ilike(search_pattern)
            | SupplyItem.description.ilike(search_pattern)
            | SupplyItem.sku.ilike(search_pattern)
        )

    count_query = select(func.count()).select_from(query.subquery())
    count_result = await db.execute(count_query)
    total = count_result.scalar()

    query = query.offset(skip).limit(limit).order_by(SupplyItem.created_at.desc())
    result = await db.execute(query)
    items = result.scalars().all()

    return SupplyItemListResponse(items=items, total=total)


@router.get("/{supply_id}", response_model=SupplyItemResponse)
async def get_supply(supply_id: int, db: AsyncSession = Depends(get_db)):
    """Obtém detalhes de um insumo específico (acesso público)."""
    result = await db.execute(select(SupplyItem).where(SupplyItem.id == supply_id))
    item = result.scalars().first()
    if not item:
        raise HTTPException(status_code=404, detail="Insumo não encontrado")
    return item


@router.post("/", response_model=SupplyItemResponse, dependencies=[Depends(verify_write_key)])
async def create_supply(supply_data: SupplyItemCreate, db: AsyncSession = Depends(get_db)):
    """Cria um novo insumo no almoxarifado (requer autenticação)."""
    existing = await db.execute(
        select(SupplyItem).where(SupplyItem.sku == supply_data.sku)
    ) if supply_data.sku else None
    if existing and existing.scalars().first():
        raise HTTPException(status_code=400, detail="SKU já cadastrado")

    new_item = SupplyItem(**supply_data.model_dump())
    db.add(new_item)
    await db.commit()
    await db.refresh(new_item)
    return new_item


@router.put("/{supply_id}", response_model=SupplyItemResponse, dependencies=[Depends(verify_write_key)])
async def update_supply(
    supply_id: int,
    supply_data: SupplyItemUpdate,
    db: AsyncSession = Depends(get_db),
):
    """Atualiza um insumo existente (requer autenticação)."""
    result = await db.execute(select(SupplyItem).where(SupplyItem.id == supply_id))
    item = result.scalars().first()
    if not item:
        raise HTTPException(status_code=404, detail="Insumo não encontrado")

    update_data = supply_data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(item, field, value)

    await db.commit()
    await db.refresh(item)
    return item


@router.patch("/{supply_id}/quantity", response_model=SupplyItemResponse, dependencies=[Depends(verify_write_key)])
async def update_supply_quantity(
    supply_id: int,
    quantity: int,
    db: AsyncSession = Depends(get_db),
):
    """Altera a quantidade de um insumo (requer autenticação)."""
    result = await db.execute(select(SupplyItem).where(SupplyItem.id == supply_id))
    item = result.scalars().first()
    if not item:
        raise HTTPException(status_code=404, detail="Insumo não encontrado")

    item.quantity = quantity
    await db.commit()
    await db.refresh(item)
    return item


@router.patch("/{supply_id}/status", response_model=SupplyItemResponse, dependencies=[Depends(verify_write_key)])
async def update_supply_status(
    supply_id: int,
    is_active: bool,
    db: AsyncSession = Depends(get_db),
):
    """Altera o status ativo/inativo de um insumo (requer autenticação)."""
    result = await db.execute(select(SupplyItem).where(SupplyItem.id == supply_id))
    item = result.scalars().first()
    if not item:
        raise HTTPException(status_code=404, detail="Insumo não encontrado")

    item.is_active = is_active
    await db.commit()
    await db.refresh(item)
    return item


@router.delete("/{supply_id}", dependencies=[Depends(verify_write_key)])
async def delete_supply(supply_id: int, db: AsyncSession = Depends(get_db)):
    """Remove um insumo do almoxarifado (requer autenticação)."""
    result = await db.execute(select(SupplyItem).where(SupplyItem.id == supply_id))
    item = result.scalars().first()
    if not item:
        raise HTTPException(status_code=404, detail="Insumo não encontrado")

    await db.delete(item)
    await db.commit()
    return {"detail": "Insumo removido com sucesso"}
