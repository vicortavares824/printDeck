/**
 * PrinterCard: cartão de uma impressora na lista/grid (Req 3.2–3.5, 4.x).
 *
 * Exibe, para uma impressora:
 * - `printer_id`, `state`, `progress`, `current_file`, `nozzle_temp`, `bed_temp`,
 *   informação de filamento (tipo + quantidade restante), `created_at` e `model`
 *   (ou o rótulo "sem modelo" quando nulo) — Req 3.3, 3.4, 3.5.
 * - Indicador de FRESCOR persistente: "atualizado" / "desatualizado" / "offline",
 *   derivado por `deriveFreshness` (Req 4.1, 4.2, 4.3, 4.5).
 * - Indicador de AVAILABILITY_STATE verde/vermelho derivado por `deriveAvailability`,
 *   com rótulo textual "Impressora X — disponível/ocupado" (Req 4.6, 4.7, 4.8).
 * - Navegação para o detalhe da impressora (`/printers/:id`) — Req 6.1.
 *
 * As cores seguem o tema (design.md → "Identidade Visual"): o Availability_State usa os
 * tokens semânticos `--color-available` (verde) / `--color-unavailable` (vermelho), que
 * NÃO são substituídos pelo azul de marca. O estado também é comunicado por TEXTO (não
 * depende só de cor), atendendo à acessibilidade.
 *
 * Ponto de extensão de RESERVA (tarefa 14.1): o card aceita um render prop opcional
 * `renderReservation` que recebe a impressora e devolve o controle de reserva
 * (`ReservationControls`). Assim o card não importa um componente ainda inexistente e o
 * build não quebra; quando a 14.1 estiver pronta, a lista injeta o controle por aqui.
 */

import type { ReactNode } from 'react';
import { Link } from 'react-router-dom';

import type { Printer } from '../api/types';
import {
  deriveAvailability,
  deriveFreshness,
  type Availability,
  type Freshness,
} from '../lib/availability';

/** Rótulos legíveis do estado de frescor (Req 4.1–4.3, 4.5). */
const FRESHNESS_LABEL: Record<Freshness, string> = {
  fresh: 'Atualizado',
  stale: 'Desatualizado',
  offline: 'Offline',
};

/** Rótulo textual do Availability_State no cartão (Req 4.8). */
const AVAILABILITY_LABEL: Record<Availability, string> = {
  disponivel: 'disponível',
  indisponivel: 'ocupado',
};

/** Formata o `created_at` (ISO) de forma legível; mantém o cru se não for parseável. */
function formatTimestamp(iso: string): string {
  const parsed = new Date(iso);
  return Number.isNaN(parsed.getTime()) ? iso : parsed.toLocaleString();
}

/** Texto do filamento: tipo/material + quantidade restante (Req 3.3). */
function formatFilament(printer: Printer): string {
  const info = printer.filament_info;
  if (info === null || info === undefined) return '—';
  const material = info.material ?? 'desconhecido';
  const remaining =
    info.remaining_weight_grams === null || info.remaining_weight_grams === undefined
      ? '—'
      : `${info.remaining_weight_grams} g`;
  return `${material} · ${remaining} restante`;
}

export interface PrinterCardProps {
  /** Impressora a exibir. */
  printer: Printer;
  /**
   * Instante de referência (epoch ms) para derivar frescor/disponibilidade. A página
   * atualiza este valor a cada Polling_Interval para reavaliar os indicadores (Req 4.4, 4.9).
   */
  nowMs: number;
  /**
   * Ponto de extensão opcional para o controle de reserva (tarefa 14.1). Quando fornecido,
   * seu retorno é renderizado no rodapé do card.
   */
  renderReservation?: (printer: Printer) => ReactNode;
}

export default function PrinterCard({
  printer,
  nowMs,
  renderReservation,
}: PrinterCardProps): JSX.Element {
  const freshness = deriveFreshness(printer, nowMs);
  const availability = deriveAvailability(printer, nowMs);

  const availabilityLabel = AVAILABILITY_LABEL[availability];
  // Rótulo textual "Impressora X — disponível/ocupado" (Req 4.8).
  const statusLabel = `Impressora ${printer.printer_id} — ${availabilityLabel}`;
  const modelLabel = printer.model ?? 'sem modelo'; // Req 3.5

  return (
    <article
      className="printer-card"
      data-availability={availability}
      data-freshness={freshness}
      aria-label={statusLabel}
    >
      <header className="printer-card__header">
        <h3 className="printer-card__title">
          <Link to={`/printers/${encodeURIComponent(printer.printer_id)}`}>
            Impressora {printer.printer_id}
          </Link>
        </h3>

        {/* Availability_State: cor semântica + texto (não depende só de cor). Req 4.6–4.8 */}
        <span
          className="printer-card__availability"
          data-availability={availability}
          role="status"
        >
          {availabilityLabel}
        </span>
      </header>

      {/* Indicador de frescor persistente, distinguível entre os três estados (Req 4.1–4.3, 4.5). */}
      <p className="printer-card__freshness" data-freshness={freshness}>
        {FRESHNESS_LABEL[freshness]}
      </p>

      <dl className="printer-card__fields">
        <div>
          <dt>Modelo</dt>
          <dd>{modelLabel}</dd>
        </div>
        <div>
          <dt>Estado</dt>
          <dd>{printer.state}</dd>
        </div>
        <div>
          <dt>Progresso</dt>
          <dd>{printer.progress}%</dd>
        </div>
        <div>
          <dt>Arquivo atual</dt>
          <dd>{printer.current_file ?? '—'}</dd>
        </div>
        <div>
          <dt>Bico</dt>
          <dd>{printer.nozzle_temp} °C</dd>
        </div>
        <div>
          <dt>Mesa</dt>
          <dd>{printer.bed_temp} °C</dd>
        </div>
        <div>
          <dt>Filamento</dt>
          <dd>{formatFilament(printer)}</dd>
        </div>
        <div>
          <dt>Atualizado em</dt>
          <dd>
            <time dateTime={printer.created_at}>{formatTimestamp(printer.created_at)}</time>
          </dd>
        </div>
      </dl>

      {renderReservation !== undefined && (
        <footer className="printer-card__reservation">{renderReservation(printer)}</footer>
      )}
    </article>
  );
}
