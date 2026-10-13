// With the keyboard open, the message box must sit above it.
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
import 'package:relay/ui/kit/controls.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  for (final size in const [Size(410, 900), Size(880, 980)]) {
    testWidgets('composer above keyboard ${size.width.toInt()}w', (tester) async {
      SharedPreferences.setMockInitialValues({'setup_done': true, 'tips_done': true, 'server_url': 'https://x.trycloudflare.com'});
      FlutterSecureStorage.setMockInitialValues({'server_password': 'pw'});
      const dpr = 2.5;
      tester.view.physicalSize = size * dpr;
      tester.view.devicePixelRatio = dpr;
      tester.view.padding = const FakeViewPadding(top: 40 * dpr, bottom: 24 * dpr);
      tester.view.viewPadding = const FakeViewPadding(top: 40 * dpr, bottom: 24 * dpr);
      final settings = await Settings.load();
      final store = Store(settings)..conn = Conn.online;
      store.chats = [Chat.fromJson({'guid': 'iMessage;+;chat1', 'style': 43, 'displayName': 'The Boys'})];
      await tester.pumpWidget(RelayApp(settings: settings, store: store));
      await tester.pump(const Duration(seconds: 1));
      ui.openChat.value = 'iMessage;+;chat1';
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      const kb = 340.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: kb * dpr);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final field = find.byType(SkField).last;
      final bottom = tester.getBottomLeft(field).dy;
      // ignore: avoid_print
      print('KB ${size.width}w: field bottom=$bottom keyboard top=${size.height - kb}');
      expect(bottom, lessThanOrEqualTo(size.height - kb), reason: 'message box is hidden behind the keyboard');
      ui.openChat.value = null;
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      tester.view.reset();
    });
  }
}
