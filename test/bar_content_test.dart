import 'dart:ui';

import 'package:erelas/bar_view.dart';
import 'package:erelas/bar_window.dart';
import 'package:erelas/detail_panel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const current = Rect.fromLTWH(10, 30, 1920, barHeight);

  test('expanded makes the content bar plus drawer tall', () {
    final expected = Rect.fromLTWH(10, 30, 1920, barHeight + detailHeight);
    expect(barContent(current, expanded: true), expected);
  });

  test('collapsed makes the content exactly the bar tall', () {
    final open = Rect.fromLTWH(10, 30, 1920, barHeight + detailHeight);
    const expected = Rect.fromLTWH(10, 30, 1920, barHeight);
    expect(barContent(open, expanded: false), expected);
  });

  test('left, top and width are never moved', () {
    final actual = barContent(
      const Rect.fromLTWH(7, 9, 800, 5),
      expanded: true,
    );
    expect([actual.left, actual.top, actual.width], [7, 9, 800]);
  });
}
