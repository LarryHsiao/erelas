import 'package:erelas/bar_edge_store.dart';
import 'package:erelas/bar_window.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

BarEdgeStore storeWith(Map<String, Object> data) {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData(data);
  return BarEdgeStore(SharedPreferencesAsync());
}

base class FailingPreferences extends InMemorySharedPreferencesAsync {
  FailingPreferences() : super.empty();

  @override
  Future<bool> setString(
    String key,
    String value,
    SharedPreferencesOptions options,
  ) => throw StateError('disk full');
}

void main() {
  test('nothing saved starts at the top', () async {
    const expected = BarEdge.top;
    final actual = await storeWith({}).load();
    expect(actual, expected);
  });

  test('a saved bottom loads as the bottom', () async {
    const expected = BarEdge.bottom;
    final actual = await storeWith({BarEdgeStore.key: 'bottom'}).load();
    expect(actual, expected);
  });

  test('a saved top loads as the top', () async {
    const expected = BarEdge.top;
    final actual = await storeWith({BarEdgeStore.key: 'top'}).load();
    expect(actual, expected);
  });

  test('an unreadable saved value starts at the top', () async {
    const expected = BarEdge.top;
    final actual = await storeWith({BarEdgeStore.key: 'left'}).load();
    expect(actual, expected);
  });

  test('a saved edge is the one loaded next time', () async {
    final store = storeWith({});
    await store.save(BarEdge.bottom);
    const expected = BarEdge.bottom;
    expect(await store.load(), expected);
  });

  test('a save that fails is reported, not thrown', () async {
    SharedPreferencesAsyncPlatform.instance = FailingPreferences();
    final store = BarEdgeStore(SharedPreferencesAsync());
    await expectLater(store.save(BarEdge.bottom), completes);
  });
}
