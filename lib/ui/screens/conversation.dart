import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart' show TextEditingController;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

import '../../api/models.dart';
import '../../skins/skin.dart';
import '../../state/store.dart';
import '../kit/controls.dart';
import '../kit/icons.dart';
import '../kit/overlays.dart';
import '../kit/scope.dart';
import 'chat_list.dart';

class ConversationPane extends StatefulWidget {
  final String chatGuid;
  final bool wide;
  final VoidCallback? onBack;
  const ConversationPane({super.key, required this.chatGuid, this.wide = false, this.onBack});

  @override
  State<ConversationPane> createState() => _ConversationPaneState();
}

class _ConversationPaneState extends State<ConversationPane> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  bool _loadingOlder = false;
  bool _firstLoad = true;
  Message? _replyTo;
  late Store _store;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _text.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _store = context.store;
    if (_firstLoad) _open();
  }

  @override
  void didUpdateWidget(covariant ConversationPane old) {
    super.didUpdateWidget(old);
    if (old.chatGuid != widget.chatGuid) {
      _replyTo = null;
      _text.clear();
      _open();
    }
  }

  Future<void> _open() async {
    _firstLoad = false;
    _store.openChat = widget.chatGuid;
    final c = _store.chatByGuid(widget.chatGuid);
    // _open runs from didChangeDependencies/didUpdateWidget (i.e. during build);
    // markRead notifies listeners elsewhere in the tree, so defer it a frame.
    if (c != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _store.markRead(c);
      });
    }
    await _store.loadMessages(widget.chatGuid);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (_store.openChat == widget.chatGuid) _store.openChat = null;
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingOlder || !_store.hasMore(widget.chatGuid)) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
      _loadingOlder = true;
      _store.loadMessages(widget.chatGuid, older: true).whenComplete(() => _loadingOlder = false);
    }
  }

  Future<void> _send(Chat chat) async {
    final t = _text.text;
    if (t.trim().isEmpty) return;
    final reply = _replyTo?.guid;
    _text.clear();
    setState(() => _replyTo = null);
    HapticFeedback.lightImpact();
    await _store.sendText(chat, t, replyTo: reply);
    if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  Future<void> _attach(Chat chat) async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (x == null) return;
    await _store.sendFile(chat, File(x.path));
  }

  void _actions(Chat chat, Message m) {
    final skin = context.skin, p = context.pal;
    showSkSheet(context, builder: (c) {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          for (final e in reactionEmoji.entries)
            Pressable(
              onTap: () async {
                Navigator.of(c).pop();
                final err = await _store.react(chat, m, e.key);
                if (err != null && mounted) Toaster.show(context, err, icon: 'alert');
              },
              builder: (pressed) => SizedBox(
                width: 46,
                height: 46,
                child: skin.buttonFace(p, primary: false, pressed: pressed, child: Center(child: Text(e.value, style: const TextStyle(fontSize: 22)))),
              ),
            ),
        ]),
        if (!_store.privateApi) ...[
          const SizedBox(height: 10),
          Text('Reactions and replies need the Private API on your Mac.', textAlign: TextAlign.center, style: skin.caption(p)),
        ],
        const SizedBox(height: 14),
        RowGroup(children: [
          if (m.text.isNotEmpty)
            SettingsRow(icon: 'copy', title: 'Copy text', onTap: () {
              Clipboard.setData(ClipboardData(text: m.text));
              Navigator.of(c).pop();
              Toaster.show(context, 'Copied', icon: 'check');
            }),
          if (_store.privateApi)
            SettingsRow(icon: 'reply', title: 'Reply', onTap: () {
              Navigator.of(c).pop();
              setState(() => _replyTo = m);
            }),
          if (m.failed)
            SettingsRow(icon: 'refresh', title: 'Try sending again', onTap: () {
              Navigator.of(c).pop();
              _store.retry(chat, m);
            }),
        ]),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final chat = _store.chatByGuid(widget.chatGuid);
        if (chat == null) {
          return Center(child: Text('Chat not found', style: skin.callout(p)));
        }
        final all = _store.messagesFor(chat.guid);
        // Fold reactions onto their targets.
        final reactions = <String, Map<String, int>>{};
        for (final m in all.reversed) {
          if (!m.isReaction) continue;
          final t = m.reactionTarget;
          if (t == null) continue;
          final map = reactions.putIfAbsent(t, () => {});
          final k = m.reactionKind!;
          map[k] = (map[k] ?? 0) + (m.isReactionRemoval ? -1 : 1);
        }
        final msgs = all.where((m) => !m.isReaction && (m.hasContent || m.isGroupEvent)).toList();
        final lastMine = msgs.indexWhere((m) => m.isFromMe);
        final typing = _store.typing.contains(chat.guid);
        final mq = MediaQuery.of(context);
        final safeTop = widget.wide ? 0.0 : mq.padding.top;
        final safeBottom = widget.wide ? 0.0 : mq.padding.bottom;

        final content = Column(children: [
          // ------------------------------------------------ header
          Padding(
            padding: EdgeInsets.fromLTRB(widget.wide ? 16 : 10, safeTop + 10, 14, 10),
            child: Row(children: [
              if (!widget.wide) ...[SkIconButton('back', size: 42, onTap: widget.onBack ?? () => Navigator.of(context).maybePop()), const SizedBox(width: 10)],
              skin.avatar(p, _store.initialsFor(chat), 44, chat.guid.hashCode.abs(), group: chat.isGroup),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_store.titleFor(chat), maxLines: 1, overflow: TextOverflow.ellipsis, style: skin.headline(p)),
                  const SizedBox(height: 1),
                  Text(
                    typing
                        ? 'typing…'
                        : chat.isGroup
                            ? '${chat.participants.length + 1} people · via Mac relay'
                            : (chat.isSms ? 'SMS · via your iPhone number' : 'iMessage · via Mac relay'),
                    style: skin.caption(p).copyWith(color: typing ? p.accent : p.text2),
                  ),
                ]),
              ),
              SkIconButton('info', size: 42, onTap: () => _showInfo(chat)),
            ]),
          ),
          SkDivider(indent: widget.wide ? 0 : 0),
          // ------------------------------------------------ messages
          Expanded(
            child: all.isEmpty && _store.hasMore(chat.guid)
                ? const Center(child: Spinner())
                : ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    itemCount: msgs.length + (typing ? 1 : 0) + 1,
                    itemBuilder: (context, i) {
                      if (typing && i == 0) return const _TypingBubble();
                      final idx = i - (typing ? 1 : 0);
                      if (idx == msgs.length) {
                        return _store.hasMore(chat.guid) ? const Padding(padding: EdgeInsets.all(16), child: Center(child: Spinner(size: 18))) : const SizedBox(height: 8);
                      }
                      final m = msgs[idx];
                      final older = idx + 1 < msgs.length ? msgs[idx + 1] : null;
                      final newer = idx > 0 ? msgs[idx - 1] : null;
                      final newDay = older == null || older.date.day != m.date.day || m.dateCreated - older.dateCreated > 3600 * 1000;
                      final firstOfRun = older == null || older.isFromMe != m.isFromMe || older.handle?.address != m.handle?.address || newDay;
                      final lastOfRun = newer == null || newer.isFromMe != m.isFromMe || newer.handle?.address != m.handle?.address;
                      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        if (newDay) _DaySep(m.dateCreated),
                        if (m.isGroupEvent && !m.hasContent)
                          _EventLine(m)
                        else
                          _BubbleRow(
                            chat: chat,
                            m: m,
                            showName: chat.isGroup && !m.isFromMe && firstOfRun,
                            tail: lastOfRun,
                            reactions: reactions[m.guid],
                            status: idx == lastMine ? _statusFor(m) : null,
                            onLong: () => _actions(chat, m),
                          ),
                        SizedBox(height: lastOfRun ? 10 : 3),
                      ]);
                    },
                  ),
          ),
          // ------------------------------------------------ composer
          if (_replyTo != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(children: [
                Ic('reply', size: 16, color: p.accent),
                const SizedBox(width: 8),
                Expanded(child: Text('Replying to “${_replyTo!.text}”', maxLines: 1, overflow: TextOverflow.ellipsis, style: skin.caption(p).copyWith(color: p.text2))),
                Pressable(onTap: () => setState(() => _replyTo = null), builder: (_) => Ic('x', size: 16, color: p.text3)),
              ]),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 6, 12, 12 + safeBottom),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              SkIconButton('image', size: 48, onTap: () => _attach(chat)),
              const SizedBox(width: 10),
              Expanded(child: SkField(controller: _text, hint: chat.isSms ? 'Text message' : 'iMessage', maxLines: 5, action: TextInputAction.newline)),
              const SizedBox(width: 10),
              _SendButton(enabled: _text.text.trim().isNotEmpty, onTap: () => _send(chat)),
            ]),
          ),
        ]);
        return content;
      },
    );
  }

  String? _statusFor(Message m) {
    if (m.sending) return 'Sending…';
    if (m.failed || m.error != 0) return 'Not delivered · tap and hold to retry';
    if (m.dateRead != null) return 'Read ${timeLabel(m.dateRead!)}';
    if (m.dateDelivered != null) return 'Delivered';
    return 'Sent via Mac relay';
  }

  void _showInfo(Chat chat) {
    showSkSheet(context, title: _store.titleFor(chat), builder: (c) {
      final skin = c.skin, p = c.pal;
      return SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          RowGroup(label: chat.isGroup ? '${chat.participants.length} others' : 'Contact', children: [
            for (final h in chat.participants)
              SettingsRow(
                title: _store.nameFor(h.address),
                subtitle: '${h.address} · ${h.service}',
                trailing: SkIconButton('copy', size: 36, onTap: () {
                  Clipboard.setData(ClipboardData(text: h.address));
                  Toaster.show(context, 'Copied ${h.address}', icon: 'check');
                }),
              ),
          ]),
          const SizedBox(height: 12),
          Text('Chat ID: ${chat.guid}', style: skin.mono(p).copyWith(fontSize: 11, color: p.text3)),
        ]),
      );
    });
  }
}

