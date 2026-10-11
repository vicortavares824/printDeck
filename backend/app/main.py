from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.database import Base, engine
from app.routers.printer import router as printer_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Cria as tabelas no SQLite automaticamente ao iniciar o app
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield


app = FastAPI(
    title="PrintDeck API",
    description="Backend integrador para Klipper/Moonraker e Spoolman com SQLite",
    version="1.0.0",
    lifespan=lifespan,
)

# Habilitar CORS para permitir requisições do Flutter e navegadores
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(printer_router)


@app.get("/")
async def root():
    return {
        "app": "PrintDeck API",
        "docs": "/docs",
        "status": "online",
    }
