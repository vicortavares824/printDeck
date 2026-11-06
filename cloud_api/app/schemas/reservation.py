from datetime import datetime
from pydantic import BaseModel


class ReserveIn(BaseModel):
    # reserved_by é compat: o e-mail das claims do token tem precedência (Req 11.8).
    reserved_by: str | None = None


class ReservationOut(BaseModel):
    printer_id: str
    reserved: bool
    reserved_by: str | None
    reserved_at: datetime | None

    class Config:
        from_attributes = True
