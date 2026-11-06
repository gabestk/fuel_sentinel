// Detecta quando o nível de combustível (PID 01 2F) parou de variar.
//
// O sensor de nível é uma boia: oscila com o combustível balançando no tanque
// e, em muitos carros, a ECU filtra o valor de propósito, que sobe devagar
// depois de abastecer. Por isso o nível "antes" e o "depois" não são o valor
// de um instante, e sim a mediana de uma janela de leituras com o carro parado,
// aceita só quando a janela está estável:
//  * pelo menos [minLeituras] leituras cobrindo pelo menos [minDuracao]
//  * pouca dispersão: a diferença entre os percentis 20 e 80 da janela é no
//    máximo [dispersaoMax] pontos percentuais (descarta picos isolados)
//  * sem tendência: a mediana da primeira metade da janela e a da segunda
//    diferem no máximo [tendenciaMax] p.p. (o valor não está mais subindo)
//
// A mediana é usada no lugar da média porque não é puxada por picos.

class LeituraNivel {
  final DateTime hora;
  final double valor;
  const LeituraNivel(this.hora, this.valor);
}

double mediana(List<double> valores) {
  if (valores.isEmpty) return double.nan;
  final v = [...valores]..sort();
  final m = v.length ~/ 2;
  return v.length.isOdd ? v[m] : (v[m - 1] + v[m]) / 2;
}

/// Percentil por interpolação linear (p entre 0 e 1).
double percentil(List<double> valores, double p) {
  if (valores.isEmpty) return double.nan;
  final v = [...valores]..sort();
  final pos = p * (v.length - 1);
  final i = pos.floor();
  final f = pos - i;
  return i + 1 < v.length ? v[i] + (v[i + 1] - v[i]) * f : v[i];
}

class EstabilizadorNivel {
  final int minLeituras;
  final int maxLeituras;
  final Duration minDuracao;
  final double dispersaoMax;
  final double tendenciaMax;

  EstabilizadorNivel({
    this.minLeituras = 6,
    this.maxLeituras = 15,
    this.minDuracao = const Duration(seconds: 15),
    this.dispersaoMax = 1.0,
    this.tendenciaMax = 0.5,
  });

  final List<LeituraNivel> _janela = [];

  List<LeituraNivel> get janela => List.unmodifiable(_janela);
  int get quantidade => _janela.length;

  /// Acrescenta uma leitura válida (0 a 100 %). Valores fora disso são ignorados.
  void adicionar(double valor, DateTime hora) {
    if (!valor.isFinite || valor < 0 || valor > 100) return;
    _janela.add(LeituraNivel(hora, valor));
    while (_janela.length > maxLeituras) {
      _janela.removeAt(0);
    }
  }

  /// Descarta a janela (por exemplo, quando o carro andou).
  void reiniciar() => _janela.clear();

  List<double> get _valores => [for (final l in _janela) l.valor];

  /// Mediana da janela atual (NaN se não houver leituras).
  double get valor => mediana(_valores);

  double get dispersao =>
      _janela.isEmpty ? double.nan : percentil(_valores, 0.8) - percentil(_valores, 0.2);

  double get tendencia {
    if (_janela.length < 2) return double.nan;
    final v = _valores;
    final meio = v.length ~/ 2;
    return (mediana(v.sublist(meio)) - mediana(v.sublist(0, meio))).abs();
  }

  Duration get duracao =>
      _janela.length < 2 ? Duration.zero : _janela.last.hora.difference(_janela.first.hora);

  bool get estavel =>
      _janela.length >= minLeituras &&
      duracao >= minDuracao &&
      dispersao <= dispersaoMax &&
      tendencia <= tendenciaMax;

  /// Fração (0 a 1) do caminho até ter leituras e tempo suficientes, para a tela.
  double get progresso {
    final a = _janela.length / minLeituras;
    final b = minDuracao.inMilliseconds == 0 ? 1.0 : duracao.inMilliseconds / minDuracao.inMilliseconds;
    return (a < b ? a : b).clamp(0.0, 1.0);
  }
}
