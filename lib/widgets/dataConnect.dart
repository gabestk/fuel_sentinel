import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:obdapp/widgets/MapGps.dart';
import 'package:obdapp/widgets/acc.dart';
import 'package:crypto/crypto.dart';
import '../dataBaseClass/confSimu.dart';
// import 'package:http/http.dart' as http; // envio para a AWS desativado
// import 'package:aws_signature_v4/aws_signature_v4.dart'; // envio para a AWS desativado
import 'dart:convert';
import '../dataBaseClass/pidDiscoveryClass.dart';
import 'package:math_expressions/math_expressions.dart' as mx;
import '../functions/csv_logger.dart';
import '../functions/pastas.dart';
import '../functions/elm327.dart';
import '../functions/obd_pids.dart';
import 'textWidget.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../dataBaseClass/obdRawData.dart';
import '../functions/security.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart' as path_prov;
import '../functions/InternalDatabase.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';


class Data_Connect extends StatefulWidget {
  /// Conexão com o adaptador, aberta na aba Abastecimento.
  final Elm327 elm;

  final int value;

  Data_Connect({
    super.key,
    required this.value,
    required this.elm,
  });
  static _ConnectState of(BuildContext context) =>
      context.findAncestorStateOfType()!;

  @override
  State<Data_Connect> createState() => _ConnectState();
}

class DeviceService {
  static const _key = 'unique_device_id';

  static Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_key);

    if (deviceId != null) return deviceId;

    final uuid = Uuid();
    final deviceInfo = DeviceInfoPlugin();
    String newId = uuid.v4(); // fallback

    try {
      final androidInfo = await deviceInfo.androidInfo;
      newId = '${androidInfo.id}-${uuid.v4()}';
    } catch (_) {
      try {
        final iosInfo = await deviceInfo.iosInfo;
        newId = '${iosInfo.identifierForVendor}-${uuid.v4()}';
      } catch (_) {
        // keep fallback
      }
    }

    await prefs.setString(_key, newId);
    return newId;
  }
}

class _ConnectState extends State<Data_Connect> {
  // CSV da coleta (mesmo formato do Scanner): uma linha por resposta do OBD
  CsvLogger? _csv;
  bool _criandoCsv = false;
  List<String> _pidsCsv = [];

  String _colunaCsv(ObdRawData r) {
    final nome = r.obddata.title.isEmpty ? 'PID ${r.pid}' : r.obddata.title;
    return r.obddata.unit.isEmpty ? '$nome (${r.pid})' : '$nome (${r.pid}) (${r.obddata.unit})';
  }

  /// Grava as leituras no CSV. O cabeçalho é montado na primeira resposta.
  Future<void> _gravarCsv(List<ObdRawData> leituras) async {
    if (leituras.isEmpty) return;
    if (_csv == null) {
      if (_criandoCsv) return;
      _criandoCsv = true;
      try {
        _pidsCsv = [for (final r in leituras) r.pid];
        _csv = await CsvLogger.criar(
          await pastaColetas(),
          'Abastecimento_${carimboArquivo(DateTime.now()).replaceAll('-', '')}.csv',
          ['Time', for (final r in leituras) _colunaCsv(r), 'Latitude (deg)', 'Longitude (deg)'],
        );
      } catch (e) {
        print('Não foi possível criar o CSV: $e');
        return;
      } finally {
        _criandoCsv = false;
      }
    }
    final porPid = {for (final r in leituras) r.pid: r.obddata.response.trim()};
    final pos = _position;
    _csv?.gravar([
      carimboObdlink(DateTime.now()),
      for (final p in _pidsCsv) porPid[p] ?? (_ehPidVin(p) ? vin.response : ''),
      pos == null ? '' : pos.latitude.toStringAsFixed(7),
      pos == null ? '' : pos.longitude.toStringAsFixed(7),
    ]);
  }

  DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  List data = [];
  double capacidadeTanqueRegistrada = 0;
  double combustivelAbastecidoRegistrado = 0;
  List<double> ultimosNiveis = [];
  List<double> ultimasMediasMoveis = [];
  double mediaMovel = 0.0;
  double mediaMovelAntes = 0.0;
  List<ObdRawData> _responses = [];
  List<Userdata> savejson = [];
  ObdData vin = ObdData(response: '', title: '', unit: '');
  MainAxisAlignment aligm = MainAxisAlignment.center;

  final TextEditingController abastecerController = TextEditingController();
  final TextEditingController tanqueController = TextEditingController();
  final TextEditingController precoController = TextEditingController();
  final TextEditingController valorGastoController = TextEditingController();
  bool isByLiters = true; // true: litros, false: reais
  final ImagePicker _picker = ImagePicker();
  XFile? _imageFile;
  String? _imageHash;

  Future<String> generateImageHash(File imageFile) async {
    List<int> imageBytes = await imageFile.readAsBytes();
    Digest hash = sha256.convert(imageBytes);
    return hash.toString();
  }

  PositionClass? pc;

  bool teste = true;
  List<LatLng> points = [];
  Timer t = Timer(Duration(seconds: 0), () {});
  Timer t2 = Timer(Duration(seconds: 0), () {});

