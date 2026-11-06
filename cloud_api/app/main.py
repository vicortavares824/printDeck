import json
import logging
from contextlib import asynccontextmanager
from datetime import datetime
from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import exists, func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select

from app.core.auth import Identity, require_auth
from app.core.config import settings
from app.core.database import Base, engine, get_db
from app.models.reservation import PrinterReservation
from app.models.queue import PrintQueueItem  # noqa: F401  (registra print_queue_items na metadata)
from app.models.telemetry import CloudPrintJob, PrinterTelemetry
from app.schemas.reservation import ReservationOut, ReserveIn
from app.schemas.telemetry import (
    CloudJobIn,
    CloudJobOut,
    PrinterOut,
    TelemetryIn,
    TelemetryOut,
)
from app.routers import supply as supply_router
from app.routers import queue as queue_router


def utcnow() -> datetime:
    # Horario de registro da reserva (Req 11.3), sem timezone — coerente com
    # created_at/reserved_at persistidos como datetime.utcnow() no restante da
    # Cloud_API. O cliente interpreta como UTC ao calcular staleness.
    return datetime.utcnow()


logger = logging.getLogger("printdeck.cloud_api")


def _init_firebase_admin() -> None:
    # Inicializa o app firebase-admin a partir da service account inline em
    # FIREBASE_SERVICE_ACCOUNT_JSON (coerente com o Render, que nao tem keyfile
    # persistente). Degradacao segura (Req 18.7, 18.8): quando a credencial esta
    # ausente, NAO inicializamos o firebase-admin e logamos a condicao uma unica
    # vez no startup — a validacao de Firebase_ID_Token passa a falhar sempre e
    # somente a x-api-key autoriza. Qualquer falha de inicializacao tambem e
    # logada sem derrubar o boot.
    raw = (settings.FIREBASE_SERVICE_ACCOUNT_JSON or "").strip()
    if not raw:
        logger.warning(
            "FIREBASE_SERVICE_ACCOUNT_JSON ausente: firebase-admin nao sera "
            "inicializado; validacao de Firebase_ID_Token desativada, apenas "
            "x-api-key autoriza (degradacao segura)."
        )
        return

    try:
        import firebase_admin
        from firebase_admin import credentials

        # Idempotente: nao reinicializa se o app padrao ja existe.
        if firebase_admin._apps:
            return

        service_account = json.loads(raw)
        cred = credentials.Certificate(service_account)
        firebase_admin.initialize_app(cred)
        logger.info("firebase-admin inicializado a partir da service account.")
    except Exception as exc:  # pragma: no cover - log defensivo de boot
        # Credencial invalida/malformada ou falha do SDK: nao derruba o boot.
        # A validacao de token continua falhando (so x-api-key autoriza).
        logger.warning(
            "Falha ao inicializar o firebase-admin (%s): validacao de "
            "Firebase_ID_Token desativada, apenas x-api-key autoriza.",
            exc,
        )


async def _ensure_supply_schema(conn):
    # Auto-migracao idempotente: garante que a coluna owner_id exista em
    # cloud_supply_items. create_all cria tabelas novas, mas NAO faz ALTER em
    # tabelas que ja existem — entao um banco criado antes do controle de posse
    # ficaria sem a coluna e o GET /api/supply/items quebraria (500). Rodamos o
    # ADD COLUMN de forma segura em cada startup.
    dialect = conn.dialect.name
    try:
        if dialect == "postgresql":
            await conn.exec_driver_sql(
                "ALTER TABLE cloud_supply_items ADD COLUMN IF NOT EXISTS owner_id VARCHAR"
            )
        elif dialect == "sqlite":
            rows = await conn.exec_driver_sql("PRAGMA table_info(cloud_supply_items)")
            cols = [r[1] for r in rows.fetchall()]
            if "owner_id" not in cols:
                await conn.exec_driver_sql(
                    "ALTER TABLE cloud_supply_items ADD COLUMN owner_id VARCHAR"
                )
        else:
            await conn.exec_driver_sql(
                "ALTER TABLE cloud_supply_items ADD COLUMN owner_id VARCHAR"
            )
    except Exception:
        # Coluna ja existe ou ajuste concorrente — seguimos sem falhar o boot.
        pass


