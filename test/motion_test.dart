// Drives the animations added for smoothness: a chat opening with the slide,
// messages arriving and growing in, the typing dots growing and shrinking,
// and a chat sliding to the top of the list. Fails on any build/layout error.
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:relay/api/models.dart';
import 'package:relay/main.dart';
import 'package:relay/state/settings.dart';
import 'package:relay/state/store.dart';
import 'package:relay/state/ui_state.dart';
import 'package:relay/ui/kit/motion.dart';

const _group = 'iMessage;+;chat1';
const _dm = 'iMessage;-;+15551234567';

var _n = 0;
Map<String, dynamic> _msg(String text, String chat, {bool fromMe = false}) => {
      'guid': 'm-${_n++}-$text',
      'text': text,
      'isFromMe': fromMe,
      'dateCreated': DateTime.now().millisecondsSinceEpoch + _n,
      'handle': {'address': '+15551234567'},
      'attachments': [],
      'chats': [
        {'guid': chat}
      ],
    };

/// Message rows that are still clipped to their growing height.
Finder _clipping({bool skipOffstage = true}) => find.descendant(
      of: find.byType(Arrive, skipOffstage: skipOffstage),
      matching: find.byWidgetPredicate((w) => w is ClipRect && w.clipBehavior != Clip.none, skipOffstage: skipOffstage),
    );

Future<void> _frames(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  for (final design in DesignId.values) {
    for (final size in const [Size(410, 900), Size(880, 980)]) {
      testWidgets('motion ${design.name} ${size.width.toInt()}w', (tester) async {
        final errors = <String>[];
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          final s = d.exceptionAsString();
          if (s.contains('google_fonts') || s.contains('GoogleFonts') || s.contains('allowRuntimeFetching')) return;
          errors.add('${d.exceptionAsString()}\n${d.context}\n${d.stack.toString().split('\n').take(25).join('\n')}');
        };
        SharedPreferences.setMockInitialValues({
          'setup_done': true,
          'tips_done': true,
          'design': design.name,
          'server_url': 'https://example.trycloudflare.com',
        });
        FlutterSecureStorage.setMockInitialValues({'server_password': 'pw'});
        tester.view.physicalSize = size * 2.5;
        tester.view.devicePixelRatio = 2.5;
        final settings = await Settings.load();
        final store = Store(settings);
        store.conn = Conn.online;
        store.chats = [
          Chat.fromJson({'guid': _group, 'style': 43, 'displayName': 'The Boys', 'participants': [{'address': '+15551234567'}, {'address': '+15557654321'}], 'lastMessage': _msg('yo', _group)}),
          Chat.fromJson({'guid': _dm, 'style': 45, 'displayName': 'Sam', 'participants': [{'address': '+15551234567'}], 'lastMessage': _msg('hey', _dm, fromMe: true)}),
        ];
        await tester.pumpWidget(RelayApp(settings: settings, store: store));
        await _frames(tester, 20);

        // Open the group: slides in. There's no Mac here, so the first load
        // gives up after a retry (~1.2 s); messages only grow in after that.
        ui.openChat.value = _group;
        await _frames(tester, 50);

        // Messages arrive while it's open, from them and from me.
        store.debugEvent('new-message', _msg('first one', _group, fromMe: true));
        await _frames(tester, 2);
        store.debugEvent('new-message', _msg('second one', _group));
        await tester.pump(const Duration(milliseconds: 60));
        // It starts at zero height, which the finder counts as off screen.
        final growing = _clipping(skipOffstage: false).evaluate().length;
        await _frames(tester, 3);
        // A reaction lands on the message that just grew in.
        store.debugEvent('new-message', {
          ..._msg('', _group),
          'associatedMessageGuid': 'p:0/${store.messagesFor(_group).firstWhere((m) => m.text == 'second one').guid}',
          'associatedMessageType': 'emphasize',
        });
        await _frames(tester, 10);
        // Rows only clip while growing; afterwards the pill must be free to show.
        final stillClipping = _clipping().evaluate().length;
        final pill = tester.getRect(find.text('‼️').last);
        final pillRow = tester.getRect(find.ancestor(of: find.text('‼️').last, matching: find.byType(Arrive)).last);
        // Typing dots grow in, then a message replaces them.
        store.debugEvent('typing-indicator', {'guid': _group, 'display': true});
        await _frames(tester, 3);
        store.debugEvent('new-message', _msg('third one', _group));
        await _frames(tester, 12);
        expect(find.text('third one'), findsWidgets, reason: 'new message did not show');
        // Your own messages sit on the right, theirs on the left (checked below,
        // once the error handler is back).
        final mine = tester.getRect(find.text('first one').last);
        final theirs = tester.getRect(find.text('second one').last);
        final pane = tester.getRect(find.byType(ListView).last);

        // Something changes in the other chat: it slides to the top of the list.
        store.debugEvent('new-message', _msg('over here', _dm, fromMe: true));
        await _frames(tester, 3);

        // Back to the list.
        ui.openChat.value = null;
        if (size.width < 700) {
          final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
          nav.popUntil((r) => r.isFirst);
        }
        await _frames(tester, 12);
        store.debugEvent('new-message', _msg('back on top', _group, fromMe: true));
        await _frames(tester, 12);

        FlutterError.onError = prev;
        if (errors.isNotEmpty) fail(errors.toSet().join('\n----------\n'));
        expect(growing, greaterThan(0), reason: 'a new message should grow in');
        expect(stillClipping, 0, reason: 'a message that has grown in must not clip its reaction pill');
        expect(pill.top, greaterThanOrEqualTo(pillRow.top), reason: 'the reaction pill must sit inside its row');
        expect(pill.bottom, lessThanOrEqualTo(pillRow.bottom), reason: 'the reaction pill must sit inside its row');
        expect(mine.center.dx, greaterThan(pane.center.dx), reason: 'my message should be on the right');
        expect(theirs.left, lessThan(mine.left), reason: 'their message should be left of mine');
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 2));
        tester.view.resetPhysicalSize();
      });
    }
  }
}
