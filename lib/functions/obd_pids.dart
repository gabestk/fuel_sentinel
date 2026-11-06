// Tabela de PIDs do modo 01 (SAE J1979) e funções para interpretar as respostas
// de um adaptador ELM327 (OBDLink, Vgate, clones).
//
// Os nomes das colunas do CSV seguem os do aplicativo do OBDLink (mesmo texto e
// mesmas unidades: pressões em bar, por exemplo), para que os arquivos gerados
// pelo app possam ser lidos pelos mesmos scripts.
//
// Este arquivo é Dart puro (não importa Flutter) para poder ser testado com
// `flutter test test/obd_pids_test.dart`.

/// Uma grandeza física extraída da resposta de um PID. A maioria dos PIDs tem
/// uma saída, mas alguns têm duas (ex.: sondas O2 com tensão e correção).
class Saida {
  /// Nome da coluna no CSV, sem a unidade (igual ao OBDLink).
  final String csv;
  final String unidade;
  final double? Function(List<int> b) formula;

  const Saida(this.csv, this.unidade, this.formula);

  String get coluna => unidade.isEmpty ? csv : '$csv ($unidade)';
}

/// Definição de um PID do modo 01.
class PidDef {
  final int pid;

  /// Nome em português, mostrado na tela.
  final String nome;
  final List<Saida> saidas;

  /// PIDs que mudam devagar (temperaturas, nível, contadores) são lidos com
  /// menos frequência, o que deixa os rápidos (rotação, velocidade, MAF) mais
  /// atualizados.
  final bool lento;

  const PidDef(this.pid, this.nome, this.saidas, {this.lento = false});

  /// Comando enviado ao ELM327, ex.: "010C".
  String get comando => '01${hex2(pid)}';

  /// Rótulo do PID, ex.: "01 0C".
  String get codigo => '01 ${hex2(pid)}';

  bool get temFormula => saidas.isNotEmpty;

  String get unidade => saidas.isEmpty ? 'hex' : saidas.first.unidade;

  /// Colunas no CSV. Sem fórmula, uma coluna com os bytes em hexadecimal.
  List<String> get colunas =>
      saidas.isEmpty ? ['PID 01 ${hex2(pid)} (hex)'] : [for (final s in saidas) s.coluna];
}

String hex2(int v) => v.toRadixString(16).toUpperCase().padLeft(2, '0');

// ---------------------------------------------------------------------------
// Fórmulas auxiliares (A = b[0], B = b[1], ...)
// ---------------------------------------------------------------------------
double? _a(List<int> b) => b.isNotEmpty ? b[0].toDouble() : null;
double? _b(List<int> b) => b.length >= 2 ? b[1].toDouble() : null;
double? _ab(List<int> b) => b.length >= 2 ? (b[0] * 256 + b[1]).toDouble() : null;
double? _pct(List<int> b) => b.isNotEmpty ? b[0] * 100 / 255 : null;
double? _trim(List<int> b) => b.isNotEmpty ? (b[0] - 128) * 100 / 128 : null;
double? _trimB(List<int> b) => b.length >= 2 ? (b[1] - 128) * 100 / 128 : null;
double? _temp(List<int> b) => b.isNotEmpty ? b[0] - 40.0 : null;
double? _barA(List<int> b) => b.isNotEmpty ? b[0] / 100 : null; // kPa -> bar
double? _torque(List<int> b) => b.isNotEmpty ? b[0] - 125.0 : null;
double? _lambda(List<int> b) {
  final v = _ab(b);
  return v == null ? null : v * 2 / 65536;
}

double? _escala(List<int> b, double k, [double soma = 0]) {
  final v = _ab(b);
  return v == null ? null : v * k + soma;
}

double? _signed16(List<int> b) {
  final v = _ab(b);
  if (v == null) return null;
  return v >= 32768 ? v - 65536 : v;
}

/// PID com uma saída.
PidDef _p(int pid, String nome, String csv, String unidade,
        double? Function(List<int>) f, {bool lento = false}) =>
    PidDef(pid, nome, [Saida(csv, unidade, f)], lento: lento);

