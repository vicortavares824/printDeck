/**
 * apiClient: cliente `fetch` base do Dashboard.
 *
 * Responsabilidades (design.md → "apiClient"; Req 7, 18, 12.8):
 * - Base URL a partir de `import.meta.env.VITE_CLOUD_API_URL` (via `config/env.ts`).
 * - Timeout por request com `AbortController` (compondo com um `signal` externo).
 * - Injeção de `Authorization: Bearer <token>` quando a requisição é autenticada,
 *   obtendo o token por uma função `getToken()` INJETADA (sem importar o AuthContext,
 *   evitando acoplamento/ciclo). O AuthContext (tarefa 10.1) fornece essa dependência.
 * - Tratamento de 401: chama `getToken(true)` (refresh) e repete UMA vez; se persistir
 *   401, aciona `onUnauthorized()` (logout) injetado (Req 18.5, 12.8).
 * - Erros tipados via `ApiError` (rede / `AbortError`/timeout / status HTTP) (Req 7.1).
 * - Retry de Cold_Start via `withColdStartRetry` (3 tentativas, 10s de intervalo,
 *   60s por tentativa) (Req 7.2–7.4).
 * - Header opcional `x-admin-code` para o Admin_Mode do estoque (Req 17.3).
 *
 * NUNCA envia `x-api-key` nem qualquer header de api key (Req 8.7, 8.8). O frontend
 * autoriza-se exclusivamente pelo `Firebase_ID_Token` via `Authorization: Bearer`.
 */

import { env } from '../config/env';
import { ApiError } from './types';

/** Timeout padrão de um request de polling/leitura (ms). (Req 5.5 referencia 8s.) */
export const DEFAULT_TIMEOUT_MS = 8_000;

/**
 * Dependências injetadas no cliente (fornecidas pelo AuthContext na tarefa 10.1).
 *
 * Injetadas por composição para que `client.ts` não importe `auth/AuthContext`
 * (evita acoplamento circular). Ambas são opcionais: um cliente sem elas só faz
 * requisições públicas (sem `Bearer`, sem refresh/logout em 401).
 */
export interface ApiClientDeps {
  /**
   * Obtém o `Firebase_ID_Token` atual. Com `forceRefresh=true`, renova o token
   * (equivalente a `getIdToken(true)`), usado no retry após um 401 (Req 18.5).
   */
  getToken?: (forceRefresh?: boolean) => Promise<string>;
  /**
   * Acionado quando um request autenticado permanece 401 após o refresh do token:
   * o cliente desloga a sessão (Req 18.5, 12.8).
   */
  onUnauthorized?: () => void | Promise<void>;
}

/** Opções por request. */
export interface RequestOptions {
  /** Método HTTP (default `GET`). */
  method?: string;
  /** Corpo JSON a ser serializado; definido também o `Content-Type`. */
  json?: unknown;
  /** Headers adicionais (nunca inclua `x-api-key`). */
  headers?: Record<string, string>;
  /** Query params anexados ao path. */
  query?: Record<string, string | number | boolean | null | undefined>;
  /** Timeout do request em ms (default `DEFAULT_TIMEOUT_MS`). */
  timeoutMs?: number;
  /** Sinal externo de cancelamento, combinado ao timeout interno. */
  signal?: AbortSignal;
  /**
   * Quando `true`, injeta `Authorization: Bearer <token>` e habilita o fluxo de
   * refresh/logout em 401. Requer `getToken` nas dependências do cliente.
   */
  auth?: boolean;
  /** Código de administrador do estoque; vira o header `x-admin-code` (Req 17.3). */
  adminCode?: string;
}

/** Parâmetros do retry de Cold_Start (Req 7.2–7.4). */
export interface ColdStartOptions {
  /** Máximo de tentativas (default 3). */
  maxAttempts?: number;
  /** Intervalo entre tentativas em ms (default 10_000). */
  retryDelayMs?: number;
  /** Janela por tentativa em ms (default 60_000). Informativo para o chamador. */
  perAttemptTimeoutMs?: number;
}

