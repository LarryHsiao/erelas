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
