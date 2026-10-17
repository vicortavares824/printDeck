rodar no emulador flutter run -d emulator-5554
rodar flutter run -d RX8RC0BK9LT

criar apk : flutter build apk --release

flutter run --debug --flavor production


# Arquitetura do PrintDeck

Este documento descreve a estrutura técnica e a organização arquitetural do **PrintDeck**, um aplicativo Flutter multiplataforma (focado em Android e iOS) para monitoramento e controle de impressoras 3D rodando Klipper/Moonraker.

---

## 1. Visão Geral da Arquitetura

O projeto adota uma arquitetura em camadas orientada a recursos (*Feature-First* e *Layer-First* híbrido), impulsionada por **gerenciamento de estado reativo** com Riverpod, geração de código imutável com Freezed e desacoplamento de lógica de negócio e rede em um pacote compartilhado (`common`).

```
┌────────────────────────────────────────────────────────┐
│                   Apresentação (UI)                   │
│   Screens / Pages ──► Widgets / Components ──► Theme   │
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────┐
│               Estado / Controladores                   │
│   Riverpod Notifiers / StateNotifier / Controllers     │
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────┐
│                  Serviços de Domínio                   │
│  NotificationService, SelectedPrinterService, Spoolman │
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────┐
│        Camada Compartilhada / Dados (`common`)        │
│  Moonraker Client (WebSocket/REST), Repositories,      │
│  Modelos de Dados (Klipper/Moonraker/Freezed)          │
└────────────────────────────────────────────────────────┘
```

---

## 2. Estrutura de Diretórios

O ecossistema é modularizado em duas partes principais: o aplicativo principal (`/lib`) e o submódulo de regras/comunicação compartilhada (`/common`).

### 2.1 Aplicativo Principal (`lib/`)

- **`lib/main.dart`**: Ponto de entrada do aplicativo, inicialização de dependências, configuração do Firebase e injeção do `ProviderScope`.
- **`lib/routing/`**: Gerenciamento de rotas e navegação declarativa usando `go_router`.
- **`lib/service/`**: Serviços transversais e de domínio do app cliente:
  - Gerenciamento da impressora selecionada (`selected_printer_service.dart`).
  - Serviços de notificação push/local.
  - Analytics e compras in-app (RevenueCat).
- **`lib/ui/`**: Camada de apresentação visual:
  - **`screens/`**: Telas funcionais divididas por recurso:
    - `overview/`: Painel inicial compacto com visualização de múltiplas impressoras (cartões, status online/offline, progresso e temperaturas).
    - `dashboard/`: Controle detalhado da impressora conectada (temperaturas, extrusora, ventiladores, macros).
    - `printers/`: Adição, edição e configuração de endpoints Moonraker.
    - `files/`: Gerenciador de arquivos G-Code na impressora.
    - `spoolman/`: Integração com o Spoolman para gerenciamento de filamentos.
    - `setting/`: Configurações globais e preferências do app.
  - **`components/`**: Widgets reaproveitáveis de UI (diálogos, cartões de temperatura, botões de comando).
  - **`theme/`**: Configurações de tema claro/escuro e estilos visuais.
- **`lib/util/`**: Utilitários auxiliares, extensões Dart, analisador de espectro de áudio e validadores de formulário.

### 2.2 Módulo de Dados e Conexão (`common/`)

O módulo `common/` encapsula a lógica que pode ser compartilhada e desacoplada da interface visual:
- **`common/lib/data/`**: Modelos de dados do ecossistema 3D (objetos de status do Klipper, Moonraker, OctoPrint/Spoolman, macros, sensores).
- **`common/lib/network/`**:
  - Comunicação de baixo nível via WebSocket (JSON-RPC) e REST com a API do Moonraker.
  - Sincronização em tempo real de eventos da impressora (*klippy state*, *gcode store*, *print stats*).
- **`common/lib/service/`**: Serviços base de comunicação com a máquina e persistência local (Hive / SharedPreferences).

---

## 3. Padrões de Gerenciamento de Estado e Reatividade

1. **Riverpod (`flutter_riverpod` / `riverpod_annotation`)**:
   - Todo o estado do aplicativo é reativo e desacoplado da árvore de widgets.
   - Provedores auto-gerados (`@riverpod`) controlam o ciclo de vida dos estados de forma granular.
   - Notifiers/AsyncNotifiers cuidam de chamadas assíncronas e tratam estados de `loading`, `error` e `data`.

2. **Modelos Imutáveis (`freezed` + `json_serializable`)**:
   - Objetos de estado e modelos de dados utilizam imutabilidade estrita.
   - Criação segura de clones com método `.copyWith()`.
   - Serialização e desserialização JSON tipadas.

3. **Reatividade em Tempo Real (WebSockets)**:
   - A comunicação com o Moonraker usa conexões WebSocket persistentes.
   - Mudanças nas leituras de termistores e status dos motores são emitidas via streams e refletidas instantaneamente na interface sem necessidade de polling HTTP contínuo.

---

## 4. Tecnologias e Bibliotecas Principais

| Categoria | Tecnologia / Pacote | Papel no Projeto |
| :--- | :--- | :--- |
| **Framework** | Flutter (Dart SDK >= 3.4.0) | Desenvolvimento multiplataforma unificado |
| **Estado** | `flutter_riverpod`, `riverpod_annotation` | Injeção de dependência e gerenciamento de estado reativo |
| **Roteamento** | `go_router` | Roteamento declarativo com suporte a deep linking |
| **Imutabilidade** | `freezed`, `freezed_annotation` | Classes de dados imutáveis com união de tipos |
| **Rede** | `web_socket_channel`, `dio` / `http` | Comunicação WebSocket JSON-RPC e REST com Moonraker |
| **Armazenamento** | `hive`, `shared_preferences` | Armazenamento de cache local e configurações do usuário |
| **Formulários** | `flutter_form_builder` | Validação e criação simplificada de formulários |
| **Internacionalização** | `easy_localization` | Suporte a múltiplos idiomas (ex: pt-BR, en) |

---

## 5. Fluxo de Execução e Desenvolvimento

- **Execução Única**: O processo de build (`assembleDebug` via Gradle) é executado na inicialização para instalar o binário no emulador/aparelho.
- **Desenvolvimento Rápido**: O ciclo diário de codificação apoia-se em **Hot Reload (`r`)** e **Hot Restart (`R`)**, evitando reconstruções completas do APK.
