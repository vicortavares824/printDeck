from datetime import datetime
from pydantic import BaseModel


class FilamentData(BaseModel):
    spool_id: int | None = None
    material: str | None = None
    color: str | None = None
    vendor: str | None = None
    remaining_weight_grams: float | None = None
    used_in_this_print_grams: float | None = None


class TelemetryIn(BaseModel):
    printer_id: str
    state: str
    progress: float = 0.0
    current_file: str | None = None
    nozzle_temp: float = 0.0
    bed_temp: float = 0.0
    filament: FilamentData | None = None


class TelemetryOut(BaseModel):
    id: int
    printer_id: str
    state: str
    progress: float
    current_file: str | None
    nozzle_temp: float
    bed_temp: float
    filament_info: dict | None
    created_at: datetime

    class Config:
        from_attributes = True


class CloudJobIn(BaseModel):
    printer_id: str
    filename: str
    status: str
    print_duration_seconds: float = 0.0
    filament_used_grams: float = 0.0
    filament_material: str | None = None
    filament_color: str | None = None


class CloudJobOut(CloudJobIn):
    id: int
    created_at: datetime

    class Config:
        from_attributes = True
