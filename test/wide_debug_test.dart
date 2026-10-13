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
import 'package:relay/ui/screens/chat_list.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  testWidgets('narrow open chat debug', (tester) async {
    final errs = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) => errs.add(d.toString().split('\n').take(60).join('\n'));
    SharedPreferences.setMockInitialValues({'setup_done': true, 'tips_done': true, 'server_url': 'https://x.trycloudflare.com'});
    FlutterSecureStorage.setMockInitialValues({'server_password': 'pw'});
    tester.view.physicalSize = const Size(410, 900) * 2.5;
    tester.view.devicePixelRatio = 2.5;
    final settings = await Settings.load();
    final store = Store(settings)..conn = Conn.online;
    store.chats = [Chat.fromJson({'guid': 'iMessage;+;chat1', 'style': 43, 'displayName': 'The Boys'})];
    await tester.pumpWidget(RelayApp(settings: settings, store: store));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    ui.openChat.value = 'iMessage;+;chat1';
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      // ignore: avoid_print
      print('DBG frame $i errors so far=${errs.length} routes=${find.byType(ModalBarrier, skipOffstage: false).evaluate().length}');
      final panes = find.byType(ChatListPane, skipOffstage: false).evaluate().toList();
      // ignore: avoid_print
      print('DBG frame $i panes=${panes.length} ${panes.map((e) => '${(e.widget as ChatListPane).groupsOnly} route=${ModalRoute.of(e)?.settings} hash=${e.hashCode}').join(' ; ')}');
    }
    FlutterError.onError = prev;
    // ignore: avoid_print
    print('DBG errors:\n${errs.join('\n=====\n')}');
  });
}
