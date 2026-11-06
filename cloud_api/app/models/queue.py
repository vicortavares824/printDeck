from datetime import datetime
from sqlalchemy import Column, DateTime, Integer, String
from app.core.database import Base


class PrintQueueItem(Base):
    __tablename__ = "print_queue_items"

    id = Column(Integer, primary_key=True, index=True)
    # printer_id é tratado logicamente como texto (Req 13.21): a fila opera mesmo
    # que o printer_id não exista em telemetry_logs. Indexado para leitura por fila.
    printer_id = Column(String, index=True, nullable=False)
    sku = Column(String, nullable=False)          # texto livre não vazio (Req 13.7)
    name = Column(String, nullable=False, default="")
    # position é única/contígua (1..n) dentro da mesma Print_Queue (Req 13.22); o
    # item de menor position é o próximo a imprimir.
    position = Column(Integer, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    created_by = Column(String, nullable=True)    # e-mail de quem adicionou
