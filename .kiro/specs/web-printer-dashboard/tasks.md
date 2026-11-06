# Implementation Plan: web-printer-dashboard

## Overview

Este plano implementa a feature em duas partes integradas: (A) extensões do backend Cloud_API
(FastAPI + SQLAlchemy async, em `cloud_api/`) e (B) o novo frontend React + Vite + TypeScript isolado
em `web_dashboard/`. A ordem prioriza o backend, para que o frontend tenha endpoints reais a consumir,
intercalando cedo o scaffold do frontend. Cada tarefa é incremental e termina integrada ao que já
existe, sem código órfão. Os testes seguem a Testing Strategy do design: backend com
`pytest` + `pytest-asyncio` + `httpx.AsyncClient` + `hypothesis`; frontend com `Vitest` + React
Testing Library + `fast-check`. Cada Correctness Property (P1..P10) tem uma subtarefa de teste
baseada em propriedade, com no mínimo 100 iterações, usando as libs prontas, anotada com a tag
`Feature: web-printer-dashboard, Property N: <nome>`.

## Tasks

- [x] 1. Autenticação e autorização JWT no backend (require_auth)
  - [x] 1.1 Configurar firebase-admin e credenciais de service account
    - Adicionar `firebase-admin>=6.5.0` em `cloud_api/requirements.txt`
    - Adicionar `FIREBASE_SERVICE_ACCOUNT_JSON` em `cloud_api/app/core/config.py` (service account inline em env; coerente com Render)
    - Inicializar o app firebase-admin no `lifespan` a partir da env; quando ausente, não inicializar e logar uma única vez no startup (degradação segura)
    - _Requirements: 18.7, 18.8_
  - [x] 1.2 Criar a dependency require_auth em app/core/auth.py
    - Criar `cloud_api/app/core/auth.py` com `Identity(email, uid, via)` e a função `require_auth`
    - Tentar `Firebase_ID_Token` via `firebase_admin.auth.verify_id_token`; derivar `email`/`uid` das claims; token inválido/expirado/malformado → não autoriza por token
    - Fallback para `x-api-key` válida; sem token válido e sem `x-api-key` válida → `HTTPException(401)` sem efeito colateral
    - Quando credenciais ausentes, `_verify_firebase_token` sempre retorna `None` (só `x-api-key` autoriza)
    - _Requirements: 18.1, 18.2, 18.3, 18.4, 18.5, 18.6, 18.8_
  - [ ]* 1.3 Escrever teste de propriedade para API_Authorization
    - **Feature: web-printer-dashboard, Property 9: API_Authorization autoriza sse token válido OU x-api-key válida**
    - **Validates: Requirements 11.9, 13.8, 18.4, 18.5**
    - `hypothesis`, mínimo 100 iterações; combinações de `Authorization: Bearer` (válido/inválido/ausente via `verify_id_token` mockado) e `x-api-key` (válida/inválida/ausente) contra endpoint protegido; autorizado sse token válido OU key válida, senão 401 sem efeito
  - [ ]* 1.4 Escrever testes de exemplo da inicialização e degradação segura
    - Inicialização do firebase-admin com e sem credenciais; sem credenciais só `x-api-key` autoriza
    - _Requirements: 18.7, 18.8_

- [x] 2. Coluna model em PrinterTelemetry e auto-migração
  - [x] 2.1 Adicionar coluna model e auto-migração idempotente
    - Adicionar `model = Column(String, nullable=True)` em `PrinterTelemetry` (`telemetry_logs`)
    - Criar `_ensure_telemetry_schema` (padrão `_ensure_supply_schema`) para SQLite (`PRAGMA table_info` + `ADD COLUMN` condicional) e PostgreSQL (`ADD COLUMN IF NOT EXISTS`), chamada no `lifespan`, com `try/except` que loga e segue o boot
    - _Requirements: 9.1, 9.2, 9.3, 9.11_
  - [x] 2.2 Persistir e expor model nos schemas e no POST /api/telemetry
    - `TelemetryIn.model: str | None = None` (opcional); `POST /api/telemetry` persiste `model` (null quando omitido)
    - `TelemetryOut.model: str | None`; registros antigos retornam `model=None` sem erro
    - _Requirements: 9.4, 9.5, 9.6, 9.7, 9.8, 9.9_
  - [ ]* 2.3 Escrever testes de migração e dos campos model
    - Auto-migração idempotente (coluna já existente não altera o schema); `model` null para omissão e para registros legados
    - _Requirements: 9.2, 9.3, 9.6, 9.8, 9.9_

