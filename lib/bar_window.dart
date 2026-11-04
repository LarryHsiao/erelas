import 'dart:io' show Platform;

import 'package:flutter/painting.dart';
import 'package:nativeapi/nativeapi.dart' show DisplayManager;
import 'package:window_manager/window_manager.dart';

import 'bar_view.dart';
import 'detail_panel.dart';

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
  if (Platform.isMacOS) {
    window.isVisibleOnAllWorkspaces = true;
    window.setVisibleOnFullScreen(true);
  }
  if (Platform.isWindows) window.isVisibleInTaskbar = false;
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

/// Grows the bar's window downward to hold the detail drawer, or shrinks it
/// back. Left, top and width stay where they are.
void resizeBar(Window window, {required bool expanded}) {
  final bounds = window.bounds.toRect();
  final height = expanded ? barHeight + detailHeight : barHeight;
  window.bounds = Rect.fromLTWH(
    bounds.left,
    bounds.top,
    bounds.width,
    height,
  ).toNative();
}

/// Gives the window its frame back, and with it a close button. Used when the
/// menu-bar or tray item could not be made: a frameless, always-on-top bar
/// with no tray has no other way to be hidden or quit. The content area keeps
/// the bar's height, so the title bar grows the window instead of eating the bar.
void restoreFrame(Window window) {
  window.setFrameless(false);
  window.isResizable = true;
  if (Platform.isWindows) window.isVisibleInTaskbar = true;
  final area = window.bounds.toRect();
  window.contentBounds =
      Rect.fromLTWH(area.left, area.top, area.width, barHeight).toNative();
}
