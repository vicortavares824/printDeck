from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.database import Base, engine
from app.routers.printer import router as printer_router
from app.routers.supplies import router as supplies_router
from app.routers.sync import router as sync_router

# Import all models so SQLAlchemy registers them before create_all
import app.models.printer  # noqa: F401
import app.models.supply_item  # noqa: F401
import app.models.app_sync  # noqa: F401


@asynccontextmanager
async def lifespan(app: FastAPI):
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield


app = FastAPI(
    title="PrintDeck API",
    description="Backend integrador para Klipper/Moonraker, Spoolman e SupplyHub com PostgreSQL",
    version="2.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(printer_router)
app.include_router(supplies_router)
app.include_router(sync_router)


@app.get("/")
async def root():
    return {
        "app": "PrintDeck API",
        "docs": "/docs",
        "status": "online",
        "modules": ["printer", "spoolman", "supply_hub", "sync"],
    }
