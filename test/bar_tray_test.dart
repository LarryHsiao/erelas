import 'package:erelas/bar_tray.dart';
import 'package:erelas/bar_window.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a visible bar offers to hide itself', () {
    expect(toggleLabel(true), 'Hide bar');
  });

  test('a hidden bar offers to show itself', () {
    expect(toggleLabel(false), 'Show bar');
  });

  test('a top bar offers to move to the bottom', () {
    expect(moveLabel(BarEdge.top), 'Move to bottom');
  });

  test('a bottom bar offers to move to the top', () {
    expect(moveLabel(BarEdge.bottom), 'Move to top');
  });

  test('the update item names what it does', () {
    expect(checkUpdatesLabel, 'Check for Updates…');
  });
}
