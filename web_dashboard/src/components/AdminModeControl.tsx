/**
 * AdminModeControl: controle do Admin_Mode do estoque (Req 17).
 *
 * Comportamento (design.md → tabela de componentes; Req 17.1–17.7):
 * - Fora do Admin_Mode: oferece um input para informar o código de administrador
 *   (Req 17.1) e um botão para validá-lo via `POST /api/supply/admin/verify` (Req 17.2).
 * - Sucesso (200 `{ admin: true }`): entra em Admin_Mode; o código validado é entregue
 *   ao pai via `onEnterAdmin(code)` para ser enviado como `x-admin-code` nas operações
 *   seguintes (Req 17.3). O input é limpo em seguida.
 * - 403: mensagem de código inválido; permanece FORA do Admin_Mode e NÃO armazena o
 *   código (Req 17.5).
 * - Dentro do Admin_Mode: oferece um botão de sair que descarta o código (Req 17.6).
 *
 * Segredo (Req 17.7): o código NUNCA é exibido em texto (input `type="password"`),
 * nem logado, nem mostrado em mensagens. O componente não guarda o código após entregá-lo
 * ao pai; o input local é limpo assim que o Admin_Mode é ativado.
 */
import { useState, type FormEvent } from 'react';

import { ApiError } from '../api/types';
import type { SupplyApi } from '../api/supplyApi';

export interface AdminModeControlProps {
  /** Serviço de supply (fornece `verifyAdmin`). */
  api: SupplyApi;
  /** `true` quando o Dashboard já está em Admin_Mode. */
  adminMode: boolean;
  /** Chamado com o código validado ao entrar em Admin_Mode (Req 17.3). */
  onEnterAdmin: (code: string) => void;
  /** Chamado ao sair do Admin_Mode; o pai descarta o código (Req 17.6). */
  onExitAdmin: () => void;
}

const MSG_CODE_REQUIRED = 'Informe o código de administrador.';
const MSG_CODE_INVALID = 'Código de administrador inválido.';
const MSG_VERIFY_FAILED =
  'Não foi possível validar o código agora. Tente novamente em instantes.';

export default function AdminModeControl({
  api,
  adminMode,
  onEnterAdmin,
  onExitAdmin,
}: AdminModeControlProps): JSX.Element {
  const [code, setCode] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [verifying, setVerifying] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault();

    const trimmed = code.trim();
    if (trimmed === '') {
      setError(MSG_CODE_REQUIRED);
      return;
    }

    setError(null);
    setVerifying(true);
    try {
      const result = await api.verifyAdmin(trimmed);
      if (result.admin) {
        // Entra em Admin_Mode: entrega o código ao pai e limpa o input local (Req 17.3, 17.7).
        onEnterAdmin(trimmed);
        setCode('');
      } else {
        // Resposta 200 porém sem admin: trata como inválido por segurança.
        setError(MSG_CODE_INVALID);
      }
    } catch (err) {
      // 403 → código inválido; não entra em Admin_Mode nem armazena o código (Req 17.5).
      if (err instanceof ApiError && err.hasStatus(403)) {
        setError(MSG_CODE_INVALID);
      } else {
        setError(MSG_VERIFY_FAILED);
      }
    } finally {
      setVerifying(false);
    }
  }

  function handleExit(): void {
    // Descarta o código armazenado e volta ao comportamento por posse (Req 17.6).
    setError(null);
    setCode('');
    onExitAdmin();
  }

  if (adminMode) {
    return (
      <section className="admin-mode admin-mode--active" aria-label="Modo administrador do estoque">
        <p className="admin-mode__status" role="status">
          Modo administrador ativo.
        </p>
        <button type="button" className="btn btn--secondary admin-mode__exit" onClick={handleExit}>
          Sair do modo administrador
        </button>
      </section>
    );
  }

  return (
    <section className="admin-mode" aria-label="Modo administrador do estoque">
      <form
        className="admin-mode__form"
        onSubmit={handleSubmit}
        aria-describedby={error ? 'admin-code-error' : undefined}
      >
        <label className="admin-mode__label" htmlFor="admin-code">
          Código de administrador
        </label>
        <input
          id="admin-code"
          name="admin-code"
          className="admin-mode__input"
          // Segredo (Req 17.7): nunca exibido em texto.
          type="password"
          autoComplete="off"
          value={code}
          onChange={(e) => setCode(e.target.value)}
          disabled={verifying}
        />
        {error !== null && (
          <p id="admin-code-error" className="admin-mode__error" role="alert">
            {error}
          </p>
        )}
        <button type="submit" className="btn btn--primary admin-mode__submit" disabled={verifying}>
          {verifying ? 'Validando…' : 'Entrar no modo administrador'}
        </button>
      </form>
    </section>
  );
}
