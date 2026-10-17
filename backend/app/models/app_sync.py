from datetime import datetime
from sqlalchemy import Column, DateTime, Float, Integer, String, Text, JSON


from app.core.database import Base


class AppSync(Base):
    """Modelo para dados e sincronização do app Flutter"""

    __tablename__ = "app_sync"

    id = Column(Integer, primary_key=True, index=True)
    device_id = Column(String(200), nullable=False, index=True)
    printer_id = Column(String(200), nullable=False, index=True)
    sync_type = Column(String(50), nullable=False)  # telemetry, job, config, supply_update
    payload = Column(JSON, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
