# Requirements Document

## Introduction

Esta feature adiciona uma nova parte web ao projeto PrintDeck: um dashboard (site SPA)
construído em React + Vite que consome a Cloud API existente (FastAPI) para **visualizar**
as impressoras 3D e **gerenciar a reserva manual de ocupação** delas. O dashboard não
envia comandos de controle/operação da impressão às impressoras (não inicia nem interrompe
impressões, não altera temperaturas), mas permite que qualquer usuário autenticado marque
uma impressora como ocupada (reservada) ou a libere de volta para disponível. O dashboard
exige autenticação via Firebase Auth (o mesmo provedor usado pelo app Flutter) e atualiza o
status das impressoras automaticamente por polling.

Para as chamadas que exigem autorização (operações de escrita e leituras protegidas), o
Dashboard autentica-se na Cloud_API usando o JWT do Firebase (o `Firebase_ID_Token` do
Authenticated_User), enviando o header `Authorization: Bearer <id_token>`. A chave
`x-api-key` NÃO é conhecida nem enviada pelo frontend: ela permanece exclusivamente no
backend e segue sendo usada pelo app Flutter e por scripts legados. A Cloud_API passa a
validar o `Firebase_ID_Token` com o firebase-admin SDK (Python) e aplica a política de
API_Authorization, na qual um endpoint protegido é autorizado quando a requisição apresenta
um `Firebase_ID_Token` válido OU uma `x-api-key` válida.

A ocupação de uma impressora pode ocorrer de duas formas: por **reserva manual** (marcada
pelo Dashboard ou pelo app Flutter e persistida de forma compartilhada na Cloud API) e por
**impressão real** detectada pela telemetria (quando o `state` indica impressão em
andamento). Ambas as formas fazem a impressora ser tratada como ocupada (indisponível).

Como a Cloud API atual não possui um endpoint que liste todas as impressoras conhecidas
(hoje só existe `GET /api/telemetry/latest/{printer_id}`, que busca uma impressora por ID),
esta feature também adiciona um novo endpoint de listagem na Cloud API que retorna, para
cada `printer_id` distinto, o registro de telemetria mais recente, junto do estado de
reserva manual compartilhado. A Cloud API também passa a expor endpoints de escrita para
ocupar e liberar uma impressora.

O site web é um projeto novo, criado em uma pasta dedicada (`web_dashboard/`) na raiz do
repositório, separado do app Flutter e da `cloud_api/`.

## Glossary

- **Dashboard**: aplicação web SPA (React + Vite) que exibe o estado das impressoras 3D e permite marcar/liberar a reserva manual de ocupação, sem enviar comandos de controle/operação da impressão.
- **Cloud_API**: serviço FastAPI existente em `cloud_api/`, hospedado em produção no Render (`https://printdeck-cloud.onrender.com`).
- **Printer_List_Endpoint**: novo endpoint da Cloud_API que retorna a lista de impressoras conhecidas, cada uma com seu registro de telemetria mais recente e seu Reservation_State.
- **Telemetry_Record**: registro de telemetria de uma impressora, contendo `printer_id`, `state`, `progress`, `current_file`, `nozzle_temp`, `bed_temp`, `filament_info` e `created_at`.
- **Job_History**: lista de trabalhos de impressão concluídos ou cancelados de uma impressora, obtida via `GET /api/jobs/{printer_id}`.
- **Firebase_Auth**: provedor de autenticação Firebase usado para login e logout no Dashboard.
- **Authenticated_User**: usuário que concluiu o login via Firebase_Auth e possui sessão ativa.
- **Firebase_ID_Token**: JWT emitido pelo Firebase_Auth para o Authenticated_User, enviado ao backend no header `Authorization: Bearer <id_token>`. A Cloud_API valida esse token com o firebase-admin SDK e dele deriva a identidade do usuário (claims `email` e `uid`).
- **API_Authorization**: política de autorização do backend segundo a qual uma requisição a um endpoint protegido é autorizada se apresentar um Firebase_ID_Token válido OU uma `x-api-key` válida. A `x-api-key` permanece apenas no backend, no app Flutter e em scripts legados, nunca no Dashboard; o frontend autoriza-se exclusivamente pelo Firebase_ID_Token.
- **Polling_Interval**: intervalo de tempo configurado para o auto-refresh dos dados das impressoras (valor padrão: 10 segundos).
- **Polling_Timeout**: tempo máximo (valor padrão: 8 segundos) que o Dashboard aguarda a resposta de uma solicitação de polling antes de considerá-la falha.
- **Staleness_Threshold**: limite de tempo (valor padrão: 60 segundos) a partir do qual o `created_at` de um Telemetry_Record é considerado desatualizado, indicando impressora offline/desatualizada.
- **Cold_Start**: atraso inicial de resposta da Cloud_API (30 a 60 segundos) causado pela hibernação do serviço no plano gratuito do Render.
- **Printer_Card**: elemento visual do Dashboard que representa uma impressora na lista/grid com seu estado resumido.
- **Printer_Model**: modelo ou tipo da impressora (por exemplo, `K1`, `V3`, `Bambu`), armazenado no campo `model` do Telemetry_Record. O valor pode ser nulo quando o modelo é desconhecido ou não foi informado.
- **Reservation_State**: estado de reserva manual de ocupação de uma impressora, persistido de forma compartilhada na Cloud_API e composto por três campos: `reserved` (booleano indicando se a impressora está reservada manualmente), `reserved_by` (identificador do Authenticated_User que realizou a reserva, por exemplo o e-mail, ou nulo quando não reservada) e `reserved_at` (horário em que a reserva manual foi registrada, ou nulo quando não reservada).
- **Availability_State**: estado derivado de disponibilidade de uma impressora, assumindo um de dois valores: `disponível` ou `indisponível`. Uma impressora é `disponível` quando NÃO está reservada manualmente (`reserved` é falso no Reservation_State) E seu Telemetry_Record mais recente está dentro do Staleness_Threshold (fresh) E seu campo `state` indica impressora ociosa/pronta (por exemplo, `standby`, `idle`, `ready` ou `operational` sem impressão ativa). Uma impressora é `indisponível` quando ocorre qualquer uma das seguintes condições: está reservada manualmente (`reserved` é verdadeiro), está imprimindo, está em erro, está offline, não possui Telemetry_Record associado, ou possui `created_at` igual ou mais antigo que o Staleness_Threshold (stale).
- **Model_Filter**: controle do Dashboard que restringe a lista de impressoras exibidas a um Printer_Model selecionado, com uma opção adicional para exibir todas as impressoras sem filtro.
- **Print_Queue**: fila ordenada e compartilhada de Queue_Items associada a uma impressora (identificada por `printer_id`), persistida de forma durável na Cloud_API de modo que todos os Authenticated_Users leiam e editem a mesma fila da impressora.
- **Queue_Item**: item da Print_Queue, composto por um SKU (texto livre não vazio), um nome (texto) e uma posição/ordem na fila; futuramente poderá ter um arquivo associado (`.gcode` como tipo principal/padrão; `.3mf` e `.stl` como tipos opcionais/alternativos), sendo que o upload e o armazenamento do arquivo em si são uma fase futura, fora do escopo desta entrega.
- **Supply_Item**: item do inventário compartilhado (Supply Hub), composto pelos campos `item_id` (identificador textual do item), `title` (nome do item), `description` (descrição do item), `quantity` (quantidade numérica), `is_bought` (booleano indicando se o item já foi comprado), `owner_id` (identidade de quem criou o item, que no Dashboard corresponde ao e-mail do Authenticated_User, podendo ser nulo em itens legados) e `updated_at` (horário da última modificação).
- **Supply_Inventory**: inventário único e compartilhado de Supply_Items, lido via `GET /api/supply/items` e modificado via `POST /api/supply/sync` (upsert não destrutivo por `item_id`) e `DELETE /api/supply/items/{item_id}`. O Supply_Inventory é único e compartilhado entre todos os usuários; o `device_id`/e-mail enviado nas chamadas serve para posse e autorização, não para separar inventários por usuário.
- **Acting_Identity**: identidade usada nas operações do Supply_Inventory como o `device_id` que age; no Dashboard é o e-mail do Authenticated_User. A Acting_Identity determina o `owner_id` dos Supply_Items criados e a autorização de edição e exclusão dos Supply_Items existentes.
- **Admin_Mode**: modo em que o Authenticated_User apresentou um código de administrador válido (header `x-admin-code`) verificado via `POST /api/supply/admin/verify`, permitindo editar e excluir qualquer Supply_Item independentemente da posse, inclusive Supply_Items legados com `owner_id` nulo. O `x-admin-code` é um segredo à parte, distinto da `x-api-key`; o Dashboard pode enviar o `x-admin-code` junto do header `Authorization: Bearer <Firebase_ID_Token>`, nunca junto de `x-api-key`.

