// Página "Scanner": lista todos os PIDs do modo 01 que o veículo informa como
// suportados, os PIDs calculados (como no OBDLink), deixa o usuário escolher o
// que registrar e grava a coleta em CSV no mesmo formato do OBDLink.
//
// A leitura e a gravação são independentes:
//  - o laço de leitura pede os PIDs ao adaptador o mais rápido possível
//    (os PIDs lentos, como temperaturas e nível, são lidos um por volta);
//  - a gravação acontece numa taxa fixa (1 Hz por padrão, como o OBDLink),
//    sempre com o último valor de cada PID, o GPS e os sensores do celular.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../functions/csv_logger.dart';
import '../functions/elm327.dart';
import '../functions/obd_calculados.dart';
import '../functions/obd_pids.dart';
import '../functions/pastas.dart';
import '../functions/preferencias.dart';
import 'coletasSalvas.dart';
import 'csvViewer.dart';
import 'MapGps.dart';

enum _Etapa { desconectado, conectando, buscando, pronto, coletando, parando }

const _verde = Color(0xFF008355);
const _verdeClaro = Color(0xFF26B07F);
const _chavePids = 'scanner_pids_selecionados';
const _chaveCalc = 'scanner_calculados_selecionados';
const _chaveTaxa = 'scanner_taxa_hz';
const _prefixoParam = 'scanner_param_';
const _taxas = [1, 2, 5, 10];

class PidScanner extends StatefulWidget {
  const PidScanner({super.key});

  @override
  State<PidScanner> createState() => _PidScannerState();
}

class _PidScannerState extends State<PidScanner> {
  late final Elm327 _elm = Elm327(aoRegistrar: _registrar);
  _Etapa _etapa = _Etapa.desconectado;
  String _status = 'Conecte-se ao adaptador OBD-II';
  String? _dispositivo;
  String _versao = '';
  String _protocolo = '';
  String _vin = '';
  final List<String> _log = [];

  List<int> _suportados = [];
  Set<int> _selecionados = {};
  Set<String> _calcSelecionados = {};
  final Map<int, LeituraPid> _ultimos = {};
  Map<String, double?> _ultimosCalc = {};
  final TextEditingController _filtro = TextEditingController();

  // opções
  bool _usarGps = true;
  bool _usarSensores = true;
  bool _primeiraResposta = true;
  int _taxaHz = 1;
  final ParametrosCalculo _param = ParametrosCalculo();

  // coleta
  CsvLogger? _logger;
  Calculadora? _calc;
  Future<void>? _laco;
  bool _parar = false;
  final Stopwatch _cronometro = Stopwatch();
  Timer? _gravacao;
  int _linhas = 0;

  // tela da coleta: trajeto, voltas e o que está sendo lido
  final List<LatLng> _trajeto = [];
  final List<LatLng> _fimVoltas = [];
  final List<double> _temposVolta = [];
  int _volta = 1;
  double _tInicioVolta = 0;
  bool _gpsNaColeta = false;
  List<String> _nomesNaColeta = [];
  int _leituras = 0;
  int _leiturasNoUltimoTick = 0;
  double _tUltimoTick = 0;
  double _taxaPids = 0;
  final List<StreamSubscription<dynamic>> _assinaturas = [];
  Position? _posicao;
  List<double>? _acel, _acelGrav, _giro;
  List<File> _coletas = [];

  bool get _ocupado =>
      _etapa == _Etapa.conectando || _etapa == _Etapa.buscando || _etapa == _Etapa.parando;
  bool get _emColeta => _etapa == _Etapa.coletando || _etapa == _Etapa.parando;

  @override
  void initState() {
    super.initState();
    _carregarPreferencias();
    _listarColetas();
  }

