/**
 * PrinterDetailPage: visualização de detalhe de uma impressora (Req 6, 12, 14).
 *
 * Responsabilidades (design.md → tabela de componentes "PrinterDetailPage"; Req 6.x):
 * - Obtém o `printerId` da rota via `useParams` (react-router) — Req 6.1.
 * - Exibe o STATUS atual da impressora obtido por `getLatestTelemetry`
 *   (`GET /api/telemetry/latest/{printer_id}`, PÚBLICO), por `usePolling` a cada
 *   Polling_Interval de 10s (Req 6.6), com no máximo 1 request simultânea. O polling
 *   para ao sair do detalhe (cleanup do hook — Req 6.7).
 * - Reaproveita o `PrinterCard` para renderizar os campos de status e os indicadores de
 *   frescor/Availability_State (Req 3.3–3.5, 4.x), evitando duplicar a composição.
 * - Integra `ReservationControls` (ocupar/liberar) passando a impressora; exibe
 *   `reserved_by`/`reserved_at` quando reservada (Req 6.8, 6.9, 12.x). O sucesso de uma
 *   reserva dispara `onChanged`, que força uma releitura IMEDIATA do status (remontando
 *   o bloco de polling por `key`), para o detalhe refletir o novo Reservation_State sem
 *   esperar o próximo tick.
 * - Integra `PrintQueuePanel` (fila compartilhada por `printerId`) — Req 14.x.
 * - Integra `JobHistoryList` (histórico de jobs) — Req 6.2–6.5.
 * - Trata CARREGAMENTO inicial e ERRO do status, preservando os dados em cache quando
 *   existirem e oferecendo nova tentativa (coerente com `PrinterListPage`).
 *
 * Observações de arquitetura:
 * - Usa um `apiClient` PÚBLICO (via `createApiClient`, sem `getToken`) para o status e o
 *   Job_History — ambas leituras públicas (Req 1.10). NUNCA envia `x-api-key` (Req 8.7,
 *   8.8). As ESCRITAS de reserva/fila vivem em `ReservationControls`/`PrintQueuePanel`,
 *   que montam seu próprio cliente autenticado via `useApiClient`.
 * - A releitura imediata do status após uma reserva segue o mesmo padrão de "nova
 *   tentativa" da lista: incrementar um nonce remonta o conteúdo de polling, disparando
 *   um fetch imediato (o `usePolling` executa um tick assim que habilitado).
 */

import { useCallback, useEffect, useMemo, useState } from 'react';
import { Link, useParams } from 'react-router-dom';

import { createApiClient, type ApiClient } from '../api/client';
import { getLatestTelemetry } from '../api/printersApi';
import type { Printer } from '../api/types';
import JobHistoryList from '../components/JobHistoryList';
import PrinterCard from '../components/PrinterCard';
import PrintQueuePanel from '../components/PrintQueuePanel';
import ReservationControls from '../components/ReservationControls';
import { usePolling } from '../hooks/usePolling';

/** Polling_Interval padrão do status no detalhe: 10 segundos (Req 6.6). */
const POLLING_INTERVAL_MS = 10_000;

export default function PrinterDetailPage(): JSX.Element {
  // `printerId` da rota `/printers/:id` (Req 6.1).
  const { id } = useParams<{ id: string }>();
  const printerId = id ?? '';

  // Cliente público (sem auth): status e Job_History são leituras públicas (Req 1.10).
  const client = useMemo<ApiClient>(() => createApiClient(), []);

  // Nonce de releitura: ao incrementar (após uma reserva bem-sucedida ou "nova
  // tentativa"), remonta o conteúdo de status e dispara um fetch imediato.
  const [reloadNonce, setReloadNonce] = useState(0);
  const reload = useCallback(() => setReloadNonce((n) => n + 1), []);

  // `printer_id` ausente na rota: estado defensivo (não deveria ocorrer com a rota correta).
  if (printerId === '') {
    return (
      <section className="printer-detail" aria-label="Detalhe da impressora">
        <p className="printer-detail__error" role="alert">
          Impressora não especificada.
        </p>
        <Link to="/">Voltar para a lista</Link>
      </section>
    );
  }

  return (
    <section className="printer-detail" aria-label={`Detalhe da impressora ${printerId}`}>
      <header className="printer-detail__header">
        <Link to="/" className="printer-detail__back">
          ← Voltar para a lista
        </Link>
        <h2 className="printer-detail__title">Impressora {printerId}</h2>
      </header>

      {/* STATUS atual com polling. Remontado por `key` para releitura imediata. */}
      <PrinterStatus
        key={reloadNonce}
        client={client}
        printerId={printerId}
        onReservationChanged={reload}
        onRetry={reload}
      />

      {/* Fila de impressão compartilhada (Req 14). Monta seu próprio cliente autenticado. */}
      <PrintQueuePanel printerId={printerId} />

      {/* Histórico de jobs (Req 6.2–6.5), leitura pública pelo cliente injetado. */}
      <JobHistoryList client={client} printerId={printerId} />
    </section>
  );
}

