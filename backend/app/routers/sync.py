from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException, Header
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc

from app.core.database import get_db
from app.core.config import settings
from app.models.app_sync import AppSync
from app.schemas.sync import (
    AppSyncCreate,
    AppSyncResponse,
    TelemetryIn,
    TelemetryOut,
)

router = APIRouter(prefix="/api/sync", tags=["App Sync & Telemetry"])


def verify_write_key(x_api_key: Optional[str] = Header(default=None)):
    if settings.CLOUD_API_KEY and settings.CLOUD_API_KEY != "disabled":
        if x_api_key != settings.CLOUD_API_KEY:
            raise HTTPException(status_code=401, detail="Chave de API inválida ou ausente")


@router.post("/telemetry", response_model=TelemetryOut, dependencies=[Depends(verify_write_key)])
async def receive_telemetry(data: TelemetryIn, db: AsyncSession = Depends(get_db)):
    """
    Recebe telemetria em tempo real do app Flutter/backend local.
    """
    entry = AppSync(
        device_id=data.printer_id,
        printer_id=data.printer_id,
        sync_type="telemetry",
        payload={
            "state": data.state,
            "progress": data.progress,
            "current_file": data.current_file,
            "nozzle_temp": data.nozzle_temp,
            "bed_temp": data.bed_temp,
            "filament": data.filament,
        },
    )
    db.add(entry)
    await db.commit()
    await db.refresh(entry)

    return TelemetryOut(
        id=entry.id,
        printer_id=entry.printer_id,
        state=entry.payload.get("state", ""),
        progress=entry.payload.get("progress", 0.0),
        current_file=entry.payload.get("current_file"),
        nozzle_temp=entry.payload.get("nozzle_temp", 0.0),
        bed_temp=entry.payload.get("bed_temp", 0.0),
        filament_info=entry.payload.get("filament"),
        created_at=entry.created_at,
    )


@router.get("/telemetry/latest/{printer_id}", response_model=TelemetryOut)
async def get_latest_telemetry(printer_id: str, db: AsyncSession = Depends(get_db)):
    """
    Retorna o último estado de telemetria de uma impressora (acesso público).
    """
    result = await db.execute(
        select(AppSync)
        .where(AppSync.printer_id == printer_id, AppSync.sync_type == "telemetry")
        .order_by(desc(AppSync.created_at))
        .limit(1)
    )
    entry = result.scalars().first()
    if not entry:
        raise HTTPException(status_code=404, detail="Nenhum dado de telemetria encontrado")
    return TelemetryOut(
        id=entry.id,
        printer_id=entry.printer_id,
        state=entry.payload.get("state", ""),
        progress=entry.payload.get("progress", 0.0),
        current_file=entry.payload.get("current_file"),
        nozzle_temp=entry.payload.get("nozzle_temp", 0.0),
        bed_temp=entry.payload.get("bed_temp", 0.0),
        filament_info=entry.payload.get("filament"),
        created_at=entry.created_at,
    )


@router.post("/", response_model=AppSyncResponse, dependencies=[Depends(verify_write_key)])
async def create_app_sync(sync_data: AppSyncCreate, db: AsyncSession = Depends(get_db)):
    """
    Registra um evento de sincronização do app (requer autenticação).
    """
    entry = AppSync(**sync_data.model_dump())
    db.add(entry)
    await db.commit()
    await db.refresh(entry)
    return entry


@router.get("/", response_model=List[AppSyncResponse], dependencies=[Depends(verify_write_key)])
async def list_app_syncs(
    db: AsyncSession = Depends(get_db),
    printer_id: Optional[str] = None,
    sync_type: Optional[str] = None,
    skip: int = 0,
    limit: int = 100,
):
    """
    Lista eventos de sincronização (requer autenticação).
    """
    query = select(AppSync)
    if printer_id:
        query = query.where(AppSync.printer_id == printer_id)
    if sync_type:
        query = query.where(AppSync.sync_type == sync_type)
    query = query.offset(skip).limit(limit).order_by(desc(AppSync.created_at))
    result = await db.execute(query)
    return result.scalars().all()
