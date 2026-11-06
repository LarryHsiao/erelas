import 'dart:ui';

import 'package:erelas/bar_view.dart';
import 'package:erelas/bar_window.dart';
import 'package:erelas/detail_panel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const area = Rect.fromLTWH(0, 25, 1920, 1055);

  test('a top bar sits flush to the top of the work area', () {
    const expected = Rect.fromLTWH(0, 25, 1920, barHeight);
    expect(barFrame(area, BarEdge.top, expanded: false), expected);
  });

  test('a bottom bar sits flush to the bottom of the work area', () {
    final expected = Rect.fromLTWH(0, 1080 - barHeight, 1920, barHeight);
    expect(barFrame(area, BarEdge.bottom, expanded: false), expected);
  });

  test('an open top bar grows downward', () {
    final expected = Rect.fromLTWH(0, 25, 1920, barHeight + detailHeight);
    expect(barFrame(area, BarEdge.top, expanded: true), expected);
  });

  test('an open bottom bar grows upward, its bottom edge held', () {
    const height = barHeight + detailHeight;
    final expected = Rect.fromLTWH(0, 1080 - height, 1920, height);
    expect(barFrame(area, BarEdge.bottom, expanded: true), expected);
  });

  test('a bottom content area keeps its bottom edge when it grows', () {
    const current = Rect.fromLTWH(10, 1000, 800, barHeight);
    final actual = barContent(current, expanded: true, edge: BarEdge.bottom);
    expect(actual.bottom, current.bottom);
  });

  test('the other edge is the one to move to', () {
    expect(BarEdge.top.other, BarEdge.bottom);
    expect(BarEdge.bottom.other, BarEdge.top);
  });
}