  @override
  void dispose() {
    _parar = true;
    _gravacao?.cancel();
    for (final a in _assinaturas) {
      a.cancel();
    }
    _logger?.fechar();
    _elm.desconectar();
    _filtro.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Utilidades e preferências
  // -------------------------------------------------------------------------
  void _registrar(String linha) {
    _log.add(linha);
    if (_log.length > 200) _log.removeAt(0);
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _carregarPreferencias() async {
    final prefs = await SharedPreferences.getInstance();
    final pids = prefs.getStringList(_chavePids) ?? [];
    final calc = prefs.getStringList(_chaveCalc) ?? [];
    final taxa = prefs.getInt(_chaveTaxa) ?? 1;
    final gps = prefs.getBool(chaveScannerGps) ?? true;
    final sensores = prefs.getBool(chaveScannerSensores) ?? true;
    final rapida = prefs.getBool(chaveScannerRapida) ?? true;
    final m = <String, double>{};
    for (final k in _param.paraMapa().keys) {
      final v = prefs.getDouble('$_prefixoParam$k');
      if (v != null) m[k] = v;
    }
    if (!mounted) return;
    setState(() {
      _selecionados = pids.map((s) => int.parse(s, radix: 16)).toSet();
      _calcSelecionados = calc.toSet();
      _taxaHz = _taxas.contains(taxa) ? taxa : 1;
      _usarGps = gps;
      _usarSensores = sensores;
      _primeiraResposta = rapida;
      _param.carregar(m);
    });
  }

  Future<void> _salvarSelecao() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_chavePids, _selecionados.map(hex2).toList());
    await prefs.setStringList(_chaveCalc, _calcSelecionados.toList());
  }

