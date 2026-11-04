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

/// A menu-bar item whose menu hides or shows the bar, and quits the app.
void installTray(Window window) {
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
  toggle.addListener((event) {
    if (event is! MenuItemClickedEvent) return;
    if (window.isVisible) {
      window.hide();
    } else {
      window.show();
    }
    toggle.label = toggleLabel(window.isVisible);
  });
  quit.addListener((event) {
    if (event is MenuItemClickedEvent) Application.instance.quit(0);
  });
  for (final item in [toggle, divider, quit]) {
    menu.addItem(item);
  }
  tray
    ..setTitle(trayTitle)
    ..setTooltip(trayTooltip)
    ..setContextMenu(menu)
    ..setContextMenuTrigger(ContextMenuTrigger.clicked);
  _alive.addAll([tray, menu, toggle, divider, quit]);
}
