import 'package:erelas/bar_view.dart';
import 'package:erelas/crawl.dart';
import 'package:erelas/today.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const items = [
  Quote(name: '半導體類指數', close: 1446.44, change: -45.17, changePct: -3.03),
  Quote(name: '水泥窯製類指數', close: 692.91, change: 7.23, changePct: 1.05),
];

Future<void> pumpCrawl(WidgetTester tester,
    {bool reduceMotion = false, double width = 400}) async {
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(
        body: SizedBox(
            width: width, height: barHeight, child: const Crawl(items: items)),
      ),
    ),
  ));
}

double beltLeft(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(crawlBeltKey)).dx;

void main() {
  testWidgets('with less room than the chip needs it draws nothing', (tester) async {
    await pumpCrawl(tester, width: crawlMinWidth - 1);
    expect(find.text(crawlLabel), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the label chip', (tester) async {
    await pumpCrawl(tester);
    expect(find.text(crawlLabel), findsOneWidget);
  });

  testWidgets('shows every item with its close and move', (tester) async {
    await pumpCrawl(tester);
    final text = tester.widgetList<RichText>(find.byType(RichText))
        .map((w) => w.text.toPlainText())
        .join(' ');
    for (final expected in ['半導體類指數 1,446.44 ▼3.03%', '水泥窯製類指數 692.91 ▲1.05%']) {
      expect(text, contains(expected));
    }
  });

  testWidgets('the belt moves left over time', (tester) async {
    await pumpCrawl(tester);
    final before = beltLeft(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(beltLeft(tester), lessThan(before));
  });

  testWidgets('the belt wraps back to the start, so it loops with no gap',
      (tester) async {
    await pumpCrawl(tester);
    var previous = beltLeft(tester);
    var wrapped = false;
    for (var i = 0; i < 60 && !wrapped; i++) {
      await tester.pump(const Duration(seconds: 1));
      final now = beltLeft(tester);
      wrapped = now > previous;
      previous = now;
    }
    expect(wrapped, isTrue);
  });

  testWidgets('with reduced motion nothing moves and text ellipsises',
      (tester) async {
    await pumpCrawl(tester, reduceMotion: true);
    expect(find.byKey(crawlBeltKey), findsNothing);
    final text = tester.widget<Text>(find.byKey(crawlStaticKey));
    expect(text.overflow, TextOverflow.ellipsis);
    expect(text.maxLines, 1);
  });

  testWidgets('a disposed crawl leaves no running ticker', (tester) async {
    await pumpCrawl(tester);
    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.transientCallbackCount, 0);
  });
}
