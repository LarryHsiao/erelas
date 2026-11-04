import 'package:flutter/painting.dart';
import 'package:nativeapi/nativeapi.dart' show DisplayManager;
import 'package:window_manager/window_manager.dart';

import 'bar_view.dart';

/// Turns the app window into a borderless, always-on-top bar docked to the
/// top of the primary display's work area, on every Space.
Window configureBarWindow() {
  final window = WindowManager.instance.getCurrent();
  final display = DisplayManager.instance.getPrimary();
  if (window == null || display == null) {
    throw StateError('no window or display to dock the bar to');
  }
  final area = display.workArea.toRect();
  window.setFrameless(true);
  window.isAlwaysOnTop = true;
  window.isVisibleOnAllWorkspaces = true;
  window.setVisibleOnFullScreen(true);
  window.isResizable = false;
  window.bounds = Rect.fromLTWH(
    area.left,
    area.top,
    area.width,
    barHeight,
  ).toNative();
  window.show();
  return window;
}