String _bs(int i) => 'Bank ${i ~/ 4 + 1}  Sensor ${i % 4 + 1}'; // dois espaços, como no OBDLink
String _bsPt(int i) => 'B${i ~/ 4 + 1}S${i % 4 + 1}';

/// PIDs do modo 01 com nome, unidade e fórmula. PIDs suportados pelo veículo
/// que não estão aqui aparecem como "PID 01 XX" e são gravados em hexadecimal.
final Map<int, PidDef> tabelaPids = {
  for (final p in <PidDef>[
    _p(0x01, 'Status dos monitores desde a limpeza de DTC', 'Monitor status since DTCs cleared', '', _ab, lento: true),
    _p(0x02, 'DTC que gerou o freeze frame', 'Freeze DTC', '', _ab, lento: true),
    PidDef(0x03, 'Status do sistema de combustível', [
      Saida('Fuel system 1 status', '', _a),
      Saida('Fuel system 2 status', '', _b),
    ]),
    _p(0x04, 'Carga calculada do motor', 'Calculated load value', '%', _pct),
    _p(0x05, 'Temperatura do líquido de arrefecimento', 'Engine coolant temperature', '°C', _temp, lento: true),
    _p(0x06, 'Correção de combustível de curto prazo banco 1 (STFT)', 'Short term fuel % trim - Bank 1', '%', _trim),
    _p(0x07, 'Correção de combustível de longo prazo banco 1 (LTFT)', 'Long term fuel % trim - Bank 1', '%', _trim),
    _p(0x08, 'Correção de combustível de curto prazo banco 2 (STFT)', 'Short term fuel % trim - Bank 3', '%', _trim),
    _p(0x09, 'Correção de combustível de longo prazo banco 2 (LTFT)', 'Long term fuel % trim - Bank 3', '%', _trim),
    _p(0x0A, 'Pressão de combustível', 'Fuel pressure', 'bar', (b) => b.isNotEmpty ? b[0] * 3 / 100 : null),
    _p(0x0B, 'Pressão absoluta do coletor de admissão (MAP)', 'Intake manifold absolute pressure', 'bar', _barA),
    _p(0x0C, 'Rotação do motor', 'Engine RPM', 'RPM', (b) => _escala(b, 0.25)),
    _p(0x0D, 'Velocidade do veículo', 'Vehicle speed', 'km/h', _a),
    _p(0x0E, 'Avanço de ignição', 'Ignition timing advance for #1 cylinder', 'deg',
        (b) => b.isNotEmpty ? b[0] / 2 - 64 : null),
    _p(0x0F, 'Temperatura do ar de admissão', 'Intake air temperature', '°C', _temp),
    _p(0x10, 'Vazão mássica de ar (MAF)', 'Mass air flow rate', 'g/s', (b) => _escala(b, 0.01)),
    _p(0x11, 'Posição absoluta da borboleta', 'Absolute throttle position', '%', _pct),
    _p(0x12, 'Status do ar secundário comandado', 'Commanded secondary air status', '', _a, lento: true),
    _p(0x13, 'Sensores de oxigênio presentes (2 bancos)', 'Location of oxygen sensors', '', _a, lento: true),
    for (var i = 0; i < 8; i++)
      PidDef(0x14 + i, 'Sonda O2 ${_bsPt(i)} (tensão e correção)', [
        Saida('O2 voltage (${_bs(i)})', 'V', (b) => b.isNotEmpty ? b[0] / 200 : null),
        Saida('Short term fuel trim (${_bs(i)})', '%', _trimB),
      ]),
    _p(0x1C, 'Norma OBD do veículo', 'OBD requirements to which vehicle or engine is certified', '', _a, lento: true),
    _p(0x1D, 'Sensores de oxigênio presentes (4 bancos)', 'Location of oxygen sensors (4 banks)', '', _a, lento: true),
    _p(0x1E, 'Status da entrada auxiliar', 'Auxiliary input status', '', _a, lento: true),
    _p(0x1F, 'Tempo desde a partida do motor', 'Time since engine start', 'sec', _ab, lento: true),
    _p(0x21, 'Distância percorrida com a MIL acesa', 'Distance traveled while MIL is activated', 'km', _ab, lento: true),
    _p(0x22, 'Pressão do rail de combustível (relativa ao vácuo)', 'Fuel rail pressure (relative to manifold vacuum)', 'bar',
        (b) => _escala(b, 0.079 / 100)),
    _p(0x23, 'Pressão do rail de combustível (injeção direta)', 'Fuel rail pressure (diesel, or gasoline direct inject)', 'bar',
        (b) => _escala(b, 10 / 100)),
    for (var i = 0; i < 8; i++)
      PidDef(0x24 + i, 'Sonda O2 S${i + 1} banda larga (lambda e tensão)', [
        Saida('O2 sensor ${i + 1} equivalence ratio', '', _lambda),
        Saida('O2 sensor ${i + 1} voltage', 'V', (b) => b.length >= 4 ? (b[2] * 256 + b[3]) * 8 / 65536 : null),
      ]),
    _p(0x2C, 'EGR comandado', 'Commanded EGR', '%', _pct),
    _p(0x2D, 'Erro do EGR', 'EGR Error', '%', _trim),
    _p(0x2E, 'Purga evaporativa comandada', 'Commanded evaporative purge', '%', _pct),
    _p(0x2F, 'Nível de combustível', 'Fuel level input', '%', _pct, lento: true),
    _p(0x30, 'Aquecimentos desde a limpeza de DTC', 'Number of warm-ups since DTCs cleared', '', _a, lento: true),
    _p(0x31, 'Distância desde a limpeza de DTC', 'Distance traveled since DTCs cleared', 'km', _ab, lento: true),
    _p(0x32, 'Pressão de vapor do sistema evaporativo', 'Evap. System Vapor Pressure', 'Pa', (b) {
      final v = _signed16(b);
      return v == null ? null : v / 4;
    }),
    _p(0x33, 'Pressão barométrica absoluta', 'Barometric pressure', 'bar', _barA, lento: true),
    for (var i = 0; i < 8; i++)
      PidDef(0x34 + i, 'Sonda O2 S${i + 1} banda larga (lambda e corrente)', [
        Saida('O2 sensor ${i + 1} equivalence ratio (current)', '', _lambda),
        Saida('O2 sensor ${i + 1} current', 'mA',
            (b) => b.length >= 4 ? (b[2] * 256 + b[3]) / 256 - 128 : null),
      ]),
    _p(0x3C, 'Temperatura do catalisador banco 1 sensor 1', 'Catalyst temperature (Bank 1 Sensor 1)', '°C', (b) => _escala(b, 0.1, -40), lento: true),
    _p(0x3D, 'Temperatura do catalisador banco 2 sensor 1', 'Catalyst temperature (Bank 2 Sensor 1)', '°C', (b) => _escala(b, 0.1, -40), lento: true),
    _p(0x3E, 'Temperatura do catalisador banco 1 sensor 2', 'Catalyst temperature (Bank 1 Sensor 2)', '°C', (b) => _escala(b, 0.1, -40), lento: true),
    _p(0x3F, 'Temperatura do catalisador banco 2 sensor 2', 'Catalyst temperature (Bank 2 Sensor 2)', '°C', (b) => _escala(b, 0.1, -40), lento: true),
    _p(0x41, 'Status dos monitores neste ciclo', 'Monitor status this drive cycle', '', _ab, lento: true),
    _p(0x42, 'Tensão do módulo de controle', 'Control module voltage', 'V', (b) => _escala(b, 0.001), lento: true),
    _p(0x43, 'Carga absoluta do motor', 'Absolute load value', '%', (b) => _escala(b, 100 / 255)),
    _p(0x44, 'Lambda comandado (razão de equivalência)', 'Fuel/Air commanded equivalence ratio', '', _lambda),
    _p(0x45, 'Posição relativa da borboleta', 'Relative throttle position', '%', _pct),
    _p(0x46, 'Temperatura ambiente', 'Ambient air temperature', '°C', _temp, lento: true),
    _p(0x47, 'Posição absoluta da borboleta B', 'Absolute throttle position B', '%', _pct),
    _p(0x48, 'Posição absoluta da borboleta C', 'Absolute throttle position C', '%', _pct),
    _p(0x49, 'Posição do pedal do acelerador D', 'Accelerator pedal position D', '%', _pct),
    _p(0x4A, 'Posição do pedal do acelerador E', 'Accelerator pedal position E', '%', _pct),
    _p(0x4B, 'Posição do pedal do acelerador F', 'Accelerator pedal position F', '%', _pct),
    _p(0x4C, 'Atuador da borboleta comandado', 'Commanded throttle actuator control', '%', _pct),
    _p(0x4D, 'Tempo com a MIL acesa', 'Time run with MIL on', 'min', _ab, lento: true),
    _p(0x4E, 'Tempo desde a limpeza de DTC', 'Time since trouble codes cleared', 'min', _ab, lento: true),
    _p(0x50, 'Valor máximo da vazão de ar (MAF)', 'Maximum value for air flow rate from mass air flow sensor', 'g/s',
        (b) => b.isNotEmpty ? b[0] * 10.0 : null, lento: true),
    _p(0x51, 'Tipo de combustível', 'Fuel type', '', _a, lento: true),
    _p(0x52, 'Teor de etanol no combustível', 'Alcohol fuel percentage', '%', _pct, lento: true),
    _p(0x53, 'Pressão absoluta de vapor do sistema evaporativo', 'Absolute evap system vapor pressure', 'kPa',
        (b) => _escala(b, 1 / 200)),
    _p(0x54, 'Pressão de vapor do sistema evaporativo', 'Evap system vapor pressure', 'Pa', _signed16),
    _p(0x55, 'Correção de curto prazo da sonda secundária banco 1', 'Short term secondary oxygen sensor trim bank 1', '%', _trim),
    _p(0x56, 'Correção de longo prazo da sonda secundária banco 1', 'Long term secondary oxygen sensor trim bank 1', '%', _trim),
    _p(0x57, 'Correção de curto prazo da sonda secundária banco 2', 'Short term secondary oxygen sensor trim bank 2', '%', _trim),
    _p(0x58, 'Correção de longo prazo da sonda secundária banco 2', 'Long term secondary oxygen sensor trim bank 2', '%', _trim),
    _p(0x59, 'Pressão absoluta do rail de combustível', 'Fuel rail absolute pressure', 'bar', (b) => _escala(b, 10 / 100)),
    _p(0x5A, 'Posição relativa do pedal do acelerador', 'Relative accelerator pedal position', '%', _pct),
    _p(0x5B, 'Vida restante da bateria híbrida', 'Hybrid battery pack remaining life', '%', _pct, lento: true),
    _p(0x5C, 'Temperatura do óleo do motor', 'Engine oil temperature', '°C', _temp, lento: true),
    _p(0x5D, 'Ponto de injeção de combustível', 'Fuel injection timing', 'deg', (b) => _escala(b, 1 / 128, -210)),
    _p(0x5E, 'Taxa de consumo de combustível do motor', 'Engine fuel rate', 'L/h', (b) => _escala(b, 0.05)),
    _p(0x5F, 'Requisitos de emissão do veículo', 'Emission requirements to which vehicle is designed', '', _a, lento: true),
    _p(0x61, 'Torque demandado pelo condutor', "Driver's demand engine - percent torque", '%', _torque),
    _p(0x62, 'Torque real do motor', 'Actual engine - percent torque', '%', _torque),
    _p(0x63, 'Torque de referência do motor', 'Engine reference torque', 'N•m', _ab, lento: true),
    _p(0xA6, 'Odômetro', 'Odometer', 'km', (b) {
      if (b.length < 4) return null;
      return ((b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]) / 10;
    }, lento: true),
  ])
    p.pid: p
};

