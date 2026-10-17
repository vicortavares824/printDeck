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

## Deploy no Render

1. Conecte seu repositorio ao Render
2. Use o arquivo `render.yaml` (Blueprint) para provisionamento automatico
3. As variaveis de ambiente sao injetadas automaticamente pelo Render
4. O banco PostgreSQL e criado e vinculado via `DATABASE_URL`

**Start command:**
```
uvicorn src.main:app --host 0.0.0.0 --port $PORT
```
