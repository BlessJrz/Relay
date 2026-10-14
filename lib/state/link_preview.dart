import 'dart:async';

import 'package:http/http.dart' as http;

/// What we show under a message that contains a link.
class LinkPreview {
  final String url;
  final String title;
  final String description;
  final String? image;
  final String domain;
  const LinkPreview(this.url, this.title, this.description, this.image, this.domain);
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
  final attr = RegExp('([a-zA-Z:_-]+)\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\')');
  for (final tag in RegExp(r'<meta\s[^>]*>', caseSensitive: false).allMatches(html)) {
    String? key, content;
    for (final a in attr.allMatches(tag.group(0)!)) {
      final n = a.group(1)!.toLowerCase();
      final v = a.group(2) ?? a.group(3) ?? '';
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

  Future<LinkPreview?> get(String url) => _cache.putIfAbsent(url, () => _fetch(url));

  Future<LinkPreview?> _fetch(String url) async {
    try {
      final uri = Uri.parse(url);
      if (uri.scheme != 'http' && uri.scheme != 'https') return null;
      final r = await http.get(uri, headers: const {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14; SM-F966U) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml',
        'Accept-Language': 'en-US,en;q=0.8',
      }).timeout(const Duration(seconds: 8));
      if (r.statusCode >= 400) return null;
      final type = r.headers['content-type'] ?? '';
      if (!type.contains('html')) return null;
      var body = r.body;
      if (body.length > 400000) body = body.substring(0, 400000);
      return parsePreview(r.request?.url.toString() ?? url, body);
    } catch (_) {
      return null;
    }
  }
}
