// Cliente simples para adaptadores ELM327 via Bluetooth clássico (SPP).
//
// Diferente do ObdPlugin, cada comando espera a resposta completa (o prompt ">")
// antes de o próximo ser enviado. Isso evita misturar respostas quando muitos
// PIDs são lidos em sequência, como na coleta.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

import 'obd_pids.dart';

class Elm327 {
  BluetoothConnection? _conexao;
  StreamSubscription<Uint8List>? _assinatura;
  final StringBuffer _buffer = StringBuffer();
  Completer<String>? _pendente;
  Future<void> _fila = Future.value();

  /// Texto bruto de cada troca (comando -> resposta), útil para depuração.
  final void Function(String linha)? aoRegistrar;

  Elm327({this.aoRegistrar});

  bool get conectado => _conexao?.isConnected ?? false;

  Future<void> conectar(String endereco) async {
    await desconectar();
    _conexao = await BluetoothConnection.toAddress(endereco);
    _assinatura = _conexao!.input?.listen(
      _aoReceber,
      onDone: () => _falharPendente('Conexão Bluetooth encerrada'),
      onError: (Object e) => _falharPendente('Erro na conexão: $e'),
    );
  }

  void _aoReceber(Uint8List dados) {
    _buffer.write(latin1.decode(dados, allowInvalid: true));
    final texto = _buffer.toString();
    if (texto.contains('>')) {
      _buffer.clear();
      final p = _pendente;
      _pendente = null;
      if (p != null && !p.isCompleted) p.complete(texto);
    }
  }

  void _falharPendente(String motivo) {
    final p = _pendente;
    _pendente = null;
    if (p != null && !p.isCompleted) p.completeError(StateError(motivo));
  }

  /// Envia um comando e devolve a resposta bruta (sem o ">").
  /// Comandos são enfileirados: nunca há dois em andamento ao mesmo tempo.
  Future<String> enviar(String comando,
      {Duration timeout = const Duration(seconds: 3)}) {
    final resultado = _fila.then((_) => _enviarAgora(comando, timeout));
    _fila = resultado.then((_) {}, onError: (_) {});
    return resultado;
  }

  Future<String> _enviarAgora(String comando, Duration timeout) async {
    final c = _conexao;
    if (c == null || !c.isConnected) {
      throw StateError('Adaptador desconectado');
    }
    _buffer.clear();
    final completer = Completer<String>();
    _pendente = completer;
    c.output.add(Uint8List.fromList(ascii.encode('$comando\r')));
    await c.output.allSent;
    try {
      final resposta = await completer.future.timeout(timeout);
      aoRegistrar?.call('$comando -> ${resposta.replaceAll(RegExp(r'[\r\n>]+'), ' ').trim()}');
      return resposta.replaceAll('>', '').trim();
    } on TimeoutException {
      _pendente = null;
      aoRegistrar?.call('$comando -> (sem resposta em ${timeout.inMilliseconds} ms)');
      // descarta uma resposta atrasada para ela não ser lida como a do próximo comando
      await Future<void>.delayed(const Duration(milliseconds: 300));
      _buffer.clear();
      return '';
    }
  }

  /// Configuração inicial padrão: reinicia, desliga eco, espaços e cabeçalhos,
  /// e deixa o protocolo em automático. Devolve a versão do adaptador.
  Future<String> inicializar() async {
    final versao = await enviar('ATZ', timeout: const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final cmd in ['ATE0', 'ATL0', 'ATS0', 'ATH0', 'ATAT1', 'ATSP0']) {
      await enviar(cmd);
    }
    return versao.replaceAll(RegExp(r'\s+'), ' ').replaceAll('ATZ', '').trim();
  }

  /// VIN do veículo (modo 09, PID 02), ou '' se o veículo não informar.
  Future<String> lerVin() async =>
      decodificarVin(await enviar('0902', timeout: const Duration(seconds: 5)));

  /// Protocolo detectado (ex.: "ISO 15765-4 (CAN 11/500)").
  Future<String> protocolo() async => (await enviar('ATDP')).trim();

  /// Descobre todos os PIDs do modo 01 suportados, consultando 0100, 0120, 0140...
  /// enquanto o último bit de cada faixa indicar que existe a faixa seguinte.
  Future<List<int>> descobrirPids({void Function(String)? progresso}) async {
    final todos = <int>{};
    for (var base = 0x00; base <= 0xE0; base += 0x20) {
      progresso?.call('Consultando 01${hex2(base)}...');
      // a primeira consulta pode demorar enquanto o adaptador busca o protocolo
      final r = await enviar('01${hex2(base)}',
          timeout: Duration(seconds: base == 0 ? 15 : 4));
      final s = pidsSuportados(r, base);
      if (s.isEmpty) break;
      todos.addAll(s);
      if (!s.contains(base + 0x20)) break;
    }
    return todos.where((p) => !ehPidDeSuporte(p)).toList()..sort();
  }

  /// Lê um PID do modo 01. Com [primeiraResposta], o adaptador devolve assim que
  /// a primeira ECU responde (sufixo "1"), o que acelera bastante a coleta em CAN.
  Future<LeituraPid> ler(PidDef def, {bool primeiraResposta = true}) async {
    final r = await enviar(primeiraResposta ? '${def.comando}1' : def.comando,
        timeout: const Duration(seconds: 2));
    return interpretar(r, def);
  }

  Future<void> desconectar() async {
    _falharPendente('Desconectado');
    await _assinatura?.cancel();
    _assinatura = null;
    try {
      await _conexao?.close();
    } catch (_) {}
    _conexao?.dispose();
    _conexao = null;
  }
}
