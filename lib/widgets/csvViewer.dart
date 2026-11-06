// Visualização de um CSV dentro do app: resumo, gráfico de uma coluna ao longo
// do tempo e a tabela completa. Também abre o arquivo em outro aplicativo.

import 'dart:io';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../functions/csv_leitor.dart';

const _verde = Color(0xFF008355);

/// Abre o arquivo no aplicativo do celular associado a CSV (Planilhas, Excel...).
Future<void> abrirEmOutroApp(BuildContext context, File arquivo) async {
  final r = await OpenFilex.open(arquivo.path, type: 'text/csv');
  if (r.type != ResultType.done && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.type == ResultType.noAppToOpen
            ? 'Nenhum aplicativo instalado abre CSV. Instale o Planilhas Google ou o Excel.'
            : 'Não foi possível abrir: ${r.message}')));
  }
}

(TabelaCsv, List<double>, List<int>) _lerArquivo(String caminho) {
  final t = lerCsv(File(caminho).readAsStringSync());
  return (t, t.tempos(), t.colunasNumericas());
}

/// Abre a página de visualização do CSV.
Future<void> abrirCsv(BuildContext context, File arquivo) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CsvViewer(arquivo: arquivo)));

class CsvViewer extends StatefulWidget {
  final File arquivo;
  const CsvViewer({super.key, required this.arquivo});

  @override
  State<CsvViewer> createState() => _CsvViewerState();
}

class _Ponto {
  final double t;
  final double v;
  const _Ponto(this.t, this.v);
}

class _CsvViewerState extends State<CsvViewer> {
  TabelaCsv? _tabela;
  List<double> _tempos = [];
  List<int> _numericas = [];
  int? _coluna;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      // a leitura e a interpretação rodam fora da interface, para não travar com arquivos grandes
      final r = await compute(_lerArquivo, widget.arquivo.path);
      if (!mounted) return;
      setState(() {
        _tabela = r.$1;
        _tempos = r.$2;
        _numericas = r.$3.where((c) => !_ehColunaDeTempo(r.$1.colunas[c])).toList();
        _coluna = _escolherColunaInicial(r.$1);
      });
    } catch (e) {
      if (mounted) setState(() => _erro = '$e');
    }
  }

  bool _ehColunaDeTempo(String c) => c == 'Time' || c == 'Elapsed time (sec)' || c == 'Tempo (s)';

  int? _escolherColunaInicial(TabelaCsv t) {
    for (final preferida in ['Vehicle speed (km/h)', 'Engine RPM (RPM)', 'Fuel level input (%)']) {
      final i = t.colunas.indexOf(preferida);
      if (i >= 0 && _numericas.contains(i)) return i;
    }
    return _numericas.isEmpty ? null : _numericas.first;
  }

  String _duracao() {
    if (_tempos.isEmpty) return '-';
    final s = _tempos.last.round();
    return '${s ~/ 60} min ${s % 60} s';
  }

  Widget _resumo(TabelaCsv t) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 24,
          runSpacing: 8,
          children: [
            _info('Linhas', '${t.nLinhas}'),
            _info('Colunas', '${t.colunas.length}'),
            _info('Duração', _duracao()),
            _info('Tamanho', '${(widget.arquivo.lengthSync() / 1024).toStringAsFixed(1)} kB'),
          ],
        ),
      ),
    );
  }

  Widget _info(String rotulo, String valor) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rotulo, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(valor, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      );

  Widget _grafico(TabelaCsv t) {
    final c = _coluna;
    if (c == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Nenhuma coluna numérica para mostrar no gráfico.'),
      );
    }
    final pontos = <_Ponto>[
      for (var i = 0; i < t.nLinhas; i++)
        if (t.numero(i, c) != null) _Ponto(_tempos[i], t.numero(i, c)!)
    ];
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Column(
          children: [
            DropdownButton<int>(
              isExpanded: true,
              value: c,
              items: [
                for (final i in _numericas)
                  DropdownMenuItem(value: i, child: Text(t.colunas[i], overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _coluna = v),
            ),
            SizedBox(
              height: 240,
              child: SfCartesianChart(
                primaryXAxis: NumericAxis(title: AxisTitle(text: 'Tempo (s)')),
                series: <CartesianSeries>[
                  LineSeries<_Ponto, double>(
                    dataSource: pontos,
                    xValueMapper: (p, _) => p.t,
                    yValueMapper: (p, _) => p.v,
                    color: _verde,
                    width: 1.5,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabelaWidget(TabelaCsv t) {
    const largura = 130.0;
    final larguraTotal = largura * t.colunas.length;
    Widget celula(String s, {bool cabecalho = false}) => Container(
          width: largura,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: Theme.of(context).dividerColor)),
            color: cabecalho ? Theme.of(context).colorScheme.secondaryContainer : null,
          ),
          child: Text(s,
              maxLines: cabecalho ? 3 : 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12, fontWeight: cabecalho ? FontWeight.bold : FontWeight.normal)),
        );
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 420,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: larguraTotal,
            child: Column(
              children: [
                Row(children: [for (final c in t.colunas) celula(c, cabecalho: true)]),
                Expanded(
                  child: ListView.builder(
                    itemCount: t.nLinhas,
                    itemExtent: 30,
                    itemBuilder: (_, i) {
                      final l = t.linhas[i];
                      return Container(
                        color: i.isEven ? null : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        child: Row(children: [
                          for (var c = 0; c < t.colunas.length; c++) celula(c < l.length ? l[c] : '')
                        ]),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _tabela;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _verde,
        foregroundColor: Colors.white,
        title: Text(widget.arquivo.uri.pathSegments.last, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            tooltip: 'Abrir em outro aplicativo',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => abrirEmOutroApp(context, widget.arquivo),
          ),
        ],
      ),
      body: _erro != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Erro ao ler o arquivo: $_erro')))
          : t == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  children: [
                    _resumo(t),
                    _grafico(t),
                    _tabelaWidget(t),
                  ],
                ),
    );
  }
}
