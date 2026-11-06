import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import 'bar_window.dart';

/// Remembers which edge the bar is docked to between launches. A value that
/// is missing, unreadable or unknown is the top, the edge a first launch uses.
class BarEdgeStore {
  const BarEdgeStore(this._preferences);

  static const String key = 'barEdge';

  final SharedPreferencesAsync _preferences;

  Future<BarEdge> load() async {
    try {
      final name = await _preferences.getString(key);
      return BarEdge.values.where((edge) => edge.name == name).firstOrNull ??
          BarEdge.top;
    } catch (error) {
      debugPrint('saved bar edge unreadable, using the top: $error');
      return BarEdge.top;
    }
  }

  /// A failed save costs only the memory of the edge, so it is reported and
  /// not thrown.
  Future<void> save(BarEdge edge) async {
    try {
      await _preferences.setString(key, edge.name);
    } catch (error) {
      debugPrint('bar edge not saved: $error');
    }
  }
}
