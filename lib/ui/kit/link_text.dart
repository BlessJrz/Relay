import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../state/link_preview.dart';
import 'icons.dart';
import 'scope.dart';

const _media = MethodChannel('relay/media');

/// Opens a link in its own app (TikTok, YouTube…) or the browser, as a separate
/// app, so Relay stays usable. Falls back to url_launcher off Android.
Future<void> openLink(String url) async {
  try {
    if (Platform.isAndroid && await _media.invokeMethod<bool>('openUrl', {'url': url}) == true) return;
  } catch (_) {}
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
        if (v == null) {
          if (snap.connectionState != ConnectionState.done) return const SizedBox.shrink();
          return _plainCard(context);
        }
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => openLink(widget.url),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: skin.surface(
              p,
              radius: 16,
              reduceEffects: true,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  if (v.image != null)
                    SizedBox(
                      height: v.video ? 160 : 140,
                      child: Stack(fit: StackFit.expand, children: [
                        Image.network(
                          v.image!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          frameBuilder: (c, child, frame, sync) => AnimatedOpacity(opacity: sync || frame != null ? 1 : 0, duration: const Duration(milliseconds: 200), child: child),
                        ),
                        if (v.video)
                          Center(
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x99000000)),
                              alignment: Alignment.center,
                              child: const Ic('play', size: 22, color: Color(0xFFFFFFFF)),
                            ),
                          ),
                      ]),
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
          ),
        );
      },
    );
  }

  /// The site wouldn't give us a preview: still show where the link goes.
  Widget _plainCard(BuildContext context) {
    final skin = context.skin, p = context.pal;
    final uri = Uri.tryParse(widget.url);
    var host = uri?.host ?? widget.url;
    if (host.startsWith('www.')) host = host.substring(4);
    final path = uri == null || uri.path.length <= 1 ? '' : uri.path;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => openLink(widget.url),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: skin.surface(
            p,
            radius: 16,
            reduceEffects: true,
            padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: Ic('external', size: 17, color: p.accent),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(host, maxLines: 1, overflow: TextOverflow.ellipsis, style: skin.headline(p).copyWith(fontSize: 14)),
                  if (path.isNotEmpty) Text(path, maxLines: 1, overflow: TextOverflow.ellipsis, style: skin.caption(p)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
