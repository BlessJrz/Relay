import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Phone videos are often too big to send: Cloudflare tunnels refuse uploads
/// over 100 MB, and big uploads can time out. Videos over [_limit] are
/// re-encoded smaller on the phone (Android Media3) before they're sent.
const _limit = 25 * 1024 * 1024;
const _target = 60 * 1000 * 1000;
const _ch = MethodChannel('relay/media');

bool isVideoFile(String path) => RegExp(r'\.(mp4|mov|m4v|3gp|webm|mkv)$', caseSensitive: false).hasMatch(path);

/// True when [f] is a video big enough that it'll be shrunk first.
Future<bool> needsShrinking(File f) async => isVideoFile(f.path) && await f.length() > _limit;

/// Returns a smaller copy of a big video, or [f] itself if it's small already
/// or shrinking didn't work.
Future<File> shrinkForSending(File f) async {
  try {
    if (!await needsShrinking(f)) return f;
    final dir = Directory('${(await getTemporaryDirectory()).path}/send');
    await dir.create(recursive: true);
    final base = f.path.split(Platform.pathSeparator).last.replaceAll(RegExp(r'\.[^.]+$'), '');
    final out = '${dir.path}/${base}_small.mp4';
    final path = await _ch.invokeMethod<String>('shrinkVideo', {'src': f.path, 'out': out, 'targetBytes': _target});
    if (path == null) return f;
    final small = File(path);
    if (await small.exists() && await small.length() > 0 && await small.length() < await f.length()) return small;
  } catch (_) {}
  return f;
}
