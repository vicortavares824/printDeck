# SupplyHub — Verificação de Persistência e Sincronização

## Resumo (resposta direta)

**Não. O SupplyHub NÃO salva tudo localmente e NÃO sincroniza tudo.**

Dois problemas graves, independentes:

1. **NÃO existe persistência local dos itens.** O `InventoryNotifier` guarda a lista de itens **apenas em memória** (`StateNotifier<List<SupplyItem>>`). Não há nenhuma box Hive (nem SharedPreferences, nem arquivo) onde os `SupplyItem` sejam gravados. Ao fechar o app, **toda a lista local é perdida**. A afirmação no comentário do código de que "o dado fica salvo localmente" (`inventory_notifier.dart:124`) é **falsa** — não há gravação local alguma.

2. **A sincronização é "last-write-wins" destrutiva e de mão única para a leitura.** O `pushItems` substitui os itens remotos deste dispositivo pela lista local; o `pullFromCloud` substitui a lista local pela remota. Como não há persistência local, o fluxo real é: ao abrir a página, o `initState` dispara `_syncFromCloud()` → `pullFromCloud()` sobrescreve a lista em memória com o que estiver na nuvem. Se a nuvem estiver vazia ou offline, o usuário vê a lista vazia; qualquer dado que existisse só sobrevive se o push anterior tiver chegado ao servidor.

Consequência combinada: o único lugar onde os dados persistem entre reinicializações é **o backend remoto**. Se o push falhar (rede, cold start, device_id), o dado some ao reiniciar o app, porque não há cópia local. A "fonte da verdade" local prometida pela arquitetura não existe.

O backend é real (`https://printdeck-cloud.onrender.com`), não é placeholder. O `device_id` é persistido corretamente na `settingsbox` (que é aberta no startup). Esses dois pontos funcionam.

---

## Evidências

### 1. Persistência local — AUSENTE

**O notifier só tem estado em memória.**
- `inventory_notifier.dart:7-11` — `class InventoryNotifier extends StateNotifier<List<SupplyItem>>`, construtor inicializa com `initialItems ?? const <SupplyItem>[]`. Não recebe nem abre nenhuma box.
- `addItem` (`inventory_notifier.dart:25-71`), `incrementQuantity` (`:74`), `decrementQuantity` (`:87`), `toggleBoughtStatus` (`:101`), `removeItem` (`:113`) — todos apenas reatribuem `state = ...` e chamam `_pushToCloud()`. **Nenhum deles grava em armazenamento local.**
- O provider `inventoryNotifierProvider` (`inventory_notifier.dart:157-161`) cria `InventoryNotifier(null, apiService)` — ou seja, **sempre inicia com lista vazia**, sem carregar nada de disco.

**Nenhuma box Hive para itens de suprimento existe no projeto.**
- Busca por `openBox`/`registerAdapter` em `lib/app_setup.dart:198-207` (`openBoxes()`): as boxes abertas são `printers`, `uuidbox`, `settingsbox`, `notifications`, `dashboard_layouts`. **Não há nenhuma box para supply/almoxarifado.**
- Nenhum `HiveType`/adapter para `SupplyItem`: o gerado `supply_item.g.dart` contém **apenas** `JsonSerializableGenerator` (`_$$SupplyItemImplFromJson` / `...ToJson`). Não há `SupplyItemAdapter`. O modelo (`supply_item.dart:6-7`) declara só `part 'supply_item.freezed.dart'` e `part 'supply_item.g.dart'`, com anotação `@freezed` — sem `@HiveType`/`@HiveField`.

**Comentário enganoso.**
- `inventory_notifier.dart:122-125` — no catch de `_pushToCloud`: "Falha silenciosa: a nuvem pode estar fora do ar; o dado fica salvo localmente." Isso é incorreto: não existe gravação local, então em falha de push o dado **não** está salvo em lugar nenhum persistente.

**O projeto TEM um padrão correto de persistência local que o SupplyHub não seguiu.**
- `lib/service/local_filament_stock_service.dart:76-78` grava em Hive: `final box = await Hive.openBox<String>(boxName); await box.put(spool.id, spool.toJson());` e recarrega no construtor via `_loadFromHive()` (`:63-73`). Esse é exatamente o tipo de persistência que falta no SupplyHub.

