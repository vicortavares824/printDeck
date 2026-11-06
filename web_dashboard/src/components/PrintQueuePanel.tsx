/**
 * PrintQueuePanel: exibe e gerencia a Print_Queue compartilhada de uma impressora
 * (Req 14). Renderizado na visualização de detalhe da impressora (tarefa 15.1), que
 * passa o `printerId`.
 *
 * Comportamento (design.md → "PrintQueuePanel"; Req 14.1–14.13):
 * - Lê a fila via `getQueue` (PÚBLICO) por `usePolling` a cada Polling_Interval de 10s,
 *   refletindo mudanças feitas por outros Authenticated_Users na fila compartilhada
 *   (Req 14.1, 14.11). Exibe os Queue_Items ordenados por `position` ascendente e
 *   DESTACA o de menor `position` como o PRÓXIMO a imprimir (Req 14.2). Mostra `sku` e
 *   `name` de cada item (Req 14.3).
 * - ADICIONAR (Req 14.4–14.6): inputs de `sku` (obrigatório, com validação local — sku
 *   vazio bloqueia e não chama a API, Req 14.5) e `name`. Envia `created_by` = e-mail do
 *   Authenticated_User (`useAuth`), autenticado por Bearer, sem `x-api-key` (Req 14.6).
 * - REORDENAR (Req 14.7): mover um item para cima/baixo, calculando a nova ordem de `id`
 *   e chamando `reorder` com essa lista (Bearer, sem `x-api-key`).
 * - REMOVER (Req 14.8) e MARCAR IMPRESSO (Req 14.9): chamam `remove`/`markPrinted`
 *   (Bearer, sem `x-api-key`), removendo o item da fila ativa.
 * - Após CADA operação bem-sucedida, relê a fila (Req 14.10); o polling também resolve
 *   eventuais divergências/corridas no próximo ciclo (Req 14.11, 14.12).
 * - Em FALHA de escrita, mostra uma mensagem de erro e MANTÉM o estado coerente exibido;
 *   a divergência se resolve na releitura do polling seguinte (Req 14.12).
 *
 * Escopo: esta entrega gerencia apenas os metadados do Queue_Item (`sku`, `name`, ordem).
 * O anexo/upload de arquivo (`.gcode` como tipo principal; `.3mf`/`.stl` opcionais) é
 * funcionalidade FUTURA, fora do escopo (Req 14.13) — exibida como nota/placeholder.
 *
 * Usa o `apiClient` AUTENTICADO (`useApiClient`) para as escritas; a leitura pública
 * reaproveita o mesmo cliente (o GET não envia `Authorization`/`x-api-key`).
 *
 * Arquitetura de releitura: o conteúdo com o polling vive em `PrintQueueContent`,
 * remontado por uma `key` (`reloadNonce`) sempre que uma escrita bem-sucedida precisa de
 * um refetch imediato — espelhando o padrão de "nova tentativa" de `PrinterListPage`.
 */

import { useCallback, useMemo, useState } from 'react';

import type { ApiClient } from '../api/client';
import { useApiClient } from '../api/useApiClient';
import {
  addItem,
  getQueue,
  markPrinted,
  remove,
  reorder,
} from '../api/queueApi';
import type { QueueItem } from '../api/types';
import { useAuth } from '../auth/AuthContext';
import { usePolling } from '../hooks/usePolling';

/** Polling_Interval padrão da fila: 10 segundos (Req 14.11). */
const POLLING_INTERVAL_MS = 10_000;

export interface PrintQueuePanelProps {
  /** Impressora alvo cuja Print_Queue é exibida/gerenciada (identificada por `printer_id`). */
  printerId: string;
}

/** Ordena uma cópia dos itens por `position` ascendente (não muta a entrada — Req 14.1). */
function sortByPosition(items: QueueItem[]): QueueItem[] {
  return [...items].sort((a, b) => a.position - b.position);
}

/** Formata o `created_at` (ISO) de forma legível; mantém o cru se não for parseável. */
function formatCreatedAt(iso: string): string {
  if (iso === '') return '—';
  const parsed = new Date(iso);
  return Number.isNaN(parsed.getTime()) ? iso : parsed.toLocaleString();
}

export default function PrintQueuePanel({ printerId }: PrintQueuePanelProps): JSX.Element {
  // Cliente AUTENTICADO para as escritas; o GET público reaproveita o mesmo cliente
  // (a leitura não envia `Authorization`/`x-api-key`).
  const client = useApiClient();

  // Nonce de releitura: ao incrementar após uma operação bem-sucedida, remonta o
  // `PrintQueueContent` (via `key`) e dispara um novo fetch imediato (Req 14.10).
  const [reloadNonce, setReloadNonce] = useState(0);
  const reload = useCallback(() => setReloadNonce((n) => n + 1), []);

  return (
    <section className="print-queue" aria-label={`Fila de impressão da impressora ${printerId}`}>
      <PrintQueueContent
        key={reloadNonce}
        client={client}
        printerId={printerId}
        onReload={reload}
      />
    </section>
  );
}

