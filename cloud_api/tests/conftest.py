"""Fixtures compartilhadas dos testes da Cloud_API.

Cada teste roda contra um banco SQLite isolado em arquivo temporário e um
cliente ASGI em memória (sem subir rede). O schema é criado via
Base.metadata.create_all, coerente com o lifespan do app.
"""
import os
import tempfile

import pytest

# Configura um banco isolado e desliga a x-api-key ANTES de importar o app, pois
# o engine é criado no import a partir de settings.async_database_url.
_TMP_DB = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
_TMP_DB.close()
os.environ["DATABASE_URL"] = f"sqlite+aiosqlite:///{_TMP_DB.name}"
os.environ.setdefault("API_SECRET_KEY", "disabled")

import httpx  # noqa: E402

from app.core.database import AsyncSessionLocal, Base, engine  # noqa: E402
from app.main import app  # noqa: E402


@pytest.fixture
async def db_session():
    """(Re)cria o schema a cada teste e entrega uma sessão para semear dados."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    async with AsyncSessionLocal() as session:
        yield session


@pytest.fixture
async def client():
    """Cliente HTTP assíncrono falando direto com o app via ASGITransport."""
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as c:
        yield c


def pytest_sessionfinish(session, exitstatus):
    try:
        os.unlink(_TMP_DB.name)
    except OSError:
        pass
