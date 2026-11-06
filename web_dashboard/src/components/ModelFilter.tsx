/**
 * ModelFilter: controle de filtro da lista de impressoras por Printer_Model (Req 10).
 *
 * Comportamento (design.md → "ModelFilter"; Req 10.1–10.8):
 * - Deriva as opções de modelo dos valores DISTINTOS de `model` presentes nos dados
 *   retornados pelo Printer_List_Endpoint (Req 10.1).
 * - Sempre inclui a opção "todas" (sem filtro) (Req 10.2).
 * - Inclui a opção "sem modelo" SOMENTE quando existe ao menos uma impressora com
 *   `model` nulo (Req 10.3).
 * - É um componente CONTROLADO: recebe `value` e `onChange`; a página aplica o filtro
 *   à lista exibida (Req 10.4, 10.5, 10.6) e, no polling, recalcula as opções e reverte
 *   a seleção que deixou de existir para "todas" (Req 10.7, 10.8) — ver `applyModelFilter`
 *   e `reconcileSelection`, funções puras exportadas aqui e usadas pela página.
 *
 * Tema (design.md → "Identidade Visual"): foco/seleção em azul de marca
 * (`--color-primary` / `--color-primary-subtle`); superfície branca.
 */

import type { Printer } from '../api/types';

/**
 * Valor de seleção do filtro:
 * - `'all'`      → todas as impressoras (Req 10.2, 10.6).
 * - `'none'`     → apenas impressoras com `model` nulo (Req 10.3, 10.5).
 * - qualquer outra string → um Printer_Model específico (Req 10.4).
 */
export type ModelFilterValue = 'all' | 'none' | (string & {});

/** Sentinelas das opções especiais do filtro. */
export const FILTER_ALL = 'all' as const;
export const FILTER_NONE = 'none' as const;

/** Uma opção renderizável do filtro (valor + rótulo legível). */
export interface ModelOption {
  value: ModelFilterValue;
  label: string;
}

/**
 * Deriva as opções do filtro a partir dos dados atuais (Req 10.1–10.3).
 *
 * Ordem: "todas" primeiro, depois cada modelo distinto em ordem alfabética, e por fim
 * "sem modelo" quando houver ao menos uma impressora com `model` nulo. A ordenação
 * estável evita que as opções "pulem" de posição entre pollings.
 */
export function deriveModelOptions(printers: Printer[]): ModelOption[] {
  const models = new Set<string>();
  let hasNullModel = false;

  for (const printer of printers) {
    if (printer.model === null || printer.model === undefined) {
      hasNullModel = true;
    } else {
      models.add(printer.model);
    }
  }

  const options: ModelOption[] = [{ value: FILTER_ALL, label: 'Todas' }];
  for (const model of [...models].sort((a, b) => a.localeCompare(b))) {
    options.push({ value: model, label: model });
  }
  if (hasNullModel) {
    options.push({ value: FILTER_NONE, label: 'Sem modelo' });
  }
  return options;
}

/**
 * Aplica o filtro selecionado à lista de impressoras (Req 10.4, 10.5, 10.6).
 * - `'all'`  → todas; `'none'` → `model` nulo; caso contrário → `model` igual ao valor.
 */
export function applyModelFilter(printers: Printer[], selected: ModelFilterValue): Printer[] {
  if (selected === FILTER_ALL) return printers;
  if (selected === FILTER_NONE) {
    return printers.filter((p) => p.model === null || p.model === undefined);
  }
  return printers.filter((p) => p.model === selected);
}

/**
 * Reconcilia a seleção atual contra as opções disponíveis após um polling (Req 10.7, 10.8).
 * Se o valor selecionado não existe mais entre as opções, reverte para "todas".
 */
export function reconcileSelection(
  selected: ModelFilterValue,
  options: ModelOption[],
): ModelFilterValue {
  return options.some((o) => o.value === selected) ? selected : FILTER_ALL;
}

export interface ModelFilterProps {
  /** Opções já derivadas dos dados atuais (via `deriveModelOptions`). */
  options: ModelOption[];
  /** Valor selecionado atualmente (controlado pela página). */
  value: ModelFilterValue;
  /** Notifica a seleção de um novo valor. */
  onChange: (value: ModelFilterValue) => void;
}

export default function ModelFilter({ options, value, onChange }: ModelFilterProps): JSX.Element {
  return (
    <div className="model-filter">
      <label htmlFor="model-filter-select" className="model-filter__label">
        Filtrar por modelo
      </label>
      <select
        id="model-filter-select"
        className="model-filter__select"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        aria-label="Filtrar impressoras por modelo"
      >
        {options.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
    </div>
  );
}
