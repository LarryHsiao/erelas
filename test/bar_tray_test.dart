import 'package:erelas/bar_tray.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a visible bar offers to hide itself', () {
    expect(toggleLabel(true), 'Hide bar');
  });

  test('a hidden bar offers to show itself', () {
    expect(toggleLabel(false), 'Show bar');
  });
}
