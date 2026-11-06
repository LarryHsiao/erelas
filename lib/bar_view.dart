import 'package:flutter/material.dart';

import 'crawl.dart';
import 'format.dart';
import 'today.dart';

const double barHeight = 36;
const Color barColor = Color(0xFF1B1B1F);

/// Taiwan convention: red is up, green is down. Open question with the owner.
const Color upColor = Color(0xFFEF5350);
const Color downColor = Color(0xFF4CAF50);
const String sourceLabel = 'Source: TWSE';
const String indexLabel = 'TAIEX';
const double barPadding = 12;
const Color mutedColor = Colors.white60;

class BarView extends StatelessWidget {
  const BarView({super.key, required this.today, this.onTap});

  final Today today;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final index = today.index;
    final color = index.change >= 0 ? upColor : downColor;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: _bar(index, color),
    );
  }

  Widget _bar(IndexQuote index, Color color) => Container(
    height: barHeight,
    color: barColor,
    padding: const EdgeInsets.symmetric(horizontal: barPadding),
    child: Row(
      children: [
        ..._quote(index, color),
        const SizedBox(width: 14),
        _middle(),
        const SizedBox(width: 14),
        _source(index),
      ],
    ),
  );

  List<Widget> _quote(IndexQuote index, Color color) => [
    Text(
      '$indexLabel ${formatPrice(index.close)}',
      style: const TextStyle(fontWeight: FontWeight.w600),
    ),
    const SizedBox(width: 10),
    Text(
      '${formatChange(index.change)}  ${formatMove(index.changePct)}',
      style: TextStyle(color: color),
    ),
  ];

  Widget _middle() => today.ticker.isEmpty
      ? const Spacer()
      : Expanded(child: Crawl(items: today.ticker));

  Widget _source(IndexQuote index) => Text(
    '${index.date} · $sourceLabel',
    style: const TextStyle(fontSize: 11, color: mutedColor),
  );
}
