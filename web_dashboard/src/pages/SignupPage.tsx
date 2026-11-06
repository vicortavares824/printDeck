/**
 * SignupPage: tela de cadastro (criar conta) do Dashboard.
 *
 * Form com e-mail, senha e confirmação de senha. Validação local antes de chamar o
 * Firebase: e-mail vazio/ inválido, senha vazia, senha curta (< 6) e confirmação
 * diferente bloqueiam o submit sem tocar no Firebase. Em erro do Firebase, preserva o
 * e-mail e exibe mensagens específicas (e-mail já em uso, senha fraca) ou de
 * comunicação. Após sucesso, o onAuthStateChanged loga o usuário e o roteador redireciona.
 *
 * Reutiliza a casca visual `login-page*` (cartão centralizado no meio da tela — ver
 * theme.css) para manter consistência com o login.
 */
import { useState, type FormEvent } from 'react';
import { Link } from 'react-router-dom';

import { AuthError, useAuth } from '../auth/AuthContext';
import { isValidEmailFormat } from './LoginPage';

const MIN_PASSWORD_LENGTH = 6;

const MSG_EMAIL_REQUIRED = 'Informe o e-mail.';
const MSG_EMAIL_INVALID = 'Informe um e-mail válido (ex.: usuario@dominio.com).';
const MSG_PASSWORD_REQUIRED = 'Informe a senha.';
const MSG_PASSWORD_SHORT = `A senha deve ter ao menos ${MIN_PASSWORD_LENGTH} caracteres.`;
const MSG_CONFIRM_MISMATCH = 'As senhas não coincidem.';
const MSG_EMAIL_IN_USE = 'Este e-mail já está cadastrado. Tente entrar.';
const MSG_WEAK_PASSWORD = 'Senha muito fraca. Escolha uma senha mais forte.';
const MSG_UNAVAILABLE =
  'Não foi possível contatar o serviço de autenticação. Tente novamente em instantes.';

/** Valida o formulário de cadastro localmente. Retorna a mensagem de erro ou `null`. */
export function validateSignupForm(
  email: string,
  password: string,
  confirm: string,
): string | null {
  if (email.trim() === '') return MSG_EMAIL_REQUIRED;
  if (!isValidEmailFormat(email.trim())) return MSG_EMAIL_INVALID;
  if (password === '') return MSG_PASSWORD_REQUIRED;
  if (password.length < MIN_PASSWORD_LENGTH) return MSG_PASSWORD_SHORT;
  if (confirm !== password) return MSG_CONFIRM_MISMATCH;
  return null;
}

export default function SignupPage(): JSX.Element {
  const { signup } = useAuth();

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault();

    const validationError = validateSignupForm(email, password, confirm);
    if (validationError !== null) {
      setError(validationError);
      return;
    }

    setError(null);
    setSubmitting(true);
    try {
      await signup(email.trim(), password);
      // Sucesso: o AuthContext atualiza `user`; o redirecionamento é do roteador.
    } catch (err) {
      if (err instanceof AuthError && err.kind === 'email-in-use') {
        setError(MSG_EMAIL_IN_USE);
      } else if (err instanceof AuthError && err.kind === 'weak-password') {
        setError(MSG_WEAK_PASSWORD);
      } else if (err instanceof AuthError && err.kind === 'invalid-credentials') {
        setError(MSG_EMAIL_INVALID);
      } else {
        setError(MSG_UNAVAILABLE);
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
        aria-describedby={error ? 'signup-error' : undefined}
      >
        <h1 className="login-page__title">Criar conta no PrintDeck</h1>

        <div className="login-page__field">
          <label htmlFor="signup-email">E-mail</label>
          <input
            id="signup-email"
            name="email"
            type="email"
            autoComplete="username"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            disabled={submitting}
          />
        </div>

        <div className="login-page__field">
          <label htmlFor="signup-password">Senha</label>
          <input
            id="signup-password"
            name="new-password"
            type="password"
            autoComplete="new-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            disabled={submitting}
          />
        </div>

        <div className="login-page__field">
          <label htmlFor="signup-confirm">Confirmar senha</label>
          <input
            id="signup-confirm"
            name="confirm-password"
            type="password"
            autoComplete="new-password"
            value={confirm}
            onChange={(e) => setConfirm(e.target.value)}
            disabled={submitting}
          />
        </div>

        {error !== null && (
          <p id="signup-error" className="login-page__error" role="alert">
            {error}
          </p>
        )}

        <button
          type="submit"
          className="btn btn--primary login-page__submit"
          disabled={submitting}
        >
          {submitting ? 'Criando conta…' : 'Criar conta'}
        </button>

        <p className="login-page__switch">
          Já tem conta? <Link to="/login">Entrar</Link>
        </p>
      </form>
    </main>
  );
}

