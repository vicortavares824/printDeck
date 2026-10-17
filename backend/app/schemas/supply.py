from datetime import datetime
from pydantic import BaseModel, Field
from typing import Optional


class SupplyItemBase(BaseModel):
    name: str = Field(..., min_length=1, max_length=200)
    description: Optional[str] = None
    category: Optional[str] = Field(None, max_length=100)
    sku: Optional[str] = Field(None, max_length=100)
    quantity: int = Field(default=0, ge=0)
    min_stock: int = Field(default=0, ge=0)
    unit: str = Field(default="unidade", max_length=50)
    location: Optional[str] = Field(None, max_length=100)
    is_active: bool = Field(default=True)


class SupplyItemCreate(SupplyItemBase):
    pass


class SupplyItemUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=200)
    description: Optional[str] = None
    category: Optional[str] = Field(None, max_length=100)
    sku: Optional[str] = Field(None, max_length=100)
    quantity: Optional[int] = Field(None, ge=0)
    min_stock: Optional[int] = Field(None, ge=0)
    unit: Optional[str] = Field(None, max_length=50)
    location: Optional[str] = Field(None, max_length=100)
    is_active: Optional[bool] = None


class SupplyItemResponse(SupplyItemBase):
    id: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class SupplyItemListResponse(BaseModel):
    items: list[SupplyItemResponse]
    total: int
