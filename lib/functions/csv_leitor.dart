// Leitura de arquivos CSV (do app ou do OBDLink) para exibir dentro do app.
// Dart puro, testado em test/obd_pids_test.dart.

class TabelaCsv {
  final List<String> colunas;
  final List<List<String>> linhas;
  const TabelaCsv(this.colunas, this.linhas);

  int get nLinhas => linhas.length;

  /// Valor numérico de uma célula, ou null se vazia/não numérica.
  double? numero(int linha, int coluna) {
    final l = linhas[linha];
    if (coluna >= l.length) return null;
    return double.tryParse(l[coluna].trim());
  }

  /// Colunas que têm ao menos um número (as que dá para pôr num gráfico).
  List<int> colunasNumericas() => [
        for (var c = 0; c < colunas.length; c++)
          if (linhas.any((l) => c < l.length && double.tryParse(l[c].trim()) != null)) c
      ];

  /// Tempo de cada linha em segundos desde a primeira: usa "Elapsed time (sec)"
  /// ou "Tempo (s)" se existir, senão a coluna "Time" do OBDLink, senão o índice.
  List<double> tempos() {
    final iElapsed = colunas.indexWhere(
        (c) => c == 'Elapsed time (sec)' || c == 'Tempo (s)');
    if (iElapsed >= 0) {
      final t = [for (var i = 0; i < nLinhas; i++) numero(i, iElapsed)];
      if (t.every((v) => v != null)) return t.cast<double>();
    }
    final iTime = colunas.indexOf('Time');
    if (iTime >= 0) {
      final t = [for (final l in linhas) iTime < l.length ? lerHoraObdlink(l[iTime]) : null];
      if (t.isNotEmpty && t.every((v) => v != null)) {
        final t0 = t.first!;
        return [for (final v in t) (v!.difference(t0).inMicroseconds) / 1e6];
      }
    }
    return [for (var i = 0; i < nLinhas; i++) i.toDouble()];
  }
}

/// Lê a coluna "Time" do OBDLink: "09/30/2026 01:36:32.3944 PM".
DateTime? lerHoraObdlink(String s) {
  final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4}) (\d{1,2}):(\d{2}):(\d{2})(?:\.(\d+))? ?(AM|PM)?$')
      .firstMatch(s.trim());
  if (m == null) return null;
  var h = int.parse(m[4]!);
  final ampm = m[8];
  if (ampm == 'PM' && h < 12) h += 12;
  if (ampm == 'AM' && h == 12) h = 0;
  final frac = (m[7] ?? '0').padRight(6, '0').substring(0, 6);
  return DateTime(int.parse(m[3]!), int.parse(m[1]!), int.parse(m[2]!), h,
      int.parse(m[5]!), int.parse(m[6]!), 0, int.parse(frac));
}

/// Separa uma linha de CSV em campos, respeitando aspas.
List<String> _campos(String linha) {
  final out = <String>[];
  final atual = StringBuffer();
  var aspas = false;
  for (var i = 0; i < linha.length; i++) {
    final ch = linha[i];
    if (aspas) {
      if (ch == '"') {
        if (i + 1 < linha.length && linha[i + 1] == '"') {
          atual.write('"');
          i++;
        } else {
          aspas = false;
        }
      } else {
        atual.write(ch);
      }
    } else if (ch == '"') {
      aspas = true;
    } else if (ch == ',') {
      out.add(atual.toString());
      atual.clear();
    } else {
      atual.write(ch);
    }
  }
  out.add(atual.toString());
  return out;
}

/// Interpreta o texto de um CSV. Remove o BOM e os espaços do cabeçalho
/// (o OBDLink separa o cabeçalho com ", ").
TabelaCsv lerCsv(String texto) {
  if (texto.startsWith('﻿')) texto = texto.substring(1);
  final linhas = texto.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
  if (linhas.isEmpty) return const TabelaCsv([], []);
  final colunas = _campos(linhas.first).map((c) => c.trim()).toList();
  return TabelaCsv(colunas, [for (final l in linhas.skip(1)) _campos(l)]);
}
