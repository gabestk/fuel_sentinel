# Fuel Sentinel (Aplicativo OBD)

<p align="center">
  <img src="assets/icon/fuel_sentinel_icon.png" width="180">
</p>

Um aplicativo mobile em Flutter para diagnóstico veicular e coleta de dados de sensores.

O Fuel Sentinel se conecta a adaptadores OBD-II via Bluetooth, registra o status do veículo e dados de GPS, armazena registros locais utilizando Hive e integra com o Firebase Cloud Firestore para sincronização com o backend.

## Índice

- [O que o projeto faz](#o-que-o-projeto-faz)
- [Por que este projeto é útil](#por-que-este-projeto-é-útil)
- [Principais funcionalidades](#principais-funcionalidades)
- [Primeiros passos](#primeiros-passos)
  - [Pré-requisitos](#pré-requisitos)
  - [Clonar e instalar](#clonar-e-instalar)
  - [Configurar o Firebase](#configurar-o-firebase)
  - [Executar o aplicativo](#executar-o-aplicativo)
  - [Tarefas de desenvolvimento](#tarefas-de-desenvolvimento)
- [Estrutura do projeto](#estrutura-do-projeto)
- [Suporte](#suporte)
- [Contribuição](#contribuição)
- [Observações](#observações)

---

## O que o projeto faz

O Fuel Sentinel é uma aplicação Flutter desenvolvida para coletar e visualizar dados telemáticos de veículos utilizando informações OBD-II e sensores do dispositivo. Ele gerencia conexões Bluetooth com dispositivos OBD, obtém respostas de PIDs, registra dados de GPS e acelerômetro, e pode sincronizar os dados coletados com o Firebase.

---

## Por que este projeto é útil

Este aplicativo é útil para desenvolvedores, pesquisadores e engenheiros que desejam uma base funcional para soluções de diagnóstico veicular e monitoramento de frotas. O projeto demonstra:

- conectividade Bluetooth OBD-II em tempo real
- persistência local de dados utilizando Hive
- inicialização do Firebase e integração com Cloud Firestore
- gerenciamento de permissões Android para Bluetooth, localização e armazenamento
- execução de tarefas em segundo plano com Workmanager
- descoberta dinâmica de PIDs e monitoramento OBD configurável

---

## Principais funcionalidades

- Descoberta e conexão com adaptadores Bluetooth OBD-II
- Gerenciamento de PIDs OBD, incluindo consultas de nível de combustível e VIN
- Armazenamento local de dados utilizando Hive
- Suporte a backend Firebase via `firebase_core` e `cloud_firestore`
- Os dados são salvos só no celular (o envio para a AWS está desativado no código)
- Sensoriamento de GPS e movimento utilizando `geolocator` e `sensors_plus`
- Execução de tarefas em segundo plano via `workmanager`
- Sistema modular de rotas com `auto_route`
- Suporte para dados OBD simulados e intervalos de amostragem configuráveis

---

## Scanner de PIDs (coleta em CSV)

A aba **Scanner** funciona como o aplicativo do OBDLink:

1. **Conectar**: escolha o adaptador entre os dispositivos pareados. O app inicializa o ELM327
   (`ATZ`, `ATE0`, `ATL0`, `ATS0`, `ATH0`, `ATAT1`, `ATSP0`) e mostra a versão e o protocolo.
2. **Buscar PIDs**: consulta `0100`, `0120`, `0140`... e lista todos os PIDs do modo 01 que o
   veículo informa como suportados. PIDs sem fórmula conhecida são gravados em hexadecimal.
3. **Selecionar** os PIDs e os **calculados** (consumo instantâneo, Fuel Rate, CO2, distância e
   combustível da viagem, potência, torque, aceleração...). A seleção fica salva.
4. **Iniciar coleta**: o app lê os PIDs o mais rápido possível e grava uma linha por segundo
   (ou 2, 5 ou 10 por segundo, no botão de ajustes), sempre com o último valor de cada PID,
   como o OBDLink. PIDs lentos (temperaturas, nível, contadores) são lidos com menos frequência,
   para os rápidos (rotação, velocidade, MAF) atualizarem mais.
5. **Parar coleta**: fecha o arquivo e mostra onde ele foi salvo.

### Formato do CSV

Igual ao do OBDLink, para os mesmos scripts lerem os dois:

- arquivo `CSVLog_AAAAMMDD_hhmmss.csv` em `Android/data/com.example.obdapp/files/coletas_obd/`
  (acessível pelo cabo USB no computador)
- BOM UTF-8, cabeçalho separado por `, `, linhas por `,`, ponto decimal
- 1ª coluna `Time` no formato `09/30/2026 01:36:32.3944 PM`
- colunas dos PIDs com os nomes e unidades do OBDLink (`Engine RPM (RPM)`,
  `Intake manifold absolute pressure (bar)`, `Fuel/Air commanded equivalence ratio`...)
- colunas dos calculados (`Fuel Rate (l/hr)`, `Instant Fuel Economy (l/100 km)`, `Trip Distance (km)`...)
- GPS do celular: `Latitude (deg)`, `Longitude (deg)`, `Altitude (m)`, `GPS Speed (km/h)`, `GPS Accuracy (m)`
- sensores do celular: `Accel X/Y/Z (m/s²)`, `Accel (Grav) X/Y/Z (m/s²)`, `Rotation Rate X/Y/Z (deg/s)`
- `PID refresh rate (Hz)` (leituras de PID por segundo) e `Elapsed time (sec)`

Diferenças em relação ao OBDLink: um PID que ainda não respondeu fica **vazio** (o OBDLink grava 0),
o MAF calculado se chama `Mass air flow rate (calculated) (g/s)` (no OBDLink a coluna tem o mesmo
nome do MAF medido) e os acumulados da viagem começam no início de cada coleta.

### PIDs calculados

As fórmulas foram ajustadas a um CSV real do OBDLink e reproduzem os valores dele
(diferença relativa abaixo de 0,002 %):

| Coluna | Fórmula |
|---|---|
| Fuel Rate (l/hr) | MAF × 3600 / (AFR × densidade) = MAF × 0,33279 (AFR 14,7, 0,7359 kg/L) |
| CO2 flow (g/s) | Fuel Rate × 2347,7 g/L / 3600 |
| Instant Fuel Economy (l/100 km) | Fuel Rate / velocidade × 100 |
| Engine Power (PS) | MAF × 1,188916 |
| Engine Torque (N•m) | Engine Power × 7219,6 / rpm |
| Mass air flow rate (calculated) | rpm/120 × MAP × cilindrada × eficiência volumétrica × M_ar / (R × T) |
| Trip Distance, Trip Fuel | integrais da velocidade e da Fuel Rate |
| Fuel Remaining (l) | nível de combustível × capacidade do tanque |

O OBDLink assume gasolina pura: não usa o teor de etanol nem as correções de combustível.
AFR, densidade, preço, tanque, cilindrada e eficiência volumétrica podem ser alterados no
botão de ajustes da aba.

Opção **Leitura rápida**: envia o PID com o sufixo `1` (ex.: `010C1`), para o adaptador responder
assim que a primeira ECU responder. Se aparecerem muitos valores vazios (alguns clones de ELM327
não aceitam o sufixo), desligue a opção.

Arquivos da funcionalidade:

- `lib/functions/obd_pids.dart`: tabela de PIDs e interpretação das respostas
- `lib/functions/obd_calculados.dart`: PIDs calculados
- `lib/functions/elm327.dart`: comunicação com o adaptador, um comando por vez
- `lib/functions/csv_logger.dart`: gravação do CSV linha a linha
- `lib/widgets/pidScanner.dart` e `lib/screens/scannerPage.dart`: a página
- `test/obd_pids_test.dart`: testes (`flutter test`)

---

## Primeiros passos

### Pré-requisitos

- Flutter SDK compatível com Dart `^3.5.3`
- Android Studio ou Xcode para deploy mobile
- Dispositivo Android ou emulador com suporte a Bluetooth (Android é o alvo principal)
- Um projeto Firebase configurado caso deseje sincronização com Firestore

---

### Clonar e instalar

```bash
git clone <repository-url>
cd fuel_sentinel
flutter pub get
```

---

### Configurar o Firebase

As opções do Firebase são carregadas a partir de `lib/functions/firebaseOptions.dart`.

Atualize este arquivo com as configurações do seu projeto Firebase ou substitua-o pela sua própria configuração.

Caso o projeto ainda não esteja configurado, utilize o Firebase CLI ou o console do Firebase para criar uma nova aplicação e baixar os dados de configuração gerados.

---

### Executar o aplicativo

```bash
flutter run -d <device-id>
```

Para Android:

```bash
flutter run -d emulator-5554
```

O aplicativo solicita permissões de Bluetooth, localização e armazenamento em tempo de execução ao ser iniciado.

---

### Tarefas de desenvolvimento

Execute a geração de código e limpe artefatos antigos ao atualizar rotas ou modelos gerados:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

Caso faça alterações em rotas ou adapters do Hive, execute novamente a geração de código para recriar arquivos como `lib/route/autoroute.gr.dart`.

---

## Estrutura do projeto

- `lib/main.dart` — ponto de entrada da aplicação, inicialização do Firebase, configuração do Hive, gerenciamento de permissões e registro do Workmanager
- `lib/route/autoroute.dart` — declarações de rotas utilizadas pelo `auto_route`
- `lib/screens/` — páginas principais da aplicação, como dashboard OBD e telas de configuração
- `lib/widgets/` — widgets reutilizáveis para Bluetooth, coleta de dados, configuração e mapas
- `lib/dataBaseClass/` — modelos Hive e classes de banco de dados local
- `lib/functions/` — funções auxiliares para integração OBD e opções do Firebase
- `pubspec.yaml` — manifesto de dependências e configurações do Flutter

---

## Suporte

Caso precise de ajuda ou queira reportar um bug:

- abra uma issue no GitHub deste repositório
- revise os arquivos em `lib/` para detalhes de implementação
- consulte o `pubspec.yaml` para versões de pacotes e dependências

---

## Contribuição

Contribuições são bem-vindas através de issues e pull requests. Siga o fluxo padrão do GitHub:

1. Faça um fork do repositório
2. Crie uma branch para sua funcionalidade
3. Teste suas alterações localmente
4. Envie um pull request com uma descrição clara

Caso adicione diretrizes formais de contribuição, inclua um arquivo `CONTRIBUTING.md` no repositório.

---

## Observações

- O nome atual do pacote é `obdapp` e o aplicativo utiliza um fluxo Bluetooth focado em Android.
- Atualmente não há um arquivo `LICENSE` no repositório. Adicione um caso deseje publicar ou compartilhar o projeto publicamente.
- O fluxo principal de execução está configurado em `lib/main.dart`, incluindo `Hive.initFlutter`, inicialização do Firebase e registro de tarefas em segundo plano.
