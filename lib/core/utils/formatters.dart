/// Human-friendly formatting for bytes, speeds, durations and timestamps.
class Fmt {
  Fmt._();

  static const _units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];

  static String bytes(num value, {int decimals = 1}) {
    var v = value.toDouble();
    if (v < 1) return '0 B';
    var i = 0;
    while (v >= 1024 && i < _units.length - 1) {
      v /= 1024;
      i++;
    }
    final d = i == 0 ? 0 : decimals;
    return '${v.toStringAsFixed(d)} ${_units[i]}';
  }

  static String speed(num bytesPerSec) => '${bytes(bytesPerSec)}/s';

  static String duration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  /// "только что", "5 мин назад", "2 ч назад", "3 дн назад".
  static String relative(DateTime? time) {
    if (time == null) return 'никогда';
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 45) return 'только что';
    if (diff.inMinutes < 60) return '${diff.inMinutes} мин назад';
    if (diff.inHours < 24) return '${diff.inHours} ч назад';
    return '${diff.inDays} дн назад';
  }

  static String date(DateTime? time) {
    if (time == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(time.day)}.${two(time.month)}.${time.year}';
  }

  static String latency(int? ms) {
    if (ms == null) return '— ms';
    if (ms < 0) return 'н/д';
    return '$ms ms';
  }
}
