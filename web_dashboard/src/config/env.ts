/**
 * Leitura e validação das variáveis de ambiente (import.meta.env).
 *
 * Requisitos:
 * - 8.2: URL base da Cloud_API vem de env.
 * - 8.3: URL ausente/vazia aborta a inicialização com erro claro de URL obrigatória.
 * - 8.4: credenciais do Firebase_Auth vêm de env.
 * - 8.5: credenciais Firebase ausentes/vazias abortam listando EXATAMENTE quais faltam.
 * - 8.7/8.8: NUNCA lemos/definimos uma x-api-key no frontend. Este módulo só conhece
 *   a URL da Cloud_API e as credenciais do Firebase.
 */

export interface FirebaseEnv {
  apiKey: string;
  authDomain: string;
  projectId: string;
  appId: string;
  // Opcionais: usados por alguns recursos do Firebase, mas não são obrigatórios para o Auth.
  storageBucket?: string;
  messagingSenderId?: string;
}

export interface AppEnv {
  cloudApiUrl: string;
  firebase: FirebaseEnv;
}

/** Erro de configuração de ambiente; sinaliza que a inicialização deve ser abortada. */
export class EnvValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'EnvValidationError';
  }
}

/** Variáveis obrigatórias do Firebase e o rótulo exibido quando faltam. */
const REQUIRED_FIREBASE_VARS = [
  'VITE_FIREBASE_API_KEY',
  'VITE_FIREBASE_AUTH_DOMAIN',
  'VITE_FIREBASE_PROJECT_ID',
  'VITE_FIREBASE_APP_ID',
] as const;

type RawEnv = Record<string, string | undefined>;

function isBlank(value: string | undefined): boolean {
  return value === undefined || value.trim() === '';
}

/**
 * Valida e resolve o ambiente. Lança EnvValidationError (abortando a init) quando:
 * - VITE_CLOUD_API_URL está ausente/vazia (Req 8.3); ou
 * - uma ou mais credenciais Firebase obrigatórias faltam (Req 8.5), listando quais.
 *
 * Recebe `source` para ser testável; por padrão usa import.meta.env.
 */
export function loadEnv(source: RawEnv = import.meta.env as unknown as RawEnv): AppEnv {
  // Req 8.3 — URL base da Cloud_API é obrigatória.
  const cloudApiUrl = source.VITE_CLOUD_API_URL;
  if (isBlank(cloudApiUrl)) {
    throw new EnvValidationError(
      'Configuração inválida: a URL base da Cloud_API (VITE_CLOUD_API_URL) é obrigatória e não foi definida.',
    );
  }

  // Req 8.5 — credenciais Firebase obrigatórias; listar EXATAMENTE quais faltam.
  const missing = REQUIRED_FIREBASE_VARS.filter((name) => isBlank(source[name]));
  if (missing.length > 0) {
    throw new EnvValidationError(
      `Configuração inválida: credenciais do Firebase_Auth ausentes: ${missing.join(', ')}.`,
    );
  }

  const firebase: FirebaseEnv = {
    apiKey: (source.VITE_FIREBASE_API_KEY as string).trim(),
    authDomain: (source.VITE_FIREBASE_AUTH_DOMAIN as string).trim(),
    projectId: (source.VITE_FIREBASE_PROJECT_ID as string).trim(),
    appId: (source.VITE_FIREBASE_APP_ID as string).trim(),
  };

  // Opcionais: incluídos apenas quando presentes; nunca abortam a init.
  if (!isBlank(source.VITE_FIREBASE_STORAGE_BUCKET)) {
    firebase.storageBucket = (source.VITE_FIREBASE_STORAGE_BUCKET as string).trim();
  }
  if (!isBlank(source.VITE_FIREBASE_MESSAGING_SENDER_ID)) {
    firebase.messagingSenderId = (source.VITE_FIREBASE_MESSAGING_SENDER_ID as string).trim();
  }

  return {
    cloudApiUrl: (cloudApiUrl as string).trim(),
    firebase,
  };
}

/** Ambiente validado da aplicação. Avaliar isto lança se a configuração for inválida (Req 8.3, 8.5). */
export const env: AppEnv = loadEnv();
