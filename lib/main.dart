import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:window_manager/window_manager.dart' show WindowBlurredEvent;

import 'bar_tray.dart';
import 'bar_view.dart';
import 'bar_window.dart';
import 'detail_panel.dart';
import 'fetch_today.dart';
import 'today.dart';

const Duration refreshInterval = Duration(minutes: 15);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final window = configureBarWindow();
  final expanded = ValueNotifier(false);
  final edge = ValueNotifier(BarEdge.top);
  try {
    installTray(window, expanded, edge);
  } catch (error) {
    debugPrint('tray item unavailable, giving the bar its frame back: $error');
    restoreFrame(window);
  }
  expanded.addListener(
    () => resizeBar(window, expanded: expanded.value, edge: edge.value),
  );
  edge.addListener(() => moveBar(window, edge.value, expanded: expanded.value));
  window.addListener((event) {
    if (event is WindowBlurredEvent) expanded.value = false;
  });
  runApp(ErelasApp(expanded: expanded, edge: edge));
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