- [x] 3. Reserva manual na Cloud_API
  - [x] 3.1 Criar tabela printer_reservations e schemas de reserva
    - Criar modelo `PrinterReservation` (`printer_id` PK, `reserved`, `reserved_by`, `reserved_at`) via `create_all` no `lifespan`
    - Criar schemas `ReserveIn` (`reserved_by` opcional) e `ReservationOut`
    - _Requirements: 11.5_
  - [x] 3.2 Implementar endpoints de ocupar e liberar
    - `POST /api/printers/{printer_id}/reserve` e `POST /api/printers/{printer_id}/release` com `Depends(require_auth)`
    - Ocupar: upsert `reserved=True`, `reserved_at=utcnow()`, `reserved_by` = `identity.email` do token ou corpo; já reservada → substitui e responde 200
    - `reserved_by` ausente/vazio e sem email no token → 422 sem alterar estado
    - Liberar: upsert `reserved=False`, `reserved_by=None`, `reserved_at=None`; não reservada → 200 mantendo não reservado
    - `printer_id` inexistente em `telemetry_logs` → 404 sem criar reserva
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.7, 11.8, 11.9, 11.10, 11.11, 11.12, 11.13_
  - [ ]* 3.3 Escrever testes de exemplo da reserva
    - Round-trip ocupar/liberar; 422 sem `reserved_by`; 404 `printer_id` inexistente; reservar já reservado e liberar não reservado → 200
    - _Requirements: 11.3, 11.4, 11.10, 11.11, 11.12, 11.13_

- [x] 4. Printer_List_Endpoint com modelo e reserva
  - [x] 4.1 Implementar GET /api/printers público com latest + merge de reserva
    - Handler público em `app/main.py` (sem `require_auth`); latest por `printer_id` via subquery `max(created_at)` + desempate `max(id)`, ordenado desc por `created_at` (compatível SQLite + PostgreSQL)
    - Merge do Reservation_State por `printer_id` (default `reserved=false`, `reserved_by=null`, `reserved_at=null` quando ausente); schema `PrinterOut` = `TelemetryOut` + `model` + Reservation_State; campos nulos como `null`
    - Lista vazia → `[]` com 200; falha de DB → `HTTPException(500)` sem escrita
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 1.10, 1.11, 1.12, 9.7_
  - [x] 4.2 Atualizar GET /api/telemetry/latest/{printer_id} para PrinterOut
    - Passar a retornar `PrinterOut` com `model` + Reservation_State (mesmos padrões de null da Req 1)
    - _Requirements: 9.7, 9.10_
  - [ ]* 4.3 Escrever teste de propriedade da seleção do mais recente por impressora com reserva
    - **Feature: web-printer-dashboard, Property 1: Seleção do registro mais recente por impressora com reserva**
    - **Validates: Requirements 1.2, 1.3, 1.7, 1.8**
    - `hypothesis`, mínimo 100 iterações; gerar `telemetry_logs` (vários ids/registros, `created_at` com empates) e subconjunto de `printer_reservations`; verificar exatamente um item por `printer_id`, seleção `(max created_at, max id)`, ordem desc e merge do Reservation_State
  - [ ]* 4.4 Escrever testes de exemplo do endpoint de listagem
    - Sem `x-api-key` → 200; `current_file`/`filament_info`/`model` nulos → `null`; DB vazio → `[]`
    - _Requirements: 1.5, 1.9, 1.10, 9.8_