interface PrinterStatusProps {
  client: ApiClient;
  printerId: string;
  /** Chamado quando a reserva muda com sucesso: força a releitura imediata do status. */
  onReservationChanged: () => void;
  /** Nova tentativa após erro de carregamento do status. */
  onRetry: () => void;
}

/**
 * Conteúdo do STATUS com o estado de polling. Separado para que a releitura imediata
 * (troca de `key` no pai) o remonte e dispare um fetch imediato — refletindo o novo
 * Reservation_State logo após uma reserva (Req 6.8, 12.4, 12.9).
 */
function PrinterStatus({
  client,
  printerId,
  onReservationChanged,
  onRetry,
}: PrinterStatusProps): JSX.Element {
  // Polling do status (PÚBLICO) a cada Polling_Interval (Req 6.6). O cleanup do hook
  // aborta o request e para o polling ao sair do detalhe (Req 6.7).
  const { data, error, isFetching } = usePolling<Printer>(
    (signal) => getLatestTelemetry(client, printerId, signal),
    { intervalMs: POLLING_INTERVAL_MS, enabled: true },
  );

  // Instante de referência para derivar frescor/disponibilidade no card; atualizado a
  // cada tick e quando chegam novos dados (Req 4.4, 4.9).
  const [nowMs, setNowMs] = useState(() => Date.now());
  useEffect(() => {
    const intervalId = setInterval(() => setNowMs(Date.now()), POLLING_INTERVAL_MS);
    return () => clearInterval(intervalId);
  }, []);
  useEffect(() => {
    if (data !== null) setNowMs(Date.now());
  }, [data]);

  // CARREGAMENTO inicial: ainda não há dados em cache e não houve erro (Req 6.5-análogo).
  if (data === null && error === null) {
    return (
      <div
        className="printer-detail__status printer-detail__status--loading"
        role="status"
        aria-live="polite"
        aria-busy="true"
      >
        Carregando o status da impressora…
      </div>
    );
  }

  // ERRO sem dados em cache: mensagem + nova tentativa.
  if (data === null && error !== null) {
    return (
      <div className="printer-detail__status printer-detail__status--error" role="alert">
        <p>Não foi possível carregar o status da impressora.</p>
        <button type="button" className="btn btn--secondary" onClick={onRetry}>
          Tentar novamente
        </button>
      </div>
    );
  }

  // A partir daqui `data` é um `Printer` (não nulo).
  const printer = data as Printer;

  return (
    <div className="printer-detail__status">
      {/* Falha ao ATUALIZAR o status preservando os últimos dados (Req 7.1). */}
      {error !== null && (
        <div className="printer-detail__stale-notice" role="alert">
          <span>Falha ao atualizar o status. Exibindo os últimos dados recebidos.</span>
          <button type="button" className="btn btn--secondary" onClick={onRetry}>
            Tentar novamente
          </button>
        </div>
      )}
      {isFetching && (
        <span className="printer-detail__refreshing" role="status" aria-live="polite">
          Atualizando…
        </span>
      )}

      {/* Reaproveita o PrinterCard para o status + indicadores; injeta a reserva no rodapé.
          O sucesso da reserva força a releitura imediata do status (Req 6.8, 6.9, 12.x). */}
      <PrinterCard
        printer={printer}
        nowMs={nowMs}
        renderReservation={(p) => (
          <ReservationControls printer={p} onChanged={onReservationChanged} />
        )}
      />
    </div>
  );
}
