// PIDs calculados, iguais aos que o aplicativo do OBDLink grava no CSV
// (Fuel Rate, Instant Fuel Economy, Trip Distance, Engine Power...).
//
// As constantes padrão foram obtidas ajustando um CSV real gravado pelo OBDLink:
//   Fuel Rate (l/hr)     = MAF (g/s) x 0,33279   -> AFR 14,7 e densidade 0,7359 kg/L
//   CO2 flow (g/s)       = Fuel Rate x 2347,7 / 3600   (2347,7 g de CO2 por litro)
//   Engine Power (PS)    = MAF (g/s) x 1,188916
//   Engine Torque (N•m)  = Engine Power (PS) x 7219,6 / rpm
//   MAF calculado (g/s)  = rpm/120 x MAP x cilindrada x eficiência volumétrica x M_ar / (R x T)
// Ou seja, o OBDLink assume gasolina pura e não usa o teor de etanol nem as
// correções de combustível. Todas as constantes podem ser alteradas na tela.
//
// Dart puro, testado em test/obd_pids_test.dart.

class ParametrosCalculo {
  double afr;
  double densidadeKgL;
  double co2GL;
  double psPorGs;
  double constanteTorque;
  double cilindradaL;
  double eficienciaVolumetrica;
  double precoLitro;
  double tanqueL;
  double limiteBruscoMs2;

  ParametrosCalculo({
    this.afr = 14.7,
    this.densidadeKgL = 0.7359,
    this.co2GL = 2347.7,
    this.psPorGs = 1.188916,
    this.constanteTorque = 7219.6,
    this.cilindradaL = 1.6,
    this.eficienciaVolumetrica = 0.8134,
    this.precoLitro = 3.50,
    this.tanqueL = 50,
    this.limiteBruscoMs2 = 2.94, // 0,3 g
  });

  Map<String, double> paraMapa() => {
        'afr': afr,
        'densidadeKgL': densidadeKgL,
        'co2GL': co2GL,
        'psPorGs': psPorGs,
        'constanteTorque': constanteTorque,
        'cilindradaL': cilindradaL,
        'eficienciaVolumetrica': eficienciaVolumetrica,
        'precoLitro': precoLitro,
        'tanqueL': tanqueL,
        'limiteBruscoMs2': limiteBruscoMs2,
      };

  void carregar(Map<String, double> m) {
    afr = m['afr'] ?? afr;
    densidadeKgL = m['densidadeKgL'] ?? densidadeKgL;
    co2GL = m['co2GL'] ?? co2GL;
    psPorGs = m['psPorGs'] ?? psPorGs;
    constanteTorque = m['constanteTorque'] ?? constanteTorque;
    cilindradaL = m['cilindradaL'] ?? cilindradaL;
    eficienciaVolumetrica = m['eficienciaVolumetrica'] ?? eficienciaVolumetrica;
    precoLitro = m['precoLitro'] ?? precoLitro;
    tanqueL = m['tanqueL'] ?? tanqueL;
    limiteBruscoMs2 = m['limiteBruscoMs2'] ?? limiteBruscoMs2;
  }
}

// PIDs usados pelos cálculos
const pidMap = 0x0B, pidRpm = 0x0C, pidVel = 0x0D, pidIat = 0x0F, pidMaf = 0x10, pidNivel = 0x2F;
const _combMaf = {pidMaf};
const _combMap = {pidMap, pidRpm, pidIat};

/// Um PID calculado: nome da coluna (igual ao OBDLink), descrição e os PIDs de
/// que depende. [requer] lista alternativas: basta uma estar disponível.
class CalcDef {
  final String id;
  final String csv;
  final String unidade;
  final String nome;
  final List<Set<int>> requer;

  const CalcDef(this.id, this.csv, this.unidade, this.nome, this.requer);

  String get coluna => unidade.isEmpty ? csv : '$csv ($unidade)';

  /// PIDs a ler para este cálculo, ou null se o veículo não tem os necessários.
  Set<int>? pidsNecessarios(Iterable<int> suportados) {
    final s = suportados.toSet();
    for (final alt in requer) {
      if (s.containsAll(alt)) return alt;
    }
    return null;
  }
}

List<Set<int>> _comb([Set<int> extra = const {}]) =>
    [_combMaf.union(extra), _combMap.union(extra)];

