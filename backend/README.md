# PrintDeck Backend API

Backend em **Python / FastAPI** com **SQLite assíncrono (SQLAlchemy)** para integrar e gerenciar dados do **Klipper/Moonraker** e do **Spoolman**.

---

## 🚀 Como Executar

### 1. Criar ambiente virtual e instalar dependências

Abra um terminal na pasta `backend/`:

```bash
cd backend
python -m venv .venv

# No Windows (PowerShell):
.venv\Scripts\Activate.ps1

# Instalar dependências:
pip install -r requirements.txt
```

### 2. Configurar o `.env`

Edite o arquivo `.env` para colocar os IPs corretos da sua impressora e do Spoolman:

```env
MOONRAKER_URL=http://<IP_DA_IMPRESSORA>:7125
SPOOLMAN_URL=http://<IP_DO_SPOOLMAN>:7912
DATABASE_URL=sqlite+aiosqlite:///./database.db
HOST=0.0.0.0
PORT=8000
```

### 3. Iniciar a API

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Abra no navegador a documentação interativa com Swagger:
👉 **`http://localhost:8000/docs`**

---

## 📡 Endpoints Disponíveis

- **`GET /api/status`**: Busca telemetria em tempo real no Moonraker (temperaturas de bico e mesa, status de impressão, progresso e arquivo atual).
- **`GET /api/files`**: Lista todos os arquivos `.gcode` salvos na impressora com tamanho e tempo estimado.
- **`GET /api/spools`**: Lista todos os carretéis e filamentos cadastrados no Spoolman (peso restante, material, cor e fabricante).
- **`POST /api/jobs`**: Cria um registro de impressão no SQLite local associando o arquivo ao carretel usado.
- **`GET /api/jobs`**: Consulta o histórico de trabalhos de impressão salvos no banco.
- **`POST /api/sync/spools`**: Puxa os dados do Spoolman e sincroniza uma cópia no banco SQLite local.