class _SendButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _SendButton({required this.enabled, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    return Pressable(
      onTap: enabled ? onTap : null,
      builder: (pressed) => AnimatedScale(
        duration: const Duration(milliseconds: 200),
        scale: enabled ? 1 : .9,
        child: SizedBox(
          width: 50,
          height: 50,
          child: skin.buttonFace(p, primary: true, pressed: pressed, radius: skin.upperHeadings ? 4 : 999, child: Center(child: Ic('send', size: 21, color: p.onAccent))),
        ),
      ),
    );
  }
}

class _DaySep extends StatelessWidget {
  final int ms;
  const _DaySep(this.ms);
  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final label = '${timeLabel(ms)}${timeLabel(ms).contains(':') ? '' : ' · ${d.hour % 12 == 0 ? 12 : d.hour % 12}:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}'}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(child: Text(skin.upperHeadings ? '— ${label.toUpperCase()} —' : label, style: skin.caption(p))),
    );
  }
}

class _EventLine extends StatelessWidget {
  final Message m;
  const _EventLine(this.m);
  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal, store = context.store;
    final who = m.isFromMe ? 'You' : (m.handle != null ? store.nameFor(m.handle!.address) : 'Someone');
    final text = m.groupTitle != null ? '$who named the group “${m.groupTitle}”' : '$who updated the group';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(child: Text(text, textAlign: TextAlign.center, style: skin.caption(p).copyWith(color: p.text2))),
    );
  }
}

