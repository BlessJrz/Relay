import 'package:flutter_test/flutter_test.dart';
import 'package:relay/state/link_preview.dart';

void main() {
  test('finds links and trims trailing punctuation', () {
    final l = findLinks('see https://example.com/a?b=1, and www.foo.org/x. ok (https://bar.io)');
    expect(l.map((e) => e.url), ['https://example.com/a?b=1', 'https://www.foo.org/x', 'https://bar.io']);
  });
  test('no links in plain text', () {
    expect(findLinks('hello world, no url here'), isEmpty);
  });
  test('parses Open Graph tags', () {
    final p = parsePreview('https://site.com/page', '''
      <html><head><title>Fallback</title>
      <meta property="og:title" content="Big &amp; Bold">
      <meta content="A nice page" property="og:description">
      <meta property="og:image" content="/img/a.png"></head></html>''');
    expect(p!.title, 'Big & Bold');
    expect(p.description, 'A nice page');
    expect(p.image, 'https://site.com/img/a.png');
    expect(p.domain, 'site.com');
  });
  test('falls back to <title>; empty page gives nothing', () {
    expect(parsePreview('https://a.com', '<title> Hi </title>')!.title, 'Hi');
    expect(parsePreview('https://a.com', '<html></html>'), isNull);
  });

  test('reads unquoted meta attributes', () {
    final p = parsePreview('https://x.com/a', '<meta property=og:title content="Post"><meta property=og:image content=https://img.x.com/1.jpg>');
    expect(p!.title, 'Post');
    expect(p.image, 'https://img.x.com/1.jpg');
  });
}