const COLD_START_DEFAULTS: Required<ColdStartOptions> = {
  maxAttempts: 3,
  retryDelayMs: 10_000,
  perAttemptTimeoutMs: 60_000,
};

/** Remove barras finais da base e iniciais do path, unindo com uma única `/`. */
function joinUrl(base: string, path: string): string {
  const b = base.replace(/\/+$/, '');
  const p = path.replace(/^\/+/, '');
  return `${b}/${p}`;
}

/** Anexa os query params (ignorando `null`/`undefined`) ao URL. */
function applyQuery(
  url: string,
  query: RequestOptions['query'],
): string {
  if (!query) return url;
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(query)) {
    if (value === null || value === undefined) continue;
    params.append(key, String(value));
  }
  const qs = params.toString();
  if (qs === '') return url;
  return url.includes('?') ? `${url}&${qs}` : `${url}?${qs}`;
}

/** Combina um `AbortSignal` externo com o `AbortController` interno de timeout. */
function linkExternalSignal(controller: AbortController, external?: AbortSignal): () => void {
  if (!external) return () => {};
  if (external.aborted) {
    controller.abort(external.reason);
    return () => {};
  }
  const onAbort = () => controller.abort(external.reason);
  external.addEventListener('abort', onAbort);
  return () => external.removeEventListener('abort', onAbort);
}

/** Lê o corpo da resposta como JSON quando possível; senão como texto; senão `null`. */
async function readBody(response: Response): Promise<unknown> {
  const contentType = response.headers.get('content-type') ?? '';
  try {
    if (contentType.includes('application/json')) {
      return await response.json();
    }
    const text = await response.text();
    return text === '' ? null : text;
  } catch {
    return null;
  }
}

/** Distingue `AbortError` (timeout/cancelamento) de falha de rede e constrói `ApiError`. */
function toApiError(error: unknown): ApiError {
  if (error instanceof ApiError) return error;
  if (error instanceof DOMException && error.name === 'AbortError') {
    return new ApiError('timeout', 'A requisição excedeu o tempo limite ou foi cancelada.', {
      cause: error,
    });
  }
  // `TypeError` do fetch indica tipicamente falha de rede/servidor inalcançável.
  if (error instanceof TypeError) {
    return new ApiError('network', 'Falha de rede ao contatar a Cloud_API.', { cause: error });
  }
  return new ApiError('unknown', 'Falha inesperada na requisição.', { cause: error });
}

/** O cliente HTTP exposto para os serviços por domínio (printersApi, etc.). */
export interface ApiClient {
  /** Executa um request e desserializa a resposta como `T` (JSON). */
  request<T>(path: string, options?: RequestOptions): Promise<T>;
  /** Base URL resolvida (útil para testes/diagnóstico). */
  readonly baseUrl: string;
}

/**
 * Cria um apiClient com as dependências injetadas (`getToken`, `onUnauthorized`).
 *
 * Uso típico (na tarefa 10.1, dentro do AuthContext):
 *   const client = createApiClient({ getToken, onUnauthorized: logout });
 */
