import 'package:erelas/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('asOf is shown to the minute, without the T or the offset', () {
    expect(formatAsOf('2026-11-04T12:28:23+08:00'), '2026-11-04 12:28');
  });

  test('a malformed asOf is shown as it came, not cut or thrown', () {
    expect(formatAsOf('soon'), 'soon');
  });
}
