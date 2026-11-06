// Página "Configuração": aparência (tema), veículo, opções da aba Abastecimento,
// opções da aba Scanner, constantes dos PIDs calculados e arquivos.
// Tudo é salvo na hora, sem botão de salvar.
//
// A parte de simulação do OBD foi retirada: ao abrir esta página, a simulação
// é desligada na configuração salva.

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../dataBaseClass/confSimu.dart';
import '../functions/obd_calculados.dart';
import '../functions/obd_pids.dart' show numeroCsv;
import '../functions/pastas.dart';
import '../functions/preferencias.dart';
import '../main.dart';
import 'coletasSalvas.dart';

const _verde = Color(0xFF008355);

/// VIN fictício que vinha na configuração padrão da simulação.
const _vinSimulado = '1GBJC34R9XF017297';

class Confwidget extends StatefulWidget {
  const Confwidget({super.key});

  @override
  State<Confwidget> createState() => _ConfwidgetState();
}

class _ConfwidgetState extends State<Confwidget> {
  Box<Confdata>? _box;
  Confdata? _conf;
  final _nome = TextEditingController();

  // Scanner
  int _taxaHz = 1;
  bool _scannerGps = true;
  bool _scannerSensores = true;
  bool _scannerRapida = true;
  final _param = ParametrosCalculo();
  final Map<String, TextEditingController> _campos = {};
  String _pasta = '';

