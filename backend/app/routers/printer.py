from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select

from app.core.database import get_db
from app.models.printer import PrintJob, SpoolRecord
from app.schemas.printer import (
    GCodeFileItem,
    PrinterStatusResponse,
    PrintJobCreate,
    PrintJobResponse,
    SpoolItem,
)
from app.services.moonraker import moonraker_service
from app.services.spoolman import spoolman_service

router = APIRouter(prefix="/api", tags=["Printer & Spoolman"])


@router.get("/status", response_model=PrinterStatusResponse)
async def get_printer_status():
    """
    Retorna o status em tempo real da impressora (temperaturas, arquivo atual e progresso)
    """
    try:
        return await moonraker_service.get_printer_status()
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Erro ao comunicar com Moonraker: {e}")


@router.get("/files", response_model=list[GCodeFileItem])
async def list_files():
    """
    Lista todos os arquivos G-Code armazenados na impressora
    """
    try:
        return await moonraker_service.list_gcode_files()
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Erro ao listar arquivos do Moonraker: {e}")


@router.get("/spools", response_model=list[SpoolItem])
async def list_spools():
    """
    Lista todos os carretéis e filamentos cadastrados no Spoolman
    """
    try:
        return await spoolman_service.list_spools()
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Erro ao conectar com Spoolman: {e}")


@router.post("/jobs", response_model=PrintJobResponse)
async def create_print_job(job_data: PrintJobCreate, db: AsyncSession = Depends(get_db)):
    """
    Registra um novo trabalho de impressão no banco local vinculado a um carretel
    """
    new_job = PrintJob(
        filename=job_data.filename,
        spool_id=job_data.spool_id,
        status="printing",
    )
    db.add(new_job)
    await db.commit()
    await db.refresh(new_job)
    return new_job


@router.get("/jobs", response_model=list[PrintJobResponse])
async def list_print_jobs(db: AsyncSession = Depends(get_db)):
    """
    Histórico de impressões salvas no SQLite local
    """
    result = await db.execute(select(PrintJob).order_by(PrintJob.created_at.desc()))
    return result.scalars().all()


@router.post("/sync/spools")
async def sync_spools_to_db(db: AsyncSession = Depends(get_db)):
    """
    Sincroniza os carretéis do Spoolman diretamente no banco de dados SQLite local
    """
    try:
        spools = await spoolman_service.list_spools()
        count = 0
        for s in spools:
            stmt = select(SpoolRecord).where(SpoolRecord.spoolman_id == s["id"])
            res = await db.execute(stmt)
            existing = res.scalars().first()

            if not existing:
                record = SpoolRecord(
                    spoolman_id=s["id"],
                    name=s["filament_name"],
                    material=s["material"],
                    color_hex=s["color_hex"],
                    vendor=s["vendor_name"],
                    remaining_weight_grams=s["remaining_weight"] or 0.0,
                    initial_weight_grams=s["initial_weight"] or 1000.0,
                )
                db.add(record)
                count += 1
            else:
                existing.remaining_weight_grams = s["remaining_weight"] or existing.remaining_weight_grams

        await db.commit()
        return {"status": "success", "new_spools_synced": count}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erro na sincronização: {e}")


@router.post("/cloud/sync")
async def push_to_cloud():
    """
    Empacota o status atual e o filamento e despacha para a sua API hospedada no Render
    """
    from app.core.config import settings
    import httpx

    if not settings.CLOUD_API_URL:
        raise HTTPException(
            status_code=400,
            detail="CLOUD_API_URL não configurada no arquivo .env do backend local",
        )

    # 1. Pega telemetria do Moonraker
    status = await moonraker_service.get_printer_status()

    # 2. Tenta pegar primeiro carretel do Spoolman para compor o payload
    spools = []
    try:
        spools = await spoolman_service.list_spools()
    except Exception:
        pass

    active_spool = spools[0] if spools else {}

    payload = {
        "printer_id": settings.PRINTER_ID,
        "state": status.get("state", "unknown"),
        "progress": status.get("progress", 0.0),
        "current_file": status.get("filename"),
        "nozzle_temp": status.get("extruder_temp", 0.0),
        "bed_temp": status.get("bed_temp", 0.0),
        "filament": {
            "spool_id": active_spool.get("id"),
            "material": active_spool.get("material"),
            "color": active_spool.get("color_hex"),
            "vendor": active_spool.get("vendor_name"),
            "remaining_weight_grams": active_spool.get("remaining_weight"),
        } if active_spool else None,
    }

    url = f"{settings.CLOUD_API_URL.rstrip('/')}/api/telemetry"
    headers = {}
    if settings.CLOUD_API_KEY:
        headers["x-api-key"] = settings.CLOUD_API_KEY

    async with httpx.AsyncClient(timeout=10.0) as client:
        res = await client.post(url, json=payload, headers=headers)
        if res.status_code >= 400:
            raise HTTPException(
                status_code=res.status_code,
                detail=f"Falha ao enviar para o Render: {res.text}",
            )
        return {"status": "synced_successfully", "cloud_response": res.json()}

