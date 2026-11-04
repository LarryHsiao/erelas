String formatPrice(double value) {
  final fixed = value.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '${value < 0 ? '-' : ''}$whole.${parts[1]}';
}

String formatMove(double pct) {
  if (pct == 0) return '0.00%';
  final arrow = pct > 0 ? '▲' : '▼';
  return '$arrow${pct.abs().toStringAsFixed(2)}%';
}

String formatChange(double change) {
  if (change == 0) return '0.00';
  final sign = change > 0 ? '+' : '−';
  return '$sign${formatPrice(change.abs())}';
}

final RegExp _isoMinute = RegExp(r'^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2})');

/// "2026-11-04T12:28:23+08:00" → "2026-11-04 12:28"; anything else as given.
String formatAsOf(String asOf) {
  final match = _isoMinute.firstMatch(asOf);
  return match == null ? asOf : '${match[1]} ${match[2]}';
}
