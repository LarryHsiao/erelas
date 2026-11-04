import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'bar_tray.dart';
import 'bar_view.dart';
import 'bar_window.dart';
import 'detail_panel.dart';
import 'fetch_today.dart';
import 'today.dart';
import 'package:window_manager/window_manager.dart' show WindowBlurredEvent;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final window = configureBarWindow();
  installTray(window);
  final expanded = ValueNotifier(false);
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

  @override
  void initState() {
    super.initState();
    _load();
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
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Text(
      _error == null ? 'TAIEX …' : 'TAIEX —',
      style: const TextStyle(fontWeight: FontWeight.w600),
    ),
  );
}
