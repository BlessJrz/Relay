import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// A still frame from a video, plus its length.
class VideoThumb {
  final String path;
  final Duration duration;
  final int width, height;
  const VideoThumb(this.path, this.duration, this.width, this.height);
  double get aspect => height == 0 ? 16 / 9 : width / height;
}

/// Makes video thumbnails on the phone (Android grabs a frame from the video)
/// and keeps them on disk, so each video is only fetched for a thumbnail once.
class VideoThumbs {
  VideoThumbs._();
  static final instance = VideoThumbs._();
  static const _ch = MethodChannel('relay/media');

  final Map<String, Future<VideoThumb?>> _cache = {};
  int _running = 0;
  final List<Completer<void>> _waiting = [];

  Future<VideoThumb?> get(String key, String src, {Map<String, String> headers = const {}}) =>
      _cache.putIfAbsent(key, () => _make(key, src, headers));

  Future<VideoThumb?> _make(String key, String src, Map<String, String> headers) async {
    try {
      final dir = Directory('${(await getTemporaryDirectory()).path}/vthumbs');
      final name = base64Url.encode(utf8.encode(key)).replaceAll('=', '');
      final img = File('${dir.path}/$name.jpg');
      final meta = File('${dir.path}/$name.json');
      if (await img.exists() && await meta.exists()) {
        final m = jsonDecode(await meta.readAsString()) as Map;
        return VideoThumb(img.path, Duration(milliseconds: (m['d'] as num).toInt()), (m['w'] as num).toInt(), (m['h'] as num).toInt());
      }
      // Two at a time, so a chat full of videos doesn't flood the connection.
      while (_running >= 2) {
        final c = Completer<void>();
        _waiting.add(c);
        await c.future;
      }
      _running++;
      try {
        // Grabbing a frame straight from the Mac over the tunnel isn't reliable,
        // so download the video once (also makes playing it instant later).
        final local = src.startsWith('/') ? src : await _download(key, src, headers);
        if (local == null) return null;
        final r = await _ch.invokeMapMethod<String, dynamic>('videoThumb', {'src': local, 'out': img.path, 'headers': const <String, String>{}});
        if (r == null) return null;
        final t = VideoThumb(r['path'] as String, Duration(milliseconds: (r['duration'] as num).toInt()), (r['w'] as num).toInt(), (r['h'] as num).toInt());
        await meta.writeAsString(jsonEncode({'d': t.duration.inMilliseconds, 'w': t.width, 'h': t.height}));
        return t;
      } finally {
        _running--;
        if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
      }
    } catch (_) {
      return null; // tried once this session; don't hammer the Mac
    }
  }

  Future<Directory> _videoDir() async => Directory('${(await getTemporaryDirectory()).path}/vcache').create(recursive: true);

  String _name(String key) => base64Url.encode(utf8.encode(key)).replaceAll('=', '');

  /// The downloaded copy of a video, if we have one.
  Future<String?> cachedVideo(String key) async {
    final f = File('${(await _videoDir()).path}/${_name(key)}.vid');
    return await f.exists() ? f.path : null;
  }

  Future<String?> _download(String key, String url, Map<String, String> headers) async {
    final dir = await _videoDir();
    final f = File('${dir.path}/${_name(key)}.vid');
    if (await f.exists()) return f.path;
    final tmp = File('${f.path}.part');
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url))..headers.addAll(headers);
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode >= 400) return null;
      final len = res.contentLength ?? 0;
      if (len > 150 * 1024 * 1024) return null; // don't pull huge files just for a picture
      final sink = tmp.openWrite();
      await res.stream.pipe(sink).timeout(const Duration(minutes: 4));
      await tmp.rename(f.path);
      unawaited(_trim(dir));
      return f.path;
    } catch (_) {
      try {
        await tmp.delete();
      } catch (_) {}
      return null;
    } finally {
      client.close();
    }
  }

  /// Keep downloaded videos under ~600 MB, oldest go first.
  Future<void> _trim(Directory dir) async {
    try {
      final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.vid')).toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      var total = 0;
      for (final f in files) {
        total += f.lengthSync();
        if (total > 600 * 1024 * 1024) f.deleteSync();
      }
    } catch (_) {}
  }
}
