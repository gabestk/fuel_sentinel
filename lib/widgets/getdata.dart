// Aba "Abastecimento": lista os PIDs usados na conferência do abastecimento,
// deixa marcar quais serão lidos, conecta ao adaptador e abre a coleta
// (página Obddata / Data_Connect).

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:permission_handler/permission_handler.dart';

import '../dataBaseClass/confSimu.dart';
import '../dataBaseClass/pidDiscoveryClass.dart';
import '../functions/obdPlugin.dart';
import '../route/autoroute.dart';

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

  var obd2 = ObdPlugin();
  bool _conectando = false;
  var pid = TextEditingController(text: '');
  var length = TextEditingController(text: ''); // unidade
  var title = TextEditingController(text: '');
  var description = TextEditingController(text: '');
  Box? pidDisc;

  List<dynamic> getresponse = [];

  void turnOBD_OFF() async {
    obd2.connection?.close();
    obd2.connection?.finish();
    obd2.connection?.dispose();
    obd2.disconnect();
    obd2 = ObdPlugin();
  }

  Future<void> init() async {
    pidDisc = await Hive.openBox<pidsDisc>('pidsDisc');
    getresponse = pidDisc!.values.toList();

    // PID 01 2F - nível de combustível
    bool temNivelCombustivel = getresponse.any((e) => e.pid == '01 2F');
    if (!temNivelCombustivel) {
      var pidNivel = pidsDisc(
        pid: '01 2F',
        title: 'nível de combustível',
      );
      pidNivel.unit = '%';
      pidNivel.description = '<int>, ( [0] * 100 ) / 255';
      pidNivel.ativo = true;
      await pidDisc!.add(pidNivel);
      getresponse.add(pidNivel);
    }

    // PID 09 02 - VIN do veículo
    bool temVin = getresponse.any((e) => e.pid == '09 02');
    if (!temVin) {
      var pidVin = pidsDisc(
        pid: '09 02',
        title: 'VIN',
      );
      pidVin.unit = '';
      pidVin.description = '<string>, número de identificação do veículo';
      pidVin.ativo = true;
      await pidDisc!.add(pidVin);
      getresponse.add(pidVin);
    }

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
    pid.dispose();
    length.dispose();
    title.dispose();
    description.dispose();
    super.dispose();
  }

  void showerror(String erro) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(erro)));
  }

  // -------------------------------------------------------------------------
  // PIDs (salvos no Hive, caixa 'pidsDisc')
  // -------------------------------------------------------------------------
  Future<void> insetpid(int index) async {
    var element = pidsDisc(pid: pid.text.trim().toUpperCase(), title: title.text.trim());
    element.unit = length.text.trim();
    element.description = description.text.trim();

    pidDisc = await Hive.openBox<pidsDisc>('pidsDisc');

    if (index != -1) {
      element.ativo = getresponse[index].ativo; // mantém a marcação ao editar
      await pidDisc!.putAt(index, element);
      getresponse[index] = element;
    } else {
      element.ativo = true;
      await pidDisc!.add(element);
      getresponse.add(element);
    }

    setState(() {});
  }

  Future<void> deletpid(int index) async {
    pidDisc = await Hive.openBox<pidsDisc>('pidsDisc');
    await pidDisc!.deleteAt(index);
    getresponse.removeAt(index);
    setState(() {});
  }

  /// Marca ou desmarca um PID e grava no Hive, para a coleta ler a mesma seleção.
  Future<void> alternarPid(int index, bool ativo) async {
    final p = getresponse[index] as pidsDisc;
    p.ativo = ativo;
    setState(() {});
    pidDisc = await Hive.openBox<pidsDisc>('pidsDisc');
    await pidDisc!.putAt(index, p);
  }

  void openedit(TextEditingController p, l, t, d, int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(index == -1 ? 'Adicionar PID' : 'Editar PID'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              TextField(
                controller: p,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'PID',
                  hintText: 'ex.: 01 2F',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: t,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Nome',
                  hintText: 'ex.: nível de combustível',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: l,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Unidade',
                  hintText: 'ex.: %',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: d,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Tipo e fórmula',
                  hintText: '<int>, ( [0] * 100 ) / 255',
                  helperText: '[0] é o 1º byte da resposta, [1] o 2º...',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              pid.text = "";
              length.text = "";
              title.text = "";
              description.text = "";
              Navigator.of(ctx).pop();
            },
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _verde),
            onPressed: () async {
              if (p.text.trim().isEmpty || t.text.trim().isEmpty) {
                showerror("Preencha ao menos o PID e o nome");
                return;
              }
              await insetpid(index);
              pid.text = "";
              length.text = "";
              title.text = "";
              description.text = "";
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Conexão e início da coleta
  // -------------------------------------------------------------------------
  int get _qtdAtivos => getresponse.where((e) => e.ativo == true).length;

  int get _indiceAtivo {
    var indexr = 0;
    for (int i = 0; i < getresponse.length; i++) {
      if (getresponse[i].ativo) indexr = i;
    }
    return indexr;
  }

  Future<void> iniciar() async {
    await init();
    if (_qtdAtivos == 0) {
      showerror("Marque ao menos um PID");
      return;
    }
    final c = confdata;
    if (c == null) {
      showerror("Configuração ainda carregando, tente de novo");
      return;
    }
    if (!mounted) return;
    // simulação ou só GPS: não precisa do adaptador
    if (c.on || !c.obd) {
      context.router.push(Obddata(obd2: obd2, value: _indiceAtivo));
      return;
    }
    final r = await [Permission.bluetoothConnect, Permission.bluetoothScan].request();
    if (r.values.any((s) => s.isDenied || s.isPermanentlyDenied)) {
      showerror('Permita o acesso a "Dispositivos próximos" para usar o Bluetooth');
      return;
    }
    if (!(await obd2.isBluetoothEnable)) {
      await obd2.enableBluetooth;
    }
    turnOBD_OFF();
    await showBluetoothList(obd2);
  }

  Future<void> showBluetoothList(ObdPlugin obd2plugin) async {
    List<BluetoothDevice> devices = await obd2plugin.getPairedDevices;
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

    setState(() => _conectando = true);
    await obd2plugin.getConnection(escolhido, (connection) async {
      if (!mounted) return;
      setState(() => _conectando = false);
      context.router.push(Obddata(obd2: obd2, value: _indiceAtivo));
    }, (message) {
      if (mounted) setState(() => _conectando = false);
      showerror("Não foi possível conectar ao adaptador");
    });
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

  Widget _cabecalho() {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.local_gas_station, color: _verde),
                SizedBox(width: 8),
                Text('Conferência de abastecimento',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Marque os PIDs que serão lidos e toque em "Iniciar". Durante a coleta, '
              'informe o tanque e o quanto foi abastecido. O app compara com o nível '
              'medido pelo OBD-II.',
            ),
            const SizedBox(height: 6),
            Text(_modo(), style: const TextStyle(color: Colors.grey, fontSize: 12)),
            if (_conectando) ...[
              const SizedBox(height: 10),
              const Row(
                children: [
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('Conectando ao adaptador...'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _itemPid(int index) {
    final p = getresponse[index];
    final descricao = (p.description as String).isEmpty ? '' : '  ·  ${p.description}';
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: CheckboxListTile(
        value: p.ativo as bool,
        activeColor: _verde,
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: (v) => alternarPid(index, v ?? false),
        title: Text(p.title as String),
        subtitle: Text('${p.pid}${(p.unit as String).isEmpty ? '' : '  ·  ${p.unit}'}$descricao',
            maxLines: 2, overflow: TextOverflow.ellipsis),
        secondary: PopupMenuButton<String>(
          onSelected: (op) {
            if (op == 'editar') {
              pid.text = p.pid;
              length.text = p.unit;
              title.text = p.title;
              description.text = p.description;
              openedit(pid, length, title, description, index);
            } else if (op == 'apagar') {
              deletpid(index);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'editar', child: Text('Editar')),
            PopupMenuItem(value: 'apagar', child: Text('Apagar')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F7),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 140),
        children: [
          _cabecalho(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text('PIDs (${_qtdAtivos} de ${getresponse.length} marcados)',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                TextButton.icon(
                  onPressed: () => openedit(pid, length, title, description, -1),
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar'),
                ),
              ],
            ),
          ),
          for (int i = 0; i < getresponse.length; i++) _itemPid(i),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: "btninit",
        backgroundColor: _verdeClaro,
        onPressed: _conectando ? null : iniciar,
        icon: const Icon(Icons.play_arrow, color: Colors.white),
        label: const Text('Iniciar', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}
