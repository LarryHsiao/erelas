import 'dart:convert';
import 'dart:io';

import 'package:erelas/today.dart';
import 'package:erelas/fetch_today.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final fixture = File('test/fixtures/today_v1.json').readAsStringSync();

void main() {
  group('Today.fromJson', () {
    test('reads the index close, signed change and date', () {
      final expected = (
        date: '2026-11-03',
        close: 43307.54,
        change: -1612.6,
        changePct: -3.59,
      );
      final today = Today.fromJson(jsonDecode(fixture) as Map<String, dynamic>);
      final actual = (
        date: today.index.date,
        close: today.index.close,
        change: today.index.change,
        changePct: today.index.changePct,
      );
      expect(actual, expected);
    });

    test('reads the six ticker items in order', () {
      final expected = [
        '電子工業類指數',
        '半導體類指數',
        '金融保險類指數',
        '臺灣50指數',
        '航運類指數',
        '塑膠類指數',
      ];
      final today = Today.fromJson(jsonDecode(fixture) as Map<String, dynamic>);
      expect(today.ticker.map((q) => q.name).toList(), expected);
    });

    test('a null topic reads as no topic', () {
      final today = Today.fromJson(jsonDecode(fixture) as Map<String, dynamic>);
      expect(today.topic, isNull);
    });

    test('unknown fields are ignored', () {
      final json = jsonDecode(fixture) as Map<String, dynamic>;
      json['somethingNew'] = {'a': 1};
      expect(() => Today.fromJson(json), returnsNormally);
    });

    test('an unsupported contract version fails loud', () {
      final json = jsonDecode(fixture) as Map<String, dynamic>;
      json['v'] = 2;
      expect(() => Today.fromJson(json), throwsFormatException);
    });

    test('an integer close from the JSON is read as a double', () {
      final json = jsonDecode(fixture) as Map<String, dynamic>;
      (json['index'] as Map<String, dynamic>)['close'] = 43307;
      expect(Today.fromJson(json).index.close, 43307.0);
    });
  });

  group('fetchToday', () {
    test('returns the parsed payload on 200', () async {
      final client = MockClient((_) async => http.Response.bytes(
            utf8.encode(fixture),
            200,
            headers: {'content-type': 'application/json'},
          ));
      final today = await fetchToday(client, Uri.parse('https://x/today.json'));
      expect(today.index.close, 43307.54);
    });

    test('a non-200 reply fails loud', () async {
      final client = MockClient((_) async => http.Response('nope', 404));
      expect(
        fetchToday(client, Uri.parse('https://x/today.json')),
        throwsA(isA<http.ClientException>()),
      );
    });

    test('a body that is not the contract fails loud', () async {
      final client = MockClient((_) async => http.Response('{}', 200));
      expect(
        fetchToday(client, Uri.parse('https://x/today.json')),
        throwsA(anything),
      );
    });
  });
}
