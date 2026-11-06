/**
 * ReservationControls: controle de ocupar/liberar a reserva manual de uma impressora
 * (Req 12). Renderizado no rodapé do `PrinterCard` (via render prop `renderReservation`)
 * e também na visualização de detalhe (tarefa 15.1).
 *
 * Comportamento (design.md → "ReservationControls"; Req 12.1–12.10):
 * - Disponível / não reservada manualmente (`printer.reserved === false`): mostra o
 *   botão "Ocupar" (Req 12.1). Ao acionar, chama `reserve` enviando `reserved_by` = e-mail
 *   do Authenticated_User (`useAuth`), via `Authorization: Bearer`, sem `x-api-key` (Req 12.3).
 * - Ocupada por reserva manual (`printer.reserved === true`): mostra o botão "Liberar"
 *   (Req 12.2) e exibe `reserved_by` + `reserved_at` (Req 12.7). Ao acionar, chama
 *   `release` (Bearer, sem `x-api-key` — Req 12.5).
 * - Ocupada APENAS por telemetria `printing` (`reserved === false` mas o estado indica
 *   impressão): NÃO mostra o botão liberar (Req 12.10). Como não há reserva manual, a
 *   regra acima já cai no ramo "Ocupar"; portanto nunca exibimos "Liberar" sem reserva.
 *
 * Sucesso → dispara `onChanged()` para que a página releia o Reservation_State no próximo
 * ciclo (Req 12.4, 12.6, 12.9). Falha → mantém o estado anteriormente exibido e mostra uma
 * mensagem de erro (Req 12.8); eventuais corridas se resolvem no polling seguinte (Req 12.9).
 *
 * Este componente NÃO deriva estado localmente a partir do resultado: a verdade é o
 * Reservation_State vindo do polling. Por isso, em sucesso ele apenas pede um refresh
 * (`onChanged`) e deixa o card refletir o novo estado — evitando divergência entre o
 * otimismo local e o estado compartilhado.
 */

import { useCallback, useState } from 'react';

import { useApiClient } from '../api/useApiClient';
import { release, reserve } from '../api/reservationApi';
import type { Printer } from '../api/types';
import { useAuth } from '../auth/AuthContext';

export interface ReservationControlsProps {
  /** Impressora alvo; `reserved`/`reserved_by`/`reserved_at` vêm do Reservation_State. */
  printer: Printer;
  /**
   * Chamado após uma operação de ocupar/liberar bem-sucedida para que a página releia
   * o estado (ex.: forçar um tick de polling ou refetch). Opcional.
   */
  onChanged?: () => void;
}

/** Formata o `reserved_at` (ISO) de forma legível; mantém o cru se não for parseável. */
function formatReservedAt(iso: string | null): string {
  if (iso === null || iso === '') return '—';
  const parsed = new Date(iso);
  return Number.isNaN(parsed.getTime()) ? iso : parsed.toLocaleString();
}

export default function ReservationControls({
  printer,
  onChanged,
}: ReservationControlsProps): JSX.Element {
  const client = useApiClient();
  const { user } = useAuth();

  // `pending` desabilita o botão enquanto a chamada está em andamento (evita cliques
  // duplos). `error` guarda a mensagem a exibir quando a operação falha (Req 12.8).
  const [pending, setPending] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  const handleReserve = useCallback(async () => {
    const email = user?.email ?? '';
    if (email === '') {
      // Sem e-mail no usuário autenticado não há como preencher `reserved_by` (Req 12.3).
      setError('Não foi possível identificar o e-mail do usuário para ocupar a impressora.');
      return;
    }
    setPending(true);
    setError(null);
    try {
      await reserve(client, printer.printer_id, email);
      // Sucesso: não mutamos estado local; pedimos o refresh e deixamos o polling refletir
      // o Reservation_State (Req 12.4, 12.9).
      onChanged?.();
    } catch {
      // Mantém o estado anteriormente exibido e mostra a mensagem (Req 12.8).
      setError('Falha ao ocupar a impressora. Tente novamente.');
    } finally {
      setPending(false);
    }
  }, [client, onChanged, printer.printer_id, user]);

  const handleRelease = useCallback(async () => {
    setPending(true);
    setError(null);
    try {
      await release(client, printer.printer_id);
      onChanged?.(); // Req 12.6, 12.9
    } catch {
      setError('Falha ao liberar a impressora. Tente novamente.'); // Req 12.8
    } finally {
      setPending(false);
    }
  }, [client, onChanged, printer.printer_id]);

  return (
    <div className="reservation-controls">
      {printer.reserved ? (
        // Ocupada por reserva MANUAL: exibe quem ocupou/quando e o botão liberar (Req 12.2, 12.7).
        <>
          <p className="reservation-controls__info">
            Ocupada por <strong>{printer.reserved_by ?? '—'}</strong> desde{' '}
            <time dateTime={printer.reserved_at ?? undefined}>
              {formatReservedAt(printer.reserved_at)}
            </time>
          </p>
          <button
            type="button"
            className="btn btn--secondary reservation-controls__release"
            onClick={handleRelease}
            disabled={pending}
          >
            {pending ? 'Liberando…' : 'Liberar'}
          </button>
        </>
      ) : (
        // Não reservada manualmente (mesmo que `printing`, sem reserva): mostra apenas
        // "Ocupar"; nunca "Liberar" sem reserva manual (Req 12.1, 12.10).
        <button
          type="button"
          className="btn btn--primary reservation-controls__reserve"
          onClick={handleReserve}
          disabled={pending}
        >
          {pending ? 'Ocupando…' : 'Ocupar'}
        </button>
      )}

      {error !== null && (
        <p className="reservation-controls__error" role="alert">
          {error}
        </p>
      )}
    </div>
  );
}