- [x] 5. Fila de impressão na Cloud_API
  - [x] 5.1 Criar tabela print_queue_items e schemas de fila
    - Criar modelo `PrintQueueItem` (`id`, `printer_id` indexado, `sku`, `name`, `position`, `created_at`, `created_by`) via `create_all`
    - Criar schemas `QueueAddIn`, `QueueReorderIn` (`ordered_ids`) e `QueueItemOut`; helper `reindex` (posições `1..n` preservando ordem relativa)
    - _Requirements: 13.19, 13.22_
  - [x] 5.2 Implementar GET público da Print_Queue
    - `GET /api/printers/{printer_id}/queue` público, itens ordenados por `position` asc; fila vazia → `[]` com 200; opera por `printer_id` textual mesmo sem registro em `telemetry_logs`
    - _Requirements: 13.1, 13.2, 13.3, 13.4, 13.21_
  - [x] 5.3 Implementar add e remove da Print_Queue
    - `POST /api/printers/{printer_id}/queue` (require_auth): `position = max+1` (ou primeira se vazia); `created_by` = email do token ou corpo; `sku` vazio → 422
    - `DELETE /api/printers/{printer_id}/queue/{item_id}` (require_auth): 404 se `id` inexistente; reindexar restantes (únicas/contíguas, ordem preservada)
    - _Requirements: 13.5, 13.6, 13.7, 13.8, 13.9, 13.10, 13.11, 13.12_
  - [x] 5.4 Implementar reorder e mark-printed da Print_Queue
    - `POST /api/printers/{printer_id}/queue/reorder` (require_auth): lista ordenada de `id`; conjunto deve bater com a fila, senão 422 sem alterar; recalcular `position` conforme a ordem
    - `POST /api/printers/{printer_id}/queue/{item_id}/mark-printed` (require_auth): 404 se `id` inexistente; remover da fila ativa e reindexar
    - _Requirements: 13.13, 13.14, 13.15, 13.16, 13.17, 13.18_
  - [ ]* 5.5 Escrever teste de propriedade do invariante de ordem da Print_Queue
    - **Feature: web-printer-dashboard, Property 8: Invariante de ordem da Print_Queue**
    - **Validates: Requirements 13.6, 13.12, 13.14, 13.18, 13.22**
    - `hypothesis`, mínimo 100 iterações; sequências de add/remove/reorder/mark-printed contra os endpoints; após cada operação posições únicas e contíguas (`1..n`), ordem relativa preservada, add no fim, reorder consistente atribui posição por ordem
  - [ ]* 5.6 Escrever testes de exemplo das bordas da fila
    - `sku` vazio → 422; remover/marcar `id` inexistente → 404; reorder inconsistente → 422
    - _Requirements: 13.7, 13.11, 13.15, 13.17_

- [x] 6. Autorização JWT nos endpoints de estoque
  - [x] 6.1 Trocar verify_secret por require_auth no supply mantendo posse e admin
    - Em `routers/supply.py`, trocar `verify_secret` por `require_auth` em `/items`, `/sync`, `/items/{item_id}` e `/admin/verify`, sem recriar os endpoints
    - Mapear `identity.email` como `device_id`/`owner_id` efetivo (`identity.email or data.device_id`); preservar posse (`owner_id`), `forbidden`, 403, 404 e `is_admin` via `x-admin-code`
    - _Requirements: 15.1, 16.7, 16.8, 16.9, 16.10, 16.12, 16.13, 17.2, 17.5, 18.3, 18.4_
  - [ ]* 6.2 Escrever teste de propriedade da autorização por posse no estoque
    - **Feature: web-printer-dashboard, Property 10: Autorização por posse no Supply_Inventory**
    - **Validates: Requirements 16.7, 16.8, 16.9, 16.10, 16.12**
    - `hypothesis`, mínimo 100 iterações; gerar `CloudSupplyItem` (`owner_id` arbitrário/nulo), `acting_device_id` (e-mail) e `admin` booleano; editar/excluir permitido sse admin ou dono; senão `forbidden` no `/sync` e 403 no `/delete`, sem alteração; legado (`owner_id=None`) só admin

