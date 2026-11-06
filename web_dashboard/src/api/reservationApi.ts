/**
 * reservationApi: serviços de RESERVA MANUAL de uma impressora (Req 11, 12).
 *
 * Expõe duas funções que consomem os endpoints AUTENTICADOS da Cloud_API:
 * - `reserve(client, printerId, reservedBy, signal?)` → `POST /api/printers/{id}/reserve`
 *   (corpo `{ reserved_by }`; ocupa/reserva a impressora — Req 12.3).
 * - `release(client, printerId, signal?)`             → `POST /api/printers/{id}/release`
 *   (libera a impressora — Req 12.5).
 *
 * Ambas são AUTENTICADAS por `Authorization: Bearer <Firebase_ID_Token>` (via
 * `apiClient` com `auth: true`) e NUNCA enviam `x-api-key` (Req 8.7, 8.8, 12.3, 12.5).
 * O `reserved_by` enviado ao ocupar é o e-mail do Authenticated_User (o backend também
 * pode derivá-lo do token — Req 12.3).
 *
 * As funções recebem o `ApiClient` por parâmetro (injeção de dependência), como em
 * `printersApi`/`supplyApi`, para reaproveitar o mesmo cliente autenticado (criado via
 * `useApiClient`) e facilitar os testes.
 *
 * Contrato do backend (cloud_api/app/main.py + schemas): ambos respondem com o
 * `ReservationOut` (`printer_id`, `reserved`, `reserved_by`, `reserved_at`).
 */

import type { ApiClient } from './client';

/**
 * Resposta dos endpoints de reserva (espelha `ReservationOut` do backend; Req 11.5).
 * `reserved_by`/`reserved_at` chegam nulos quando a impressora não está reservada.
 */
export interface ReservationOut {
  printer_id: string;
  reserved: boolean;
  reserved_by: string | null;
  reserved_at: string | null;
}

/**
 * Ocupa (reserva) a impressora `printerId` (Req 12.3, 12.4).
 * Autenticado por Bearer; envia `reserved_by` = e-mail do Authenticated_User; sem
 * `x-api-key`. Retorna o Reservation_State resultante (`reserved` verdadeiro).
 */
export function reserve(
  client: ApiClient,
  printerId: string,
  reservedBy: string,
  signal?: AbortSignal,
): Promise<ReservationOut> {
  return client.request<ReservationOut>(
    `/api/printers/${encodeURIComponent(printerId)}/reserve`,
    {
      method: 'POST',
      auth: true,
      json: { reserved_by: reservedBy },
      signal,
    },
  );
}

/**
 * Libera a impressora `printerId` (Req 12.5, 12.6).
 * Autenticado por Bearer; sem corpo relevante e sem `x-api-key`. Retorna o
 * Reservation_State resultante (`reserved` falso).
 */
export function release(
  client: ApiClient,
  printerId: string,
  signal?: AbortSignal,
): Promise<ReservationOut> {
  return client.request<ReservationOut>(
    `/api/printers/${encodeURIComponent(printerId)}/release`,
    {
      method: 'POST',
      auth: true,
      signal,
    },
  );
}
