from datetime import datetime
from pydantic import BaseModel


class QueueAddIn(BaseModel):
    sku: str                          # vazio => 422 (Req 13.7)
    name: str = ""
    # email do token tem precedência quando disponível (Req 13.5); o corpo é fallback.
    created_by: str | None = None


class QueueReorderIn(BaseModel):
    # conjunto de ids deve bater exatamente com a fila atual, senão 422 (Req 13.15).
    ordered_ids: list[int]


class QueueItemOut(BaseModel):
    id: int
    printer_id: str
    sku: str
    name: str
    position: int
    created_at: datetime
    created_by: str | None

    class Config:
        from_attributes = True
