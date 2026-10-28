// Opens the camera + recent photos screen in every design and both fold
// states. There's no real camera or photo library in tests, so this checks the
// layout and the "couldn't start" / "allow photos" fallbacks don't break.
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:relay/main.dart';
import 'package:relay/state/settings.dart';
import 'package:relay/state/store.dart';
import 'package:relay/ui/screens/camera_sheet.dart';
import 'package:relay/ui/shell.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  for (final design in DesignId.values) {
    for (final size in const [Size(410, 900), Size(880, 980)]) {
      testWidgets('camera sheet ${design.name} ${size.width.toInt()}w', (tester) async {
        final errors = <String>[];
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          final s = d.exceptionAsString();
          if (s.contains('google_fonts') || s.contains('GoogleFonts') || s.contains('allowRuntimeFetching')) return;
          errors.add('${d.exceptionAsString()}\n${d.context}\n${d.stack.toString().split('\n').take(20).join('\n')}');
        };
        SharedPreferences.setMockInitialValues({'setup_done': true, 'tips_done': true, 'design': design.name, 'server_url': 'https://example.trycloudflare.com'});
        FlutterSecureStorage.setMockInitialValues({'server_password': 'pw'});
        tester.view.physicalSize = size * 2.5;
        tester.view.devicePixelRatio = 2.5;
        final settings = await Settings.load();
        final store = Store(settings)..conn = Conn.online;
        await tester.pumpWidget(RelayApp(settings: settings, store: store));
        await tester.pump(const Duration(milliseconds: 500));

        final ctx = tester.element(find.byType(Shell));
        final result = showCameraSheet(ctx);
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 60));
        }
        final shown = find.byType(CameraSheet).evaluate().length;
        final close = find.bySemanticsLabel('Close').evaluate().length;
        // Close it again.
        Navigator.of(tester.element(find.byType(CameraSheet))).pop();
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 60));
        }
        FlutterError.onError = prev;
        if (errors.isNotEmpty) fail(errors.toSet().join('\n----------\n'));
        expect(shown, 1, reason: 'camera screen did not open');
        expect(close, greaterThan(0), reason: 'close button missing');
        expect(await result, isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        tester.view.resetPhysicalSize();
      });
    }
  }
}
