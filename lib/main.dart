import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'fetch_today.dart';
import 'format.dart';
import 'today.dart';

/// Taiwan convention: red is up, green is down. Open question with the owner.
const Color upColor = Color(0xFFC0392B);
const Color downColor = Color(0xFF2F7D3A);
const String sourceLabel = 'Source: TWSE';

void main() => runApp(const ErelasApp());

class ErelasApp extends StatelessWidget {
  const ErelasApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Erelas',
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
      body: Center(
        child: today == null ? _placeholder() : _CloseView(index: today.index),
      ),
    );
  }

  Widget _placeholder() =>
      Text(_error == null ? 'TAIEX …' : 'TAIEX —', style: const TextStyle(fontSize: 32));
}

class _CloseView extends StatelessWidget {
  const _CloseView({required this.index});

  final IndexQuote index;

  @override
  Widget build(BuildContext context) {
    final color = index.change >= 0 ? upColor : downColor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('TAIEX ${formatPrice(index.close)}',
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w600)),
        Text('${formatChange(index.change)}  ${formatMove(index.changePct)}',
            style: TextStyle(fontSize: 20, color: color)),
        Text('${index.date} · $sourceLabel'),
      ],
    );
  }
}
