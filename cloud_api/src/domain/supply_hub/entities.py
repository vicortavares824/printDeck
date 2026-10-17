from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum


class StockUnit(str, Enum):
    UNIT = "un"
    KG = "kg"
    GRAMS = "g"
    LITERS = "L"
    METERS = "m"
    ROLL = "rolo"
    BOX = "caixa"


@dataclass
class SupplyItem:
    id: int | None
    name: str
    description: str | None
    sku: str | None
    unit: StockUnit
    quantity: float
    min_quantity: float  # alert threshold
    unit_cost: float | None
    supplier: str | None
    location: str | None  # physical storage location
    is_active: bool = True
    created_at: datetime = field(default_factory=datetime.utcnow)
    updated_at: datetime = field(default_factory=datetime.utcnow)

    @property
    def is_low_stock(self) -> bool:
        return self.quantity <= self.min_quantity


@dataclass
class StockMovement:
    id: int | None
    supply_item_id: int
    quantity_delta: float  # positive = entry, negative = exit
    reason: str
    user_id: int | None
    created_at: datetime = field(default_factory=datetime.utcnow)
