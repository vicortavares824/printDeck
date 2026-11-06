from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import Identity, require_auth
from app.core.database import get_db
from app.models.queue import PrintQueueItem
from app.schemas.queue import QueueAddIn, QueueItemOut, QueueReorderIn

# Router da Print_Queue. Os endpoints de escrita (add/remove/reorder/mark-printed)
# são implementados nas tarefas 5.3/5.4; aqui definimos o router, o helper de
# reindexação compartilhado e o GET público de leitura (tarefa 5.2). Mantemos as
# seções claramente separadas para que as tarefas seguintes acrescentem seus
# endpoints de escrita sem conflito.
router = APIRouter(tags=["queue"])


# ---------------------------------------------------------------------------
# Helpers compartilhados
# ---------------------------------------------------------------------------
def reindex(items_sorted_by_position: list[PrintQueueItem]) -> list[PrintQueueItem]:
    """Reatribui position 1..n preservando a ordem relativa recebida.

    Recebe os Queue_Items já ordenados pela ordem desejada (tipicamente por
    position ascendente) e grava 1, 2, 3, ... em cada um. Garante a invariante de
    posições únicas e contíguas de uma mesma Print_Queue (Req 13.12, 13.18, 13.22).
    Usado por remove e mark-printed (tarefas 5.3/5.4). Retorna a mesma lista por
    conveniência.
    """
    for new_pos, item in enumerate(items_sorted_by_position, start=1):
        item.position = new_pos
    return items_sorted_by_position


# ---------------------------------------------------------------------------
# Leitura pública (tarefa 5.2 — Req 13.1-13.4, 13.21)
# ---------------------------------------------------------------------------
@router.get("/api/printers/{printer_id}/queue", response_model=list[QueueItemOut])
async def get_queue(
    printer_id: str, db: AsyncSession = Depends(get_db)
) -> list[PrintQueueItem]:
    """Lê a Print_Queue de uma impressora (Req 13.1-13.4, 13.21).

    Endpoint PÚBLICO: sem require_auth e sem x-api-key (Req 13.4). Retorna os
    Queue_Items do `printer_id` ordenados por `position` ascendente (Req 13.1),
    serializados como QueueItemOut com os campos id, printer_id, sku, name,
    position, created_at e created_by (Req 13.2).

    O `printer_id` é tratado logicamente como texto (Req 13.21): a leitura opera
    normalmente mesmo que o `printer_id` não exista em `telemetry_logs`. Quando
    não há Queue_Items para o `printer_id`, retorna lista vazia com 200 (Req 13.3).
    """
    query = (
        select(PrintQueueItem)
        .where(PrintQueueItem.printer_id == printer_id)
        .order_by(PrintQueueItem.position.asc())
    )
    result = await db.execute(query)
    return list(result.scalars().all())


# ---------------------------------------------------------------------------
# Escrita protegida (tarefas 5.3/5.4 — Req 13.5-13.18, require_auth)
# add / remove / reorder / mark-printed são adicionados aqui.
# ---------------------------------------------------------------------------

# --- add / remove (tarefa 5.3 — Req 13.5-13.12) ----------------------------
@router.post(
    "/api/printers/{printer_id}/queue",
    response_model=QueueItemOut,
    dependencies=[Depends(require_auth)],
)
async def add_queue_item(
    printer_id: str,
    body: QueueAddIn,
    identity: Identity = Depends(require_auth),
    db: AsyncSession = Depends(get_db),
) -> PrintQueueItem:
    """Adiciona um Queue_Item ao FIM da Print_Queue (Req 13.5-13.7).

    Protegido por require_auth (Req 13.8/13.9): sem token válido nem x-api-key
    válida, a dependency responde 401 antes de qualquer efeito colateral.

    - `position` = maior `position` da fila deste `printer_id` + 1, ou 1 quando
      a fila está vazia (Req 13.6), preservando a invariante de posições únicas e
      contíguas (Req 13.22).
    - `created_by` = `email` das claims do token quando disponível; senão o
      `created_by` do corpo (Req 13.5).
    - `sku` vazio (após strip) => HTTPException 422, sem persistir (Req 13.7).

    O `printer_id` é tratado logicamente como texto (Req 13.21): a fila opera
    mesmo que o `printer_id` não exista em `telemetry_logs`.
    """
    sku = (body.sku or "").strip()
    if not sku:
        raise HTTPException(status_code=422, detail="sku não pode ser vazio")

    # max(position) da fila deste printer_id; None quando a fila está vazia.
    max_position = await db.scalar(
        select(func.max(PrintQueueItem.position)).where(
            PrintQueueItem.printer_id == printer_id
        )
    )
    next_position = (max_position or 0) + 1

    # email do token tem precedência; o corpo é fallback (Req 13.5).
    created_by = identity.email or body.created_by

    item = PrintQueueItem(
        printer_id=printer_id,
        sku=sku,
        name=body.name or "",
        position=next_position,
        created_by=created_by,
    )
    db.add(item)
    await db.commit()
    await db.refresh(item)
    return item


