import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:nativeapi/nativeapi.dart'
    show
        Application,
        ContextMenuTrigger,
        Image,
        Menu,
        MenuItem,
        MenuItemClickedEvent,
        MenuItemType,
        TrayIcon;
import 'package:window_manager/window_manager.dart' show Window;

import 'bar_window.dart' show BarEdge;

const String trayTitle = '◆';
const String trayTooltip = 'Erelas';
const String quitLabel = 'Quit Erelas';
const String trayIconFile = 'tray_icon.png';

String toggleLabel(bool barVisible) => barVisible ? 'Hide bar' : 'Show bar';

String moveLabel(BarEdge edge) =>
    edge == BarEdge.top ? 'Move to bottom' : 'Move to top';

/// Where the tray icon lies beside a built app: the executable's directory,
/// then `data/flutter_assets/assets/tray_icon.png`. Windows draws no title in
/// its tray, so it needs the image. The path is built with [separator], the
/// platform's by default.
String trayIconPath(String executable, {String? separator}) {
  final sep = separator ?? Platform.pathSeparator;
  final cut = executable.lastIndexOf(sep);
  return [
    if (cut > 0) executable.substring(0, cut),
    'data',
    'flutter_assets',
    'assets',
    trayIconFile,
  ].join(sep);
}

/// Native handles must outlive [installTray] or the menu-bar item vanishes.
final List<Object> _alive = [];

typedef _Handles = ({
  TrayIcon tray,
  Menu menu,
  MenuItem toggle,
  MenuItem move,
  MenuItem divider,
  MenuItem quit,
});

_Handles _createHandles() {
  final tray = TrayIcon.create();
  final menu = Menu.create();
  final toggle = MenuItem.createWithLabelAndType(
    toggleLabel(true),
    MenuItemType.normal,
  );
  final move = MenuItem.createWithLabelAndType(
    moveLabel(BarEdge.top),
    MenuItemType.normal,
  );
  final divider = MenuItem.createWithLabelAndType('', MenuItemType.separator);
  final quit = MenuItem.createWithLabelAndType(quitLabel, MenuItemType.normal);
  if (tray == null ||
      menu == null ||
      toggle == null ||
      move == null ||
      divider == null ||
      quit == null) {
    throw StateError('the native tray or menu could not be created');
  }
  return (
    tray: tray,
    menu: menu,
    toggle: toggle,
    move: move,
    divider: divider,
    quit: quit,
  );
}

void _listen(
  _Handles h,
  Window window,
  ValueNotifier<bool> expanded,
  ValueNotifier<BarEdge> edge,
) {
  h.toggle.addListener((event) {
    if (event is! MenuItemClickedEvent) return;
    if (window.isVisible) {
      expanded.value = false; // never leave the drawer open behind a hidden bar
      window.hide();
    } else {
      window.show();
    }
    h.toggle.label = toggleLabel(window.isVisible);
  });
  h.move.addListener((event) {
    if (event is! MenuItemClickedEvent) return;
    edge.value = edge.value.other;
    h.move.label = moveLabel(edge.value);
  });
  h.quit.addListener((event) {
    if (event is MenuItemClickedEvent) Application.instance.quit(0);
  });
}

/// A menu-bar item whose menu hides or shows the bar, moves it to the other
/// edge, and quits the app.
void installTray(
  Window window,
  ValueNotifier<bool> expanded,
  ValueNotifier<BarEdge> edge,
) {
  final h = _createHandles();
  _listen(h, window, expanded, edge);
  for (final item in [h.toggle, h.move, h.divider, h.quit]) {
    h.menu.addItem(item);
  }
  _showMark(h.tray);
  h.tray
    ..setTooltip(trayTooltip)
    ..setContextMenu(h.menu)
    ..setContextMenuTrigger(ContextMenuTrigger.clicked);
  // Windows registers the icon with the taskbar only here; macOS status items
  // are visible by default, so the call is a no-op there.
  h.tray.setVisible(true);
  // Windows watches the icon for clicks only once something listens to it;
  // without a listener the context menu trigger above never fires.
  h.tray.addListener((_) {});
  _alive.addAll([h.tray, h.menu, h.toggle, h.move, h.divider, h.quit]);
}

/// macOS draws a text title in the menu bar; Windows draws only an icon.
void _showMark(TrayIcon tray) {
  if (Platform.isMacOS) {
    tray.setTitle(trayTitle);
    return;
  }
  final icon = Image.fromFile(trayIconPath(Platform.resolvedExecutable));
  if (icon == null) throw StateError('the tray icon image could not be loaded');
  tray.icon = icon; // a coloured image: a template would mask it to a square
  _alive.add(icon);
}
