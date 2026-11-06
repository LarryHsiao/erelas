import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferencesAsync;
import 'package:window_manager/window_manager.dart'
    show Window, WindowBlurredEvent, WindowMovedEvent;

import 'bar_edge_store.dart';
import 'bar_tray.dart';
import 'bar_view.dart';
import 'bar_window.dart';
import 'detail_panel.dart';
import 'fetch_today.dart';
import 'today.dart';

const Duration refreshInterval = Duration(minutes: 15);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = BarEdgeStore(SharedPreferencesAsync());
  final edge = ValueNotifier(await store.load());
  final window = configureBarWindow(edge.value);
  final expanded = ValueNotifier(false);
  final docked = _tryInstallTray(window, expanded, edge);
  expanded.addListener(
    () => resizeBar(window, expanded: expanded.value, edge: edge.value),
  );
  edge.addListener(() {
    moveBar(window, edge.value, expanded: expanded.value);
    store.save(edge.value);
  });
  window.addListener((event) {
    if (event is WindowBlurredEvent) expanded.value = false;
    // After launch macOS moves the window off the top edge it was given; put
    // it back wherever it was meant to be. Only a frameless bar can be docked.
    if (event is WindowMovedEvent && docked) {
      moveBar(window, edge.value, expanded: expanded.value);
    }
  });
  runApp(ErelasApp(expanded: expanded, edge: edge));
}

/// Whether the tray stands. Without it the bar gets its frame back, so it has
/// a close button and is no longer docked.
bool _tryInstallTray(
  Window window,
  ValueNotifier<bool> expanded,
  ValueNotifier<BarEdge> edge,
) {
  try {
    installTray(window, expanded, edge);
    return true;
  } catch (error) {
    debugPrint('tray item unavailable, giving the bar its frame back: $error');
    restoreFrame(window);
    return false;
  }
}

class ErelasApp extends StatelessWidget {
  const ErelasApp({super.key, required this.expanded, required this.edge});

  final ValueNotifier<bool> expanded;
  final ValueNotifier<BarEdge> edge;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Erelas',
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: TodayPage(expanded: expanded, edge: edge),
  );
}

Future<Today> _fetchLive() async {
  final client = http.Client();
  try {
    return await fetchToday(client, todayUrl);
  } finally {
    client.close();
  }
}

class TodayPage extends StatefulWidget {
  const TodayPage({
    super.key,
    this.load = _fetchLive,
    required this.expanded,
    required this.edge,
  });

  final Future<Today> Function() load;

  /// Whether the detail drawer is open. Owned by the caller, who also sizes
  /// the window to match.
  final ValueNotifier<bool> expanded;

  /// The edge the bar is docked to. The drawer opens away from it.
  final ValueNotifier<BarEdge> edge;

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  Today? _today;
  Object? _error;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _load();
    _refresh = Timer.periodic(refreshInterval, (_) => _load());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final today = await widget.load();
      if (mounted) setState(() => _today = today);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = _today;
    return Scaffold(
      backgroundColor: barColor,
      body: today == null
          ? ListenableBuilder(
              listenable: widget.edge,
              builder: (_, _) => Align(
                alignment: widget.edge.value == BarEdge.top
                    ? Alignment.topCenter
                    : Alignment.bottomCenter,
                child: _placeholder(),
              ),
            )
          : ListenableBuilder(
              listenable: Listenable.merge([widget.expanded, widget.edge]),
              builder: (_, _) {
                final open = widget.expanded.value;
                final bar = BarView(
                  today: today,
                  onTap: () => widget.expanded.value = !open,
                );
                final drawer = open ? DetailPanel(today: today) : null;
                final atTop = widget.edge.value == BarEdge.top;
                return Column(
                  mainAxisAlignment: atTop
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.end,
                  children: atTop ? [bar, ?drawer] : [?drawer, bar],
                );
              },
            ),
    );
  }

  Widget _placeholder() => Container(
    height: barHeight,
    color: barColor,
    padding: const EdgeInsets.symmetric(horizontal: barPadding),
    child: Row(
      children: [
        Text(
          _error == null ? '$indexLabel …' : '$indexLabel —',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        const Text(
          sourceLabel,
          style: TextStyle(fontSize: 11, color: mutedColor),
        ),
      ],
    ),
  );
}
