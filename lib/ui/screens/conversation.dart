import 'dart:io';
import 'dart:ui' show ImageFilter;
import '../../state/link_preview.dart';
import '../kit/link_text.dart';
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
import 'video_view.dart';

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
  bool _loadStarted = false;
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
    _loadStarted = false;
    _store.openChat = widget.chatGuid;
    final c = _store.chatByGuid(widget.chatGuid);
    // _open runs from didChangeDependencies/didUpdateWidget (i.e. during build);
    // anything that notifies listeners elsewhere in the tree must wait a frame.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (c != null) _store.markRead(c);
      _loadStarted = true;
      await _store.loadMessages(widget.chatGuid);
      if (mounted) setState(() {});
    });
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
    final x = await ImagePicker().pickMedia(imageQuality: 90); // photos and videos
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
        // Unfolded Pinned/Folders: the chat header runs up under the status bar (edge to edge).
        final edgeTop = widget.wide && (skin.layout == AppLayout.pinned || skin.layout == AppLayout.folders);
        final safeTop = widget.wide && !edgeTop ? 0.0 : mq.padding.top;
        final safeBottom = widget.wide ? 0.0 : mq.padding.bottom;

        // Pinned design: a slim see-through header floats over the chat,
        // so messages scroll up behind it instead of being cut off.
        final floatHeader = skin.layout == AppLayout.pinned;
        final headerH = floatHeader ? safeTop + _pinnedHeaderH : 0.0;
        final content = Column(children: [
          // ------------------------------------------------ header
          if (!floatHeader) _header(chat, typing, safeTop),
          // ------------------------------------------------ messages
          Expanded(
            child: Stack(children: [
              Positioned.fill(child: _wallpaper(all.isEmpty
                ? (!_loadStarted || _store.isLoadingMessages(chat.guid)
                    ? const Center(child: Spinner())
                    : _store.messageError(chat.guid) != null
                        ? _LoadError(message: _store.messageError(chat.guid)!, onRetry: () => _store.loadMessages(chat.guid))
                        : Center(child: Text('No messages yet', style: skin.callout(p))))
                : ListView.builder(
                    controller: _scroll,
                    cacheExtent: 700,
                    reverse: true,
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    padding: EdgeInsets.fromLTRB(14, 14 + headerH, 14, 14),
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
                  ))),
              if (floatHeader) Positioned(left: 0, right: 0, top: 0, child: _header(chat, typing, safeTop)),
            ]),
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
          _composer(chat, safeBottom),
        ]);
        return content;
      },
    );
  }


  Widget _wallpaper(Widget child) {
    final skin = context.skin, p = context.pal;
    if (skin.layout != AppLayout.folders) return child;
    return CustomPaint(painter: _DotsPainter(Color.alphaBlend(withA(p.accent, p.dark ? .10 : .12), p.bg), p.dark ? Color.lerp(p.bg, const Color(0xFF000000), .25)! : const Color(0xFFDCE6EE)), child: child);
  }

  static const _pinnedHeaderH = 78.0;

  Widget _header(Chat chat, bool typing, double safeTop) {
    final skin = context.skin, p = context.pal;
    final subtitle = typing
        ? 'typing…'
        : chat.isGroup
            ? '${chat.participants.length + 1} people · via Mac relay'
            : (chat.isSms ? 'SMS · via your iPhone number' : 'iMessage · via Mac relay');
    final avatar = Pressable(
      onTap: () => _showInfo(chat),
      haptic: false,
      builder: (_) => skin.avatar(p, _store.initialsFor(chat), skin.layout == AppLayout.folders ? 42 : 44, chat.guid.hashCode.abs(), group: chat.isGroup, image: _store.avatars.forChat(chat)),
    );
    final back = widget.wide ? null : BareIcon('back', label: 'Back', color: skin.layout == AppLayout.pinned ? p.accent : p.text, onTap: widget.onBack ?? () => Navigator.of(context).maybePop());
    switch (skin.layout) {
      case AppLayout.pinned:
        return ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              height: safeTop + _pinnedHeaderH,
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(4, safeTop + 4, 4, 0),
              decoration: BoxDecoration(
                color: withA(p.dark ? const Color(0xFF161618) : const Color(0xFFF7F7F9), .72),
                border: Border(bottom: BorderSide(color: withA(p.line, .7), width: .5)),
              ),
              child: Stack(alignment: Alignment.topCenter, children: [
                Pressable(
                  onTap: () => _showInfo(chat),
                  haptic: false,
                  builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
                    skin.avatar(p, _store.initialsFor(chat), 38, chat.guid.hashCode.abs(), group: chat.isGroup, image: _store.avatars.forChat(chat)),
                    const SizedBox(height: 3),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      ConstrainedBox(constraints: const BoxConstraints(maxWidth: 220), child: Text(_store.titleFor(chat), maxLines: 1, overflow: TextOverflow.ellipsis, style: skin.caption(p).copyWith(color: p.text, fontSize: 12.5, fontWeight: FontWeight.w600))),
                      const SizedBox(width: 2),
                      Ic('chevron', size: 11, color: p.text3),
                    ]),
                    if (typing) Text('typing…', style: skin.caption(p).copyWith(fontSize: 10.5, color: p.accent)),
                  ]),
                ),
                if (back != null) Positioned(left: 0, top: 0, child: back),
              ]),
            ),
          ),
        );
      case AppLayout.material:
        return Padding(
          padding: EdgeInsets.fromLTRB(widget.wide ? 16 : 4, safeTop + 8, 6, 8),
          child: Row(children: [
            if (back != null) back,
            avatar,
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_store.titleFor(chat), maxLines: 1, overflow: TextOverflow.ellipsis, style: skin.title(p).copyWith(fontSize: 19, fontWeight: FontWeight.w500)),
                Text(subtitle, style: skin.caption(p).copyWith(fontSize: 12.5, color: typing ? p.accent : p.text2)),
              ]),
            ),
            BareIcon('more', label: 'Chat details', onTap: () => _showInfo(chat)),
          ]),
        );
      case AppLayout.folders:
        return Container(
          color: p.surface,
          padding: EdgeInsets.fromLTRB(widget.wide ? 16 : 2, safeTop + 6, 4, 6),
          child: Row(children: [
            if (back != null) back,
            avatar,
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_store.titleFor(chat), maxLines: 1, overflow: TextOverflow.ellipsis, style: skin.headline(p).copyWith(fontWeight: FontWeight.w600)),
                Text(typing ? 'typing…' : (chat.isGroup ? '${chat.participants.length + 1} members' : 'iMessage'), style: skin.caption(p).copyWith(fontSize: 13, color: typing ? p.accent : p.text2)),
              ]),
            ),
            BareIcon('more', label: 'Chat details', color: p.text2, onTap: () => _showInfo(chat)),
          ]),
        );
      case AppLayout.standard:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(widget.wide ? 16 : 10, safeTop + 10, 14, 10),
            child: Row(children: [
              if (!widget.wide) ...[SkIconButton('back', size: 42, onTap: widget.onBack ?? () => Navigator.of(context).maybePop()), const SizedBox(width: 10)],
              Pressable(
                onTap: () => _showInfo(chat),
                haptic: false,
                builder: (_) => skin.avatar(p, _store.initialsFor(chat), 44, chat.guid.hashCode.abs(), group: chat.isGroup, image: _store.avatars.forChat(chat)),
              ),
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
        ]);
    }
  }

  Widget _composer(Chat chat, double safeBottom) {
    final skin = context.skin, p = context.pal;
    final hint = chat.isSms ? 'Text message' : 'iMessage';
    final hasText = _text.text.trim().isNotEmpty;
    switch (skin.layout) {
      case AppLayout.pinned:
        return Padding(
          padding: EdgeInsets.fromLTRB(10, 6, 12, 10 + safeBottom),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Semantics(
                button: true,
                label: 'Attach photo or video',
                child: Pressable(
                  onTap: () => _attach(chat),
                  builder: (_) => Container(width: 38, height: 38, decoration: BoxDecoration(shape: BoxShape.circle, color: p.surface2), child: Center(child: Ic('plus', size: 20, color: p.text2))),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SkField(
                controller: _text,
                hint: hint,
                maxLines: 5,
                action: TextInputAction.newline,
                trailing: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: hasText ? 1 : .35,
                  child: Semantics(
                    button: true,
                    label: 'Send',
                    child: Pressable(
                      onTap: hasText ? () => _send(chat) : null,
                      builder: (_) => Container(
                        width: 34,
                        height: 34,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(shape: BoxShape.circle, color: skin.outgoingBubble(p)),
                        child: Center(child: Ic('arrowup', size: 19, color: skin.outgoingText(p), stroke: 2.8)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        );
      case AppLayout.material:
        return Padding(
          padding: EdgeInsets.fromLTRB(10, 6, 10, 12 + safeBottom),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: SkField(
                controller: _text,
                hint: hint,
                maxLines: 5,
                action: TextInputAction.newline,
                leading: BareIcon('plus', label: 'Attach', onTap: () => _attach(chat)),
                trailing: BareIcon('image', label: 'Photos and videos', onTap: () => _attach(chat)),
              ),
            ),
            const SizedBox(width: 8),
            _SendButton(enabled: hasText, onTap: () => _send(chat), size: 54),
          ]),
        );
      case AppLayout.folders:
        return Container(
          color: p.surface,
          padding: EdgeInsets.fromLTRB(4, 4, 8, 4 + safeBottom),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Padding(padding: const EdgeInsets.only(bottom: 2), child: BareIcon('paperclip', label: 'Attach', color: p.text2, onTap: () => _attach(chat))),
            Expanded(child: SkField(controller: _text, hint: 'Write a message…', maxLines: 5, action: TextInputAction.newline)),
            const SizedBox(width: 6),
            Padding(padding: const EdgeInsets.only(bottom: 2), child: _SendButton(enabled: hasText, onTap: () => _send(chat), size: 46)),
          ]),
        );
      case AppLayout.standard:
        return Padding(
          padding: EdgeInsets.fromLTRB(12, 6, 12, 12 + safeBottom),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            SkIconButton('image', size: 48, onTap: () => _attach(chat)),
            const SizedBox(width: 10),
            Expanded(child: SkField(controller: _text, hint: hint, maxLines: 5, action: TextInputAction.newline)),
            const SizedBox(width: 10),
            _SendButton(enabled: hasText, onTap: () => _send(chat)),
          ]),
        );
    }
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
          ListenableBuilder(
            listenable: _store.avatars,
            builder: (context, _) => Column(children: [
              Center(child: skin.avatar(p, _store.initialsFor(chat), 84, chat.guid.hashCode.abs(), group: chat.isGroup, image: _store.avatars.forChat(chat))),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: SkButton('Change photo', primary: false, icon: 'image', onTap: () async {
                    final ok = await _store.avatars.pickFor(chat);
                    if (ok && mounted) Toaster.show(context, 'Photo updated', icon: 'check');
                  }),
                ),
                if (_store.avatars.hasCustom(chat.guid)) ...[
                  const SizedBox(width: 12),
                  Expanded(child: SkButton('Remove', primary: false, icon: 'x', onTap: () => _store.avatars.clearFor(chat))),
                ],
              ]),
              const SizedBox(height: 6),
              Text('Only changes how this chat looks on your phone.', textAlign: TextAlign.center, style: skin.caption(p)),
              const SizedBox(height: 14),
            ]),
          ),
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
  final double size;
  const _SendButton({required this.enabled, required this.onTap, this.size = 50});
  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    return Pressable(
      onTap: enabled ? onTap : null,
      builder: (pressed) => AnimatedScale(
        duration: const Duration(milliseconds: 200),
        scale: enabled ? 1 : .9,
        child: SizedBox(
          width: size,
          height: size,
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
      child: Center(
        child: skin.layout == AppLayout.folders
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                decoration: BoxDecoration(color: withA(p.surface, .92), borderRadius: BorderRadius.circular(12)),
                child: Text(label, style: skin.caption(p).copyWith(color: p.text, fontWeight: FontWeight.w500)),
              )
            : Text(skin.upperHeadings ? '— ${label.toUpperCase()} —' : label, style: skin.caption(p)),
      ),
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
    final maxW = math.min(MediaQuery.of(context).size.width * .74, 460.0) - (skin.layout == AppLayout.material && chat.isGroup && !m.isFromMe ? 38 : 0);
    final textColor = out ? skin.outgoingText(p) : p.text;
    final reacts = (reactions ?? {}).entries.where((e) => e.value > 0).map((e) => reactionEmoji[e.key] ?? '').join();
    final layout = skin.layout;
    final sender = m.handle == null ? '' : store.nameFor(m.handle!.address);
    final nameInside = layout == AppLayout.folders && chat.isGroup && !out && showName && m.handle != null && m.text.isNotEmpty;
    final withAvatar = layout == AppLayout.material && chat.isGroup && !out;

    final parts = <Widget>[];
    for (final a in m.attachments) {
      parts.add(Padding(padding: const EdgeInsets.only(bottom: 4), child: _AttachmentView(a: a, outgoing: out)));
    }
    if (m.text.isNotEmpty) {
      parts.add(skin.bubble(
        p,
        outgoing: out,
        tail: tail,
        child: layout == AppLayout.folders
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                if (nameInside)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(sender, style: skin.caption(p).copyWith(fontSize: 13.5, fontWeight: FontWeight.w600, color: senderColor(p, m.handle!.address))),
                  ),
                Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.end, spacing: 8, children: [
                  LinkText(m.text, style: skin.body(p).copyWith(color: textColor), linkColor: out ? skin.outgoingText(p) : p.accent),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(clockLabel(m.dateCreated), style: skin.caption(p).copyWith(fontSize: 11, color: out ? withA(skin.outgoingText(p), .7) : p.text3)),
                  ),
                ]),
              ])
            : LinkText(m.text, style: skin.body(p).copyWith(color: textColor), linkColor: out ? skin.outgoingText(p) : p.accent),
      ));
      final links = findLinks(m.text);
      if (links.isNotEmpty) parts.add(LinkCard(links.first.url));
    }

    Widget bubble = Column(crossAxisAlignment: out ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: parts);
    if (m.sending) bubble = Opacity(opacity: .6, child: bubble);

    Widget result = Column(crossAxisAlignment: out ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
      if (showName && m.handle != null && !nameInside)
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 3),
          child: Text(sender, style: skin.caption(p).copyWith(color: layout == AppLayout.folders ? senderColor(p, m.handle!.address) : p.text2)),
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
    if (withAvatar) {
      result = Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        SizedBox(
          width: 30,
          child: tail && m.handle != null ? skin.avatar(p, sender.trim().isEmpty ? '?' : sender.trim()[0].toUpperCase(), 30, m.handle!.address.hashCode.abs()) : null,
        ),
        const SizedBox(width: 8),
        Flexible(child: result),
      ]);
    }
    return result;
  }
}

