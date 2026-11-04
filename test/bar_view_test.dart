import 'dart:convert';
import 'dart:io';

import 'package:erelas/bar_view.dart';
import 'package:erelas/crawl.dart';
import 'package:erelas/today.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final today = Today.fromJson(
  jsonDecode(File('test/fixtures/today_v1.json').readAsStringSync())
      as Map<String, dynamic>,
);

Future<void> pumpBar(WidgetTester tester, double width, {Today? data}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, barHeight);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: BarView(today: data ?? today)),
    ),
  );
}

void main() {
  testWidgets('the source label sits at the right edge of the bar', (
    tester,
  ) async {
    const width = 1200.0;
    const padding = 12.0;
    await pumpBar(tester, width);
    final right = tester.getTopRight(find.text('2026-11-03 · Source: TWSE')).dx;
    expect(right, width - padding);
  });

  testWidgets('a wide bar shows close, change and source', (tester) async {
    await pumpBar(tester, 1200);
    expect(find.text('TAIEX 43,307.54'), findsOneWidget);
    expect(find.text('−1,612.60  ▼3.59%'), findsOneWidget);
    expect(find.text('2026-11-03 · Source: TWSE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a narrow bar shrinks the crawl first (test font is 1em wide)', (
    tester,
  ) async {
    await pumpBar(tester, 900);
    final close = tester.widget<Text>(find.text('TAIEX 43,307.54'));
    expect(close.overflow, isNot(TextOverflow.ellipsis));
    expect(find.text('TAIEX 43,307.54'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with no ticker items the crawl strip is not drawn', (
    tester,
  ) async {
    final bare = Today(index: today.index, ticker: const [], asOf: today.asOf);
    await pumpBar(tester, 1200, data: bare);
    expect(find.byType(Crawl), findsNothing);
    final right = tester.getTopRight(find.text('2026-11-03 · Source: TWSE')).dx;
    expect(right, 1200 - 12);
  });

  testWidgets('with ticker items the bar draws the crawl', (tester) async {
    await pumpBar(tester, 1200);
    expect(find.byType(Crawl), findsOneWidget);
  });

  testWidgets('the source label never disappears from a bar that has room', (
    tester,
  ) async {
    await pumpBar(tester, 800);
    expect(find.textContaining('Source: TWSE'), findsOneWidget);
  });
}
