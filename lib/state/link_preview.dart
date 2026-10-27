import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// What we show under a message that contains a link.
class LinkPreview {
  final String url;
  final String title;
  final String description;
  final String? image;
  final String domain;
  final bool video; // draw a play button over the picture
  const LinkPreview(this.url, this.title, this.description, this.image, this.domain, {this.video = false});
}

final _urlRe = RegExp(r'((?:https?://|www\.)[^\s<>]+)', caseSensitive: false);

class LinkSpan {
  final int start, end;
  final String text; // as written
  final String url; // openable
  const LinkSpan(this.start, this.end, this.text, this.url);
}

/// Finds web links in message text.
List<LinkSpan> findLinks(String text) {
  final out = <LinkSpan>[];
  for (final m in _urlRe.allMatches(text)) {
    var s = m.group(0)!;
    var end = m.end;
    // Trailing punctuation belongs to the sentence, not the link.
    while (s.isNotEmpty && '.,;:!?\'"'.contains(s[s.length - 1])) {
      s = s.substring(0, s.length - 1);
      end--;
    }
    while (s.isNotEmpty && ')]}'.contains(s[s.length - 1]) && !s.contains('(')) {
      s = s.substring(0, s.length - 1);
      end--;
    }
    if (s.length < 5) continue;
    out.add(LinkSpan(m.start, end, s, s.toLowerCase().startsWith('www.') ? 'https://$s' : s));
  }
  return out;
}

/// The video id in a YouTube link (youtu.be/ID, watch?v=ID, shorts/ID…).
String _bareHost(Uri u) {
  var h = u.host.toLowerCase();
  for (final p in const ['www.', 'm.']) {
    if (h.startsWith(p)) h = h.substring(p.length);
  }
  return h;
}

String? youTubeId(Uri u) {
  final host = _bareHost(u);
  String? id;
  if (host == 'youtu.be') {
    id = u.pathSegments.isNotEmpty ? u.pathSegments.first : null;
  } else if (host == 'youtube.com' || host == 'music.youtube.com' || host == 'youtube-nocookie.com') {
    final seg = u.pathSegments;
    if (u.queryParameters['v'] != null) {
      id = u.queryParameters['v'];
    } else if (seg.length >= 2 && const ['shorts', 'embed', 'live', 'v'].contains(seg.first)) {
      id = seg[1];
    }
  }
  if (id == null || !RegExp(r'^[A-Za-z0-9_-]{6,20}$').hasMatch(id)) return null;
  return id;
}

String _unescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&#x27;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&nbsp;', ' ')
    .trim();

/// Reads Open Graph / Twitter / <title> data out of a page's HTML.
LinkPreview? parsePreview(String url, String html) {
  final meta = <String, String>{};
  final attr = RegExp('([a-zA-Z:_-]+)\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s"\'>]+))');
  for (final tag in RegExp(r'<meta\s[^>]*>', caseSensitive: false).allMatches(html)) {
    String? key, content;
    for (final a in attr.allMatches(tag.group(0)!)) {
      final n = a.group(1)!.toLowerCase();
      final v = a.group(2) ?? a.group(3) ?? a.group(4) ?? '';
      if (n == 'property' || n == 'name') key ??= v.toLowerCase();
      if (n == 'content') content = v;
    }
    if (key != null && content != null && content.isNotEmpty) meta.putIfAbsent(key, () => content!);
  }
  var title = meta['og:title'] ?? meta['twitter:title'] ?? '';
  if (title.isEmpty) {
    final t = RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false).firstMatch(html);
    title = t?.group(1) ?? '';
  }
  title = _unescape(title).replaceAll(RegExp(r'\s+'), ' ');
  final desc = _unescape(meta['og:description'] ?? meta['twitter:description'] ?? meta['description'] ?? '').replaceAll(RegExp(r'\s+'), ' ');
  var image = meta['og:image'] ?? meta['og:image:url'] ?? meta['twitter:image'];
  final base = Uri.tryParse(url);
  if (image != null && base != null) {
    image = base.resolve(_unescape(image)).toString();
  }
  if (title.isEmpty && desc.isEmpty && image == null) return null;
  var domain = base?.host ?? '';
  if (domain.startsWith('www.')) domain = domain.substring(4);
  return LinkPreview(url, title, desc, image, domain);
}

/// Fetches and remembers link previews (the phone asks the website itself).
class LinkPreviews {
  LinkPreviews._();
  static final instance = LinkPreviews._();
  final Map<String, Future<LinkPreview?>> _cache = {};

