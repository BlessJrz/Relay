import 'dart:io';

import 'package:flutter/widgets.dart';

import '../../api/models.dart';
import '../../state/link_preview.dart';
import '../../state/media_save.dart';
import '../../state/video_thumbs.dart';
import '../kit/controls.dart';
import '../kit/icons.dart';
import '../kit/link_text.dart';
import '../kit/overlays.dart';
import '../kit/scope.dart';
import 'chat_list.dart' show BareIcon, timeLabel;
import 'video_view.dart';

/// Saves an attachment and shows how it went.
Future<void> saveAttachment(BuildContext context, Attachment a) async {
  final api = context.store.api;
  if (api == null) return;
  Toaster.show(context, a.isVideo ? 'Saving video…' : 'Saving photo…', icon: 'download');
  final err = await saveToPhone(api, a);
  if (!context.mounted) return;
  Toaster.show(context, err ?? (a.isVideo ? 'Video saved to your gallery' : 'Photo saved to your gallery'), icon: err == null ? 'check' : 'alert');
}

/// Plays a chat video, using the downloaded copy when there is one.
Future<void> playAttachment(BuildContext context, Attachment a) async {
  final api = context.store.api;
  if (api == null) return;
  final cached = await VideoThumbs.instance.cachedVideo(a.guid);
  if (!context.mounted) return;
  await openVideo(context, file: cached, url: cached == null ? api.attachmentUrl(a.guid) : null, headers: api.headers, title: a.transferName);
}

/// Full-screen photo: pinch to zoom, tap to close, save button.
void showPhoto(BuildContext context, Attachment a) {
  final api = context.store.api;
  if (api == null) return;
  pushScreen(context, (c) {
    final mq = MediaQuery.of(c);
    return ColoredBox(
      color: const Color(0xF2000000),
      child: Stack(fit: StackFit.expand, children: [
        GestureDetector(
          onTap: () => Navigator.of(c).pop(),
          child: InteractiveViewer(
            maxScale: 5,
            child: Center(
              child: Image.network(
                api.attachmentUrl(a.guid),
                headers: api.headers,
                loadingBuilder: (_, child, prog) => prog == null ? child : const Spinner(color: Color(0xFFFFFFFF)),
              ),
            ),
          ),
        ),
        Positioned(
          top: mq.padding.top + 8,
          left: 8,
          right: 8,
          child: Row(children: [
            BareIcon('x', label: 'Close', color: const Color(0xFFFFFFFF), onTap: () => Navigator.of(c).pop()),
            const Spacer(),
            BareIcon('download', label: 'Save to phone', color: const Color(0xFFFFFFFF), onTap: () => saveAttachment(c, a)),
          ]),
        ),
      ]),
    );
  });
}

/// Every photo, video and link that's been shared in a chat (from the
/// messages loaded so far; "Load older" pulls in more).
class ChatMediaScreen extends StatefulWidget {
  final Chat chat;
  const ChatMediaScreen({super.key, required this.chat});
  @override
  State<ChatMediaScreen> createState() => _ChatMediaScreenState();
}

class _ChatMediaScreenState extends State<ChatMediaScreen> {
  int _tab = 0;
  bool _loading = false;

  Future<void> _older() async {
    setState(() => _loading = true);
    await context.store.loadMessages(widget.chat.guid, older: true);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal, store = context.store;
    final mq = MediaQuery.of(context);
    return skin.background(
      p,
      animate: false,
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final msgs = store.messagesFor(widget.chat.guid);
          final media = <(Attachment, Message)>[
            for (final m in msgs)
              for (final a in m.attachments)
                if (a.isImage || a.isVideo) (a, m),
          ];
          final links = <(LinkSpan, Message)>[
            for (final m in msgs)
              for (final l in findLinks(m.text)) (l, m),
          ];
          final api = store.api;
          Widget body;
          if (_tab == 0) {
            body = media.isEmpty
                ? _empty('No photos or videos yet.')
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 150, mainAxisSpacing: 4, crossAxisSpacing: 4),
                    itemCount: media.length,
                    itemBuilder: (context, i) {
                      final (a, _) = media[i];
                      return Pressable(
                        onTap: () => a.isVideo ? playAttachment(context, a) : showPhoto(context, a),
                        onLongPress: () => saveAttachment(context, a),
                        scale: .96,
                        builder: (_) => ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: ColoredBox(
                            color: p.surface2,
                            child: a.isVideo
                                ? FutureBuilder<VideoThumb?>(
                                    future: api == null ? null : VideoThumbs.instance.get(a.guid, api.attachmentUrl(a.guid), headers: api.headers),
                                    builder: (_, s) => Stack(fit: StackFit.expand, children: [
                                      if (s.data != null) Image.file(File(s.data!.path), fit: BoxFit.cover),
                                      const Center(child: Ic('play', size: 22, color: Color(0xFFFFFFFF))),
                                    ]),
                                  )
                                : (api == null
                                    ? const SizedBox()
                                    : Image(
                                        image: ResizeImage(NetworkImage(api.attachmentUrl(a.guid), headers: api.headers), width: 300, allowUpscaling: false),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Center(child: Ic('image', color: p.text3)),
                                      )),
                          ),
                        ),
                      );
                    },
                  );
          } else {
            body = links.isEmpty
                ? _empty('No links yet.')
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: links.length,
                    itemBuilder: (context, i) {
                      final (l, m) = links[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          LinkCard(l.url),
                          const SizedBox(height: 4),
                          Pressable(
                            onTap: () => openLink(l.url),
                            builder: (_) => Text(l.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: skin.callout(p).copyWith(color: p.accent)),
                          ),
                          Text('${m.isFromMe ? 'You' : (m.handle == null ? '' : store.nameFor(m.handle!.address))} · ${timeLabel(m.dateCreated)}', style: skin.caption(p)),
                        ]),
                      );
                    },
                  );
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: EdgeInsets.fromLTRB(8, mq.padding.top + 6, 16, 6),
              child: Row(children: [
                BareIcon('back', label: 'Back', onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 6),
                Expanded(child: Text(store.titleFor(widget.chat), maxLines: 1, overflow: TextOverflow.ellipsis, style: skin.title(p))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: SkSegmented(options: ['Photos & videos (${media.length})', 'Links (${links.length})'], index: _tab, expand: true, onChanged: (i) => setState(() => _tab = i)),
            ),
            Expanded(child: body),
            if (store.hasMore(widget.chat.guid))
              Padding(
                padding: EdgeInsets.fromLTRB(16, 6, 16, mq.padding.bottom + 12),
                child: SkButton(_loading ? 'Loading…' : 'Load older messages', primary: false, busy: _loading, expand: true, onTap: _loading ? null : _older),
              ),
          ]);
        },
      ),
    );
  }

  Widget _empty(String t) => Center(child: Text(t, style: context.skin.callout(context.pal)));
}
