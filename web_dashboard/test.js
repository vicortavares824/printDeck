#!/usr/bin/env node
/*
 * web_dashboard/test.js — SMOKE / VALIDAÇÃO AGREGADA DE PONTA A PONTA (roda ao FINAL).
 * ---------------------------------------------------------------------------------
 * Este script é um smoke test AGREGADO que exercita a Cloud_API REAL (em execução)
 * de ponta a ponta. Ele COMPLEMENTA — e NÃO SUBSTITUI — os testes unitários e de
 * propriedade (PBT) do projeto:
 *   - Backend:  pytest + pytest-asyncio + httpx.AsyncClient + hypothesis
 *   - Frontend: Vitest + React Testing Library + fast-check
 *
 * Diferente dos testes unitários/PBT (que rodam isolados, com DB em memória/mocks e
 * cobrem invariantes e bordas), este arquivo faz chamadas HTTP reais contra uma
 * instância da Cloud_API para confirmar que o sistema integrado responde como o
 * esperado. Deve ser o ÚLTIMO passo de validação.
 *
 * EXECUÇÃO:
 *   node web_dashboard/test.js            # roda as checagens
 *   node web_dashboard/test.js --help     # mostra ajuda e sai (exit 0)
 *
 * Requer Node 18+ (usa `fetch` global nativo — SEM dependências externas).
 *
 * CONFIGURAÇÃO (por variáveis de ambiente, SEM segredos hardcoded):
 *   API_BASE_URL   Base da Cloud_API (ex.: http://localhost:8000). Default de dev:
 *                  http://localhost:8000. Em produção/CI, defina explicitamente.
 *   TEST_TOKEN     (opcional) Firebase_ID_Token de teste para as escritas protegidas,
 *                  enviado como `Authorization: Bearer <TEST_TOKEN>`.
 *   TEST_API_KEY   (opcional) x-api-key de teste para as escritas protegidas, enviada
 *                  como header `x-api-key`. OBS: este é um UTILITÁRIO de validação
 *                  server-side, então PODE usar x-api-key para exercitar o backend —
 *                  o FRONTEND nunca usa x-api-key (autoriza-se só por Bearer).
 *
 * SAÍDA:
 *   Imprime um resumo PASS/FAIL por checagem e sai com código != 0 se QUALQUER
 *   checagem falhar (exit 0 somente quando tudo passa).
 *
 * NOTA (tarefa 21.1): este arquivo entrega o SCAFFOLD (harness + helpers) e 1
 * checagem básica de conectividade. As checagens completas de fluxo (autorização,
 * reserva, fila, estoque) são adicionadas na tarefa 21.2 usando o mesmo harness.
 */

'use strict';

// ---------------------------------------------------------------------------
// Configuração a partir do ambiente (sem segredos hardcoded).
// ---------------------------------------------------------------------------

const DEFAULT_DEV_BASE_URL = 'http://localhost:8000';

/**
 * Lê e normaliza a configuração a partir das variáveis de ambiente.
 * Aborta com mensagem clara se API_BASE_URL faltar e não houver default aplicável.
 *
 * @returns {{ baseUrl: string, token: string | null, apiKey: string | null }}
 */
function loadConfig() {
  const rawBase = (process.env.API_BASE_URL || '').trim();
  const baseUrl = rawBase || DEFAULT_DEV_BASE_URL;

  if (!baseUrl) {
    // Caminho defensivo: só ocorre se o default for removido no futuro.
    console.error(
      'ERRO: API_BASE_URL não definida e sem default disponível.\n' +
        'Defina a base da Cloud_API, por exemplo:\n' +
        '  API_BASE_URL=http://localhost:8000 node web_dashboard/test.js',
    );
    process.exit(2);
  }

  // Remove barra final para evitar `//` ao concatenar os paths.
  const normalizedBase = baseUrl.replace(/\/+$/, '');

  const token = (process.env.TEST_TOKEN || '').trim() || null;
  const apiKey = (process.env.TEST_API_KEY || '').trim() || null;

  return { baseUrl: normalizedBase, token, apiKey };
}

// ---------------------------------------------------------------------------
// Helper de requisição HTTP (fetch nativo).
// ---------------------------------------------------------------------------

