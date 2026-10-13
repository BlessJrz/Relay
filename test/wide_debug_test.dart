import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:relay/main.dart';
import 'package:relay/state/settings.dart';
import 'package:relay/state/store.dart';
import 'package:relay/ui/shell.dart';
import 'package:relay/ui/kit/nav.dart';
import 'package:relay/ui/screens/chat_list.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  testWidgets('wide debug', (tester) async {
    final errs = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) => errs.add(d.exceptionAsString().split('\n').first);
    SharedPreferences.setMockInitialValues({'setup_done': true, 'tips_done': true, 'server_url': 'https://x.trycloudflare.com'});
    FlutterSecureStorage.setMockInitialValues({'server_password': 'pw'});
    tester.view.physicalSize = const Size(880, 980) * 2.5;
    tester.view.devicePixelRatio = 2.5;
    final settings = await Settings.load();
    final store = Store(settings)..conn = Conn.online;
    await tester.pumpWidget(RelayApp(settings: settings, store: store));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    FlutterError.onError = prev;
    void show(String n, Finder f) {
      final els = f.evaluate().toList();
      final sizes = els.map((e) => (e.renderObject is RenderBox) ? (e.renderObject as RenderBox).hasSize ? (e.renderObject as RenderBox).size.toString() : 'nosize' : e.renderObject.runtimeType.toString()).join(', ');
      // ignore: avoid_print
      print('DBG $n: ${els.length} [$sizes]');
    }
    show('Shell', find.byType(Shell));
    show('LayoutBuilder in Shell', find.descendant(of: find.byType(Shell), matching: find.byType(LayoutBuilder)));
    show('SkNavRail', find.byType(SkNavRail));
    show('ChatListPane', find.byType(ChatListPane));
    show('Row in Shell', find.descendant(of: find.byType(Shell), matching: find.byType(Row)));
    show('Text', find.byType(Text));
    // ignore: avoid_print
    print('DBG errors: ${errs.toSet().join(' | ')}');
    // ignore: avoid_print
    print('DBG texts: ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).take(30).join(' / ')}');
  });
}