class _BubbleRow extends StatelessWidget {
  final Chat chat;
  final Message m;
  final bool showName;
  final bool tail;
  final Map<String, int>? reactions;
  final String? status;
  final VoidCallback onLong;
  const _BubbleRow({required this.chat, required this.m, required this.showName, required this.tail, this.reactions, this.status, required this.onLong});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal, store = context.store;
    final out = m.isFromMe;
    final maxW = math.min(MediaQuery.of(context).size.width * .74, 460.0);
    final textColor = out ? (skin.id.name == 'hud' ? p.text : p.onAccent) : p.text;
    final reacts = (reactions ?? {}).entries.where((e) => e.value > 0).map((e) => reactionEmoji[e.key] ?? '').join();

    final parts = <Widget>[];
    for (final a in m.attachments) {
      parts.add(Padding(padding: const EdgeInsets.only(bottom: 4), child: _AttachmentView(a: a, outgoing: out)));
    }
    if (m.text.isNotEmpty) {
      parts.add(skin.bubble(
        p,
        outgoing: out,
        tail: tail,
        child: Text(m.text, style: skin.body(p).copyWith(color: textColor)),
      ));
    }

    Widget bubble = Column(crossAxisAlignment: out ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: parts);
    if (m.sending) bubble = Opacity(opacity: .6, child: bubble);