/// PIDs que só informam quais outros PIDs existem (0x00, 0x20, 0x40...).
bool ehPidDeSuporte(int pid) => pid % 0x20 == 0;

/// Definição de um PID, inclusive dos que não estão na tabela.
PidDef definicaoDoPid(int pid) =>
    tabelaPids[pid] ?? PidDef(pid, 'PID 01 ${hex2(pid)}', const [], lento: true);

// ---------------------------------------------------------------------------
// Interpretação das respostas do ELM327
// ---------------------------------------------------------------------------

/// Mensagens do ELM327 que não são dados.
const _ruido = [
  'SEARCHING...',
  'SEARCHING',
  'BUS INIT: ...OK',
  'BUS INIT:...OK',
  'BUS INIT: OK',
  'BUS INIT',
  'STOPPED',
];

/// Respostas que indicam que o PID não respondeu.
bool respostaSemDados(String bruta) {
  final r = bruta.toUpperCase();
  return r.contains('NO DATA') ||
      r.contains('UNABLE TO CONNECT') ||
      r.contains('BUFFER FULL') ||
      r.contains('ERROR') ||
      r.trim() == '?';
}

/// Separa a resposta em linhas de hexadecimal sem espaços, uma por ECU/quadro.
List<String> linhasHex(String bruta) {
  var r = bruta.toUpperCase().replaceAll('>', '');
  for (final n in _ruido) {
    r = r.replaceAll(n, '\n');
  }
  return r
      .split(RegExp(r'[\r\n]+'))
      .map((l) => l.replaceAll(RegExp(r'\s'), ''))
      .where((l) => l.isNotEmpty && RegExp(r'^[0-9A-F]+$').hasMatch(l))
      .toList();
}