- [x] 7. Registro e smoke dos endpoints no backend
  - [x] 7.1 Garantir registro dos novos endpoints em app/main.py
    - Confirmar que listagem, reserva, fila e routers de supply estão incluídos em `app.main:app` (deploy Render usa `uvicorn app.main:app`)
    - _Requirements: 1.1, 11.1, 11.2, 13.1, 13.5, 13.10, 13.13, 13.16_

- [x] 8. Scaffold do frontend React + Vite isolado
  - [x] 8.1 Criar projeto web_dashboard com config isolada e validação de env
    - Criar projeto React + Vite + TS isolado em `web_dashboard/` (`package.json`, `vite.config.ts`, `tsconfig.json`, `index.html`), SPA, sem compartilhar build com Flutter/cloud_api
    - `.env.example` com `VITE_CLOUD_API_URL` e `VITE_FIREBASE_*`; `src/config/env.ts` valida (aborta init se faltar URL ou credenciais Firebase, listando quais faltam); NUNCA define `x-api-key`
    - `src/config/firebase.ts` com `initializeApp` + `getAuth`
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7, 8.8_
  - [ ]* 8.2 Escrever testes de env.ts
    - URL ausente/vazia aborta com erro de URL obrigatória; credenciais Firebase ausentes listam quais faltam
    - _Requirements: 8.3, 8.5_

- [x] 9. apiClient com Bearer, timeout, retry e refresh
  - [x] 9.1 Implementar apiClient (fetch base, Bearer, 401 refresh/logout, Cold_Start)
    - Criar `src/api/client.ts` e `src/api/types.ts`: base URL de `VITE_CLOUD_API_URL`; `AbortController`/timeout; injeção de `Authorization: Bearer` via `getToken()`; `ApiError` tipado (rede/`AbortError`/HTTP)
    - 401: `getToken(true)` e repete uma vez; novo 401 → `logout()`; retry de Cold_Start (3 tentativas, 10s, janela de 60s); NUNCA envia `x-api-key`
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 8.7, 8.8, 12.8, 18.5_
  - [ ]* 9.2 Escrever testes do apiClient
    - `withColdStartRetry` (3 tentativas/10s/60s); refresh de token em 401 e logout ao persistir; sem `x-api-key`
    - _Requirements: 7.2, 7.3, 7.4, 7.5, 18.5_

- [x] 10. Autenticação no frontend
  - [x] 10.1 Implementar AuthContext, ProtectedRoute e LoginPage
    - `src/auth/AuthContext.tsx`: `login` (timeout 10s), `logout` (signOut), `user`, `initializing` (onAuthStateChanged), `getToken(force?)` via `getIdToken`
    - `src/auth/ProtectedRoute.tsx`: sem sessão → redireciona `/login`, nunca renderiza conteúdo protegido
    - `src/pages/LoginPage.tsx`: campos e-mail/senha, validação local (vazios/formato), mensagens de erro, preserva e-mail, trata rejeição e indisponibilidade/timeout
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 2.10_
  - [ ]* 10.2 Escrever teste de propriedade da rota protegida
    - **Feature: web-printer-dashboard, Property 5: Rota protegida nunca expõe conteúdo sem autenticação**
    - **Validates: Requirements 2.1, 2.10**
    - `fast-check`, mínimo 100 iterações; `ProtectedRoute` com `user=null` para qualquer rota protegida nunca renderiza o conteúdo, sempre o redirect
  - [ ]* 10.3 Escrever teste de propriedade da validação local de login
    - **Feature: web-printer-dashboard, Property 6: Validação local bloqueia submissão inválida de login**
    - **Validates: Requirements 2.3**
    - `fast-check`, mínimo 100 iterações; pares (email, senha) inválidos não chamam o Firebase e mostram mensagem; válidos chamam o Firebase (mock)
  - [ ]* 10.4 Escrever testes de exemplo de login/logout/sessão
    - LoginPage rejeição/indisponibilidade/preserva e-mail; logout; restaurar/expirar sessão
    - _Requirements: 2.5, 2.6, 2.7, 2.8, 2.9, 2.10_

