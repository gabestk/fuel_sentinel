// Preferências do app guardadas no celular (SharedPreferences), usadas pela
// página de Configuração e pelas abas.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const chaveTema = 'tema';

// Scanner (as mesmas chaves que a aba Scanner usa)
const chaveScannerTaxa = 'scanner_taxa_hz';
const chaveScannerGps = 'scanner_usar_gps';
const chaveScannerSensores = 'scanner_usar_sensores';
const chaveScannerRapida = 'scanner_leitura_rapida';
const prefixoParamCalculo = 'scanner_param_';

ThemeMode temaDeTexto(String? t) => switch (t) {
      'claro' => ThemeMode.light,
      'escuro' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

String textoDeTema(ThemeMode m) => switch (m) {
      ThemeMode.light => 'claro',
      ThemeMode.dark => 'escuro',
      _ => 'sistema',
    };

Future<ThemeMode> carregarTema() async {
  final prefs = await SharedPreferences.getInstance();
  return temaDeTexto(prefs.getString(chaveTema));
}

Future<void> salvarTema(ThemeMode m) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(chaveTema, textoDeTema(m));
}

/// Tema claro e escuro do app, com o verde do Fuel Sentinel.
ThemeData temaDoApp(Brightness brilho) {
  final esquema = ColorScheme.fromSeed(
    seedColor: const Color(0xFF26B07F),
    brightness: brilho,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    scaffoldBackgroundColor:
        brilho == Brightness.light ? const Color(0xFFF6F8F7) : esquema.surface,
    cardTheme: CardThemeData(
      color: brilho == Brightness.light ? Colors.white : esquema.surfaceContainer,
    ),
  );
}
