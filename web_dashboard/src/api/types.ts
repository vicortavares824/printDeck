/**
 * Tipos TypeScript que espelham a API da Cloud_API (schemas Pydantic do backend)
 * e o erro tipado do apiClient.
 *
 * Referências de design (design.md → "Data Models" → "Tipos TypeScript (frontend)"
 * e "Schemas backend novos/alterados"):
 * - `Printer`  espelha `PrinterOut`  (TelemetryOut + `model` + Reservation_State).
 * - `Job`      espelha `CloudJobOut` (Job_History).
 * - `QueueItem` espelha `QueueItemOut`.
 * - `SupplyItem` espelha `SupplyItemOut`.
 *
 * Datas (`created_at`, `reserved_at`, `updated_at`) chegam como string ISO. O backend
 * grava com `datetime.utcnow()` (naive, sem offset); o parsing UTC para cálculo de
 * staleness é responsabilidade de `src/lib/availability.ts` (função `parseUtc`).
 *
 * Este módulo NÃO conhece `x-api-key` (Req 8.7, 8.8): nenhum tipo aqui a representa.
 */

import type { Printer as AvailabilityPrinter } from '../lib/availability';

/**
 * Informação de filamento (campo `filament_info` do Telemetry_Record).
 * Todos os campos são opcionais/nulos: registros antigos ou parciais podem omiti-los.
 */
export interface FilamentInfo {
  spool_id?: number | null;
  material?: string | null;
  color?: string | null;
  vendor?: string | null;
  remaining_weight_grams?: number | null;
  used_in_this_print_grams?: number | null;
}

/**
 * Impressora: último Telemetry_Record por `printer_id` + `model` + Reservation_State.
 * Espelha o schema `PrinterOut` do backend (Req 1.4–1.8, 9.7).
 *
 * Este contrato é um superconjunto do `Printer` mínimo exigido pela lógica pura em
 * `src/lib/availability.ts` (que precisa apenas de `state`, `created_at`, `reserved?`).
 * A verificação `satisfies` ao final do arquivo garante que este `Printer` permanece
 * atribuível ao contrato de `availability.ts`, evitando divergência entre os módulos.
 */
export interface Printer {
  id: number;
  printer_id: string;
  state: string;
  progress: number;
  current_file: string | null;
  nozzle_temp: number;
  bed_temp: number;
  filament_info: FilamentInfo | null;
  /** Modelo da impressora (Req 9); `null` quando desconhecido/registro legado. */
  model: string | null;
  /** ISO do Telemetry_Record mais recente (UTC naive no backend). */
  created_at: string;
  /** Reservation_State mesclado pelo Printer_List_Endpoint (Req 1.7, 1.8). */
  reserved: boolean;
  reserved_by: string | null;
  reserved_at: string | null;
}

/**
 * Item do Job_History. Espelha `CloudJobOut` (Req 6.3, 6.4).
 */
export interface Job {
  id: number;
  printer_id: string;
  filename: string;
  status: string;
  print_duration_seconds: number;
  filament_used_grams: number;
  filament_material: string | null;
  filament_color: string | null;
  created_at: string;
}

/**
 * Item da Print_Queue. Espelha `QueueItemOut` (Req 13.2, 13.22).
 * `position` é único/contíguo (1..n) por `printer_id`; o menor é o próximo a imprimir.
 */
export interface QueueItem {
  id: number;
  printer_id: string;
  sku: string;
  name: string;
  position: number;
  created_at: string;
  created_by: string | null;
}

/**
 * Item do Supply_Inventory. Espelha `SupplyItemOut` (Req 15, 16).
 * `owner_id` é o e-mail do dono (`null` para itens legados — só admin pode alterar).
 */
export interface SupplyItem {
  id: number;
  item_id: string;
  title: string;
  description: string;
  quantity: number;
  is_bought: boolean;
  owner_id: string | null;
  updated_at: string;
}

/**
 * Categorias de falha distinguidas pelo apiClient (Req 7.1):
 * - `network`: falha de transporte (fetch rejeitou; servidor inalcançável).
 * - `timeout`: a requisição foi abortada por estouro de tempo (`AbortError`) ou
 *   cancelada por um `AbortSignal` externo.
 * - `http`:    a resposta chegou com status fora da faixa 2xx (`status` preenchido).
 * - `unknown`: qualquer outra falha inesperada.
 */
export type ApiErrorKind = 'network' | 'timeout' | 'http' | 'unknown';

/**
 * Erro tipado das chamadas do apiClient.
 *
 * Distingue erro de rede, timeout/`AbortError` e erro de status HTTP (Req 7.1),
 * permitindo às camadas superiores escolher a mensagem e o fluxo de retry/refresh
 * corretos (ver design.md → "Error Handling" → "Distinção de erros").
 */
export class ApiError extends Error {
  /** Categoria da falha. */
  readonly kind: ApiErrorKind;
  /** Status HTTP quando `kind === 'http'`; caso contrário `undefined`. */
  readonly status?: number;
  /** Corpo/resposta bruta associada (texto ou JSON já lido), quando disponível. */
  readonly body?: unknown;
  /** Erro original que originou esta falha (para depuração), quando houver. */
  readonly cause?: unknown;

  constructor(
    kind: ApiErrorKind,
    message: string,
    options: { status?: number; body?: unknown; cause?: unknown } = {},
  ) {
    super(message);
    this.name = 'ApiError';
    this.kind = kind;
    this.status = options.status;
    this.body = options.body;
    this.cause = options.cause;
    // Mantém a cadeia de protótipo correta ao estender Error com target ES2020.
    Object.setPrototypeOf(this, ApiError.prototype);
  }

  /** Falha de rede (servidor inalcançável / fetch rejeitado). */
  get isNetwork(): boolean {
    return this.kind === 'network';
  }

  /** Timeout ou cancelamento (`AbortError`). */
  get isTimeout(): boolean {
    return this.kind === 'timeout';
  }

  /** Erro de status HTTP (status fora de 2xx). */
  get isHttp(): boolean {
    return this.kind === 'http';
  }

  /** Verdadeiro quando o status HTTP é exatamente `expected`. */
  hasStatus(expected: number): boolean {
    return this.kind === 'http' && this.status === expected;
  }
}

/**
 * Garantia estática de que `Printer` (completo) permanece compatível com o contrato
 * mínimo exigido por `src/lib/availability.ts`. Se os campos divergirem, o build falha.
 */
export type PrinterSatisfiesAvailability = Printer extends AvailabilityPrinter ? true : never;
const _printerAvailabilityCheck: PrinterSatisfiesAvailability = true;
// Evita o erro de "declarado mas nunca usado" mantendo a checagem acima.
void _printerAvailabilityCheck;
