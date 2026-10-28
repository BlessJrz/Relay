import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A newer build waiting on GitHub.
class UpdateInfo {
  final int build;
  final String url;
  final int size;
  final DateTime? published;
  const UpdateInfo(this.build, this.url, this.size, this.published);
}

/// Updates straight from GitHub: every push to main publishes `Relay-<N>.apk`
/// on the rolling `latest` release. Compares N with this app's build number,
/// downloads the APK and hands it to Android's installer (same signing key, so
/// it installs over the top and keeps everything).
class Updater extends ChangeNotifier {
  Updater._();
  static final instance = Updater._();

  @visibleForTesting
  static String releaseUrl = 'https://api.github.com/repos/BlessJrz/Relay/releases/tags/latest';
  static const _media = MethodChannel('relay/media');
  static final _apk = RegExp(r'^Relay-(\d+)\.apk$');

  int? current; // this app's build number (null until read, 0 if unknown)
  String version = ''; // e.g. "1.1.0"
  UpdateInfo? available;
  bool checking = false;
  double? progress; // 0..1 while downloading
  String? error;
  DateTime? lastChecked;

  Future<int> currentBuild() async {
    if (current != null) return current!;
    try {
      current = (await _media.invokeMethod<int>('appBuild')) ?? 0;
      version = (await _media.invokeMethod<String>('appVersion')) ?? '';
    } catch (_) {
      current ??= 0;
    }
    return current!;
  }

  /// Asks GitHub for the newest build. Returns it if it's newer than this one.
  Future<UpdateInfo?> check() async {
    if (checking) return available;
    checking = true;
    error = null;
    notifyListeners();
    try {
      final mine = await currentBuild();
      final r = await http.get(Uri.parse(releaseUrl), headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'Relay-app'}).timeout(const Duration(seconds: 15));
      // 404: CI is rebuilding the `latest` release right now. Nothing new yet.
      if (r.statusCode != 200 && r.statusCode != 404) throw 'GitHub answered ${r.statusCode}';
      final j = r.statusCode == 404 ? const <String, dynamic>{} : jsonDecode(r.body) as Map<String, dynamic>;
      UpdateInfo? best;
      for (final a in (j['assets'] as List? ?? const [])) {
        final m = _apk.firstMatch((a['name'] ?? '').toString());
        if (m == null) continue;
        final n = int.parse(m.group(1)!);
        if (best == null || n > best.build) {
          best = UpdateInfo(n, (a['browser_download_url'] ?? '').toString(), (a['size'] as num?)?.toInt() ?? 0, DateTime.tryParse((a['updated_at'] ?? '').toString()));
        }
      }
      lastChecked = DateTime.now();
      available = best != null && mine > 0 && best.build > mine ? best : null;
    } catch (e) {
      error = e is String ? e : 'Couldn’t reach GitHub. Check your connection.';
    } finally {
      checking = false;
      notifyListeners();
    }
    return available;
  }

  /// A quiet check when the app opens, at most every 6 hours.
  Future<UpdateInfo?> checkQuietly(SharedPreferences prefs) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - (prefs.getInt('update_checked') ?? 0) < 6 * 3600 * 1000) return null;
    final u = await check();
    if (error != null) return null; // try again next time Relay opens
    await prefs.setInt('update_checked', now);
    // Don't nag about the same build twice.
    if (u == null || prefs.getInt('update_told') == u.build) return null;
    await prefs.setInt('update_told', u.build);
    return u;
  }

  /// Downloads the update and opens the installer. Returns an error message, or null.
  Future<String?> install(UpdateInfo u) async {
    if (progress != null) return null;
    progress = 0;
    error = null;
    notifyListeners();
    try {
      var path = await _download(u);
      if (path == null) {
        // 404: the `latest` release is rebuilt on every push, so this link is
        // gone. Look again and try the new one, once.
        available = null;
        final again = await check();
        if (again == null) throw error ?? 'That build was replaced on GitHub. Try again in a minute.';
        progress = 0;
        notifyListeners();
        path = await _download(again);
        if (path == null) throw 'That build was replaced on GitHub. Try again in a minute.';
      }
      progress = 1;
      notifyListeners();
      final r = await _media.invokeMethod<String>('installApk', {'path': path});
      if (r != 'ok') throw 'Couldn’t open the installer ($r)';
      return null;
    } catch (e) {
      error = e is String ? e : 'Download failed. Check your connection.';
      return error;
    } finally {
      progress = null;
      notifyListeners();
    }
  }

  static Future<Directory> _updatesDir() async => Directory('${(await getTemporaryDirectory()).path}/updates');

  /// Saves the APK under the cache's `updates` folder and returns its path,
  /// or null if GitHub says it's gone (404). A failed download leaves no file.
  Future<String?> _download(UpdateInfo u) async {
    final dir = await _updatesDir();
    await dir.create(recursive: true);
    for (final f in dir.listSync()) {
      try {
        f.deleteSync(recursive: true);
      } catch (_) {}
    }
    final file = File('${dir.path}/Relay-${u.build}.apk');
    final client = http.Client();
    IOSink? sink;
    var done = false;
    try {
      final res = await client.send(http.Request('GET', Uri.parse(u.url))..headers['User-Agent'] = 'Relay-app').timeout(const Duration(seconds: 30));
      if (res.statusCode == 404) return null;
      if (res.statusCode != 200) throw 'Download failed (${res.statusCode})';
      final total = res.contentLength ?? u.size;
      sink = file.openWrite();
      var got = 0, lastTick = 0;
      // Gives up if nothing arrives for 30 s.
      await for (final chunk in res.stream.timeout(const Duration(seconds: 30))) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0 && got - lastTick > 256 * 1024) {
          lastTick = got;
          progress = got / total;
          notifyListeners();
        }
      }
      await sink.close();
      sink = null;
      if (total > 0 && got < total) throw 'Download was cut off. Try again.';
      done = true;
      return file.path;
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client.close();
      if (!done) {
        try {
          if (file.existsSync()) file.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// Deletes downloaded updates. Once Relay is running, the APK isn't needed.
  static Future<void> cleanOldDownloads() async {
    try {
      final dir = await _updatesDir();
      if (!await dir.exists()) return;
      await for (final f in dir.list()) {
        try {
          await f.delete(recursive: true);
        } catch (_) {}
      }
    } catch (_) {}
  }
}
