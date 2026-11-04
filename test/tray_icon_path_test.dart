import 'package:erelas/bar_tray.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the icon sits in the flutter assets beside the executable', () {
    const sep = '/';
    final expected = [
      'C:/apps/erelas',
      'data',
      'flutter_assets',
      'assets',
      'tray_icon.png',
    ].join(sep);
    final actual = trayIconPath('C:/apps/erelas/erelas.exe', separator: sep);
    expect(actual, expected);
  });

  test('a backslash separator is used as given', () {
    const sep = r'\';
    final expected = [
      r'C:\apps\erelas',
      'data',
      'flutter_assets',
      'assets',
      'tray_icon.png',
    ].join(sep);
    final actual = trayIconPath(r'C:\apps\erelas\erelas.exe', separator: sep);
    expect(actual, expected);
  });

  test('an executable with no directory part resolves beside itself', () {
    final actual = trayIconPath('erelas.exe', separator: '/');
    expect(actual, 'data/flutter_assets/assets/tray_icon.png');
  });
}