- [x] 11. Hook de polling
  - [x] 11.1 Implementar usePolling (10s, 1 simultânea, para ao desmontar)
    - Criar `src/hooks/usePolling.ts`: intervalo 10s, flag `inFlight` suprime novos ticks (máx. 1 simultânea), sucesso substitui `data`, falha/timeout mantém `data` e seta `error`, cleanup faz `clearInterval` + `abort`, `enabled=false` impede ticks
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6_
  - [ ]* 11.2 Escrever teste de propriedade de no máximo 1 polling simultâneo
    - **Feature: web-printer-dashboard, Property 4: No máximo uma requisição de polling simultânea**
    - **Validates: Requirements 5.6**
    - `fast-check`, mínimo 100 iterações; fetcher instrumentado que conta concorrência; sequências de ticks/durações; concorrência nunca excede 1
  - [ ]* 11.3 Escrever testes de exemplo do usePolling com timers falsos
    - Substituição de dados, manutenção em falha, parada ao desmontar/disable
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_

- [x] 12. Lógica pura de disponibilidade e staleness
  - [x] 12.1 Implementar availability.ts (parseUtc, deriveFreshness, deriveAvailability)
    - Criar `src/lib/availability.ts`: `parseUtc` (interpretar `created_at` como UTC), `deriveFreshness` (offline → stale → fresh, limite 60s), `deriveAvailability` (precedência reserved/printing/erro/offline/stale → indisponível; senão fresh + idle/ready → disponível)
    - _Requirements: 4.1, 4.2, 4.3, 4.5, 4.6, 4.7_
  - [ ]* 12.2 Escrever teste de propriedade da derivação de frescor
    - **Feature: web-printer-dashboard, Property 2: Derivação do estado de frescor (staleness/offline)**
    - **Validates: Requirements 4.1, 4.2, 4.3, 4.5**
    - `fast-check`, mínimo 100 iterações; printer (incl. `null`, `state` offline, `created_at` na borda de 60s) e `now`; precedência offline → stale → fresh
  - [ ]* 12.3 Escrever teste de propriedade da derivação de Availability_State com reserva
    - **Feature: web-printer-dashboard, Property 3: Derivação do Availability_State incluindo reserva**
    - **Validates: Requirements 4.6, 4.7**
    - `fast-check`, mínimo 100 iterações; printer (`reserved` bool, states variados, `created_at`) e `now`; `indisponível` sse reserva/printing/erro/offline/stale, senão `disponível`

- [x] 13. Lista de impressoras no frontend
  - [x] 13.1 Implementar printersApi e PrinterListPage/PrinterGrid/PrinterCard/ModelFilter
    - `src/api/printersApi.ts`: `getPrinters`, `getLatestTelemetry`, `getJobHistory` (públicos)
    - `PrinterListPage` com polling da lista, estados de loading/vazio/erro + retry; `PrinterGrid` + `PrinterCard` (campos + `model`/"sem modelo" + indicador de frescor atualizado/desatualizado/offline + verde/vermelho + rótulo "Impressora X — disponível/ocupado")
    - `ModelFilter` (todas / "sem modelo" / por modelo; recalcula modelos no polling e reverte seleção que deixa de existir)
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.10, 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8, 4.9, 10.1, 10.2, 10.3, 10.4, 10.5, 10.6, 10.7, 10.8_
  - [ ]* 13.2 Escrever teste de propriedade de um card por impressora
    - **Feature: web-printer-dashboard, Property 7: Um Printer_Card por impressora com os campos requeridos**
    - **Validates: Requirements 3.2, 3.3, 3.4, 3.5**
    - `fast-check`, mínimo 100 iterações; listas de `Printer`; nº de cards == nº de impressoras; cada card expõe campos requeridos e `model` (ou "sem modelo")
  - [ ]* 13.3 Escrever testes de exemplo de lista/filtro/estados
    - Loading/vazio/erro/retry; opções do Model_Filter e reversão
    - _Requirements: 3.6, 3.7, 3.10, 10.2, 10.3, 10.8_

