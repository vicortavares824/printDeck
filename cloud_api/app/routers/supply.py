from fastapi import APIRouter, Depends, HTTPException, Header
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, delete
from typing import List, Optional

from app.core.database import get_db
from app.core.config import settings
from app.models.supply import CloudSupplyItem
from app.schemas.supply import SupplyItemIn, SupplyItemOut, SupplySyncIn

router = APIRouter(prefix="/api/supply", tags=["supply"])


def verify_secret(x_api_key: str | None = Header(default=None)):
    if settings.API_SECRET_KEY and settings.API_SECRET_KEY != "disabled":
        if x_api_key != settings.API_SECRET_KEY:
            raise HTTPException(status_code=401, detail="Chave de API inválida ou ausente")


@router.get("/items", response_model=List[SupplyItemOut], dependencies=[Depends(verify_secret)])
async def list_supply_items(
    device_id: str,
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(CloudSupplyItem).where(CloudSupplyItem.device_id == device_id)
    )
    return result.scalars().all()


@router.post("/sync", dependencies=[Depends(verify_secret)])
async def sync_supply_items(
    data: SupplySyncIn,
    db: AsyncSession = Depends(get_db),
):
    # Substitui todos os itens do dispositivo pela lista enviada (merge simples por item_id)
    await db.execute(
        delete(CloudSupplyItem).where(CloudSupplyItem.device_id == data.device_id)
    )

    for item in data.items:
        db.add(
            CloudSupplyItem(
                device_id=data.device_id,
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
    result = await db.execute(
        select(CloudSupplyItem).where(
            CloudSupplyItem.item_id == item_id,
            CloudSupplyItem.device_id == device_id,
        )
    )
    item = result.scalars().first()
    if not item:
        raise HTTPException(status_code=404, detail="Item não encontrado")

    await db.delete(item)
    await db.commit()
    return {"deleted": True}