/**
 * Executa uma requisição HTTP contra a Cloud_API.
 *
 * @param {string} baseUrl  Base normalizada (sem barra final).
 * @param {string} path     Path iniciando com `/` (ex.: `/api/printers`).
 * @param {object} [options]
 * @param {string} [options.method='GET']   Método HTTP.
 * @param {object} [options.body]           Corpo JSON (serializado automaticamente).
 * @param {object} [options.auth]           Credenciais de auth para escritas protegidas.
 * @param {string} [options.auth.token]     Enviado como `Authorization: Bearer <token>`.
 * @param {string} [options.auth.apiKey]    Enviado como header `x-api-key`.
 * @param {number} [options.timeoutMs=10000] Timeout por requisição (AbortController).
 * @returns {Promise<{ status: number, ok: boolean, json: any, text: string }>}
 */
async function httpRequest(baseUrl, path, options = {}) {
  const { method = 'GET', body, auth, timeoutMs = 10000 } = options;

  const headers = { Accept: 'application/json' };
  if (body !== undefined) headers['Content-Type'] = 'application/json';

  // Auth opcional. O frontend real só usa Bearer; este utilitário de validação
  // server-side pode usar x-api-key para exercitar o backend.
  if (auth && auth.token) headers['Authorization'] = `Bearer ${auth.token}`;
  if (auth && auth.apiKey) headers['x-api-key'] = auth.apiKey;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const res = await fetch(`${baseUrl}${path}`, {
      method,
      headers,
      body: body !== undefined ? JSON.stringify(body) : undefined,
      signal: controller.signal,
    });

    const text = await res.text();
    let json;
    try {
      json = text ? JSON.parse(text) : undefined;
    } catch {
      json = undefined; // resposta não-JSON; `text` ainda fica disponível
    }

    return { status: res.status, ok: res.ok, json, text };
  } catch (err) {
    if (err && err.name === 'AbortError') {
      throw new Error(`Timeout após ${timeoutMs}ms em ${method} ${path}`);
    }
    // Erro de rede (servidor fora do ar, DNS, conexão recusada, etc.).
    const reason = err && err.message ? err.message : String(err);
    throw new Error(`Falha de rede em ${method} ${path}: ${reason}`);
  } finally {
    clearTimeout(timer);
  }
}

// Helper conveniente para GET público.
function getPublic(baseUrl, path, options = {}) {
  return httpRequest(baseUrl, path, { ...options, method: 'GET' });
}

// Helper conveniente para GET/POST/DELETE autenticado (Bearer e/ou x-api-key).
function requestAuthed(baseUrl, path, auth, options = {}) {
  return httpRequest(baseUrl, path, { ...options, auth });
}

/**
 * Monta o objeto de auth aceito por `httpRequest` a partir da config.
 * Retorna `null` quando NENHUMA credencial (token nem apiKey) está configurada —
 * sinal para as checagens protegidas degradarem para SKIP.
 *
 * @param {{ token: string | null, apiKey: string | null }} config
 * @returns {{ token?: string, apiKey?: string } | null}
 */
function buildAuth(config) {
  if (!config.token && !config.apiKey) return null;
  const auth = {};
  if (config.token) auth.token = config.token;
  if (config.apiKey) auth.apiKey = config.apiKey;
  return auth;
}

/**
 * E-mail de teste determinístico derivado de um id isolado. Usado como `device_id`
 * de posse nas checagens de estoque e como `reserved_by`/`created_by` quando não há
 * e-mail nas claims do token (ex.: auth por x-api-key).
 *
 * @param {string} id  Id de teste isolado (tipicamente derivado de timestamp).
 * @returns {string}
 */
function testEmail(id) {
  return `smoke-${id}@test.printdeck.local`;
}

/**
 * Gera um id de teste isolado a partir do timestamp + sufixo aleatório curto,
 * para evitar colisão entre execuções concorrentes/repetidas.
 *
 * @param {string} prefix  Prefixo legível (ex.: 'printer', 'item').
 * @returns {string}
 */
function makeTestId(prefix) {
  const rand = Math.random().toString(36).slice(2, 8);
  return `smoke-${prefix}-${Date.now()}-${rand}`;
}

// ---------------------------------------------------------------------------
// Mini-harness de checagens: registra nome + função async, acumula PASS/FAIL,
// imprime resumo e define o exit code.
// ---------------------------------------------------------------------------

/** Lista de checagens registradas: { name, fn }. */
const checks = [];