## Requirements

### Requirement 1: Listagem de impressoras na Cloud API

**User Story:** Como desenvolvedor do Dashboard, quero um endpoint que retorne todas as impressoras conhecidas com o último status e o estado de reserva de cada uma, para que o Dashboard possa exibir uma lista completa sem precisar conhecer os IDs antecipadamente.

#### Acceptance Criteria

1. THE Cloud_API SHALL expor um Printer_List_Endpoint acessível por requisição HTTP GET.
2. WHEN o Printer_List_Endpoint recebe uma requisição GET, THE Cloud_API SHALL retornar uma lista contendo um Telemetry_Record por `printer_id` distinto presente na tabela `telemetry_logs`, ordenada de forma decrescente por `created_at`.
3. WHEN existe mais de um registro para um mesmo `printer_id`, THE Cloud_API SHALL selecionar o registro com o maior `created_at`; em caso de empate de `created_at`, SHALL selecionar o de maior identificador de linha.
4. THE Cloud_API SHALL incluir em cada item da lista os campos `printer_id`, `state`, `progress`, `current_file`, `nozzle_temp`, `bed_temp`, `filament_info`, `model` e `created_at`.
5. WHEN um campo de um Telemetry_Record é nulo ou ausente, THE Cloud_API SHALL incluir o campo no item retornado com valor nulo.
6. WHEN o Telemetry_Record selecionado não possui Printer_Model, THE Cloud_API SHALL incluir o campo `model` no item retornado com valor nulo.
7. THE Cloud_API SHALL incluir em cada item da lista os campos de Reservation_State `reserved`, `reserved_by` e `reserved_at`.
8. WHEN uma impressora não possui Reservation_State registrado, THE Cloud_API SHALL retornar `reserved` com valor falso, `reserved_by` com valor nulo e `reserved_at` com valor nulo.
9. WHEN não existe nenhum registro na tabela `telemetry_logs`, THE Cloud_API SHALL retornar uma lista vazia com código de status HTTP 200.
10. THE Cloud_API SHALL permitir acesso ao Printer_List_Endpoint sem o header `x-api-key`.
11. IF a consulta ao banco de dados falha, THEN THE Cloud_API SHALL retornar código de status HTTP 500 com uma mensagem indicando falha na recuperação dos dados, sem alterar dados persistidos.
12. THE Cloud_API SHALL responder ao Printer_List_Endpoint em até 2 segundos sob condições normais de operação.

### Requirement 2: Autenticação de acesso ao Dashboard

**User Story:** Como administrador, quero que apenas usuários autenticados acessem o Dashboard, para que os dados das impressoras não fiquem expostos publicamente.

#### Acceptance Criteria

1. WHEN um usuário não autenticado acessa qualquer rota do Dashboard que não seja a tela de login, THE Dashboard SHALL redirecionar o usuário para a tela de login.
2. THE Dashboard SHALL exibir uma tela de login contendo um campo de e-mail, um campo de senha e um controle de envio que submete as credenciais para autenticação via Firebase_Auth.
3. IF o usuário aciona o controle de envio com o campo de e-mail vazio, o campo de senha vazio, ou um e-mail em formato inválido (ausência de "@" ou de domínio), THEN THE Dashboard SHALL exibir uma mensagem de validação indicando o campo inválido, permanecer na tela de login e não submeter as credenciais ao Firebase_Auth.
4. WHEN um usuário envia credenciais válidas na tela de login, THE Dashboard SHALL estabelecer uma sessão de Authenticated_User e exibir a lista de impressoras em até 5 segundos.
5. IF o usuário envia credenciais rejeitadas pelo Firebase_Auth, THEN THE Dashboard SHALL exibir uma mensagem de erro indicando falha de autenticação, permanecer na tela de login e preservar o valor do campo de e-mail informado.
6. IF o Firebase_Auth está indisponível ou não responde em até 10 segundos durante uma tentativa de login, THEN THE Dashboard SHALL exibir uma mensagem de erro indicando falha de comunicação com o serviço de autenticação e permanecer na tela de login.
7. WHILE existe uma sessão de Authenticated_User ativa, THE Dashboard SHALL exibir um controle de logout.
8. WHEN o Authenticated_User aciona o controle de logout, THE Dashboard SHALL encerrar a sessão via Firebase_Auth e redirecionar o usuário para a tela de login.
9. WHEN o Dashboard é recarregado e existe uma sessão de Firebase_Auth persistida e válida, THE Dashboard SHALL restaurar a sessão de Authenticated_User sem solicitar login novamente.
10. IF o Dashboard é recarregado e a sessão de Firebase_Auth persistida está expirada ou ausente, THEN THE Dashboard SHALL redirecionar o usuário para a tela de login.

### Requirement 3: Visualização da lista de impressoras

**User Story:** Como Authenticated_User, quero ver todas as impressoras em uma lista/grid com seu status resumido, para que eu acompanhe rapidamente o estado da frota.

#### Acceptance Criteria