**No restart não há recarga do local** — porque não há local. O notifier sempre começa vazio (ver provider acima). A única recarga é a remota, disparada por `supply_hub_page.dart:48-54` (`initState` → `addPostFrameCallback` → `_syncFromCloud`).

### 2. Sincronização remota

**Backend real, configurado.**
- `supply_api_service.dart:13-14` — `_baseUrl = 'https://printdeck-cloud.onrender.com'`, `_apiKey = 'printdeck-V2Niche'`. Não é TODO/mock. (Observação de segurança: a API key está hardcoded no app cliente.)
- Dio configurado com timeouts de 60s e header `x-api-key` (`supply_api_service.dart:43-58`).

**device_id persistido corretamente.**
- `supply_api_service.dart:27-41` — lê/gera `device_id` da `Hive.box('settingsbox')` sob a chave `supply_hub_device_id`, com cache em memória. A `settingsbox` **é aberta no startup** (`app_setup.dart:202`), então `Hive.box('settingsbox')` não falha. Esse mecanismo está correto.

**Push (envio).**
- `pushItems` (`supply_api_service.dart:74-91`) monta payload `{device_id, items:[{item_id, title, description, quantity(double), is_bought}]}` e faz `POST /api/supply/sync`. O comentário em `:73` confirma a semântica destrutiva: "substitui os itens remotos deste dispositivo". Trata status != 200/201 lançando exceção — mas essa exceção é engolida (ver item 4).

**Pull (recebimento).**
- `pullItems` (`supply_api_service.dart:94-106`) faz `GET /api/supply/items?device_id=...`, mapeia a resposta via `_fromJson`. `pullFromCloud` (`inventory_notifier.dart:135-140`) faz `state = cloudItems` — **substitui** a lista local inteira, sem merge/reconciliação. Não há resolução de conflito: o que a nuvem devolver vira a verdade, descartando qualquer item local ainda não enviado.

**Delete.**
- `deleteItem` (`supply_api_service.dart:119-129`) faz `DELETE /api/supply/items/{itemId}?device_id=...`. Chamado por `removeItemWithCloud` (`inventory_notifier.dart:143-153`), usado pelo card de UI (`supply_item_card.dart:73-76`). Já o `removeItem` (`inventory_notifier.dart:113-117`) remove local e chama `_pushToCloud()` (re-sync completo), não `deleteItem`.

### 3. Completude — o que é/não é sincronizado

- **Campos:** os cinco campos de `SupplyItem` (id, title, description, quantity, isBought) são enviados no push (`supply_api_service.dart:78-83`) e lidos no pull (`_fromJson`, `:107-115`). Então, por item, "todos os campos" vão. Observe que `quantity` é enviado como `double` (`quantity.toDouble()`) e relido com `(json['quantity'] ?? 1).toInt()` — ida e volta por double pode perder precisão em teoria, mas para inteiros pequenos é ok.
- **Itens:** o push envia a lista local inteira (`items` = `state`). Mas como não há persistência local, "todos os itens" significa só os que estão em memória na sessão atual.
- **Nenhum TODO/FIXME/UnimplementedError** encontrado nos arquivos do SupplyHub. O código não é um stub — ele realmente faz chamadas HTTP. O problema não é código não-implementado; é **ausência de camada de persistência local** e **catch vazio**.
- **Catches vazios que engolem erros:** `inventory_notifier.dart:122-125` (`_pushToCloud`) e `:148-151` (`removeItemWithCloud`) — ambos capturam e descartam a exceção silenciosamente.

### 4. Modos de falha

- **Falha de rede no push:** `_pushToCloud` captura qualquer exceção e não faz nada (`inventory_notifier.dart:120-126`). O usuário **não é avisado** de que a gravação na nuvem falhou. Como não há cópia local persistente, ao reiniciar o app o item some silenciosamente.
- **Falha de rede no pull:** `pullFromCloud` **não** tem try/catch (`inventory_notifier.dart:135-140`); a exceção sobe. Ela é capturada na UI em `_syncFromCloud` (`supply_hub_page.dart:31-40`), que mostra um SnackBar vermelho "Erro ao sincronizar com a nuvem". Esse é o único caminho onde o erro é surfaced ao usuário.
- **device_id ausente:** não ocorre — se não existir, é gerado e persistido na hora (`supply_api_service.dart:32-37`). Risco real é oposto: se a `settingsbox` for limpa/reinstalada, gera-se novo `device_id` e a nuvem passa a tratar como outro dispositivo (itens "somem" do ponto de vista do usuário).
- **Cold start do Render:** tratado com `_withRetry` (uma segunda tentativa) e timeouts de 60s (`supply_api_service.dart:62-72`). Razoável, mas uma única retry pode não bastar em cold start lento.