/**
 * Registra uma checagem. A função recebe o contexto compartilhado (config + helpers)
 * e deve lançar um erro (ou retornar rejeitado) para sinalizar FAIL. Qualquer retorno
 * sem throw é considerado PASS.
 *
 * @param {string} name                    Nome legível da checagem.
 * @param {(ctx: object) => Promise<void>} fn  Função assíncrona da checagem.
 */
function registerCheck(name, fn) {
  checks.push({ name, fn });
}

/** Lança um erro de asserção com mensagem clara quando a condição é falsa. */
function assert(condition, message) {
  if (!condition) {
    throw new Error(message || 'Asserção falhou');
  }
}

/**
 * Sentinel de SKIP: quando uma checagem não tem pré-condições (ex.: sem credenciais
 * de teste configuradas), ela lança um `SkipError` em vez de FAIL. O runner trata
 * isso como "pulada" (não conta no exit code), mas reporta no resumo (Total/PASS/
 * FAIL/SKIP). Mantém o harness mínimo: nenhuma outra mudança de contrato.
 */
class SkipError extends Error {
  constructor(message) {
    super(message || 'Checagem pulada');
    this.name = 'SkipError';
    this.isSkip = true;
  }
}

/** Lança um SkipError para sinalizar que a checagem foi pulada (SKIP, não FAIL). */
function skip(message) {
  throw new SkipError(message);
}

/**
 * Executa todas as checagens registradas em sequência, imprimindo PASS/FAIL por
 * checagem e um resumo final. Retorna o número de falhas.
 *
 * @param {object} ctx  Contexto compartilhado passado a cada checagem.
 * @returns {Promise<number>} quantidade de checagens que falharam.
 */
async function runChecks(ctx) {
  let passed = 0;
  let failed = 0;
  let skipped = 0;

  console.log('\n=== Smoke de validação agregada (web_dashboard/test.js) ===');
  console.log(`Base da Cloud_API: ${ctx.baseUrl}`);
  console.log(
    `Credenciais de teste: token=${ctx.token ? 'definido' : 'ausente'}, ` +
      `x-api-key=${ctx.apiKey ? 'definida' : 'ausente'}\n`,
  );

  for (const check of checks) {
    const started = Date.now();
    try {
      await check.fn(ctx);
      const ms = Date.now() - started;
      passed += 1;
      console.log(`PASS  ${check.name} (${ms}ms)`);
    } catch (err) {
      const ms = Date.now() - started;
      const reason = err && err.message ? err.message : String(err);
      if (err && err.isSkip) {
        // SKIP: pré-condição ausente (ex.: sem credenciais). Não é FAIL e não
        // afeta o exit code; apenas aparece no resumo.
        skipped += 1;
        console.log(`SKIP  ${check.name} (${ms}ms)`);
        console.log(`      → ${reason}`);
      } else {
        failed += 1;
        console.log(`FAIL  ${check.name} (${ms}ms)`);
        console.log(`      → ${reason}`);
      }
    }
  }

  const total = passed + failed + skipped;
  console.log('\n--- Resumo ---');
  console.log(
    `Total: ${total}  |  PASS: ${passed}  |  FAIL: ${failed}  |  SKIP: ${skipped}`,
  );
  console.log(failed === 0 ? 'Resultado: PASS (tudo verde)' : 'Resultado: FAIL');

  return failed;
}

// ---------------------------------------------------------------------------
// Checagens.
// ---------------------------------------------------------------------------
// Tarefa 21.1: apenas a checagem básica de conectividade abaixo.
// Tarefa 21.2 adicionará as checagens de fluxo (autorização, reserva, fila,
// estoque) registrando-as com `registerCheck(...)` logo abaixo desta.

// Conectividade básica: GET /api/printers deve responder 200 com um array (Req 1.1).
registerCheck('Conectividade: GET /api/printers responde 200 e array', async (ctx) => {
  const res = await getPublic(ctx.baseUrl, '/api/printers');
  assert(
    res.status === 200,
    `esperava 200 em GET /api/printers, recebeu ${res.status}` +
      (res.text ? ` (corpo: ${res.text.slice(0, 200)})` : ''),
  );
  assert(
    Array.isArray(res.json),
    `esperava um array no corpo de GET /api/printers, recebeu ${typeof res.json}`,
  );
});

