from datetime import datetime
from pydantic import BaseModel
from typing import Optional, List


class SupplyItemIn(BaseModel):
    item_id: str
    title: str
    description: Optional[str] = ""
    quantity: float = 1.0
    is_bought: bool = False


class SupplyItemOut(BaseModel):
    id: int
    item_id: str
    title: str
    description: str
    quantity: float
    is_bought: bool
    updated_at: datetime

    class Config:
        from_attributes = True


class SupplySyncIn(BaseModel):
    device_id: str
    items: List[SupplyItemIn]

