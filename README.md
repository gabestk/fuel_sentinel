# 📱 Aplicativo de Monitoramento Veicular (Fuel Sentinel)

Este repositório contém o `Fuel Sentinel`, um aplicativo desenvolvido em Flutter como parte de um projeto de mestrado. O objetivo principal do aplicativo é coletar dados veiculares em tempo real através da interface OBD-II, processá-los e enviá-los para uma plataforma em nuvem (Firebase) para análise e rastreamento do comportamento veicular.

## 📑 Índice

- [Visão Geral](#-visão-geral)
- [✨ Funcionalidades Principais](#-funcionalidades-principais)
- [🛠️ Tecnologias Utilizadas](#️-tecnologias-utilizadas)
- [⚙️ Arquitetura do Sistema](#️-arquitetura-do-sistema)
- [🔧 Pré-requisitos](#-pré-requisitos)
- [🚀 Configuração e Instalação](#-configuração-e-instalação)
  - [1. Clonar o Repositório](#1-clonar-o-repositório)
  - [2. Configurar o Flutter](#2-configurar-o-flutter)
  - [3. Configurar o Firebase](#3-configurar-o-firebase)
  - [4. Permissões](#4-permissões)
- [ሩ Como Executar](#-como-executar)
- [📂 Estrutura do Projeto](#-estrutura-do-projeto)
- [🧩 Dependências Chave](#-dependências-chave)
- [🖼️ Telas e Fluxo](#️-telas-e-fluxo)
- [🤝 Contribuindo](#-contribuindo)
- [📄 Licença](#-licença)
- [📧 Contato](#-contato)

## 🔭 Visão Geral

O `Fuel Sentinel` permite a conexão com adaptadores OBD-II via Bluetooth para ler diversos parâmetros do veículo. Os dados coletados são armazenados localmente utilizando Hive e, quando disponível, sincronizados com o Cloud Firestore (Firebase). O aplicativo também captura dados de sensores do dispositivo móvel e informações de GPS, enriquecendo a análise do comportamento de condução. Uma funcionalidade adicional permite o registro fotográfico de bombas de combustível, potencialmente para controle de abastecimento.

## ✨ Funcionalidades Principais

-   **📡 Conexão OBD-II:**
    -   Conecta-se a dispositivos OBD-II via Bluetooth (`flutter_bluetooth_serial`).
    -   Descoberta e seleção de PIDs (Parameter IDs) suportados pelo veículo.
-   **🚗 Coleta de Dados Veiculares em Tempo Real:**
    -   Leitura de dados como velocidade, RPM, temperatura do motor, carga do motor, etc.
    -   Coleta de dados brutos e processados do OBD.
-   **📱 Coleta de Dados de Sensores do Dispositivo:**
    -   Utilização de `sensors_plus` para coletar dados de acelerômetro, giroscópio, etc. (verificar implementação específica para detalhes).
-   **🗺️ Rastreamento por GPS:**
    -   Coleta de dados de localização (`geolocator`).
    -   Exibição de mapas na interface (`flutter_map`).
-   **📸 Captura de Fotos:**
    -   Funcionalidade para tirar fotos (ex: bomba de combustível) usando `image_picker`. (Nota: O local de armazenamento destas imagens - Firebase Storage, S3 ou local - precisa ser verificado no código ou documentado pelo desenvolvedor original).
-   **🧠 Processamento de Dados:**
    -   Cálculos e transformações sobre os dados coletados (ex: `math_expressions`).
    -   Lógica para detecção de falhas na comunicação com o veículo.
-   **🗂️ Armazenamento de Dados:**
    -   **Local:** Utiliza Hive (`hive`, `hive_flutter`) para armazenamento persistente no dispositivo, permitindo funcionamento offline. Inclui diversos adaptadores Hive para objetos customizados.
    -   **Nuvem:** Envio dos dados para o Cloud Firestore (`cloud_firestore`) para análise e backup.
-   **👤 Interface do Usuário:**
    -   Interface para condutores com visualização simplificada dos dados.
    -   Gráficos para visualização de dados históricos e em tempo real (`syncfusion_flutter_charts`).
    -   Navegação intuitiva com `auto_route` e `salomon_bottom_bar`.
-   **⚙️ Tarefas em Background:**
    -   Utilização de `workmanager` para executar tarefas em segundo plano (ex: upload de dados).
-   **🔐 Segurança (Potencial):**
    -   Dependências como `elliptic`, `ecdsa`, `crypto` sugerem funcionalidades de segurança ou assinatura de dados.
-   **☁️ Integração AWS (Potencial):**
    -   Presença de dependências `aws_signature_v4` e `aws_common`. O uso específico (ex: S3 para fotos, Cognito para autenticação complementar) deve ser verificado. A funcionalidade principal de dados veiculares parece centrada no Firebase.

## 🛠️ Tecnologias Utilizadas

-   **Flutter:** Framework UI para desenvolvimento de aplicações nativas multiplataforma.
-   **Dart:** Linguagem de programação utilizada pelo Flutter.
-   **Hive:** Banco de dados NoSQL leve e rápido para armazenamento local no dispositivo.
-   **flutter_bluetooth_serial:** Para comunicação Bluetooth com adaptadores OBD-II.
-   **geolocator:** Para obter coordenadas GPS.
-   **sensors_plus:** Para acesso a sensores do dispositivo (acelerômetro, giroscópio).
-   **auto_route:** Para gerenciamento de rotas e navegação.
-   **workmanager:** Para execução de tarefas em segundo plano.
-   **image_picker:** Para seleção de imagens da galeria ou captura pela câmera.
-   **path_provider:** Para encontrar caminhos de sistema de arquivos no dispositivo.
-   **permission_handler:** Para solicitar e verificar permissões em tempo de execução.

## ⚙️ Arquitetura do Sistema

O fluxo de dados geral do aplicativo pode ser descrito como:

1.  **Coleta de Dados:**
    *   O aplicativo se conecta a um adaptador OBD-II via Bluetooth.
    *   Dados do veículo (PIDs) são lidos.
    *   Dados de GPS e sensores do celular são coletados simultaneamente.
    *   O usuário pode capturar fotos (ex: bomba de combustível).
2.  **Armazenamento Local:**
    *   Os dados coletados são primeiramente armazenados em um banco de dados local Hive. Isso garante que os dados não sejam perdidos em caso de falta de conectividade.
3.  **Sincronização com a Nuvem:**
    *   Quando há conexão com a internet, os dados armazenados localmente são enviados para o Amazon Timestream.
4.  **Visualização e Interação:**
    *   Visualização em tempo real dos dados via Amazon Grafana

## 🔧 Pré-requisitos

-   Flutter SDK (versão especificada em `pubspec.yaml` no `environment: sdk:`)
-   Dart SDK (compatível com a versão do Flutter)
-   Um editor de código como Android Studio ou VS Code com os plugins Flutter e Dart.
-   Um dispositivo Android/iOS ou emulador/simulador configurado.
-   Um adaptador OBD-II Bluetooth para funcionalidade completa.

## 🚀 Configuração e Instalação

Siga os passos abaixo para clonar e executar o projeto localmente:

### 1. Clonar o Repositório

```bash
git clone https://github.com/gabestk/app_mestrado.git
cd app_mestrado
```

(Nota: Substitua a URL pelo link correto do seu repositório, se diferente.)

### 2. Configurar o Flutter

```bash
flutter pub get
```

Este comando irá baixar todas as dependências listadas no arquivo `pubspec.yaml`.

### 3. Permissões

O aplicativo requer as seguintes permissões, que são solicitadas em tempo de execução (`permission_handler`):

-   **Localização:** Para rastreamento GPS.
-   **Bluetooth:** Para comunicação com o adaptador OBD-II.
-   **Armazenamento (em versões mais antigas do Android):** Para armazenar dados localmente.
-   **Câmera/Galeria (se a funcionalidade de foto estiver ativa):** Para capturar/selecionar fotos.

Certifique-se de que as permissões necessárias também estão declaradas nos arquivos `AndroidManifest.xml` (para Android) e `Info.plist` (para iOS).

## ሩ Como Executar

Após a configuração:

1.  **Conecte um Dispositivo ou Inicie um Emulador/Simulador.**
2.  **Execute o Aplicativo:**
    ```bash
    flutter run
    ```
    Para executar em um dispositivo específico, você pode usar `flutter run -d <deviceId>`.

## 📂 Estrutura do Projeto

A estrutura principal do código-fonte na pasta `lib/` é organizada da seguinte forma:

-   `lib/`
    -   `dataBaseClass/`: Contém as classes de modelo de dados (ex: `obdRawData.dart`, `vehiclesUser.dart`) e seus adaptadores Hive gerados (`*.g.dart`).
    -   `functions/`: Módulos com lógica central do aplicativo:
        -   `InternalDatabase.dart`: Gerenciamento do banco de dados local Hive.
        -   `firebaseOptions.dart`: Configurações do Firebase para diferentes plataformas.
        -   `math.dart`: Funções matemáticas auxiliares.
        -   `obdPlugin.dart`: Lógica para interação com o plugin OBD.
        -   `repository.dart`: Lógica para comunicação com o backend (Firestore).
        -   `security.dart`: (Potencialmente) Funções relacionadas à segurança.
    -   `route/`: Configuração de navegação utilizando `auto_route`.
        -   `autoroute.dart`: Definição das rotas.
        -   `autoroute.gr.dart`: Arquivo gerado pelo `auto_route`.
    -   `screens/`: Widgets que representam as diferentes telas do aplicativo (ex: `appMainPage.dart`, `OBDdatacollect.dart`, `historyRiderUserPage.dart`).
    -   `widgets/`: Widgets reutilizáveis utilizados em várias telas (ex: `MapGps.dart`, `acc.dart` para gráficos de aceleração, `navigationWidget.dart`).
    -   `main.dart`: Ponto de entrada principal do aplicativo, onde ocorrem as inicializações.
-   `android/`: Arquivos e configurações específicas da plataforma Android.
-   `ios/`: Arquivos e configurações específicas da plataforma iOS.
-   `pubspec.yaml`: Define as dependências do projeto, versão, assets, etc.
-   `condutor.png`: Imagem da interface do condutor.
-   `fluxodeinteração.png`: Diagrama do fluxo de interação do aplicativo.

## 🧩 Dependências Chave

-   **`cloud_firestore`:** Para interagir com o banco de dados Firebase Firestore.
-   **`firebase_core`:** Para inicializar os serviços Firebase.
-   **`hive` & `hive_flutter`:** Para armazenamento local NoSQL.
-   **`hive_generator` & `build_runner`:** Para gerar adaptadores Hive.
-   **`flutter_bluetooth_serial`:** Para comunicação Bluetooth.
-   **`geolocator`:** Para obter dados de GPS.
-   **`sensors_plus`:** Para acessar sensores do dispositivo.
-   **`auto_route` & `auto_route_generator`:** Para navegação e geração de rotas.
-   **`salomon_bottom_bar`:** Para a barra de navegação inferior customizada.
-   **`syncfusion_flutter_charts`:** Para criar gráficos.
-   **`permission_handler`:** Para gerenciar permissões em tempo de execução.
-   **`workmanager`:** Para tarefas em segundo plano.
-   **`image_picker`:** Para funcionalidades de câmera e galeria.
-   **`path_provider`:** Para obter caminhos de diretórios do sistema.

## 🖼️ Telas e Fluxo

*Interface principal do condutor (condutor.png):*
![Interface do Condutor](condutor.png)

O fluxo de interação do usuário geralmente envolve:
1.  Abrir o aplicativo.
2.  Conectar-se a um adaptador OBD-II.
3.  Iniciar uma sessão de monitoramento/viagem.
4.  Visualizar dados em tempo real (velocidade, RPM, mapa, etc.).
5.  Acessar o histórico de viagens/dados.
6.  Configurar preferências (se aplicável).

## 🤝 Contribuindo

Contribuições são bem-vindas! Se você deseja contribuir para este projeto, por favor, siga estas etapas:

1.  Faça um Fork do repositório.
2.  Crie uma nova Branch (`git checkout -b feature/sua-feature`).
3.  Faça suas alterações e commit (`git commit -m 'Adiciona sua-feature'`).
4.  Faça um Push para a Branch (`git push origin feature/sua-feature`).
5.  Abra um Pull Request.

Por favor, tente manter a consistência do código e adicione comentários onde necessário.

## 📄 Licença

Este projeto não possui um arquivo de licença definido. Recomenda-se adicionar um, como MIT, Apache 2.0, ou GPL, dependendo dos requisitos do projeto de mestrado e das dependências utilizadas. Para adicionar uma licença MIT, por exemplo, crie um arquivo `LICENSE` na raiz do projeto com o seguinte conteúdo:

```
MIT License

Copyright (c) [2025] [Gabriel Trajano de Almeida]

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## 📧 Contato e Informações extras

Para dúvidas ou informações sobre o projeto, entre em contato com o desenvolvedor principal:
-   Nome: (Gabriel Trajano de Almeida - verificar `pubspec.yaml` ou commits)
-   Email: (gabriel.trajano97@hotmail.com - verificar `pubspec.yaml` ou commits)
-   GitHub: [gabestk](https://github.com/gabestk) (Baseado na URL do clone no README original)

Este projeto contou com recursos do Conselho Nacional de Desenvolvimento
Científico e Tecnológico (CNPq) que financiou parte desta pesquisa, por meio do projeto
Conecta2AI (Processo nº 405531/2022-2).
O projeto contou também com recursos da FAPERJ, processo E-26/290.124/2021 -
Projeto MobiCrowd; e com apoio do Pronametro.
```
