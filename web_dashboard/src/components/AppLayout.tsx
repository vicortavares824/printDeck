/**
 * AppLayout: casca autenticada do Dashboard (Req 2.7, 2.8).
 *
 * Comportamento (design.md → tabela de componentes "AppLayout"):
 * - Cabeçalho (barra azul — classe `app-layout__header` já estilizada no theme.css)
 *   com a marca do produto e a navegação principal.
 * - Navegação client-side entre Impressoras (`/`) e Estoque (`/supply`) via `NavLink`
 *   (sem recarregar o documento — Req 8.6); o link ativo é destacado.
 * - Controle de LOGOUT visível enquanto há sessão de Authenticated_User (Req 2.7); ao
 *   acioná-lo, chama `logout()` do `useAuth` (Req 2.8). Após o `signOut`, o `user` vai a
 *   `null` e o `ProtectedRoute` redireciona para `/login`.
 *
 * As páginas protegidas são renderizadas dentro deste layout via `<Outlet>` do
 * react-router (rota de layout). O AppLayout fica sob o `ProtectedRoute`, então só é
 * montado com sessão ativa — por isso o logout é sempre exibido aqui.
 */
import { useCallback, useState } from 'react';
import { NavLink, Outlet } from 'react-router-dom';

import { useAuth } from '../auth/AuthContext';

/** Classe aplicada ao `NavLink` conforme o estado ativo da rota. */
function navLinkClass({ isActive }: { isActive: boolean }): string {
  return isActive ? 'app-layout__nav-link app-layout__nav-link--active' : 'app-layout__nav-link';
}

export default function AppLayout(): JSX.Element {
  const { user, logout } = useAuth();
  const [loggingOut, setLoggingOut] = useState(false);

  const handleLogout = useCallback(async (): Promise<void> => {
    setLoggingOut(true);
    try {
      // Encerra a sessão (Req 2.8); o redirecionamento para /login é do ProtectedRoute,
      // disparado quando o onAuthStateChanged leva `user` a null.
      await logout();
    } finally {
      setLoggingOut(false);
    }
  }, [logout]);

  return (
    <div className="app-layout">
      <header className="app-layout__header">
        <div className="app-layout__brand">PrintDeck</div>

        <nav className="app-layout__nav" aria-label="Navegação principal">
          {/* `end` em "/" evita que a raiz fique ativa em sub-rotas como /printers/:id. */}
          <NavLink to="/" end className={navLinkClass}>
            Impressoras
          </NavLink>
          <NavLink to="/supply" className={navLinkClass}>
            Estoque
          </NavLink>
        </nav>

        {/* Logout visível enquanto há sessão ativa (Req 2.7). */}
        {user !== null && (
          <button
            type="button"
            className="btn btn--secondary app-layout__logout"
            onClick={() => void handleLogout()}
            disabled={loggingOut}
          >
            {loggingOut ? 'Saindo…' : 'Sair'}
          </button>
        )}
      </header>

      {/* Páginas protegidas renderizadas dentro do layout. */}
      <Outlet />
    </div>
  );
}
