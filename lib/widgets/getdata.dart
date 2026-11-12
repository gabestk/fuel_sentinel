import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/adapters.dart';

import '../dataBaseClass/confSimu.dart';
import '../dataBaseClass/pidDiscoveryClass.dart';
import '../functions/obdPlugin.dart';
import '../route/autoroute.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class InitBluetooth extends StatefulWidget {
  const InitBluetooth({
    super.key,
  });

  @override
  State<InitBluetooth> createState() => _FloatState();
}

class _FloatState extends State<InitBluetooth> {
  bool aux = true;
  late Box confapp;
  late Confdata confdata;

  var obd2 = ObdPlugin();
  bool help = true;
  var pid = TextEditingController(text: '');
  var length = TextEditingController(text: '');
  var title = TextEditingController(text: '');
  var description = TextEditingController(text: '');
  Box? pidDisc;

  List<dynamic> getresponse = [];

  final FlutterBluetoothSerial _bluetooth = FlutterBluetoothSerial.instance;

  change_flag() {
    setState(() {
      help = !help;
    });
  }

  void turnOBD_OFF() async {
    setState(() {
      obd2.connection?.close();
      obd2.connection?.finish();
      obd2.connection?.dispose();
      obd2.disconnect();
    });
    obd2 = ObdPlugin();
  }

  OverlayEntry? entry;

void init() async {
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
  confdata = confapp.getAt(0);

  setState(() {
    getresponse;
  });
}

