import 'package:flutter_test/flutter_test.dart';
import 'package:obdapp/functions/nivel_estavel.dart';

void main() {
  final t0 = DateTime(2026, 11, 6, 14);
  DateTime t(int s) => t0.add(Duration(seconds: s));

  test('mediana e percentil', () {
    expect(mediana([3, 1, 2]), 2);
    expect(mediana([4, 1, 2, 3]), 2.5);
    expect(percentil([0, 10], 0.5), 5);
  });

  test('nível parado com ruído fica estável e usa a mediana', () {
    final e = EstabilizadorNivel();
    final valores = [32.2, 32.5, 32.5, 40.0, 32.9, 32.5, 32.2, 32.5];
    for (var i = 0; i < valores.length; i++) {
      e.adicionar(valores[i], t(i * 3));
    }
    expect(e.estavel, isTrue);
    expect(e.valor, 32.5);
  });

  test('poucas leituras ou pouco tempo ainda não é estável', () {
    final e = EstabilizadorNivel();
    for (var i = 0; i < 10; i++) {
      e.adicionar(50, t(i)); // 9 s de leitura
    }
    expect(e.estavel, isFalse);
    e.adicionar(50, t(16));
    expect(e.estavel, isTrue);
  });

  test('nível ainda subindo (filtro da ECU) não é estável', () {
    final e = EstabilizadorNivel();
    for (var i = 0; i < 12; i++) {
      e.adicionar(30 + i * 1.5, t(i * 3));
    }
    expect(e.estavel, isFalse);
  });

  test('ignora leituras inválidas e reinicia', () {
    final e = EstabilizadorNivel();
    e.adicionar(double.nan, t(0));
    e.adicionar(-1, t(1));
    e.adicionar(120, t(2));
    expect(e.quantidade, 0);
    e.adicionar(10, t(3));
    e.reiniciar();
    expect(e.quantidade, 0);
  });

  test('a 1 Hz com valor constante estabiliza (caso do emulador)', () {
    final e = EstabilizadorNivel();
    var travou = -1;
    for (var i = 0; i < 60; i++) {
      e.adicionar(72.94117647058823, t(i));
      if (travou < 0 && e.estavel) travou = i;
    }
    expect(travou, 15);
    expect(e.duracao.inSeconds, lessThanOrEqualTo(30));
  });

  test('com intervalo longo (10 s) mantém leituras suficientes', () {
    final e = EstabilizadorNivel();
    for (var i = 0; i < 8; i++) {
      e.adicionar(40, t(i * 10));
    }
    expect(e.quantidade, greaterThanOrEqualTo(6));
    expect(e.estavel, isTrue);
  });
}
