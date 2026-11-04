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
  try {
    installTray(window, expanded);
  } catch (error) {
    debugPrint('tray item unavailable, giving the bar its frame back: $error');
    restoreFrame(window);
  }
  expanded.addListener(() => resizeBar(window, expanded: expanded.value));
  window.addListener((event) {
    if (event is WindowBlurredEvent) expanded.value = false;
  });
  runApp(ErelasApp(expanded: expanded));
}

class ErelasApp extends StatelessWidget {
  const ErelasApp({super.key, required this.expanded});

  final ValueNotifier<bool> expanded;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Erelas',
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: TodayPage(expanded: expanded),
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
  const TodayPage({super.key, this.load = _fetchLive, required this.expanded});

  final Future<Today> Function() load;

  /// Whether the detail drawer is open. Owned by the caller, who also sizes
  /// the window to match.
  final ValueNotifier<bool> expanded;

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
          ? Align(alignment: Alignment.topCenter, child: _placeholder())
          : ValueListenableBuilder<bool>(
              valueListenable: widget.expanded,
              builder: (_, open, _) => Column(
                children: [
                  BarView(
                    today: today,
                    onTap: () => widget.expanded.value = !open,
                  ),
                  if (open) DetailPanel(today: today),
                ],
              ),
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
