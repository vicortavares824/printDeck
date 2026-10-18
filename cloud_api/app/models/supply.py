from datetime import datetime
from sqlalchemy import Column, DateTime, Float, Integer, Boolean, String
from app.core.database import Base


class CloudSupplyItem(Base):
    __tablename__ = "cloud_supply_items"

    id = Column(Integer, primary_key=True, index=True)
    device_id = Column(String, index=True, nullable=False)
    item_id = Column(String, index=True, nullable=False)
    title = Column(String, nullable=False)
    description = Column(String, nullable=True, default="")
    quantity = Column(Float, default=1.0)
    is_bought = Column(Boolean, default=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
