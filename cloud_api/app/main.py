from contextlib import asynccontextmanager
from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select

from app.core.config import settings
from app.core.database import Base, engine, get_db
from app.models.telemetry import CloudPrintJob, PrinterTelemetry
from app.schemas.telemetry import CloudJobIn, CloudJobOut, TelemetryIn, TelemetryOut


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Cria as tabelas automaticamente (funciona tanto no SQLite quanto no PostgreSQL do Render)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield


app = FastAPI(
    title="PrintDeck Cloud API",
    description="API Online para recepção de telemetria, filamentos e jobs de impressoras 3D",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def verify_secret(x_api_key: str | None = Header(default=None)):
    if settings.API_SECRET_KEY and settings.API_SECRET_KEY != "disabled":
        if x_api_key != settings.API_SECRET_KEY:
            raise HTTPException(status_code=401, detail="Chave de API inválida ou ausente")


@app.get("/")
async def root():
    return {
        "service": "PrintDeck Cloud API",
        "docs": "/docs",
        "status": "online",
    }


@app.post("/api/telemetry", response_model=TelemetryOut, dependencies=[Depends(verify_secret)])
async def receive_telemetry(data: TelemetryIn, db: AsyncSession = Depends(get_db)):
    """
    Recebe o estado em tempo real da impressora enviado pelo backend local / script
    """
    entry = PrinterTelemetry(
        printer_id=data.printer_id,
        state=data.state,
        progress=data.progress,
        current_file=data.current_file,
        nozzle_temp=data.nozzle_temp,
        bed_temp=data.bed_temp,
        filament_info=data.filament.model_dump() if data.filament else None,
    )
    db.add(entry)
    await db.commit()
    await db.refresh(entry)
    return entry


@app.get("/api/telemetry/latest/{printer_id}", response_model=TelemetryOut)
async def get_latest_telemetry(printer_id: str, db: AsyncSession = Depends(get_db)):
    """
    Retorna o último estado registrado de uma impressora
    """
    query = (
        select(PrinterTelemetry)
        .where(PrinterTelemetry.printer_id == printer_id)
        .order_by(PrinterTelemetry.created_at.desc())
        .limit(1)
    )
    result = await db.execute(query)
    telemetry = result.scalars().first()
    if not telemetry:
        raise HTTPException(status_code=404, detail="Nenhum dado encontrado para esta impressora")
    return telemetry


@app.post("/api/jobs", response_model=CloudJobOut, dependencies=[Depends(verify_secret)])
async def record_finished_job(job: CloudJobIn, db: AsyncSession = Depends(get_db)):
    """
    Registra um histórico de impressão concluída ou cancelada com os gastos de filamento
    """
    new_job = CloudPrintJob(
        printer_id=job.printer_id,
        filename=job.filename,
        status=job.status,
        print_duration_seconds=job.print_duration_seconds,
        filament_used_grams=job.filament_used_grams,
        filament_material=job.filament_material,
        filament_color=job.filament_color,
    )
    db.add(new_job)
    await db.commit()
    await db.refresh(new_job)
    return new_job


@app.get("/api/jobs/{printer_id}", response_model=list[CloudJobOut])
async def list_printer_jobs(printer_id: str, db: AsyncSession = Depends(get_db)):
    """
    Lista todos os trabalhos registrados para uma impressora
    """
    query = (
        select(CloudPrintJob)
        .where(CloudPrintJob.printer_id == printer_id)
        .order_by(CloudPrintJob.created_at.desc())
    )
    result = await db.execute(query)
    return result.scalars().all()