/// Calculados na mesma ordem do CSV do OBDLink.
final List<CalcDef> tabelaCalculados = [
  CalcDef('inst_fe', 'Instant Fuel Economy', 'l/100 km', 'Consumo instantâneo', _comb({pidVel})),
  CalcDef('total_fe', 'Total Fuel Economy', 'l/100 km', 'Consumo médio total', _comb({pidVel})),
  CalcDef('fuel_rate', 'Fuel Rate', 'l/hr', 'Vazão de combustível', _comb()),
  CalcDef('inst_co2', 'Instant CO2 rate', 'g/km', 'CO2 instantâneo por km', _comb({pidVel})),
  CalcDef('total_co2', 'Total CO2', 'kg', 'CO2 total', _comb()),
  CalcDef('co2_flow', 'CO2 flow', 'g/s', 'Vazão de CO2', _comb()),
  CalcDef('trip_dist', 'Trip Distance', 'km', 'Distância da viagem', [{pidVel}]),
  CalcDef('trip_fuel', 'Trip Fuel', 'l', 'Combustível da viagem', _comb()),
  CalcDef('trip_fe', 'Trip Fuel Economy', 'l/100 km', 'Consumo médio da viagem', _comb({pidVel})),
  CalcDef('trip_dur', 'Trip Duration', 'min', 'Duração da viagem', [<int>{}]),
  CalcDef('hard_brake', 'Hard Brake Count', '', 'Frenagens bruscas', [{pidVel}]),
  CalcDef('hard_accel', 'Hard Accel Count', '', 'Acelerações bruscas', [{pidVel}]),
  CalcDef('idle_count', 'Idling Count', '', 'Vezes em marcha lenta', [{pidVel, pidRpm}]),
  CalcDef('idle_sec', 'Seconds Idling', 'sec', 'Tempo em marcha lenta', [{pidVel, pidRpm}]),
  CalcDef('max_speed', 'Max Speed', 'km/h', 'Velocidade máxima', [{pidVel}]),
  CalcDef('avg_co2', 'Average Trip CO2 Rate', 'g/km', 'CO2 médio por km da viagem', _comb({pidVel})),
  CalcDef('trip_co2', 'Total Trip CO2', 'kg', 'CO2 total da viagem', _comb()),
  CalcDef('trip_cost', r'Trip Cost', r'R$', 'Custo da viagem', _comb()),
  CalcDef('avg_speed', 'Average Speed', 'km/h', 'Velocidade média', [{pidVel}]),
  CalcDef('maf_calc', 'Mass air flow rate (calculated)', 'g/s', 'MAF calculado (MAP, rpm e temperatura)', [_combMap]),
  CalcDef('accel', 'Acceleration', 'm/s²', 'Aceleração', [{pidVel}]),
  CalcDef('accel_avg', 'Acceleration (Avg)', 'm/s²', 'Aceleração média (5 s)', [{pidVel}]),
  CalcDef('power', 'Engine Power', 'PS', 'Potência do motor', _comb()),
  CalcDef('torque', 'Engine Torque', 'N•m', 'Torque do motor', _comb({pidRpm})),
  CalcDef('fuel_rem', 'Fuel Remaining', 'l', 'Combustível restante', [{pidNivel}]),
];

/// Recebe as leituras dos PIDs (com o instante de cada uma) e mantém os
/// acumulados da viagem. A viagem começa no início da coleta.
class Calculadora {
  final ParametrosCalculo p;
  Calculadora(this.p);

  // últimos valores (nas unidades do CSV)
  double? _vel, _maf, _mapBar, _rpm, _iat, _nivel;

  // acumulados
  double _t0 = 0;
  double? _tUltimo;
  double _distKm = 0, _combL = 0, _marchaLentaS = 0, _velMax = 0;
  int _nMarchaLenta = 0, _nFreio = 0, _nAcel = 0;
  bool _emMarchaLenta = false, _emFreio = false, _emAcel = false;

  // aceleração
  final List<(double, double)> _velHist = []; // (t, m/s)
  final List<(double, double)> _acelHist = []; // (t, m/s²)
  double? _acel;

  void iniciar(double t) {
    _t0 = t;
    _tUltimo = t;
  }

  /// MAF calculado pela densidade do ar (speed-density), em g/s.
  double? get mafCalculado {
    if (_rpm == null || _mapBar == null || _iat == null) return null;
    final vd = p.cilindradaL / 1000 * p.eficienciaVolumetrica; // m³ por ciclo de 2 voltas
    final rho = _mapBar! * 1e5 * 0.028964 / (8.314 * (_iat! + 273.15)); // kg/m³
    return _rpm! / 120 * vd * rho * 1000;
  }

  /// MAF usado nos cálculos: o do sensor, ou o calculado se não houver sensor.
  double? get _mafUsado => _maf ?? mafCalculado;

