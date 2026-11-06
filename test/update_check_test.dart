import 'package:erelas/update_check.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingSource implements UpdateSource {
  RecordingSource({this.failOn});

  final String? failOn;
  final List<String> calls = [];

  Future<void> _record(String call, String name) async {
    calls.add(call);
    if (failOn == name) throw StateError('$name failed');
  }

  @override
  Future<void> setFeedUrl(String url) => _record('feed:$url', 'feed');

  @override
  Future<void> setCheckInterval(Duration interval) =>
      _record('interval:${interval.inSeconds}', 'interval');

  @override
  Future<void> checkInBackground() => _record('check', 'check');

  @override
  Future<void> checkNow() => _record('now', 'now');
}

void main() {
  test(
    'start points Sparkle at the feed, sets the interval, then checks',
    () async {
      final source = RecordingSource();
      final expected = [
        'feed:$updateFeedUrl',
        'interval:${updateCheckInterval.inSeconds}',
        'check',
      ];
      await UpdateCheck(source).start();
      expect(source.calls, expected);
    },
  );

  test('the feed is on the same Pages site as today.json', () {
    const expected = 'https://larryhsiao.github.io/erelas/appcast.xml';
    expect(updateFeedUrl, expected);
  });

  test('the check repeats once a day', () {
    const expected = Duration(hours: 24);
    expect(updateCheckInterval, expected);
  });

  test('a failure while checking is swallowed', () async {
    final source = RecordingSource(failOn: 'check');
    await expectLater(UpdateCheck(source).start(), completes);
  });

  test('a failure setting the feed skips the rest and is swallowed', () async {
    final source = RecordingSource(failOn: 'feed');
    final expected = ['feed:$updateFeedUrl'];
    await UpdateCheck(source).start();
    expect(source.calls, expected);
  });

  test(
    'a failure setting the interval skips the check and is swallowed',
    () async {
      final source = RecordingSource(failOn: 'interval');
      final expected = ['feed:$updateFeedUrl', 'interval:86400'];
      await UpdateCheck(source).start();
      expect(source.calls, expected);
    },
  );

  test('checkNow asks Sparkle for a visible check', () async {
    final source = RecordingSource();
    final expected = ['now'];
    await UpdateCheck(source).checkNow();
    expect(source.calls, expected);
  });

  test('a failure during checkNow is swallowed', () async {
    final source = RecordingSource(failOn: 'now');
    await expectLater(UpdateCheck(source).checkNow(), completes);
  });
}
