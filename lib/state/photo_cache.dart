import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Keeps the photos from your Mac on the phone. Each one is downloaded once;
/// after that it's read from storage, so scrolling back through a chat (or
/// opening Relay again) shows photos straight away instead of fetching them
/// from the Mac every time they'd dropped out of memory.
class PhotoCache {
  PhotoCache._();
  static final instance = PhotoCache._();

  static const _limit = 500 * 1024 * 1024; // on disk, oldest go first
  static const _tooBig = 80 * 1024 * 1024; // not a photo worth keeping

  final Map<String, Future<File>> _fetching = {};
  Directory? _dir;
  int _sinceTrim = 0;

  Future<Directory> _folder() async => _dir ??= await Directory('${(await getTemporaryDirectory()).path}/photos').create(recursive: true);

  static String _name(String guid) => base64Url.encode(utf8.encode(guid)).replaceAll('=', '');

  /// The photo's file, downloading it first if it isn't on the phone yet.
  /// Two bubbles asking for the same photo share one download.
  Future<File> fileFor(String guid, String url, Map<String, String> headers) {
    final running = _fetching[guid];
    if (running != null) return running;
    final f = _get(guid, url, headers);
    _fetching[guid] = f;
    return f.whenComplete(() => _fetching.remove(guid));
  }

  Future<File> _get(String guid, String url, Map<String, String> headers) async {
    final file = File('${(await _folder()).path}/${_name(guid)}');
    if (await file.exists() && await file.length() > 0) return file;
    final part = File('${file.path}.part');
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(url))..headers.addAll(headers)).timeout(const Duration(seconds: 30));
      if (res.statusCode >= 400) throw HttpException('Photo not available (${res.statusCode})');
      if ((res.contentLength ?? 0) > _tooBig) throw const HttpException('Photo too large');
      final sink = part.openWrite();
      try {
        // No bytes for 30 s means the Mac went away mid-download.
        await res.stream.timeout(const Duration(seconds: 30)).pipe(sink);
      } finally {
        await sink.close();
      }
      await part.rename(file.path);
      if (++_sinceTrim >= 40) {
        _sinceTrim = 0;
        unawaited(trim());
      }
      return file;
    } catch (_) {
      try {
        if (await part.exists()) await part.delete();
      } catch (_) {}
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Forgets a copy that wouldn't decode, so it's fetched fresh next time.
  Future<void> drop(String guid) async {
    try {
      await File('${(await _folder()).path}/${_name(guid)}').delete();
    } catch (_) {}
  }

  /// Keeps the folder under its limit, deleting the least recently saved first.
  Future<void> trim() async {
    try {
      final entries = <(File, FileStat)>[];
      await for (final e in (await _folder()).list()) {
        if (e is File) entries.add((e, await e.stat()));
      }
      entries.sort((a, b) => b.$2.modified.compareTo(a.$2.modified));
      var total = 0;
      final now = DateTime.now();
      for (final (f, st) in entries) {
        // A download that never finished (the app was closed mid-way).
        final stale = f.path.endsWith('.part') && now.difference(st.modified) > const Duration(hours: 1);
        total += st.size;
        if (stale || total > _limit) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}

/// A photo attachment from the Mac, shown from the phone's copy (see
/// [PhotoCache]). Use it wherever `NetworkImage(attachmentUrl)` would go,
/// usually inside a `ResizeImage` so it's decoded at the size it's drawn.
@immutable
class MacPhoto extends ImageProvider<MacPhoto> {
  final String guid;
  final String url;
  final Map<String, String> headers;
  const MacPhoto(this.guid, this.url, this.headers);

  @override
  Future<MacPhoto> obtainKey(ImageConfiguration configuration) => SynchronousFuture<MacPhoto>(this);

  @override
  ImageStreamCompleter loadImage(MacPhoto key, ImageDecoderCallback decode) => MultiFrameImageStreamCompleter(
        codec: _load(key, decode),
        scale: 1,
        debugLabel: 'MacPhoto(${key.guid})',
      );

  Future<ui.Codec> _load(MacPhoto key, ImageDecoderCallback decode) async {
    try {
      final file = await PhotoCache.instance.fileFor(key.guid, key.url, key.headers);
      try {
        return await decode(await ui.ImmutableBuffer.fromFilePath(file.path));
      } catch (_) {
        await PhotoCache.instance.drop(key.guid); // a broken copy: fetch it again next time
        rethrow;
      }
    } catch (_) {
      // Don't let a failed load stay in memory as "the" result: a later look
      // (the Mac is back, the tunnel recovered) should try again.
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      rethrow;
    }
  }

  // The same attachment is the same picture, whatever the address is today
  // (the Mac's tunnel URL changes when it restarts).
  @override
  bool operator ==(Object other) => other is MacPhoto && other.guid == guid;

  @override
  int get hashCode => guid.hashCode;

  @override
  String toString() => 'MacPhoto($guid)';
}
