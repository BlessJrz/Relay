import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

const _media = MethodChannel('relay/media');

/// Opens a file from the Mac (a PDF, a video…) in another app. It's
/// downloaded inside Relay first and the copy on the phone is handed over, so
/// the Mac's address and password never leave Relay (a plain link would end
/// up in the browser's history). Returns an error to show, or null.
Future<String?> openRemoteFile(String url, Map<String, String> headers, String name, {String? mime}) async {
  final client = http.Client();
  File? part;
  try {
    final dir = Directory('${(await getTemporaryDirectory()).path}/open');
    await dir.create(recursive: true);
    // Only the latest few opened files are kept.
    final old = dir.listSync().whereType<File>().toList()..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    for (final f in old.skip(5)) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
    // Named after the attachment itself as well, so two files that share a
    // name ("Scan.pdf", every voice message) don't open each other's copy.
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    final tag = url.hashCode.toUnsigned(32).toRadixString(16);
    final file = File('${dir.path}/${tag}_${safe.isEmpty ? 'attachment' : safe}');
    if (!await file.exists()) {
      final res = await client.send(http.Request('GET', Uri.parse(url))..headers.addAll(headers)).timeout(const Duration(seconds: 30));
      if (res.statusCode >= 400) return 'Couldn’t download it from your Mac (${res.statusCode}).';
      part = File('${file.path}.part');
      final sink = part.openWrite();
      try {
        await res.stream.timeout(const Duration(seconds: 30)).pipe(sink);
      } finally {
        await sink.close();
      }
      await part.rename(file.path);
      part = null;
    }
    final ok = await _media.invokeMethod<bool>('openFile', {'path': file.path, 'mime': mime});
    return ok == true ? null : 'No app on this phone can open this file.';
  } catch (_) {
    return 'Couldn’t download it from your Mac.';
  } finally {
    client.close();
    try {
      await part?.delete();
    } catch (_) {}
  }
}
