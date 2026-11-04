import 'dart:convert';
import 'dart:io';

import 'package:erelas/detail_panel.dart';
import 'package:erelas/format.dart';
import 'package:erelas/today.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final today = Today.fromJson(
  jsonDecode(File('test/fixtures/today_v1.json').readAsStringSync())
      as Map<String, dynamic>,
);

Future<void> pumpPanel(WidgetTester tester, Today data) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: DetailPanel(today: data)),
    ),
  );
}

void main() {
  testWidgets('shows the close, change, percent, date and source', (
    tester,
  ) async {
    await pumpPanel(tester, today);
    for (final expected in [
      '43,307.54',
      '−1,612.60  ▼3.59%',
      'Index close · 2026-11-03',
      'Source: TWSE',
    ]) {
      expect(find.text(expected), findsOneWidget);
    }
  });

  testWidgets('shows when the data was fetched', (tester) async {
    await pumpPanel(tester, today);
    expect(find.text('Updated 2026-11-04 12:28'), findsOneWidget);
  });

  testWidgets('lists every ticker item with its close and move', (
    tester,
  ) async {
    await pumpPanel(tester, today);
    for (final item in today.ticker) {
      expect(find.text(item.name), findsOneWidget);
      expect(find.text(formatPrice(item.close)), findsWidgets);
    }
    expect(find.byKey(tickerListKey), findsOneWidget);
  });

  testWidgets('with no ticker items the list is not drawn', (tester) async {
    final bare = Today(index: today.index, ticker: const [], asOf: today.asOf);
    await pumpPanel(tester, bare);
    expect(find.byKey(tickerListKey), findsNothing);
    expect(find.text('Source: TWSE'), findsOneWidget);
  });

  testWidgets('a long list in a short panel scrolls, it does not overflow', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(300, detailHeight);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: detailHeight,
            child: DetailPanel(today: today),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
