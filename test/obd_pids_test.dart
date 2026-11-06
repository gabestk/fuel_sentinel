// Testes da interpretação das respostas do ELM327, dos PIDs calculados e do CSV.
// Rodar com:  flutter test test/obd_pids_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:obdapp/functions/csv_logger.dart';
import 'package:obdapp/functions/obd_calculados.dart';
import 'package:obdapp/functions/obd_pids.dart';

void main() {
  group('PIDs suportados', () {
    test('exemplo clássico 0100 -> BE 1F A8 13', () {
      final s = pidsSuportados('41 00 BE 1F A8 13\r\r>', 0x00);
      expect(s, {
        0x01, 0x03, 0x04, 0x05, 0x06, 0x07, 0x0C, 0x0D, 0x0E, 0x0F,
        0x10, 0x11, 0x13, 0x15, 0x1C, 0x1F, 0x20,
      });
    });

    test('junta as respostas de duas ECUs', () {
      final s = pidsSuportados('41 00 80 00 00 01\r41 00 40 00 00 00\r', 0x00);
      expect(s, {0x01, 0x02, 0x20});
    });

    test('ignora SEARCHING... e aceita sem espaços', () {
      final s = pidsSuportados('SEARCHING...\r4100BE1FA813\r', 0x00);
      expect(s.contains(0x0C), isTrue);
      expect(s.length, 17);
    });

    test('aceita cabeçalho CAN de 11 bits', () {
      expect(pidsSuportados('7E8 06 41 00 BE 1F A8 13', 0x00).length, 17);
    });

    test('faixa 0120 começa no PID 0x21', () {
      expect(pidsSuportados('41 20 80 00 00 01', 0x20), {0x21, 0x40});
    });

    test('NO DATA não gera PIDs', () {
      expect(pidsSuportados('NO DATA', 0x40), isEmpty);
    });
  });

  group('Leitura de valores (unidades do OBDLink)', () {
    double? valor(String r, int pid) => interpretar(r, tabelaPids[pid]!).valor;

    test('rotação', () {
      final l = interpretar('41 0C 1C DC', tabelaPids[0x0C]!);
      expect(l.valor, 1847); // valor do CSV do OBDLink
      expect(l.hex, '1C DC');
    });

    test('vazão de ar com eco e sem espaços', () {
      expect(valor('010C\r4110 01F4\r', 0x10), closeTo(5.0, 1e-9));
    });

    test('pressões em bar, como no OBDLink', () {
      expect(valor('41 0B 1B', 0x0B), closeTo(0.27, 1e-9));
      expect(valor('41 33 65', 0x33), closeTo(1.01, 1e-9));
    });

    test('velocidade, temperatura e correção de combustível', () {
      expect(valor('41 0D 3C', 0x0D), 60);
      expect(valor('41 05 7B', 0x05), 83);
      expect(valor('41 06 80', 0x06), 0);
      expect(valor('41 07 70', 0x07), closeTo(-12.5, 1e-9));
    });

    test('lambda comandado e carga absoluta', () {
      expect(valor('41 44 80 00', 0x44), closeTo(1.0, 1e-9));
      expect(valor('41 43 00 68', 0x43), closeTo(40.784313, 1e-6));
    });

    test('sonda O2 tem duas colunas: tensão e correção', () {
      final d = tabelaPids[0x15]!;
      expect(d.colunas, ['O2 voltage (Bank 1  Sensor 2) (V)', 'Short term fuel trim (Bank 1  Sensor 2) (%)']);
      final l = interpretar('41 15 4D FF', d);
      expect(l.paraCsv(d), ['0.385', '99.21875']);
    });

    test('status do sistema de combustível tem duas colunas', () {
      final d = tabelaPids[0x03]!;
      expect(interpretar('41 03 02 00', d).paraCsv(d), ['2', '0']);
    });

    test('taxa de combustível e odômetro', () {
      expect(valor('41 5E 00 C8', 0x5E), closeTo(10.0, 1e-9));
      expect(valor('41 A6 00 01 E2 40', 0xA6), closeTo(12345.6, 1e-6));
    });

    test('sem resposta', () {
      for (final r in ['NO DATA', '', '?', 'STOPPED', 'CAN ERROR']) {
        expect(interpretar(r, tabelaPids[0x0C]!).vazio, isTrue, reason: r);
      }
    });

    test('PID sem fórmula é gravado em hexadecimal', () {
      final d = definicaoDoPid(0x9D);
      expect(d.temFormula, isFalse);
      expect(d.colunas, ['PID 01 9D (hex)']);
      expect(interpretar('41 9D 01 02 03 04', d).paraCsv(d), ['01 02 03 04']);
    });

    test('formato dos números', () {
      expect(numeroCsv(1847), '1847');
      expect(numeroCsv(9.019607843), '9.019608');
      expect(numeroCsv(0.27), '0.27');
      expect(numeroCsv(-0.0000001), '0');
    });
  });

  group('Tabela', () {
    test('não lista PIDs de suporte como dados', () {
      expect(ehPidDeSuporte(0x00), isTrue);
      expect(ehPidDeSuporte(0x20), isTrue);
      expect(ehPidDeSuporte(0x0C), isFalse);
    });

    test('nomes de coluna são únicos', () {
      final colunas = [
        for (final d in tabelaPids.values) ...d.colunas,
        for (final c in tabelaCalculados) c.coluna,
      ];
      expect(colunas.toSet().length, colunas.length);
    });

    test('nomes iguais aos do OBDLink', () {
      expect(tabelaPids[0x0C]!.colunas.single, 'Engine RPM (RPM)');
      expect(tabelaPids[0x44]!.colunas.single, 'Fuel/Air commanded equivalence ratio');
      expect(tabelaPids[0x52]!.colunas.single, 'Alcohol fuel percentage (%)');
    });
  });

  group('PIDs calculados (conferidos com um CSV do OBDLink)', () {
    // Linha real do CSV: MAF 10,25 g/s, 2134 rpm, 33 km/h
    Calculadora calc() {
      final c = Calculadora(ParametrosCalculo())..iniciar(0);
      c.registrar(pidVel, 33, 0);
      c.registrar(pidRpm, 2134, 0);
      c.registrar(pidMaf, 10.25, 0);
      return c;
    }

    test('vazão de combustível, CO2, potência e torque', () {
      final v = calc().valores(0);
      expect(v['fuel_rate']!, closeTo(10.25 * 0.33279, 1e-4));
      expect(v['co2_flow']!, closeTo(v['fuel_rate']! * 0.652138, 1e-5));
      expect(v['power']!, closeTo(10.25 * 1.188916, 1e-6));
      expect(v['torque']!, closeTo(v['power']! * 7219.6 / 2134, 1e-6));
      expect(v['inst_fe']!, closeTo(v['fuel_rate']! / 33 * 100, 1e-9));
      expect(v['inst_co2']!, closeTo(v['co2_flow']! * 3600 / 33, 1e-9));
    });

    test('MAF calculado pela densidade do ar', () {
      final c = Calculadora(ParametrosCalculo())..iniciar(0);
      c.registrar(pidRpm, 1689.25, 0);
      c.registrar(pidMap, 0.38, 0);
      c.registrar(pidIat, 48, 0);
      // valor do CSV do OBDLink nesta condição: 7,551890 g/s
      expect(c.mafCalculado!, closeTo(7.551890, 1e-3));
    });

    test('acumulados da viagem', () {
      final c = calc();
      final v = c.valores(3600); // 1 h a 33 km/h com MAF constante
      expect(v['trip_dist']!, closeTo(33, 1e-9));
      expect(v['trip_fuel']!, closeTo(10.25 * 0.33279, 1e-3));
      expect(v['avg_speed']!, closeTo(33, 1e-9));
      expect(v['trip_dur']!, closeTo(60, 1e-9));
      expect(v['trip_cost']!, closeTo(v['trip_fuel']! * 3.5, 1e-9));
    });

    test('marcha lenta e aceleração', () {
      final c = Calculadora(ParametrosCalculo())..iniciar(0);
      c.registrar(pidRpm, 800, 0);
      c.registrar(pidVel, 0, 0);
      c.registrar(pidVel, 0, 10);
      c.registrar(pidVel, 18, 11); // 0 -> 5 m/s em 1 s
      final v = c.valores(11);
      expect(v['idle_count'], 1);
      // o valor anterior (parado) vale até a leitura seguinte, em t = 11 s
      expect(v['idle_sec']!, closeTo(11, 1e-9));
      expect(v['accel']!, closeTo(5, 1e-9));
      expect(v['hard_accel'], 1);
    });

    test('dependências', () {
      final fr = tabelaCalculados.firstWhere((c) => c.id == 'fuel_rate');
      expect(fr.pidsNecessarios([pidMaf]), {pidMaf});
      expect(fr.pidsNecessarios([pidMap, pidRpm, pidIat]), {pidMap, pidRpm, pidIat});
      expect(fr.pidsNecessarios([pidVel]), isNull);
    });
  });

  group('CSV', () {
    test('escapa vírgulas e aspas', () {
      expect(linhaCsv(['a', 'b,c', 'd"e']), 'a,"b,c","d""e"');
    });

    test('nome de arquivo sem dois-pontos nem espaços', () {
      final n = carimboArquivo(DateTime(2026, 11, 6, 9, 5, 3));
      expect(n, '2026-11-06_09-05-03');
    });

    test('coluna Time no formato do OBDLink', () {
      expect(carimboObdlink(DateTime(2026, 9, 30, 13, 36, 32, 394, 400)), '09/30/2026 01:36:32.3944 PM');
      expect(carimboObdlink(DateTime(2026, 9, 30, 0, 5, 1, 7)), '09/30/2026 12:05:01.0070 AM');
    });
  });
}