// ---------------------------------------------------------------------------
// Checagens de fluxo integrado (tarefa 21.2).
// ---------------------------------------------------------------------------
// Cada checagem usa `assert` para PASS/FAIL e `ctx.skip(...)` quando falta uma
// pré-condição (ex.: sem credenciais de teste). Ids de teste são isolados por
// timestamp e a checagem faz limpeza do que cria (itens de fila/estoque) sempre
// que possível. A execução REAL contra o servidor é a tarefa 21.3 — aqui o foco é
// que o script seja válido e degrade para SKIP sem credenciais.

// --- 1. Backend responde (fila por printer_id de teste) --------------------
// GET /api/printers já é coberto pela checagem de conectividade acima; aqui
// validamos o contrato público da fila por um printer_id isolado (Req 13.1-13.3).
registerCheck(
  'Backend: GET /api/printers/{id}/queue responde 200 e array',
  async (ctx) => {
    const printerId = makeTestId('printer');
    const res = await ctx.getPublic(
      `/api/printers/${encodeURIComponent(printerId)}/queue`,
    );
    ctx.assert(
      res.status === 200,
      `esperava 200 em GET .../queue, recebeu ${res.status}` +
        (res.text ? ` (corpo: ${res.text.slice(0, 200)})` : ''),
    );
    ctx.assert(
      Array.isArray(res.json),
      `esperava um array no corpo de GET .../queue, recebeu ${typeof res.json}`,
    );
    // Fila de um printer_id novo deve vir vazia (Req 13.3).
    ctx.assert(
      res.json.length === 0,
      `esperava fila vazia para printer_id novo, recebeu ${res.json.length} itens`,
    );
  },
);

// --- 2. Autorização: 401 sem auth; 2xx com auth (ou SKIP) ------------------
// Endpoint protegido: POST .../queue. Sem auth DEVE responder 401 (Req 13.8/18.4).
// Com auth válida DEVE autorizar (2xx). Sem credenciais, só valida o 401 (SKIP do
// ramo autorizado, Req 18.5).
registerCheck(
  'Autorização: POST .../queue 401 sem auth e 2xx com auth',
  async (ctx) => {
    const printerId = makeTestId('printer');
    const queuePath = `/api/printers/${encodeURIComponent(printerId)}/queue`;

    // 2a) SEM auth → 401 (sempre validado). Usa requestAuthed com auth=null para
    // enviar o POST sem credenciais (getPublic forçaria GET e não aceita body).
    const noAuth = await ctx.requestAuthed(queuePath, null, {
      method: 'POST',
      body: { sku: 'SMOKE-AUTH', name: 'auth probe' },
    });
    ctx.assert(
      noAuth.status === 401,
      `esperava 401 em POST .../queue sem auth, recebeu ${noAuth.status}` +
        (noAuth.text ? ` (corpo: ${noAuth.text.slice(0, 200)})` : ''),
    );

    // 2b) COM auth → 2xx. Sem credenciais, SKIP deste ramo (não FAIL).
    const auth = ctx.buildAuth();
    if (!auth) {
      ctx.skip(
        'sem TEST_TOKEN/TEST_API_KEY: validado apenas o 401 sem auth; ramo autorizado pulado',
      );
    }

    const authed = await ctx.requestAuthed(queuePath, auth, {
      method: 'POST',
      body: {
        sku: 'SMOKE-AUTH',
        name: 'auth probe',
        created_by: testEmail(printerId),
      },
    });
    ctx.assert(
      authed.status >= 200 && authed.status < 300,
      `esperava 2xx em POST .../queue com auth, recebeu ${authed.status}` +
        (authed.text ? ` (corpo: ${authed.text.slice(0, 200)})` : ''),
    );

    // Limpeza: remove o item criado para não deixar resíduo na fila de teste.
    if (authed.json && typeof authed.json.id === 'number') {
      await ctx
        .requestAuthed(`${queuePath}/${authed.json.id}`, auth, {
          method: 'DELETE',
        })
        .catch(() => {
          /* limpeza best-effort; não falha a checagem */
        });
    }
  },
);

