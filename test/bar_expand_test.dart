import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:erelas/bar_view.dart';
import 'package:erelas/bar_window.dart';
import 'package:erelas/detail_panel.dart';
import 'package:erelas/main.dart';
import 'package:erelas/today.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Today> load() async => Today.fromJson(
  jsonDecode(File('test/fixtures/today_v1.json').readAsStringSync())
      as Map<String, dynamic>,
);

Future<ValueNotifier<bool>> pumpPage(
  WidgetTester tester, {
  BarEdge edge = BarEdge.top,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1600, 400);
  addTearDown(tester.view.reset);
  final expanded = ValueNotifier(false);
  await tester.pumpWidget(
    MaterialApp(
      home: TodayPage(
        load: load,
        expanded: expanded,
        edge: ValueNotifier(edge),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return expanded;
}

void main() {
  testWidgets('the panel is closed at first', (tester) async {
    final expanded = await pumpPage(tester);
    expect(expanded.value, isFalse);
    expect(find.byType(DetailPanel), findsNothing);
  });

  testWidgets('tapping the bar opens the panel', (tester) async {
    final expanded = await pumpPage(tester);
    await tester.tap(find.text('TAIEX 43,307.54'));
    await tester.pump();
    expect(expanded.value, isTrue);
    expect(find.byType(DetailPanel), findsOneWidget);
  });

  testWidgets('tapping again closes it', (tester) async {
    final expanded = await pumpPage(tester);
    await tester.tap(find.text('TAIEX 43,307.54'));
    await tester.pump();
    await tester.tap(find.text('TAIEX 43,307.54'));
    await tester.pump();
    expect(expanded.value, isFalse);
    expect(find.byType(DetailPanel), findsNothing);
  });

  testWidgets('collapsing from outside closes the panel', (tester) async {
    final expanded = await pumpPage(tester);
    await tester.tap(find.text('TAIEX 43,307.54'));
    await tester.pump();
    expanded.value = false;
    await tester.pump();
    expect(find.byType(DetailPanel), findsNothing);
  });

  testWidgets('a top bar has its drawer below it', (tester) async {
    final expanded = await pumpPage(tester);
    expanded.value = true;
    await tester.pump();
    const expected = barHeight;
    final actual = tester.getTopLeft(find.byType(DetailPanel)).dy;
    expect(actual, expected);
  });

  testWidgets('a bottom bar has its drawer above it', (tester) async {
    final expanded = await pumpPage(tester, edge: BarEdge.bottom);
    expanded.value = true;
    await tester.pump();
    const expected = 400 - barHeight - detailHeight;
    final actual = tester.getTopLeft(find.byType(DetailPanel)).dy;
    expect(actual, expected);
  });

  testWidgets('a bottom bar still loading sits at the bottom', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: TodayPage(
          load: () => Completer<Today>().future,
          expanded: ValueNotifier(false),
          edge: ValueNotifier(BarEdge.bottom),
        ),
      ),
    );
    const expected = 400.0;
    final actual = tester.getBottomLeft(find.byType(Container).last).dy;
    expect(actual, expected);
  });
}
