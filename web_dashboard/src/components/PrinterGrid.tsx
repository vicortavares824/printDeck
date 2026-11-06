/**
 * PrinterGrid: grid de `PrinterCard`s (Req 3.2).
 *
 * Renderiza um `PrinterCard` por impressora recebida (já filtrada pela página via
 * `applyModelFilter`). Encaminha `nowMs` (para reavaliar frescor/disponibilidade a cada
 * Polling_Interval — Req 4.4, 4.9) e o render prop opcional de reserva (ponto de extensão
 * da tarefa 14.1) a cada card.
 *
 * Os estados de carregamento/vazio/erro NÃO são tratados aqui: são responsabilidade da
 * `PrinterListPage`. Este componente só desenha o grid dos dados que recebe.
 */

import type { ReactNode } from 'react';

import type { Printer } from '../api/types';
import PrinterCard from './PrinterCard';

export interface PrinterGridProps {
  /** Impressoras a renderizar (já filtradas pelo Model_Filter). */
  printers: Printer[];
  /** Instante de referência (epoch ms) para derivar frescor/disponibilidade por card. */
  nowMs: number;
  /** Ponto de extensão opcional de reserva (tarefa 14.1), repassado a cada card. */
  renderReservation?: (printer: Printer) => ReactNode;
}

export default function PrinterGrid({
  printers,
  nowMs,
  renderReservation,
}: PrinterGridProps): JSX.Element {
  return (
    <div className="printer-grid" role="list">
      {printers.map((printer) => (
        <div className="printer-grid__item" role="listitem" key={printer.printer_id}>
          <PrinterCard printer={printer} nowMs={nowMs} renderReservation={renderReservation} />
        </div>
      ))}
    </div>
  );
}