1. WHEN a lista de impressoras é exibida, THE Dashboard SHALL solicitar os dados ao Printer_List_Endpoint da Cloud_API.
2. THE Dashboard SHALL renderizar um Printer_Card para cada impressora retornada pelo Printer_List_Endpoint.
3. THE Dashboard SHALL exibir em cada Printer_Card os campos `printer_id`, `state`, `progress`, `current_file`, `nozzle_temp`, `bed_temp`, a informação de filamento (tipo de filamento e quantidade restante) e o horário da última atualização (`created_at`).
4. THE Dashboard SHALL exibir em cada Printer_Card o Printer_Model da impressora.
5. WHEN o Printer_Model de uma impressora é nulo, THE Dashboard SHALL exibir no Printer_Card correspondente o rótulo "sem modelo".
6. WHILE os dados da lista de impressoras estão sendo carregados, ainda não há dados em cache e o tempo decorrido desde a solicitação é inferior a 10 segundos, THE Dashboard SHALL exibir um indicador visual de carregamento em progresso.
7. WHEN o Printer_List_Endpoint retorna uma lista vazia, THE Dashboard SHALL exibir uma mensagem informando que nenhuma impressora foi encontrada.
8. THE Dashboard SHALL NÃO expor controles que enviem comandos de controle ou operação da impressão às impressoras (iniciar impressão, interromper impressão, alterar temperatura ou similares).
9. THE Dashboard SHALL permitir o registro do estado de reserva manual (ocupar ou liberar) de uma impressora por meio da Cloud_API, conforme a Requirement 12.
10. IF a solicitação ao Printer_List_Endpoint falha ou não é concluída em até 10 segundos, THEN THE Dashboard SHALL exibir uma mensagem de erro indicando que os dados não puderam ser carregados, oferecer uma ação de nova tentativa e preservar os dados previamente exibidos em cache, caso existam.

### Requirement 4: Indicação de impressora offline, desatualizada ou ocupada

**User Story:** Como Authenticated_User, quero identificar visualmente impressoras offline, com dados antigos ou ocupadas, para que eu saiba quais estão disponíveis e quais não estão reportando status atual.

#### Acceptance Criteria

1. WHEN a diferença entre o horário atual e o `created_at` do Telemetry_Record mais recente de uma impressora é maior ou igual ao Staleness_Threshold de 60 segundos, THE Dashboard SHALL exibir no Printer_Card correspondente um indicador visual persistente de estado "desatualizado", distinguível dos estados "atualizado" e "offline".
2. WHEN a diferença entre o horário atual e o `created_at` do Telemetry_Record mais recente de uma impressora é menor que o Staleness_Threshold de 60 segundos, THE Dashboard SHALL exibir no Printer_Card correspondente um indicador visual persistente de estado "atualizado", distinguível dos estados "desatualizado" e "offline".
3. WHERE o campo `state` do Telemetry_Record mais recente de uma impressora indica que a impressora está offline, THE Dashboard SHALL exibir no Printer_Card correspondente um indicador visual persistente de estado "offline", distinguível dos estados "atualizado" e "desatualizado".
4. WHEN decorre cada Polling_Interval, THE Dashboard SHALL reavaliar a condição de Staleness_Threshold de cada Printer_Card e atualizar o indicador visual sempre que o estado resultante mudar.
5. IF uma impressora não possui nenhum Telemetry_Record associado, THEN THE Dashboard SHALL exibir no Printer_Card correspondente um indicador visual persistente de estado "offline", distinguível dos demais estados.
6. WHEN uma impressora NÃO está reservada manualmente (`reserved` é falso no Reservation_State) E a diferença entre o horário atual e o `created_at` do Telemetry_Record mais recente é menor que o Staleness_Threshold E o campo `state` desse Telemetry_Record indica impressora ociosa ou pronta (`standby`, `idle`, `ready` ou `operational` sem impressão ativa), THE Dashboard SHALL atribuir o Availability_State `disponível` à impressora e exibir no Printer_Card correspondente um indicador visual de cor verde.
7. IF uma impressora está reservada manualmente (`reserved` é verdadeiro no Reservation_State), o campo `state` do Telemetry_Record mais recente indica impressão em andamento ou condição de erro, a impressora é offline, a impressora não possui Telemetry_Record associado, ou a diferença entre o horário atual e o `created_at` do Telemetry_Record mais recente é maior ou igual ao Staleness_Threshold, THEN THE Dashboard SHALL atribuir o Availability_State `indisponível` à impressora e exibir no Printer_Card correspondente um indicador visual de cor vermelha.
8. THE Dashboard SHALL exibir em cada Printer_Card um rótulo textual legível com o `printer_id` e o Availability_State da impressora (por exemplo, "Impressora 178 — disponível" quando o Availability_State é `disponível` e "Impressora 178 — ocupado" quando o Availability_State é `indisponível`).
9. WHEN decorre cada Polling_Interval, THE Dashboard SHALL reavaliar o Availability_State de cada impressora e atualizar o indicador visual e o rótulo textual correspondentes sempre que o Availability_State resultante mudar.

### Requirement 5: Atualização automática por polling

**User Story:** Como Authenticated_User, quero que o status das impressoras atualize sozinho em intervalos regulares, para que eu veja informações recentes sem recarregar a página.

#### Acceptance Criteria

1. WHILE a lista de impressoras está visível, THE Dashboard SHALL solicitar dados atualizados ao Printer_List_Endpoint a cada Polling_Interval de 10 segundos.
2. WHEN novos dados são recebidos de uma solicitação de polling, THE Dashboard SHALL substituir os dados exibidos nos Printer_Cards pelos dados recebidos em até 1 segundo após o recebimento.
3. WHILE uma solicitação de polling está em andamento e já existem dados exibidos, THE Dashboard SHALL manter os dados anteriores visíveis até a chegada dos novos dados.
4. WHEN o Authenticated_User encerra a sessão ou sai da visualização de lista, THE Dashboard SHALL interromper as solicitações de polling dentro de 1 Polling_Interval.
5. IF uma solicitação de polling falha ou não retorna resposta dentro de um Polling_Timeout de 8 segundos, THEN THE Dashboard SHALL manter os últimos dados recebidos visíveis, exibir um indicador de falha de atualização e agendar a próxima solicitação no Polling_Interval seguinte.
6. IF uma solicitação de polling anterior ainda está em andamento quando o Polling_Interval seguinte é atingido, THEN THE Dashboard SHALL suprimir a nova solicitação até a conclusão ou o Polling_Timeout da solicitação em andamento, garantindo no máximo 1 solicitação de polling simultânea.

### Requirement 6: Detalhe de uma impressora com histórico de jobs

**User Story:** Como Authenticated_User, quero abrir o detalhe de uma impressora e ver seu status atual junto com o histórico de impressões e o estado de reserva, para que eu analise o uso daquela máquina e possa ocupá-la ou liberá-la.

#### Acceptance Criteria

1. WHEN o Authenticated_User seleciona uma impressora na lista, THE Dashboard SHALL exibir uma visualização de detalhe com o status atual dessa impressora.
2. WHEN a visualização de detalhe de uma impressora é exibida, THE Dashboard SHALL solicitar o Job_History dessa impressora via `GET /api/jobs/{printer_id}` da Cloud_API.
3. THE Dashboard SHALL exibir, para cada item do Job_History, os campos `filename`, `status`, `print_duration_seconds`, `filament_used_grams`, `filament_material`, `filament_color` e `created_at`.
4. WHEN o Job_History retornado está vazio, THE Dashboard SHALL exibir uma mensagem informando que não há histórico de jobs para essa impressora.
5. WHILE a solicitação do Job_History está em andamento e ainda não há dados de histórico exibidos, THE Dashboard SHALL exibir um indicador de carregamento na visualização de detalhe.
6. WHILE a visualização de detalhe está aberta, THE Dashboard SHALL solicitar o status atual da impressora via `GET /api/telemetry/latest/{printer_id}` da Cloud_API a cada Polling_Interval.
7. WHEN o Authenticated_User fecha a visualização de detalhe ou retorna à lista de impressoras, THE Dashboard SHALL interromper as solicitações de polling do status dessa impressora.
8. WHEN a impressora exibida no detalhe está reservada manualmente (`reserved` é verdadeiro no Reservation_State), THE Dashboard SHALL exibir na visualização de detalhe o identificador do Authenticated_User que a ocupou (`reserved_by`) e o horário da ocupação (`reserved_at`).
9. THE Dashboard SHALL oferecer na visualização de detalhe o controle de ocupar ou liberar a impressora conforme a Requirement 12.

