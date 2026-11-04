import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:nativeapi/nativeapi.dart'
    show
        Application,
        ContextMenuTrigger,
        Menu,
        MenuItem,
        MenuItemClickedEvent,
        MenuItemType,
        TrayIcon;
import 'package:window_manager/window_manager.dart' show Window;

const String trayTitle = '◆';
const String trayTooltip = 'Erelas';
const String quitLabel = 'Quit Erelas';

String toggleLabel(bool barVisible) => barVisible ? 'Hide bar' : 'Show bar';

/// Native handles must outlive [installTray] or the menu-bar item vanishes.
final List<Object> _alive = [];

typedef _Handles = ({
  TrayIcon tray,
  Menu menu,
  MenuItem toggle,
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
  final divider = MenuItem.createWithLabelAndType('', MenuItemType.separator);
  final quit = MenuItem.createWithLabelAndType(quitLabel, MenuItemType.normal);
  if (tray == null ||
      menu == null ||
      toggle == null ||
      divider == null ||
      quit == null) {
    throw StateError('the native tray or menu could not be created');
  }
  return (tray: tray, menu: menu, toggle: toggle, divider: divider, quit: quit);
}

void _listen(_Handles h, Window window, ValueNotifier<bool> expanded) {
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
  h.quit.addListener((event) {
    if (event is MenuItemClickedEvent) Application.instance.quit(0);
  });
}

/// A menu-bar item whose menu hides or shows the bar, and quits the app.
void installTray(Window window, ValueNotifier<bool> expanded) {
  final h = _createHandles();
  _listen(h, window, expanded);
  for (final item in [h.toggle, h.divider, h.quit]) {
    h.menu.addItem(item);
  }
  h.tray
    ..setTitle(trayTitle)
    ..setTooltip(trayTooltip)
    ..setContextMenu(h.menu)
    ..setContextMenuTrigger(ContextMenuTrigger.clicked);
  _alive.addAll([h.tray, h.menu, h.toggle, h.divider, h.quit]);
}