  // Many sites (Instagram, TikTok, X, Reddit…) only put the preview details in
  // the page for link-preview bots, so ask as one first, then as a browser.
  static const _agents = [
    'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)',
    'Mozilla/5.0 (Linux; Android 14; SM-F966U) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36',
  ];

  Future<LinkPreview?> get(String url) => _cache.putIfAbsent(url, () async {
        final v = await _fetchAny(url);
        // Didn't work (offline, slow site…): let a later look try again.
        if (v == null) Timer(const Duration(minutes: 2), () => _cache.remove(url));
        return v;
      });

  Future<LinkPreview?> _fetchAny(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) return null;
    final yt = youTubeId(uri);
    if (yt != null) return _youTube(uri, yt);
    final oembed = _oembedFor(uri);
    if (oembed != null) {
      final v = await _oembed(uri, oembed);
      if (v != null) return v;
    }
    for (final ua in _agents) {
      final v = await _fetch(uri, ua);
      if (v != null) return v;
    }
    return null;
  }

  /// YouTube: the thumbnail address is known from the video id, and the
  /// title comes from YouTube's public oEmbed (no page scraping needed).
  Future<LinkPreview> _youTube(Uri uri, String id) async {
    var title = '', author = '';
    try {
      final r = await http
          .get(Uri.https('www.youtube.com', '/oembed', {'url': 'https://www.youtube.com/watch?v=$id', 'format': 'json'}))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final j = jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
        title = (j['title'] ?? '').toString();
        author = (j['author_name'] ?? '').toString();
      }
    } catch (_) {}
    return LinkPreview(uri.toString(), title, author, 'https://i.ytimg.com/vi/$id/hqdefault.jpg', 'youtube.com', video: true);
  }

  /// Sites with a public oEmbed endpoint that gives a picture.
  static Uri? _oembedFor(Uri u) {
    final host = _bareHost(u);
    final url = u.toString();
    if (host.endsWith('tiktok.com')) return Uri.https('www.tiktok.com', '/oembed', {'url': url});
    if (host == 'open.spotify.com') return Uri.https('open.spotify.com', '/oembed', {'url': url});
    if (host == 'vimeo.com') return Uri.https('vimeo.com', '/api/oembed.json', {'url': url});
    if (host == 'soundcloud.com') return Uri.https('soundcloud.com', '/oembed', {'url': url, 'format': 'json'});
    return null;
  }

  Future<LinkPreview?> _oembed(Uri uri, Uri endpoint) async {
    try {
      final r = await http.get(endpoint, headers: {'User-Agent': _agents.last}).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
      if (j is! Map) return null;
      final title = (j['title'] ?? '').toString();
      final author = (j['author_name'] ?? '').toString();
      final thumb = j['thumbnail_url']?.toString();
      if (title.isEmpty && thumb == null) return null;
      var host = uri.host;
      if (host.startsWith('www.')) host = host.substring(4);
      final video = (j['type'] ?? '').toString() == 'video';
      return LinkPreview(uri.toString(), title, author, thumb, host, video: video);
    } catch (_) {
      return null;
    }
  }

  Future<LinkPreview?> _fetch(Uri uri, String ua) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', uri)
        ..followRedirects = true
        ..maxRedirects = 8
        ..headers.addAll({
          'User-Agent': ua,
          'Accept': 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.8',
        });
      final r = await client.send(req).timeout(const Duration(seconds: 8));
      if (r.statusCode >= 400) return null;
      final type = r.headers['content-type'] ?? '';
      if (type.startsWith('image/')) {
        // A link straight to a picture: the picture is the preview.
        var host = uri.host;
        if (host.startsWith('www.')) host = host.substring(4);
        return LinkPreview(uri.toString(), '', '', uri.toString(), host);
      }
      if (type.isNotEmpty && !type.contains('html')) return null;
      // The preview details live in <head>; stop reading once it's done.
      final bytes = <int>[];
      await for (final chunk in r.stream.timeout(const Duration(seconds: 8))) {
        final from = bytes.length > 8 ? bytes.length - 8 : 0;
        bytes.addAll(chunk);
        if (bytes.length > 600000) break;
        // Stop at the end of <head> once the preview tags have shown up (some
        // sites put them further down, so keep reading if they haven't).
        if (bytes.length > 2048 && latin1.decode(bytes.sublist(from), allowInvalid: true).toLowerCase().contains('</head>') && latin1.decode(bytes, allowInvalid: true).contains('og:')) break;
      }
      final html = utf8.decode(bytes, allowMalformed: true);
      final finalUrl = uri.toString();
      return parsePreview(finalUrl, html);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}