### Requirement 7: Tratamento de carregamento, erro e cold start

**User Story:** Como Authenticated_User, quero que o Dashboard trate falhas e a demora inicial da Cloud_API de forma clara, para que eu entenda o que está acontecendo quando os dados não aparecem imediatamente.

#### Acceptance Criteria

1. IF uma requisição à Cloud_API retorna um código de status de erro, THEN THE Dashboard SHALL exibir uma mensagem de erro indicando que o carregamento dos dados falhou, preservar os dados previamente exibidos e manter visível a opção de nova tentativa.
2. IF uma requisição à Cloud_API não recebe resposta dentro de 60 segundos, THEN THE Dashboard SHALL exibir uma mensagem indicando que o serviço pode estar inicializando e continuar aguardando a resposta.
3. WHEN uma requisição à Cloud_API falha durante o Cold_Start, THE Dashboard SHALL repetir a requisição automaticamente a cada 10 segundos até receber resposta ou atingir o máximo de 3 tentativas.
4. IF as 3 tentativas automáticas durante o Cold_Start são esgotadas sem resposta, THEN THE Dashboard SHALL exibir uma mensagem de erro indicando que o serviço não respondeu e manter visível a opção de nova tentativa.
5. WHEN o Authenticated_User aciona a opção de nova tentativa após um erro, THE Dashboard SHALL repetir a requisição que falhou.
6. WHILE uma requisição à Cloud_API está pendente de resposta, THE Dashboard SHALL exibir um indicador de carregamento.

### Requirement 8: Estrutura e configuração do projeto web

**User Story:** Como desenvolvedor, quero que o Dashboard seja um projeto React + Vite isolado na raiz do repositório, para que ele seja desenvolvido e implantado independentemente do app Flutter e da Cloud_API.

#### Acceptance Criteria

1. THE Dashboard SHALL ser criado como um projeto React + Vite em uma pasta dedicada (`web_dashboard/`) na raiz do repositório, sem compartilhar dependências, artefatos de build ou configuração de build com o app Flutter ou com a Cloud_API.
2. THE Dashboard SHALL obter a URL base da Cloud_API a partir de uma variável de configuração de ambiente, usando o valor de produção `https://printdeck-cloud.onrender.com` quando a variável estiver definida.
3. IF a variável de ambiente com a URL base da Cloud_API não estiver definida ou contiver valor vazio no momento da inicialização, THEN THE Dashboard SHALL interromper a inicialização e exibir uma mensagem de erro indicando que a URL base da Cloud_API é obrigatória.
4. THE Dashboard SHALL obter as credenciais de configuração do Firebase_Auth a partir de variáveis de configuração de ambiente.
5. IF uma ou mais variáveis de ambiente de configuração do Firebase_Auth não estiverem definidas ou contiverem valor vazio no momento da inicialização, THEN THE Dashboard SHALL interromper a inicialização e exibir uma mensagem de erro indicando quais credenciais do Firebase_Auth estão ausentes.
6. THE Dashboard SHALL ser uma aplicação single-page (SPA) servida a partir de um único documento HTML, realizando a navegação entre telas no lado do cliente sem recarregar o documento.
7. THE Dashboard SHALL limitar suas variáveis de configuração de ambiente à URL base da Cloud_API e às credenciais de configuração do Firebase_Auth, sem definir nenhuma variável de ambiente que contenha a `x-api-key` da Cloud_API.
8. THE Dashboard SHALL NÃO armazenar a `x-api-key` da Cloud_API em variável de ambiente, em código do frontend ou em armazenamento local, autorizando-se à Cloud_API exclusivamente pelo Firebase_ID_Token enviado em `Authorization: Bearer <id_token>`.

### Requirement 9: Campo de modelo da impressora na Cloud API

**User Story:** Como desenvolvedor do Dashboard, quero que a Cloud_API armazene e exponha o modelo/tipo de cada impressora, para que o Dashboard possa exibir e filtrar impressoras por modelo.

#### Acceptance Criteria

1. THE Cloud_API SHALL definir no modelo PrinterTelemetry uma coluna `model` do tipo texto que aceita valor nulo na tabela `telemetry_logs`.
2. WHEN a Cloud_API inicia, THE Cloud_API SHALL executar uma auto-migração idempotente que adiciona a coluna `model` à tabela `telemetry_logs` caso a coluna ainda não exista, para bancos SQLite e PostgreSQL.
3. WHEN a auto-migração verifica que a coluna `model` já existe na tabela `telemetry_logs`, THE Cloud_API SHALL concluir a inicialização sem alterar o esquema da tabela.
4. THE Cloud_API SHALL aceitar no corpo da requisição `POST /api/telemetry` um campo opcional `model` do tipo texto no schema TelemetryIn.
5. WHEN uma requisição `POST /api/telemetry` inclui um valor para o campo `model`, THE Cloud_API SHALL persistir esse valor na coluna `model` do Telemetry_Record criado.
6. WHEN uma requisição `POST /api/telemetry` omite o campo `model`, THE Cloud_API SHALL persistir o valor nulo na coluna `model` do Telemetry_Record criado.
7. THE Cloud_API SHALL incluir o campo `model` no schema TelemetryOut retornado pelo Printer_List_Endpoint e pelo endpoint `GET /api/telemetry/latest/{printer_id}`.
8. WHEN o Telemetry_Record retornado possui valor nulo na coluna `model`, THE Cloud_API SHALL retornar o campo `model` com valor nulo.
9. WHEN um Telemetry_Record foi criado antes da existência da coluna `model`, THE Cloud_API SHALL tratar o campo `model` desse registro como nulo e retornar os demais campos sem erro.
10. THE Cloud_API SHALL incluir os campos de Reservation_State `reserved`, `reserved_by` e `reserved_at` no retorno do endpoint `GET /api/telemetry/latest/{printer_id}`, aplicando os mesmos padrões de valor nulo definidos na Requirement 1 quando não houver reserva registrada.
11. IF a auto-migração da coluna `model` falha, THEN THE Cloud_API SHALL registrar a falha e prosseguir com a inicialização sem interromper o serviço.

### Requirement 10: Filtro de impressoras por modelo no Dashboard

**User Story:** Como Authenticated_User, quero filtrar a lista de impressoras por modelo, para que eu visualize apenas as impressoras de um tipo específico da frota.

#### Acceptance Criteria