  Future<void> _salvarOpcoes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_chaveTaxa, _taxaHz);
    await prefs.setBool(chaveScannerGps, _usarGps);
    await prefs.setBool(chaveScannerSensores, _usarSensores);
    await prefs.setBool(chaveScannerRapida, _primeiraResposta);
    for (final e in _param.paraMapa().entries) {
      await prefs.setDouble('$_prefixoParam${e.key}', e.value);
    }
  }

  Future<void> _listarColetas() async {
    final arquivos = await listarColetas();
    if (mounted) setState(() => _coletas = arquivos);
  }

  // -------------------------------------------------------------------------
  // Conexão
  // -------------------------------------------------------------------------
  Future<bool> _permissoesBluetooth() async {
    if (!Platform.isAndroid) return true;
    final r = await [Permission.bluetoothConnect, Permission.bluetoothScan].request();
    final negada = r.values.any((s) => s.isDenied || s.isPermanentlyDenied);
    if (negada) {
      _aviso('Permita o acesso a "Dispositivos próximos" para usar o Bluetooth');
      if (r.values.any((s) => s.isPermanentlyDenied)) await openAppSettings();
      return false;
    }
    return true;
  }

  Future<void> _escolherDispositivo() async {
    if (!await _permissoesBluetooth()) return;
    final bt = FlutterBluetoothSerial.instance;
    if (await bt.isEnabled != true) {
      final ligou = await bt.requestEnable();
      if (ligou != true) {
        _aviso('Ligue o Bluetooth para continuar');
        return;
      }
    }
    final pareados = await bt.getBondedDevices();
    if (!mounted) return;
    if (pareados.isEmpty) {
      _aviso('Nenhum dispositivo pareado. Pareie o adaptador nas configurações do Android.');
      return;
    }
    final escolhido = await showModalBottomSheet<BluetoothDevice>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Dispositivos pareados', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final d in pareados)
              ListTile(
                leading: const Icon(Icons.bluetooth),
                title: Text(d.name ?? 'Sem nome'),
                subtitle: Text(d.address),
                onTap: () => Navigator.of(ctx).pop(d),
              ),
          ],
        ),
      ),
    );
    if (escolhido != null) await _conectar(escolhido);
  }

  Future<void> _conectar(BluetoothDevice d) async {
    setState(() {
      _etapa = _Etapa.conectando;
      _dispositivo = d.name ?? d.address;
      _status = 'Conectando a $_dispositivo...';
    });
    try {
      await _elm.conectar(d.address);
      if (mounted) setState(() => _status = 'Inicializando o adaptador...');
      _versao = await _elm.inicializar();
      await _buscarPids();
    } catch (e) {
      await _elm.desconectar();
      if (!mounted) return;
      setState(() {
        _etapa = _Etapa.desconectado;
        _status = 'Não foi possível conectar: $e';
      });
    }
  }

  Future<void> _buscarPids() async {
    setState(() {
      _etapa = _Etapa.buscando;
      _status = 'Buscando os PIDs suportados (com a ignição ligada)...';
    });
    try {
      final pids = await _elm.descobrirPids(progresso: (m) {
        if (mounted) setState(() => _status = m);
      });
      _protocolo = await _elm.protocolo();
      _vin = await _elm.lerVin();
      if (!mounted) return;
      setState(() {
        _suportados = pids;
        _etapa = _Etapa.pronto;
        _status = pids.isEmpty
            ? 'O veículo não respondeu. Confira se a ignição está ligada e tente de novo.'
            : '${pids.length} PIDs suportados';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _etapa = _elm.conectado ? _Etapa.pronto : _Etapa.desconectado;
        _status = 'Erro ao buscar PIDs: $e';
      });
    }
  }

  Future<void> _desconectar() async {
    await _elm.desconectar();
    setState(() {
      _etapa = _Etapa.desconectado;
      _status = 'Desconectado';
      _suportados = [];
      _ultimos.clear();
    });
  }

  // -------------------------------------------------------------------------
  // Sensores do celular
  // -------------------------------------------------------------------------
  Future<bool> _iniciarGps() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _aviso('Ative a localização para gravar o GPS');
      return false;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      _aviso('Sem permissão de localização: a coleta seguirá sem GPS');
      return false;
    }
    _posicao = null;
    _assinaturas.add(Geolocator.getPositionStream(
      locationSettings:
          const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0),
    ).listen((pos) {
      _posicao = pos;
      final p = LatLng(pos.latitude, pos.longitude);
      // guarda um ponto a cada 2 m para o mapa não ficar pesado
      if (_trajeto.isEmpty || const Distance().as(LengthUnit.Meter, _trajeto.last, p) >= 2) {
        _trajeto.add(p);
      }
    }, onError: (_) {}));
    return true;
  }

  void _iniciarSensores() {
    const periodo = SensorInterval.gameInterval; // ~50 Hz, guarda só o último valor
    _acel = _acelGrav = _giro = null;
    _assinaturas.add(userAccelerometerEventStream(samplingPeriod: periodo)
        .listen((e) => _acel = [e.x, e.y, e.z], onError: (_) {}));
    _assinaturas.add(accelerometerEventStream(samplingPeriod: periodo)
        .listen((e) => _acelGrav = [e.x, e.y, e.z], onError: (_) {}));
    const radParaGrau = 180 / math.pi;
    _assinaturas.add(gyroscopeEventStream(samplingPeriod: periodo).listen(
        (e) => _giro = [e.x * radParaGrau, e.y * radParaGrau, e.z * radParaGrau],
        onError: (_) {}));
  }

  Future<void> _pararSensores() async {
    for (final a in _assinaturas) {
      await a.cancel();
    }
    _assinaturas.clear();
  }

  // -------------------------------------------------------------------------
  // Coleta
  // -------------------------------------------------------------------------
  List<CalcDef> get _calcDisponiveis =>
      tabelaCalculados.where((c) => c.pidsNecessarios(_suportados) != null).toList();

  Future<void> _iniciarColeta() async {
    // pega o que foi mudado na página de Configuração
    await _carregarPreferencias();
    final pidsCsv = _selecionados.where(_suportados.contains).toList()..sort();
    final calcs =
        _calcDisponiveis.where((c) => _calcSelecionados.contains(c.id)).toList();
    if (pidsCsv.isEmpty && calcs.isEmpty) {
      _aviso('Selecione ao menos um PID');
      return;
    }
    // PIDs lidos = os selecionados + os necessários para os calculados
    final lidos = {...pidsCsv};
    for (final c in calcs) {
      lidos.addAll(c.pidsNecessarios(_suportados)!);
    }
    final defsCsv = pidsCsv.map(definicaoDoPid).toList();
    final defsLidos = (lidos.toList()..sort()).map(definicaoDoPid).toList();

    final comGps = _usarGps && await _iniciarGps();
    final comSensores = _usarSensores;
    if (comSensores) _iniciarSensores();

    final cabecalho = [
      'Time',
      for (final d in defsCsv) ...d.colunas,
      for (final c in calcs) c.coluna,
      if (comGps) ...['Latitude (deg)', 'Longitude (deg)', 'Altitude (m)', 'GPS Speed (km/h)', 'GPS Accuracy (m)'],
      if (comSensores) ...[
        'Accel X (m/s²)', 'Accel Y (m/s²)', 'Accel Z (m/s²)',
        'Accel (Grav) X (m/s²)', 'Accel (Grav) Y (m/s²)', 'Accel (Grav) Z (m/s²)',
        'Rotation Rate X (deg/s)', 'Rotation Rate Y (deg/s)', 'Rotation Rate Z (deg/s)',
      ],
      'Lap',
      'PID refresh rate (Hz)',
      'Elapsed time (sec)',
    ];
    try {
      _logger = await CsvLogger.criar(await pastaColetas(),
          'CSVLog_${carimboArquivo(DateTime.now()).replaceAll('-', '')}.csv', cabecalho);
    } catch (e) {
      await _pararSensores();
      _aviso('Não foi possível criar o arquivo: $e');
      return;
    }

    _ultimos.clear();
    _ultimosCalc = {};
    _linhas = 0;
    _trajeto.clear();
    _fimVoltas.clear();
    _temposVolta.clear();
    _volta = 1;
    _tInicioVolta = 0;
    _gpsNaColeta = comGps;
    _nomesNaColeta = [
      for (final d in defsCsv) d.nome,
      for (final c in calcs) c.nome,
    ];
    _leituras = 0;
    _leiturasNoUltimoTick = 0;
    _tUltimoTick = 0;
    _taxaPids = 0;
    _parar = false;
    _cronometro
      ..reset()
      ..start();
    _calc = Calculadora(_param)..iniciar(0);

    setState(() {
      _etapa = _Etapa.coletando;
      _status = 'Lendo ${defsLidos.length} PIDs, gravando a $_taxaHz Hz';
    });

    _laco = _lacoDeLeitura(defsLidos);
    _gravacao = Timer.periodic(Duration(milliseconds: 1000 ~/ _taxaHz),
        (_) => _gravarLinha(defsCsv, calcs, comGps, comSensores));
  }

  /// Lê os PIDs sem parar. Os rápidos são lidos em toda volta, os lentos um por
  /// volta. A primeira volta lê todos, para não começar com colunas vazias.
  Future<void> _lacoDeLeitura(List<PidDef> defs) async {
    final rapidos = defs.where((d) => !d.lento).toList();
    final lentos = defs.where((d) => d.lento).toList();
    var iLento = 0;
    var primeira = true;
    while (!_parar && _elm.conectado) {
      final volta = <PidDef>[
        if (primeira) ...defs else ...rapidos,
        if (!primeira && lentos.isNotEmpty) lentos[iLento++ % lentos.length],
      ];
      if (volta.isEmpty) break;
      primeira = false;
      for (final def in volta) {
        if (_parar) break;
        LeituraPid leitura;
        try {
          leitura = await _elm.ler(def, primeiraResposta: _primeiraResposta);
        } catch (_) {
          leitura = LeituraPid.vazia;
        }
        final t = _cronometro.elapsedMicroseconds / 1e6;
        _leituras++;
        if (!leitura.vazio) _ultimos[def.pid] = leitura;
        _calc?.registrar(def.pid, leitura.valor, t);
      }
    }
    if (!_elm.conectado && !_parar) {
      _aviso('A conexão com o adaptador caiu. A coleta foi encerrada e salva.');
      await _finalizarColeta();
    }
  }

  String _num(double? v) => v == null ? '' : numeroCsv(v);

  /// Campos do CSV de um PID: o último valor lido, ou vazio se ainda não respondeu.
  List<String> _camposPid(PidDef d) {
    final l = _ultimos[d.pid];
    if (l == null || l.vazio) return List.filled(d.colunas.length, '');
    return l.paraCsv(d);
  }

  void _gravarLinha(List<PidDef> defsCsv, List<CalcDef> calcs, bool comGps, bool comSensores) {
    final logger = _logger;
    if (logger == null) return;
    final t = _cronometro.elapsedMicroseconds / 1e6;
    final dt = t - _tUltimoTick;
    if (dt > 0) _taxaPids = (_leituras - _leiturasNoUltimoTick) / dt;
    _leiturasNoUltimoTick = _leituras;
    _tUltimoTick = t;

    final calcValores = _calc?.valores(t) ?? {};
    _ultimosCalc = calcValores;
    final pos = _posicao;
    logger.gravar([
      carimboObdlink(DateTime.now()),
      for (final d in defsCsv) ..._camposPid(d),
      for (final c in calcs) _num(calcValores[c.id]),
      if (comGps) ...[
        _num(pos?.latitude),
        _num(pos?.longitude),
        _num(pos?.altitude),
        _num(pos == null ? null : pos.speed * 3.6),
        _num(pos?.accuracy),
      ],
      if (comSensores) ...[
        for (final v in [_acel, _acelGrav, _giro])
          for (var i = 0; i < 3; i++) _num(v?[i]),
      ],
      '$_volta',
      _num(_taxaPids),
      _num(t),
    ]);
    _linhas = logger.linhas;
    if (mounted) setState(() {});
  }

  /// Botão "Fim da volta": a partir daqui as linhas do CSV ganham o número da
  /// próxima volta (coluna Lap) e o ponto aparece como bandeira no mapa.
  void _marcarFimDaVolta() {
    final t = _cronometro.elapsedMicroseconds / 1e6;
    final duracao = t - _tInicioVolta;
    HapticFeedback.mediumImpact();
    setState(() {
      _temposVolta.add(duracao);
      final pos = _posicao;
      if (pos != null) _fimVoltas.add(LatLng(pos.latitude, pos.longitude));
      _volta++;
      _tInicioVolta = t;
    });
    _aviso('Volta ${_volta - 1} terminou: ${_tempo(Duration(milliseconds: (duracao * 1000).round()))}');
  }

  Future<void> _pararColeta() async {
    setState(() {
      _etapa = _Etapa.parando;
      _status = 'Finalizando a coleta...';
    });
    _parar = true;
    await _laco;
    await _finalizarColeta();
  }

  Future<void> _finalizarColeta() async {
    _gravacao?.cancel();
    _gravacao = null;
    _cronometro.stop();
    await _pararSensores();
    final logger = _logger;
    _logger = null;
    if (logger != null) {
      await logger.fechar();
      if (mounted) {
        final arquivo = logger.arquivo;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text('Coleta salva: ${logger.linhas} linhas'),
            action: SnackBarAction(label: 'Abrir', onPressed: () => abrirCsv(context, arquivo)),
          ));
      }
    }
    await _listarColetas();
    if (!mounted) return;
    setState(() {
      _etapa = _elm.conectado ? _Etapa.pronto : _Etapa.desconectado;
      _status = _elm.conectado ? '${_suportados.length} PIDs suportados' : 'Desconectado';
    });
  }

  // -------------------------------------------------------------------------
  // Configurações
  // -------------------------------------------------------------------------
  Future<void> _abrirConfiguracoes() async {
    final campos = <String, (String, TextEditingController)>{
      'precoLitro': ('Preço do combustível (R\$/L)', TextEditingController()),
      'tanqueL': ('Capacidade do tanque (L)', TextEditingController()),
      'cilindradaL': ('Cilindrada do motor (L)', TextEditingController()),
      'eficienciaVolumetrica': ('Eficiência volumétrica (0 a 1)', TextEditingController()),
      'afr': ('Razão ar-combustível (AFR)', TextEditingController()),
      'densidadeKgL': ('Densidade do combustível (kg/L)', TextEditingController()),
      'co2GL': ('CO2 por litro de combustível (g/L)', TextEditingController()),
      'limiteBruscoMs2': ('Limite de aceleração/frenagem brusca (m/s²)', TextEditingController()),
    };
    final atuais = _param.paraMapa();
    for (final e in campos.entries) {
      e.value.$2.text = numeroCsv(atuais[e.key]!);
    }
    var taxa = _taxaHz;
    final salvar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Configurações da coleta'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('Taxa de gravação')),
                    DropdownButton<int>(
                      value: taxa,
                      items: [
                        for (final t in _taxas) DropdownMenuItem(value: t, child: Text('$t Hz')),
                      ],
                      onChanged: (v) => setD(() => taxa = v ?? 1),
                    ),
                  ],
                ),
                const Text(
                  'Os valores abaixo são usados nos PIDs calculados. Os padrões '
                  'reproduzem o OBDLink (gasolina, AFR 14,7).',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                for (final e in campos.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: e.value.$2,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          isDense: true, labelText: e.value.$1, border: const OutlineInputBorder()),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                final padrao = ParametrosCalculo().paraMapa();
                for (final e in campos.entries) {
                  e.value.$2.text = numeroCsv(padrao[e.key]!);
                }
                setD(() => taxa = 1);
              },
              child: const Text('Padrões'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (salvar == true) {
      final m = <String, double>{};
      for (final e in campos.entries) {
        final v = double.tryParse(e.value.$2.text.replaceAll(',', '.'));
        if (v != null && v > 0) m[e.key] = v;
      }
      setState(() {
        _param.carregar(m);
        _taxaHz = taxa;
      });
      await _salvarOpcoes();
    }
    for (final e in campos.values) {
      e.$2.dispose();
    }
  }

  // -------------------------------------------------------------------------
  // Interface
  // -------------------------------------------------------------------------
  String _tempo(Duration d) {
    String d2(int v) => v.toString().padLeft(2, '0');
    return '${d2(d.inHours)}:${d2(d.inMinutes % 60)}:${d2(d.inSeconds % 60)}';
  }

  Widget _cabecalho() {
    final conectado = _etapa != _Etapa.desconectado && _etapa != _Etapa.conectando;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(conectado ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                    color: conectado ? _verde : Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(conectado ? (_dispositivo ?? 'Adaptador') : 'Sem adaptador',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                if (_ocupado)
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                IconButton(
                  tooltip: 'Configurações da coleta',
                  icon: const Icon(Icons.tune),
                  onPressed: _emColeta ? null : _abrirConfiguracoes,
                ),
              ],
            ),
            Text(_status),
            if (conectado && (_versao.isNotEmpty || _protocolo.isNotEmpty)) ...[
              const SizedBox(height: 4),
              Text('$_versao  ·  $_protocolo', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              if (_vin.isNotEmpty)
                SelectableText('VIN: $_vin', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ],
            if (_emColeta) ...[
              const Divider(),
              Text(
                'Tempo ${_tempo(_cronometro.elapsed)}   ·   $_linhas linhas   ·   '
                '${_taxaPids.toStringAsFixed(1)} PIDs/s',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (_etapa == _Etapa.desconectado)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _verdeClaro),
                    onPressed: _escolherDispositivo,
                    icon: const Icon(Icons.bluetooth_searching),
                    label: const Text('Conectar'),
                  ),
                if (_etapa == _Etapa.pronto) ...[
                  OutlinedButton.icon(
                    onPressed: _buscarPids,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Buscar PIDs de novo'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _desconectar,
                    icon: const Icon(Icons.link_off),
                    label: const Text('Desconectar'),
                  ),
                ],
                TextButton(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Comunicação com o adaptador'),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: SingleChildScrollView(
                          child: SelectableText(_log.isEmpty ? 'Nada ainda' : _log.reversed.join('\n'),
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                        ),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
                      ],
                    ),
                  ),
                  child: const Text('Ver comunicação'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _opcoes() {
    return Column(
      children: [
        SwitchListTile(
          dense: true,
          title: const Text('Gravar GPS do celular'),
          subtitle: const Text('Latitude, longitude, altitude, velocidade e precisão'),
          value: _usarGps,
          onChanged: _emColeta
              ? null
              : (v) {
                  setState(() => _usarGps = v);
                  _salvarOpcoes();
                },
        ),
        SwitchListTile(
          dense: true,
          title: const Text('Gravar acelerômetro e giroscópio do celular'),
          value: _usarSensores,
          onChanged: _emColeta
              ? null
              : (v) {
                  setState(() => _usarSensores = v);
                  _salvarOpcoes();
                },
        ),
        SwitchListTile(
          dense: true,
          title: const Text('Leitura rápida'),
          subtitle: const Text(
              'Aceita a primeira ECU que responder. Desligue se aparecerem muitos valores vazios.'),
          value: _primeiraResposta,
          onChanged: _emColeta
              ? null
              : (v) {
                  setState(() => _primeiraResposta = v);
                  _salvarOpcoes();
                },
        ),
      ],
    );
  }

  bool _combina(String termo, String a, String b) =>
      termo.isEmpty || a.toLowerCase().contains(termo) || b.toLowerCase().contains(termo);

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)),
      );

  Widget _listaPids() {
    final termo = _filtro.text.toLowerCase();
    final visiveis = _suportados.where((p) {
      final d = definicaoDoPid(p);
      return _combina(termo, d.nome, '${d.codigo} ${d.colunas.join(' ')}');
    }).toList();
    final calcs = _calcDisponiveis.where((c) => _combina(termo, c.nome, c.coluna)).toList();
    final nSel = _selecionados.where(_suportados.contains).length +
        _calcDisponiveis.where((c) => _calcSelecionados.contains(c.id)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _filtro,
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Filtrar PIDs',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Text('$nSel selecionados'),
              PopupMenuButton<String>(
                enabled: !_emColeta,
                onSelected: (op) {
                  setState(() {
                    if (op == 'todos') {
                      _selecionados.addAll(visiveis);
                      _calcSelecionados.addAll(calcs.map((c) => c.id));
                    }
                    if (op == 'formula') {
                      _selecionados.addAll(visiveis.where((p) => definicaoDoPid(p).temFormula));
                    }
                    if (op == 'calc') _calcSelecionados.addAll(calcs.map((c) => c.id));
                    if (op == 'nenhum') {
                      _selecionados.removeAll(visiveis);
                      _calcSelecionados.removeAll(calcs.map((c) => c.id));
                    }
                  });
                  _salvarSelecao();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'todos', child: Text('Selecionar tudo')),
                  PopupMenuItem(value: 'formula', child: Text('Selecionar os PIDs com valor físico')),
                  PopupMenuItem(value: 'calc', child: Text('Selecionar todos os calculados')),
                  PopupMenuItem(value: 'nenhum', child: Text('Limpar seleção')),
                ],
              ),
            ],
          ),
        ),
        _titulo('PIDs do veículo (${_suportados.length})'),
        for (final p in visiveis) _itemPid(p),
        if (calcs.isNotEmpty) ...[
          _titulo('Calculados, como no OBDLink (${_calcDisponiveis.length})'),
          for (final c in calcs) _itemCalc(c),
        ],
      ],
    );
  }

  Widget? _valor(String? texto, bool vazio) => texto == null
      ? null
      : Text(texto,
          style: TextStyle(fontWeight: FontWeight.bold, color: vazio ? Colors.grey : _verde));

  Widget _itemPid(int p) {
    final d = definicaoDoPid(p);
    final leitura = _ultimos[p];
    String? valor;
    if (_emColeta) {
      if (leitura == null || leitura.vazio) {
        valor = '—';
      } else if (!d.temFormula) {
        valor = leitura.hex;
      } else {
        final v = leitura.valor;
        valor = v == null ? '—' : '${numeroCsv(double.parse(v.toStringAsFixed(2)))} ${d.unidade}';
      }
    }
    return CheckboxListTile(
      dense: true,
      value: _selecionados.contains(p),
      activeColor: _verde,
      onChanged: _emColeta
          ? null
          : (v) {
              setState(() => v == true ? _selecionados.add(p) : _selecionados.remove(p));
              _salvarSelecao();
            },
      title: Text(d.nome),
      subtitle: Text('${d.codigo}${d.lento ? '  ·  lento' : ''}  ·  ${d.colunas.join(', ')}',
          maxLines: 2, overflow: TextOverflow.ellipsis),
      secondary: _valor(valor, valor == '—'),
    );
  }

  Widget _itemCalc(CalcDef c) {
    String? valor;
    if (_emColeta) {
      final v = _ultimosCalc[c.id];
      valor = v == null ? '—' : '${numeroCsv(double.parse(v.toStringAsFixed(2)))} ${c.unidade}';
    }
    final usa = c.pidsNecessarios(_suportados)!.map((p) => '01 ${hex2(p)}').join(', ');
    return CheckboxListTile(
      dense: true,
      value: _calcSelecionados.contains(c.id),
      activeColor: _verde,
      onChanged: _emColeta
          ? null
          : (v) {
              setState(() => v == true ? _calcSelecionados.add(c.id) : _calcSelecionados.remove(c.id));
              _salvarSelecao();
            },
      title: Text(c.nome),
      subtitle: Text('${c.coluna}${usa.isEmpty ? '' : '  ·  usa $usa'}',
          maxLines: 2, overflow: TextOverflow.ellipsis),
      secondary: _valor(valor, valor == '—'),
    );
  }

  Widget _listaColetas() {
    if (_coletas.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _titulo('Coletas salvas'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('Pasta: ${_coletas.first.parent.path}',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ),
        for (final f in _coletas)
          ItemColeta(arquivo: f, bloqueado: _emColeta, aoApagar: _listarColetas),
      ],
    );
  }

  Widget _telaColeta() {
    final tVolta = _cronometro.elapsedMicroseconds / 1e6 - _tInicioVolta;
    final cinza = TextStyle(fontSize: 12, color: Theme.of(context).hintColor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_gpsNaColeta)
          Card(
            margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: 260,
              child: MapaTrajeto(pontos: List.of(_trajeto), fimDeVolta: List.of(_fimVoltas)),
            ),
          ),
        Card(
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.flag, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Volta $_volta  ·  ${_tempo(Duration(seconds: tVolta.round()))}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ],
                ),
                if (_temposVolta.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Voltas anteriores: ${[
                      for (var i = 0; i < _temposVolta.length; i++)
                        '${i + 1}ª ${_tempo(Duration(seconds: _temposVolta[i].round()))}'
                    ].join('  ·  ')}',
                    style: cinza,
                  ),
                ],
                const SizedBox(height: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _etapa == _Etapa.coletando ? _marcarFimDaVolta : null,
                  icon: const Icon(Icons.flag),
                  label: const Text('Fim da volta', style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Coletando ${_nomesNaColeta.length} itens',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('$_linhas linhas gravadas  ·  $_leituras leituras de PID  ·  '
                    '${_taxaPids.toStringAsFixed(1)} PIDs/s', style: cinza),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final n in _nomesNaColeta)
                      Chip(
                        label: Text(n, style: const TextStyle(fontSize: 12)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final coletando = _etapa == _Etapa.coletando;
    final podeIniciar = _etapa == _Etapa.pronto &&
        (_selecionados.any(_suportados.contains) ||
            _calcDisponiveis.any((c) => _calcSelecionados.contains(c.id)));
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          _cabecalho(),
          // durante a coleta: mapa, voltas e o que está sendo lido (sem os valores,
          // para a tela ficar leve)
          if (_emColeta)
            _telaColeta()
          else if (_suportados.isNotEmpty) ...[
            _opcoes(),
            _listaPids(),
          ],
          if (!_emColeta) _listaColetas(),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: (coletando || podeIniciar || _etapa == _Etapa.parando)
          ? FloatingActionButton.extended(
              heroTag: 'scanner_coleta',
              backgroundColor: _emColeta ? const Color(0xFFB02626) : _verdeClaro,
              onPressed: _etapa == _Etapa.parando ? null : (coletando ? _pararColeta : _iniciarColeta),
              icon: Icon(coletando ? Icons.stop : Icons.fiber_manual_record, color: Colors.white),
              label: Text(
                coletando
                    ? 'Parar coleta'
                    : _etapa == _Etapa.parando
                        ? 'Finalizando...'
                        : 'Iniciar coleta',
                style: const TextStyle(color: Colors.white),
              ),
            )
          : null,
    );
  }
}
