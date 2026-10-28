// "Check for updates": a fake GitHub release says Relay-60.apk is out.
// Build 55 should see it; build 60 should be told it's up to date.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:relay/state/updater.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding fakes all HTTP; this test talks to its own local server.
  HttpOverrides.global = null;
  const channel = MethodChannel('relay/media');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // A fake GitHub: /latest is the release, /dl/<name> the APKs.
  late HttpServer server;
  var releaseStatus = 200;
  var assets = <Map<String, Object>>[];
  final apks = <String, List<int>>{};
  String url(String path) => 'http://127.0.0.1:${server.port}$path';

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      final path = req.uri.path;
      if (path == '/latest') {
        req.response.statusCode = releaseStatus;
        req.response.headers.contentType = ContentType.json;
        req.response.write(releaseStatus == 200 ? jsonEncode({'assets': assets}) : '{"message":"Not Found"}');
      } else if (path.startsWith('/dl/') && apks.containsKey(path.substring(4))) {
        // No length header, like a slow CDN: the app goes by the size GitHub listed.
        req.response.headers.chunkedTransferEncoding = true;
        req.response.add(apks[path.substring(4)]!);
      } else {
        req.response.statusCode = 404;
      }
      req.response.close();
    });
    Updater.releaseUrl = url('/latest');
    releaseStatus = 200;
    assets = [];
    apks.clear();
    final u = Updater.instance;
    u.current = null;
    u.available = null;
    u.error = null;
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await server.close(force: true);
  });

  test('finds a newer build on GitHub, and nothing when up to date', () async {
    assets = [
      {'name': 'Relay-58.apk', 'browser_download_url': 'https://x/Relay-58.apk', 'size': 1},
      {'name': 'Relay-60.apk', 'browser_download_url': 'https://x/Relay-60.apk', 'size': 78000000},
      {'name': 'notes.txt', 'browser_download_url': 'https://x/notes.txt', 'size': 3},
    ];
    final u = Updater.instance;

    var mine = 55;
    messenger.setMockMethodCallHandler(channel, (c) async => c.method == 'appBuild' ? mine : null);
    final found = await u.check();
    expect(found?.build, 60);
    expect(found?.url, 'https://x/Relay-60.apk');
    expect(u.error, isNull);

    mine = 60;
    u.current = null;
    expect(await u.check(), isNull);
    expect(u.error, isNull);
  });

  test('a missing release (CI rebuilding it) is "nothing new", not an error', () async {
    messenger.setMockMethodCallHandler(channel, (c) async => c.method == 'appBuild' ? 55 : null);
    releaseStatus = 404;
    expect(await Updater.instance.check(), isNull);
    expect(Updater.instance.error, isNull);
  });

  test('the quiet check only counts as done when GitHub answered', () async {
    messenger.setMockMethodCallHandler(channel, (c) async => c.method == 'appBuild' ? 55 : null);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final u = Updater.instance;

    releaseStatus = 500;
    expect(await u.checkQuietly(prefs), isNull);
    expect(u.error, isNotNull);
    expect(prefs.getInt('update_checked'), isNull, reason: 'a failed check should be retried next time');

    releaseStatus = 404;
    expect(await u.checkQuietly(prefs), isNull);
    expect(u.error, isNull);
    expect(prefs.getInt('update_checked'), isNotNull);
  });

  test('Install finds the new link when the release was rebuilt (404)', () async {
    final tmp = Directory.systemTemp.createTempSync('relay_upd');
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (c) async => tmp.path);
    String? installed;
    messenger.setMockMethodCallHandler(channel, (c) async {
      if (c.method == 'appBuild') return 55;
      if (c.method == 'installApk') {
        installed = (c.arguments as Map)['path'] as String;
        return 'ok';
      }
      return null;
    });
    final u = Updater.instance;

    assets = [
      {'name': 'Relay-60.apk', 'browser_download_url': url('/dl/Relay-60.apk'), 'size': 4},
    ];
    final old = await u.check();
    expect(old?.build, 60);

    // CI pushed again: build 60's link is gone, 61 is up.
    assets = [
      {'name': 'Relay-61.apk', 'browser_download_url': url('/dl/Relay-61.apk'), 'size': 4},
    ];
    apks['Relay-61.apk'] = [1, 2, 3, 4];

    expect(await u.install(old!), isNull);
    expect(installed, endsWith('Relay-61.apk'));
    expect(File(installed!).readAsBytesSync(), [1, 2, 3, 4]);
    expect(u.progress, isNull);

    // At the next start the downloaded APK is cleaned up.
    await Updater.cleanOldDownloads();
    expect(Directory('${tmp.path}/updates').listSync(), isEmpty);

    messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null);
    tmp.deleteSync(recursive: true);
  });

  test('a failed download leaves no half file behind', () async {
    final tmp = Directory.systemTemp.createTempSync('relay_upd');
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (c) async => tmp.path);
    messenger.setMockMethodCallHandler(channel, (c) async => c.method == 'appBuild' ? 55 : 'ok');
    final u = Updater.instance;
    // Says 10 bytes, sends 4.
    assets = [
      {'name': 'Relay-62.apk', 'browser_download_url': url('/dl/Relay-62.apk'), 'size': 10},
    ];
    apks['Relay-62.apk'] = [1, 2, 3, 4];
    final found = await u.check();
    expect(await u.install(UpdateInfo(found!.build, found.url, 10, null)), isNotNull);
    expect(Directory('${tmp.path}/updates').listSync(), isEmpty);

    messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null);
    tmp.deleteSync(recursive: true);
  });
}