### 5. Flag `_isSyncing`

A flag **não é só UI** — ela realmente dispara trabalho. `supply_hub_page.dart:22-45` (`_syncFromCloud`): seta `_isSyncing = true`, chama de fato `ref.read(inventoryNotifierProvider.notifier).pullFromCloud()` (`:25`), mostra SnackBar de sucesso/erro e no `finally` volta `_isSyncing = false`. O botão (`:70-77`) fica desabilitado e vira spinner enquanto sincroniza. Porém, atenção: o botão só faz **pull** (download). Não existe botão/ação explícita de "push agora"; o push só acontece como efeito colateral das mutações.

### Analisador

`flutter analyze lib/features/supply_hub` (Flutter 3.22.3) → **"No issues found!"** para os arquivos do SupplyHub. Houve um erro do servidor de análise ao carregar o plugin `custom_lint`/`riverpod_lint` (dependências do plugin não resolvidas), mas isso é global do projeto e não aponta nenhum problema nos arquivos do SupplyHub.

---

## Conclusão (veredito)

O SupplyHub **sincroniza** com um backend real, mas **não persiste nada localmente** e **não reconcilia** dados — portanto não cumpre "salva e sincroniza tudo". O modelo efetivo é "backend é a única fonte da verdade; memória é cache volátil". Qualquer item criado offline, ou quando o push falha, é **perdido no próximo restart**, silenciosamente.

### Problemas por severidade

1. **CRÍTICO — Sem persistência local.** Não há box Hive para `SupplyItem`; o notifier é só memória (`inventory_notifier.dart:7-11`, provider `:157-161`; nenhuma box em `app_setup.dart:198-207`; `.g.dart` sem adapter Hive). Dados somem no restart se o push remoto não tiver tido sucesso. Contradiz a arquitetura (armazenamento local com Hive) e o próprio comentário do código (`inventory_notifier.dart:124`).

2. **ALTO — Falha de push silenciosa.** `_pushToCloud` engole exceções (`inventory_notifier.dart:120-126`); o usuário acredita que salvou. Combinado com (1), é perda de dados sem aviso.

3. **ALTO — Pull destrutivo sem merge, disparado automaticamente ao abrir a tela.** `pullFromCloud` faz `state = cloudItems` (`inventory_notifier.dart:135-140`) e roda no `initState` (`supply_hub_page.dart:48-54`); substitui o estado local sem reconciliar, podendo descartar itens locais ainda não enviados.

4. **MÉDIO — `device_id` volátil.** Preso à `settingsbox`; limpeza de dados/reinstalação gera novo id e "perde" o inventário na nuvem (`supply_api_service.dart:27-41`).

5. **BAIXO — API key hardcoded no cliente** (`supply_api_service.dart:14`).

6. **BAIXO — `quantity` trafega como double** no push e volta via `toInt()` (`supply_api_service.dart:81`, `:113`); sem impacto prático para inteiros pequenos, mas inconsistente com o modelo `int`.

### Recomendações (não implementadas)

- Adicionar persistência local real seguindo o padrão já existente em `lib/service/local_filament_stock_service.dart`: abrir uma box (ex.: `supply_hub_items`) no `openBoxes()` de `app_setup.dart`, carregar no construtor do notifier e gravar em cada mutação (addItem/increment/decrement/toggle/remove). Essa box deve ser a fonte da verdade; a nuvem vira sincronização por cima.
- Transformar o push em operação confiável: fila/flag de "pendente de sincronização" por item, retry e feedback de falha ao usuário; não engolir a exceção em `_pushToCloud`.
- Trocar o pull "replace-all" por um merge/reconciliação (por `item_id` + carimbo de atualização) para não descartar itens locais não enviados.
- Corrigir o comentário enganoso em `inventory_notifier.dart:124` após (ou como parte de) introduzir persistência local.
- Considerar id de dispositivo/conta mais estável (ou login) para não perder o vínculo com os dados na nuvem em reinstalações.

> Observação: trechos de comentários do código foram parafrasados/resumidos neste relatório.