    return Column(crossAxisAlignment: out ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
      if (showName && m.handle != null)
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 3),
          child: Text(store.nameFor(m.handle!.address), style: skin.caption(p).copyWith(color: p.text2)),
        ),
      Pressable(
        onLongPress: onLong,
        onTap: m.failed ? onLong : null,
        scale: .98,
        haptic: false,
        builder: (_) => ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: Stack(clipBehavior: Clip.none, children: [
            Padding(padding: EdgeInsets.only(top: reacts.isNotEmpty ? 12 : 0), child: bubble),
            if (reacts.isNotEmpty)
              Positioned(
                top: -6,
                right: out ? null : -6,
                left: out ? -6 : null,
                child: skin.surface(p, strong: true, radius: skin.upperHeadings ? 3 : 14, brackets: false, padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), child: Text(reacts, style: const TextStyle(fontSize: 13))),
              ),
          ]),
        ),
      ),
      if (status != null)
        Padding(
          padding: const EdgeInsets.only(top: 4, right: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (status!.startsWith('Read') || status == 'Delivered') ...[Ic('checks', size: 13, color: p.success), const SizedBox(width: 4)],
            if (m.failed) ...[Ic('alert', size: 13, color: p.danger), const SizedBox(width: 4)],
            Text(skin.upperHeadings ? status!.toUpperCase() : status!, style: skin.caption(p).copyWith(color: m.failed ? p.danger : p.text3)),
          ]),
        ),
    ]);
  }
}

class _AttachmentView extends StatelessWidget {
  final Attachment a;
  final bool outgoing;
  const _AttachmentView({required this.a, required this.outgoing});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal, store = context.store;
    final r = BorderRadius.circular(skin.upperHeadings ? 4 : 18);
    final localPath = (a.mimeType ?? '').startsWith('local/') ? a.mimeType!.substring(6) : null;
    if (a.isImage && (localPath != null || store.api != null)) {
      final img = localPath != null
          ? Image.file(File(localPath), fit: BoxFit.cover)
          : Image.network(
              store.api!.attachmentUrl(a.guid, width: 900),
              headers: store.api!.headers,
              fit: BoxFit.cover,
              loadingBuilder: (c, child, prog) => prog == null ? child : Container(color: p.inset, alignment: Alignment.center, child: const Spinner(size: 18)),
              errorBuilder: (c, e, s) => Container(color: p.inset, alignment: Alignment.center, padding: const EdgeInsets.all(20), child: Ic('image', color: p.text3)),
            );
      final ratio = (a.width != null && a.height != null && a.height! > 0) ? (a.width! / a.height!).clamp(.5, 2.0) : 1.0;
      return Pressable(
        onTap: localPath == null ? () => _viewer(context) : null,
        haptic: false,
        builder: (_) => Container(
          decoration: BoxDecoration(borderRadius: r, border: Border.all(color: outgoing ? withA(p.accent, .6) : p.line)),
          child: ClipRRect(borderRadius: r, child: SizedBox(width: 240, child: AspectRatio(aspectRatio: ratio, child: img))),
        ),
      );
    }
    final icon = a.isVideo ? 'play' : a.isAudio ? 'mic' : 'file';
    return skin.bubble(
      p,
      outgoing: outgoing,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Ic(icon, size: 20, color: outgoing && skin.id.name != 'hud' ? p.onAccent : p.accent),
        const SizedBox(width: 10),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(a.transferName, maxLines: 1, overflow: TextOverflow.ellipsis, style: skin.callout(p).copyWith(color: outgoing && skin.id.name != 'hud' ? p.onAccent : p.text)),
            if (a.sizeLabel.isNotEmpty) Text(a.sizeLabel, style: skin.caption(p).copyWith(color: outgoing && skin.id.name != 'hud' ? withA(p.onAccent, .7) : p.text3)),
          ]),
        ),
      ]),
    );
  }

  void _viewer(BuildContext context) {
    final store = context.store;
    pushScreen(context, (c) => GestureDetector(
          onTap: () => Navigator.of(c).pop(),
          child: ColoredBox(
            color: const Color(0xF0000000),
            child: InteractiveViewer(
              maxScale: 5,
              child: Center(child: Image.network(store.api!.attachmentUrl(a.guid), headers: store.api!.headers)),
            ),
          ),
        ));
  }
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();
  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: skin.bubble(
          p,
          outgoing: false,
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < 3; i++)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 4),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: withA(p.text2, .35 + .65 * (.5 + .5 * math.sin((_c.value - i * .18) * 2 * math.pi))),
                    shape: skin.upperHeadings ? BoxShape.rectangle : BoxShape.circle,
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
