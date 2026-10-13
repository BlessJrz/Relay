// Renders the main screen (after setup) in every design and both fold states,
// with a couple of chats loaded, and fails on any build/layout/paint error.
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

Map<String, dynamic> _msg(String text, {bool fromMe = false}) => {
      'guid': 'm-$text',
      'text': text,
      'isFromMe': fromMe,
      'dateCreated': DateTime.now().millisecondsSinceEpoch,
      'handle': {'address': '+15551234567'},
      'attachments': [],
    };

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  for (final design in DesignId.values) {
    for (final size in const [Size(880, 980), Size(410, 900)]) {
      for (final dark in [false, true]) {
        testWidgets('shell ${design.name} ${size.width.toInt()}w dark=$dark', (tester) async {
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
            'mode': dark ? 'dark' : 'light',
            'server_url': 'https://example.trycloudflare.com',
          });
          FlutterSecureStorage.setMockInitialValues({'server_password': 'pw'});
          tester.view.physicalSize = size * 2.5;
          tester.view.devicePixelRatio = 2.5;
          final settings = await Settings.load();
          final store = Store(settings);
          store.conn = Conn.online;
          store.chats = [
            Chat.fromJson({'guid': 'iMessage;+;chat1', 'style': 43, 'displayName': 'The Boys', 'participants': [{'address': '+15551234567'}, {'address': '+15557654321'}], 'lastMessage': _msg('yo')}),
            Chat.fromJson({'guid': 'iMessage;-;+15551234567', 'style': 45, 'participants': [{'address': '+15551234567'}], 'lastMessage': _msg('hey', fromMe: true)}),
          ];
          await tester.pumpWidget(RelayApp(settings: settings, store: store));
          for (var i = 0; i < 30; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          // Open a chat and visit each tab.
          ui.openChat.value = 'iMessage;+;chat1';
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          for (final t in [1, 2, 3, 0]) {
            ui.tab.value = t;
            for (var i = 0; i < 8; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
          }
          ui.openChat.value = null;
          await tester.pump(const Duration(seconds: 1));
          FlutterError.onError = prev;
          final shown = find.text('The Boys').evaluate().length;
          // ignore: avoid_print
          print('RESULT ${design.name} ${size.width}w dark=$dark: ${errors.length} errors, chat row found=$shown');
          if (errors.isNotEmpty) fail(errors.toSet().join('\n----------\n'));
          expect(shown, greaterThan(0), reason: 'chat list did not render');
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 2));
          tester.view.resetPhysicalSize();
        });
      }
    }
  }
}