export function createApiClient(
  deps: ApiClientDeps = {},
  baseUrl: string = env.cloudApiUrl,
): ApiClient {
  /**
   * Executa um único request com timeout, injetando `Bearer` quando `auth`, e
   * retornando `{ response, body }`. NÃO trata 401 aqui — isso é feito em `request`
   * para orquestrar o refresh/retry único.
   */
  async function doFetch(
    url: string,
    options: RequestOptions,
    forceRefreshToken: boolean,
  ): Promise<{ response: Response; body: unknown }> {
    const headers: Record<string, string> = { ...(options.headers ?? {}) };

    if (options.json !== undefined) {
      headers['Content-Type'] = 'application/json';
    }
    // Header opcional do Admin_Mode do estoque (Req 17.3). Tratado como segredo:
    // não é logado em nenhum ponto do cliente.
    if (options.adminCode !== undefined && options.adminCode !== '') {
      headers['x-admin-code'] = options.adminCode;
    }
    // Injeção do Bearer (Req 18): só quando autenticado e com `getToken` disponível.
    if (options.auth) {
      if (!deps.getToken) {
        throw new ApiError(
          'unknown',
          'Requisição autenticada sem provedor de token configurado (getToken).',
        );
      }
      const token = await deps.getToken(forceRefreshToken);
      headers['Authorization'] = `Bearer ${token}`;
    }

    const controller = new AbortController();
    const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
    const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
    const unlink = linkExternalSignal(controller, options.signal);

    try {
      const response = await fetch(url, {
        method: options.method ?? 'GET',
        headers,
        body: options.json !== undefined ? JSON.stringify(options.json) : undefined,
        signal: controller.signal,
      });
      const body = await readBody(response);
      return { response, body };
    } catch (error) {
      throw toApiError(error);
    } finally {
      clearTimeout(timeoutId);
      unlink();
    }
  }

  async function request<T>(path: string, options: RequestOptions = {}): Promise<T> {
    const url = applyQuery(joinUrl(baseUrl, path), options.query);

    // Primeira tentativa (token em cache quando autenticado).
    let { response, body } = await doFetch(url, options, false);

    // Tratamento de 401 em request autenticado: refresh do token e UMA repetição.
    if (response.status === 401 && options.auth && deps.getToken) {
      const retry = await doFetch(url, options, true); // getToken(true) → refresh
      response = retry.response;
      body = retry.body;

      if (response.status === 401) {
        // Persistiu 401 após o refresh → logout (Req 18.5, 12.8).
        await deps.onUnauthorized?.();
        throw new ApiError('http', 'Não autorizado (401) após renovar o token.', {
          status: 401,
          body,
        });
      }
    }

    if (!response.ok) {
      throw new ApiError('http', `Requisição falhou com status ${response.status}.`, {
        status: response.status,
        body,
      });
    }

    return body as T;
  }

  return { request, baseUrl };
}

/** Pausa `ms` milissegundos, cancelável por um `AbortSignal` externo. */
function delay(ms: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) {
      reject(toApiError(new DOMException('Aborted', 'AbortError')));
      return;
    }
    const id = setTimeout(() => {
      cleanup();
      resolve();
    }, ms);
    const onAbort = () => {
      cleanup();
      reject(toApiError(new DOMException('Aborted', 'AbortError')));
    };
    function cleanup() {
      clearTimeout(id);
      signal?.removeEventListener('abort', onAbort);
    }
    signal?.addEventListener('abort', onAbort);
  });
}

/**
 * Executa `fn` com retry de Cold_Start (Req 7.2–7.4): até `maxAttempts` tentativas
 * (default 3), aguardando `retryDelayMs` (default 10s) entre falhas. `perAttemptTimeoutMs`
 * (default 60s) é a janela esperada por tentativa — o timeout efetivo de cada request
 * é configurado por quem monta `fn` (via `RequestOptions.timeoutMs`).
 *
 * Reexecuta apenas em falhas transitórias de Cold_Start (timeout/rede). Erros HTTP de
 * status (ex.: 401/404/422) NÃO são retriados — são propagados imediatamente, pois não
 * representam "serviço inicializando". Esgotadas as tentativas, propaga o último erro.
 *
 * `signal` opcional permite cancelar a espera entre tentativas (ex.: desmontagem).
 */
export async function withColdStartRetry<T>(
  fn: () => Promise<T>,
  options: ColdStartOptions = {},
  signal?: AbortSignal,
): Promise<T> {
  const { maxAttempts, retryDelayMs } = { ...COLD_START_DEFAULTS, ...options };
  let lastError: unknown;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;

      // Só retriar falhas transitórias de Cold_Start (timeout/rede). HTTP propaga já.
      const apiError = error instanceof ApiError ? error : toApiError(error);
      const retriable = apiError.kind === 'timeout' || apiError.kind === 'network';
      if (!retriable || attempt === maxAttempts) {
        throw apiError;
      }
      await delay(retryDelayMs, signal);
    }
  }

  // Inatingível na prática (o loop sempre retorna ou lança), mas satisfaz o compilador.
  throw lastError instanceof ApiError ? lastError : toApiError(lastError);
}
