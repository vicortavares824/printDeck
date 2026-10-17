from datetime import datetime
from pydantic import BaseModel, Field


class CreateCategoryRequest(BaseModel):
    name: str = Field(..., min_length=2, max_length=200)
    description: str | None = None


class CategoryResponse(BaseModel):
    id: int
    name: str
    description: str | None
    organization_id: int
    created_at: datetime

    model_config = {"from_attributes": True}