/// A steady colour per person for names in group chats (Folders design).
Color senderColor(Palette p, String address) {
  const dark = [Color(0xFFFF7A7D), Color(0xFF6FB4FF), Color(0xFFF2C14E), Color(0xFF7DD3A8), Color(0xFFC49BFF)];
  const light = [Color(0xFFC62828), Color(0xFF1565C0), Color(0xFF8D6E00), Color(0xFF2E7D32), Color(0xFF6A3DB8)];
  final l = p.dark ? dark : light;
  return l[address.hashCode.abs() % l.length];
}

String clockLabel(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')}';
}

/// Faint dotted chat wallpaper (Folders design).
class _DotsPainter extends CustomPainter {
  final Color dot;
  final Color base;
  _DotsPainter(this.dot, this.base);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final paint = Paint()..color = dot;
    const step = 22.0;
    for (var y = 0.0, row = 0; y < size.height + step; y += step / 2, row++) {
      for (var x = row.isOdd ? step / 2 : 0.0; x < size.width + step; x += step) {
        canvas.drawCircle(Offset(x, y), 1.3, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotsPainter o) => o.dot != dot || o.base != base;
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
          // Download the original and shrink it on the phone: the Mac's resized
          // copies lose the photo's rotation, so they showed up sideways.
          : Image(
              image: ResizeImage(NetworkImage(store.api!.attachmentUrl(a.guid), headers: store.api!.headers), width: 720, allowUpscaling: false),
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
    final isLocalVideo = localPath != null && RegExp(r'\.(mp4|mov|m4v|3gp|webm|mkv)$', caseSensitive: false).hasMatch(localPath);
    if (a.isVideo || isLocalVideo) {
      final api = store.api;
      final canPlay = localPath != null || api != null;
      return VideoTile(
        label: a.transferName,
        size: a.sizeLabel,
        outgoing: outgoing,
        onTap: canPlay
            ? () => openVideo(context, file: localPath, url: localPath == null ? api!.attachmentUrl(a.guid) : null, headers: api?.headers ?? const {}, title: a.transferName)
            : null,
      );
    }
    final icon = a.isVideo ? 'play' : a.isAudio ? 'mic' : 'file';
    final canOpen = localPath == null && store.api != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: canOpen ? () => openLink(store.api!.attachmentUrl(a.guid)) : null,
      child: _fileBubble(skin, p, icon),
    );
  }

  Widget _fileBubble(Skin skin, Palette p, String icon) {
    return skin.bubble(
      p,
      outgoing: outgoing,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Ic(icon, size: 20, color: outgoing ? skin.outgoingText(p) : p.accent),
        const SizedBox(width: 10),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(a.transferName, maxLines: 1, overflow: TextOverflow.ellipsis, style: skin.callout(p).copyWith(color: outgoing ? skin.outgoingText(p) : p.text)),
            if (a.sizeLabel.isNotEmpty) Text(a.sizeLabel, style: skin.caption(p).copyWith(color: outgoing ? withA(skin.outgoingText(p), .7) : p.text3)),
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


class _LoadError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _LoadError({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Ic('alert', size: 30, color: p.warning),
          const SizedBox(height: 12),
          Text('Couldn’t load this chat', style: skin.headline(p)),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center, style: skin.callout(p)),
          const SizedBox(height: 16),
          SizedBox(width: 160, child: SkButton('Try again', icon: 'refresh', onTap: onRetry)),
        ]),
      ),
    );
  }
}
