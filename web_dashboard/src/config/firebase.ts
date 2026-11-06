/**
 * Inicialização do Firebase_Auth a partir das credenciais validadas em env.ts.
 * Req 8.4: initializeApp + getAuth usando as credenciais do ambiente.
 */
import { initializeApp, type FirebaseApp } from 'firebase/app';
import { getAuth, type Auth } from 'firebase/auth';

import { env } from './env';

export const firebaseApp: FirebaseApp = initializeApp({
  apiKey: env.firebase.apiKey,
  authDomain: env.firebase.authDomain,
  projectId: env.firebase.projectId,
  appId: env.firebase.appId,
  storageBucket: env.firebase.storageBucket,
  messagingSenderId: env.firebase.messagingSenderId,
});

export const auth: Auth = getAuth(firebaseApp);
