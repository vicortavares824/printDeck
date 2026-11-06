/**
 * LoginPage: tela de login do Dashboard (Req 2.2, 2.3, 2.5, 2.6).
 *
 * Comportamento (design.md -> "LoginPage" e "Fluxo de login"):
 * - Form com campo de e-mail, campo de senha e controle de envio (Req 2.2).
 * - Validação LOCAL antes de chamar o Firebase (Req 2.3): e-mail vazio, senha vazia ou
 *   e-mail em formato inválido (sem "@" ou sem domínio) bloqueiam o submit, exibem uma
 *   mensagem de validação e NAO chamam o Firebase_Auth.
 * - Credenciais rejeitadas (Req 2.5): mensagem de falha de autenticação, permanece na
 *   tela e preserva o e-mail digitado (o estado do campo nunca é limpo em erro).
 * - Indisponibilidade/timeout do Firebase (Req 2.6): mensagem de falha de comunicação.
 *
 * O redirecionamento pós-login (Req 2.4) e o controle de logout (Req 2.7, 2.8) são
 * responsabilidade das rotas/layout (tarefas 19.1 e AppLayout), não desta página. Aqui
 * basta estabelecer a sessão via `login()`; o `onAuthStateChanged` do AuthContext
 * atualiza `user` e o roteador reage.
 */
import { useState, type FormEvent } from 'react';
import { Link } from 'react-router-dom';

import { AuthError, useAuth } from '../auth/AuthContext';

/** Mensagens de validação local (Req 2.3). */
const MSG_EMAIL_REQUIRED = 'Informe o e-mail.';
const MSG_PASSWORD_REQUIRED = 'Informe a senha.';
const MSG_EMAIL_INVALID = 'Informe um e-mail válido (ex.: usuario@dominio.com).';
/** Mensagens de erro de autenticação (Req 2.5, 2.6). */
const MSG_AUTH_REJECTED = 'E-mail ou senha incorretos. Verifique os dados e tente novamente.';
const MSG_AUTH_UNAVAILABLE =
  'Não foi possível contatar o serviço de autenticação. Tente novamente em instantes.';

/**
 * Valida o formato do e-mail localmente (Req 2.3): exige a presença de "@" e de um
 * domínio com ao menos um ponto após o "@", sem espaços. Deliberadamente simples ->
 * o objetivo é bloquear entradas claramente inválidas antes de ir ao Firebase, não
 * replicar o RFC 5322.
 */
export function isValidEmailFormat(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

/** Resultado da validação local: `null` quando válido, ou a mensagem a exibir. */
export function validateLoginForm(email: string, password: string): string | null {
  if (email.trim() === '') return MSG_EMAIL_REQUIRED;
  if (password === '') return MSG_PASSWORD_REQUIRED;
  if (!isValidEmailFormat(email.trim())) return MSG_EMAIL_INVALID;
  return null;
}

export default function LoginPage(): JSX.Element {
  const { login } = useAuth();

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault();

    // Validação local primeiro: bloqueia o submit sem tocar no Firebase (Req 2.3).
    const validationError = validateLoginForm(email, password);
    if (validationError !== null) {
      setError(validationError);
      return;
    }

    setError(null);
    setSubmitting(true);
    try {
      await login(email.trim(), password);
      // Sucesso: o AuthContext atualiza `user`; o redirecionamento é do roteador (Req 2.4).
    } catch (err) {
      // Preserva o e-mail digitado (Req 2.5): nunca limpamos os campos em erro.
      if (err instanceof AuthError && err.kind === 'invalid-credentials') {
        setError(MSG_AUTH_REJECTED);
      } else {
        // Indisponibilidade/timeout ou erro inesperado -> falha de comunicação (Req 2.6).
        setError(MSG_AUTH_UNAVAILABLE);
      }
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <main className="login-page">
      <form
        className="login-page__form"
        onSubmit={handleSubmit}
        noValidate
        aria-describedby={error ? 'login-error' : undefined}
      >
        <h1 className="login-page__title">Entrar no PrintDeck</h1>

        <div className="login-page__field">
          <label htmlFor="login-email">E-mail</label>
          <input
            id="login-email"
            name="email"
            type="email"
            autoComplete="username"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            disabled={submitting}
          />
        </div>

        <div className="login-page__field">
          <label htmlFor="login-password">Senha</label>
          <input
            id="login-password"
            name="password"
            type="password"
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            disabled={submitting}
          />
        </div>

        {error !== null && (
          <p id="login-error" className="login-page__error" role="alert">
            {error}
          </p>
        )}

        <button type="submit" className="btn btn--primary login-page__submit" disabled={submitting}>
          {submitting ? 'Entrando.' : 'Entrar'}
        </button>

        <p className="login-page__switch">
          Não tem conta? <Link to="/signup">Criar conta</Link>
        </p>
      </form>
    </main>
  );
}


