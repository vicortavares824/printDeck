from datetime import datetime
from sqlalchemy import Column, DateTime, Float, ForeignKey, Integer, String
from sqlalchemy.orm import relationship

from app.core.database import Base


class PrintJob(Base):
    __tablename__ = "print_jobs"

    id = Column(Integer, primary_key=True, index=True)
    filename = Column(String, nullable=False, index=True)
    status = Column(String, default="standby")  # printing, completed, cancelled, error
    print_duration_seconds = Column(Float, default=0.0)
    filament_used_mm = Column(Float, default=0.0)
    filament_used_grams = Column(Float, default=0.0)
    spool_id = Column(Integer, ForeignKey("spools.id"), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    completed_at = Column(DateTime, nullable=True)

    spool = relationship("SpoolRecord", back_populates="jobs")


class SpoolRecord(Base):
    """
    Registro / Cache local de carretéis do Spoolman para histórico
    """
    __tablename__ = "spools"

    id = Column(Integer, primary_key=True, index=True)
    spoolman_id = Column(Integer, unique=True, index=True, nullable=True)
    name = Column(String, nullable=True)
    material = Column(String, nullable=True)  # PLA, PETG, ABS, etc.
    color_hex = Column(String, nullable=True)
    vendor = Column(String, nullable=True)
    initial_weight_grams = Column(Float, default=1000.0)
    remaining_weight_grams = Column(Float, default=1000.0)

    jobs = relationship("PrintJob", back_populates="spool")
