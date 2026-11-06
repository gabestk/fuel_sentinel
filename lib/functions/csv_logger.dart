// Gravação das coletas em CSV, linha a linha, no mesmo formato do aplicativo do
// OBDLink: BOM UTF-8 no início, cabeçalho separado por ", ", linhas separadas
// por ",", ponto decimal e a coluna "Time" no formato "09/30/2026 01:36:32.3944 PM".
// Cada linha é gravada assim que é produzida, então os dados não se perdem se o
// aplicativo for fechado no meio da coleta.

import 'dart:io';

String _d2(int v) => v.toString().padLeft(2, '0');

/// Nome de arquivo seguro para Android (sem ":" nem espaços).
String carimboArquivo(DateTime t) =>
    '${t.year}-${_d2(t.month)}-${_d2(t.day)}_${_d2(t.hour)}-${_d2(t.minute)}-${_d2(t.second)}';

/// Data e hora no formato da coluna "Time" do OBDLink: MM/dd/yyyy hh:mm:ss.ffff AM/PM.
String carimboObdlink(DateTime t) {
  final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final ampm = t.hour < 12 ? 'AM' : 'PM';
  final frac = (t.millisecond * 10 + t.microsecond ~/ 100).toString().padLeft(4, '0');
  return '${_d2(t.month)}/${_d2(t.day)}/${t.year} ${_d2(h12)}:${_d2(t.minute)}:${_d2(t.second)}.$frac $ampm';
}

/// Escapa um campo de CSV (aspas quando há vírgula, aspas ou quebra de linha).
String campoCsv(String v) {
  if (v.contains(',') || v.contains('"') || v.contains('\n') || v.contains('\r')) {
    return '"${v.replaceAll('"', '""')}"';
  }
  return v;
}

String linhaCsv(Iterable<String> campos, {String separador = ','}) =>
    campos.map(campoCsv).join(separador);

class CsvLogger {
  final File arquivo;
  final RandomAccessFile _saida;
  int linhas = 0;

  CsvLogger._(this.arquivo, this._saida);

  /// Cria o arquivo e grava o cabeçalho.
  static Future<CsvLogger> criar(Directory pasta, String nome, List<String> cabecalho) async {
    await pasta.create(recursive: true);
    final f = File('${pasta.path}/$nome');
    final s = f.openSync(mode: FileMode.write);
    s.writeStringSync('﻿${linhaCsv(cabecalho, separador: ', ')}\n');
    s.flushSync();
    return CsvLogger._(f, s);
  }

  /// Grava uma linha. A escrita é síncrona e pequena, e o arquivo é descarregado
  /// no disco a cada 10 linhas.
  void gravar(List<String> campos) {
    _saida.writeStringSync('${linhaCsv(campos)}\n');
    linhas++;
    if (linhas % 10 == 0) _saida.flushSync();
  }

  Future<void> fechar() async {
    _saida.flushSync();
    _saida.closeSync();
  }
}