  final _streamSubscriptions = <StreamSubscription<dynamic>>[];
  //UserAccelerometerEvent? _userAccelerometerEvent;
  Duration sensorInterval = SensorInterval.normalInterval;
  //DateTime? _userAccelerometerUpdateTime;
  //int? _userAccelerometerLastInterval;
  static const Duration _ignoreDuration = Duration(milliseconds: 20);
  //UserAcc acc = UserAcc(x: '', y: '', z: '', unit: '');

  String? uniqueid;

  static Position? _position;
  late GeoPoint lastPosition;
  bool isLastPositionInitialized = false;
  double distanceInMeters = 0;
  Timer? _timer;

  Box? confapp;
  late Box pidDisc;
  late pidsDisc pidDiskcong;
  Confdata? confdata;
  var bancoInterno = InternalDatabase();

  static const LocationSettings _locationSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 0,
  );
  StreamSubscription<Position>? _positionStream;

  void updatemap() {
    setState(() {
      points;
    });
  }

  double roundDouble(double value, int places) {
    num mod = pow(10.0, places);
    return ((value * mod).round().toDouble() / mod);
  }

  Future<bool> checkUserConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        return true;
      }
    } on SocketException catch (_) {}
    return false;
  }

  Future<void> _tirarFoto() async {
    final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
    if (photo != null) {
      File imageFile = File(photo.path);
      String imageHash =
          await generateImageHash(imageFile); // Gerando o hash da imagem

      setState(() {
        _imageFile = photo;
        _imageHash = imageHash; // Armazena o hash para salvar no JSON depois
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("Foto capturada com sucesso!"),
            duration: Duration(seconds: 1)),
      );
    }
  }
