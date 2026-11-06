import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/foundation.dart' show debugPrint;

const String updateFeedUrl = 'https://larryhsiao.github.io/erelas/appcast.xml';
const Duration updateCheckInterval = Duration(hours: 24);

/// What the update check needs from Sparkle. [AutoUpdater] has a private
/// constructor, so this seam is what lets a test stand in for it.
abstract interface class UpdateSource {
  Future<void> setFeedUrl(String url);
  Future<void> setCheckInterval(Duration interval);
  Future<void> checkInBackground();
  Future<void> checkNow();
}

class SparkleSource implements UpdateSource {
  const SparkleSource();

  @override
  Future<void> setFeedUrl(String url) => autoUpdater.setFeedURL(url);

  @override
  Future<void> setCheckInterval(Duration interval) =>
      autoUpdater.setScheduledCheckInterval(interval.inSeconds);

  @override
  Future<void> checkInBackground() =>
      autoUpdater.checkForUpdates(inBackground: true);

  @override
  Future<void> checkNow() => autoUpdater.checkForUpdates(inBackground: false);
}

/// Checks for a newer release at launch and then on Sparkle's own schedule.
/// Best-effort: a missing feed or a dropped network must never get in the way
/// of the bar, so a failure is reported to the console and nothing more.
class UpdateCheck {
  const UpdateCheck(this._source);

  final UpdateSource _source;

  Future<void> start() async {
    await _guarded(() async {
      await _source.setFeedUrl(updateFeedUrl);
      await _source.setCheckInterval(updateCheckInterval);
      await _source.checkInBackground();
    });
  }

  /// A check the user asked for: Sparkle answers it with a dialog either way,
  /// "up to date" or "update available".
  Future<void> checkNow() => _guarded(_source.checkNow);

  Future<void> _guarded(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      debugPrint('update check unavailable: $error');
    }
  }
}
