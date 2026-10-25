from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Header
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List, Optional

from app.core.database import get_db
from app.core.config import settings
from app.models.supply import CloudSupplyItem
from app.schemas.supply import (
    SupplyItemIn,
    SupplyItemOut,
    SupplySyncIn,
    SupplySyncOut,
)

router = APIRouter(prefix="/api/supply", tags=["supply"])

# O inventário é um único escopo compartilhado/global: todos os dispositivos veem e
# editam o mesmo conjunto de itens. Last-write-wins por updated_at é aceitável para v1.
# /sync é um upsert por item e NUNCA deve apagar em massa o escopo compartilhado.
SHARED_SCOPE = "__shared__"


def verify_secret(x_api_key: str | None = Header(default=None)):
    if settings.API_SECRET_KEY and settings.API_SECRET_KEY != "disabled":
        if x_api_key != settings.API_SECRET_KEY:
            raise HTTPException(status_code=401, detail="Chave de API inválida ou ausente")


def is_admin(x_admin_code: str | None = Header(default=None)) -> bool:
    """True quando a requisição apresenta o código de admin correto.

    O código é um segredo de backend (settings.ADMIN_CODE, vindo de variável de
    ambiente). Vazio ou "disabled" significa que o admin está desligado e nunca é
    concedido. O código nunca é registrado em log.
    """
    code = settings.ADMIN_CODE
    if not code or code == "disabled":
        return False
    return x_admin_code is not None and x_admin_code == code


def _can_modify(item: CloudSupplyItem, acting_device_id: str, admin: bool) -> bool:
    """Regra de autorização: pode alterar/excluir se for admin, ou se for o dono.

    Itens legados sem owner_id (None) só podem ser alterados por admin.
    """
    if admin:
        return True
    if item.owner_id is None:
        return False
    return item.owner_id == acting_device_id


@router.get("/items", response_model=List[SupplyItemOut], dependencies=[Depends(verify_secret)])
async def list_supply_items(
    device_id: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
):
    # device_id é aceito para estabilidade do contrato, mas IGNORADO para escopo:
    # sempre retornamos todo o inventário compartilhado (incluindo owner_id, para
    # o cliente saber quem é o dono de cada item).
    result = await db.execute(
        select(CloudSupplyItem).where(CloudSupplyItem.device_id == SHARED_SCOPE)
    )
    return result.scalars().all()


@router.post("/sync", response_model=SupplySyncOut, dependencies=[Depends(verify_secret)])
async def sync_supply_items(
    data: SupplySyncIn,
    db: AsyncSession = Depends(get_db),
    admin: bool = Depends(is_admin),
):
    # Upsert por item dentro do escopo compartilhado. NÃO apaga itens ausentes do
    # payload (não destrutivo).
    #
    # Autorização por item (NÃO 403 no lote inteiro, pois /sync é um batch):
    #  - INSERT (item novo): o dono (owner_id) passa a ser o device_id que está agindo.
    #  - UPDATE (item existente): permitido só se o device for o dono OU admin;
    #    caso contrário o item é IGNORADO e seu item_id entra em `forbidden`.
    acting_device_id = data.device_id
    synced = 0
    forbidden: list[str] = []

    for item in data.items:
        result = await db.execute(
            select(CloudSupplyItem).where(
                CloudSupplyItem.device_id == SHARED_SCOPE,
                CloudSupplyItem.item_id == item.item_id,
            )
        )
        existing = result.scalars().first()

        if existing:
            if not _can_modify(existing, acting_device_id, admin):
                forbidden.append(item.item_id)
                continue
            existing.title = item.title
            existing.description = item.description or ""
            existing.quantity = item.quantity
            existing.is_bought = item.is_bought
            existing.updated_at = datetime.utcnow()
            synced += 1
        else:
            db.add(
                CloudSupplyItem(
                    device_id=SHARED_SCOPE,
                    item_id=item.item_id,
                    owner_id=acting_device_id,
                    title=item.title,
                    description=item.description or "",
                    quantity=item.quantity,
                    is_bought=item.is_bought,
                )
            )
            synced += 1

    await db.commit()
    return SupplySyncOut(synced=synced, forbidden=forbidden)


@router.delete("/items/{item_id}", dependencies=[Depends(verify_secret)])
async def delete_supply_item(
    item_id: str,
    device_id: str,
    db: AsyncSession = Depends(get_db),
    admin: bool = Depends(is_admin),
):
    # device_id = dispositivo que está agindo (para autorização). A remoção é no
    # inventário compartilhado (vale para todos), mas só é permitida ao dono do
    # item ou a um admin; caso contrário retorna 403.
    result = await db.execute(
        select(CloudSupplyItem).where(
            CloudSupplyItem.item_id == item_id,
            CloudSupplyItem.device_id == SHARED_SCOPE,
        )
    )
    item = result.scalars().first()
    if not item:
        raise HTTPException(status_code=404, detail="Item não encontrado")

    if not _can_modify(item, device_id, admin):
        raise HTTPException(
            status_code=403,
            detail="Apenas o criador do item ou um administrador pode excluí-lo.",
        )

    await db.delete(item)
    await db.commit()
    return {"deleted": True}


@router.post("/admin/verify", dependencies=[Depends(verify_secret)])
async def verify_admin(admin: bool = Depends(is_admin)):
    # Permite ao cliente confirmar o código de admin antes de armazená-lo.
    # Retorna 200 {"admin": true} quando o header x-admin-code confere; senão 403.
    if not admin:
        raise HTTPException(status_code=403, detail="Código de administrador inválido.")
    return {"admin": True}