/*

    
    {
        "PID": "01 05",
        "length": 1,
        "title": "temperatura do liquido de arrefecimento",
        "unit": "°C",
        "description": "<int>, ( [0] - 40 )",
        "status": true
    },
    {
        "PID": "01 0B",
        "length": 1,
        "title": "pressao absoluta do coletor de admissao",
        "unit": "kPa",
        "description": "<int>, [0]",
        "status": true
    },
        {
        "PID": "01 0F",
        "length": 1,
        "title": "temperatura do ar de entrada",
        "unit": "°C",
        "description": "<int>, ( [0] - 40 )",
        "status": true
    },

        {
        "PID": "01 10",
        "length": 2,
        "title": "fluxo de massa de ar (MAF)",
        "unit": "g/s",
        "description": "<double>, (( [0] * 256 ) + [1] ) / 100",
        "status": true
    },
*/

  void getGps(var pc) {
    if (_position != null) {
      GeoPoint actualPosition = GeoPoint(_position!.latitude, _position!.longitude);
      PositionClass pc = PositionClass(lat: _position!.latitude, long: _position!.longitude);
      pc.lat = roundDouble(actualPosition.latitude, 4);
      pc.long = roundDouble(actualPosition.longitude, 4);
      LatLng aux = LatLng(roundDouble(actualPosition.latitude, 4), roundDouble(actualPosition.longitude, 4));

      if (points.length > 1 && points.length < 2) {
        var distance = Distance();
        //create a new distance calculator with Haversine algorithm
        distance = const Distance(calculator: Haversine());

        //create coordinates with NaN or Infinity state to check if the distance is calculated correctly
        final point1 = aux;
        final point2 = points[0];

        var meterDistance = distance.as(LengthUnit.Meter, point1, point2);

        if (meterDistance < 55.00) {
          points.add(aux);
        } else {
          points[0] = aux;
        }
      } else {
        points.add(aux);
      }
    }
  }

  /*void accuser(String x, y, z, unit) {
    if (_userAccelerometerEvent != null) {
      Map accel = {};
      accel['x'] = _userAccelerometerEvent?.x.toStringAsFixed(3);
      accel['y'] = _userAccelerometerEvent?.y.toStringAsFixed(3);
      accel['z'] = _userAccelerometerEvent?.z.toStringAsFixed(3);
      accel['unit'] = 'm/s^2';
      x = accel['x'];
      y = accel['y'];
      z = accel['z'];
      unit = accel['unit'];
    }
  }*/

  void simuobdtime() {
    Timer.periodic(Duration(seconds: int.parse(confdata!.timereqobd)),
        (timer) async {
      _timer = timer;

      print(confdata!.gps);
      print(confdata!.obd);

      if (confdata!.gps) {
        print("oi");
        getGps(pc);
        updatemap();
        setState(() {
          points;
        });
      }

      /*if (confdata!.acc) {
        accuser(acc.x, acc.y, acc.z, acc.unit);
      }*/

      if (confdata!.obd) {
        Random random = Random();
        List<ObdRawData> responses1 = [];
        ObdData help2 = ObdData(
            unit: "g/s",
            title: "fluxo de massa de ar (MAF)",
            response: (random.nextInt(
                        confdata!.mafmax.toInt() - confdata!.mafmin.toInt()) +
                    confdata!.mafmin.toInt())
                .toString());
        ObdRawData help1 = ObdRawData(pid: '01 10', obddata: help2);
        responses1.add(help1);

        help2 = ObdData(
            unit: "Km/h",
            title: "velocidade",
            response: (random.nextInt(confdata!.velomax - confdata!.velomin) +
                    confdata!.velomin)
                .toString());
        help1 = ObdRawData(pid: '01 0D', obddata: help2);
        responses1.add(help1);

        help2 = ObdData(
            unit: "kPa",
            title: "pressao absoluta do coletor de admissao",
            response: (random.nextInt(confdata!.pressmax.toInt() -
                        confdata!.pressmin.toInt()) +
                    confdata!.pressmin.toInt())
                .toString());
        help1 = ObdRawData(pid: '01 0B', obddata: help2);
        responses1.add(help1);

        // print(widget.points.length);

        help2 = ObdData(
            unit: "\u00b0C",
            title: "temperatura do ar de entrada",
            response: (random.nextInt(confdata!.tempaemax.toInt() -
                        confdata!.tempaemin.toInt()) +
                    confdata!.tempaemin.toInt())
                .toString());
        help1 = ObdRawData(pid: '01 0F', obddata: help2);
        responses1.add(help1);

        help2 = ObdData(
            unit: "\u00b0C",
            title: "Temperatura do liquido de arrefecimento",
            response: (random.nextInt(confdata!.templamax.toInt() -
                        confdata!.templamin.toInt()) +
                    confdata!.templamin.toInt())
                .toString());
        help1 = ObdRawData(pid: '01 0F', obddata: help2);
        responses1.add(help1);

        vin = ObdData(unit: "", title: "VIN", response: confdata!.vin);
        help1 = ObdRawData(pid: '09 02', obddata: vin);
        responses1.add(help1);

        help2 = ObdData(
            unit: "%",
            title: "nivel de combustivel",
            response: (random.nextDouble() *
                        (confdata!.pressmax - confdata!.pressmin) +
                    confdata!.pressmin)
                .toString());
        help1 = ObdRawData(pid: '01 2F', obddata: help2);
        responses1.add(help1);

        help2 = ObdData(
            unit: "RPM",
            title: "rotacao",
            response:
                (random.nextDouble() * (confdata!.rpmmax - confdata!.rpmmin) +
                        confdata!.rpmmin)
                    .toString());
        help1 = ObdRawData(pid: '01 0C', obddata: help2);
        responses1.add(help1);

        setState(() {
          _responses = responses1;
        });
        _gravarCsv(responses1);
      }
      // sem envio remoto: não testa a internet a cada amostra (era lento)
      // bool a = await checkUserConnection();

      UserDataProcess save = UserDataProcess(
          processada: false,
          isOnline: false,
          signature: '',
          userdata: _responses,
          //acc: acc,
          //pos: pc,
          time: DateTime.now());
      var signature = await sign(save).then((signature) => signature);
      save.signature = signature.toString();
      UserVehicleRaw vehicledata =
          UserVehicleRaw(userdata: save, vin: vin.response);

      Userdata tobesaved = Userdata(name: uniqueid!, uservehicle: vehicledata);
      savejson.add(tobesaved);

      var userd = tobesaved.toJson();
      data.add(userd);
      if (save.isOnline) {
//Repository.add(tobesaved);
//  bancoInterno.insertObdData(tobesaved);
      } else {
//  bancoInterno.insertObdData(tobesaved);
      }

      await Future.delayed(
        Duration(seconds: int.parse(confdata!.timereqobd)),
      );
    });
  }

  void obdinfo() async {
    // leitura pela comunicação nova (Elm327): cada PID espera a sua resposta
    _lacoObd();
  }

  /// Trata um conjunto de leituras: GPS, VIN, tela, CSV, nível de combustível
  /// e registro assinado. É o mesmo processamento de antes; só mudou a forma
  /// de ler o adaptador.
  Future<void> _processarRespostas(List<ObdRawData> responses1) async {
    if (confdata!.gps) {
      getGps(pc);
      updatemap;
    }

    _registrarVin(responses1);
    setState(() {
      _responses = responses1;
    });
    _gravarCsv(responses1);

    for (var resp in _responses) {
      if (resp.pid == "01 2F" ||
          resp.obddata.title == "nivel de combustivel") {
        double nivel = double.tryParse(resp.obddata.response) ?? 0.0;

        if (ultimosNiveis.length >= 10) {
          ultimosNiveis.removeAt(0);
        }
        ultimosNiveis.add(nivel);
        if (ultimosNiveis.isNotEmpty) {
          mediaMovel =
              ultimosNiveis.reduce((a, b) => a + b) / ultimosNiveis.length;
        }
        if (ultimasMediasMoveis.length >= 10) {
          ultimasMediasMoveis.removeAt(0);
        }
        ultimasMediasMoveis.add(mediaMovel);
      }
    }

    /*if (confdata!.acc) {
      accuser(acc.x, acc.y, acc.z, acc.unit);
    }*/
    // sem envio remoto: não testa a internet a cada amostra (era lento)
    // bool a = await checkUserConnection();

    UserDataProcess save = UserDataProcess(
        processada: false,
        isOnline: false,
        signature: '',
        userdata: _responses,
        //acc: acc,
        // pos: pc,
        time: DateTime.now());
    var signature = await sign(save).then((signature) => signature);
    save.signature = signature.toString();
    UserVehicleRaw vehicledata =
        UserVehicleRaw(userdata: save, vin: confdata!.name);
    if (vin.response != '') {
      vehicledata = UserVehicleRaw(userdata: save, vin: vin.response);
    }

    Userdata tobesaved =
        Userdata(name: uniqueid!, uservehicle: vehicledata);
    savejson.add(tobesaved);
    var userd = tobesaved.toJson();
    data.add(userd);

    if (save.isOnline) {
      //Repository.add(tobesaved);
      //bancoInterno.insertObdData(tobesaved);
    } else {
      //bancoInterno.insertObdData(tobesaved);
    }
  }

