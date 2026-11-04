import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'bar_tray.dart';
import 'bar_view.dart';
import 'bar_window.dart';
import 'fetch_today.dart';
import 'today.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final window = configureBarWindow();
  installTray(window);
  runApp(const ErelasApp());
}

class ErelasApp extends StatelessWidget {
  const ErelasApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Erelas',
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: const TodayPage(),
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
  const TodayPage({super.key, this.load = _fetchLive});

  final Future<Today> Function() load;

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
      body: Align(
        alignment: Alignment.topCenter,
        child: today == null ? _placeholder() : BarView(today: today),
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
