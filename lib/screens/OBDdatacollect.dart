import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import '../functions/elm327.dart';

import 'package:obdapp/functions/InternalDatabase.dart';

import '../widgets/coletasSalvas.dart';
import '../widgets/dataConnect.dart';

@RoutePage()
class obddata extends StatelessWidget {
  final Elm327 elm;
  final int value;

  const obddata({super.key, required this.elm, required this.value});

  Future<void> _voltar(BuildContext context) async {
    var bancoInterno = InternalDatabase();
    await bancoInterno.handledata();
    if (context.mounted) context.router.popUntilRoot();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _voltar(context);
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF008355),
          foregroundColor: Colors.white,
          title: const Text('Abastecimento'),
          centerTitle: true,
          leading: IconButton(
            tooltip: 'Encerrar coleta',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _voltar(context),
          ),
          actions: [
            IconButton(
              tooltip: 'Coletas salvas (CSV)',
              icon: const Icon(Icons.folder_open),
              onPressed: () => abrirColetas(context),
            ),
          ],
        ),
        body: SafeArea(
          child: Data_Connect(
            elm: elm,
            value: value,
          ),
        ),
      ),
    );
  }
}
