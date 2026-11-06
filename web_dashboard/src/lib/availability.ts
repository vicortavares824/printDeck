/**
 * Lógica PURA de frescor (staleness) e de Availability_State.
 *
 * Este módulo NÃO depende de React nem de nenhuma API de navegador: todas as
 * funções são puras e determinísticas (recebem `nowMs` em vez de ler o relógio),
 * o que as torna fáceis de testar com testes unitários e baseados em propriedade.
 *
 * Cobre os critérios de aceitação da Requirement 4 (Req 4.1, 4.2, 4.3, 4.5, 4.6, 4.7).
 *
 * Observação sobre datas (ver design.md, "Lógica de Availability_State e staleness"):
 * o backend grava `created_at`/`reserved_at` com `datetime.utcnow()` (naive, sem
 * timezone). Ao calcular staleness no cliente precisamos interpretar essa string
 * explicitamente como UTC — anexando `Z` quando o ISO não traz offset — antes de
 * comparar com o relógio local. Esse parsing está isolado em `parseUtc`.
 */

/** Limite de staleness (Staleness_Threshold): 60 segundos. (Req 4.1, 4.2) */
export const STALENESS_THRESHOLD_MS = 60_000;

/** Estado de frescor do Telemetry_Record mais recente. */
export type Freshness = 'offline' | 'stale' | 'fresh';

/** Availability_State derivado de uma impressora. */
export type Availability = 'disponivel' | 'indisponivel';

/**
 * Tipo mínimo de impressora exigido pela lógica de disponibilidade.
 *
 * Definido localmente porque `src/api/types.ts` ainda não existe. Quando o módulo
 * de tipos da API for criado (tarefa 13.1), ele poderá reexportar/estender este
 * contrato — os campos abaixo são o subconjunto necessário para derivar frescor
 * e Availability_State.
 */
export interface Printer {
  /** Campo `state` do Telemetry_Record (ex.: `standby`, `printing`, `error`). */
  state: string;
  /** `created_at` do Telemetry_Record mais recente (ISO; UTC naive no backend). */
  created_at: string;
  /** Reserva manual compartilhada (`reserved` do Reservation_State). */
  reserved?: boolean;
}

/**
 * Normaliza um `state` para comparação robusta: minúsculas e sem espaços nas pontas.
 */
function normalizeState(state: string | null | undefined): string {
  return (state ?? '').trim().toLowerCase();
}

/**
 * Interpreta a string ISO de `created_at` como UTC e retorna o epoch em milissegundos.
 *
 * O backend usa `datetime.utcnow()` (naive, sem offset), então um ISO como
 * `2024-01-01T12:00:00` precisa ser tratado como UTC. Se a string já traz um
 * offset explícito (`Z` ou `±HH:MM`), ele é respeitado; caso contrário anexamos `Z`.
 *
 * Retorna `NaN` quando a string é vazia/indefinida ou não representa uma data válida;
 * os chamadores tratam `NaN` como "sem leitura válida" (offline/indisponível).
 */
export function parseUtc(createdAt: string | null | undefined): number {
  if (createdAt == null) return NaN;
  const raw = createdAt.trim();
  if (raw === '') return NaN;

  // Já possui offset explícito? `Z` no fim, ou `+HH:MM` / `-HH:MM` após o 'T'.
  const hasZulu = /[zZ]$/.test(raw);
  const hasNumericOffset = /[+-]\d{2}:?\d{2}$/.test(raw);
  const normalized = hasZulu || hasNumericOffset ? raw : `${raw}Z`;

  return Date.parse(normalized);
}

/** O `state` indica impressora offline/desconectada. (Req 4.3) */
export function isOfflineState(state: string | null | undefined): boolean {
  const s = normalizeState(state);
  return s === 'offline' || s === 'disconnected' || s === 'shutdown';
}

/** O `state` indica impressão em andamento. */
export function isPrintingState(state: string | null | undefined): boolean {
  const s = normalizeState(state);
  return s === 'printing' || s === 'paused' || s === 'pausing' || s === 'resuming';
}

/** O `state` indica condição de erro. */
export function isErrorState(state: string | null | undefined): boolean {
  const s = normalizeState(state);
  return s === 'error' || s === 'cancelled' || s === 'canceled';
}

/**
 * O `state` indica impressora ociosa/pronta (sem impressão ativa):
 * `standby`, `idle`, `ready` ou `operational`. (Req 4.6)
 */
export function isIdleState(state: string | null | undefined): boolean {
  const s = normalizeState(state);
  return s === 'standby' || s === 'idle' || s === 'ready' || s === 'operational' || s === 'complete';
}

/**
 * Deriva o estado de frescor da impressora. Precedência: offline → stale → fresh.
 *
 * - Sem Telemetry_Record (`printer === null`) ⇒ `offline` (Req 4.5).
 * - `state` indica offline ⇒ `offline` (precede a verificação de staleness; Req 4.3).
 * - idade (`now - created_at`) ≥ Staleness_Threshold de 60s ⇒ `stale` (Req 4.1).
 * - caso contrário ⇒ `fresh` (Req 4.2).
 *
 * Um `created_at` inválido (`NaN`) resulta em idade `NaN`; como `NaN >= X` é falso,
 * o fallback seguro é tratá-lo como stale (dados não confiáveis ⇒ não fresh).
 */
export function deriveFreshness(printer: Printer | null, nowMs: number): Freshness {
  if (printer === null) return 'offline'; // Req 4.5
  if (isOfflineState(printer.state)) return 'offline'; // Req 4.3 (precede staleness)

  const createdMs = parseUtc(printer.created_at);
  if (Number.isNaN(createdMs)) return 'stale'; // created_at inválido ⇒ não confiável

  const age = nowMs - createdMs;
  return age >= STALENESS_THRESHOLD_MS ? 'stale' : 'fresh'; // Req 4.1, 4.2
}

/**
 * Deriva o Availability_State da impressora.
 *
 * INDISPONÍVEL se QUALQUER condição ocorrer (Req 4.7):
 *   - sem Telemetry_Record (`printer === null`);
 *   - `reserved === true` (reserva manual);
 *   - frescor diferente de `fresh` (offline ou stale);
 *   - `state` indica impressão em andamento ou erro.
 * Caso contrário — não reservada, fresh e `state` ocioso/pronto
 * (`standby`/`idle`/`ready`/`operational`) — DISPONÍVEL (Req 4.6).
 */
export function deriveAvailability(printer: Printer | null, nowMs: number): Availability {
  if (printer === null) return 'indisponivel'; // sem Telemetry_Record (Req 4.7)
  if (printer.reserved === true) return 'indisponivel'; // reserva manual (Req 4.7)

  const freshness = deriveFreshness(printer, nowMs);
  if (freshness !== 'fresh') return 'indisponivel'; // offline/stale (Req 4.7)

  if (isPrintingState(printer.state) || isErrorState(printer.state)) {
    return 'indisponivel'; // imprimindo/erro (Req 4.7)
  }

  if (isIdleState(printer.state)) return 'disponivel'; // ocioso/pronto + fresh (Req 4.6)

  // state desconhecido e não explicitamente ocioso ⇒ conservadoramente indisponível.
  return 'indisponivel';
}