interface PrintQueueContentProps {
  client: ApiClient;
  printerId: string;
  /** Pede uma releitura imediata da fila (remonta este conteúdo). */
  onReload: () => void;
}

/**
 * Conteúdo com o estado de polling da fila. Separado para que a releitura pós-operação
 * (troca de `key` no pai) o remonte e dispare um fetch imediato (Req 14.10).
 */
function PrintQueueContent({
  client,
  printerId,
  onReload,
}: PrintQueueContentProps): JSX.Element {
  const { user } = useAuth();

  // Polling da fila (PÚBLICO) a cada Polling_Interval (Req 14.1, 14.11). O cleanup do
  // hook aborta o request e para o polling ao desmontar o painel/remontar o conteúdo.
  const { data, error, isFetching } = usePolling<QueueItem[]>(
    (signal) => getQueue(client, printerId, signal),
    { intervalMs: POLLING_INTERVAL_MS, enabled: true },
  );

  // Campos do formulário de adicionar (Req 14.4).
  const [sku, setSku] = useState('');
  const [name, setName] = useState('');
  // Mensagem de validação local do `sku` (Req 14.5).
  const [validationError, setValidationError] = useState<string | null>(null);
  // Mensagem de erro de uma operação de escrita que falhou (Req 14.12).
  const [opError, setOpError] = useState<string | null>(null);
  // Desabilita os controles enquanto uma escrita está em andamento (evita cliques duplos).
  const [pending, setPending] = useState(false);

  const items = useMemo(() => sortByPosition(data ?? []), [data]);

  /**
   * Executa uma operação de escrita tratando `pending`/erro de forma uniforme e, em
   * sucesso, pedindo a releitura da fila (Req 14.10, 14.12). Não muta estado local da
   * fila: a verdade é o que o polling/releitura traz (evita divergência otimista).
   */
  const runWrite = useCallback(
    async (op: () => Promise<unknown>, errorMsg: string): Promise<boolean> => {
      setPending(true);
      setOpError(null);
      try {
        await op();
        onReload(); // releitura imediata para refletir a fila atualizada (Req 14.10).
        return true;
      } catch {
        // Mantém o estado coerente exibido; a divergência se resolve no próximo polling
        // (Req 14.12).
        setOpError(errorMsg);
        return false;
      } finally {
        setPending(false);
      }
    },
    [onReload],
  );

  const handleAdd = useCallback(async () => {
    // Validação local: `sku` vazio bloqueia e NÃO chama a API (Req 14.5).
    const trimmedSku = sku.trim();
    if (trimmedSku === '') {
      setValidationError('Informe o SKU do item (campo obrigatório).');
      return;
    }
    setValidationError(null);

    const email = user?.email ?? null;
    const ok = await runWrite(
      () =>
        addItem(client, printerId, {
          sku: trimmedSku,
          name: name.trim(),
          created_by: email, // o backend prefere o e-mail do token (Req 13.5).
        }),
      'Falha ao adicionar o item à fila. Tente novamente.',
    );
    if (ok) {
      // Limpa o formulário apenas quando a adição foi aceita.
      setSku('');
      setName('');
    }
  }, [client, name, printerId, runWrite, sku, user]);

  const handleRemove = useCallback(
    (itemId: number) =>
      runWrite(
        () => remove(client, printerId, itemId),
        'Falha ao remover o item da fila. Tente novamente.',
      ),
    [client, printerId, runWrite],
  );

  const handleMarkPrinted = useCallback(
    (itemId: number) =>
      runWrite(
        () => markPrinted(client, printerId, itemId),
        'Falha ao marcar o item como impresso. Tente novamente.',
      ),
    [client, printerId, runWrite],
  );

  /**
   * Move o item do índice `index` uma posição para cima/baixo e chama `reorder` com a
   * nova ordem de `id` (Req 14.7). A lista enviada contém TODOS os `id` da fila atual
   * (o backend exige que o conjunto bata exatamente — Req 13.15).
   */
  const handleMove = useCallback(
    (index: number, direction: -1 | 1): Promise<boolean> | void => {
      const target = index + direction;
      if (target < 0 || target >= items.length) return; // nada a mover nas bordas.
      const orderedIds = items.map((item) => item.id);
      // Troca os dois vizinhos na nova ordem.
      [orderedIds[index], orderedIds[target]] = [orderedIds[target], orderedIds[index]];
      return runWrite(
        () => reorder(client, printerId, orderedIds),
        'Falha ao reordenar a fila. Tente novamente.',
      );
    },
    [client, items, printerId, runWrite],
  );

  return (
    <>
      <header className="print-queue__header">
        <h3 className="print-queue__title">Fila de impressão</h3>
        {isFetching && (
          <span className="print-queue__refreshing" role="status" aria-live="polite">
            Atualizando…
          </span>
        )}
      </header>

      {/* Formulário de adicionar (Req 14.4–14.6). */}
      <form
        className="print-queue__add"
        onSubmit={(e) => {
          e.preventDefault();
          void handleAdd();
        }}
      >
        <label className="print-queue__field">
          <span>SKU</span>
          <input
            type="text"
            value={sku}
            onChange={(e) => setSku(e.target.value)}
            placeholder="SKU (obrigatório)"
            aria-invalid={validationError !== null}
            disabled={pending}
          />
        </label>
        <label className="print-queue__field">
          <span>Nome</span>
          <input
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Nome (opcional)"
            disabled={pending}
          />
        </label>
        <button type="submit" className="btn btn--primary" disabled={pending}>
          {pending ? 'Adicionando…' : 'Adicionar'}
        </button>
      </form>

      {/* Validação local do `sku` (Req 14.5). */}
      {validationError !== null && (
        <p className="print-queue__validation" role="alert">
          {validationError}
        </p>
      )}

      {/* Erro de operação de escrita, mantendo o estado exibido (Req 14.12). */}
      {opError !== null && (
        <p className="print-queue__error" role="alert">
          {opError}
        </p>
      )}

      {/* Falha ao ATUALIZAR a fila (polling), preservando os últimos dados (Req 14.12). */}
      {error !== null && data !== null && (
        <p className="print-queue__stale" role="alert">
          Falha ao atualizar a fila. Exibindo os últimos dados recebidos.
        </p>
      )}

      {/* CARREGAMENTO inicial: sem dados em cache e sem erro. */}
      {data === null && error === null && (
        <p className="print-queue__loading" role="status" aria-live="polite" aria-busy="true">
          Carregando a fila…
        </p>
      )}

      {/* ERRO sem dados em cache. */}
      {data === null && error !== null && (
        <p className="print-queue__error" role="alert">
          Não foi possível carregar a fila de impressão.
        </p>
      )}

      {/* Fila VAZIA (Req 13.3). */}
      {data !== null && items.length === 0 && (
        <p className="print-queue__empty">A fila de impressão está vazia.</p>
      )}

      {/* Lista ordenada por `position`, destacando o PRÓXIMO (menor position — Req 14.2). */}
      {items.length > 0 && (
        <ol className="print-queue__list">
          {items.map((item, index) => {
            const isNext = index === 0; // já ordenado por position asc → o menor é o próximo.
            return (
              <li
                key={item.id}
                className={
                  isNext ? 'print-queue__item print-queue__item--next' : 'print-queue__item'
                }
                aria-current={isNext ? 'true' : undefined}
              >
                <div className="print-queue__item-main">
                  {isNext && <span className="print-queue__badge">Próximo</span>}
                  <span className="print-queue__sku">{item.sku}</span>
                  {item.name !== '' && <span className="print-queue__name">{item.name}</span>}
                  <span className="print-queue__meta">
                    #{item.position}
                    {item.created_by !== null && item.created_by !== '' && (
                      <> · por {item.created_by}</>
                    )}{' '}
                    · {formatCreatedAt(item.created_at)}
                  </span>
                </div>
                <div className="print-queue__item-actions">
                  <button
                    type="button"
                    className="btn btn--secondary"
                    onClick={() => void handleMove(index, -1)}
                    disabled={pending || index === 0}
                    aria-label={`Mover ${item.sku} para cima`}
                  >
                    ↑
                  </button>
                  <button
                    type="button"
                    className="btn btn--secondary"
                    onClick={() => void handleMove(index, 1)}
                    disabled={pending || index === items.length - 1}
                    aria-label={`Mover ${item.sku} para baixo`}
                  >
                    ↓
                  </button>
                  <button
                    type="button"
                    className="btn btn--secondary"
                    onClick={() => void handleMarkPrinted(item.id)}
                    disabled={pending}
                  >
                    Marcar impresso
                  </button>
                  <button
                    type="button"
                    className="btn btn--secondary"
                    onClick={() => void handleRemove(item.id)}
                    disabled={pending}
                  >
                    Remover
                  </button>
                </div>
              </li>
            );
          })}
        </ol>
      )}

      {/* Nota/placeholder: anexo de arquivo é funcionalidade FUTURA, fora de escopo (Req 14.13). */}
      <p className="print-queue__future-note">
        O anexo de arquivo (<code>.gcode</code> como tipo principal; <code>.3mf</code> e{' '}
        <code>.stl</code> opcionais) é uma funcionalidade futura, fora do escopo desta entrega.
      </p>
    </>
  );
}