- [x] 14. Reserva no frontend
  - [x] 14.1 Implementar reservationApi e ReservationControls
    - `src/api/reservationApi.ts`: `reserve`, `release` com `Authorization: Bearer`, `reserved_by` = e-mail, sem `x-api-key`
    - `src/components/ReservationControls.tsx`: ocupar/liberar, exibir `reserved_by`/`reserved_at`; esconder liberar quando ocupado só por telemetria `printing` (sem reserva); erro mantém estado exibido; corrida resolvida no polling
    - _Requirements: 12.1, 12.2, 12.3, 12.4, 12.5, 12.6, 12.7, 12.8, 12.9, 12.10_
  - [ ]* 14.2 Escrever testes de exemplo da reserva no frontend
    - Ocupar/liberar e sucesso refletido; visibilidade do liberar; erro mantém estado
    - _Requirements: 12.1, 12.2, 12.8, 12.10_

- [x] 15. Detalhe da impressora
  - [x] 15.1 Implementar PrinterDetailPage e JobHistoryList
    - `src/pages/PrinterDetailPage.tsx`: status via polling de `/api/telemetry/latest/{printer_id}` + `JobHistoryList` + reserva + `PrintQueuePanel`; parar polling ao sair
    - `src/components/JobHistoryList.tsx`: itens do Job_History com os campos definidos; mensagem de histórico vazio; indicador de carregamento
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 6.8, 6.9_
  - [ ]* 15.2 Escrever testes de exemplo do detalhe
    - Status + Job_History + reserva; histórico vazio; parada do polling ao sair
    - _Requirements: 6.3, 6.4, 6.7, 6.8_

- [x] 16. Fila de impressão no frontend
  - [x] 16.1 Implementar queueApi e PrintQueuePanel
    - `src/api/queueApi.ts`: `getQueue` (público), `addItem`, `remove`, `reorder`, `markPrinted` com `Authorization: Bearer`, `created_by` = e-mail, sem `x-api-key`
    - `src/components/PrintQueuePanel.tsx`: exibir ordenado destacando o próximo; adicionar `sku`/`name` com validação local (sku vazio bloqueia); reordenar; remover; marcar impresso; releitura após operação e a cada Polling_Interval; nota de upload futuro (`.gcode`/`.3mf`/`.stl`) fora de escopo
    - _Requirements: 14.1, 14.2, 14.3, 14.4, 14.5, 14.6, 14.7, 14.8, 14.9, 14.10, 14.11, 14.12, 14.13_
  - [ ]* 16.2 Escrever testes de exemplo da fila no frontend
    - Exibir/destacar próximo; sku vazio bloqueia; reordenar/remover/marcar e releitura
    - _Requirements: 14.2, 14.5, 14.10_

