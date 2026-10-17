from datetime import datetime
from pydantic import BaseModel, Field
from typing import Optional, Dict, Any


class AppSyncBase(BaseModel):
    device_id: str = Field(..., min_length=1, max_length=200)
    printer_id: str = Field(..., min_length=1, max_length=200)
    sync_type: str = Field(..., min_length=1, max_length=50)
    payload: Dict[str, Any]


class AppSyncCreate(AppSyncBase):
    pass


class AppSyncResponse(AppSyncBase):
    id: int
    created_at: datetime

    class Config:
        from_attributes = True


class TelemetryIn(BaseModel):
    printer_id: str
    state: str
    progress: float = 0.0
    current_file: Optional[str] = None
    nozzle_temp: float = 0.0
    bed_temp: float = 0.0
    filament: Optional[Dict[str, Any]] = None


class TelemetryOut(BaseModel):
    id: int
    printer_id: str
    state: str
    progress: float
    current_file: Optional[str]
    nozzle_temp: float
    bed_temp: float
    filament_info: Optional[dict]
    created_at: datetime

    class Config:
        from_attributes = True