// --- 3. Reserva: round-trip ocupar/liberar (ou SKIP) -----------------------
// Precisa de auth. `reserve` exige que o printer_id exista em telemetry_logs
// (senão 404), então o script primeiro cria o printer via POST /api/telemetry
// (também protegido). Sem auth, SKIP de toda a checagem (Req 11.9).
registerCheck(
  'Reserva: round-trip ocupar/liberar (POST reserve/release)',
  async (ctx) => {
    const auth = ctx.buildAuth();
    if (!auth) {
      ctx.skip('sem TEST_TOKEN/TEST_API_KEY: reserva exige auth; checagem pulada');
    }

    const printerId = makeTestId('printer');
    const reservedBy = testEmail(printerId);

    // Pré-condição: criar o printer em telemetry_logs via POST /api/telemetry
    // (protegido). Sem isso, reserve responde 404 (Req 11.13).
    const telemetry = await ctx.requestAuthed('/api/telemetry', auth, {
      method: 'POST',
      body: { printer_id: printerId, state: 'idle', model: 'SmokeTest' },
    });
    ctx.assert(
      telemetry.status >= 200 && telemetry.status < 300,
      `esperava 2xx ao criar telemetria para o printer de teste, recebeu ${telemetry.status}` +
        (telemetry.text ? ` (corpo: ${telemetry.text.slice(0, 200)})` : ''),
    );

    const reservePath = `/api/printers/${encodeURIComponent(printerId)}/reserve`;
    const releasePath = `/api/printers/${encodeURIComponent(printerId)}/release`;

    // Ocupar → reserved=true.
    const reserved = await ctx.requestAuthed(reservePath, auth, {
      method: 'POST',
      body: { reserved_by: reservedBy },
    });
    ctx.assert(
      reserved.status === 200,
      `esperava 200 em POST reserve, recebeu ${reserved.status}` +
        (reserved.text ? ` (corpo: ${reserved.text.slice(0, 200)})` : ''),
    );
    ctx.assert(
      reserved.json && reserved.json.reserved === true,
      `esperava reserved=true após reserve, recebeu ${JSON.stringify(reserved.json)}`,
    );

    // Liberar → reserved=false.
    const released = await ctx.requestAuthed(releasePath, auth, {
      method: 'POST',
    });
    ctx.assert(
      released.status === 200,
      `esperava 200 em POST release, recebeu ${released.status}` +
        (released.text ? ` (corpo: ${released.text.slice(0, 200)})` : ''),
    );
    ctx.assert(
      released.json && released.json.reserved === false,
      `esperava reserved=false após release, recebeu ${JSON.stringify(released.json)}`,
    );
  },
);

