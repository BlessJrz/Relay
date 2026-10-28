// The Google Messages-style home screen and chat backgrounds, in every design
// and both fold states: scrolls the chat list (Material's big title shrinks
// and snaps back when let go early), then opens a chat that has a background
// photo. Fails on any build/layout error.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:relay/api/models.dart';
import 'package:relay/main.dart';
import 'package:relay/state/settings.dart';
import 'package:relay/state/store.dart';
import 'package:relay/state/ui_state.dart';

const _dm = 'iMessage;-;+15551234567';
// A 1x1 PNG.
const _png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

Future<void> _frames(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  for (final design in DesignId.values) {
    for (final size in const [Size(410, 900), Size(880, 980)]) {
      testWidgets('home + background ${design.name} ${size.width.toInt()}w', (tester) async {
        final errors = <String>[];
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          final s = d.exceptionAsString();
          if (s.contains('google_fonts') || s.contains('GoogleFonts') || s.contains('allowRuntimeFetching')) return;
          errors.add('${d.exceptionAsString()}\n${d.context}\n${d.stack.toString().split('\n').take(25).join('\n')}');
        };

        // A fake app folder holding the chat's background photo.
        final tmp = Directory.systemTemp.createTempSync('relay_bg');
        Directory('${tmp.path}/avatars').createSync();
        File('${tmp.path}/avatars/w_test.png').writeAsBytesSync(base64Decode(_png));
        const channel = MethodChannel('plugins.flutter.io/path_provider');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => tmp.path);

        SharedPreferences.setMockInitialValues({
          'setup_done': true,
          'tips_done': true,
          'design': design.name,
          'server_url': 'https://example.trycloudflare.com',
          'chat_backgrounds': jsonEncode({_dm: 'w_test.png'}),
        });
        FlutterSecureStorage.setMockInitialValues({'server_password': 'pw'});
        tester.view.physicalSize = size * 2.5;
        tester.view.devicePixelRatio = 2.5;
        final settings = await Settings.load();
        final store = Store(settings);
        await tester.runAsync(() => store.avatars.init());
        // Only the photo store needs the fake folder (fonts look for one too).
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
        store.conn = Conn.online;
        final now = DateTime.now().millisecondsSinceEpoch;
        store.chats = [
          Chat.fromJson({
            'guid': _dm,
            'style': 45,
            'displayName': 'Sam',
            'participants': [{'address': '+15551234567'}],
            'lastMessage': {'guid': 'm-dm', 'text': 'hey', 'isFromMe': false, 'dateCreated': now, 'handle': {'address': '+15551234567'}, 'attachments': []},
          }),
          for (var i = 0; i < 24; i++)
            Chat.fromJson({
              'guid': 'iMessage;+;chat$i',
              'style': 43,
              'displayName': 'Group $i',
              'participants': [{'address': '+1555000${1000 + i}'}, {'address': '+1555111${1000 + i}'}],
              'lastMessage': {'guid': 'm-$i', 'text': 'message $i', 'isFromMe': i.isEven, 'dateCreated': now - (i + 1) * 3600000, 'handle': {'address': '+1555000${1000 + i}'}, 'attachments': []},
            }),
        ];
        expect(store.avatars.hasBackground(_dm), isTrue, reason: 'background photo not found');

        await tester.pumpWidget(RelayApp(settings: settings, store: store));
        await _frames(tester, 20);

        // Scroll a little and let go: Material's big title springs back open.
        final list = find.byType(CustomScrollView).first;
        final pos = tester.state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable)).first).position;
        final g = await tester.startGesture(tester.getCenter(list));
        for (var i = 0; i < 6; i++) {
          await g.moveBy(const Offset(0, -10));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump(const Duration(milliseconds: 400)); // hold still, so it isn't a fling
        await g.up();
        await _frames(tester, 12);
        final afterSmall = pos.pixels;

        // A long scroll: the title shrinks into the bar, then back to the top.
        await tester.drag(list, const Offset(0, -700));
        await _frames(tester, 20);
        await tester.drag(list, const Offset(0, 1400));
        await _frames(tester, 20);

        // Open the chat with the background photo.
        ui.openChat.value = _dm;
        await _frames(tester, 50);
        final photos = find
            .byWidgetPredicate((w) => w is Image && w.image is ResizeImage && (w.image as ResizeImage).imageProvider is FileImage && (w.image as ResizeImage).height != null)
            .evaluate()
            .length;

        ui.openChat.value = null;
        if (size.width < 700) {
          tester.state<NavigatorState>(find.byType(Navigator).first).popUntil((r) => r.isFirst);
        }
        await _frames(tester, 12);

        FlutterError.onError = prev;
        if (errors.isNotEmpty) fail(errors.toSet().join('\n----------\n'));
        if (design == DesignId.material) expect(afterSmall, lessThan(1), reason: 'big title should snap back open');
        expect(photos, greaterThan(0), reason: 'chat background photo not shown');
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 2));
        tester.view.resetPhysicalSize();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
    }
  }
}
