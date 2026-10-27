import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
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
        final r = await _ch.invokeMapMethod<String, dynamic>('videoThumb', {'src': src, 'out': img.path, 'headers': headers});
        if (r == null) return null;
        final t = VideoThumb(r['path'] as String, Duration(milliseconds: (r['duration'] as num).toInt()), (r['w'] as num).toInt(), (r['h'] as num).toInt());
        await meta.writeAsString(jsonEncode({'d': t.duration.inMilliseconds, 'w': t.width, 'h': t.height}));
        return t;
      } finally {
        _running--;
        if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
      }
    } catch (_) {
      _cache.remove(key); // try again next time
      return null;
    }
  }
}
