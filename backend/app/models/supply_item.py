from datetime import datetime
from sqlalchemy import Column, DateTime, Float, Integer, String, Text, Boolean


from app.core.database import Base


class SupplyItem(Base):
    """Modelo da tabela de Insumos do Almoxarifado (SupplyHub)"""

    __tablename__ = "supply_items"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(200), nullable=False, index=True)
    description = Column(Text, nullable=True)
    category = Column(String(100), nullable=True, index=True)
    sku = Column(String(100), nullable=True, unique=True, index=True)
    quantity = Column(Integer, default=0, nullable=False)
    min_stock = Column(Integer, default=0, nullable=False)
    unit = Column(String(50), default="unidade", nullable=False)
    location = Column(String(100), nullable=True)
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