List<int> _bytes(String hex) => [
      for (var i = 0; i + 1 < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16)
    ];

/// Bytes de dados de todas as ECUs que responderam ao PID [pid] do modo 01.
/// Cada item da lista é a resposta de uma ECU, sem o "41 XX".
List<List<int>> respostasModo01(String bruta, int pid) {
  final prefixo = '41${hex2(pid)}';
  final saida = <List<int>>[];
  for (final linha in linhasHex(bruta)) {
    // Procura "41XX" alinhado a um byte. Sem cabeçalho a posição é par. Com
    // cabeçalho CAN de 11 bits ("7E8 06 41 0C ...") ela é ímpar, então aceita
    // a primeira ocorrência ímpar se não houver nenhuma par.
    int? inicio;
    int? impar;
    for (var i = linha.indexOf(prefixo); i >= 0; i = linha.indexOf(prefixo, i + 1)) {
      if (i.isEven) {
        inicio = i;
        break;
      }
      impar ??= i;
    }
    inicio ??= impar;
    if (inicio == null) continue;
    final dados = linha.substring(inicio + prefixo.length);
    if (dados.length >= 2) saida.add(_bytes(dados));
  }
  return saida;
}

/// PIDs informados como suportados pela resposta a 0100, 0120, 0140...
/// [base] é o PID de suporte consultado (0x00, 0x20, ...). Junta as respostas
/// de todas as ECUs.
Set<int> pidsSuportados(String bruta, int base) {
  final suportados = <int>{};
  for (final b in respostasModo01(bruta, base)) {
    if (b.length < 4) continue;
    for (var i = 0; i < 32; i++) {
      final bit = (b[i ~/ 8] >> (7 - i % 8)) & 1;
      if (bit == 1) suportados.add(base + i + 1);
    }
  }
  return suportados;
}

