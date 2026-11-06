import 'dart:io';

import 'package:path_provider/path_provider.dart' as path_prov;

/// Pasta onde ficam os CSVs das coletas (Scanner e Abastecimento):
/// Android/data/com.example.obdapp/files/coletas_obd
Future<Directory> pastaColetas() async {
  Directory? base;
  if (Platform.isAndroid) base = await path_prov.getExternalStorageDirectory();
  base ??= await path_prov.getApplicationDocumentsDirectory();
  return Directory('${base.path}/coletas_obd');
}

/// CSVs salvos, do mais recente para o mais antigo.
Future<List<File>> listarColetas() async {
  final pasta = await pastaColetas();
  if (!await pasta.exists()) return [];
  final arquivos = pasta
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.csv'))
      .toList()
    ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
  return arquivos;
}
