# PrintDeck Cloud API v2

API REST centralizada da plataforma **PrintDeck**, construida com FastAPI, SQLAlchemy async e Clean Architecture.

## Rodando localmente

```bash
# 1. Instalar dependencias
pip install -r requirements.txt

# 2. Criar .env (copie o exemplo)
cp .env.example .env

# 3. Rodar o servidor
uvicorn src.main:app --reload --port 8000
```

Acesse a documentacao interativa em: http://localhost:8000/docs

## Estrutura de Modulos

| Modulo | Prefixo | Auth Necessaria |
|---|---|---|
| Auth | `/api/auth` | Nao (registro/login) |
| Organizations | `/api/organizations` | Parcial |
| Categories | `/api/categories` | Sim |
| Transactions | `/api/transactions` | Sim |
| Reports | `/api/reports` | Sim |
| **Supply Hub** | **`/api/supply-hub`** | **Somente escrita** |

## Supply Hub - Endpoints Publicos

```
GET /api/supply-hub/items          # Lista todos os insumos
GET /api/supply-hub/items/low-stock # Itens abaixo do minimo
GET /api/supply-hub/items/{id}      # Detalhe de um insumo
```

## Supply (`/api/supply`) - Inventario compartilhado (contrato real do cliente)

> IMPORTANTE: estes endpoints sao servidos pelo pacote `app/` (`app.main:app`), NAO
> pelo `src/` dos endpoints `/api/supply-hub` acima. Veja a nota de deploy no final.

Este e o inventario usado pelo app cliente (Flutter Supply Hub). Trata-se de **um unico
inventario global compartilhado**: todos os dispositivos veem e editam o mesmo conjunto
de itens. O campo `device_id` continua presente no contrato (query e corpo), mas e
**aceito e ignorado para fins de escopo** — ele nao particiona mais os dados.

Autenticacao: header `x-api-key: <API_SECRET_KEY>` em todas as rotas.

```
GET    /api/supply/items?device_id=<qualquer>   # Retorna TODO o inventario compartilhado
POST   /api/supply/sync                          # Upsert por item, nao destrutivo
DELETE /api/supply/items/{item_id}?device_id=<qualquer>  # Remove o item para todos
```

### GET /api/supply/items
Retorna a lista completa do inventario compartilhado, independentemente do valor de
`device_id`. Resposta: lista de itens (`id`, `item_id`, `title`, `description`,
`quantity`, `is_bought`, `updated_at`).

### POST /api/supply/sync
Corpo: `{ "device_id": "<qualquer>", "items": [ { "item_id", "title", "description?",
"quantity?", "is_bought?" } ] }`.

Faz **upsert por item** dentro do escopo compartilhado: para cada item do payload,
atualiza a linha existente (mesmo `item_id`) ou insere uma nova. Itens ausentes do
payload **NUNCA sao apagados** (sincronizacao parcial nao destrutiva). Politica de
conflito: last-write-wins por `updated_at` (aceitavel para v1). Resposta:
`{ "synced": <n> }`.

### DELETE /api/supply/items/{item_id}
Remove o item do inventario compartilhado para todos os dispositivos (o `device_id` da
query e ignorado). Retorna `404` se o `item_id` nao existir; `{ "deleted": true }` em
sucesso.

> Observacao de schema: a coluna `device_id` da tabela `cloud_supply_items` e mantida
> (sem migracao destrutiva — `create_all` nao faz ALTER de tabela existente). Para o
> escopo compartilhado usamos o valor fixo `device_id = "__shared__"`.

## Deploy no Render

1. Conecte seu repositorio ao Render
2. Use o arquivo `render.yaml` (Blueprint) para provisionamento automatico
3. As variaveis de ambiente sao injetadas automaticamente pelo Render
4. O banco PostgreSQL e criado e vinculado via `DATABASE_URL`

**Start command:**
```
uvicorn src.main:app --host 0.0.0.0 --port $PORT
```

### NOTA: mismatch de start command (`app.main:app` vs `src.main:app`)

O servico em producao e executado como **`uvicorn app.main:app`** — e esse app que
serve os endpoints `/api/supply` (inventario compartilhado), `/api/telemetry` e
`/api/jobs` usados pelo cliente. Entretanto, o `startCommand` do `render.yaml` aponta
para **`uvicorn src.main:app`**, que serve o app Clean-Architecture separado
(`/api/supply-hub`, `/api/auth`, etc.) e **NAO** serve `/api/supply`.

Consequencia: qualquer redeploy que use o `startCommand` atual do `render.yaml`
derrubaria o `/api/supply`. Qualquer redeploy deve executar **`app.main:app`** para
manter o contrato do cliente funcionando. (O `render.yaml` nao e alterado aqui; esta
nota documenta o mismatch.)