  @override
  void initState() {
    init();
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> showerror(String erro) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return TapRegion(
          onTapOutside: (tap) {
            context.router.popForced();
          },
          child: AlertDialog(
            title: const Text(''),
            content: SingleChildScrollView(
              child: ListBody(
                children: <Widget>[
                  Text(erro),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Ok'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> insetpid(int index) async {
    var element = pidsDisc(pid: pid.text, title: title.text);
    element.unit = length.text;
    element.description = description.text;

    pidDisc = await Hive.openBox<pidsDisc>('pidsDisc');

    if (index != -1) {
      pidDisc!.putAt(index, element);
    } else {
      pidDisc!.add(element);
      getresponse.add(element);
    }

    setState(() {
      getresponse;
    });
  }

  Future<void> deletpid(int index) async {
    pidDisc = await Hive.openBox<pidsDisc>('pidsDisc');
    pidDisc!.deleteAt(index);

    getresponse.removeAt(index);

    setState(() {
      getresponse;
    });
  }

  void openedit(TextEditingController p, l, t, d, int index) {
    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: EdgeInsets.zero,
        actions: [
          TextButton(
            onPressed: () {
              pid.text = "";
              length.text = "";
              title.text = "";
              description.text = "";
              context.router.popForced();
            },
            child: Text('Fechar'),
          ),
          TextButton(
            onPressed: () async {
              if (p.text == "" &&
                  l.text == "" &&
                  t.text == "" &&
                  d.text == "") {
                showerror("Um dos campos está vazio");
              } else {
                await insetpid(index).then((onValue) {
                  pid.text = "";
                  length.text = "";
                  title.text = "";
                  description.text = "";
                  context.router.popForced();
                });
              }
            },
            child: Text('Salvar'),
          ),
        ],
        title: Text('Adicionar um PID'),
        content: Container(
          height: 280,
          child: Column(
            children: [
              TextField(
                controller: p,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Pid',
                ),
              ),
              SizedBox(height: 10),
              TextField(
                controller: l,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'unit',
                ),
              ),
              SizedBox(height: 10),
              TextField(
                controller: t,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'title',
                ),
              ),
              SizedBox(height: 10),
              TextField(
                controller: d,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'description',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> showBluetoothList(
      BuildContext context, ObdPlugin obd2plugin) async {
    List<BluetoothDevice> devices = await obd2plugin.getPairedDevices;

    showBottomSheet(
        context: context,
        builder: (BuildContext context) => TapRegion(
            onTapOutside: (tap) {
              context.router.popUntilRouteWithName(Appmain.name);
            },
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.only(top: 0),
              width: double.infinity,
              height: devices.length * 50,
              child: ListView.builder(
                itemCount: devices.length,
                itemBuilder: (context, index) {
                  return SizedBox(
                    height: 50,
                    child: TextButton(
                      onPressed: () {
                        obd2plugin.getConnection(devices[index],
                            (connection) async {
                          // if (!conn2) {

                          change_flag();
                          int indexr = 0;
                          int count = 0;

                          for (int i = 0; i < getresponse.length; i++) {
                            if (getresponse[i].ativo) {
                              count++;
                              indexr = i;
                            }
                          }
                          if (count == 0) {
                            showerror("Selecione um PID");
                          }
                          if (count > 2) {
                            showerror("Só pode ser enviado um comando por vez");
                          } else {
                            context.router
                                .popAndPush(Obddata(obd2: obd2, value: indexr));
                          }
                          //}
                        }, (message) {
                          showerror("Não é possível conectar-se");
                        });

                        //Navigator.pop(context, aux);
                      },
                      child: Center(
                        child: Text(devices[index].name.toString()),
                      ),
                    ),
                  );
                },
              ),
            )));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "btninit2",
            backgroundColor: Color(0xFF26B07F),
            child: const Icon(
              Icons.add,
              color: Colors.white,
            ),
            onPressed: () async {
              openedit(pid, length, title, description, -1);
            },
          ),
          SizedBox(height: 30),
          FloatingActionButton(
            heroTag: "btninit",
            backgroundColor: Color(0xFF26B07F),
            child: const Icon(
              Icons.bluetooth_searching,
              color: Colors.white,
            ),
            onPressed: () async {
              init();
              int indexr = 0;
              int count = 0;

              for (int i = 0; i < getresponse.length; i++) {
                if (getresponse[i].ativo) {
                  count++;
                  indexr = i;
                }
              }
              if (count == 0) {
                showerror("Selecione um PID");
              }
              if (count > 2) {
                showerror("Só pode ser enviado um comando por vez");
              } else if (count == 2) {
                if (confdata.on || !confdata.obd) {
                  context.router.push(Obddata(obd2: obd2, value: indexr));
                } else {
                  if (!(await obd2.isBluetoothEnable)) {
                    await obd2.enableBluetooth;
                  }
                  //_bluetooth.startDiscovery();

                  turnOBD_OFF();

                  showBluetoothList(context, obd2);
                  //obd2 = ObdPlugin();
                }
              }
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            ListView.builder(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                itemCount: getresponse.length,
                itemBuilder: (context, index) {
                  return ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 70,
                        minHeight: 70,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(6),
                            color: Colors.white,
                          ),
                          width: 80,
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Checkbox(
                                    value: getresponse[index].ativo,
                                    onChanged: (newbool) {
                                      setState(() {
                                        getresponse[index].ativo = !getresponse[index].ativo;
                                      });
                                    },
                                  ),
                                  SizedBox(width: 10),
                                  Text("N° $index"),
                                ],
                              ),
                              SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text("PIDs: "),
                                        SizedBox(width: 5),
                                        Text(getresponse[index].pid),
                                      ],
                                    ),
                                    SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Text("Título: "),
                                        SizedBox(width: 5),
                                        Text(getresponse[index].title),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: 15),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  SizedBox(
                                    width: 120,
                                    height: 40,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Color(0xFF26B07F),
                                      ),
                                      onPressed: () {
                                        pid.text = getresponse[index].pid;
                                        length.text = getresponse[index].unit;
                                        title.text = getresponse[index].title;
                                        description.text = getresponse[index].description;
                                        openedit(pid, length, title, description, index);
                                      },
                                      child: Text('Editar', style: TextStyle(color: Colors.white)),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 120,
                                    height: 40,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Color.fromARGB(255, 176, 38, 38),
                                      ),
                                      onPressed: () {
                                        deletpid(index);
                                      },
                                      child: Text('Deletar', style: TextStyle(color: Colors.white)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ));
                })
          ],
        ),
      ),
    );
  }
}
