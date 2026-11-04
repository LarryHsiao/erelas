import 'package:flutter/material.dart';

import 'bar_view.dart';
import 'format.dart';
import 'today.dart';

const String crawlLabel = '今日焦點';
const double crawlSpeed = 60; // logical pixels per second
const double crawlFontSize = 13;
const double crawlMinWidth = 160; // below this the strip is dropped
const Color crawlChipColor = Color(0xFFC0392B);
const String itemMarker = '◆';
const Key crawlBeltKey = Key('crawl-belt');
const Key crawlStaticKey = Key('crawl-static');

TextSpan crawlSpan(List<Quote> items) => TextSpan(children: [
      for (final item in items) ...[
        TextSpan(text: '$itemMarker ${item.name} ${formatPrice(item.close)} '),
        TextSpan(
          text: '${formatMove(item.changePct)}   ',
          style: TextStyle(color: item.change >= 0 ? upColor : downColor),
        ),
      ],
    ]);

/// A TV-style strip: a fixed label chip and a looping belt of index moves.
/// With reduced motion the belt stands still and ellipsises instead.
class Crawl extends StatefulWidget {
  const Crawl({super.key, required this.items});

  final List<Quote> items;

  @override
  State<Crawl> createState() => _CrawlState();
}

class _CrawlState extends State<Crawl> with SingleTickerProviderStateMixin {
  late final AnimationController _belt = AnimationController(vsync: this);
  double _span = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configure();
  }

  @override
  void didUpdateWidget(Crawl old) {
    super.didUpdateWidget(old);
    _configure();
  }

  @override
  void dispose() {
    _belt.dispose();
    super.dispose();
  }

  TextStyle get _style => DefaultTextStyle.of(context)
      .style
      .copyWith(fontSize: crawlFontSize);

  void _configure() {
    if (MediaQuery.disableAnimationsOf(context) || widget.items.isEmpty) {
      _belt.stop();
      return;
    }
    final painter = TextPainter(
      text: TextSpan(style: _style, children: [crawlSpan(widget.items)]),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    _span = painter.width;
    painter.dispose();
    final millis = (_span / crawlSpeed * 1000).round();
    _belt.duration = Duration(milliseconds: millis < 1 ? 1 : millis);
    _belt.repeat(); // continues from the current value, at the new period
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (_, box) => box.maxWidth < crawlMinWidth
          ? const SizedBox.shrink()
          : Row(children: [
              Container(
                color: crawlChipColor,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: const Text(crawlLabel,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              ),
              const SizedBox(width: 8),
              Expanded(child: reduce ? _still() : _moving()),
            ]),
    );
  }

  Widget _still() => Text.rich(crawlSpan(widget.items),
      key: crawlStaticKey,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: _style);

  Widget _moving() {
    final belt = Row(
      key: crawlBeltKey,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 2; i++)
          Text.rich(crawlSpan(widget.items), softWrap: false, style: _style),
      ],
    );
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.centerLeft,
        minWidth: 0,
        maxWidth: double.infinity,
        child: AnimatedBuilder(
          animation: _belt,
          child: belt,
          builder: (_, child) => Transform.translate(
              offset: Offset(-_belt.value * _span, 0), child: child),
        ),
      ),
    );
  }
}
