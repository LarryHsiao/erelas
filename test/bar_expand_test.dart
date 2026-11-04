import 'dart:convert';
import 'dart:io';

import 'package:erelas/detail_panel.dart';
import 'package:erelas/main.dart';
import 'package:erelas/today.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Today> load() async => Today.fromJson(
  jsonDecode(File('test/fixtures/today_v1.json').readAsStringSync())
      as Map<String, dynamic>,
);

Future<ValueNotifier<bool>> pumpPage(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1600, 400);
  addTearDown(tester.view.reset);
  final expanded = ValueNotifier(false);
  await tester.pumpWidget(
    MaterialApp(
      home: TodayPage(load: load, expanded: expanded),
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
}