async def _ensure_telemetry_schema(conn):
    # Auto-migracao idempotente: garante que a coluna model exista em
    # telemetry_logs. create_all cria tabelas novas, mas NAO faz ALTER em
    # tabelas que ja existem — entao um banco criado antes do campo model
    # ficaria sem a coluna. Rodamos o ADD COLUMN de forma segura em cada
    # startup (Req 9.2, 9.3). Qualquer falha e logada e o boot segue (Req 9.11).
    dialect = conn.dialect.name
    try:
        if dialect == "postgresql":
            await conn.exec_driver_sql(
                "ALTER TABLE telemetry_logs ADD COLUMN IF NOT EXISTS model VARCHAR"
            )
        elif dialect == "sqlite":
            rows = await conn.exec_driver_sql("PRAGMA table_info(telemetry_logs)")
            cols = [r[1] for r in rows.fetchall()]
            if "model" not in cols:
                await conn.exec_driver_sql(
                    "ALTER TABLE telemetry_logs ADD COLUMN model VARCHAR"
                )
        else:
            await conn.exec_driver_sql(
                "ALTER TABLE telemetry_logs ADD COLUMN model VARCHAR"
            )
    except Exception as exc:
        # Coluna ja existe ou ajuste concorrente — logamos e seguimos o boot.
        logger.warning("Falha ao migrar coluna model; seguindo o boot (%s)", exc)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Inicializa o firebase-admin (ou degrada com seguranca quando a credencial
    # da service account estiver ausente). Uma unica vez no startup.
    _init_firebase_admin()
    # Cria as tabelas automaticamente (funciona tanto no SQLite quanto no PostgreSQL do Render)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await _ensure_supply_schema(conn)
        await _ensure_telemetry_schema(conn)
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

app.include_router(supply_router.router)
app.include_router(queue_router.router)


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
        model=data.model,
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


@app.get("/api/printers", response_model=list[PrinterOut])
async def list_printers(db: AsyncSession = Depends(get_db)):
    """
    Printer_List_Endpoint (Req 1): lista publica (sem require_auth, Req 1.10) com
    um item por printer_id distinto, contendo o Telemetry_Record mais recente da
    impressora (Req 1.2, 1.4) mesclado com o Reservation_State (Req 1.7, 1.8).

    Selecao do mais recente (Req 1.3) compativel com SQLite e PostgreSQL (sem
    window functions/DISTINCT ON): subquery de agregacao max(created_at) por
    printer_id e desempate por max(id). Ordenacao desc por created_at (Req 1.2).

    Lista vazia -> [] com 200 (Req 1.9). Falha de DB -> HTTPException(500) sem
    qualquer escrita (Req 1.11).
    """
    try:
        # (1) Maior created_at por printer_id.
        latest_ts = (
            select(
                PrinterTelemetry.printer_id.label("pid"),
                func.max(PrinterTelemetry.created_at).label("max_ts"),
            )
            .group_by(PrinterTelemetry.printer_id)
            .subquery()
        )
        # (2) Desempate por maior id entre as linhas que casam (printer_id, max_ts).
        latest_id = (
            select(func.max(PrinterTelemetry.id).label("max_id"))
            .join(
                latest_ts,
                (PrinterTelemetry.printer_id == latest_ts.c.pid)
                & (PrinterTelemetry.created_at == latest_ts.c.max_ts),
            )
            .group_by(PrinterTelemetry.printer_id)
            .scalar_subquery()
        )
        # (3) Linhas de telemetria vencedoras, ordenadas desc por created_at.
        query = (
            select(PrinterTelemetry)
            .where(PrinterTelemetry.id.in_(latest_id))
            .order_by(PrinterTelemetry.created_at.desc())
        )
        result = await db.execute(query)
        telemetries = result.scalars().all()

        if not telemetries:
            return []

        # (4) Carrega as reservas das impressoras presentes e indexa por printer_id.
        printer_ids = [t.printer_id for t in telemetries]
        reservations_result = await db.execute(
            select(PrinterReservation).where(
                PrinterReservation.printer_id.in_(printer_ids)
            )
        )
        reservations = {r.printer_id: r for r in reservations_result.scalars().all()}

        # (5) Merge: aplica default reserved=false/null quando nao ha reserva (Req 1.8).
        printers: list[PrinterOut] = []
        for t in telemetries:
            reservation = reservations.get(t.printer_id)
            printers.append(
                PrinterOut(
                    id=t.id,
                    printer_id=t.printer_id,
                    state=t.state,
                    progress=t.progress,
                    current_file=t.current_file,
                    nozzle_temp=t.nozzle_temp,
                    bed_temp=t.bed_temp,
                    filament_info=t.filament_info,
                    model=t.model,
                    created_at=t.created_at,
                    reserved=reservation.reserved if reservation else False,
                    reserved_by=reservation.reserved_by if reservation else None,
                    reserved_at=reservation.reserved_at if reservation else None,
                )
            )
        return printers
    except Exception as exc:
        # Falha de consulta ao banco: 500 sem alterar dados persistidos (Req 1.11).
        logger.warning("Falha ao listar impressoras: %s", exc)
        raise HTTPException(
            status_code=500,
            detail="Falha ao recuperar a lista de impressoras",
        )


@app.get("/api/telemetry/latest/{printer_id}", response_model=PrinterOut)
async def get_latest_telemetry(printer_id: str, db: AsyncSession = Depends(get_db)):
    """
    Retorna o ultimo estado registrado de uma impressora como PrinterOut
    (Req 9.7, 9.10): Telemetry_Record mais recente (com o campo model) mesclado
    com o Reservation_State da impressora.

    O merge da reserva segue o mesmo padrao do GET /api/printers: busca a linha
    em printer_reservations por printer_id e, quando nao ha reserva registrada,
    aplica os defaults da Req 1 (reserved=false, reserved_by=null,
    reserved_at=null).

    404 quando nao ha nenhum Telemetry_Record para o printer_id.
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

    # Merge do Reservation_State por printer_id (reutiliza o helper usado pelos
    # endpoints de reserva). Sem linha de reserva -> defaults da Req 1 (Req 9.10).
    reservation = await _get_reservation(db, printer_id)
    return PrinterOut(
        id=telemetry.id,
        printer_id=telemetry.printer_id,
        state=telemetry.state,
        progress=telemetry.progress,
        current_file=telemetry.current_file,
        nozzle_temp=telemetry.nozzle_temp,
        bed_temp=telemetry.bed_temp,
        filament_info=telemetry.filament_info,
        model=telemetry.model,
        created_at=telemetry.created_at,
        reserved=reservation.reserved if reservation else False,
        reserved_by=reservation.reserved_by if reservation else None,
        reserved_at=reservation.reserved_at if reservation else None,
    )


async def _printer_exists(db: AsyncSession, printer_id: str) -> bool:
    # A impressora so e "conhecida" quando ha ao menos um Telemetry_Record com
    # esse printer_id em telemetry_logs (Req 11.13). Usamos select(exists(...))
    # para nao materializar linhas.
    result = await db.execute(
        select(exists().where(PrinterTelemetry.printer_id == printer_id))
    )
    return bool(result.scalar())


async def _get_reservation(
    db: AsyncSession, printer_id: str
) -> PrinterReservation | None:
    result = await db.execute(
        select(PrinterReservation).where(
            PrinterReservation.printer_id == printer_id
        )
    )
    return result.scalars().first()


@app.post(
    "/api/printers/{printer_id}/reserve",
    response_model=ReservationOut,
    dependencies=[Depends(require_auth)],
)
async def reserve_printer(
    printer_id: str,
    body: ReserveIn,
    identity: Identity = Depends(require_auth),
    db: AsyncSession = Depends(get_db),
):
    """
    Ocupar (reservar) uma impressora (Req 11.1, 11.3, 11.8, 11.11).

    Autorizacao por require_auth (Req 11.7, 11.9): sem Firebase_ID_Token valido
    e sem x-api-key valida -> 401 sem efeito colateral.

    reserved_by efetivo = identity.email (claims do token) quando disponivel,
    senao o reserved_by do corpo (Req 11.8). Se ambos ausentes/vazios -> 422
    sem alterar o estado persistido (Req 11.10).

    printer_id inexistente em telemetry_logs -> 404 sem criar reserva (Req 11.13).
    Impressora ja reservada -> substitui os valores e responde 200 (Req 11.11).
    """
    # printer_id precisa existir em telemetry_logs (Req 11.13). Checado antes de
    # qualquer escrita para nao criar reserva orfa.
    if not await _printer_exists(db, printer_id):
        raise HTTPException(
            status_code=404,
            detail="Impressora inexistente (nenhum Telemetry_Record)",
        )

    # reserved_by: precedencia do email do token (Req 11.8); fallback ao corpo.
    body_reserved_by = (body.reserved_by or "").strip()
    effective_reserved_by = (identity.email or "").strip() or body_reserved_by
    if not effective_reserved_by:
        # Sem email no token e sem reserved_by no corpo -> 422 sem alterar estado
        # (Req 11.10).
        raise HTTPException(
            status_code=422,
            detail="reserved_by e obrigatorio quando o token nao traz email",
        )

    # Upsert: cria a linha se nao existe, senao substitui os valores (Req 11.11).
    reservation = await _get_reservation(db, printer_id)
    if reservation is None:
        reservation = PrinterReservation(printer_id=printer_id)
        db.add(reservation)
    reservation.reserved = True
    reservation.reserved_by = effective_reserved_by
    reservation.reserved_at = utcnow()

    await db.commit()
    await db.refresh(reservation)
    return reservation


@app.post(
    "/api/printers/{printer_id}/release",
    response_model=ReservationOut,
    dependencies=[Depends(require_auth)],
)
async def release_printer(
    printer_id: str,
    db: AsyncSession = Depends(get_db),
):
    """
    Liberar uma impressora (Req 11.2, 11.4, 11.12).

    Autorizacao por require_auth (Req 11.7, 11.9). printer_id inexistente em
    telemetry_logs -> 404 sem criar reserva (Req 11.13).

    Upsert com reserved=False, reserved_by=None, reserved_at=None. Liberar uma
    impressora que nao esta reservada mantem o estado nao reservado e responde
    200 (Req 11.12).
    """
    if not await _printer_exists(db, printer_id):
        raise HTTPException(
            status_code=404,
            detail="Impressora inexistente (nenhum Telemetry_Record)",
        )

    reservation = await _get_reservation(db, printer_id)
    if reservation is None:
        # Nunca reservada: cria a linha ja no estado liberado (Req 11.12).
        reservation = PrinterReservation(printer_id=printer_id)
        db.add(reservation)
    reservation.reserved = False
    reservation.reserved_by = None
    reservation.reserved_at = None

    await db.commit()
    await db.refresh(reservation)
    return reservation


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
