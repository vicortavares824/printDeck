from datetime import datetime
from pydantic import BaseModel, Field
from src.domain.supply_hub.entities import StockUnit


# ── Requests ────────────────────────────────────────────────────
class CreateSupplyItemRequest(BaseModel):
    name: str = Field(..., min_length=2, max_length=200)
    description: str | None = None
    sku: str | None = Field(default=None, max_length=100)
    unit: StockUnit = StockUnit.UNIT
    quantity: float = Field(default=0.0, ge=0)
    min_quantity: float = Field(default=0.0, ge=0)
    unit_cost: float | None = Field(default=None, gt=0)
    supplier: str | None = None
    location: str | None = None


class StockMovementRequest(BaseModel):
    quantity_delta: float = Field(..., description="Positivo para entrada, negativo para saída")
    reason: str = Field(..., min_length=3, max_length=300)


# ── Responses ───────────────────────────────────────────────────
class SupplyItemResponse(BaseModel):
    id: int
    name: str
    description: str | None
    sku: str | None
    unit: StockUnit
    quantity: float
    min_quantity: float
    unit_cost: float | None
    supplier: str | None
    location: str | None
    is_active: bool
    is_low_stock: bool
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class StockMovementResponse(BaseModel):
    id: int
    supply_item_id: int
    quantity_delta: float
    reason: str
    user_id: int | None
    created_at: datetime

    model_config = {"from_attributes": True}
