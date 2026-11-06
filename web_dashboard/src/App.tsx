/**
 * App: raiz da SPA. Monta o roteador client-side e envolve tudo no AuthProvider.
 *
 * Rotas (design.md -> "App + router"; Req 8.6 -> SPA sem recarregar o documento):
 * - `/login`          -> LoginPage (pública); se já autenticado, redireciona para `/`.
 * - `/`               -> lista de impressoras (protegida, dentro do AppLayout).
 * - `/printers/:id`   -> detalhe da impressora (protegida, dentro do AppLayout).
 * - `/supply`         -> estoque compartilhado (protegida, dentro do AppLayout).
 * - `*`               -> qualquer outra rota cai na raiz.
 *
 * Estrutura de proteção: uma rota de layout usa `ProtectedRoute` como elemento e, aninhado
 * sob ela, o `AppLayout` (casca autenticada com cabeçalho/navegação/logout). As páginas
 * protegidas são os filhos do `AppLayout`, renderizados no seu `<Outlet>`. Assim, sem
 * sessão o `ProtectedRoute` redireciona para `/login` e o conteúdo protegido nunca é
 * montado (Req 2.1, 2.10); com sessão, as páginas aparecem dentro do layout.
 *
 * O frontend autoriza-se exclusivamente pelo `Firebase_ID_Token` (Authorization: Bearer);
 * nenhuma rota/componente aqui conhece `x-api-key` (Req 8.7, 8.8).
 */
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom';

import { AuthProvider, useAuth } from './auth/AuthContext';
import ProtectedRoute from './auth/ProtectedRoute';
import AppLayout from './components/AppLayout';
import LoginPage from './pages/LoginPage';
import SignupPage from './pages/SignupPage';
import PrinterDetailPage from './pages/PrinterDetailPage';
import PrinterListPage from './pages/PrinterListPage';
import SupplyPage from './pages/SupplyPage';

/**
 * Rota de login: se já há sessão de Authenticated_User, redireciona para a raiz (evita
 * mostrar o login a quem já está autenticado). Enquanto `initializing`, não decide ainda
 * para não "piscar" (Req 2.9); exibe a LoginPage, e o redirect ocorre quando a sessão
 * persistida é restaurada.
 */
function LoginRoute(): JSX.Element {
  const { user, initializing } = useAuth();
  if (!initializing && user !== null) {
    return <Navigate to="/" replace />;
  }
  return <LoginPage />;
}

/**
 * Rota de cadastro: se ja ha sessao, redireciona para a raiz; senao exibe a SignupPage.
 */
function SignupRoute(): JSX.Element {
  const { user, initializing } = useAuth();
  if (!initializing && user !== null) {
    return <Navigate to="/" replace />;
  }
  return <SignupPage />;
}

export default function App(): JSX.Element {
  return (
    <AuthProvider>
      <BrowserRouter>
        <Routes>
          {/* Rota pública de login. */}
          <Route path="/login" element={<LoginRoute />} />
          <Route path="/signup" element={<SignupRoute />} />

          {/* Rotas protegidas: ProtectedRoute -> AppLayout (Outlet) -> páginas. */}
          <Route element={<ProtectedRoute />}>
            <Route element={<AppLayout />}>
              <Route path="/" element={<PrinterListPage />} />
              <Route path="/printers/:id" element={<PrinterDetailPage />} />
              <Route path="/supply" element={<SupplyPage />} />
            </Route>
          </Route>

          {/* Fallback: qualquer outra rota cai na raiz (protegida). */}
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  );
}