// --- 4. Fila: add → reorder → remove mantendo posições contíguas (ou SKIP) -
// Precisa de auth. Adiciona itens, lê a fila ordenada, reordena via ordered_ids,
// confirma a nova ordem e posições contíguas (1..n), remove um e confirma a
// reindexação (Req 13.6, 13.14, 13.18, 13.22).
registerCheck(
  'Fila: add/reorder/remove mantendo posições contíguas (1..n)',
  async (ctx) => {
    const auth = ctx.buildAuth();
    if (!auth) {
      ctx.skip('sem TEST_TOKEN/TEST_API_KEY: escrita de fila exige auth; checagem pulada');
    }

    const printerId = makeTestId('printer');
    const queuePath = `/api/printers/${encodeURIComponent(printerId)}/queue`;
    const createdBy = testEmail(printerId);
    const createdIds = [];

    // Valida que as posições de uma fila ordenada por position são exatamente 1..n.
    const assertContiguous = (items, where) => {
      ctx.assert(
        Array.isArray(items),
        `${where}: esperava um array, recebeu ${typeof items}`,
      );
      items.forEach((item, idx) => {
        ctx.assert(
          item.position === idx + 1,
          `${where}: posição não contígua no índice ${idx} ` +
            `(esperava ${idx + 1}, recebeu ${item.position})`,
        );
      });
    };

    try {
      // Add 3 itens (vão para o fim, posições 1,2,3 — Req 13.6).
      for (let i = 1; i <= 3; i += 1) {
        const added = await ctx.requestAuthed(queuePath, auth, {
          method: 'POST',
          body: { sku: `SMOKE-SKU-${i}`, name: `item ${i}`, created_by: createdBy },
        });
        ctx.assert(
          added.status >= 200 && added.status < 300,
          `esperava 2xx ao adicionar item ${i}, recebeu ${added.status}` +
            (added.text ? ` (corpo: ${added.text.slice(0, 200)})` : ''),
        );
        ctx.assert(
          added.json && typeof added.json.id === 'number',
          `esperava um id numérico no item adicionado, recebeu ${JSON.stringify(added.json)}`,
        );
        createdIds.push(added.json.id);
      }

      // Lê a fila ordenada e confirma contiguidade 1..n.
      const listed = await ctx.getPublic(queuePath);
      ctx.assert(listed.status === 200, `esperava 200 ao ler a fila, recebeu ${listed.status}`);
      assertContiguous(listed.json, 'após add');
      ctx.assert(
        listed.json.length === createdIds.length,
        `esperava ${createdIds.length} itens na fila, recebeu ${listed.json.length}`,
      );

      // Reordena invertendo a ordem atual via ordered_ids.
      const currentIds = listed.json.map((it) => it.id);
      const reversedIds = [...currentIds].reverse();
      const reordered = await ctx.requestAuthed(`${queuePath}/reorder`, auth, {
        method: 'POST',
        body: { ordered_ids: reversedIds },
      });
      ctx.assert(
        reordered.status === 200,
        `esperava 200 em reorder, recebeu ${reordered.status}` +
          (reordered.text ? ` (corpo: ${reordered.text.slice(0, 200)})` : ''),
      );
      assertContiguous(reordered.json, 'após reorder');
      const newOrderIds = reordered.json.map((it) => it.id);
      ctx.assert(
        JSON.stringify(newOrderIds) === JSON.stringify(reversedIds),
        `esperava nova ordem ${JSON.stringify(reversedIds)}, recebeu ${JSON.stringify(newOrderIds)}`,
      );

      // Remove o primeiro da nova ordem e confirma reindexação contígua.
      const removeId = newOrderIds[0];
      const afterRemove = await ctx.requestAuthed(`${queuePath}/${removeId}`, auth, {
        method: 'DELETE',
      });
      ctx.assert(
        afterRemove.status === 200,
        `esperava 200 em remove, recebeu ${afterRemove.status}` +
          (afterRemove.text ? ` (corpo: ${afterRemove.text.slice(0, 200)})` : ''),
      );
      assertContiguous(afterRemove.json, 'após remove');
      ctx.assert(
        afterRemove.json.length === newOrderIds.length - 1,
        `esperava ${newOrderIds.length - 1} itens após remove, recebeu ${afterRemove.json.length}`,
      );
      ctx.assert(
        !afterRemove.json.some((it) => it.id === removeId),
        `o item removido (id ${removeId}) ainda aparece na fila`,
      );
      // O item removido não precisa mais de limpeza.
      const removedIdx = createdIds.indexOf(removeId);
      if (removedIdx >= 0) createdIds.splice(removedIdx, 1);
    } finally {
      // Limpeza best-effort: remove os itens de fila remanescentes criados aqui.
      for (const id of createdIds) {
        await ctx
          .requestAuthed(`${queuePath}/${id}`, auth, { method: 'DELETE' })
          .catch(() => {
            /* limpeza best-effort; não falha a checagem */
          });
      }
    }
  },
);

// --- 5. Estoque: list → sync → delete respeitando posse (ou SKIP) ----------
// Precisa de auth. Lista o inventário, sincroniza um item novo (posse por
// device_id = e-mail de teste), confirma synced>=1 e depois exclui o item
// (Req 15.2, 16.10). Sem auth, SKIP (os endpoints de supply exigem auth).
registerCheck(
  'Estoque: list/sync/delete respeitando posse (device_id por e-mail)',
  async (ctx) => {
    const auth = ctx.buildAuth();
    if (!auth) {
      ctx.skip('sem TEST_TOKEN/TEST_API_KEY: estoque exige auth; checagem pulada');
    }

    const itemId = makeTestId('item');
    const deviceId = testEmail(itemId);
    let created = false;

    try {
      // list → 200 e array.
      const listPath = `/api/supply/items?device_id=${encodeURIComponent(deviceId)}`;
      const listed = await ctx.requestAuthed(listPath, auth, { method: 'GET' });
      ctx.assert(
        listed.status === 200,
        `esperava 200 em GET /api/supply/items, recebeu ${listed.status}` +
          (listed.text ? ` (corpo: ${listed.text.slice(0, 200)})` : ''),
      );
      ctx.assert(
        Array.isArray(listed.json),
        `esperava um array em GET /api/supply/items, recebeu ${typeof listed.json}`,
      );

      // sync de um item novo → synced>=1.
      const synced = await ctx.requestAuthed('/api/supply/sync', auth, {
        method: 'POST',
        body: {
          device_id: deviceId,
          items: [
            {
              item_id: itemId,
              title: 'Smoke Item',
              description: 'criado pelo smoke test',
              quantity: 1,
              is_bought: false,
            },
          ],
        },
      });
      ctx.assert(
        synced.status === 200,
        `esperava 200 em POST /api/supply/sync, recebeu ${synced.status}` +
          (synced.text ? ` (corpo: ${synced.text.slice(0, 200)})` : ''),
      );
      ctx.assert(
        synced.json && typeof synced.json.synced === 'number' && synced.json.synced >= 1,
        `esperava synced>=1, recebeu ${JSON.stringify(synced.json)}`,
      );
      created = true;

      // delete do item → ok (posse por device_id = e-mail de teste).
      const deletePath =
        `/api/supply/items/${encodeURIComponent(itemId)}` +
        `?device_id=${encodeURIComponent(deviceId)}`;
      const deleted = await ctx.requestAuthed(deletePath, auth, { method: 'DELETE' });
      ctx.assert(
        deleted.status === 200,
        `esperava 200 em DELETE /api/supply/items/{id}, recebeu ${deleted.status}` +
          (deleted.text ? ` (corpo: ${deleted.text.slice(0, 200)})` : ''),
      );
      ctx.assert(
        deleted.json && deleted.json.deleted === true,
        `esperava {deleted:true}, recebeu ${JSON.stringify(deleted.json)}`,
      );
      created = false;
    } finally {
      // Limpeza best-effort caso o delete acima não tenha ocorrido.
      if (created) {
        const cleanupPath =
          `/api/supply/items/${encodeURIComponent(itemId)}` +
          `?device_id=${encodeURIComponent(deviceId)}`;
        await ctx
          .requestAuthed(cleanupPath, auth, { method: 'DELETE' })
          .catch(() => {
            /* limpeza best-effort; não falha a checagem */
          });
      }
    }
  },
);

