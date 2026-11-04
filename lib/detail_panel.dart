import 'package:flutter/material.dart';

import 'bar_view.dart';
import 'format.dart';
import 'today.dart';

const double detailHeight = 170;
const double tickerCellWidth = 240;
const Key tickerListKey = Key('ticker-list');

/// The drawer under the bar: the index detail and the full ticker list.
class DetailPanel extends StatelessWidget {
  const DetailPanel({super.key, required this.today});

  final Today today;

  @override
  Widget build(BuildContext context) {
    final index = today.index;
    return Container(
      height: detailHeight,
      width: double.infinity,
      color: barColor,
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(index),
            Text('Index close · ${index.date}'),
            const Text(sourceLabel),
            Text(
              'Updated ${formatAsOf(today.asOf)}',
              style: const TextStyle(color: mutedColor),
            ),
            if (today.ticker.isNotEmpty) _list(),
          ],
        ),
      ),
    );
  }

  Widget _header(IndexQuote index) => Wrap(
    spacing: 14,
    crossAxisAlignment: WrapCrossAlignment.end,
    children: [
      Text(
        formatPrice(index.close),
        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
      ),
      Text(
        '${formatChange(index.change)}  ${formatMove(index.changePct)}',
        style: TextStyle(
          fontSize: 16,
          color: index.change >= 0 ? upColor : downColor,
        ),
      ),
    ],
  );

  Widget _list() => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Wrap(
      key: tickerListKey,
      spacing: 24,
      runSpacing: 4,
      children: [for (final item in today.ticker) _Cell(item: item)],
    ),
  );
}

class _Cell extends StatelessWidget {
  const _Cell({required this.item});

  final Quote item;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: tickerCellWidth,
    child: Row(
      children: [
        Expanded(
          child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        Text(formatPrice(item.close)),
        const SizedBox(width: 8),
        Text(
          formatMove(item.changePct),
          style: TextStyle(color: item.change >= 0 ? upColor : downColor),
        ),
      ],
    ),
  );
}
