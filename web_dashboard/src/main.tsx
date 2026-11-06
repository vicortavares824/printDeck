/**
 * Bootstrap do Dashboard.
 *
 * Valida o ambiente ANTES de montar a aplicação (Req 8.3, 8.5): se a URL da
 * Cloud_API ou as credenciais do Firebase faltarem, env.ts lança EnvValidationError;
 * aqui capturamos e exibimos a mensagem de erro clara, sem montar a SPA.
 */
import './styles/theme.css';

import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';

import { EnvValidationError, loadEnv } from './config/env';

const rootElement = document.getElementById('root');
if (!rootElement) {
  throw new Error('Elemento #root não encontrado no documento.');
}

function renderFatalError(message: string): void {
  rootElement!.innerHTML = '';
  const container = document.createElement('div');
  container.setAttribute('role', 'alert');
  container.style.cssText =
    'max-width:640px;margin:48px auto;padding:24px;font-family:system-ui,sans-serif;' +
    'border:1px solid #C62828;border-radius:8px;color:#1A2733;background:#FFFFFF;';

  const title = document.createElement('h1');
  title.textContent = 'Erro de configuração';
  title.style.cssText = 'margin:0 0 12px;font-size:18px;color:#C62828;';

  const detail = document.createElement('p');
  detail.textContent = message;
  detail.style.cssText = 'margin:0;line-height:1.5;';

  container.append(title, detail);
  rootElement!.append(container);
}

async function bootstrap(): Promise<void> {
  try {
    // Dispara a validação de env (Req 8.3, 8.5) antes de qualquer import que a utilize.
    loadEnv();
  } catch (error) {
    if (error instanceof EnvValidationError) {
      renderFatalError(error.message);
      return;
    }
    renderFatalError(
      error instanceof Error ? error.message : 'Falha desconhecida ao validar a configuração.',
    );
    return;
  }

  // Import dinâmico para que config/firebase.ts (que usa env) só avalie após a validação.
  const { default: App } = await import('./App');

  createRoot(rootElement!).render(
    <StrictMode>
      <App />
    </StrictMode>,
  );
}

void bootstrap();