1. THE Dashboard SHALL exibir um Model_Filter com a lista de Printer_Models disponíveis derivada dos valores distintos de `model` presentes nos dados retornados pelo Printer_List_Endpoint.
2. THE Dashboard SHALL incluir no Model_Filter uma opção para exibir todas as impressoras sem aplicar filtro de modelo.
3. WHEN existe pelo menos uma impressora com `model` nulo nos dados retornados, THE Dashboard SHALL incluir no Model_Filter uma opção "sem modelo" que agrupa as impressoras com Printer_Model nulo.
4. WHEN o Authenticated_User seleciona um Printer_Model no Model_Filter, THE Dashboard SHALL exibir somente os Printer_Cards das impressoras cujo `model` é igual ao Printer_Model selecionado.
5. WHEN o Authenticated_User seleciona a opção "sem modelo" no Model_Filter, THE Dashboard SHALL exibir somente os Printer_Cards das impressoras cujo `model` é nulo.
6. WHEN o Authenticated_User seleciona a opção de exibir todas as impressoras no Model_Filter, THE Dashboard SHALL exibir os Printer_Cards de todas as impressoras retornadas pelo Printer_List_Endpoint.
7. WHEN uma solicitação de polling atualiza os dados das impressoras, THE Dashboard SHALL recalcular a lista de Printer_Models disponíveis no Model_Filter e manter o Printer_Model atualmente selecionado aplicado à lista exibida.
8. IF o Printer_Model atualmente selecionado no Model_Filter deixa de existir nos dados retornados após uma atualização, THEN THE Dashboard SHALL reverter o Model_Filter para a opção de exibir todas as impressoras.

### Requirement 11: Reserva manual de ocupação na Cloud API

**User Story:** Como desenvolvedor do Dashboard e do app Flutter, quero que a Cloud_API exponha e persista o estado de reserva manual de cada impressora, para que o site e o app compartilhem a mesma informação de quem ocupou cada impressora e desde quando.

#### Acceptance Criteria

1. THE Cloud_API SHALL expor um endpoint de escrita para marcar uma impressora como ocupada (reservada), identificando a impressora por `printer_id`.
2. THE Cloud_API SHALL expor um endpoint de escrita para liberar uma impressora reservada, identificando a impressora por `printer_id`.
3. WHEN o endpoint de ocupar recebe uma requisição válida para um `printer_id`, THE Cloud_API SHALL persistir o Reservation_State dessa impressora com `reserved` igual a verdadeiro, `reserved_by` igual ao identificador do usuário (o `reserved_by` recebido no corpo da requisição ou, quando a requisição está autenticada por Firebase_ID_Token, o `email` derivado das claims do token) e `reserved_at` igual ao horário em que a ocupação é registrada.
4. WHEN o endpoint de liberar recebe uma requisição válida para um `printer_id`, THE Cloud_API SHALL persistir o Reservation_State dessa impressora com `reserved` igual a falso, `reserved_by` igual a nulo e `reserved_at` igual a nulo.
5. THE Cloud_API SHALL persistir o Reservation_State de forma durável, por meio de uma nova tabela criada via `create_all` ou de novas colunas adicionadas a uma tabela existente, de modo que o Dashboard e o app Flutter leiam o mesmo estado compartilhado.
6. WHERE o Reservation_State é persistido como novas colunas em uma tabela existente, THE Cloud_API SHALL executar na inicialização uma auto-migração idempotente, no padrão `_ensure_supply_schema`, que adiciona as colunas de reserva caso ainda não existam, para bancos SQLite e PostgreSQL.
7. THE Cloud_API SHALL exigir API_Authorization (um Firebase_ID_Token válido OU uma `x-api-key` válida) nas requisições aos endpoints de ocupar e liberar, de forma coerente com os endpoints `POST /api/telemetry` e `POST /api/supply/sync`.
8. THE Cloud_API SHALL aceitar no corpo da requisição do endpoint de ocupar o campo `reserved_by` com o identificador do usuário que está reservando, mantido para compatibilidade, e SHALL usar o `email` derivado das claims do Firebase_ID_Token como `reserved_by` quando a requisição está autenticada por token e esse `email` está disponível.
9. IF uma requisição ao endpoint de ocupar ou de liberar é recebida sem um Firebase_ID_Token válido e sem uma `x-api-key` válida, THEN THE Cloud_API SHALL rejeitar a requisição com código de status HTTP 401 e não alterar o Reservation_State persistido.
10. IF uma requisição ao endpoint de ocupar omite o campo `reserved_by`, o fornece vazio e não apresenta um Firebase_ID_Token válido do qual derivar o `email`, THEN THE Cloud_API SHALL rejeitar a requisição com código de status HTTP 422 e não alterar o Reservation_State persistido.
11. WHEN o endpoint de ocupar recebe uma requisição para uma impressora que já está reservada, THE Cloud_API SHALL substituir o Reservation_State existente pelos valores da nova requisição (`reserved_by` e `reserved_at` atualizados) e responder com código de status HTTP 200.
12. WHEN o endpoint de liberar recebe uma requisição para uma impressora que não está reservada, THE Cloud_API SHALL manter o Reservation_State como não reservado e responder com código de status HTTP 200.
13. IF uma requisição ao endpoint de ocupar ou de liberar informa um `printer_id` inexistente na tabela `telemetry_logs`, THEN THE Cloud_API SHALL responder com código de status HTTP 404 e não criar Reservation_State para esse `printer_id`.
14. THE Cloud_API SHALL permitir a leitura do Reservation_State sem autenticação (sem Firebase_ID_Token e sem `x-api-key`), retornando-o junto dos dados da impressora conforme a Requirement 1.

### Requirement 12: Marcar impressora como ocupada ou disponível pelo Dashboard

**User Story:** Como Authenticated_User, quero marcar uma impressora como ocupada (reservar) e liberá-la pelo Dashboard, para que eu e minha equipe saibamos quem está usando cada impressora e desde quando.

#### Acceptance Criteria

1. WHERE uma impressora está disponível (Availability_State `disponível`), THE Dashboard SHALL exibir no Printer_Card correspondente um controle para ocupar (reservar) a impressora.
2. WHERE uma impressora está ocupada por reserva manual (`reserved` é verdadeiro no Reservation_State), THE Dashboard SHALL exibir no Printer_Card correspondente um controle para liberar a impressora.
3. WHEN o Authenticated_User aciona o controle de ocupar de uma impressora, THE Dashboard SHALL chamar o endpoint de ocupar da Cloud_API enviando o header `Authorization: Bearer <Firebase_ID_Token>`, sem enviar `x-api-key`, e enviando `reserved_by` igual ao e-mail do Authenticated_User (que o backend pode também derivar do token).
4. WHEN a chamada de ocupar retorna sucesso, THE Dashboard SHALL refletir o estado ocupado (indisponível) da impressora no Printer_Card correspondente.
5. WHEN o Authenticated_User aciona o controle de liberar de uma impressora, THE Dashboard SHALL chamar o endpoint de liberar da Cloud_API para essa impressora enviando o header `Authorization: Bearer <Firebase_ID_Token>`, sem enviar `x-api-key`.
6. WHEN a chamada de liberar retorna sucesso, THE Dashboard SHALL refletir o estado disponível da impressora no Printer_Card correspondente, desde que as demais condições de disponibilidade sejam satisfeitas.
7. WHERE uma impressora está ocupada por reserva manual, THE Dashboard SHALL exibir no Printer_Card correspondente o identificador do usuário que a ocupou (`reserved_by`) e o horário da ocupação (`reserved_at`).
8. IF a chamada de ocupar ou de liberar falha, THEN THE Dashboard SHALL exibir uma mensagem de erro e manter o estado de reserva anteriormente exibido para a impressora.
9. WHEN uma solicitação de polling posterior retorna um Reservation_State diferente do exibido para uma impressora, THE Dashboard SHALL atualizar o Printer_Card correspondente com o Reservation_State recebido.
10. WHERE uma impressora é exibida como ocupada apenas porque o Telemetry_Record indica impressão em andamento e seu Reservation_State tem `reserved` igual a falso, THE Dashboard SHALL NÃO exibir o controle de liberar reserva manual para essa impressora.