/*

var requeridResponse = [
{
"PID": "01 00",
"length": 4,
"title": "PIDs supported [01 - 20]",
"unit": "",
"description": "<bit>",
"status": true
},
{
"PID": "01 20",
"length": 4,
"title": "PIDs supported [21 - 40]",
"unit": "",
"description": "<bit>",
"status": true
},
{
"PID": "01 40",
"length": 4,
"title": "PIDs supported [41 - 60]",
"unit": "",
"description": "<bit>",
"status": true
},
{
"PID": "01 60",
"length": 4,
"title": "PIDs supported [61 - 80]",
"unit": "",
"description": "<bit>",
"status": true
},
{
"PID": "01 80",
"length": 4,
"title": "PIDs supported [81  - A0]",
"unit": "",
"description": "<bit>",
"status": true
},
{
"PID": "01 A0",
"length": 4,
"title": "PIDs supported [A1  - C0]",
"unit": "",
"description": "<bit>",
"status": true
},
];


int count = 0;
int j = 1;
int count = 0;

print(_responses.length);
while (_responses.length < j) {
t = Timer(Duration(seconds: 1), () {
    count += 1;
    print(count);
});
}

_responses[j - 1].timer = count;
j++;
count = 0;

*/

  bool _ehPidVin(String pid) => pid.replaceAll(' ', '').startsWith('0902');

  /// Guarda o VIN lido: mostra na tela, usa nos registros e salva na configuração.
  void _registrarVin(List<ObdRawData> leituras) {
    for (final r in leituras) {
      final v = r.obddata.response.trim();
      if (_ehPidVin(r.pid) && v.length == 17 && v != vin.response) {
        vin = ObdData(unit: '', title: 'VIN', response: v);
        final c = confdata;
        if (c != null && confapp != null && confapp!.isNotEmpty) {
          c.vin = v;
          confapp!.putAt(0, c);
        }
      }
    }
  }

  /// PIDs pedidos ao veículo: os marcados na aba Abastecimento. Sem nenhum
  /// marcado, usa o nível de combustível e o VIN, como antes.
  String _pidsAtivosJson() {
    final ativos = pidDisc.values
        .whereType<pidsDisc>()
        .where((p) => p.ativo)
        .map((p) => p.toJson())
        .toList();
    if (ativos.isNotEmpty) return json.encode(ativos);
    return json.encode([
      {
        "PID": "01 2F",
        "length": 1,
        "title": "nivel de combustivel",
        "unit": "%",
        "description": "<int>, ( [0] * 100 ) / 255",
        "status": true
      },
      {
        "PID": "09 02",
        "length": 1,
        "title": "VIN",
        "unit": "",
        "description": "<string>, número de identificação do veículo",
        "status": true
      }
    ]);
  }

  bool _pararLeitura = false;
  int _leiturasObd = 0;

  /// Valor de um PID a partir da resposta bruta do adaptador. Usa a fórmula da
  /// descrição do PID (ex.: "<int>, ( [0] * 100 ) / 255"), como antes. Se a
  /// fórmula falhar, usa a fórmula padrão da norma SAE J1979 para o modo 01.
  String _valorDoPid(Map p, String bruta) {
    final pid = p["PID"].toString();
    if (_ehPidVin(pid)) return decodificarVin(bruta);
    if (respostaSemDados(bruta)) return '';
    final partes = pid.trim().split(RegExp(r'\s+'));
    if (partes.length < 2) return '';
    final modo = int.tryParse(partes[0], radix: 16);
    final codigo = int.tryParse(partes[1], radix: 16);
    if (modo == null || codigo == null) return '';
    // bytes de dados depois de "4X YY"
    final prefixo = '${hex2(modo + 0x40)}${hex2(codigo)}';
    List<int>? bytes;
    for (final linha in linhasHex(bruta)) {
      final k = linha.indexOf(prefixo);
      if (k >= 0) {
        final dados = linha.substring(k + prefixo.length);
        bytes = [
          for (var n = 0; n + 1 < dados.length; n += 2) int.parse(dados.substring(n, n + 2), radix: 16)
        ];
        break;
      }
    }
    if (bytes == null || bytes.isEmpty) return '';
    final descricao = p["description"].toString();
    if (descricao.contains(", ")) {
      var formula = descricao.split(", ")[1];
      for (var n = 0; n < bytes.length; n++) {
        formula = formula.replaceAll("[$n]", bytes[n].toString());
      }
      try {
        final v = mx.Parser().parse(formula).evaluate(mx.EvaluationType.REAL, mx.ContextModel());
        if (v is num && v.isFinite) return v.toString();
      } catch (_) {}
    }
    final padrao = modo == 1 ? tabelaPids[codigo] : null;
    if (padrao != null && padrao.temFormula) {
      final v = padrao.saidas.first.formula(bytes);
      if (v != null) return v.toString();
    }
    return bytes.map(hex2).join(' ');
  }

  /// Lê os PIDs marcados sem parar, um de cada vez, esperando cada resposta
  /// (comunicação nova, a mesma do Scanner). Um ciclo começa a cada intervalo
  /// da configuração. Se os PIDs demorarem mais que o intervalo, o próximo
  /// ciclo começa logo em seguida.
  Future<void> _lacoObd() async {
    final pedidos = (json.decode(_pidsAtivosJson()) as List).cast<Map>();
    final intervalo = Duration(seconds: int.tryParse(confdata!.timereqobd) ?? 1);
    final elm = widget.elm;
    while (mounted && !_pararLeitura && elm.conectado) {
      final inicio = DateTime.now();
      final leituras = <ObdRawData>[];
      for (final p in pedidos) {
        if (_pararLeitura || !elm.conectado) break;
        final pid = p["PID"].toString();
        // o VIN não muda: depois de lido, não é pedido de novo
        if (_ehPidVin(pid) && vin.response.isNotEmpty) {
          leituras.add(ObdRawData(pid: pid, obddata: ObdData(unit: '', title: p["title"].toString(), response: vin.response)));
          continue;
        }
        String bruta;
        try {
          bruta = await elm.enviar(pid.replaceAll(' ', ''),
              timeout: Duration(seconds: _ehPidVin(pid) ? 5 : 2));
        } catch (_) {
          bruta = '';
        }
        _leiturasObd++;
        leituras.add(ObdRawData(
          pid: pid,
          obddata: ObdData(
            unit: p["unit"].toString(),
            title: p["title"].toString(),
            response: _valorDoPid(p, bruta),
          ),
        ));
      }
      if (!mounted || _pararLeitura) break;
      if (leituras.isNotEmpty) await _processarRespostas(leituras);
      final resta = intervalo - DateTime.now().difference(inicio);
      if (resta > Duration.zero) await Future<void>.delayed(resta);
    }
  }

  void getinfo() async {
    print(confdata!.obd);

    if (confdata!.obd) {
      if (confdata!.on) {
        print("oi1");
        simuobdtime();
      } else {
        print("oi2");
        obdinfo();
      }
    } else {
      print("oi3");
      simuobdtime();
    }
  }

  Future<void> init() async {
    if (Platform.isIOS) {
      var iosDeviceInfo = await deviceInfo.iosInfo;
      uniqueid = iosDeviceInfo.identifierForVendor;
    } else if (Platform.isAndroid) {
      var androidDeviceInfo = await deviceInfo.androidInfo;
      uniqueid = androidDeviceInfo.id;
    }
    confapp = await Hive.openBox<Confdata>('conf');

    if (confapp == null) {
      var bancoInterno = InternalDatabase();
      bancoInterno.init();

      var a = Confdata(
          rpmmin: 750,
          rpmmax: 10000,
          velomin: 0,
          velomax: 120,
          templamin: 90,
          templamax: 104.4,
          pressmin: 14.7,
          pressmax: 101,
          vin: '1GBJC34R9XF017297',
          tempaemin: 30,
          tempaemax: 70,
          mafmin: 400,
          mafmax: 1000,
          percentmin: 50,
          percentmax: 70,
          responseobddata: [],
          name: 'Appteste',
          timereqobd: '1',
          on: false);
      confdata = a;
    } else {
      confdata = confapp!.getAt(0);
      setState(() {
        confdata;
      });
    }

    pidDisc = await Hive.openBox<pidsDisc>('pidsDisc');
    pidDiskcong = pidDisc.getAt(widget.value);
  }

  // ---- Envio para a AWS desativado: por enquanto os dados ficam só no celular ----
  // Future<void> enviarListaJsonParaGateway(List<Map<String, dynamic>> jsonList) async {
  //   final url = Uri.parse('https://n7trtk1sok.execute-api.us-east-1.amazonaws.com/saveTimestream');
  //
  //   const int tamanhoBloco = 100;
  //
  //   for (var i = 0; i < jsonList.length; i += tamanhoBloco) {
  //     // pega o bloco de no máximo 100 itens
  //     final bloco = jsonList.sublist(
  //       i,
  //       i + tamanhoBloco > jsonList.length ? jsonList.length : i + tamanhoBloco,
  //     );
  //
  //     try {
  //       final response = await http.post(
  //         url,
  //         headers: {'Content-Type': 'application/json'},
  //         body: json.encode(bloco),
  //       );
  //
  //       if (response.statusCode == 200) {
  //         print('Bloco ${i ~/ tamanhoBloco + 1} enviado com sucesso!');
  //       } else {
  //         print('Erro ao enviar bloco ${i ~/ tamanhoBloco + 1}: ${response.statusCode}');
  //         print(response.body);
  //       }
  //     } catch (e) {
  //       print('Erro ao conectar no bloco ${i ~/ tamanhoBloco + 1}: $e');
  //     }
  //   }
  // }

  @override
  void initState() {
    super.initState();
    init().then((value) {
      /*if (confdata!.acc) {
        _streamSubscriptions.add(
          userAccelerometerEventStream(samplingPeriod: sensorInterval).listen(
            (UserAccelerometerEvent event) {
              final now = event.timestamp;
              setState(() {
                _userAccelerometerEvent = event;
                if (_userAccelerometerUpdateTime != null) {
                  final interval =
                      now.difference(_userAccelerometerUpdateTime!);
                  if (interval > _ignoreDuration) {
                    _userAccelerometerLastInterval = interval.inMilliseconds;
                  }
                }
              });
              _userAccelerometerUpdateTime = now;
            },
            onError: (e) {
              showDialog(
                  context: context,
                  builder: (context) {
                    return const AlertDialog(
                      title: Text("Sensor Not Found"),
                      content: Text(
                          "It seems that your device doesn't support User Accelerometer Sensor"),
                    );
                  });
            },
            cancelOnError: true,
          ),
        );
      }*/

      if (confdata!.gps) {
        _positionStream =
            Geolocator.getPositionStream(locationSettings: _locationSettings)
                .listen((Position? position) {
          //print(position == null
          //    ? 'Unknown'
          //    : '${position.latitude.toString()}, ${position.longitude.toString()}');
          _position = position;
        });
      }

      getinfo();
    });
  }

  @override
  void dispose() async {
    super.dispose();
    // fecha o CSV antes de qualquer outra coisa, para não perder dados
    final csv = _csv;
    _csv = null;
    await csv?.fechar();
    for (final subscription in _streamSubscriptions) {
      subscription.cancel();
    }

    // para o laço de leitura; a conexão continua aberta (é da aba Abastecimento),
    // assim dá para fazer outra coleta sem conectar de novo
    _pararLeitura = true;

    final diretorioUsuario = await path_prov.getExternalStorageDirectory();

    File file = File(
        diretorioUsuario!.path + "/" + carimboArquivo(DateTime.now()) + '.json');

    file.create();
    const JsonEncoder encoder = JsonEncoder();

    final String jsonString = encoder.convert(data);
    file.writeAsStringSync(jsonString);
    if (_positionStream != null) {
      _positionStream!.cancel();
    }
    points.clear();
    if (_timer != null) {
      _timer!.cancel();
    }

    t.cancel();
    t2.cancel();
  }

  /// Confere o abastecimento com o nível medido e salva os dados no celular.
  Future<void> _salvarAbastecimento() async {
    final diretorioUsuario =
        await path_prov
            .getExternalStorageDirectory();
    File file = File(
        "${diretorioUsuario!.path}/medicao_${carimboArquivo(DateTime.now())}.json");
    // o arquivo só é criado ao gravar, para não deixar arquivos vazios
    double capacidadeTanque =
        capacidadeTanqueRegistrada;
    double combustivelAbastecido =
        combustivelAbastecidoRegistrado;
    double precoLitroReais = 0.0;
    double totalAbastecidoReais = 0.0;

    // Se a entrada foi por reais, calcula litros a partir do preço e do valor gasto
    if (!isByLiters) {
      precoLitroReais = double.tryParse(precoController.text) ?? 0.0;
      totalAbastecidoReais = double.tryParse(valorGastoController.text) ?? 0.0;
      if (precoLitroReais > 0 && totalAbastecidoReais > 0) {
        combustivelAbastecido = totalAbastecidoReais / precoLitroReais;
        // atualiza registro local também
        combustivelAbastecidoRegistrado = combustivelAbastecido;
      }
    }

    if (capacidadeTanque <= 0 || combustivelAbastecido <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
              "Registre a capacidade do tanque e o abastecimento primeiro!"),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    double percentualAbastecido =
        (combustivelAbastecido /
                capacidadeTanque) *
            100;

    // Obtém o nível de combustível exibido pelo OBD
    double nivelMedidoOBD = mediaMovel;

    // Calcula o percentual esperado após abastecimento
    double percentualEsperado =
        mediaMovelAntes +
            ((combustivelAbastecido /
                    capacidadeTanque) *
                100);

    // Calcula a diferença absoluta
    double diferenca = (nivelMedidoOBD -
            percentualEsperado)
        .abs();

    // Define um limite de tolerância (exemplo: 2%)
    double limiteTolerancia = 2.0;

    // Verifica se há discrepância significativa

    Position? posicaoAtual;
    try {
      posicaoAtual = await Geolocator
          .getCurrentPosition(
        // ignore: deprecated_member_use
        desiredAccuracy:
            LocationAccuracy.high,
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
              "Erro ao obter localização: $e"),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    String deviceId = await DeviceService.getDeviceId();
    double latitude = posicaoAtual.latitude;
    double longitude = posicaoAtual.longitude;

    String? imageHash;
    if (_imageFile != null) {File imageFile = File(_imageFile!.path); imageHash = await generateImageHash(imageFile);
    }

    if (diferenca > limiteTolerancia) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            "🚨 Atenção: abastecimento não concluído, envie os dados novamente em alguns segundos",
            style: TextStyle(
                color: Colors.red),
          ),
          duration: Duration(seconds: 5),
        ),
      );
      return;
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            "✅ Medição consistente com abastecimento informado.",
            style: TextStyle(
                color: Colors.green),
          ),
          duration: Duration(seconds: 3),
        ),
      );
      List<Map<String, dynamic>>
          jsonData = savejson.map((data) {
        var originalData = data.toJson();
        originalData["timestamp"] = DateTime.now().toUtc().toIso8601String();
        originalData["total_tanque_litros"] = capacidadeTanque.toStringAsFixed(2);
        originalData["total_abastecido_litros"] = combustivelAbastecido.toStringAsFixed(2);
        // Campos adicionais quando informado por reais
        if (!isByLiters) {
          originalData["preco_litro_reais"] = precoLitroReais.toStringAsFixed(2);
          originalData["total_abastecido_reais"] = totalAbastecidoReais.toStringAsFixed(2);
        }
        originalData["percentual_abastecido"] = percentualAbastecido.toStringAsFixed(2);
        originalData["latitude"] = latitude.toStringAsFixed(7);
        originalData["longitude"] = longitude.toStringAsFixed(7);
        originalData["imagem_hash"] = imageHash ?? "Sem imagem";
        originalData["media_movel_nivel_combustivel_antes"] = mediaMovelAntes.toStringAsFixed(2);
        originalData["media_movel_nivel_combustivel"] = mediaMovel.toStringAsFixed(2);
        originalData["diferenca_percentual_detectada"] = (ultimosNiveis.length >= 10 ? diferenca : 0.0).toStringAsFixed(2);
        originalData["device_id"] = deviceId;
        return originalData;
      }).toList();
      if (jsonData.isNotEmpty) {
        // Envio para a AWS desativado: salva só no celular
        // await enviarListaJsonParaGateway(
        //     jsonData);

        const JsonEncoder encoder =
            JsonEncoder.withIndent(" ");
        final String jsonString =
            encoder.convert(jsonData);
        await file
            .writeAsString(jsonString);

        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text(
                "Dados salvos com sucesso!"),
            duration:
                Duration(seconds: 1),
          ),
        );
      }
    }
  }

  // -------------------------------------------------------------------------
  // Registro do tanque e do abastecimento
  // -------------------------------------------------------------------------
  static const _verde = Color(0xFF008355);
  static const double _tolerancia = 2.0; // pontos percentuais

  void _aviso(String texto, {Color? cor, int segundos = 2}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(texto, style: cor == null ? null : TextStyle(color: cor)),
        duration: Duration(seconds: segundos),
      ));
  }

  double? _numero(String texto) => double.tryParse(texto.replaceAll(',', '.'));

  void _registrarTanque() {
    final v = _numero(tanqueController.text) ?? 0;
    setState(() => capacidadeTanqueRegistrada = v);
    _aviso(v > 0 ? 'Capacidade do tanque registrada!' : 'Informe uma capacidade válida');
  }

  void _registrarLitros() {
    final v = _numero(abastecerController.text) ?? 0;
    if (v <= 0) {
      _aviso('Informe a quantidade em litros');
      return;
    }
    setState(() {
      combustivelAbastecidoRegistrado = v;
      mediaMovelAntes = mediaMovel;
    });
    _aviso('Quantidade abastecida registrada!');
  }

  void _registrarReais() {
    final preco = _numero(precoController.text) ?? 0;
    final gasto = _numero(valorGastoController.text) ?? 0;
    if (preco <= 0 || gasto <= 0) {
      _aviso('Informe preço e valor gasto válidos');
      return;
    }
    final litros = gasto / preco;
    setState(() {
      combustivelAbastecidoRegistrado = litros;
      mediaMovelAntes = mediaMovel;
    });
    _aviso('Equivalente a ${litros.toStringAsFixed(2)} L registrado.');
  }

  // -------------------------------------------------------------------------
  // Interface
  // -------------------------------------------------------------------------
  Widget _cartao(String titulo, IconData icone, List<Widget> filhos) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icone, color: _verde, size: 20),
                const SizedBox(width: 8),
                Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 10),
            ...filhos,
          ],
        ),
      ),
    );
  }

  Widget _linha(String rotulo, String valor, {bool destaque = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(rotulo, style: const TextStyle(color: Colors.black87))),
          Text(valor,
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: destaque ? _verde : Colors.black87)),
        ],
      ),
    );
  }

  String _modo() {
    final c = confdata;
    if (c == null) return 'Carregando...';
    if (!c.obd) return 'Só GPS (OBD desligado nas configurações)';
    if (c.on) return 'Simulação (dados gerados pelo app)';
    return 'OBD-II';
  }

  Widget _cartaoStatus() {
    final conectado = widget.elm.conectado;
    return _cartao('Coleta', Icons.sensors, [
      _linha('Modo', _modo()),
      if (confdata?.obd == true && confdata?.on == false)
        _linha('Adaptador', conectado ? 'conectado' : 'desconectado', destaque: conectado),
      _linha('Leituras registradas', '${data.length}'),
      if (vin.response.isNotEmpty) _linha('VIN', vin.response),
    ]);
  }

  Widget _cartaoNivel() {
    final atual = ultimosNiveis.isNotEmpty ? ultimosNiveis.last : null;
    final litros = capacidadeTanqueRegistrada > 0 ? mediaMovel / 100 * capacidadeTanqueRegistrada : null;
    return _cartao('Nível de combustível', Icons.local_gas_station, [
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(atual == null ? '—' : atual.toStringAsFixed(1),
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: _verde)),
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text('%', style: TextStyle(fontSize: 18)),
          ),
          const Spacer(),
          if (litros != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('≈ ${litros.toStringAsFixed(1)} L no tanque'),
            ),
        ],
      ),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: (mediaMovel / 100).clamp(0.0, 1.0),
          minHeight: 10,
          color: _verde,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        atual == null
            ? 'Aguardando a primeira leitura do nível...'
            : 'Média móvel das últimas ${ultimosNiveis.length} leituras: ${mediaMovel.toStringAsFixed(1)} %',
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      ),
    ]);
  }

  Widget _cartaoLeituras() {
    return _cartao('Leituras do OBD', Icons.list_alt, [
      if (_responses.isEmpty)
        const Text('Nenhuma leitura ainda', style: TextStyle(color: Colors.grey))
      else
        for (final r in _responses)
          _linha(
            r.obddata.title.isEmpty ? 'PID ${r.pid}' : r.obddata.title,
            r.obddata.response.isEmpty ? '—' : '${r.obddata.response} ${r.obddata.unit}'.trim(),
          ),
    ]);
  }

  Widget _cartaoGps() {
    return _cartao('Trajeto (GPS)', Icons.map_outlined, [
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(height: 200, child: MapWidget(points: points)),
      ),
    ]);
  }

  Widget _campo(TextEditingController c, String rotulo, VoidCallback aoConfirmar) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: c,
            decoration: InputDecoration(labelText: rotulo, border: const OutlineInputBorder(), isDense: true),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onSubmitted: (_) => aoConfirmar(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          style: IconButton.styleFrom(backgroundColor: _verde),
          onPressed: aoConfirmar,
          icon: const Icon(Icons.check, color: Colors.white),
        ),
      ],
    );
  }

  Widget _verificacao() {
    if (capacidadeTanqueRegistrada <= 0 || combustivelAbastecidoRegistrado <= 0) {
      return const Text(
        'Registre a capacidade do tanque e o abastecimento para conferir com o nível medido.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      );
    }
    final esperado =
        mediaMovelAntes + combustivelAbastecidoRegistrado / capacidadeTanqueRegistrada * 100;
    final diferenca = (mediaMovel - esperado).abs();
    final ok = diferenca <= _tolerancia;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ok
            ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5)
            : Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _linha('Nível antes do abastecimento', '${mediaMovelAntes.toStringAsFixed(1)} %'),
          _linha('Abastecido', '${combustivelAbastecidoRegistrado.toStringAsFixed(2)} L'),
          _linha('Nível esperado', '${esperado.toStringAsFixed(1)} %'),
          _linha('Nível medido agora', '${mediaMovel.toStringAsFixed(1)} %'),
          const Divider(),
          Row(
            children: [
              Icon(ok ? Icons.check_circle : Icons.warning_amber_rounded,
                  color: ok ? _verde : Colors.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ok
                      ? 'Consistente: diferença de ${diferenca.toStringAsFixed(1)} p.p.'
                      : 'Diferença de ${diferenca.toStringAsFixed(1)} p.p. (limite ${_tolerancia.toStringAsFixed(0)} p.p.). '
                          'Aguarde o nível estabilizar.',
                  style: TextStyle(color: ok ? _verde : Colors.red, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cartaoAbastecimento() {
    return _cartao('Abastecimento', Icons.water_drop_outlined, [
      _campo(tanqueController, 'Capacidade total do tanque (L)', _registrarTanque),
      const SizedBox(height: 12),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: true, label: Text('Por litros'), icon: Icon(Icons.local_drink_outlined)),
          ButtonSegment(value: false, label: Text('Por reais'), icon: Icon(Icons.attach_money)),
        ],
        selected: {isByLiters},
        onSelectionChanged: (s) => setState(() => isByLiters = s.first),
      ),
      const SizedBox(height: 12),
      if (isByLiters)
        _campo(abastecerController, 'Quantidade abastecida (L)', _registrarLitros)
      else ...[
        TextField(
          controller: precoController,
          decoration: const InputDecoration(
              labelText: 'Preço do litro (R\$)', border: OutlineInputBorder(), isDense: true),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 8),
        _campo(valorGastoController, 'Valor gasto (R\$)', _registrarReais),
      ],
      const SizedBox(height: 12),
      _verificacao(),
      const SizedBox(height: 12),
      // foto da bomba, centralizada
      Center(
        child: Column(
          children: [
            if (_imageFile != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(_imageFile!.path), height: 120, fit: BoxFit.cover),
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton.icon(
              onPressed: _tirarFoto,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(_imageFile == null ? 'Tirar foto da bomba' : 'Trocar foto'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: _verde, padding: const EdgeInsets.all(14)),
          onPressed: _salvarAbastecimento,
          icon: const Icon(Icons.save_alt),
          label: const Text('Salvar dados do abastecimento'),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ListView(
        padding: const EdgeInsets.only(top: 6, bottom: 96),
        children: [
          _cartaoStatus(),
          if (confdata?.obd ?? false) ...[
            _cartaoNivel(),
            _cartaoLeituras(),
          ],
          if (confdata?.gps ?? false) _cartaoGps(),
          if (confdata?.obd ?? false) _cartaoAbastecimento(),
        ],
      ),
    );
  }
}
