/**
 * SupplyPage: área de estoque do Dashboard (Req 15, 16, 17).
 *
 * Visão geral (design.md → "e. Estoque"; tabela de componentes):
 * - LISTA via polling de `GET /api/supply/items` a cada Polling_Interval de 10s (Req 15.9),
 *   com estados de carregamento inicial (Req 15.5), lista vazia (Req 15.6) e erro com
 *   ação de nova tentativa preservando os dados exibidos (Req 15.7, 15.8).
 * - CRUD via `POST /api/supply/sync` e `DELETE /api/supply/items/{item_id}`:
 *   - Adicionar: `title` obrigatório (validação local, Req 16.2); `item_id` gerado por
 *     `crypto.randomUUID()`; `description` opcional; `quantity` default 1.0; `is_bought`
 *     default `false` (Req 16.1, 16.3).
 *   - Editar: mesmo `item_id` com novos valores (Req 16.4).
 *   - Alternar `is_bought`: sync do item com o novo valor (Req 16.5).
 *   - Excluir: `deleteItem` (Req 16.6).
 * - POSSE (Req 16.7, 16.8, 16.9): editar/excluir habilitados apenas quando
 *   `owner_id === email` do usuário OU em Admin_Mode (inclui `owner_id` nulo).
 * - Tratamento de erros: `forbidden` no sync (Req 16.10), 403 no delete (Req 16.12),
 *   404 no delete (remove da lista, Req 16.13), falha de rede mantém estado (Req 16.14).
 * - Admin_Mode via `AdminModeControl` (Req 17): o `x-admin-code` validado acompanha as
 *   operações de escrita; o código é mantido só em memória (estado), nunca logado/exibido.
 *
 * Toda chamada é autenticada por `Authorization: Bearer` (apiClient `auth: true`) e NUNCA
 * envia `x-api-key` (Req 8.7, 8.8).
 */
import { useCallback, useEffect, useMemo, useState } from 'react';

import { ApiError } from '../api/types';
import type { SupplyItem } from '../api/types';
import { createSupplyApi, type SupplyItemInput } from '../api/supplyApi';
import { useApiClient } from '../api/useApiClient';
import { useAuth } from '../auth/AuthContext';
import { usePolling } from '../hooks/usePolling';
import AdminModeControl from '../components/AdminModeControl';

/** Intervalo de polling do estoque: 10s (Req 15.9). */
const SUPPLY_POLL_INTERVAL_MS = 10_000;

/** Mensagens da página. */
const MSG_TITLE_REQUIRED = 'Informe um título para o item.';
const MSG_EMPTY = 'O estoque não possui itens.';
const MSG_LOAD_ERROR = 'Não foi possível carregar o estoque.';
const MSG_FORBIDDEN_SYNC =
  'A alteração não foi permitida: este item pertence a outro usuário.';
const MSG_DELETE_FORBIDDEN =
  'Apenas o criador ou um administrador pode excluir este item.';
const MSG_WRITE_ERROR =
  'Não foi possível concluir a operação. Verifique a conexão e tente novamente.';

/** Estado do formulário de adicionar/editar. */
interface ItemForm {
  /** `item_id` em edição; `null` quando é um novo item. */
  editingItemId: string | null;
  title: string;
  description: string;
  quantity: string;
  is_bought: boolean;
}

const EMPTY_FORM: ItemForm = {
  editingItemId: null,
  title: '',
  description: '',
  quantity: '1',
  is_bought: false,
};

/** Gera um `item_id` para um novo Supply_Item (Req 16.3). */
function newItemId(): string {
  // `crypto.randomUUID` disponível em browsers modernos (contexto seguro) e Node 18+.
  return crypto.randomUUID();
}