### Requirement 13: Fila de impressão por impressora na Cloud API

**User Story:** Como desenvolvedor do Dashboard, quero que a Cloud_API exponha e persista uma fila de impressão ordenada e compartilhada por impressora, para que todos os Authenticated_Users vejam e editem a mesma Print_Queue de cada impressora.

#### Acceptance Criteria

1. THE Cloud_API SHALL expor um endpoint de leitura acessível por requisição HTTP GET que retorna a Print_Queue de uma impressora identificada por `printer_id`, com os Queue_Items ordenados por `position` de forma ascendente.
2. THE Cloud_API SHALL incluir em cada Queue_Item retornado os campos `id`, `printer_id`, `sku`, `name`, `position`, `created_at` e `created_by`.
3. WHEN o endpoint de leitura da Print_Queue recebe uma requisição para um `printer_id` sem Queue_Items, THE Cloud_API SHALL retornar uma lista vazia com código de status HTTP 200.
4. THE Cloud_API SHALL permitir acesso ao endpoint de leitura da Print_Queue sem o header `x-api-key`.
5. THE Cloud_API SHALL expor um endpoint de escrita para adicionar um Queue_Item ao fim da Print_Queue de uma impressora identificada por `printer_id`, aceitando no corpo da requisição os campos `sku`, `name` e `created_by`, e SHALL usar o `email` derivado das claims do Firebase_ID_Token como `created_by` quando a requisição está autenticada por token e esse `email` está disponível.
6. WHEN o endpoint de adicionar recebe uma requisição válida, THE Cloud_API SHALL persistir um novo Queue_Item com `position` igual à maior `position` existente na Print_Queue dessa impressora mais um, ou com a primeira posição quando a Print_Queue está vazia.
7. IF uma requisição ao endpoint de adicionar informa um `sku` vazio, THEN THE Cloud_API SHALL rejeitar a requisição com código de status HTTP 422 e não persistir o Queue_Item.
8. IF uma requisição a qualquer endpoint de escrita da Print_Queue é recebida sem um Firebase_ID_Token válido e sem uma `x-api-key` válida, THEN THE Cloud_API SHALL rejeitar a requisição com código de status HTTP 401 e não alterar os Queue_Items persistidos.
9. THE Cloud_API SHALL exigir API_Authorization (um Firebase_ID_Token válido OU uma `x-api-key` válida) nas requisições aos endpoints de escrita da Print_Queue, de forma coerente com os endpoints `POST /api/telemetry`, `POST /api/supply/sync` e os endpoints de reserva da Requirement 11.
10. THE Cloud_API SHALL expor um endpoint de escrita para remover um Queue_Item identificado por `id` da Print_Queue de uma impressora.
11. IF uma requisição ao endpoint de remover informa um `id` de Queue_Item inexistente, THEN THE Cloud_API SHALL responder com código de status HTTP 404 e não alterar os Queue_Items persistidos.
12. WHEN o endpoint de remover remove um Queue_Item, THE Cloud_API SHALL reindexar as posições dos Queue_Items restantes da mesma Print_Queue de modo que permaneçam únicas, contíguas e preservem a ordem relativa anterior.
13. THE Cloud_API SHALL expor um endpoint de escrita para reordenar a Print_Queue de uma impressora, recebendo no corpo da requisição a lista ordenada de `id` dos Queue_Items que define a nova ordem.
14. WHEN o endpoint de reordenar recebe uma lista ordenada de `id` consistente com os Queue_Items atuais da Print_Queue, THE Cloud_API SHALL atribuir a cada Queue_Item a `position` correspondente à sua ordem na lista recebida.
15. IF uma requisição ao endpoint de reordenar informa um `id` desconhecido ou uma lista inconsistente com os Queue_Items atuais da Print_Queue, THEN THE Cloud_API SHALL rejeitar a requisição com código de status HTTP 422 e não alterar as posições persistidas.
16. THE Cloud_API SHALL expor um endpoint de escrita para marcar um Queue_Item identificado por `id` como impresso, removendo-o da Print_Queue ativa.
17. IF uma requisição ao endpoint de marcar como impresso informa um `id` de Queue_Item inexistente, THEN THE Cloud_API SHALL responder com código de status HTTP 404 e não alterar os Queue_Items persistidos.
18. WHEN o endpoint de marcar como impresso remove um Queue_Item da Print_Queue ativa, THE Cloud_API SHALL reindexar as posições dos Queue_Items restantes da mesma Print_Queue de modo que permaneçam únicas, contíguas e preservem a ordem relativa anterior.
19. THE Cloud_API SHALL persistir os Queue_Items de forma durável em uma nova tabela `print_queue_items`, criada via `create_all`, contendo as colunas `printer_id`, `sku`, `name`, `position`, `created_at` e `created_by`, compartilhada de modo que todos os Authenticated_Users leiam a mesma Print_Queue por `printer_id`.
20. WHERE a persistência da Print_Queue exigir colunas novas em uma tabela existente, THE Cloud_API SHALL executar na inicialização uma auto-migração idempotente, no padrão `_ensure_supply_schema`, que adiciona as colunas caso ainda não existam, para bancos SQLite e PostgreSQL.
21. WHEN um endpoint da Print_Queue recebe um `printer_id` inexistente na tabela `telemetry_logs`, THE Cloud_API SHALL operar a Print_Queue desse `printer_id` normalmente, tratando a impressora como existente de forma lógica pelo `printer_id` textual.
22. THE Cloud_API SHALL manter a `position` dos Queue_Items de uma mesma Print_Queue única dentro da fila, definindo que o Queue_Item de menor `position` é o próximo item a ser impresso.

### Requirement 14: Gerenciamento da fila de impressão no Dashboard

**User Story:** Como Authenticated_User, quero visualizar e gerenciar a fila de impressão de cada impressora pelo Dashboard, para que eu e minha equipe saibamos qual é o próximo item a imprimir e possamos organizar a Print_Queue compartilhada.

#### Acceptance Criteria

