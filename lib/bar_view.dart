import 'package:flutter/material.dart';

import 'format.dart';
import 'today.dart';

const double barHeight = 36;
const Color barColor = Color(0xFF1B1B1F);
/// Taiwan convention: red is up, green is down. Open question with the owner.
const Color upColor = Color(0xFFC0392B);
const Color downColor = Color(0xFF2F7D3A);
const String sourceLabel = 'Source: TWSE';

class BarView extends StatelessWidget {
  const BarView({super.key, required this.today});

  final Today today;

  @override
  Widget build(BuildContext context) {
    final index = today.index;
    final color = index.change >= 0 ? upColor : downColor;
    return Container(
      height: barHeight,
      color: barColor,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Text('TAIEX ${formatPrice(index.close)}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          Text('${formatChange(index.change)}  ${formatMove(index.changePct)}',
              style: TextStyle(color: color)),
          const SizedBox(width: 10),
          Expanded(
            child: Text('${index.date} · $sourceLabel',
                textAlign: TextAlign.right,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.white60)),
          ),
        ],
      ),
    );
  }
}