/// Formata um número para o CSV: inteiro sem casas, senão até 6 casas sem
/// zeros à direita (ex.: 9.019608, 0.27, 1847).
String numeroCsv(double v) {
  if (v.isNaN || v.isInfinite) return '';
  if (v == v.roundToDouble() && v.abs() < 1e15) return v.toStringAsFixed(0);
  var s = v.toStringAsFixed(6);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return s == '-0' ? '0' : s;
}

/// Resultado da leitura de um PID: um valor por saída e os bytes em hex.
class LeituraPid {
  final List<double?> valores;
  final String hex;
  const LeituraPid(this.valores, this.hex);

  static const vazia = LeituraPid([], '');

  bool get vazio => hex.isEmpty;

  /// Primeiro valor (o principal), ou null.
  double? get valor => valores.isEmpty ? null : valores.first;

  /// Campos do CSV, um por coluna do PID ([def.colunas]).
  List<String> paraCsv(PidDef def) {
    if (!def.temFormula) return [hex];
    return [
      for (var i = 0; i < def.saidas.length; i++)
        (i < valores.length && valores[i] != null) ? numeroCsv(valores[i]!) : ''
    ];
  }
}

/// Interpreta a resposta de um PID do modo 01 usando a primeira ECU que respondeu.
LeituraPid interpretar(String bruta, PidDef def) {
  if (respostaSemDados(bruta)) return LeituraPid.vazia;
  final respostas = respostasModo01(bruta, def.pid);
  if (respostas.isEmpty) return LeituraPid.vazia;
  final b = respostas.first;
  final hex = b.map(hex2).join(' ');
  return LeituraPid([for (final s in def.saidas) s.formula(b)], hex);
}

