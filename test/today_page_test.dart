import 'dart:convert';
import 'dart:io';

import 'package:erelas/bar_view.dart';
import 'package:erelas/main.dart';
import 'package:erelas/today.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Today> loadFixture() async => Today.fromJson(
    jsonDecode(File('test/fixtures/today_v1.json').readAsStringSync())
        as Map<String, dynamic>);

Future<Today> loadFailure() async => throw Exception('offline');

Future<void> pumpPage(WidgetTester tester, Future<Today> Function() load) async {
  await tester.pumpWidget(MaterialApp(home: TodayPage(load: load)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the close, change, date and source', (tester) async {
    const expected = [
      'TAIEX 43,307.54',
      '−1,612.60  ▼3.59%',
      '2026-11-03 · Source: TWSE',
    ];
    await pumpPage(tester, loadFixture);
    for (final line in expected) {
      expect(find.text(line), findsOneWidget);
    }
  });

  testWidgets('a down day is drawn in the down colour', (tester) async {
    await pumpPage(tester, loadFixture);
    final change = tester.widget<Text>(find.text('−1,612.60  ▼3.59%'));
    expect(change.style?.color, downColor);
  });

  testWidgets('a failed load shows a dash, not an error screen', (tester) async {
    await pumpPage(tester, loadFailure);
    expect(find.text('TAIEX —'), findsOneWidget);
  });
}
