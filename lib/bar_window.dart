import 'dart:io' show Platform;

import 'package:flutter/painting.dart';
import 'package:nativeapi/nativeapi.dart' show DisplayManager;
import 'package:window_manager/window_manager.dart';

import 'bar_view.dart';
import 'detail_panel.dart';

/// The screen edge the bar is docked to.
enum BarEdge {
  top,
  bottom;

  BarEdge get other => this == top ? bottom : top;
}

/// The window frame for the bar inside [area], flush to [edge]. An open bar
/// grows away from its edge, so the edge itself never moves.
Rect barFrame(Rect area, BarEdge edge, {required bool expanded}) {
  final height = expanded ? barHeight + detailHeight : barHeight;
  final top = edge == BarEdge.top ? area.top : area.bottom - height;
  return Rect.fromLTWH(area.left, top, area.width, height);
}

/// Turns the app window into a borderless, always-on-top bar docked to the
/// top of the primary display's work area, on every Space.
Window configureBarWindow() {
  final window = WindowManager.instance.getCurrent();
  final display = DisplayManager.instance.getPrimary();
  if (window == null || display == null) {
    throw StateError('no window or display to dock the bar to');
  }
  window.setFrameless(true);
  window.isAlwaysOnTop = true;
  if (Platform.isMacOS) {
    window.isVisibleOnAllWorkspaces = true;
    window.setVisibleOnFullScreen(true);
  }
  if (Platform.isWindows) window.isVisibleInTaskbar = false;
  window.isResizable = false;
  window.bounds = barFrame(
    display.workArea.toRect(),
    BarEdge.top,
    expanded: false,
  ).toNative();
  window.show();
  return window;
}

/// Docks the bar to [edge] of the primary display's work area. It sets the
/// outer bounds, which equal the content area only while the window is
/// frameless; the framed fallback has no tray, so it never moves.
void moveBar(Window window, BarEdge edge, {required bool expanded}) {
  final display = DisplayManager.instance.getPrimary();
  if (display == null) throw StateError('no display to dock the bar to');
  window.bounds = barFrame(
    display.workArea.toRect(),
    edge,
    expanded: expanded,
  ).toNative();
}

/// The content area for the bar, closed or holding the detail drawer. Left
/// and width stay where they are, and so does the edge the bar is docked to.
Rect barContent(Rect current, {required bool expanded, required BarEdge edge}) {
  final height = expanded ? barHeight + detailHeight : barHeight;
  final top = edge == BarEdge.top ? current.top : current.bottom - height;
  return Rect.fromLTWH(current.left, top, current.width, height);
}

/// Grows the bar's window away from its edge to hold the detail drawer, or
/// shrinks it back. It sizes the content area, so a framed window (see
/// [restoreFrame]) keeps its title bar outside the bar's own height.
void resizeBar(Window window, {required bool expanded, required BarEdge edge}) {
  final content = window.contentBounds.toRect();
  window.contentBounds = barContent(
    content,
    expanded: expanded,
    edge: edge,
  ).toNative();
}

/// Gives the window its frame back, and with it a close button. Used when the
/// menu-bar or tray item could not be made: a frameless, always-on-top bar
/// with no tray has no other way to be hidden or quit. The content area keeps
/// the bar's height, so the title bar grows the window instead of eating it.
void restoreFrame(Window window) {
  window.setFrameless(false);
  window.isResizable = true;
  if (Platform.isWindows) window.isVisibleInTaskbar = true;
  final area = window.bounds.toRect();
  window.contentBounds = Rect.fromLTWH(
    area.left,
    area.top,
    area.width,
    barHeight,
  ).toNative();
}
