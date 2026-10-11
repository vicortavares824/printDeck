# PrintDeck Cloud API (Pronto para o Render)

Esta API foi preparada especificamente para você subir no **[Render.com](https://render.com)** como um **Web Service** gratuito (ou pago).

---

## 🛠️ Como fazer o Deploy no Render em 3 minutos:

1. **Suba este diretório para o seu GitHub** (pode ser dentro do seu repo ou em um repositório dedicado).
2. Acesse seu painel no **Render** ([dashboard.render.com](https://dashboard.render.com)).
3. Clique em **New +** e escolha **Web Service**.
4. Conecte o repositório do GitHub.
5. Preencha as configurações do Render:
   - **Name**: `printdeck-cloud` (ou o nome que preferir)
   - **Root Directory**: `cloud_api` (se estiver dentro do projeto printDeck)
   - **Environment**: `Python 3`
   - **Build Command**: `pip install -r requirements.txt`
   - **Start Command**: `uvicorn app.main:app --host 0.0.0.0 --port $PORT`
6. *(Opcional)* Em **Environment Variables**:
   - `API_SECRET_KEY`: crie uma chave ou senha secreta (ex: `minha-chave-secreta-123`).
   - `DATABASE_URL`: Se você criar um banco PostgreSQL gratuito no Render, basta colar o `Internal Database URL` aqui. Se não colocar nada, ela usará SQLite automaticamente!

---

## 🛰️ Como enviar dados do seu backend local para esta API na Nuvem

Seu backend local (ou um script em Python) só precisa fazer uma requisição POST:

### Endpoint: `POST https://seu-app.onrender.com/api/telemetry`
**Headers:**
- `x-api-key`: `minha-chave-secreta-123`
- `Content-Type`: `application/json`

**Body:**
```json
{
  "printer_id": "ender3_v3",
  "state": "printing",
  "progress": 42.5,
  "current_file": "vaso_decorativo.gcode",
  "nozzle_temp": 205.0,
  "bed_temp": 60.0,
  "filament": {
    "spool_id": 4,
    "material": "PLA",
    "color": "#00FF00",
    "vendor": "Voolt3D",
    "remaining_weight_grams": 720.0
  }
}
```

---

## 📱 Consultar dados online em qualquer lugar

- Último estado: `GET https://seu-app.onrender.com/api/telemetry/latest/ender3_v3`
- Histórico de impressões: `GET https://seu-app.onrender.com/api/jobs/ender3_v3`
- Documentação interativa: `https://seu-app.onrender.com/docs`
