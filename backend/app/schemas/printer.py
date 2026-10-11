from datetime import datetime
from pydantic import BaseModel


class PrinterStatusResponse(BaseModel):
    state: str
    message: str | None = None
    filename: str | None = None
    progress: float = 0.0
    print_duration: float = 0.0
    filament_used: float = 0.0
    extruder_temp: float = 0.0
    extruder_target: float = 0.0
    bed_temp: float = 0.0
    bed_target: float = 0.0


class GCodeFileItem(BaseModel):
    path: str
    size: int
    modified: float | None = None
    estimated_time: float | None = None
    filament_total: float | None = None


class SpoolItem(BaseModel):
    id: int
    filament_name: str | None = None
    material: str | None = None
    vendor_name: str | None = None
    remaining_weight: float | None = None
    initial_weight: float | None = None
    color_hex: str | None = None


class PrintJobCreate(BaseModel):
    filename: str
    spool_id: int | None = None


class PrintJobResponse(BaseModel):
    id: int
    filename: str
    status: str
    print_duration_seconds: float
    filament_used_mm: float
    filament_used_grams: float
    spool_id: int | None = None
    created_at: datetime
    completed_at: datetime | None = None

    class Config:
        from_attributes = True
