# PrintDeck — MVP pessoal (nome provisório)

Protótipo para uso **pessoal e não comercial**, derivado da versão pública Mobileraker `ios2.6.20`. A licença e os avisos de autoria do projeto original foram preservados.

## O que foi personalizado

- Início mais simples, com cartões compactos para acompanhar várias impressoras Klipper/Moonraker.
- Indicador online/offline e estado atual da impressão.
- Nome do arquivo, progresso e temperaturas de bico/mesa.
- Acesso direto aos controles de cada impressora.
- Atalho contextual para pausar ou retomar uma impressão, além de reconectar quando offline.
- Atualização por gesto, estado vazio com ação para cadastrar impressora e tentativa de recuperação quando a lista falha.
- Nome de exibição provisório `PrintDeck` no app, Android e iOS.

A tela fica em `lib/ui/screens/overview/overview_page.dart`; a tradução do painel foi adicionada a `assets/translations/pt-BR.json` e `assets/translations/en.json`.

## Abrir o projeto

O ZIP contém dois diretórios irmãos: `PrintDeck/` e `mobileraker_pro_compatible/`. A dependência local Pro precisa continuar como irmã do app.

1. Instale Flutter **3.22.3** e configure o Android SDK (ou Xcode/macOS para iOS).
2. Entre em `PrintDeck/` e execute:

   ```bash
   flutter pub get
   flutter devices
   flutter run -d <id-do-dispositivo>
   ```

3. Para validar os testes do app:

   ```bash
   flutter test
   ```

## Antes de instalar junto com o app original ou distribuir

Este ainda é um protótipo, não um pacote pronto para publicação:

- Os IDs Android/iOS ainda são os do upstream (`com.mobileraker.android` e `com.mobileraker.ios`). Escolha IDs únicos antes de instalar lado a lado ou distribuir.
- O ícone de lançamento ainda é o do Mobileraker; substitua-o pela identidade visual final.
- O código aponta `DefaultFirebaseOptions.currentPlatform` para opções herdadas do pacote Pro. O projeto não inclui `google-services.json` nem `GoogleService-Info.plist`. Crie um projeto Firebase seu, gere/configure as opções da sua aplicação e não publique usando as credenciais/opções do upstream.
- Mantenha a licença, os avisos de copyright e o uso não comercial. A licença do Mobileraker exige autorização expressa escrita para uso comercial.

## Origem e licença

- App Mobileraker: [repositório original](https://github.com/Clon1998/mobileraker) — base usada: [tag `ios2.6.20`](https://github.com/Clon1998/mobileraker/tree/ios2.6.20).
- Extensão pública compatível: [mobileraker_pro_pub](https://github.com/Clon1998/mobileraker_pro_pub), versão pública antiga `2.6.7`.
- Consulte `LICENSE` em cada diretório do bundle e preserve os avisos de autoria.

## Validação neste ambiente

- `flutter test`: **23 testes do app aprovados** (22 unitários e 1 widget smoke test do estado vazio).
- `flutter analyze lib/ui/screens/overview/overview_page.dart test/widget_test.dart`: sem problemas.
- A suíte do pacote `common` da base antiga ainda possui 3 falhas em testes legados (287 passaram, 4 foram ignorados; uma falha identificada é `MissingStubError` de `clientType`).
- O sandbox não tem Android SDK, `adb` ou emulador, então o app não foi iniciado num dispositivo nem foi gerado APK. Também não é um host macOS para build iOS.
