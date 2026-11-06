/**
 * ProtectedRoute: bloqueia rotas que exigem sessão de Authenticated_User (Req 2.1, 2.10).
 *
 * Comportamento (design.md → "ProtectedRoute" e "Fluxo de login"):
 * - Enquanto `initializing` (o primeiro `onAuthStateChanged` ainda não resolveu), exibe
 *   um indicador de carregamento e NÃO redireciona, para não "piscar" a tela de login
 *   num reload com sessão persistida válida (Req 2.9).
 * - Resolvida a inicialização, se NÃO há sessão (`user === null`), redireciona para
 *   `/login` via `<Navigate replace>` e NUNCA renderiza o conteúdo protegido (Req 2.1,
 *   2.10). O `replace` evita empilhar a rota protegida no histórico.
 * - Com sessão ativa, renderiza o conteúdo protegido (os filhos ou o `<Outlet>`).
 *
 * As rotas completas são montadas na tarefa 19.1; este componente é exportado para
 * composição (tanto como wrapper de `children` quanto como rota de layout com `Outlet`).
 */
import type { ReactNode } from 'react';
import { Navigate, Outlet } from 'react-router-dom';

import { useAuth } from './AuthContext';

/** Caminho da tela de login para onde sessões ausentes são redirecionadas. */
export const LOGIN_PATH = '/login';

export interface ProtectedRouteProps {
  /**
   * Conteúdo protegido. Quando omitido, renderiza `<Outlet>` (uso como rota de layout
   * do react-router). Quando fornecido, renderiza os filhos diretamente.
   */
  children?: ReactNode;
}

export default function ProtectedRoute({ children }: ProtectedRouteProps): JSX.Element {
  const { user, initializing } = useAuth();

  // Ainda não sabemos se há sessão persistida: mostra loader, sem redirecionar (Req 2.9).
  if (initializing) {
    return (
      <div role="status" aria-live="polite" aria-busy="true">
        Carregando…
      </div>
    );
  }

  // Sem sessão após a inicialização: redireciona e nunca renderiza o protegido (Req 2.1, 2.10).
  if (user === null) {
    return <Navigate to={LOGIN_PATH} replace />;
  }

  // Sessão ativa: libera o conteúdo protegido.
  return <>{children ?? <Outlet />}</>;
}
