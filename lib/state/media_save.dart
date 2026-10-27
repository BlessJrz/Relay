import 'dart:io';

import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../api/bb_api.dart';
import '../api/models.dart';
import 'video_thumbs.dart';

String _extFor(String? contentType, String name, bool video) {
  final t = (contentType ?? '').toLowerCase();
  if (t.contains('jpeg') || t.contains('jpg')) return 'jpg';
  if (t.contains('png')) return 'png';
  if (t.contains('gif')) return 'gif';
  if (t.contains('heic') || t.contains('heif')) return 'heic';
  if (t.contains('webp')) return 'webp';
  if (t.contains('quicktime')) return 'mov';
  if (t.contains('mp4')) return 'mp4';
  final dot = name.lastIndexOf('.');
  if (dot > 0 && dot < name.length - 1) return name.substring(dot + 1).toLowerCase();
  return video ? 'mp4' : 'jpg';
}

/// Saves a photo or video from a chat to the phone's gallery.
/// Returns null when saved, otherwise a message to show.
Future<String?> saveToPhone(BBApi api, Attachment a) async {
  try {
    if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
      return 'Relay needs permission to save to your gallery.';
    }
    final tmp = await getTemporaryDirectory();
    File file;
    final cached = a.isVideo ? await VideoThumbs.instance.cachedVideo(a.guid) : null;
    if (cached != null) {
      file = await File(cached).copy('${tmp.path}/relay_${a.guid.hashCode.abs()}.${_extFor(null, a.transferName, true)}');
    } else {
      // Stream to disk so a big video never has to fit in memory.
      final client = http.Client();
      try {
        final res = await client.send(http.Request('GET', Uri.parse(api.attachmentUrl(a.guid)))..headers.addAll(api.headers)).timeout(const Duration(seconds: 30));
        if (res.statusCode >= 400) return 'Your Mac couldn’t send the file (${res.statusCode}).';
        file = File('${tmp.path}/relay_${a.guid.hashCode.abs()}.${_extFor(res.headers['content-type'], a.transferName, a.isVideo)}');
        await res.stream.pipe(file.openWrite()).timeout(const Duration(minutes: 5));
      } finally {
        client.close();
      }
    }
    if (a.isVideo) {
      await Gal.putVideo(file.path);
    } else {
      await Gal.putImage(file.path);
    }
    try {
      await file.delete();
    } catch (_) {}
    return null;
  } on GalException catch (e) {
    return e.type.message;
  } catch (e) {
    return 'Couldn’t save it: $e';
  }
}
