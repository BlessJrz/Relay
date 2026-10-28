// "Check for updates": a fake GitHub release says Relay-60.apk is out.
// Build 55 should see it; build 60 should be told it's up to date.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:relay/state/updater.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding fakes all HTTP; this test talks to its own local server.
  HttpOverrides.global = null;

  test('finds a newer build on GitHub, and nothing when up to date', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({
        'assets': [
          {'name': 'Relay-58.apk', 'browser_download_url': 'https://x/Relay-58.apk', 'size': 1},
          {'name': 'Relay-60.apk', 'browser_download_url': 'https://x/Relay-60.apk', 'size': 78000000},
          {'name': 'notes.txt', 'browser_download_url': 'https://x/notes.txt', 'size': 3},
        ],
      }));
      req.response.close();
    });
    Updater.releaseUrl = 'http://127.0.0.1:${server.port}/latest';
    const channel = MethodChannel('relay/media');
    final u = Updater.instance;

    var mine = 55;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (c) async => c.method == 'appBuild' ? mine : null);
    final found = await u.check();
    expect(found?.build, 60);
    expect(found?.url, 'https://x/Relay-60.apk');
    expect(u.error, isNull);

    mine = 60;
    u.current = null;
    expect(await u.check(), isNull);
    expect(u.error, isNull);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    await server.close(force: true);
  });
}