- [x] 17. Estoque no frontend
  - [x] 17.1 Implementar supplyApi, SupplyPage e AdminModeControl
    - `src/api/supplyApi.ts`: `listItems`, `sync`, `deleteItem`, `verifyAdmin` com `Authorization: Bearer` (+ `x-admin-code` opcional), `device_id` = e-mail, sem `x-api-key`
    - `src/pages/SupplyPage.tsx`: listar via polling; CRUD `title`/`description`/`quantity`/`is_bought` (`item_id` gerado); indicadores is_bought; posse por e-mail habilita editar/excluir; tratar `forbidden`/403/404; loading/vazio/erro + retry
    - `src/components/AdminModeControl.tsx`: informar/validar `x-admin-code` via `/admin/verify`, entrar/sair do Admin_Mode, tratar o código como segredo
    - _Requirements: 15.1, 15.2, 15.3, 15.4, 15.5, 15.6, 15.7, 15.8, 15.9, 15.10, 15.11, 16.1, 16.2, 16.3, 16.4, 16.5, 16.6, 16.7, 16.8, 16.9, 16.10, 16.11, 16.12, 16.13, 16.14, 17.1, 17.2, 17.3, 17.4, 17.5, 17.6, 17.7_
  - [ ]* 17.2 Escrever testes de exemplo do estoque no frontend
    - Lista/indicadores is_bought/posse; `forbidden`/403/404; Admin_Mode entrar/sair
    - _Requirements: 15.2, 16.10, 16.12, 16.13, 17.3, 17.5_