  /// Vazão de combustível em L/h.
  double? get vazaoLh {
    final m = _mafUsado;
    if (m == null) return null;
    return m * 3600 / (p.afr * p.densidadeKgL * 1000);
  }

  /// Registra uma leitura de PID feita no instante [t] (s).
  void registrar(int pid, double? valor, double t) {
    _integrar(t);
    if (valor == null) return;
    switch (pid) {
      case pidVel:
        _vel = valor;
        if (valor > _velMax) _velMax = valor;
        _atualizarAceleracao(t, valor / 3.6);
        break;
      case pidMaf:
        _maf = valor;
        break;
      case pidMap:
        _mapBar = valor;
        break;
      case pidRpm:
        _rpm = valor;
        break;
      case pidIat:
        _iat = valor;
        break;
      case pidNivel:
        _nivel = valor;
        break;
    }
    _atualizarMarchaLenta();
  }

  void _integrar(double t) {
    final ant = _tUltimo;
    _tUltimo = t;
    if (ant == null || t <= ant) return;
    final dt = t - ant;
    if (_vel != null) _distKm += _vel! * dt / 3600;
    final q = vazaoLh;
    if (q != null) _combL += q * dt / 3600;
    if (_emMarchaLenta) _marchaLentaS += dt;
  }

  void _atualizarMarchaLenta() {
    final parado = _vel != null && _vel! == 0 && _rpm != null && _rpm! > 0;
    if (parado && !_emMarchaLenta) _nMarchaLenta++;
    _emMarchaLenta = parado;
  }

  void _atualizarAceleracao(double t, double v) {
    _velHist.add((t, v));
    _velHist.removeWhere((e) => e.$1 < t - 3);
    // diferença entre a velocidade atual e a de ~1 s atrás
    (double, double)? ref;
    for (final e in _velHist) {
      if (e.$1 <= t - 1) ref = e;
    }
    ref ??= _velHist.first;
    if (t - ref.$1 < 0.2) return;
    final a = (v - ref.$2) / (t - ref.$1);
    _acel = a;
    _acelHist.add((t, a));
    _acelHist.removeWhere((e) => e.$1 < t - 5);

    final lim = p.limiteBruscoMs2;
    if (a > lim && !_emAcel) _nAcel++;
    if (a < -lim && !_emFreio) _nFreio++;
    _emAcel = a > lim / 2;
    _emFreio = a < -lim / 2;
  }

  /// Valores de todos os calculados no instante [t] (s), pelo id de [CalcDef].
  Map<String, double?> valores(double t) {
    _integrar(t);
    final q = vazaoLh;
    final v = _vel;
    final co2gs = q == null ? null : q * p.co2GL / 3600;
    final durH = (t - _t0) / 3600;
    final ps = _mafUsado == null ? null : _mafUsado! * p.psPorGs;
    final consumoViagem = _distKm > 0 ? _combL / _distKm * 100 : 0.0;
    return {
      'inst_fe': (q == null || v == null) ? null : (v > 0 ? q / v * 100 : 0),
      'total_fe': q == null ? null : consumoViagem,
      'fuel_rate': q,
      'inst_co2': (co2gs == null || v == null) ? null : (v > 0 ? co2gs * 3600 / v : 0),
      'total_co2': q == null ? null : _combL * p.co2GL / 1000,
      'co2_flow': co2gs,
      'trip_dist': _distKm,
      'trip_fuel': q == null ? null : _combL,
      'trip_fe': q == null ? null : consumoViagem,
      'trip_dur': durH * 60,
      'hard_brake': _nFreio.toDouble(),
      'hard_accel': _nAcel.toDouble(),
      'idle_count': _nMarchaLenta.toDouble(),
      'idle_sec': _marchaLentaS,
      'max_speed': _velMax,
      'avg_co2': q == null ? null : (_distKm > 0 ? _combL * p.co2GL / _distKm : 0),
      'trip_co2': q == null ? null : _combL * p.co2GL / 1000,
      'trip_cost': q == null ? null : _combL * p.precoLitro,
      'avg_speed': durH > 0 ? _distKm / durH : 0,
      'maf_calc': mafCalculado,
      'accel': _acel,
      'accel_avg': _acelHist.isEmpty
          ? null
          : _acelHist.map((e) => e.$2).reduce((a, b) => a + b) / _acelHist.length,
      'power': ps,
      'torque': (ps == null || _rpm == null || _rpm! <= 0) ? null : ps * p.constanteTorque / _rpm!,
      'fuel_rem': _nivel == null ? null : _nivel! / 100 * p.tanqueL,
    };
  }
}
