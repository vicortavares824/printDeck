/**
 * AuthContext: provider React que encapsula o Firebase_Auth do Dashboard (Req 2, 18).
 *
 * - user: usuario Firebase atual (null quando sem sessao).
 * - initializing: true enquanto o primeiro onAuthStateChanged nao resolveu.
 * - login(email, password): signInWithEmailAndPassword com timeout de 10s (Req 2.6).
 * - signup(email, password): createUserWithEmailAndPassword com timeout de 10s.
 * - logout(): signOut (Req 2.8).
 * - getToken(forceRefresh?): getIdToken do usuario atual (Req 18).
 *
 * Usa o auth ja inicializado em config/firebase.ts. Este modulo NAO conhece
 * x-api-key (Req 8.7, 8.8): a autorizacao ao backend e exclusivamente pelo
 * Firebase_ID_Token.
 */
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import {
  createUserWithEmailAndPassword,
  onAuthStateChanged,
  signInWithEmailAndPassword,
  signOut,
  type User as FirebaseUser,
} from 'firebase/auth';

import { auth } from '../config/firebase';

/** Timeout maximo de uma tentativa de login/cadastro (Req 2.6: 10 segundos). */
export const LOGIN_TIMEOUT_MS = 10_000;

/** Categorias de erro que login/cadastro podem propagar. */
export type AuthErrorKind =
  | 'invalid-credentials'
  | 'email-in-use'
  | 'weak-password'
  | 'unavailable';

/** Erro tipado emitido por login/signup. */
export class AuthError extends Error {
  readonly kind: AuthErrorKind;
  readonly cause?: unknown;

  constructor(kind: AuthErrorKind, message: string, options: { cause?: unknown } = {}) {
    super(message);
    this.name = 'AuthError';
    this.kind = kind;
    this.cause = options.cause;
    Object.setPrototypeOf(this, AuthError.prototype);
  }
}

/** Interface do estado/acoes de autenticacao. */
export interface AuthState {
  user: FirebaseUser | null;
  initializing: boolean;
  login(email: string, password: string): Promise<void>;
  signup(email: string, password: string): Promise<void>;
  logout(): Promise<void>;
  getToken(forceRefresh?: boolean): Promise<string>;
}

const AuthContext = createContext<AuthState | null>(null);

/** Codigos do Firebase que representam credenciais invalidas/rejeitadas (Req 2.5). */
const INVALID_CREDENTIAL_CODES = new Set<string>([
  'auth/invalid-credential',
  'auth/invalid-email',
  'auth/user-not-found',
  'auth/wrong-password',
  'auth/user-disabled',
]);

/** Extrai o code de um erro do Firebase (FirebaseError) quando presente. */
function firebaseErrorCode(error: unknown): string | undefined {
  if (typeof error === 'object' && error !== null && 'code' in error) {
    const code = (error as { code?: unknown }).code;
    return typeof code === 'string' ? code : undefined;
  }
  return undefined;
}

/** Promessa que rejeita apos ms com um sentinela de timeout. */
function timeout(ms: number): { promise: Promise<never>; cancel: () => void } {
  let timer: ReturnType<typeof setTimeout>;
  const promise = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new AuthError('unavailable', 'timeout')), ms);
  });
  return { promise, cancel: () => clearTimeout(timer) };
}

/** Mapeia um erro de login para AuthError. */
function mapLoginError(error: unknown): AuthError {
  if (error instanceof AuthError) return error;
  const code = firebaseErrorCode(error);
  if (code && INVALID_CREDENTIAL_CODES.has(code)) {
    return new AuthError('invalid-credentials', 'Credenciais rejeitadas.', { cause: error });
  }
  return new AuthError('unavailable', 'Falha de comunicacao com o servico de autenticacao.', {
    cause: error,
  });
}

/** Mapeia um erro de cadastro para AuthError (casos especificos de signup). */
function mapSignupError(error: unknown): AuthError {
  if (error instanceof AuthError) return error;
  const code = firebaseErrorCode(error);
  if (code === 'auth/email-already-in-use') {
    return new AuthError('email-in-use', 'E-mail ja cadastrado.', { cause: error });
  }
  if (code === 'auth/weak-password') {
    return new AuthError('weak-password', 'Senha fraca.', { cause: error });
  }
  if (code === 'auth/invalid-email') {
    return new AuthError('invalid-credentials', 'E-mail invalido.', { cause: error });
  }
  return new AuthError('unavailable', 'Falha de comunicacao com o servico de autenticacao.', {
    cause: error,
  });
}

export interface AuthProviderProps {
  children: ReactNode;
}

export function AuthProvider({ children }: AuthProviderProps): JSX.Element {
  const [user, setUser] = useState<FirebaseUser | null>(null);
  const [initializing, setInitializing] = useState<boolean>(true);
  const userRef = useRef<FirebaseUser | null>(null);

  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, (nextUser) => {
      userRef.current = nextUser;
      setUser(nextUser);
      setInitializing(false);
    });
    return unsubscribe;
  }, []);

  const login = useCallback(async (email: string, password: string): Promise<void> => {
    const t = timeout(LOGIN_TIMEOUT_MS);
    try {
      await Promise.race([signInWithEmailAndPassword(auth, email, password), t.promise]);
    } catch (error) {
      throw mapLoginError(error);
    } finally {
      t.cancel();
    }
  }, []);

  const signup = useCallback(async (email: string, password: string): Promise<void> => {
    const t = timeout(LOGIN_TIMEOUT_MS);
    try {
      await Promise.race([createUserWithEmailAndPassword(auth, email, password), t.promise]);
    } catch (error) {
      throw mapSignupError(error);
    } finally {
      t.cancel();
    }
  }, []);

  const logout = useCallback(async (): Promise<void> => {
    await signOut(auth);
  }, []);

  const getToken = useCallback(async (forceRefresh = false): Promise<string> => {
    const current = userRef.current;
    if (!current) {
      throw new AuthError('unavailable', 'Sem sessao ativa para obter o token.');
    }
    return current.getIdToken(forceRefresh);
  }, []);

  const value = useMemo<AuthState>(
    () => ({ user, initializing, login, signup, logout, getToken }),
    [user, initializing, login, signup, logout, getToken],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthState {
  const ctx = useContext(AuthContext);
  if (ctx === null) {
    throw new Error('useAuth deve ser usado dentro de um <AuthProvider>.');
  }
  return ctx;
}

export { AuthContext };