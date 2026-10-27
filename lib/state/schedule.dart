/// Quick choices for "Send later".
List<(String, DateTime)> schedulePresets(DateTime now) {
  final out = <(String, DateTime)>[('In 1 hour', now.add(const Duration(hours: 1)))];
  final tonight = DateTime(now.year, now.month, now.day, 20);
  if (now.isBefore(tonight.subtract(const Duration(minutes: 30)))) out.add(('Tonight at 8 PM', tonight));
  final tomorrow = DateTime(now.year, now.month, now.day + 1, 9);
  out.add(('Tomorrow at 9 AM', tomorrow));
  return out;
}

String scheduleLabel(DateTime at, DateTime now) {
  final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final t = '$h:${at.minute.toString().padLeft(2, '0')} ${at.hour < 12 ? 'AM' : 'PM'}';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'today at $t';
  if (diff == 1) return 'tomorrow at $t';
  return '${at.month}/${at.day} at $t';
}

/// Index (in a newest-first list) of the oldest message that arrived after
/// [lastRead], i.e. where the "New messages" line goes. -1 if none.
int firstUnreadIndex<T>(List<T> newestFirst, int lastRead, bool Function(T) fromMe, int Function(T) date) {
  if (lastRead <= 0) return -1;
  for (var i = newestFirst.length - 1; i >= 0; i--) {
    final m = newestFirst[i];
    if (!fromMe(m) && date(m) > lastRead) return i;
  }
  return -1;
}
