import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../state/link_preview.dart';
import 'scope.dart';

Future<void> openLink(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
}

/// Message text where web links are underlined and open when tapped.
class LinkText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Color linkColor;
  const LinkText(this.text, {super.key, required this.style, required this.linkColor});
  @override
  State<LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<LinkText> {
  final List<TapGestureRecognizer> _taps = [];

  void _clear() {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final links = findLinks(widget.text);
    if (links.isEmpty) return Text(widget.text, style: widget.style);
    final spans = <InlineSpan>[];
    var at = 0;
    for (final l in links) {
      if (l.start > at) spans.add(TextSpan(text: widget.text.substring(at, l.start)));
      final tap = TapGestureRecognizer()..onTap = () => openLink(l.url);
      _taps.add(tap);
      spans.add(TextSpan(
        text: widget.text.substring(l.start, l.end),
        recognizer: tap,
        style: TextStyle(color: widget.linkColor, decoration: TextDecoration.underline, decorationColor: widget.linkColor),
      ));
      at = l.end;
    }
    if (at < widget.text.length) spans.add(TextSpan(text: widget.text.substring(at)));
    return Text.rich(TextSpan(children: spans), style: widget.style);
  }
}

/// A small card with the page's picture, title and site, shown under a message.
class LinkCard extends StatefulWidget {
  final String url;
  const LinkCard(this.url, {super.key});
  @override
  State<LinkCard> createState() => _LinkCardState();
}

class _LinkCardState extends State<LinkCard> {
  late final Future<LinkPreview?> _f = LinkPreviews.instance.get(widget.url);

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    return FutureBuilder<LinkPreview?>(
      future: _f,
      builder: (context, snap) {
        final v = snap.data;
        if (v == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => openLink(widget.url),
            child: skin.surface(
              p,
              radius: 16,
              brackets: false,
              reduceEffects: true,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  if (v.image != null)
                    SizedBox(
                      height: 140,
                      child: Image.network(
                        v.image!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        frameBuilder: (c, child, frame, sync) => AnimatedOpacity(opacity: sync || frame != null ? 1 : 0, duration: const Duration(milliseconds: 200), child: child),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      if (v.title.isNotEmpty) Text(v.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: skin.headline(p).copyWith(fontSize: 14)),
                      if (v.description.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(v.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: skin.callout(p).copyWith(fontSize: 12)),
                      ],
                      const SizedBox(height: 5),
                      Text(v.domain, maxLines: 1, overflow: TextOverflow.ellipsis, style: skin.caption(p)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}
