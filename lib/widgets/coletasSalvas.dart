// Lista dos CSVs salvos, usada no Scanner e no Abastecimento. Tocar num arquivo
// abre a visualização dentro do app. O menu permite abrir em outro aplicativo
// ou apagar.

import 'dart:io';

import 'package:flutter/material.dart';

import '../functions/pastas.dart';
import 'csvViewer.dart';

String _tamanho(File f) {
  final kb = f.lengthSync() / 1024;
  return kb < 1024 ? '${kb.toStringAsFixed(1)} kB' : '${(kb / 1024).toStringAsFixed(1)} MB';
}

String _data(File f) {
  final t = f.lastModifiedSync();
  String d2(int v) => v.toString().padLeft(2, '0');
  return '${d2(t.day)}/${d2(t.month)}/${t.year} ${d2(t.hour)}:${d2(t.minute)}';
}

/// Um item da lista de coletas.
class ItemColeta extends StatelessWidget {
  final File arquivo;
  final bool bloqueado;
  final VoidCallback aoApagar;

  const ItemColeta({super.key, required this.arquivo, required this.aoApagar, this.bloqueado = false});

  Future<void> _apagar(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar coleta?'),
        content: Text(arquivo.uri.pathSegments.last),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apagar')),
        ],
      ),
    );
    if (ok == true) {
      await arquivo.delete();
      aoApagar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.table_chart_outlined, color: Color(0xFF008355)),
      title: Text(arquivo.uri.pathSegments.last),
      subtitle: Text('${_data(arquivo)}  ·  ${_tamanho(arquivo)}'),
      onTap: () => abrirCsv(context, arquivo),
      trailing: PopupMenuButton<String>(
        onSelected: (op) {
          if (op == 'ver') abrirCsv(context, arquivo);
          if (op == 'outro') abrirEmOutroApp(context, arquivo);
          if (op == 'apagar') _apagar(context);
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'ver', child: Text('Abrir no app')),
          const PopupMenuItem(value: 'outro', child: Text('Abrir em outro aplicativo')),
          PopupMenuItem(value: 'apagar', enabled: !bloqueado, child: const Text('Apagar')),
        ],
      ),
    );
  }
}

/// Página com todas as coletas salvas.
class ColetasPage extends StatefulWidget {
  const ColetasPage({super.key});

  @override
  State<ColetasPage> createState() => _ColetasPageState();
}

class _ColetasPageState extends State<ColetasPage> {
  List<File>? _arquivos;
  String _pasta = '';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final pasta = await pastaColetas();
    final a = await listarColetas();
    if (mounted) {
      setState(() {
        _arquivos = a;
        _pasta = pasta.path;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _arquivos;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF008355),
        foregroundColor: Colors.white,
        title: const Text('Coletas salvas'),
      ),
      body: a == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text('Pasta: $_pasta', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ),
                  if (a.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Nenhuma coleta salva ainda.'),
                    ),
                  for (final f in a)
                    Card(
                      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                      child: ItemColeta(arquivo: f, aoApagar: _carregar),
                    ),
                ],
              ),
            ),
    );
  }
}

/// Abre a página de coletas salvas.
Future<void> abrirColetas(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ColetasPage()));
