"""Testes do GET público da Print_Queue (tarefa 5.2 — Req 13.1-13.4, 13.21).

GET /api/printers/{printer_id}/queue:
  - público, sem x-api-key (Req 13.4)
  - itens ordenados por position asc (Req 13.1) com os campos de QueueItemOut (Req 13.2)
  - fila vazia => [] com 200 (Req 13.3)
  - opera por printer_id textual, mesmo sem registro em telemetry_logs (Req 13.21)
"""
from app.models.queue import PrintQueueItem

QUEUE_FIELDS = {
    "id",
    "printer_id",
    "sku",
    "name",
    "position",
    "created_at",
    "created_by",
}


async def test_empty_queue_returns_empty_list_200(client, db_session):
    # Req 13.3 / 13.21: printer_id sem Queue_Items (e inexistente em
    # telemetry_logs) => [] com 200, sem x-api-key.
    resp = await client.get("/api/printers/unknown-printer/queue")
    assert resp.status_code == 200
    assert resp.json() == []


async def test_queue_ordered_by_position_ascending(client, db_session):
    # Semeia itens fora de ordem; a leitura deve devolvê-los por position asc.
    db_session.add_all(
        [
            PrintQueueItem(printer_id="p1", sku="C", name="c", position=3,
                           created_by="c@x.com"),
            PrintQueueItem(printer_id="p1", sku="A", name="a", position=1,
                           created_by=None),
            PrintQueueItem(printer_id="p1", sku="B", name="b", position=2,
                           created_by="b@x.com"),
        ]
    )
    await db_session.commit()

    resp = await client.get("/api/printers/p1/queue")
    assert resp.status_code == 200
    body = resp.json()

    # Req 13.1: ordem ascendente por position.
    assert [i["position"] for i in body] == [1, 2, 3]
    assert [i["sku"] for i in body] == ["A", "B", "C"]
    # Req 13.2: todos os campos esperados presentes.
    assert QUEUE_FIELDS.issubset(body[0].keys())
    # created_by pode ser nulo e é preservado.
    assert body[0]["created_by"] is None
    assert body[1]["created_by"] == "b@x.com"


async def test_queue_scoped_to_requested_printer_id(client, db_session):
    # Itens de outras impressoras não vazam para a fila consultada (Req 13.1).
    db_session.add_all(
        [
            PrintQueueItem(printer_id="p1", sku="A", name="a", position=1),
            PrintQueueItem(printer_id="p2", sku="X", name="x", position=1),
            PrintQueueItem(printer_id="p2", sku="Y", name="y", position=2),
        ]
    )
    await db_session.commit()

    resp = await client.get("/api/printers/p2/queue")
    assert resp.status_code == 200
    body = resp.json()
    assert [i["sku"] for i in body] == ["X", "Y"]
    assert all(i["printer_id"] == "p2" for i in body)


async def test_queue_operates_for_printer_absent_from_telemetry(client, db_session):
    # Req 13.21: o printer_id "zeta" não existe em telemetry_logs, mas a fila
    # ainda assim retorna seus Queue_Items normalmente.
    db_session.add(
        PrintQueueItem(printer_id="zeta", sku="ONLY", name="only", position=1)
    )
    await db_session.commit()

    resp = await client.get("/api/printers/zeta/queue")
    assert resp.status_code == 200
    body = resp.json()
    assert len(body) == 1
    assert body[0]["printer_id"] == "zeta"
    assert body[0]["sku"] == "ONLY"