// ---------------------------------------------------------------------------
// --help
// ---------------------------------------------------------------------------

function printHelp() {
  console.log(
    [
      'web_dashboard/test.js — smoke de validação agregada de ponta a ponta.',
      '',
      'Uso:',
      '  node web_dashboard/test.js            Roda as checagens contra a Cloud_API',
      '  node web_dashboard/test.js --help     Mostra esta ajuda',
      '',
      'Variáveis de ambiente:',
      `  API_BASE_URL   Base da Cloud_API (default dev: ${DEFAULT_DEV_BASE_URL})`,
      '  TEST_TOKEN     (opcional) Firebase_ID_Token de teste (Authorization: Bearer)',
      '  TEST_API_KEY   (opcional) x-api-key de teste (header x-api-key)',
      '',
      'Saída: resumo PASS/FAIL/SKIP por checagem; exit != 0 somente se houver FAIL.',
      '',
      'SKIP: checagens protegidas (reserva, fila, estoque e o ramo autorizado da',
      'autorização) são puladas — não falham — quando NENHUMA credencial de teste',
      '(TEST_TOKEN ou TEST_API_KEY) está configurada.',
    ].join('\n'),
  );
}

// ---------------------------------------------------------------------------
// Entrypoint.
// ---------------------------------------------------------------------------

async function main() {
  const args = process.argv.slice(2);
  if (args.includes('--help') || args.includes('-h')) {
    printHelp();
    process.exit(0);
  }

  // Node 18+ expõe `fetch` global. Degrada com mensagem clara se ausente.
  if (typeof fetch !== 'function') {
    console.error(
      'ERRO: `fetch` global não disponível. Use Node 18+ para rodar este script.',
    );
    process.exit(2);
  }

  const config = loadConfig();
  const ctx = {
    ...config,
    // Helpers expostos às checagens para evitar recriar lógica em 21.2.
    getPublic: (path, options) => getPublic(config.baseUrl, path, options),
    requestAuthed: (path, auth, options) =>
      requestAuthed(config.baseUrl, path, auth, options),
    assert,
    skip,
    // Monta o objeto de auth (Bearer e/ou x-api-key) a partir da config, ou null
    // quando NENHUMA credencial foi configurada (checagens degradam para SKIP).
    buildAuth: () => buildAuth(config),
  };

  const failed = await runChecks(ctx);
  // exit != 0 quando qualquer checagem falha (ex.: servidor fora do ar → FAIL de
  // conectividade). Isso é o comportamento esperado sem servidor; a execução real
  // validada é a tarefa 21.3.
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((err) => {
  // Rede defensiva: qualquer erro não tratado não deve travar silenciosamente.
  const reason = err && err.message ? err.message : String(err);
  console.error(`ERRO inesperado: ${reason}`);
  process.exit(1);
});
