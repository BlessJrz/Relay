// Photos with a message: what you attach waits in a tray above the text box,
// can be taken off again, and goes out together with what you typed, in
// every design and both fold states. Fails on any build/layout error.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:relay/api/bb_api.dart';
import 'package:relay/api/models.dart';
import 'package:relay/main.dart';
import 'package:relay/state/settings.dart';
import 'package:relay/state/store.dart';
import 'package:relay/state/ui_state.dart';
import 'package:relay/ui/screens/conversation.dart';

const _dm = 'iMessage;-;+15551234567';
// A 1x1 PNG.
const _png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

Future<void> _frames(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 60));
  }
}

Finder _labelled(String label) => find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label);
Finder _removeButtons() => find.byWidgetPredicate((w) => w is Semantics && (w.properties.label ?? '').startsWith('Remove '));

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  for (final design in DesignId.values) {
    for (final size in const [Size(410, 900), Size(880, 980)]) {
      testWidgets('attach + message ${design.name} ${size.width.toInt()}w', (tester) async {
        final errors = <String>[];
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          final s = d.exceptionAsString();
          if (s.contains('google_fonts') || s.contains('GoogleFonts') || s.contains('allowRuntimeFetching')) return;
          errors.add('${d.exceptionAsString()}\n${d.context}\n${d.stack.toString().split('\n').take(25).join('\n')}');
        };
        final tmp = Directory.systemTemp.createTempSync('relay_attach');
        final photo = File('${tmp.path}${Platform.pathSeparator}beach.png')..writeAsBytesSync(base64Decode(_png));
        final video = File('${tmp.path}${Platform.pathSeparator}clip.mp4')..writeAsBytesSync([0, 1, 2]);
        final doc = File('${tmp.path}${Platform.pathSeparator}notes.pdf')..writeAsBytesSync([0, 1, 2]);

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
        // No Mac here: sends fail, but the bubbles and their order still show.
        store.api = BBApi(serverUrl: 'https://example.trycloudflare.com', password: 'pw');
        final now = DateTime.now().millisecondsSinceEpoch;
        store.chats = [
          Chat.fromJson({
            'guid': _dm,
            'style': 45,
            'displayName': 'Sam',
            'participants': [{'address': '+15551234567'}],
            'lastMessage': {'guid': 'm-dm', 'text': 'hey', 'isFromMe': false, 'dateCreated': now - 60000, 'handle': {'address': '+15551234567'}, 'attachments': []},
          }),
        ];
        await tester.pumpWidget(RelayApp(settings: settings, store: store));
        await _frames(tester, 20);
        ui.openChat.value = _dm;
        await _frames(tester, 50);

        // Nothing attached: the button records a voice message.
        final micFirst = _labelled('Record a voice message').evaluate().length;

        ConversationPane.debugAttach(_dm, [photo, video, doc]);
        await _frames(tester, 8);
        final trayFull = _removeButtons().evaluate().length;
        final canSendPhotosOnly = _labelled('Send (hold to send later)').evaluate().length;

        // Take the video off again.
        await tester.tap(_labelled('Remove clip.mp4'), warnIfMissed: false);
        await _frames(tester, 8);
        final trayAfterRemove = ConversationPane.debugAttached(_dm).map((f) => f.path.split(Platform.pathSeparator).last).toList();

        // Add a message and send the lot.
        await tester.enterText(find.byType(EditableText).last, 'look at this');
        await _frames(tester, 4);
        await tester.tap(_labelled('Send (hold to send later)'), warnIfMissed: false);
        await _frames(tester, 30);
        final sentNow = store.messagesFor(_dm).where((m) => m.isFromMe).toList();
        final trayAfterSend = ConversationPane.debugAttached(_dm).length;
        final boxAfterSend = tester.widget<EditableText>(find.byType(EditableText).last).controller.text;
        final trayGone = _removeButtons().evaluate().length;

        ui.openChat.value = null;
        if (size.width < 700) {
          tester.state<NavigatorState>(find.byType(Navigator).first).popUntil((r) => r.isFirst);
        }
        await _frames(tester, 12);

        FlutterError.onError = prev;
        if (errors.isNotEmpty) fail(errors.toSet().join('\n----------\n'));
        expect(micFirst, 1, reason: 'an empty composer should offer the microphone');
        expect(trayFull, 3, reason: 'all three attachments should show in the tray');
        expect(canSendPhotosOnly, 1, reason: 'attachments alone should be sendable');
        expect(trayAfterRemove, ['beach.png', 'notes.pdf'], reason: 'the removed one should be gone, the rest in order');
        expect(sentNow.length, 3, reason: 'two attachments and the message');
        // Newest first: the message, then the files in the order attached.
        expect(sentNow[0].text, 'look at this');
        expect(sentNow[1].attachments.single.transferName, 'notes.pdf');
        expect(sentNow[2].attachments.single.transferName, 'beach.png');
        expect(trayAfterSend, 0, reason: 'the tray empties on send');
        expect(trayGone, 0);
        expect(boxAfterSend, '', reason: 'the text box empties on send');

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 2));
        // The uploads never finish here (no Mac): let each one's timeout run
        // out, so the test doesn't end with their timers still pending.
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(minutes: 4));
        }
        tester.view.resetPhysicalSize();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
    }
  }
}
