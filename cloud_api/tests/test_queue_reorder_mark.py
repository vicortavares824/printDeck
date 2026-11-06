"""Testes de reorder/mark-printed da Print_Queue (tarefa 5.4 — Req 13.13-13.18).

POST /api/printers/{printer_id}/queue/reorder              -> reordena (Req 13.13-13.15)
POST /api/printers/{printer_id}/queue/{item_id}/mark-printed -> marca impresso + reindexa (Req 13.16-13.18)

Ambos protegidos por require_auth (Req 13.8/13.9). Como em test_queue_write.py,
sobrescrevemos a dependency `require_auth` via `app.dependency_overrides` para
exercitar o caminho autorizado sem subir o Firebase; os testes de 401 NÃO usam
esse override, validando que a escrita sem auth é rejeitada.
"""
import pytest

from app.core.auth import Identity, require_auth
from app.main import app
from app.models.queue import PrintQueueItem


@pytest.fixture
def auth_api_key():
    """Autoriza as escritas como via x-api-key (sem e-mail no token)."""
    app.dependency_overrides[require_auth] = lambda: Identity(
        email=None, uid=None, via="api_key"
    )
    yield
    app.dependency_overrides.pop(require_auth, None)


# --- reorder (Req 13.13-13.15) ---------------------------------------------
async def test_reorder_applies_received_order(client, db_session, auth_api_key):
    # Reorder consistente atribui position 1..n conforme a ordem recebida (Req 13.14).
    items = [
        PrintQueueItem(printer_id="p1", sku="A", name="a", position=1),
        PrintQueueItem(printer_id="p1", sku="B", name="b", position=2),
        PrintQueueItem(printer_id="p1", sku="C", name="c", position=3),
    ]
    db_session.add_all(items)
    await db_session.commit()
    id_a, id_b, id_c = items[0].id, items[1].id, items[2].id

    resp = await client.post(
        "/api/printers/p1/queue/reorder",
        json={"ordered_ids": [id_c, id_a, id_b]},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert [i["sku"] for i in body] == ["C", "A", "B"]
    assert [i["position"] for i in body] == [1, 2, 3]

    # Persistido: a releitura reflete a nova ordem.
    listing = (await client.get("/api/printers/p1/queue")).json()
    assert [i["sku"] for i in listing] == ["C", "A", "B"]
    assert [i["position"] for i in listing] == [1, 2, 3]


async def test_reorder_unknown_id_returns_422_without_changing(
    client, db_session, auth_api_key
):
    # id desconhecido na lista => 422, posições inalteradas (Req 13.15).
    items = [
        PrintQueueItem(printer_id="p1", sku="A", name="a", position=1),
        PrintQueueItem(printer_id="p1", sku="B", name="b", position=2),
    ]
    db_session.add_all(items)
    await db_session.commit()
    id_a = items[0].id

    resp = await client.post(
        "/api/printers/p1/queue/reorder",
        json={"ordered_ids": [id_a, 99999]},
    )
    assert resp.status_code == 422

    listing = (await client.get("/api/printers/p1/queue")).json()
    assert [i["sku"] for i in listing] == ["A", "B"]
    assert [i["position"] for i in listing] == [1, 2]


async def test_reorder_missing_id_returns_422_without_changing(
    client, db_session, auth_api_key
):
    # Lista incompleta (faltando um id da fila) => 422 sem alterar (Req 13.15).
    items = [
        PrintQueueItem(printer_id="p1", sku="A", name="a", position=1),
        PrintQueueItem(printer_id="p1", sku="B", name="b", position=2),
        PrintQueueItem(printer_id="p1", sku="C", name="c", position=3),
    ]
    db_session.add_all(items)
    await db_session.commit()
    id_a, id_b = items[0].id, items[1].id

    resp = await client.post(
        "/api/printers/p1/queue/reorder",
        json={"ordered_ids": [id_b, id_a]},
    )
    assert resp.status_code == 422

    listing = (await client.get("/api/printers/p1/queue")).json()
    assert [i["sku"] for i in listing] == ["A", "B", "C"]
    assert [i["position"] for i in listing] == [1, 2, 3]


async def test_reorder_duplicate_id_returns_422_without_changing(
    client, db_session, auth_api_key
):
    # id duplicado (mesmo que todos pertençam à fila) => 422 sem alterar (Req 13.15).
    items = [
        PrintQueueItem(printer_id="p1", sku="A", name="a", position=1),
        PrintQueueItem(printer_id="p1", sku="B", name="b", position=2),
    ]
    db_session.add_all(items)
    await db_session.commit()
    id_a = items[0].id

    resp = await client.post(
        "/api/printers/p1/queue/reorder",
        json={"ordered_ids": [id_a, id_a]},
    )
    assert resp.status_code == 422

    listing = (await client.get("/api/printers/p1/queue")).json()
    assert [i["sku"] for i in listing] == ["A", "B"]
    assert [i["position"] for i in listing] == [1, 2]


async def test_reorder_without_auth_returns_401(client, db_session):
    # Sem auth => 401, sem alterar (Req 13.8/13.9). Sem override.
    items = [
        PrintQueueItem(printer_id="p1", sku="A", name="a", position=1),
        PrintQueueItem(printer_id="p1", sku="B", name="b", position=2),
    ]
    db_session.add_all(items)
    await db_session.commit()
    id_a, id_b = items[0].id, items[1].id

    resp = await client.post(
        "/api/printers/p1/queue/reorder",
        json={"ordered_ids": [id_b, id_a]},
        headers={"x-api-key": "whatever"},
    )
    assert resp.status_code == 401

    listing = (await client.get("/api/printers/p1/queue")).json()
    assert [i["sku"] for i in listing] == ["A", "B"]
    assert [i["position"] for i in listing] == [1, 2]


# --- mark-printed (Req 13.16-13.18) ----------------------------------------
async def test_mark_printed_removes_and_reindexes(client, db_session, auth_api_key):
    # Marca o item do meio como impresso; os restantes ficam 1..n preservando a
    # ordem relativa (Req 13.16, 13.18, 13.22).
    items = [
        PrintQueueItem(printer_id="p1", sku="A", name="a", position=1),
        PrintQueueItem(printer_id="p1", sku="B", name="b", position=2),
        PrintQueueItem(printer_id="p1", sku="C", name="c", position=3),
    ]
    db_session.add_all(items)
    await db_session.commit()
    middle_id = items[1].id

    resp = await client.post(f"/api/printers/p1/queue/{middle_id}/mark-printed")
    assert resp.status_code == 200
    body = resp.json()
    assert [i["sku"] for i in body] == ["A", "C"]
    assert [i["position"] for i in body] == [1, 2]

    # Persistido.
    listing = (await client.get("/api/printers/p1/queue")).json()
    assert [i["sku"] for i in listing] == ["A", "C"]
    assert [i["position"] for i in listing] == [1, 2]


async def test_mark_printed_nonexistent_returns_404(client, db_session, auth_api_key):
    # id inexistente => 404 sem alterar (Req 13.17).
    db_session.add(PrintQueueItem(printer_id="p1", sku="A", name="a", position=1))
    await db_session.commit()

    resp = await client.post("/api/printers/p1/queue/99999/mark-printed")
    assert resp.status_code == 404

    listing = (await client.get("/api/printers/p1/queue")).json()
    assert [i["sku"] for i in listing] == ["A"]
    assert [i["position"] for i in listing] == [1]


async def test_mark_printed_does_not_touch_other_printers(
    client, db_session, auth_api_key
):
    # Reindexação é escopada ao printer_id da requisição.
    items = [
        PrintQueueItem(printer_id="p1", sku="A", name="a", position=1),
        PrintQueueItem(printer_id="p1", sku="B", name="b", position=2),
        PrintQueueItem(printer_id="p2", sku="X", name="x", position=1),
    ]
    db_session.add_all(items)
    await db_session.commit()
    first_p1 = items[0].id

    resp = await client.post(f"/api/printers/p1/queue/{first_p1}/mark-printed")
    assert resp.status_code == 200

    p1 = (await client.get("/api/printers/p1/queue")).json()
    p2 = (await client.get("/api/printers/p2/queue")).json()
    assert [i["sku"] for i in p1] == ["B"]
    assert [i["position"] for i in p1] == [1]
    assert [i["sku"] for i in p2] == ["X"]
    assert [i["position"] for i in p2] == [1]


async def test_mark_printed_without_auth_returns_401(client, db_session):
    # Sem auth => 401, sem alterar (Req 13.8/13.9). Sem override.
    item = PrintQueueItem(printer_id="p1", sku="A", name="a", position=1)
    db_session.add(item)
    await db_session.commit()
    item_id = item.id

    resp = await client.post(
        f"/api/printers/p1/queue/{item_id}/mark-printed",
        headers={"x-api-key": "whatever"},
    )
    assert resp.status_code == 401

    listing = (await client.get("/api/printers/p1/queue")).json()
    assert [i["sku"] for i in listing] == ["A"]
    assert [i["position"] for i in listing] == [1]
