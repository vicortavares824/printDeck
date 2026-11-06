/**
 * queueApi: serviços da Print_Queue de uma impressora (Req 13, 14).
 *
 * Expõe as funções que consomem os endpoints da Cloud_API para a fila compartilhada:
 * - `getQueue(client, printerId, signal?)`                → `GET  /api/printers/{id}/queue`              (PÚBLICO; Req 13.1–13.4, 14.1)
 * - `addItem(client, printerId, { sku, name, created_by })` → `POST /api/printers/{id}/queue`             (AUTH; Req 13.5, 14.6)
 * - `remove(client, printerId, itemId, signal?)`          → `DELETE /api/printers/{id}/queue/{itemId}`    (AUTH; Req 13.10, 14.8)
 * - `reorder(client, printerId, orderedIds, signal?)`     → `POST /api/printers/{id}/queue/reorder`       (AUTH; Req 13.13, 14.7)
 * - `markPrinted(client, printerId, itemId, signal?)`     → `POST /api/printers/{id}/queue/{itemId}/mark-printed` (AUTH; Req 13.16, 14.9)
 *
 * A leitura (`getQueue`) é PÚBLICA (Req 13.4): não exige `Authorization: Bearer` nem
 * `x-api-key`, e pode ser chamada com um `apiClient` sem `getToken` configurado.
 *
 * As ESCRITAS (`addItem`, `remove`, `reorder`, `markPrinted`) são AUTENTICADAS por
 * `Authorization: Bearer <Firebase_ID_Token>` (via `apiClient` com `auth: true`) e
 * NUNCA enviam `x-api-key` (Req 8.7, 8.8, 14.6–14.9). Ao adicionar, `created_by` é o
 * e-mail do Authenticated_User (o backend também pode derivá-lo do token — Req 13.5).
 *
 * As funções recebem o `ApiClient` por parâmetro (injeção de dependência), como em
 * `printersApi`/`reservationApi`/`supplyApi`, para reaproveitar o mesmo cliente
 * (criado via `createApiClient`/`useApiClient`) e facilitar os testes.
 *
 * Contratos do backend (cloud_api/app/routers/queue.py + schemas/queue.py):
 * - add: corpo `{ sku, name, created_by }` → `QueueItemOut`; `sku` vazio → 422 (Req 13.7).
 * - reorder: corpo `{ ordered_ids }`; conjunto deve bater com a fila, senão 422 (Req 13.15).
 * - remove/mark-printed: `id` inexistente → 404 (Req 13.11, 13.17).
 */

import type { ApiClient } from './client';
import type { QueueItem } from './types';

/**
 * Corpo de `POST /api/printers/{id}/queue` (espelha `QueueAddIn` do backend).
 * `sku` é texto livre não vazio (vazio → 422, Req 13.7); `name` é opcional (default "");
 * `created_by` é o e-mail do Authenticated_User (o backend prefere o e-mail do token).
 */
export interface QueueAddInput {
  sku: string;
  name?: string;
  created_by?: string | null;
}

/**
 * Lê a Print_Queue da impressora `printerId`, com os Queue_Items ordenados por
 * `position` ascendente (Req 13.1, 14.1). PÚBLICO — sem auth (Req 13.4).
 *
 * Retorna um array (possivelmente vazio quando a fila está vazia — Req 13.3).
 */
export function getQueue(
  client: ApiClient,
  printerId: string,
  signal?: AbortSignal,
): Promise<QueueItem[]> {
  return client.request<QueueItem[]>(
    `/api/printers/${encodeURIComponent(printerId)}/queue`,
    { signal },
  );
}

/**
 * Adiciona um Queue_Item ao FIM da Print_Queue de `printerId` (Req 13.5, 13.6, 14.6).
 * Autenticado por Bearer; `created_by` = e-mail do Authenticated_User; sem `x-api-key`.
 * Retorna o Queue_Item criado (`QueueItemOut`). `sku` vazio → 422 (Req 13.7).
 */
export function addItem(
  client: ApiClient,
  printerId: string,
  input: QueueAddInput,
  signal?: AbortSignal,
): Promise<QueueItem> {
  return client.request<QueueItem>(
    `/api/printers/${encodeURIComponent(printerId)}/queue`,
    {
      method: 'POST',
      auth: true,
      json: input,
      signal,
    },
  );
}

/**
 * Remove o Queue_Item `itemId` da Print_Queue de `printerId` (Req 13.10, 14.8).
 * Autenticado por Bearer; sem `x-api-key`. O backend reindexa as posições restantes
 * (Req 13.12). `id` inexistente → 404 (`ApiError` com `status === 404`, Req 13.11).
 */
export function remove(
  client: ApiClient,
  printerId: string,
  itemId: number,
  signal?: AbortSignal,
): Promise<void> {
  return client
    .request<unknown>(
      `/api/printers/${encodeURIComponent(printerId)}/queue/${encodeURIComponent(itemId)}`,
      {
        method: 'DELETE',
        auth: true,
        signal,
      },
    )
    .then(() => undefined);
}

/**
 * Reordena a Print_Queue de `printerId` conforme a nova ordem de `id` (Req 13.13, 14.7).
 * Autenticado por Bearer; corpo `{ ordered_ids }`; sem `x-api-key`. O conjunto de ids
 * deve bater exatamente com a fila atual, senão o backend responde 422 sem alterar as
 * posições (Req 13.15).
 */
export function reorder(
  client: ApiClient,
  printerId: string,
  orderedIds: number[],
  signal?: AbortSignal,
): Promise<QueueItem[]> {
  return client.request<QueueItem[]>(
    `/api/printers/${encodeURIComponent(printerId)}/queue/reorder`,
    {
      method: 'POST',
      auth: true,
      json: { ordered_ids: orderedIds },
      signal,
    },
  );
}

/**
 * Marca o Queue_Item `itemId` como impresso, removendo-o da Print_Queue ativa
 * (Req 13.16, 14.9). Autenticado por Bearer; sem `x-api-key`. O backend reindexa as
 * posições restantes (Req 13.18). `id` inexistente → 404 (Req 13.17).
 */
export function markPrinted(
  client: ApiClient,
  printerId: string,
  itemId: number,
  signal?: AbortSignal,
): Promise<void> {
  return client
    .request<unknown>(
      `/api/printers/${encodeURIComponent(printerId)}/queue/${encodeURIComponent(
        itemId,
      )}/mark-printed`,
      {
        method: 'POST',
        auth: true,
        signal,
      },
    )
    .then(() => undefined);
}
