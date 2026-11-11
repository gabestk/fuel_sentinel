// Aba "Abastecimento": conecta ao adaptador e abre a coleta (página Obddata /
// Data_Connect). Os PIDs são fixos: nível de combustível (01 2F) e VIN (09 02).

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import '../dataBaseClass/confSimu.dart';
import '../functions/elm327.dart';
import '../route/autoroute.dart';
import 'coletasSalvas.dart';

const _verde = Color(0xFF008355);
const _verdeClaro = Color(0xFF26B07F);

class InitBluetooth extends StatefulWidget {
  const InitBluetooth({
    super.key,
  });

  @override
  State<InitBluetooth> createState() => _FloatState();
}

class _FloatState extends State<InitBluetooth> {
  Box? confapp;
  Confdata? confdata;

  final Elm327 _elm = Elm327();
  bool _conectando = false;
  bool _conectado = false;
  String? _adaptador;

  Future<void> init() async {
    confapp = await Hive.openBox<Confdata>('conf');
    if (confapp!.isNotEmpty) confdata = confapp!.getAt(0);

    if (mounted) setState(() {});
  }

  @override
  void initState() {
    init();
    super.initState();
  }

  @override
  void dispose() {
    _elm.desconectar();
    super.dispose();
  }

  void showerror(String erro) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(erro)));
  }

  // -------------------------------------------------------------------------
  // Conexão e início da coleta
  // -------------------------------------------------------------------------

  /// Simulação ou só GPS: a coleta não usa o adaptador.
  bool get _semAdaptador {
    final c = confdata;
    return c != null && (c.on || !c.obd);
  }

  bool get _pronto => _qtdAtivos > 0 && (_semAdaptador || _conectado);

  /// Passo 1: escolhe o adaptador pareado e conecta.
  Future<void> conectar() async {
    final r = await [Permission.bluetoothConnect, Permission.bluetoothScan].request();
    if (r.values.any((s) => s.isDenied || s.isPermanentlyDenied)) {
      showerror('Permita o acesso a "Dispositivos próximos" para usar o Bluetooth');
      if (r.values.any((s) => s.isPermanentlyDenied)) await openAppSettings();
      return;
    }
    final bt = FlutterBluetoothSerial.instance;
    if (!((await bt.isEnabled) ?? false)) {
      await bt.requestEnable();
    }
    if (_elm.conectado) await _elm.desconectar();
    final devices = await bt.getBondedDevices();
    if (!mounted) return;
    if (devices.isEmpty) {
      showerror('Nenhum dispositivo pareado. Pareie o adaptador nas configurações do Android.');
      return;
    }
    final escolhido = await showModalBottomSheet<BluetoothDevice>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Escolha o adaptador OBD-II', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final d in devices)
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
    if (escolhido == null) return;

    setState(() {
      _conectando = true;
      _adaptador = escolhido.name ?? escolhido.address;
    });
    try {
      await _elm.conectar(escolhido.address);
      await _elm.inicializar();
      if (!mounted) return;
      setState(() {
        _conectando = false;
        _conectado = _elm.conectado;
      });
      if (!_conectado) showerror("Não foi possível conectar ao adaptador");
    } catch (_) {
      if (mounted) {
        setState(() {
          _conectando = false;
          _conectado = false;
        });
      }
      showerror("Não foi possível conectar ao adaptador");
    }
  }

  Future<void> desconectar() async {
    await _elm.desconectar();
    if (mounted) setState(() => _conectado = false);
  }

  /// Passo 2: abre a coleta. A conexão continua aberta ao voltar, então dá
  /// para fazer outra coleta sem reconectar.
  Future<void> iniciar() async {
    await init();
    if (_qtdAtivos == 0) {
      showerror("Marque ao menos um PID");
      return;
    }
    if (confdata == null) {
      showerror("Configuração ainda carregando, tente de novo");
      return;
    }
    if (!_semAdaptador && !_conectado) {
      showerror("Conecte ao adaptador primeiro");
      return;
    }
    if (!mounted) return;
    await context.router.push(Obddata(elm: _elm, value: 0));
    if (!mounted) return;
    setState(() => _conectado = _elm.conectado);
  }

  // -------------------------------------------------------------------------
  // Interface
  // -------------------------------------------------------------------------
  String _modo() {
    final c = confdata;
    if (c == null) return '';
    if (!c.obd) return 'Modo: só GPS (OBD desligado nas configurações)';
    if (c.on) return 'Modo: simulação, sem adaptador';
    return 'Modo: OBD-II pelo Bluetooth';
  }

  String _status() {
    if (_semAdaptador) return 'Pronto para iniciar (não usa o adaptador neste modo)';
    if (_conectando) return 'Conectando a ${_adaptador ?? 'adaptador'}...';
    if (_conectado) return 'Conectado. Toque em "Iniciar coleta".';
    return 'Conecte-se ao adaptador OBD-II';
  }

  Widget _cabecalho() {
    final ok = _conectado || _semAdaptador;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                    _semAdaptador
                        ? Icons.local_gas_station
                        : (_conectado ? Icons.bluetooth_connected : Icons.bluetooth_disabled),
                    color: ok ? _verde : Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _semAdaptador
                        ? 'Conferência de abastecimento'
                        : (_conectado ? (_adaptador ?? 'Adaptador') : 'Sem adaptador'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                if (_conectando)
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 6),
            Text(_status()),
            const SizedBox(height: 4),
            Text(_modo(), style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (!_semAdaptador && !_conectado)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _verdeClaro),
                    onPressed: _conectando ? null : conectar,
                    icon: const Icon(Icons.bluetooth_searching),
                    label: const Text('Conectar'),
                  ),
                if (!_semAdaptador && _conectado)
                  OutlinedButton.icon(
                    onPressed: desconectar,
                    icon: const Icon(Icons.link_off),
                    label: const Text('Desconectar'),
                  ),
                TextButton.icon(
                  onPressed: () => abrirColetas(context),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Coletas salvas'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Dados lidos na coleta do abastecimento (fixos).
  Widget _cartaoDados() {
    Widget item(IconData icone, String titulo, String pid) => ListTile(
          dense: true,
          leading: Icon(icone, color: _verde),
          title: Text(titulo),
          trailing: Text(pid, style: const TextStyle(color: Colors.grey)),
        );
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text('Dados lidos do veículo', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          item(Icons.local_gas_station, 'Nível de combustível', '01 2F'),
          item(Icons.badge_outlined, 'VIN (identificação do veículo)', '09 02'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // acompanha mudanças feitas na página de Configuração (OBD/GPS ligados)
    if (Hive.isBoxOpen('conf')) {
      return ValueListenableBuilder<Box<Confdata>>(
        valueListenable: Hive.box<Confdata>('conf').listenable(),
        builder: (context, box, _) {
          if (box.isNotEmpty) confdata = box.getAt(0);
          return _pagina(context);
        },
      );
    }
    return _pagina(context);
  }

  Widget _pagina(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: 140),
        children: [
          _cabecalho(),
          if (confdata?.obd ?? true) _cartaoDados(),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      // como no Scanner: o botão de iniciar só aparece depois de conectar
      floatingActionButton: _pronto && !_conectando
          ? FloatingActionButton.extended(
              heroTag: "btninit",
              backgroundColor: _verdeClaro,
              onPressed: iniciar,
              icon: const Icon(Icons.fiber_manual_record, color: Colors.white),
              label: const Text('Iniciar coleta', style: TextStyle(color: Colors.white)),
            )
          : null,
    );
  }
}
