/**
 * PrinterListPage: lista/grid das impressoras da frota (Req 3, 4, 5, 10).
 *
 * Responsabilidades (design.md → "PrinterListPage"):
 * - Solicita os dados ao Printer_List_Endpoint via `getPrinters` (Req 3.1), atualizando
 *   por `usePolling` a cada Polling_Interval de 10s, com no máximo 1 request simultânea
 *   (Req 5.1, 5.6). O polling para ao desmontar (cleanup do hook — Req 5.4).
 * - Estados de UI:
 *     • CARREGAMENTO inicial (sem dados em cache, sem erro) → indicador de progresso
 *       (Req 3.6, 7.6).
 *     • VAZIO (lista `[]`) → mensagem "nenhuma impressora encontrada" (Req 3.7).
 *     • ERRO → mensagem de falha + ação de NOVA TENTATIVA, preservando os dados em
 *       cache quando existirem (Req 3.10, 7.1, 7.5).
 * - Renderiza `PrinterGrid` (um `PrinterCard` por impressora) e integra o `ModelFilter`
 *   (Req 3.2, 10): aplica o filtro à lista exibida; a cada polling recalcula as opções e,
 *   se o modelo selecionado sumir, reverte para "todas" (Req 10.7, 10.8).
 * - Reavalia frescor/Availability_State a cada Polling_Interval via um `nowMs` que
 *   acompanha os ticks (Req 4.4, 4.9).
 *
 * Observações de arquitetura:
 * - Usa um `apiClient` PÚBLICO (sem `getToken`): as leituras da lista são públicas
 *   (Req 1.10). NUNCA envia `x-api-key` (Req 8.7, 8.8).
 * - A "nova tentativa" remonta o bloco de polling (via `key`), o que dispara um fetch
 *   imediato — o `usePolling` executa um tick assim que habilitado.
 * - A reserva (tarefa 14.1) é um ponto de extensão opcional: `PrinterCard`/`PrinterGrid`
 *   aceitam `renderReservation`, mas esta página ainda não o injeta (não bloqueia o build).
 */

import { useEffect, useMemo, useState } from 'react';

import { createApiClient, type ApiClient } from '../api/client';
import { getPrinters } from '../api/printersApi';
import type { Printer } from '../api/types';
import ModelFilter, {
  applyModelFilter,
  deriveModelOptions,
  reconcileSelection,
  FILTER_ALL,
  type ModelFilterValue,
} from '../components/ModelFilter';
import PrinterGrid from '../components/PrinterGrid';
import { usePolling } from '../hooks/usePolling';

/** Polling_Interval padrão da lista: 10 segundos (Req 5.1). */
const POLLING_INTERVAL_MS = 10_000;

export default function PrinterListPage(): JSX.Element {
  // Cliente público (sem auth): as leituras da lista são públicas (Req 1.10).
  const client = useMemo<ApiClient>(() => createApiClient(), []);

  // Nonce de "nova tentativa": ao incrementar, remonta o bloco de polling e refaz o fetch.
  const [reloadNonce, setReloadNonce] = useState(0);

  return (
    <section className="printer-list" aria-label="Lista de impressoras">
      <PrinterListContent
        key={reloadNonce}
        client={client}
        onRetry={() => setReloadNonce((n) => n + 1)}
      />
    </section>
  );
}

interface PrinterListContentProps {
  client: ApiClient;
  onRetry: () => void;
}

/**
 * Conteúdo com o estado de polling. É um componente separado para que a "nova tentativa"
 * da página (troca de `key`) o remonte e dispare um novo fetch imediato.
 */
function PrinterListContent({ client, onRetry }: PrinterListContentProps): JSX.Element {
  const { data, error, isFetching } = usePolling<Printer[]>(
    (signal) => getPrinters(client, signal),
    { intervalMs: POLLING_INTERVAL_MS, enabled: true },
  );

  // Instante de referência para derivar frescor/disponibilidade; atualizado a cada tick
  // para reavaliar os indicadores ao longo do tempo (Req 4.4, 4.9).
  const [nowMs, setNowMs] = useState(() => Date.now());
  useEffect(() => {
    const id = setInterval(() => setNowMs(Date.now()), POLLING_INTERVAL_MS);
    return () => clearInterval(id);
  }, []);
  // Também atualiza o relógio quando chegam novos dados (substituição em <=1s — Req 5.2).
  useEffect(() => {
    if (data !== null) setNowMs(Date.now());
  }, [data]);

  // Seleção do Model_Filter (controlada pela página). Padrão: "todas" (Req 10.2).
  const [selected, setSelected] = useState<ModelFilterValue>(FILTER_ALL);

  const printers = data ?? [];
  const options = useMemo(() => deriveModelOptions(printers), [printers]);

  // Reconcilia a seleção a cada atualização de opções: se o modelo sumiu, volta a "todas"
  // (Req 10.7, 10.8). Mantém a seleção vigente aplicada enquanto ela existir.
  useEffect(() => {
    setSelected((current) => reconcileSelection(current, options));
  }, [options]);

  const visiblePrinters = useMemo(
    () => applyModelFilter(printers, selected),
    [printers, selected],
  );

  // CARREGAMENTO inicial: ainda não há dados em cache e não houve erro (Req 3.6, 7.6).
  if (data === null && error === null) {
    return (
      <div className="printer-list__loading" role="status" aria-live="polite" aria-busy="true">
        Carregando impressoras…
      </div>
    );
  }

  // ERRO sem dados em cache: mensagem + nova tentativa (Req 3.10, 7.1, 7.5).
  if (data === null && error !== null) {
    return (
      <div className="printer-list__error" role="alert">
        <p>Não foi possível carregar as impressoras.</p>
        <button type="button" className="btn btn--secondary" onClick={onRetry}>
          Tentar novamente
        </button>
      </div>
    );
  }

  return (
    <>
      <div className="printer-list__toolbar">
        <ModelFilter options={options} value={selected} onChange={setSelected} />
        {/* Indicador de falha de atualização preservando os dados em cache (Req 5.5, 7.1). */}
        {error !== null && (
          <div className="printer-list__stale-notice" role="alert">
            <span>Falha ao atualizar. Exibindo os últimos dados recebidos.</span>
            <button type="button" className="btn btn--secondary" onClick={onRetry}>
              Tentar novamente
            </button>
          </div>
        )}
        {isFetching && (
          <span className="printer-list__refreshing" role="status" aria-live="polite">
            Atualizando…
          </span>
        )}
      </div>

      {/* VAZIO: lista retornada sem impressoras (Req 3.7). */}
      {printers.length === 0 ? (
        <p className="printer-list__empty">Nenhuma impressora encontrada.</p>
      ) : (
        <PrinterGrid printers={visiblePrinters} nowMs={nowMs} />
      )}
    </>
  );
}
