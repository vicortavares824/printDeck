from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Header
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List, Optional

from app.core.database import get_db
from app.core.config import settings
from app.models.supply import CloudSupplyItem
from app.schemas.supply import SupplyItemIn, SupplyItemOut, SupplySyncIn

router = APIRouter(prefix="/api/supply", tags=["supply"])

# O inventário é um único escopo compartilhado/global: todos os dispositivos veem e
# editam o mesmo conjunto de itens. Last-write-wins por updated_at é aceitável para v1.
# /sync é um upsert por item e NUNCA deve apagar em massa o escopo compartilhado.
SHARED_SCOPE = "__shared__"


def verify_secret(x_api_key: str | None = Header(default=None)):
    if settings.API_SECRET_KEY and settings.API_SECRET_KEY != "disabled":
        if x_api_key != settings.API_SECRET_KEY:
            raise HTTPException(status_code=401, detail="Chave de API inválida ou ausente")


@router.get("/items", response_model=List[SupplyItemOut], dependencies=[Depends(verify_secret)])
async def list_supply_items(
    device_id: str,
    db: AsyncSession = Depends(get_db),
):
    # device_id é aceito para estabilidade do contrato, mas IGNORADO para escopo:
    # sempre retornamos todo o inventário compartilhado.
    result = await db.execute(
        select(CloudSupplyItem).where(CloudSupplyItem.device_id == SHARED_SCOPE)
    )
    return result.scalars().all()


@router.post("/sync", dependencies=[Depends(verify_secret)])
async def sync_supply_items(
    data: SupplySyncIn,
    db: AsyncSession = Depends(get_db),
):
    # Upsert por item dentro do escopo compartilhado. NÃO apaga itens ausentes do payload
    # (não destrutivo). data.device_id é aceito mas ignorado para escopo.
    for item in data.items:
        result = await db.execute(
            select(CloudSupplyItem).where(
                CloudSupplyItem.device_id == SHARED_SCOPE,
                CloudSupplyItem.item_id == item.item_id,
            )
        )
        existing = result.scalars().first()

        if existing:
            existing.title = item.title
            existing.description = item.description or ""
            existing.quantity = item.quantity
            existing.is_bought = item.is_bought
            existing.updated_at = datetime.utcnow()
        else:
            db.add(
                CloudSupplyItem(
                    device_id=SHARED_SCOPE,
                    item_id=item.item_id,
                    title=item.title,
                    description=item.description or "",
                    quantity=item.quantity,
                    is_bought=item.is_bought,
                )
            )

    await db.commit()
    return {"synced": len(data.items)}


@router.delete("/items/{item_id}", dependencies=[Depends(verify_secret)])
async def delete_supply_item(
    item_id: str,
    device_id: str,
    db: AsyncSession = Depends(get_db),
):
    # device_id é aceito para estabilidade do contrato, mas NÃO usado para escopo:
    # a remoção acontece no inventário compartilhado para todos.
    result = await db.execute(
        select(CloudSupplyItem).where(
            CloudSupplyItem.item_id == item_id,
            CloudSupplyItem.device_id == SHARED_SCOPE,
        )
    )
    item = result.scalars().first()
    if not item:
        raise HTTPException(status_code=404, detail="Item não encontrado")

    await db.delete(item)
    await db.commit()
    return {"deleted": True}
