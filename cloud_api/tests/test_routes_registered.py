"""Smoke de registro de rotas (tarefa 7.1).

Garante que TODOS os endpoints novos da feature web-printer-dashboard estão
registrados e acessíveis via `app.main:app` — o mesmo objeto que o Render sobe
com `uvicorn app.main:app`. Este é um teste de verificação/fiação: não exercita
a lógica dos handlers (coberta por outros testes), apenas confirma que cada rota
esperada, com o método HTTP correto, está exposta pelo app.

A checagem é feita contra o schema OpenAPI do app (`app.openapi()`), que é
exatamente o conjunto de rotas que o FastAPI serve em runtime (incluindo as
rotas trazidas por `include_router` do supply e da queue). Esse é o sinal fiel
ao deploy: o que aparece no OpenAPI é o que responde sob uvicorn/ASGI.

Requisitos cobertos: 1.1, 11.1, 11.2, 13.1, 13.5, 13.10, 13.13, 13.16.
"""
from app.main import app


def _registered_routes() -> set[tuple[str, str]]:
    """Conjunto de (METHOD, path) de todas as rotas servidas pelo app.

    Lê do schema OpenAPI, que reflete as rotas efetivamente expostas em runtime
    (handlers inline + routers incluídos via include_router).
    """
    schema = app.openapi()
    pairs: set[tuple[str, str]] = set()
    for path, operations in schema.get("paths", {}).items():
        for method in operations:
            pairs.add((method.upper(), path))
    return pairs


# (METHOD, path) esperados. Os paths usam os mesmos placeholders que o FastAPI
# registra internamente ({printer_id}, {item_id}).
EXPECTED_ROUTES = [
    # Printer_List_Endpoint (Req 1.1) + telemetry latest como PrinterOut (Req 9.7/9.10)
    ("GET", "/api/printers"),
    ("GET", "/api/telemetry/latest/{printer_id}"),
    # Reserva (Req 11.1, 11.2)
    ("POST", "/api/printers/{printer_id}/reserve"),
    ("POST", "/api/printers/{printer_id}/release"),
    # Print_Queue (Req 13.1, 13.5, 13.10, 13.13, 13.16)
    ("GET", "/api/printers/{printer_id}/queue"),
    ("POST", "/api/printers/{printer_id}/queue"),
    ("DELETE", "/api/printers/{printer_id}/queue/{item_id}"),
    ("POST", "/api/printers/{printer_id}/queue/reorder"),
    ("POST", "/api/printers/{printer_id}/queue/{item_id}/mark-printed"),
    # Supply_Inventory router (/api/supply/*)
    ("GET", "/api/supply/items"),
    ("POST", "/api/supply/sync"),
    ("DELETE", "/api/supply/items/{item_id}"),
    ("POST", "/api/supply/admin/verify"),
]


def test_all_expected_routes_are_registered():
    registered = _registered_routes()
    missing = [route for route in EXPECTED_ROUTES if route not in registered]
    assert not missing, (
        "Rotas esperadas ausentes em app.main:app: "
        + ", ".join(f"{m} {p}" for m, p in missing)
    )


def test_telemetry_latest_uses_printer_out_schema():
    # Req 9.7/9.10: GET /api/telemetry/latest/{printer_id} deve responder como
    # PrinterOut (telemetria + model + Reservation_State).
    from app.schemas.telemetry import PrinterOut

    for route in app.routes:
        if getattr(route, "path", None) == "/api/telemetry/latest/{printer_id}":
            assert route.response_model is PrinterOut
            break
    else:  # pragma: no cover - a rota tem que existir
        raise AssertionError("Rota /api/telemetry/latest/{printer_id} não encontrada")
