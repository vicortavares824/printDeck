/**
 * `usePolling` — hook de polling genérico do Dashboard.
 *
 * Atualiza dados em intervalos regulares (padrão de uso: 10s) garantindo NO
 * MÁXIMO 1 request simultânea e parando o polling ao desmontar o componente.
 * Cobre os critérios de aceitação da Requirement 5 (Req 5.1–5.6).
 *
 * Contrato (ver design.md, "usePolling (Req 5)"):
 *
 *   function usePolling<T>(
 *     fetcher: (signal: AbortSignal) => Promise<T>,
 *     opts: { intervalMs: number; enabled: boolean }
 *   ): { data: T | null; error: Error | null; isFetching: boolean };
 *
 * Regras:
 * - Dispara o `fetcher` a cada `intervalMs` (Req 5.1) e também IMEDIATAMENTE ao
 *   habilitar, sem esperar o primeiro intervalo — coerente com o uso nas páginas.
 * - Flag `inFlight` garante no máximo 1 request simultânea: se um tick ocorre
 *   enquanto um request está em andamento, o tick é SUPRIMIDO (Req 5.6).
 * - Em sucesso, substitui `data` e limpa `error` (Req 5.2, 5.3).
 * - Em falha/timeout/abort, MANTÉM o `data` anterior e seta `error` (Req 5.5).
 * - Cleanup do `useEffect` faz `clearInterval` + `abort()` do request em
 *   andamento, interrompendo o polling ao desmontar / ao desabilitar (Req 5.4).
 * - `enabled === false` impede novos ticks e para o polling.
 *
 * O `fetcher` recebe um `AbortSignal`: o `apiClient` usa esse signal para abortar
 * o request em andamento no cleanup e para aplicar seu próprio Polling_Timeout.
 */

import { useEffect, useRef, useState } from 'react';

/** Opções de configuração do polling. */
export interface UsePollingOptions {
  /** Intervalo entre ticks em milissegundos (uso padrão: 10_000). */
  intervalMs: number;
  /** Quando `false`, nenhum tick é disparado e o polling fica parado. */
  enabled: boolean;
}

/** Resultado reativo exposto pelo hook. */
export interface UsePollingResult<T> {
  /** Últimos dados recebidos com sucesso, ou `null` antes do primeiro sucesso. */
  data: T | null;
  /** Erro do último fetch que falhou, ou `null` após um sucesso. */
  error: Error | null;
  /** `true` enquanto há um request em andamento. */
  isFetching: boolean;
}

/**
 * Normaliza um valor arbitrário lançado por `fetcher` em uma instância de `Error`.
 * Promises podem rejeitar com qualquer valor; a UI espera sempre um `Error`.
 */
function toError(value: unknown): Error {
  return value instanceof Error ? value : new Error(String(value));
}

export function usePolling<T>(
  fetcher: (signal: AbortSignal) => Promise<T>,
  opts: UsePollingOptions,
): UsePollingResult<T> {
  const { intervalMs, enabled } = opts;

  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<Error | null>(null);
  const [isFetching, setIsFetching] = useState(false);

  /**
   * Guarda sempre a referência mais recente do `fetcher` sem reiniciar o efeito
   * de polling a cada render. As páginas podem passar um `fetcher` recriado em
   * todo render (closure sobre props); reiniciar o `setInterval` nesses casos
   * zeraria o relógio do intervalo. Em vez disso, lemos `fetcherRef.current`
   * dentro do tick, mantendo o intervalo estável e vinculado a `intervalMs`/`enabled`.
   */
  const fetcherRef = useRef(fetcher);
  fetcherRef.current = fetcher;

  useEffect(() => {
    if (!enabled) {
      // Desabilitado: nenhum tick, polling parado. (Req 5.4 — desabilitar para o polling)
      return;
    }

    // Garante no máximo 1 request simultânea. (Req 5.6)
    let inFlight = false;
    // AbortController do request em andamento, para abortá-lo no cleanup. (Req 5.4)
    let activeController: AbortController | null = null;
    // Evita atualizar state após o efeito ter sido limpo (desmontar/desabilitar).
    let cancelled = false;

    const runTick = () => {
      // Tick enquanto já há request em andamento é SUPRIMIDO. (Req 5.6)
      if (inFlight) return;

      inFlight = true;
      const controller = new AbortController();
      activeController = controller;

      if (!cancelled) setIsFetching(true);

      Promise.resolve()
        .then(() => fetcherRef.current(controller.signal))
        .then((result) => {
          if (cancelled || controller.signal.aborted) return;
          // Sucesso: substitui os dados e limpa o erro. (Req 5.2, 5.3)
          setData(result);
          setError(null);
        })
        .catch((err: unknown) => {
          if (cancelled || controller.signal.aborted) return;
          // Falha/timeout: mantém o `data` anterior e seta `error`. (Req 5.5)
          setError(toError(err));
        })
        .finally(() => {
          // Libera a flag mesmo quando abortado, para o próximo tick poder rodar.
          inFlight = false;
          if (activeController === controller) activeController = null;
          if (!cancelled && !controller.signal.aborted) setIsFetching(false);
        });
    };

    // Fetch imediato ao habilitar — não espera o primeiro intervalo.
    runTick();

    // Ticks subsequentes a cada Polling_Interval. (Req 5.1)
    const intervalId = setInterval(runTick, intervalMs);

    // Cleanup: para o polling e aborta o request em andamento. (Req 5.4)
    return () => {
      cancelled = true;
      clearInterval(intervalId);
      if (activeController !== null) activeController.abort();
    };
  }, [enabled, intervalMs]);

  return { data, error, isFetching };
}

export default usePolling;
