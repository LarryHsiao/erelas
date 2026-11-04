/// The v1 contract published at docs/today.json (see docs/today-contract.md).
const int supportedContractVersion = 1;

class Quote {
  const Quote({
    required this.name,
    required this.close,
    required this.change,
    required this.changePct,
  });

  factory Quote.fromJson(Map<String, dynamic> json) => Quote(
        name: json['name'] as String,
        close: (json['close'] as num).toDouble(),
        change: (json['change'] as num).toDouble(),
        changePct: (json['changePct'] as num).toDouble(),
      );

  final String name;
  final double close;
  final double change;
  final double changePct;
}

class IndexQuote extends Quote {
  const IndexQuote({
    required this.date,
    required super.name,
    required super.close,
    required super.change,
    required super.changePct,
  });

  factory IndexQuote.fromJson(Map<String, dynamic> json) {
    final quote = Quote.fromJson(json);
    return IndexQuote(
      date: json['date'] as String,
      name: quote.name,
      close: quote.close,
      change: quote.change,
      changePct: quote.changePct,
    );
  }

  final String date;
}

class Today {
  const Today({
    required this.index,
    required this.ticker,
    required this.asOf,
    this.topic,
  });

  factory Today.fromJson(Map<String, dynamic> json) {
    if (json['v'] != supportedContractVersion) {
      throw FormatException('unsupported contract version ${json['v']}');
    }
    final items = (json['ticker'] as Map<String, dynamic>)['items'] as List;
    return Today(
      index: IndexQuote.fromJson(json['index'] as Map<String, dynamic>),
      ticker: [
        for (final item in items) Quote.fromJson(item as Map<String, dynamic>),
      ],
      asOf: json['asOf'] as String,
      topic: json['topic'] as Map<String, dynamic>?,
    );
  }

  final IndexQuote index;
  final List<Quote> ticker;
  final String asOf;

  /// Reserved: null until a lead is published (see the contract).
  final Map<String, dynamic>? topic;
}
