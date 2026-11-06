/**
 * printersApi: serviços de LEITURA PÚBLICA da frota de impressoras (Req 1, 3, 6).
 *
 * Expõe três funções que consomem os GETs públicos da Cloud_API:
 * - `getPrinters(client, signal?)`        → `GET /api/printers`               (Printer_List_Endpoint; Req 1, 3.1)
 * - `getLatestTelemetry(client, id, …)`   → `GET /api/telemetry/latest/{id}`  (status da impressora; Req 6.6, 9.7)
 * - `getJobHistory(client, id, …)`        → `GET /api/jobs/{id}`              (Job_History; Req 6.2)
 *
 * Essas leituras são PÚBLICAS (Req 1.10): não exigem `Authorization: Bearer` nem
 * `x-api-key`. Por isso as funções usam `auth: false` (padrão do `RequestOptions`) e
 * podem ser chamadas com um `apiClient` sem `getToken` configurado.
 *
 * As funções recebem o `ApiClient` por parâmetro (injeção de dependência), em vez de
 * criar um cliente internamente, para que as páginas reaproveitem o mesmo cliente
 * (criado via `createApiClient` de `api/client.ts`) e para facilitar os testes.
 *
 * O `signal` opcional é encaminhado ao `apiClient` — o `usePolling` passa seu
 * `AbortSignal` para que o request em andamento seja abortado no cleanup (Req 5.4).
 */

import type { ApiClient } from './client';
import type { Job, Printer } from './types';

/**
 * Lista todas as impressoras conhecidas, cada uma com o Telemetry_Record mais recente,
 * o `model` e o Reservation_State mesclado (Req 1, 3.1). Público — sem auth (Req 1.10).
 *
 * Retorna um array (possivelmente vazio quando não há impressoras — Req 1.9/3.7).
 */
export function getPrinters(client: ApiClient, signal?: AbortSignal): Promise<Printer[]> {
  return client.request<Printer[]>('/api/printers', { signal });
}

/**
 * Obtém o status atual (último Telemetry_Record) de uma impressora específica, já com
 * `model` + Reservation_State (Req 6.6, 9.7, 9.10). Público — sem auth.
 *
 * Usado pelo polling do detalhe da impressora (tarefa 15.1).
 */
export function getLatestTelemetry(
  client: ApiClient,
  printerId: string,
  signal?: AbortSignal,
): Promise<Printer> {
  return client.request<Printer>(`/api/telemetry/latest/${encodeURIComponent(printerId)}`, {
    signal,
  });
}

/**
 * Obtém o Job_History (trabalhos concluídos/cancelados) de uma impressora (Req 6.2).
 * Público — sem auth. Retorna um array (vazio quando não há histórico — Req 6.4).
 */
export function getJobHistory(
  client: ApiClient,
  printerId: string,
  signal?: AbortSignal,
): Promise<Job[]> {
  return client.request<Job[]>(`/api/jobs/${encodeURIComponent(printerId)}`, { signal });
}