1. WHEN a visualização de detalhe de uma impressora (Requirement 6) ou o Printer_Card correspondente é exibido, THE Dashboard SHALL solicitar a Print_Queue dessa impressora ao endpoint de leitura da Print_Queue da Cloud_API e exibir os Queue_Items na ordem definida por `position` ascendente.
2. THE Dashboard SHALL destacar visualmente o Queue_Item de menor `position` como o próximo item a ser impresso.
3. THE Dashboard SHALL exibir para cada Queue_Item o `sku` e o `name`.
4. THE Dashboard SHALL oferecer um controle para adicionar um Queue_Item informando o `sku` (texto livre) e o `name`.
5. IF o Authenticated_User aciona o controle de adicionar com o campo `sku` vazio, THEN THE Dashboard SHALL exibir uma mensagem de validação local e não enviar a requisição à Cloud_API.
6. WHEN o Authenticated_User confirma a adição de um Queue_Item com `sku` não vazio, THE Dashboard SHALL chamar o endpoint de adicionar da Cloud_API com o header `Authorization: Bearer <Firebase_ID_Token>`, sem enviar `x-api-key`, e enviar `created_by` igual ao e-mail do Authenticated_User.
7. THE Dashboard SHALL oferecer um controle para reordenar os Queue_Items da Print_Queue e, ao reordenar, SHALL chamar o endpoint de reordenar da Cloud_API com o header `Authorization: Bearer <Firebase_ID_Token>`, sem enviar `x-api-key`, enviando a nova ordem de `id`.
8. THE Dashboard SHALL oferecer um controle para remover um Queue_Item e, ao removê-lo, SHALL chamar o endpoint de remover da Cloud_API com o header `Authorization: Bearer <Firebase_ID_Token>`, sem enviar `x-api-key`.
9. THE Dashboard SHALL oferecer um controle para marcar um Queue_Item como impresso e, ao acioná-lo, SHALL chamar o endpoint de marcar como impresso da Cloud_API com o header `Authorization: Bearer <Firebase_ID_Token>`, sem enviar `x-api-key`, removendo o Queue_Item da Print_Queue ativa exibida.
10. WHEN uma operação de escrita na Print_Queue retorna sucesso, THE Dashboard SHALL reler a Print_Queue da impressora para refletir a ordem e os Queue_Items atualizados.
11. WHILE a visualização que exibe a Print_Queue está aberta, THE Dashboard SHALL reler a Print_Queue da impressora a cada Polling_Interval para refletir mudanças feitas por outros Authenticated_Users na fila compartilhada.
12. IF uma operação de escrita na Print_Queue falha, THEN THE Dashboard SHALL exibir uma mensagem de erro, manter o estado coerente da Print_Queue exibida e resolver eventual divergência na releitura do Polling_Interval seguinte.
13. THE Dashboard SHALL gerenciar nesta entrega apenas os metadados do Queue_Item (`sku`, `name` e ordem), tratando o anexo e o upload de arquivo (`.gcode` como tipo principal; `.3mf` e `.stl` como tipos opcionais) como funcionalidade futura fora do escopo desta entrega.

### Requirement 15: Visualização do estoque no Dashboard

**User Story:** Como Authenticated_User, quero ver o inventário compartilhado de itens de estoque no Dashboard, para que eu acompanhe o que existe no Supply_Inventory e o que ainda precisa ser comprado.

#### Acceptance Criteria

1. THE Dashboard SHALL exibir uma área de estoque que lista os Supply_Items do Supply_Inventory solicitando os dados ao endpoint `GET /api/supply/items` da Cloud_API com o header `Authorization: Bearer <Firebase_ID_Token>`, sem enviar `x-api-key`, e com `device_id` igual ao e-mail do Authenticated_User.
2. THE Dashboard SHALL exibir, para cada Supply_Item listado, os campos `title`, `description`, `quantity`, o estado de `is_bought` e o `owner_id` do item.
3. WHERE um Supply_Item possui `is_bought` igual a falso, THE Dashboard SHALL exibir um indicador visual persistente de item a comprar, distinguível do indicador de item já comprado.
4. WHERE um Supply_Item possui `is_bought` igual a verdadeiro, THE Dashboard SHALL exibir um indicador visual persistente de item já comprado, distinguível do indicador de item a comprar.
5. WHILE os dados do Supply_Inventory estão sendo carregados e ainda não há dados de estoque exibidos, THE Dashboard SHALL exibir um indicador visual de carregamento em progresso.
6. WHEN o endpoint `GET /api/supply/items` retorna uma lista vazia, THE Dashboard SHALL exibir uma mensagem informando que o Supply_Inventory não possui itens.
7. IF a solicitação ao endpoint `GET /api/supply/items` falha ou não é concluída dentro do Polling_Timeout de 8 segundos, THEN THE Dashboard SHALL exibir uma mensagem de erro indicando que o estoque não pôde ser carregado, oferecer uma ação de nova tentativa e preservar os dados de estoque previamente exibidos, caso existam.
8. WHEN o Authenticated_User aciona a ação de nova tentativa após um erro de carregamento do estoque, THE Dashboard SHALL repetir a solicitação ao endpoint `GET /api/supply/items`.
9. WHILE a área de estoque está visível, THE Dashboard SHALL solicitar dados atualizados do Supply_Inventory ao endpoint `GET /api/supply/items` a cada Polling_Interval de 10 segundos.
10. WHEN o Authenticated_User reabre a área de estoque, THE Dashboard SHALL solicitar dados atualizados do Supply_Inventory ao endpoint `GET /api/supply/items`.
11. WHEN uma solicitação ao endpoint `GET /api/supply/items` retorna Supply_Items alterados por outros usuários, THE Dashboard SHALL atualizar a lista exibida com os Supply_Items recebidos do inventário compartilhado.

### Requirement 16: Gerenciamento do estoque pelo Dashboard

**User Story:** Como Authenticated_User, quero adicionar, editar, marcar como comprado e excluir itens do estoque pelo Dashboard, para que eu mantenha o Supply_Inventory compartilhado atualizado respeitando a posse de cada item.

#### Acceptance Criteria

