from datetime import datetime
from pydantic import BaseModel
from typing import Optional, List


class SupplyItemIn(BaseModel):
    item_id: str
    title: str
    description: Optional[str] = ""
    quantity: float = 1.0
    is_bought: bool = False
    # Observação: owner_id NÃO é aceito do cliente. O dono é derivado no servidor
    # a partir do device_id que está agindo (SupplySyncIn.device_id), para que
    # um cliente não consiga forjar a posse de um item.


class SupplyItemOut(BaseModel):
    id: int
    item_id: str
    title: str
    description: str
    quantity: float
    is_bought: bool
    owner_id: Optional[str] = None
    updated_at: datetime

    class Config:
        from_attributes = True


class SupplySyncIn(BaseModel):
    # device_id = dispositivo que está agindo (usado para posse/autorização,
    # NÃO para escopo — o escopo é sempre o inventário compartilhado).
    device_id: str
    items: List[SupplyItemIn]


class SupplySyncOut(BaseModel):
    # synced: quantos itens foram inseridos/atualizados com sucesso.
    # forbidden: item_ids rejeitados por autorização (tentativa de alterar item
    # de outro dono sem ser admin). O cliente deve parar de reenviá-los.
    synced: int
    forbidden: List[str] = []
