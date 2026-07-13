String formatBitrate(int bitsPerSecond) {
  if (bitsPerSecond >= 1000000000) {
    return '${(bitsPerSecond / 1000000000).toStringAsFixed(2)} Gb/s';
  }
  if (bitsPerSecond >= 1000000) {
    return '${(bitsPerSecond / 1000000).toStringAsFixed(2)} Mb/s';
  }
  if (bitsPerSecond >= 1000) {
    return '${(bitsPerSecond / 1000).toStringAsFixed(0)} kb/s';
  }
  return '$bitsPerSecond b/s';
}

String formatTimestamp(String value) {
  final DateTime? parsed = DateTime.tryParse(value);
  if (parsed == null) {
    return value.isEmpty ? '—' : value;
  }
  final DateTime local = parsed.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