export default function SupplyPage(): JSX.Element {
  const { user } = useAuth();
  const client = useApiClient();
  const email = user?.email ?? '';

  // Serviço de supply ligado ao e-mail (device_id). Memorizado por client+email.
  const api = useMemo(() => createSupplyApi(client, email), [client, email]);

  // Admin_Mode: o código validado fica só em memória (nunca logado/exibido) (Req 17).
  const [adminCode, setAdminCode] = useState<string | null>(null);
  const adminMode = adminCode !== null;

  const [form, setForm] = useState<ItemForm>(EMPTY_FORM);
  const [writeError, setWriteError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // Itens removidos localmente após um 404 no delete, até o próximo polling reconciliar
  // (Req 16.13): mantemos o conjunto para não "piscar" o item de volta entre ticks.
  const [locallyRemoved, setLocallyRemoved] = useState<Set<string>>(new Set());

  // Poller periódico da lista (Req 15.9): no máximo 1 request simultânea (garantido por
  // `usePolling`). Reage a `api` (client/email) via `fetcherRef` interno do hook.
  const pollingFetcher = useCallback(
    (signal: AbortSignal) => api.listItems(signal),
    [api],
  );
  const pollResult = usePolling<SupplyItem[]>(pollingFetcher, {
    intervalMs: SUPPLY_POLL_INTERVAL_MS,
    enabled: email !== '',
  });

  // Overlay de refetch manual (Req 15.8) e de escrita: um fetch pontual fora do intervalo
  // do poller, cujo resultado tem precedência sobre o do poller até o próximo tick. O
  // `usePolling` não expõe um `refetch`, então orquestramos um fetch único aqui, mantendo
  // o invariante de 1 request simultânea do poller (este é um request separado e curto,
  // disparado por ação do usuário/escrita, não um segundo poller).
  const [manualData, setManualData] = useState<SupplyItem[] | null>(null);
  const [manualError, setManualError] = useState<Error | null>(null);
  const [manualFetching, setManualFetching] = useState(false);

  const refetchNow = useCallback(() => {
    const controller = new AbortController();
    setManualFetching(true);
    api
      .listItems(controller.signal)
      .then((list) => {
        setManualData(list);
        setManualError(null);
      })
      .catch((err: unknown) => {
        // Mantém os dados exibidos; só registra o erro de carregamento (Req 15.7).
        setManualError(err instanceof Error ? err : new Error(String(err)));
      })
      .finally(() => setManualFetching(false));
  }, [api]);

  // Precedência: dados do poller (mais recentes no fluxo periódico) sobrepõem o overlay
  // manual assim que chegam; antes disso, o overlay cobre o intervalo até o próximo tick.
  const items = pollResult.data ?? manualData;
  const loadError = pollResult.error ?? manualError;
  const fetching = pollResult.isFetching || manualFetching;

  // Lista exibida: aplica a remoção local otimista de 404 (Req 16.13).
  const displayedItems = useMemo(() => {
    if (!items) return null;
    if (locallyRemoved.size === 0) return items;
    return items.filter((it) => !locallyRemoved.has(it.item_id));
  }, [items, locallyRemoved]);

  const hasData = displayedItems !== null;
  const isInitialLoading = !hasData && fetching && !loadError; // Req 15.5.
  const isEmpty = hasData && displayedItems!.length === 0; // Req 15.6.

  /** Decide se o usuário pode editar/excluir um item (Req 16.7, 16.8, 16.9). */
  const canModify = useCallback(
    (item: SupplyItem): boolean => {
      if (adminMode) return true; // Admin_Mode: tudo habilitado, inclui owner_id nulo (Req 16.9).
      if (item.owner_id === null) return false; // legado: só admin (Req 16.9).
      return item.owner_id === email; // posse por e-mail (Req 16.7, 16.8).
    },
    [adminMode, email],
  );

  /** Normaliza o `quantity` do formulário: número ≥ 0, default 1.0 quando inválido. */
  function parseQuantity(raw: string): number {
    const n = Number(raw);
    if (!Number.isFinite(n) || n < 0) return 1.0;
    return n;
  }

  function resetForm(): void {
    setForm(EMPTY_FORM);
  }

  /** Aplica os resultados de um `sync` (synced/forbidden) às mensagens (Req 16.10, 16.11). */
  function reportSyncResult(forbidden: string[]): boolean {
    if (forbidden.length > 0) {
      setNotice(null);
      setWriteError(MSG_FORBIDDEN_SYNC); // Req 16.10.
      return false;
    }
    return true;
  }

  /** Executa um sync de um único item, cuidando de erros e refetch (Req 16.3–16.5, 16.14). */
  async function syncItem(input: SupplyItemInput): Promise<boolean> {
    setBusy(true);
    setWriteError(null);
    setNotice(null);
    try {
      const result = await api.sync([input], adminCode ?? undefined);
      const ok = reportSyncResult(result.forbidden);
      refetchNow(); // reflete a alteração na releitura (Req 16.11).
      return ok;
    } catch {
      // Falha de rede/timeout: mantém o estado coerente; reconcilia no polling (Req 16.14).
      setWriteError(MSG_WRITE_ERROR);
      return false;
    } finally {
      setBusy(false);
    }
  }

  /** Submissão do formulário de adicionar/editar (Req 16.1–16.4). */
  async function handleSubmitForm(event: React.FormEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault();

    const title = form.title.trim();
    if (title === '') {
      // Validação local: não envia à Cloud_API (Req 16.2).
      setWriteError(MSG_TITLE_REQUIRED);
      return;
    }

    const input: SupplyItemInput = {
      item_id: form.editingItemId ?? newItemId(), // novo → gera; edição → mantém (Req 16.3, 16.4).
      title,
      description: form.description.trim(),
      quantity: parseQuantity(form.quantity),
      is_bought: form.is_bought,
    };

    const ok = await syncItem(input);
    if (ok) resetForm();
  }

  /** Alterna `is_bought` de um item existente (Req 16.5). */
  async function handleToggleBought(item: SupplyItem): Promise<void> {
    await syncItem({
      item_id: item.item_id,
      title: item.title,
      description: item.description,
      quantity: item.quantity,
      is_bought: !item.is_bought,
    });
  }

  /** Carrega um item no formulário para edição (Req 16.4). */
  function handleStartEdit(item: SupplyItem): void {
    setWriteError(null);
    setNotice(null);
    setForm({
      editingItemId: item.item_id,
      title: item.title,
      description: item.description,
      quantity: String(item.quantity),
      is_bought: item.is_bought,
    });
  }

  /** Exclui um item, tratando 403 (mantém) e 404 (remove) (Req 16.6, 16.12, 16.13). */
  async function handleDelete(item: SupplyItem): Promise<void> {
    setBusy(true);
    setWriteError(null);
    setNotice(null);
    try {
      await api.deleteItem(item.item_id, adminCode ?? undefined);
      // Sucesso: remove otimisticamente até o polling reconciliar.
      setLocallyRemoved((prev) => new Set(prev).add(item.item_id));
      refetchNow();
    } catch (err) {
      if (err instanceof ApiError && err.hasStatus(403)) {
        // 403: mantém o item na lista e informa (Req 16.12).
        setWriteError(MSG_DELETE_FORBIDDEN);
      } else if (err instanceof ApiError && err.hasStatus(404)) {
        // 404: já não existe → remove da lista exibida (Req 16.13).
        setLocallyRemoved((prev) => new Set(prev).add(item.item_id));
        refetchNow();
      } else {
        // Rede/timeout/outros: mantém estado coerente; reconcilia no polling (Req 16.14).
        setWriteError(MSG_WRITE_ERROR);
      }
    } finally {
      setBusy(false);
    }
  }

  // Quando o polling reconcilia, descartamos remoções locais já refletidas pelo servidor
  // (o item não está mais presente), evitando um Set que cresce indefinidamente.
  useMemoCleanup(items, locallyRemoved, setLocallyRemoved);

  return (
    <main className="supply">
      <h1 className="supply__title">Estoque</h1>

      <AdminModeControl
        api={api}
        adminMode={adminMode}
        onEnterAdmin={(code) => {
          setAdminCode(code); // guarda só em memória (Req 17.3, 17.7).
          setNotice('Modo administrador ativado.');
        }}
        onExitAdmin={() => {
          setAdminCode(null); // descarta o código (Req 17.6).
          setNotice(null);
        }}
      />

      {/* Formulário de adicionar/editar (Req 16.1) */}
      <section
        className="supply__form-card"
        aria-label={form.editingItemId ? 'Editar item' : 'Adicionar item'}
      >
        <h2 className="supply__subtitle">
          {form.editingItemId ? 'Editar item' : 'Adicionar item'}
        </h2>
        <form className="supply__form" onSubmit={handleSubmitForm}>
          <div className="supply__field">
            <label htmlFor="supply-title">Título</label>
            <input
              id="supply-title"
              value={form.title}
              onChange={(e) => setForm((f) => ({ ...f, title: e.target.value }))}
              disabled={busy}
            />
          </div>
          <div className="supply__field">
            <label htmlFor="supply-description">Descrição (opcional)</label>
            <input
              id="supply-description"
              value={form.description}
              onChange={(e) => setForm((f) => ({ ...f, description: e.target.value }))}
              disabled={busy}
            />
          </div>
          <div className="supply__field">
            <label htmlFor="supply-quantity">Quantidade</label>
            <input
              id="supply-quantity"
              type="number"
              min="0"
              step="any"
              value={form.quantity}
              onChange={(e) => setForm((f) => ({ ...f, quantity: e.target.value }))}
              disabled={busy}
            />
          </div>
          <div className="supply__field supply__field--checkbox">
            <label>
              <input
                type="checkbox"
                checked={form.is_bought}
                onChange={(e) => setForm((f) => ({ ...f, is_bought: e.target.checked }))}
                disabled={busy}
              />
              Já comprado
            </label>
          </div>
          <div className="supply__form-actions">
            <button type="submit" className="btn btn--primary" disabled={busy}>
              {form.editingItemId ? 'Salvar alterações' : 'Adicionar item'}
            </button>
            {form.editingItemId && (
              <button
                type="button"
                className="btn btn--secondary"
                onClick={resetForm}
                disabled={busy}
              >
                Cancelar edição
              </button>
            )}
          </div>
        </form>
      </section>

      {/* Mensagens de escrita (forbidden/403/erro) e avisos (Req 16.10, 16.12, 16.14) */}
      {writeError !== null && (
        <p className="supply__error" role="alert">
          {writeError}
        </p>
      )}
      {notice !== null && (
        <p className="supply__notice" role="status">
          {notice}
        </p>
      )}

      {/* Estados de carregamento/erro/vazio da lista (Req 15.5, 15.6, 15.7) */}
      {isInitialLoading && (
        <p className="supply__loading" role="status">
          Carregando estoque…
        </p>
      )}

      {loadError !== null && (
        <div className="supply__error-box" role="alert">
          <p>{MSG_LOAD_ERROR}</p>
          {/* Nova tentativa; preserva os dados previamente exibidos (Req 15.7, 15.8). */}
          <button type="button" className="btn btn--secondary" onClick={refetchNow}>
            Tentar novamente
          </button>
        </div>
      )}

      {isEmpty && loadError === null && (
        <p className="supply__empty" role="status">
          {MSG_EMPTY}
        </p>
      )}

      {/* Lista de itens (Req 15.2, 15.3, 15.4) */}
      {hasData && displayedItems!.length > 0 && (
        <ul className="supply__list" aria-label="Itens do estoque">
          {displayedItems!.map((item) => {
            const modifiable = canModify(item);
            return (
              <li key={item.item_id} className="supply__item" data-bought={item.is_bought}>
                <div className="supply__item-main">
                  <span className="supply__item-title">{item.title}</span>
                  {item.description !== '' && (
                    <span className="supply__item-desc"> — {item.description}</span>
                  )}
                  <span className="supply__item-qty"> (qtd: {item.quantity})</span>
                  {/* Indicador persistente de is_bought (Req 15.3, 15.4). */}
                  <span
                    className="supply__item-bought"
                    data-bought={item.is_bought}
                    role="status"
                    aria-label={item.is_bought ? 'Comprado' : 'A comprar'}
                  >
                    {item.is_bought ? ' ✓ comprado' : ' • a comprar'}
                  </span>
                  {/* owner_id exibido (Req 15.2). */}
                  <span className="supply__item-owner"> [dono: {item.owner_id ?? 'sem dono'}]</span>
                </div>

                {/* Controles habilitados só por posse/Admin_Mode (Req 16.7, 16.8, 16.9). */}
                <div className="supply__item-actions">
                  <button
                    type="button"
                    className="btn btn--secondary"
                    onClick={() => handleToggleBought(item)}
                    disabled={busy || !modifiable}
                  >
                    {item.is_bought ? 'Marcar a comprar' : 'Marcar comprado'}
                  </button>
                  <button
                    type="button"
                    className="btn btn--secondary"
                    onClick={() => handleStartEdit(item)}
                    disabled={busy || !modifiable}
                  >
                    Editar
                  </button>
                  <button
                    type="button"
                    className="btn btn--secondary"
                    onClick={() => handleDelete(item)}
                    disabled={busy || !modifiable}
                  >
                    Excluir
                  </button>
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </main>
  );
}

/**
 * Efeito auxiliar: quando a lista do servidor deixa de conter um `item_id` que estava em
 * `locallyRemoved`, removemos esse id do conjunto (a reconciliação já ocorreu). Mantém o
 * Set enxuto sem reintroduzir itens já excluídos entre ticks.
 */
function useMemoCleanup(
  items: SupplyItem[] | null,
  locallyRemoved: Set<string>,
  setLocallyRemoved: React.Dispatch<React.SetStateAction<Set<string>>>,
): void {
  useEffect(() => {
    if (!items || locallyRemoved.size === 0) return;
    const present = new Set(items.map((it) => it.item_id));
    let changed = false;
    const next = new Set<string>();
    for (const id of locallyRemoved) {
      if (present.has(id)) {
        // ainda presente no servidor → manter a remoção local até sumir.
        next.add(id);
      } else {
        changed = true; // servidor já não tem → pode descartar do conjunto local.
      }
    }
    if (changed) setLocallyRemoved(next);
  }, [items, locallyRemoved, setLocallyRemoved]);
}
