from datetime import datetime
from sqlalchemy import Column, DateTime, Float, Integer, JSON, String
from app.core.database import Base


class PrinterTelemetry(Base):
    __tablename__ = "telemetry_logs"

    id = Column(Integer, primary_key=True, index=True)
    printer_id = Column(String, index=True, nullable=False)
    state = Column(String, default="standby")
    progress = Column(Float, default=0.0)
    current_file = Column(String, nullable=True)
    nozzle_temp = Column(Float, default=0.0)
    bed_temp = Column(Float, default=0.0)
    filament_info = Column(JSON, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, index=True)


class CloudPrintJob(Base):
    __tablename__ = "cloud_print_jobs"

    id = Column(Integer, primary_key=True, index=True)
    printer_id = Column(String, index=True, nullable=False)
    filename = Column(String, nullable=False)
    status = Column(String, default="completed")  # completed, cancelled, error
    print_duration_seconds = Column(Float, default=0.0)
    filament_used_grams = Column(Float, default=0.0)
    filament_material = Column(String, nullable=True)
    filament_color = Column(String, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