// ---------------------------------------------------------------------------
// VIN (modo 09, PID 02)
// ---------------------------------------------------------------------------

/// Caracteres válidos num VIN (sem I, O e Q).
final _caracterVin = RegExp(r'[A-HJ-NPR-Z0-9]');

/// Extrai o VIN da resposta ao comando "0902", em qualquer um dos formatos
/// que o ELM327 devolve:
///  - CAN, em vários quadros: "014\r0: 49 02 01 39 42 57\r1: 47 4B ...\r2: ..."
///  - CAN com cabeçalho: "7E8 10 14 49 02 01 39 42 57\r7E8 21 47 4B ..."
///  - ISO 9141/KWP, uma linha por pedaço: "49 02 01 00 00 00 39\r49 02 02 42 57 47 4B..."
/// Devolve '' se não encontrar 17 caracteres válidos.
String decodificarVin(String bruta) {
  if (respostaSemDados(bruta)) return '';
  var r = bruta.toUpperCase().replaceAll('>', '');
  for (final n in _ruido) {
    r = r.replaceAll(n, '\n');
  }
  final bytes = <int>[];
  var achou = false;
  for (var linha in r.split(RegExp(r'[\r\n]+'))) {
    linha = linha.trim();
    if (linha.isEmpty) continue;
    // índice do quadro CAN ("0:", "1:"...)
    linha = linha.replaceFirst(RegExp(r'^[0-9A-F]{1,2}:'), '');
    var hex = linha.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^[0-9A-F]+$').hasMatch(hex)) continue;
    if (hex == '0902') continue; // eco do comando
    final i = hex.indexOf('4902');
    if (i >= 0) {
      achou = true;
      // depois de "49 02" vem o número do item/sequência (1 byte)
      hex = hex.substring(i + 4);
      hex = hex.length >= 2 ? hex.substring(2) : '';
    } else if (!achou) {
      continue; // contagem de bytes ("014") ou lixo antes do início
    } else if (hex.length.isOdd || hex.length > 16 && hex.startsWith('7E')) {
      // quadro de continuação com cabeçalho CAN: "7E821..." -> tira cabeçalho e índice
      final m = RegExp(r'^7E[0-9A-F]2[0-9A-F]').firstMatch(hex);
      if (m != null) hex = hex.substring(m.end);
    }
    for (var k = 0; k + 1 < hex.length; k += 2) {
      bytes.add(int.parse(hex.substring(k, k + 2), radix: 16));
    }
  }
  final texto = String.fromCharCodes(bytes.where((b) => b >= 0x20 && b < 0x7F))
      .split('')
      .where((c) => _caracterVin.hasMatch(c))
      .join();
  if (texto.length < 17) return '';
  return texto.substring(texto.length - 17);
}
