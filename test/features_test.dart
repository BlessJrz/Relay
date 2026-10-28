// Small pieces of logic behind the quality-of-life features.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:relay/state/schedule.dart';
import 'package:relay/state/settings.dart';

void main() {
  test('send-later presets are all in the future and sensible', () {
    final morning = DateTime(2026, 10, 27, 9, 15);
    final p = schedulePresets(morning);
    expect(p.map((e) => e.$1), ['In 1 hour', 'Tonight at 8 PM', 'Tomorrow at 9 AM']);
    for (final (_, at) in p) {
      expect(at.isAfter(morning), true);
    }
    // Late evening: no "tonight".
    final late = schedulePresets(DateTime(2026, 10, 27, 21, 40));
    expect(late.map((e) => e.$1), ['In 1 hour', 'Tomorrow at 9 AM']);
    expect(late.last.$2, DateTime(2026, 10, 28, 9));
  });

  test('schedule labels read naturally', () {
    final now = DateTime(2026, 10, 27, 9);
    expect(scheduleLabel(DateTime(2026, 10, 27, 20), now), 'today at 8:00 PM');
    expect(scheduleLabel(DateTime(2026, 10, 28, 9, 5), now), 'tomorrow at 9:05 AM');
    expect(scheduleLabel(DateTime(2026, 11, 2, 0, 30), now), '11/2 at 12:30 AM');
  });

  test('"New messages" line goes above the oldest unread message', () {
    // newest first: (fromMe, date)
    final msgs = [(false, 900), (false, 800), (true, 700), (false, 500), (false, 400)];
    expect(firstUnreadIndex(msgs, 600, (m) => m.$1, (m) => m.$2), 1);
    expect(firstUnreadIndex(msgs, 950, (m) => m.$1, (m) => m.$2), -1, reason: 'all read');
    expect(firstUnreadIndex(msgs, 0, (m) => m.$1, (m) => m.$2), -1, reason: 'never opened: no line');
  });

  test('drafts, mutes and pins are remembered per chat', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final s = await Settings.load();
    s.setDraft('a', 'half a thought');
    s.setDraft('b', '   ');
    expect(s.draftFor('a'), 'half a thought');
    expect(s.draftFor('b'), '');
    s.setDraft('a', '');
    expect(s.draftFor('a'), '');
    s.toggleMute('a');
    expect(s.isMuted('a'), true);
    s.toggleMute('a');
    expect(s.isMuted('a'), false);
    s.togglePin('x');
    expect(s.pinnedChats, ['x']);
    expect(s.pinsSeeded, true);
  });

  test('the server address is saved cleaned up', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final s = await Settings.load();
    await s.saveServer(' my-mac.trycloudflare.com/ ', 'pw');
    expect(s.serverUrl, 'https://my-mac.trycloudflare.com');
    await s.updateServerUrl('https://other.trycloudflare.com/api/v1/');
    expect(s.serverUrl, 'https://other.trycloudflare.com');
  });
}
