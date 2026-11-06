/**
 * JobHistoryList: exibe o Job_History (trabalhos concluídos/cancelados) de uma
 * impressora na visualização de detalhe (Req 6.2, 6.3, 6.4, 6.5).
 *
 * Comportamento (design.md → tabela de componentes "JobHistoryList"; Req 6):
 * - Busca o Job_History via `getJobHistory` (`GET /api/jobs/{printer_id}`, PÚBLICO —
 *   sem `Authorization`/`x-api-key`), por `usePolling` a cada Polling_Interval de 10s
 *   (Req 6.2). O histórico não exige polling agressivo, mas recarregar junto do status
 *   é inofensivo e mantém os dados frescos; o cleanup do hook aborta o request e para o
 *   polling ao sair do detalhe (Req 6.7).
 * - Para CADA item exibe `filename`, `status`, `print_duration_seconds`,
 *   `filament_used_grams`, `filament_material`, `filament_color` e `created_at`
 *   (Req 6.3).
 * - Histórico VAZIO (`[]`) → mensagem "não há histórico de jobs para essa impressora"
 *   (Req 6.4).
 * - Enquanto a primeira busca está em andamento e ainda não há dados em cache → exibe
 *   um indicador de carregamento (Req 6.5).
 * - Em falha de atualização, preserva os últimos dados exibidos e sinaliza a falha
 *   (coerente com o tratamento de erro do restante do Dashboard).
 *
 * Observação sobre o cliente: as leituras são públicas, então aceitamos o `ApiClient`
 * por parâmetro (injeção de dependência) e NÃO exigimos um cliente autenticado — o
 * detalhe reaproveita o mesmo cliente público usado para o status.
 */

import { useMemo } from 'react';

import type { ApiClient } from '../api/client';
import { getJobHistory } from '../api/printersApi';
import type { Job } from '../api/types';
import { usePolling } from '../hooks/usePolling';

/** Polling_Interval padrão do histórico: 10 segundos (recarrega junto do status). */
const POLLING_INTERVAL_MS = 10_000;

export interface JobHistoryListProps {
  /** Cliente (público) usado para `GET /api/jobs/{printer_id}`. */
  client: ApiClient;
  /** Impressora alvo cujo Job_History é exibido. */
  printerId: string;
}

/** Formata o `created_at` (ISO) de forma legível; mantém o cru se não for parseável. */
function formatCreatedAt(iso: string): string {
  if (iso === '') return '—';
  const parsed = new Date(iso);
  return Number.isNaN(parsed.getTime()) ? iso : parsed.toLocaleString();
}

/**
 * Formata a duração (segundos) de forma legível (h/min/s). Mantém valores inválidos
 * como "—" para não poluir a UI.
 */
function formatDuration(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds < 0) return '—';
  const total = Math.floor(seconds);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const parts: string[] = [];
  if (h > 0) parts.push(`${h}h`);
  if (m > 0) parts.push(`${m}min`);
  if (s > 0 || parts.length === 0) parts.push(`${s}s`);
  return parts.join(' ');
}

export default function JobHistoryList({ client, printerId }: JobHistoryListProps): JSX.Element {
  // Polling do Job_History (PÚBLICO) a cada Polling_Interval (Req 6.2). O cleanup do
  // hook aborta o request e para o polling ao desmontar o detalhe (Req 6.7).
  const { data, error, isFetching } = usePolling<Job[]>(
    (signal) => getJobHistory(client, printerId, signal),
    { intervalMs: POLLING_INTERVAL_MS, enabled: true },
  );

  // Ordena do mais recente para o mais antigo por `created_at` (sem mutar a entrada).
  const jobs = useMemo(() => {
    const list = data ?? [];
    return [...list].sort((a, b) => {
      const ta = Date.parse(a.created_at);
      const tb = Date.parse(b.created_at);
      if (Number.isNaN(ta) || Number.isNaN(tb)) return 0;
      return tb - ta;
    });
  }, [data]);

  return (
    <section className="job-history" aria-label={`Histórico de jobs da impressora ${printerId}`}>
      <header className="job-history__header">
        <h3 className="job-history__title">Histórico de jobs</h3>
        {isFetching && (
          <span className="job-history__refreshing" role="status" aria-live="polite">
            Atualizando…
          </span>
        )}
      </header>

      {/* CARREGAMENTO inicial: ainda não há dados em cache e não houve erro (Req 6.5). */}
      {data === null && error === null && (
        <p className="job-history__loading" role="status" aria-live="polite" aria-busy="true">
          Carregando o histórico de jobs…
        </p>
      )}

      {/* ERRO sem dados em cache. */}
      {data === null && error !== null && (
        <p className="job-history__error" role="alert">
          Não foi possível carregar o histórico de jobs.
        </p>
      )}

      {/* Falha ao ATUALIZAR preservando os últimos dados recebidos. */}
      {error !== null && data !== null && (
        <p className="job-history__stale" role="alert">
          Falha ao atualizar o histórico. Exibindo os últimos dados recebidos.
        </p>
      )}

      {/* Histórico VAZIO (Req 6.4). */}
      {data !== null && jobs.length === 0 && (
        <p className="job-history__empty">Não há histórico de jobs para essa impressora.</p>
      )}

      {/* Lista de jobs com os campos requeridos (Req 6.3). */}
      {jobs.length > 0 && (
        <ul className="job-history__list">
          {jobs.map((job) => (
            <li key={job.id} className="job-history__item">
              <div className="job-history__item-main">
                <span className="job-history__filename">{job.filename}</span>
                <span className="job-history__status" data-status={job.status}>
                  {job.status}
                </span>
              </div>
              <dl className="job-history__fields">
                <div>
                  <dt>Duração</dt>
                  <dd>{formatDuration(job.print_duration_seconds)}</dd>
                </div>
                <div>
                  <dt>Filamento usado</dt>
                  <dd>{job.filament_used_grams} g</dd>
                </div>
                <div>
                  <dt>Material</dt>
                  <dd>{job.filament_material ?? '—'}</dd>
                </div>
                <div>
                  <dt>Cor</dt>
                  <dd>{job.filament_color ?? '—'}</dd>
                </div>
                <div>
                  <dt>Concluído em</dt>
                  <dd>
                    <time dateTime={job.created_at}>{formatCreatedAt(job.created_at)}</time>
                  </dd>
                </div>
              </dl>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