1. THE Dashboard SHALL oferecer um controle para adicionar um Supply_Item informando `title`, `description` (opcional), `quantity` (valor padrão 1.0) e `is_bought` (valor padrão falso).
2. IF o Authenticated_User aciona o controle de adicionar com o campo `title` vazio, THEN THE Dashboard SHALL exibir uma mensagem de validação local e não enviar a requisição à Cloud_API.
3. WHEN o Authenticated_User confirma a adição de um Supply_Item com `title` não vazio, THE Dashboard SHALL chamar o endpoint `POST /api/supply/sync` com o header `Authorization: Bearer <Firebase_ID_Token>`, sem enviar `x-api-key`, com `device_id` igual ao e-mail do Authenticated_User e um item com `item_id` gerado para o novo Supply_Item.
4. WHEN o Authenticated_User confirma a edição de um Supply_Item, THE Dashboard SHALL chamar o endpoint `POST /api/supply/sync` com o header `Authorization: Bearer <Firebase_ID_Token>`, sem enviar `x-api-key`, com `device_id` igual ao e-mail do Authenticated_User e o mesmo `item_id` do Supply_Item com os novos valores.
5. WHEN o Authenticated_User alterna o estado de comprado de um Supply_Item, THE Dashboard SHALL chamar o endpoint `POST /api/supply/sync` com o header `Authorization: Bearer <Firebase_ID_Token>`, sem enviar `x-api-key`, com `device_id` igual ao e-mail do Authenticated_User e o Supply_Item com o novo valor de `is_bought`.
6. WHEN o Authenticated_User confirma a exclusão de um Supply_Item, THE Dashboard SHALL chamar o endpoint `DELETE /api/supply/items/{item_id}` com o header `Authorization: Bearer <Firebase_ID_Token>`, sem enviar `x-api-key`, e `device_id` igual ao e-mail do Authenticated_User.
7. WHERE um Supply_Item possui `owner_id` igual ao e-mail do Authenticated_User, THE Dashboard SHALL exibir os controles de editar e excluir desse Supply_Item habilitados.
8. WHERE um Supply_Item possui `owner_id` diferente do e-mail do Authenticated_User E o Dashboard não está em Admin_Mode, THE Dashboard SHALL exibir o Supply_Item como somente leitura, mantendo os controles de editar e excluir desse item desabilitados ou ocultos.
9. WHERE o Dashboard está em Admin_Mode, THE Dashboard SHALL exibir os controles de editar e excluir habilitados para qualquer Supply_Item, inclusive Supply_Items com `owner_id` nulo.
10. WHEN uma resposta do endpoint `POST /api/supply/sync` inclui o `item_id` de um Supply_Item no campo `forbidden`, THE Dashboard SHALL exibir uma mensagem informando que a alteração não foi permitida por o item pertencer a outro dono e não refletir a alteração desse Supply_Item na lista exibida.
11. WHEN uma resposta do endpoint `POST /api/supply/sync` confirma o Supply_Item no campo `synced` sem incluí-lo em `forbidden`, THE Dashboard SHALL refletir a alteração do Supply_Item na lista exibida.
12. IF uma chamada ao endpoint `DELETE /api/supply/items/{item_id}` retorna código de status HTTP 403, THEN THE Dashboard SHALL exibir uma mensagem informando que apenas o criador ou um administrador pode excluir o Supply_Item e manter o item na lista exibida.
13. IF uma chamada ao endpoint `DELETE /api/supply/items/{item_id}` retorna código de status HTTP 404, THEN THE Dashboard SHALL remover o Supply_Item da lista exibida por já não existir no Supply_Inventory.
14. IF uma operação de escrita no Supply_Inventory falha por erro de rede ou ausência de resposta, THEN THE Dashboard SHALL exibir uma mensagem de erro, manter o estado coerente do estoque exibido e resolver eventual divergência na releitura do Polling_Interval seguinte.

### Requirement 17: Modo administrador do estoque no Dashboard

**User Story:** Como Authenticated_User, quero informar um código de administrador e, após validá-lo, agir como administrador do estoque, para que eu possa editar e excluir qualquer Supply_Item independentemente da posse.

#### Acceptance Criteria

1. THE Dashboard SHALL oferecer um controle para o Authenticated_User informar um código de administrador do estoque.
2. WHEN o Authenticated_User submete um código de administrador, THE Dashboard SHALL chamar o endpoint `POST /api/supply/admin/verify` com os headers `Authorization: Bearer <Firebase_ID_Token>` e `x-admin-code`, sem enviar `x-api-key`.
3. WHEN o endpoint `POST /api/supply/admin/verify` retorna código de status HTTP 200 com `admin` igual a verdadeiro, THE Dashboard SHALL entrar em Admin_Mode e enviar o header `x-admin-code` junto do header `Authorization: Bearer <Firebase_ID_Token>` nas operações subsequentes do Supply_Inventory, sem enviar `x-api-key`.
4. WHILE o Dashboard está em Admin_Mode, THE Dashboard SHALL habilitar a edição e a exclusão de qualquer Supply_Item, inclusive Supply_Items com `owner_id` nulo.
5. IF o endpoint `POST /api/supply/admin/verify` retorna código de status HTTP 403, THEN THE Dashboard SHALL exibir uma mensagem indicando que o código de administrador é inválido, permanecer fora do Admin_Mode e não armazenar o código informado.
6. THE Dashboard SHALL oferecer um controle para sair do Admin_Mode que descarta o código de administrador armazenado e retorna o Dashboard ao comportamento baseado na posse por `owner_id`.
7. THE Dashboard SHALL tratar o código de administrador como segredo, não o exibindo em texto nem o registrando em logs ou mensagens.

### Requirement 18: Autenticação e autorização da Cloud API por JWT do Firebase

**User Story:** Como responsável pela segurança do sistema, quero que a Cloud_API valide o JWT do Firebase e aceite também a `x-api-key` para compatibilidade, para que o Dashboard autorize suas chamadas sem conhecer a `x-api-key` e o app Flutter e scripts legados continuem funcionando.

#### Acceptance Criteria

1. THE Cloud_API SHALL validar o Firebase_ID_Token apresentado no header `Authorization: Bearer` usando o firebase-admin SDK.
2. WHEN uma requisição a um endpoint protegido apresenta um Firebase_ID_Token válido, THE Cloud_API SHALL autorizar a requisição e derivar a identidade do usuário (`email` e `uid`) a partir das claims do token.
3. WHEN uma requisição a um endpoint protegido apresenta uma `x-api-key` válida sem Firebase_ID_Token, THE Cloud_API SHALL autorizar a requisição, mantendo a compatibilidade com o app Flutter e scripts legados.
4. IF uma requisição a um endpoint protegido não apresenta um Firebase_ID_Token válido nem uma `x-api-key` válida, THEN THE Cloud_API SHALL responder com código de status HTTP 401 e não alterar dados persistidos.
5. IF uma requisição a um endpoint protegido apresenta um Firebase_ID_Token expirado, malformado ou com assinatura inválida e não apresenta uma `x-api-key` válida, THEN THE Cloud_API SHALL responder com código de status HTTP 401 e não alterar dados persistidos.
6. THE Cloud_API SHALL manter a `x-api-key` apenas no backend e na configuração de servidor, sem expô-la ao frontend.
7. THE Cloud_API SHALL configurar o firebase-admin com credenciais de conta de serviço (service account) fornecidas por variável de ambiente, de forma coerente com o deploy no Render.
8. WHERE as credenciais do firebase-admin não estão configuradas, THE Cloud_API SHALL tratar toda validação de Firebase_ID_Token como falha, autorizar os endpoints protegidos apenas mediante `x-api-key` válida e registrar a condição de credenciais ausentes.

### Observações de consistência do escopo de estoque

As requirements 15, 16 e 17 operam sobre um Supply_Inventory único e compartilhado entre todos os
Authenticated_Users: o `device_id`/e-mail enviado nas chamadas serve exclusivamente para posse e
autorização (determinando o `owner_id` dos Supply_Items criados e quem pode editar ou excluir cada item),
e nunca para separar inventários por usuário. Diferentemente do Printer_List_Endpoint (que é público e
não exige autenticação), todos os endpoints do Supply_Inventory (`GET /api/supply/items`,
`POST /api/supply/sync`, `DELETE /api/supply/items/{item_id}` e `POST /api/supply/admin/verify`) exigem
API_Authorization, ou seja, um Firebase_ID_Token válido OU uma `x-api-key` válida. A partir do Dashboard,
o apiClient autoriza essas chamadas enviando o header `Authorization: Bearer <Firebase_ID_Token>`, sem
nunca enviar `x-api-key` (que permanece apenas no backend, no app Flutter e em scripts legados) e,
quando em Admin_Mode, também o header `x-admin-code`, que é um segredo à parte distinto da `x-api-key`.
