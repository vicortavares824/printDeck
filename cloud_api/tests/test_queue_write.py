"""Testes das escritas add/remove da Print_Queue (tarefa 5.3 — Req 13.5-13.12).

POST   /api/printers/{printer_id}/queue           -> add ao FIM (Req 13.5-13.7)
DELETE /api/printers/{printer_id}/queue/{item_id} -> remove + reindexa (Req 13.10-13.12)

Ambos protegidos por require_auth (Req 13.8/13.9). Nos testes, API_SECRET_KEY é
"disabled" (ver conftest) e o firebase-admin não está inicializado, portanto
nenhuma autorização real é concedida. Para exercitar o caminho autorizado sem
subir o Firebase, sobrescrevemos a dependency `require_auth` via
`app.dependency_overrides` (fixtures `auth_token`/`auth_api_key`). Os testes de
401 NÃO usam esse override, validando que a escrita sem auth é rejeitada.
"""
import pytest

from app.core.auth import Identity, require_auth
from app.main import app
from app.models.queue import PrintQueueItem


@pytest.fixture
def auth_token():
    """Autoriza as escritas como se um Firebase_ID_Token trouxesse este e-mail."""
    app.dependency_overrides[require_auth] = lambda: Identity(
        email="token@x.com", uid="uid-1", via="firebase"
    )
    yield "token@x.com"
    app.dependency_overrides.pop(require_auth, None)


@pytest.fixture
def auth_api_key():
    """Autoriza as escritas como via x-api-key (sem e-mail no token)."""
    app.dependency_overrides[require_auth] = lambda: Identity(
        email=None, uid=None, via="api_key"
    )
    yield
    app.dependency_overrides.pop(require_auth, None)


# --- add (Req 13.5-13.7) ---------------------------------------------------
async def test_add_appends_to_end_of_queue(client, db_session, auth_api_key):
    # Fila com posições 1 e 2; o novo item deve ir para a posição 3 (Req 13.6).
    db_session.add_all(
        [
            PrintQueueItem(printer_id="p1", sku="A", name="a", position=1),
            PrintQueueItem(printer_id="p1", sku="B", name="b", position=2),
        ]
    )
    await db_session.commit()

    resp = await client.post(
        "/api/printers/p1/queue",
        json={"sku": "C", "name": "c", "created_by": "u@x.com"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["sku"] == "C"
    assert body["position"] == 3
    assert body["printer_id"] == "p1"
    # Sem email no token (via api_key), usa o created_by do corpo (Req 13.5).
    assert body["created_by"] == "u@x.com"

    # A fila completa reflete o novo item ao fim.
    listing = await client.get("/api/printers/p1/queue")
    assert [i["sku"] for i in listing.json()] == ["A", "B", "C"]
    assert [i["position"] for i in listing.json()] == [1, 2, 3]


async def test_add_uses_token_email_as_created_by(client, db_session, auth_token):
    # Req 13.5: o email das claims do token tem precedência sobre o corpo.
    resp = await client.post(
        "/api/printers/p1/queue",
        json={"sku": "A", "name": "a", "created_by": "body@x.com"},
    )
    assert resp.status_code == 200
    assert resp.json()["created_by"] == "token@x.com"


async def test_add_to_empty_queue_uses_position_one(client, db_session, auth_api_key):
    # Fila vazia => primeira posição é 1 (Req 13.6).
    resp = await client.post(
        "/api/printers/empty/queue",
        json={"sku": "ONLY", "name": "only"},
    )
    assert resp.status_code == 200
    assert resp.json()["position"] == 1


async def test_add_empty_sku_returns_422_and_does_not_persist(
    client, db_session, auth_api_key
):
    # sku vazio (após strip) => 422 sem persistir (Req 13.7).
    resp = await client.post(
        "/api/printers/p1/queue",
        json={"sku": "   ", "name": "x"},
    )
    assert resp.status_code == 422

    listing = await client.get("/api/printers/p1/queue")
    assert listing.json() == []


async def test_add_without_auth_returns_401(client, db_session):
    # Sem token válido nem x-api-key válida => 401 (Req 13.8/13.9). Sem override.
    resp = await client.post(
        "/api/printers/p1/queue",
        json={"sku": "A", "name": "a"},
        headers={"x-api-key": "whatever"},
    )
    assert resp.status_code == 401

    listing = await client.get("/api/printers/p1/queue")
    assert listing.json() == []


# --- remove (Req 13.10-13.12) ----------------------------------------------
async def test_remove_nonexistent_item_returns_404(client, db_session, auth_api_key):
    db_session.add(
        PrintQueueItem(printer_id="p1", sku="A", name="a", position=1)
    )
    await db_session.commit()

    resp = await client.delete("/api/printers/p1/queue/99999")
    assert resp.status_code == 404

    # Nada alterado (Req 13.11).
    listing = await client.get("/api/printers/p1/queue")
    assert [i["sku"] for i in listing.json()] == ["A"]


async def test_remove_reindexes_remaining_contiguously(
    client, db_session, auth_api_key
):
    # Remove o item do meio; os restantes devem ficar 1..n preservando a ordem
    # relativa (Req 13.12, 13.22).
    items = [
        PrintQueueItem(printer_id="p1", sku="A", name="a", position=1),
        PrintQueueItem(printer_id="p1", sku="B", name="b", position=2),
        PrintQueueItem(printer_id="p1", sku="C", name="c", position=3),
    ]
    db_session.add_all(items)
    await db_session.commit()
    middle_id = items[1].id

    resp = await client.delete(f"/api/printers/p1/queue/{middle_id}")
    assert resp.status_code == 200

    listing = await client.get("/api/printers/p1/queue")
    body = listing.json()
    assert [i["sku"] for i in body] == ["A", "C"]
    # Posições únicas e contíguas 1..n.
    assert [i["position"] for i in body] == [1, 2]


async def test_remove_does_not_touch_other_printers(client, db_session, auth_api_key):
    # Reindexação é escopada ao printer_id da requisição.
    items = [
        PrintQueueItem(printer_id="p1", sku="A", name="a", position=1),
        PrintQueueItem(printer_id="p1", sku="B", name="b", position=2),
        PrintQueueItem(printer_id="p2", sku="X", name="x", position=1),
    ]
    db_session.add_all(items)
    await db_session.commit()
    first_p1 = items[0].id

    resp = await client.delete(f"/api/printers/p1/queue/{first_p1}")
    assert resp.status_code == 200

    p1 = (await client.get("/api/printers/p1/queue")).json()
    p2 = (await client.get("/api/printers/p2/queue")).json()
    assert [i["sku"] for i in p1] == ["B"]
    assert [i["position"] for i in p1] == [1]
    # p2 intacta.
    assert [i["sku"] for i in p2] == ["X"]
    assert [i["position"] for i in p2] == [1]


async def test_remove_without_auth_returns_401(client, db_session):
    item = PrintQueueItem(printer_id="p1", sku="A", name="a", position=1)
    db_session.add(item)
    await db_session.commit()
    item_id = item.id

    resp = await client.delete(
        f"/api/printers/p1/queue/{item_id}",
        headers={"x-api-key": "whatever"},
    )
    assert resp.status_code == 401

    # Nada alterado.
    listing = await client.get("/api/printers/p1/queue")
    assert [i["sku"] for i in listing.json()] == ["A"]