@router.delete(
    "/api/printers/{printer_id}/queue/{item_id}",
    response_model=list[QueueItemOut],
    dependencies=[Depends(require_auth)],
)
async def remove_queue_item(
    printer_id: str,
    item_id: int,
    db: AsyncSession = Depends(get_db),
) -> list[PrintQueueItem]:
    """Remove um Queue_Item da Print_Queue e reindexa os restantes (Req 13.10-13.12).

    Protegido por require_auth (Req 13.8/13.9).

    - 404 se o `item_id` não existe nesta Print_Queue (`printer_id`), sem alterar
      nada (Req 13.11).
    - Após remover, reindexa (helper `reindex`) as posições restantes mantendo a
      ordem relativa anterior, únicas e contíguas (1..n) (Req 13.12, 13.22).

    Retorna a Print_Queue resultante ordenada por `position` asc.
    """
    item = await db.scalar(
        select(PrintQueueItem).where(
            PrintQueueItem.printer_id == printer_id,
            PrintQueueItem.id == item_id,
        )
    )
    if item is None:
        raise HTTPException(status_code=404, detail="Queue_Item não encontrado")

    await db.delete(item)
    await db.flush()

    # Reindexa os remanescentes desta fila preservando a ordem por position.
    remaining = list(
        (
            await db.execute(
                select(PrintQueueItem)
                .where(PrintQueueItem.printer_id == printer_id)
                .order_by(PrintQueueItem.position.asc())
            )
        )
        .scalars()
        .all()
    )
    reindex(remaining)
    await db.commit()
    return remaining


# --- reorder / mark-printed (tarefa 5.4 — Req 13.13-13.18) -----------------
@router.post(
    "/api/printers/{printer_id}/queue/reorder",
    response_model=list[QueueItemOut],
    dependencies=[Depends(require_auth)],
)
async def reorder_queue(
    printer_id: str,
    body: QueueReorderIn,
    db: AsyncSession = Depends(get_db),
) -> list[PrintQueueItem]:
    """Reordena a Print_Queue conforme `ordered_ids` (Req 13.13-13.15).

    Protegido por require_auth (Req 13.8/13.9).

    - `ordered_ids` define a nova ordem; o conjunto de ids recebido DEVE bater
      exatamente com o conjunto de ids atual da fila deste `printer_id`. Qualquer
      id desconhecido, faltando ou duplicado => HTTPException 422 sem alterar
      nenhuma `position` persistida (Req 13.15).
    - Quando consistente, atribui a cada Queue_Item a `position` correspondente à
      sua ordem na lista recebida (1..n), preservando a invariante de posições
      únicas e contíguas (Req 13.14, 13.22).

    Retorna a Print_Queue resultante ordenada por `position` asc.
    """
    items = list(
        (
            await db.execute(
                select(PrintQueueItem)
                .where(PrintQueueItem.printer_id == printer_id)
                .order_by(PrintQueueItem.position.asc())
            )
        )
        .scalars()
        .all()
    )

    current_ids = {item.id for item in items}
    # Divergência de conjunto: tamanho (captura duplicatas/faltando) ou ids
    # desconhecidos/ausentes. Qualquer caso => 422 sem alterar nada (Req 13.15).
    if len(body.ordered_ids) != len(current_ids) or set(body.ordered_ids) != current_ids:
        raise HTTPException(
            status_code=422,
            detail="ordered_ids não corresponde exatamente à fila atual",
        )

    by_id = {item.id: item for item in items}
    for new_pos, item_id in enumerate(body.ordered_ids, start=1):
        by_id[item_id].position = new_pos
    await db.commit()

    reordered = list(
        (
            await db.execute(
                select(PrintQueueItem)
                .where(PrintQueueItem.printer_id == printer_id)
                .order_by(PrintQueueItem.position.asc())
            )
        )
        .scalars()
        .all()
    )
    return reordered


@router.post(
    "/api/printers/{printer_id}/queue/{item_id}/mark-printed",
    response_model=list[QueueItemOut],
    dependencies=[Depends(require_auth)],
)
async def mark_printed(
    printer_id: str,
    item_id: int,
    db: AsyncSession = Depends(get_db),
) -> list[PrintQueueItem]:
    """Marca um Queue_Item como impresso, removendo-o da fila ativa (Req 13.16-13.18).

    Protegido por require_auth (Req 13.8/13.9).

    - 404 se o `item_id` não existe nesta Print_Queue (`printer_id`), sem alterar
      nada (Req 13.17).
    - Após remover, reindexa (helper `reindex`) as posições restantes mantendo a
      ordem relativa anterior, únicas e contíguas (1..n) (Req 13.18, 13.22).

    Retorna a Print_Queue resultante ordenada por `position` asc.
    """
    item = await db.scalar(
        select(PrintQueueItem).where(
            PrintQueueItem.printer_id == printer_id,
            PrintQueueItem.id == item_id,
        )
    )
    if item is None:
        raise HTTPException(status_code=404, detail="Queue_Item não encontrado")

    await db.delete(item)
    await db.flush()

    # Reindexa os remanescentes desta fila preservando a ordem por position.
    remaining = list(
        (
            await db.execute(
                select(PrintQueueItem)
                .where(PrintQueueItem.printer_id == printer_id)
                .order_by(PrintQueueItem.position.asc())
            )
        )
        .scalars()
        .all()
    )
    reindex(remaining)
    await db.commit()
    return remaining