- [x] 18. Tema azul/branco (identidade visual)
  - [x] 18.1 Criar theme.css com os design tokens e importar no main.tsx
    - Criar `src/styles/theme.css` com as CSS variables de marca/interação (`--color-primary` #1565C0, `--color-primary-hover` #0D47A1, `--color-primary-subtle` #E3F2FD) e de superfícies/texto/bordas (`--color-surface` #FFFFFF, `--color-background` #F5F8FC, `--color-text` #1A2733, `--color-text-muted` #5B6B7B, `--color-border` #D6E0EA)
    - Incluir os tokens semânticos de STATUS (`--color-available` #2E7D32, `--color-unavailable` #C62828, `--color-warning` #F9A825), preservando verde/vermelho do Availability_State (não substituir por azul)
    - Importar `src/styles/theme.css` uma única vez em `src/main.tsx`; componentes consomem via `var(--color-*)`, sem cores fixas (hard-coded)
    - _Requirements: 4.8 (ver seção "## Identidade Visual (Tema)" do design)_
  - [x] 18.2 Aplicar os tokens de tema nos componentes consumidores
    - `AppLayout`: cabeçalho azul (`--color-primary`) com texto/ícones brancos
    - Botões primários (fundo azul, texto branco, hover `--color-primary-hover`) e secundários (fundo branco, borda e texto azul `--color-primary`)
    - `LoginPage` (superfície branca, botão primário azul, foco/links em azul), `ModelFilter` e `AdminModeControl` (foco/seleção em `--color-primary`/`--color-primary-subtle`)
    - `PrinterCard`s consomem os tokens de superfície/texto, mantendo verde/vermelho (`--color-available`/`--color-unavailable`) para o Availability_State
    - Garantir contraste WCAG AA (texto normal ≥ 4.5:1) e não depender só de cor (rótulo textual "disponível/ocupado" já exigido)
    - _Requirements: 4.8 (ver seção "## Identidade Visual (Tema)" do design)_

- [x] 19. Integração final e fiação do frontend
  - [x] 19.1 Configurar rotas, AppLayout e revisar ausência de x-api-key
    - `src/App.tsx`: rotas client-side `/login`, `/`, `/printers/:id`, `/supply` (SPA, sem recarregar); `src/components/AppLayout.tsx` com navegação (impressoras/estoque) e logout
    - Revisar que nenhuma chamada do frontend usa `x-api-key` (autorização só por `Authorization: Bearer`)
    - _Requirements: 2.7, 2.8, 8.6, 8.7, 8.8_

- [x] 20. Checkpoint final - garantir que todos os testes passam
  - Ensure all tests pass, ask the user if questions arise.

- [x] 21. Script de validação agregada de ponta a ponta (test.js)
  - [x] 21.1 Criar web_dashboard/test.js como smoke de validação executável via node
    - Criar `web_dashboard/test.js` como script Node executável (`node test.js`), sem dependências externas obrigatórias (usar `fetch` nativo do Node 18+)
    - Configurável por variáveis de ambiente, sem hardcode de segredos: `API_BASE_URL` (base da Cloud_API), `TEST_API_KEY`/`TEST_TOKEN` (credenciais de teste); abortar com mensagem clara se a base URL faltar
    - Deixar explícito em comentário que é um smoke/validação agregada que roda ao FINAL, complementando (não substituindo) os testes unitários/PBT (Vitest/pytest + fast-check/hypothesis)
    - _Requirements: 1.1, 11.1, 13.1, 15.1, 16.7, 18.1_
  - [x] 21.2 Implementar as checagens de fluxo integrado no test.js
    - Backend responde: `GET /api/printers` → 200 e array; `GET /api/printers/{id}/queue` → 200 e array
    - Autorização: endpoints protegidos retornam 401 sem auth e autorizam com token/`x-api-key` de teste
    - Reserva: `POST .../reserve` e `POST .../release` funcionam (round-trip de ocupar/liberar)
    - Fila: add/reorder/remove/mark-printed mantendo posições únicas e contíguas
    - Estoque: list/sync/delete respeitando posse (`owner_id`/`device_id` por e-mail)
    - Imprimir resumo PASS/FAIL por checagem e sair com código `!= 0` se qualquer checagem falhar
    - _Requirements: 1.2, 11.9, 13.6, 13.8, 13.22, 15.2, 16.10, 18.4, 18.5_
  - [x] 21.3 Executar node test.js e registrar o resultado agregado
    - Rodar `node web_dashboard/test.js` contra a Cloud_API (local/real) e confirmar que todas as checagens reportam PASS (exit 0)
    - _Requirements: 1.1, 11.1, 13.1, 15.1, 16.7, 18.1_

## Notes

- Tarefas marcadas com `*` são opcionais (testes) e podem ser puladas para um MVP mais rápido; as
  tarefas de implementação principais nunca são opcionais.
- Cada tarefa referencia critérios de aceitação específicos para rastreabilidade.
- As subtarefas de teste por propriedade (P1..P10) usam `hypothesis` (backend) e `fast-check`
  (frontend), com no mínimo 100 iterações, e são anotadas com a tag `Feature: web-printer-dashboard,
  Property N: <nome>`.
- Upload/armazenamento de arquivos da fila (`.gcode`/`.3mf`/`.stl`) é fase futura, fora do escopo.
- O frontend autoriza-se exclusivamente pelo `Firebase_ID_Token`; a `x-api-key` nunca é usada no
  frontend.
- O `web_dashboard/test.js` é um smoke/validação agregada de ponta a ponta que roda ao FINAL
  (`node web_dashboard/test.js`), configurado por variáveis de ambiente (`API_BASE_URL`,
  `TEST_API_KEY`/`TEST_TOKEN`), e complementa — não substitui — os testes unitários/PBT
  (Vitest/pytest + fast-check/hypothesis).

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2", "2.1", "8.1"] },
    { "id": 1, "tasks": ["1.3", "1.4", "2.2", "2.3", "3.1", "5.1", "6.1", "8.2", "9.1", "12.1"] },
    { "id": 2, "tasks": ["3.2", "4.1", "5.2", "6.2", "9.2", "10.1", "11.1", "12.2", "12.3"] },
    { "id": 3, "tasks": ["3.3", "4.2", "5.3", "7.1", "10.2", "10.3", "10.4", "11.2", "11.3", "13.1"] },
    { "id": 4, "tasks": ["4.3", "4.4", "5.4", "13.2", "13.3", "14.1", "16.1", "17.1"] },
    { "id": 5, "tasks": ["5.5", "5.6", "14.2", "15.1", "16.2", "17.2", "18.1"] },
    { "id": 6, "tasks": ["15.2", "18.2", "19.1"] },
    { "id": 7, "tasks": ["21.1"] },
    { "id": 8, "tasks": ["21.2"] },
    { "id": 9, "tasks": ["21.3"] }
  ]
}
```