  static const _rotulos = {
    'precoLitro': 'Preço do combustível (R\$/L)',
    'tanqueL': 'Capacidade do tanque (L)',
    'cilindradaL': 'Cilindrada do motor (L)',
    'eficienciaVolumetrica': 'Eficiência volumétrica (0 a 1)',
    'afr': 'Razão ar-combustível (AFR)',
    'densidadeKgL': 'Densidade do combustível (kg/L)',
    'co2GL': 'CO2 por litro de combustível (g/L)',
    'limiteBruscoMs2': 'Limite de aceleração/frenagem brusca (m/s²)',
  };

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _nome.dispose();
    for (final c in _campos.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _carregar() async {
    final box = Hive.isBoxOpen('conf') ? Hive.box<Confdata>('conf') : await Hive.openBox<Confdata>('conf');
    final conf = box.isNotEmpty ? box.getAt(0) : null;
    if (conf != null && (conf.on || conf.acc)) {
      // simulação e acelerômetro foram retirados do app
      conf.on = false;
      conf.acc = false;
      await box.putAt(0, conf);
    }
    final prefs = await SharedPreferences.getInstance();
    final m = <String, double>{};
    for (final k in _param.paraMapa().keys) {
      final v = prefs.getDouble('$prefixoParamCalculo$k');
      if (v != null) m[k] = v;
    }
    _param.carregar(m);
    final pasta = await pastaColetas();
    if (!mounted) return;
    setState(() {
      _box = box;
      _conf = conf;
      _nome.text = conf?.name ?? '';
      _taxaHz = prefs.getInt(chaveScannerTaxa) ?? 1;
      _scannerGps = prefs.getBool(chaveScannerGps) ?? true;
      _scannerSensores = prefs.getBool(chaveScannerSensores) ?? true;
      _scannerRapida = prefs.getBool(chaveScannerRapida) ?? true;
      for (final e in _param.paraMapa().entries) {
        _campos[e.key] = TextEditingController(text: numeroCsv(e.value));
      }
      _pasta = pasta.path;
    });
  }

  // -------------------------------------------------------------------------
  // Gravação
  // -------------------------------------------------------------------------
  void _aviso(String t) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 2)));

  Future<void> _salvarConf(void Function(Confdata c) mudar) async {
    final c = _conf;
    final box = _box;
    if (c == null || box == null) return;
    setState(() => mudar(c));
    if (!c.obd && !c.gps) {
      // a coleta do Abastecimento precisa de ao menos uma fonte de dados
      setState(() => c.gps = true);
      _aviso('É preciso deixar o OBD-II ou o GPS ligado. O GPS foi mantido.');
    }
    await box.putAt(0, c);
  }

  Future<void> _salvarScanner() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(chaveScannerTaxa, _taxaHz);
    await prefs.setBool(chaveScannerGps, _scannerGps);
    await prefs.setBool(chaveScannerSensores, _scannerSensores);
    await prefs.setBool(chaveScannerRapida, _scannerRapida);
  }

  Future<void> _salvarParametro(String chave, String texto) async {
    final v = double.tryParse(texto.replaceAll(',', '.'));
    if (v == null || v <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('$prefixoParamCalculo$chave', v);
  }

  Future<void> _restaurarParametros() async {
    final prefs = await SharedPreferences.getInstance();
    final padrao = ParametrosCalculo().paraMapa();
    for (final e in padrao.entries) {
      await prefs.remove('$prefixoParamCalculo${e.key}');
      _campos[e.key]?.text = numeroCsv(e.value);
    }
    _aviso('Valores padrão restaurados');
  }

  // -------------------------------------------------------------------------
  // Interface
  // -------------------------------------------------------------------------
  Widget _secao(IconData icone, String titulo, List<Widget> filhos) => Card(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  Icon(icone, color: _verde),
                  const SizedBox(width: 8),
                  Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ]),
              ),
              const SizedBox(height: 4),
              ...filhos,
            ],
          ),
        ),
      );

  Widget _aparencia() {
    final tema = MyApp.of(context).tema;
    return _secao(Icons.palette_outlined, 'Aparência', [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('Sistema'), icon: Icon(Icons.brightness_auto)),
              ButtonSegment(value: ThemeMode.light, label: Text('Claro'), icon: Icon(Icons.light_mode)),
              ButtonSegment(value: ThemeMode.dark, label: Text('Escuro'), icon: Icon(Icons.dark_mode)),
            ],
            selected: {tema},
            onSelectionChanged: (s) {
              MyApp.of(context).definirTema(s.first);
              setState(() {});
            },
          ),
        ),
      ),
    ]);
  }

  Widget _veiculo() {
    final c = _conf;
    final vin = (c == null || c.vin == _vinSimulado) ? '' : c.vin;
    return _secao(Icons.directions_car_outlined, 'Veículo', [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: TextField(
          controller: _nome,
          decoration: const InputDecoration(
            labelText: 'Nome do veículo',
            helperText: 'Usado nos registros quando o VIN não é lido',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => _salvarConf((c) => c.name = v.trim()),
        ),
      ),
      ListTile(
        title: const Text('VIN lido do veículo'),
        subtitle: SelectableText(vin.isEmpty
            ? 'Ainda não lido. Ele é lido ao conectar no Scanner ou numa coleta do Abastecimento com o PID 09 02 marcado.'
            : vin),
        trailing: vin.isEmpty
            ? null
            : IconButton(
                tooltip: 'Esquecer o VIN',
                icon: const Icon(Icons.clear),
                onPressed: () => _salvarConf((c) => c.vin = ''),
              ),
      ),
    ]);
  }

  Widget _abastecimento() {
    final c = _conf;
    if (c == null) return const SizedBox.shrink();
    final intervalo = int.tryParse(c.timereqobd) ?? 1;
    const opcoes = [1, 2, 5, 10];
    return _secao(Icons.local_gas_station_outlined, 'Abastecimento', [
      SwitchListTile(
        title: const Text('Ler o OBD-II'),
        subtitle: const Text('Desligado, a coleta usa só o GPS'),
        value: c.obd,
        onChanged: (v) => _salvarConf((c) => c.obd = v),
      ),
      SwitchListTile(
        title: const Text('Gravar o GPS'),
        value: c.gps,
        onChanged: (v) => _salvarConf((c) => c.gps = v),
      ),
      ListTile(
        title: const Text('Intervalo entre leituras'),
        subtitle: const Text('Com muitos PIDs marcados, o app aumenta o intervalo sozinho'),
        trailing: DropdownButton<int>(
          value: opcoes.contains(intervalo) ? intervalo : 1,
          items: [for (final o in opcoes) DropdownMenuItem(value: o, child: Text('$o s'))],
          onChanged: (v) => _salvarConf((c) => c.timereqobd = '${v ?? 1}'),
        ),
      ),
    ]);
  }

  Widget _scanner() {
    const taxas = [1, 2, 5, 10];
    return _secao(Icons.manage_search, 'Scanner', [
      ListTile(
        title: const Text('Taxa de gravação do CSV'),
        subtitle: const Text('O OBDLink grava 1 linha por segundo'),
        trailing: DropdownButton<int>(
          value: taxas.contains(_taxaHz) ? _taxaHz : 1,
          items: [for (final t in taxas) DropdownMenuItem(value: t, child: Text('$t Hz'))],
          onChanged: (v) {
            setState(() => _taxaHz = v ?? 1);
            _salvarScanner();
          },
        ),
      ),
      SwitchListTile(
        title: const Text('Gravar o GPS do celular'),
        value: _scannerGps,
        onChanged: (v) {
          setState(() => _scannerGps = v);
          _salvarScanner();
        },
      ),
      SwitchListTile(
        title: const Text('Gravar acelerômetro e giroscópio'),
        value: _scannerSensores,
        onChanged: (v) {
          setState(() => _scannerSensores = v);
          _salvarScanner();
        },
      ),
      SwitchListTile(
        title: const Text('Leitura rápida'),
        subtitle: const Text('Aceita a primeira ECU que responder. Desligue se vierem muitos valores vazios.'),
        value: _scannerRapida,
        onChanged: (v) {
          setState(() => _scannerRapida = v);
          _salvarScanner();
        },
      ),
    ]);
  }

  Widget _calculados() {
    return _secao(Icons.functions, 'PIDs calculados (Scanner)', [
      const Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Text('Os padrões reproduzem o OBDLink (gasolina pura, AFR 14,7).',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
      ),
      for (final e in _rotulos.entries)
        if (_campos[e.key] != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: TextField(
              controller: _campos[e.key],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: e.value, border: const OutlineInputBorder(), isDense: true),
              onChanged: (t) => _salvarParametro(e.key, t),
            ),
          ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: _restaurarParametros,
          icon: const Icon(Icons.restore),
          label: const Text('Restaurar padrões'),
        ),
      ),
    ]);
  }

  Widget _arquivos() {
    return _secao(Icons.folder_outlined, 'Arquivos', [
      ListTile(
        title: const Text('Coletas salvas (CSV)'),
        subtitle: Text(_pasta, style: const TextStyle(fontSize: 11)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => abrirColetas(context),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (_box == null) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.only(top: 6, bottom: 24),
      children: [
        _aparencia(),
        _veiculo(),
        _abastecimento(),
        _scanner(),
        _calculados(),
        _arquivos(),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: Text('Fuel Sentinel 1.0.0', style: TextStyle(color: Colors.grey, fontSize: 12))),
        ),
      ],
    );
  }
}
