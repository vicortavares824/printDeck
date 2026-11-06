/**
 * supplyApi: serviço de acesso aos endpoints do Supply_Inventory (Req 15, 16, 17).
 *
 * Todos os endpoints são AUTENTICADOS por `Authorization: Bearer <Firebase_ID_Token>`
 * (via `apiClient` com `auth: true`) e NUNCA enviam `x-api-key` (Req 8.7, 8.8, 15.1).
 * O `device_id` enviado (query do GET/DELETE e corpo do POST /sync) é sempre o e-mail
 * do Authenticated_User (Req 15.1, 16.3, 16.4, 16.5, 16.6).
 *
 * Admin_Mode (Req 17): quando um `adminCode` é fornecido, o cliente o repassa como o
 * header `x-admin-code` (tratado como segredo pelo `apiClient` — nunca logado). O código
 * é passado como argumento e NUNCA guardado neste módulo.
 *
 * Contratos do backend (cloud_api/app/routers/supply.py + schemas/supply.py):
 * - GET    /api/supply/items?device_id=<email>              → SupplyItem[]
 * - POST   /api/supply/sync   { device_id, items: [...] }   → { synced, forbidden }
 * - DELETE /api/supply/items/{item_id}?device_id=<email>    → 200 | 403 | 404
 * - POST   /api/supply/admin/verify  (header x-admin-code)  → 200 { admin: true } | 403
 */
import type { ApiClient } from './client';
import type { SupplyItem } from './types';

/**
 * Item enviado no corpo de `POST /api/supply/sync` (espelha `SupplyItemIn` do backend).
 * O servidor deriva `owner_id` do `device_id` que está agindo — o cliente NÃO o envia.
 */
export interface SupplyItemInput {
  item_id: string;
  title: string;
  /** Opcional (Req 16.1): default `""` no backend quando omitido. */
  description?: string;
  /** Default 1.0 (Req 16.1). */
  quantity: number;
  /** Default `false` (Req 16.1). */
  is_bought: boolean;
}

/**
 * Resposta de `POST /api/supply/sync` (espelha `SupplySyncOut`):
 * - `synced`: quantidade de itens inseridos/atualizados com sucesso (Req 16.11).
 * - `forbidden`: `item_id`s rejeitados por autorização de posse (Req 16.10).
 */
export interface SupplySyncResult {
  synced: number;
  forbidden: string[];
}

/** Resposta de `POST /api/supply/admin/verify` (200 → `{ admin: true }`). */
export interface AdminVerifyResult {
  admin: boolean;
}

/**
 * Cria o serviço de supply ligado a um `apiClient` (autenticado) e ao `email` do
 * Authenticated_User (usado como `device_id` em todas as chamadas).
 */
export function createSupplyApi(client: ApiClient, email: string) {
  return {
    /**
     * Lista os Supply_Items do inventário compartilhado (Req 15.1).
     * `device_id` = e-mail; autenticado por Bearer; sem `x-api-key`.
     */
    async listItems(signal?: AbortSignal): Promise<SupplyItem[]> {
      return client.request<SupplyItem[]>('/api/supply/items', {
        method: 'GET',
        auth: true,
        query: { device_id: email },
        signal,
      });
    },

    /**
     * Sincroniza (insere/atualiza) um ou mais Supply_Items (Req 16.3, 16.4, 16.5).
     * O `adminCode` opcional habilita o Admin_Mode no servidor (Req 17.3/17.4).
     */
    async sync(
      items: SupplyItemInput[],
      adminCode?: string,
      signal?: AbortSignal,
    ): Promise<SupplySyncResult> {
      return client.request<SupplySyncResult>('/api/supply/sync', {
        method: 'POST',
        auth: true,
        json: { device_id: email, items },
        adminCode,
        signal,
      });
    },

    /**
     * Exclui um Supply_Item por `item_id` (Req 16.6). Pode retornar 403 (sem posse)
     * ou 404 (inexistente) — propagados como `ApiError` para a página tratar.
     * O `adminCode` opcional habilita o Admin_Mode (Req 17.4).
     */
    async deleteItem(itemId: string, adminCode?: string, signal?: AbortSignal): Promise<void> {
      await client.request<unknown>(`/api/supply/items/${encodeURIComponent(itemId)}`, {
        method: 'DELETE',
        auth: true,
        query: { device_id: email },
        adminCode,
        signal,
      });
    },

    /**
     * Valida o código de administrador (Req 17.2). Sucesso (200) → `{ admin: true }`;
     * código inválido → 403 (`ApiError` com `status === 403`). O `adminCode` vai no
     * header `x-admin-code` (segredo; nunca logado/exibido).
     */
    async verifyAdmin(adminCode: string, signal?: AbortSignal): Promise<AdminVerifyResult> {
      return client.request<AdminVerifyResult>('/api/supply/admin/verify', {
        method: 'POST',
        auth: true,
        adminCode,
        signal,
      });
    },
  };
}

export type SupplyApi = ReturnType<typeof createSupplyApi>;
