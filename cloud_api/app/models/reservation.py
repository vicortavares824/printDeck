from datetime import datetime
from sqlalchemy import Boolean, Column, DateTime, String
from app.core.database import Base


class PrinterReservation(Base):
    # Uma linha por impressora (Req 11.5). A reserva fica numa tabela separada,
    # e não em telemetry_logs, porque cada printer_id tem muitas linhas de
    # telemetria; manter o estado de reserva aqui evita replicar/atualizar a
    # reserva a cada inserção de telemetria.
    __tablename__ = "printer_reservations"

    # printer_id é o identificador lógico único da impressora (chave primária).
    printer_id = Column(String, primary_key=True, index=True)
    reserved = Column(Boolean, nullable=False, default=False)
    # e-mail do Authenticated_User que ocupou a impressora (nulo quando livre).
    reserved_by = Column(String, nullable=True)
    reserved_at = Column(DateTime, nullable=True)
