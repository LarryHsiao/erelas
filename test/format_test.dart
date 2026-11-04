import 'package:erelas/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('price carries a thousands comma and two decimals', () {
    expect(formatPrice(43307.54), '43,307.54');
  });

  test('a small price keeps two decimals and no comma', () {
    expect(formatPrice(86.5), '86.50');
  });

  test('a down move is marked with a down arrow and no minus', () {
    expect(formatMove(-3.59), '▼3.59%');
  });

  test('an up move is marked with an up arrow', () {
    expect(formatMove(1.05), '▲1.05%');
  });

  test('a flat move has no arrow', () {
    expect(formatMove(0), '0.00%');
  });

  test('a point change keeps its sign and thousands comma', () {
    expect(formatChange(-1612.6), '−1,612.60');
    expect(formatChange(7.23), '+7.23');
  });
}
