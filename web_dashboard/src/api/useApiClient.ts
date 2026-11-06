/**
 * `useApiClient` — hook que monta um `apiClient` autenticado a partir do AuthContext.
 *
 * O `apiClient` (`createApiClient`, em `client.ts`) recebe suas dependências por
 * injeção (`getToken`, `onUnauthorized`) para não acoplar `client.ts` ao AuthContext
 * (evitando ciclo de import). Este hook faz essa fiação no lado React: lê `getToken`
 * e `logout` de `useAuth()` e devolve um cliente memorizado.
 *
 * - `getToken(forceRefresh?)` → `Authorization: Bearer <token>` nas requisições `auth`.
 * - `onUnauthorized` → `logout()`, acionado quando um request autenticado permanece
 *   401 após o refresh do token (Req 18.5, 12.8).
 *
 * NUNCA injeta `x-api-key` (Req 8.7, 8.8). A autorização é só pelo Firebase_ID_Token.
 */
import { useMemo } from 'react';

import { useAuth } from '../auth/AuthContext';
import { createApiClient, type ApiClient } from './client';

/**
 * Retorna um `ApiClient` estável enquanto `getToken`/`logout` do AuthContext não mudam.
 * Os callbacks do AuthContext são memorizados (`useCallback`), então o cliente só é
 * recriado quando necessário.
 */
export function useApiClient(): ApiClient {
  const { getToken, logout } = useAuth();

  return useMemo<ApiClient>(
    () => createApiClient({ getToken, onUnauthorized: logout }),
    [getToken, logout],
  );
}

export default useApiClient;
