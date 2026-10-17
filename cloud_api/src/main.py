"""
PrintDeck Cloud API - Ponto de Entrada Principal
================================================
Arquitetura: Clean Architecture / DDD Pragmático
Deploy target: Render (PostgreSQL + Uvicorn)
"""
import logging
import os
from contextlib import asynccontextmanager
from typing import AsyncGenerator

from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from starlette.exceptions import HTTPException as StarletteHTTPException

from src.infrastructure.config import settings
from src.infrastructure.database.connection import Base, engine

# Import all models so SQLAlchemy registers them before create_all
import src.infrastructure.database.models  # noqa: F401

from src.presentation.routers import (
    auth_router,
    category_router,
    organization_router,
    report_router,
    supply_hub_router,
    transaction_router,
)
from src.presentation.middlewares.error_handler import (
    generic_exception_handler,
    http_exception_handler,
    validation_exception_handler,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Cria tabelas automaticamente ao iniciar (funciona em SQLite e PostgreSQL)."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    logger.info("Banco de dados inicializado com sucesso.")
    yield
    logger.info("Encerrando aplicação.")


app = FastAPI(
    title="PrintDeck Cloud API",
    description=(
        "API REST centralizada da plataforma PrintDeck.\n\n"
        "**Módulos:** Auth, Organizations, Categories, Transactions, Reports, Supply Hub (Almoxarifado).\n\n"
        "**Nota:** Endpoints do `/api/supply-hub/items` são públicos (sem autenticação)."
    ),
    version="2.0.0",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
)

# ── CORS ─────────────────────────────────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Exception handlers ───────────────────────────────────────────
app.add_exception_handler(StarletteHTTPException, http_exception_handler)
app.add_exception_handler(RequestValidationError, validation_exception_handler)
app.add_exception_handler(Exception, generic_exception_handler)

# ── Routers (prefixed with /api) ─────────────────────────────────
API_PREFIX = "/api"

app.include_router(auth_router.router, prefix=API_PREFIX)
app.include_router(organization_router.router, prefix=API_PREFIX)
app.include_router(category_router.router, prefix=API_PREFIX)
app.include_router(transaction_router.router, prefix=API_PREFIX)
app.include_router(report_router.router, prefix=API_PREFIX)
app.include_router(supply_hub_router.router, prefix=API_PREFIX)


# ── Health check ─────────────────────────────────────────────────
@app.get("/", tags=["Health"])
async def health_check() -> dict:
    return {
        "service": "PrintDeck Cloud API",
        "version": "2.0.0",
        "status": "online",
        "docs": "/docs",
    }


@app.get("/api/health", tags=["Health"])
async def api_health() -> dict:
    return {"status": "ok"}
