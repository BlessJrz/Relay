import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/material.dart' show TextEditingController, TimeOfDay, showDatePicker, showTimePicker;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';

import '../../api/models.dart';
import '../../skins/skin.dart';
import '../../state/link_preview.dart';
import '../../state/schedule.dart';
import '../../state/store.dart';
import '../../state/video_thumbs.dart';
import '../kit/controls.dart';
import '../kit/icons.dart';
import '../kit/link_text.dart';
import '../kit/overlays.dart';
import '../kit/scope.dart';
import 'chat_list.dart';
import 'chat_media.dart';
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

  // "New messages" line and the jump-to-latest button.
  int _lastReadAtOpen = 0;
  bool _showJump = false;
  int _newWhileAway = 0;
  String? _newestSeen;

  // Drafts are saved shortly after you stop typing.
  Timer? _draftTimer;

  // Voice messages.
  AudioRecorder? _recorder;
  bool _recording = false;
  final _recWatch = Stopwatch();
  Timer? _recTick;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _text.addListener(_onText);
  }

  void _onText() {
    setState(() {});
    _draftTimer?.cancel();
    final guid = widget.chatGuid;
    _draftTimer = Timer(const Duration(milliseconds: 500), () => context.settings.setDraft(guid, _text.text));
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
      _draftTimer?.cancel();
      context.settings.setDraft(old.chatGuid, _text.text);
      _replyTo = null;
      _open();
    }
  }

  void _open() {
    _firstLoad = false;
    _loadStarted = false;
    _showJump = false;
    _newWhileAway = 0;
    _newestSeen = null;
    _store.openChat = widget.chatGuid;
    _lastReadAtOpen = _store.lastReadFor(widget.chatGuid);
    final draft = context.settings.draftFor(widget.chatGuid);
    _text.removeListener(_onText);
    _text.text = draft;
    _text.addListener(_onText);
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
    _draftTimer?.cancel();
    _store.settings.setDraft(widget.chatGuid, _text.text);
    if (_store.openChat == widget.chatGuid) _store.openChat = null;
    _recTick?.cancel();
    _recorder?.dispose();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final away = _scroll.position.pixels > 500;
    if (away != _showJump) setState(() => _showJump = away);
    if (_scroll.position.pixels < 80 && _newWhileAway != 0) setState(() => _newWhileAway = 0);
    if (_loadingOlder || !_store.hasMore(widget.chatGuid)) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
      _loadingOlder = true;
      _store.loadMessages(widget.chatGuid, older: true).whenComplete(() => _loadingOlder = false);
    }
  }

  void _jumpToLatest() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(0, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    setState(() => _newWhileAway = 0);
  }

  Future<void> _send(Chat chat) async {
    final t = _text.text;
    if (t.trim().isEmpty) return;
    final reply = _replyTo?.guid;
    _text.clear();
    _draftTimer?.cancel();
    context.settings.setDraft(chat.guid, '');
    setState(() => _replyTo = null);
    HapticFeedback.lightImpact();
    await _store.sendText(chat, t, replyTo: reply);
    if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  // ------------------------------------------------------------ attachments

  Future<void> _pick(Chat chat, Future<XFile?> Function(ImagePicker) how) async {
    try {
      final x = await how(ImagePicker());
      if (x == null) return;
      await _store.sendFile(chat, File(x.path));
    } catch (e) {
      if (mounted) Toaster.show(context, 'Couldn’t open that: $e', icon: 'alert');
    }
  }

  void _gallery(Chat chat) => _pick(chat, (p) => p.pickMedia(imageQuality: 90));
  void _camera(Chat chat) => _pick(chat, (p) => p.pickImage(source: ImageSource.camera, imageQuality: 90));

  void _attachMenu(Chat chat) {
    showSkSheet(context, title: 'Send', builder: (c) {
      void go(void Function() f) {
        Navigator.of(c).pop();
        f();
      }

      return RowGroup(children: [
        SettingsRow(icon: 'image', title: 'Photos & videos', onTap: () => go(() => _gallery(chat))),
        SettingsRow(icon: 'camera', title: 'Take a photo', onTap: () => go(() => _camera(chat))),
        SettingsRow(icon: 'play', title: 'Record a video', onTap: () => go(() => _pick(chat, (p) => p.pickVideo(source: ImageSource.camera)))),
        SettingsRow(icon: 'mic', title: 'Voice message', onTap: () => go(() => _startRecording())),
      ]);
    });
  }

  // ------------------------------------------------------------ voice messages

  Future<void> _startRecording() async {
    try {
      final r = _recorder ??= AudioRecorder();
      if (!await r.hasPermission()) {
        if (mounted) Toaster.show(context, 'Allow the microphone for Relay in Android Settings to send voice messages.', icon: 'mic');
        return;
      }
      final dir = await getTemporaryDirectory();
      await r.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100, numChannels: 1), path: '${dir.path}/Voice message ${DateTime.now().millisecondsSinceEpoch}.m4a');
      HapticFeedback.mediumImpact();
      _recWatch
        ..reset()
        ..start();
      _recTick?.cancel();
      _recTick = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted) setState(() {});
      });
      setState(() => _recording = true);
    } catch (e) {
      if (mounted) Toaster.show(context, 'Couldn’t start recording: $e', icon: 'alert');
    }
  }

  Future<void> _stopRecording(Chat chat, {required bool send}) async {
    _recTick?.cancel();
    _recWatch.stop();
    final r = _recorder;
    setState(() => _recording = false);
    if (r == null) return;
    try {
      if (!send || _recWatch.elapsedMilliseconds < 700) {
        await r.cancel();
        if (send && mounted) Toaster.show(context, 'Too short — tap the mic and talk a little longer.', icon: 'mic');
        return;
      }
      final path = await r.stop();
      if (path != null) await _store.sendFile(chat, File(path));
    } catch (e) {
      if (mounted) Toaster.show(context, 'Couldn’t send the recording: $e', icon: 'alert');
    }
  }

  // ------------------------------------------------------------ send later

  void _sendLater(Chat chat) {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final now = DateTime.now();
    showSkSheet(context, title: 'Send later', builder: (c) {
      Future<void> pick(DateTime at) async {
        Navigator.of(c).pop();
        if (at.isBefore(DateTime.now().add(const Duration(minutes: 1)))) {
          Toaster.show(context, 'Pick a time in the future.', icon: 'alert');
          return;
        }
        final err = await _store.scheduleMessage(chat, text, at);
        if (!mounted) return;
        if (err != null) {
          Toaster.show(context, err, icon: 'alert');
        } else {
          _text.clear();
          context.settings.setDraft(chat.guid, '');
          Toaster.show(context, 'Your Mac will send it ${scheduleLabel(at, DateTime.now())}', icon: 'check');
        }
      }

      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('“$text”', maxLines: 2, overflow: TextOverflow.ellipsis, style: c.skin.callout(c.pal)),
        const SizedBox(height: 12),
        RowGroup(children: [
          for (final (label, at) in schedulePresets(now)) SettingsRow(icon: 'bell', title: label, onTap: () => pick(at)),
          SettingsRow(
            icon: 'sliders',
            title: 'Pick a date and time…',
            onTap: () async {
              final d = await showDatePicker(context: c, initialDate: now, firstDate: now, lastDate: now.add(const Duration(days: 365)));
              if (d == null || !c.mounted) return;
              final t = await showTimePicker(context: c, initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))));
              if (t == null) return;
              await pick(DateTime(d.year, d.month, d.day, t.hour, t.minute));
            },
          ),
        ]),
        const SizedBox(height: 8),
        Text('Your Mac sends it at that time, even if your phone is off.', textAlign: TextAlign.center, style: c.skin.caption(c.pal)),
      ]);
    });
  }

  // ------------------------------------------------------------ message actions

  void _edit(Message m) {
    final ctrl = TextEditingController(text: m.text);
    showSkSheet(context, title: 'Edit message', builder: (c) {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SkField(controller: ctrl, hint: 'Message', maxLines: 5, autofocus: true),
        const SizedBox(height: 12),
        SkButton('Save', icon: 'check', onTap: () async {
          final t = ctrl.text.trim();
          Navigator.of(c).pop();
          if (t.isEmpty || t == m.text) return;
          final err = await _store.editMessage(m, t);
          if (err != null && mounted) Toaster.show(context, err, icon: 'alert');
        }),
        const SizedBox(height: 6),
        Text('People on older iPhones see “Edited to …” instead.', textAlign: TextAlign.center, style: c.skin.caption(c.pal)),
      ]);
    });
  }

  void _actions(Chat chat, Message m) {
    final skin = context.skin, p = context.pal;
    final age = DateTime.now().millisecondsSinceEpoch - m.dateCreated;
    final mineLive = m.isFromMe && _store.privateApi && !m.sending && !m.queued && !m.failed && m.dateRetracted == null && !chat.isSms;
    final canEdit = mineLive && m.text.isNotEmpty && age < 15 * 60 * 1000;
    final canUnsend = mineLive && age < 2 * 60 * 1000;
    final media = m.attachments.where((a) => (a.isImage || a.isVideo) && !(a.mimeType ?? '').startsWith('local/')).toList();
    showSkSheet(context, builder: (c) {
      void go(void Function() f) {
        Navigator.of(c).pop();
        f();
      }

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
          Text('Reactions, replies, editing and unsending need the Private API on your Mac.', textAlign: TextAlign.center, style: skin.caption(p)),
        ],
        const SizedBox(height: 14),
        RowGroup(children: [
          if (m.text.isNotEmpty)
            SettingsRow(icon: 'copy', title: 'Copy text', onTap: () => go(() {
                  Clipboard.setData(ClipboardData(text: m.text));
                  Toaster.show(context, 'Copied', icon: 'check');
                })),
          if (_store.privateApi && !m.queued && !m.sending) SettingsRow(icon: 'reply', title: 'Reply', onTap: () => go(() => setState(() => _replyTo = m))),
          for (final a in media) SettingsRow(icon: 'download', title: a.isVideo ? 'Save video to phone' : 'Save photo to phone', onTap: () => go(() => saveAttachment(context, a))),
          if (canEdit) SettingsRow(icon: 'pencil', title: 'Edit', onTap: () => go(() => _edit(m))),
          if (canUnsend)
            SettingsRow(icon: 'x', title: 'Unsend', titleColor: p.danger, iconColor: p.danger, onTap: () => go(() async {
                  final err = await _store.unsendMessage(m);
                  if (err != null && mounted) Toaster.show(context, err, icon: 'alert');
                })),
          if (m.failed) SettingsRow(icon: 'refresh', title: 'Try sending again', onTap: () => go(() => _store.retry(chat, m))),
        ]),
      ]);
    });
  }

  Future<void> _heart(Chat chat, Message m) async {
    if (!_store.privateApi || m.sending || m.queued) return;
    HapticFeedback.lightImpact();
    final err = await _store.react(chat, m, 'love');
    if (err != null && mounted) Toaster.show(context, err, icon: 'alert');
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
        final msgs = all.where((m) => !m.isReaction && (m.hasContent || m.isGroupEvent || m.dateRetracted != null)).toList();
        final lastMine = msgs.indexWhere((m) => m.isFromMe);
        final unreadFrom = firstUnreadIndex<Message>(msgs, _lastReadAtOpen, (m) => m.isFromMe, (m) => m.dateCreated);
        // Count messages that arrive while you're scrolled up.
        final newest = msgs.isEmpty ? null : msgs.first;
        if (_newestSeen != null && newest != null && newest.guid != _newestSeen && !newest.isFromMe && _showJump) _newWhileAway++;
        _newestSeen = newest?.guid;
        final typing = _store.typing.contains(chat.guid);
        final mq = MediaQuery.of(context);
        // Unfolded Pinned/Folders: the chat header runs up under the status bar (edge to edge).
        final edgeTop = widget.wide && (skin.layout == AppLayout.pinned || skin.layout == AppLayout.folders);
        final safeTop = widget.wide && !edgeTop ? 0.0 : mq.padding.top;
        final safeBottom = widget.wide ? 0.0 : mq.padding.bottom;
        final canReply = _store.privateApi;

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
              Positioned.fill(
                child: _wallpaper(all.isEmpty
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
                            if (idx == unreadFrom) const _NewMessagesLine(),
                            if (m.dateRetracted != null)
                              _EventLine(m, unsent: true)
                            else if (m.isGroupEvent && !m.hasContent)
                              _EventLine(m)
                            else
                              _SwipeToReply(
                                enabled: canReply && !m.sending && !m.queued,
                                onReply: () => setState(() => _replyTo = m),
                                child: _BubbleRow(
                                  chat: chat,
                                  m: m,
                                  showName: chat.isGroup && !m.isFromMe && firstOfRun,
                                  tail: lastOfRun,
                                  reactions: reactions[m.guid],
                                  status: idx == lastMine ? _statusFor(m) : null,
                                  onLong: () => _actions(chat, m),
                                  onDoubleTap: canReply ? () => _heart(chat, m) : null,
                                ),
                              ),
                            SizedBox(height: lastOfRun ? 10 : 3),
                          ]);
                        },
                      )),
              ),
              if (floatHeader) Positioned(left: 0, right: 0, top: 0, child: _header(chat, typing, safeTop)),
              Positioned(
                right: 14,
                bottom: 12,
                child: IgnorePointer(
                  ignoring: !_showJump,
                  child: AnimatedScale(
                    scale: _showJump ? 1 : .6,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutBack,
                    child: AnimatedOpacity(
                      opacity: _showJump ? 1 : 0,
                      duration: const Duration(milliseconds: 160),
                      child: _JumpButton(count: _newWhileAway, onTap: _jumpToLatest),
                    ),
                  ),
                ),
              ),
            ]),
          ),
          // ------------------------------------------------ composer
          if (_replyTo != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: Row(children: [
                Ic('reply', size: 16, color: p.accent),
                const SizedBox(width: 8),
                Expanded(child: Text('Replying to “${_replyTo!.text.isEmpty ? 'attachment' : _replyTo!.text}”', maxLines: 1, overflow: TextOverflow.ellipsis, style: skin.caption(p).copyWith(color: p.text2))),
                BareIcon('x', label: 'Cancel reply', size: 16, color: p.text3, onTap: () => setState(() => _replyTo = null)),
              ]),
            ),
          if (_recording) _recordingBar(chat, safeBottom) else _composer(chat, safeBottom),
        ]);
        return content;
      },
    );
  }

  Widget _recordingBar(Chat chat, double safeBottom) {
    final skin = context.skin, p = context.pal;
    final secs = _recWatch.elapsed.inSeconds;
    final blink = (_recWatch.elapsedMilliseconds ~/ 500).isEven;
    return Padding(
      padding: EdgeInsets.fromLTRB(10, 6, 10, 10 + safeBottom),
      child: Row(children: [
        BareIcon('x', label: 'Cancel recording', color: p.text2, onTap: () => _stopRecording(chat, send: false)),
        const SizedBox(width: 4),
        Expanded(
          child: skin.well(
            p,
            radius: 999,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              height: 50,
              child: Row(children: [
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: blink ? 1 : .25,
                  child: Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: p.danger)),
                ),
                const SizedBox(width: 10),
                Text('${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}', style: skin.headline(p).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(width: 10),
                Expanded(child: Text('Recording…', style: skin.callout(p))),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _SendButton(hasText: true, onTap: () => _stopRecording(chat, send: true)),
      ]),
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
    // Empty box: the button records a voice message. Typed text: tap to send,
    // hold to send later.
    final send = _SendButton(
      hasText: hasText,
      onTap: hasText ? () => _send(chat) : _startRecording,
      onLongPress: hasText ? () => _sendLater(chat) : null,
      size: switch (skin.layout) { AppLayout.material => 54, AppLayout.folders => 46, AppLayout.pinned => 34, AppLayout.standard => 50 },
      compact: skin.layout == AppLayout.pinned,
    );
    final camera = BareIcon('camera', label: 'Take a photo', color: p.text2, onTap: () => _camera(chat));
    switch (skin.layout) {
      case AppLayout.pinned:
        return Padding(
          padding: EdgeInsets.fromLTRB(6, 6, 12, 10 + safeBottom),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Semantics(
                button: true,
                label: 'Attach',
                child: Pressable(
                  onTap: () => _attachMenu(chat),
                  builder: (_) => Container(width: 38, height: 38, margin: const EdgeInsets.only(left: 4), decoration: BoxDecoration(shape: BoxShape.circle, color: p.surface2), child: Center(child: Ic('plus', size: 20, color: p.text2))),
                ),
              ),
            ),
            if (!hasText) Padding(padding: const EdgeInsets.only(bottom: 2), child: camera) else const SizedBox(width: 8),
            Expanded(
              child: SkField(
                controller: _text,
                hint: hint,
                maxLines: 5,
                action: TextInputAction.newline,
                trailing: Padding(padding: const EdgeInsets.only(right: 4), child: send),
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
                leading: BareIcon('plus', label: 'Attach', onTap: () => _attachMenu(chat)),
                trailing: hasText ? null : Row(mainAxisSize: MainAxisSize.min, children: [camera, BareIcon('image', label: 'Photos and videos', color: p.text2, onTap: () => _gallery(chat))]),
              ),
            ),
            const SizedBox(width: 8),
            send,
          ]),
        );
      case AppLayout.folders:
        return Container(
          color: p.surface,
          padding: EdgeInsets.fromLTRB(4, 4, 8, 4 + safeBottom),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Padding(padding: const EdgeInsets.only(bottom: 2), child: BareIcon('paperclip', label: 'Attach', color: p.text2, onTap: () => _attachMenu(chat))),
            Expanded(child: SkField(controller: _text, hint: 'Write a message…', maxLines: 5, action: TextInputAction.newline, trailing: hasText ? null : camera)),
            const SizedBox(width: 6),
            Padding(padding: const EdgeInsets.only(bottom: 2), child: send),
          ]),
        );
      case AppLayout.standard:
        return Padding(
          padding: EdgeInsets.fromLTRB(12, 6, 12, 12 + safeBottom),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            SkIconButton('image', size: 48, onTap: () => _attachMenu(chat)),
            const SizedBox(width: 10),
            Expanded(child: SkField(controller: _text, hint: hint, maxLines: 5, action: TextInputAction.newline, trailing: hasText ? null : camera)),
            const SizedBox(width: 10),
            send,
          ]),
        );
    }
  }

  String? _statusFor(Message m) {
    if (m.queued) return 'Waiting for your Mac · sends when it’s back';
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
          ListenableBuilder(
            listenable: c.settings,
            builder: (context, _) => RowGroup(children: [
              SettingsRow(
                icon: 'image',
                title: 'Photos, videos & links',
                chevron: true,
                onTap: () {
                  Navigator.of(c).pop();
                  pushScreen(this.context, (_) => ChatMediaScreen(chat: chat));
                },
              ),
              SettingsRow(
                icon: c.settings.isMuted(chat.guid) ? 'belloff' : 'bell',
                title: 'Mute notifications',
                trailing: SkToggle(value: c.settings.isMuted(chat.guid), onChanged: (_) => c.settings.toggleMute(chat.guid)),
              ),
              SettingsRow(
                icon: 'pin',
                title: 'Pin to top',
                trailing: SkToggle(value: c.settings.isPinned(chat.guid), onChanged: (_) => c.settings.togglePin(chat.guid)),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          _ScheduledList(chat: chat),
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
  final bool hasText;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double size;
  final bool compact;
  const _SendButton({required this.hasText, required this.onTap, this.onLongPress, this.size = 50, this.compact = false});
  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    final icon = hasText ? (compact ? 'arrowup' : 'send') : 'mic';
    final face = compact
        ? (bool pressed) => AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: size,
              height: size,
              decoration: BoxDecoration(shape: BoxShape.circle, color: hasText ? skin.outgoingBubble(p) : const Color(0x00000000)),
              child: Center(child: Ic(icon, size: size * .56, color: hasText ? skin.outgoingText(p) : p.text2, stroke: hasText ? 2.8 : null)),
            )
        : (bool pressed) => SizedBox(
              width: size,
              height: size,
              child: skin.buttonFace(p, primary: hasText, pressed: pressed, radius: 999, child: Center(child: Ic(icon, size: size * .42, color: hasText ? p.onAccent : p.text))),
            );
    return Semantics(
      button: true,
      label: hasText ? 'Send (hold to send later)' : 'Record a voice message',
      child: Pressable(onTap: onTap, onLongPress: onLongPress, builder: face),
    );
  }
}

/// "New messages" line above the first message you haven't seen.
class _NewMessagesLine extends StatelessWidget {
  const _NewMessagesLine();
  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    final c = skin.badge(p);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Expanded(child: Container(height: 1, color: withA(c, .5))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('New messages', style: skin.caption(p).copyWith(color: c, fontWeight: FontWeight.w600))),
        Expanded(child: Container(height: 1, color: withA(c, .5))),
      ]),
    );
  }
}

/// Round "jump to latest" button, with a count of messages that came in while you scrolled up.
class _JumpButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _JumpButton({required this.count, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    return Semantics(
      button: true,
      label: count > 0 ? '$count new messages, jump to latest' : 'Jump to latest',
      child: Pressable(
        onTap: onTap,
        builder: (_) => Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(shape: BoxShape.circle, color: p.surface2, boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 10, offset: Offset(0, 3))]),
            child: Center(child: Ic('down', size: 22, color: p.text)),
          ),
          if (count > 0) Positioned(top: -6, right: -4, child: UnreadBadge(count)),
        ]),
      ),
    );
  }
}

/// Swipe a message to the right to reply to it.
class _SwipeToReply extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final VoidCallback onReply;
  const _SwipeToReply({required this.child, required this.enabled, required this.onReply});
  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> with SingleTickerProviderStateMixin {
  static const _trigger = 58.0, _max = 80.0;
  double _dx = 0;
  bool _armed = false;
  late final AnimationController _back = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
    ..addListener(() => setState(() => _dx = _from * (1 - Curves.easeOutCubic.transform(_back.value))));
  double _from = 0;

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  void _update(DragUpdateDetails d) {
    final next = (_dx + d.delta.dx * .7).clamp(0.0, _max);
    final armed = next >= _trigger;
    if (armed && !_armed) HapticFeedback.selectionClick();
    setState(() {
      _dx = next;
      _armed = armed;
    });
  }

  void _end([DragEndDetails? _]) {
    if (_armed) widget.onReply();
    _armed = false;
    _from = _dx;
    _back.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final p = context.pal;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: _end,
      onHorizontalDragCancel: _end,
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.centerLeft, children: [
        if (_dx > 4)
          Positioned(
            left: 0,
            child: Opacity(
              opacity: (_dx / _trigger).clamp(0.0, 1.0),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(shape: BoxShape.circle, color: _armed ? p.accent : p.surface2),
                child: Center(child: Ic('reply', size: 17, color: _armed ? p.onAccent : p.text2)),
              ),
            ),
          ),
        Transform.translate(offset: Offset(_dx, 0), child: widget.child),
      ]),
    );
  }
}

/// Messages waiting on the Mac to send later, with a way to cancel them.
class _ScheduledList extends StatefulWidget {
  final Chat chat;
  const _ScheduledList({required this.chat});
  @override
  State<_ScheduledList> createState() => _ScheduledListState();
}

class _ScheduledListState extends State<_ScheduledList> {
  late Future<List<ScheduledMessage>> _f = context.store.scheduledFor(widget.chat);

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    return FutureBuilder<List<ScheduledMessage>>(
      future: _f,
      builder: (context, snap) {
        final list = snap.data ?? const <ScheduledMessage>[];
        if (list.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: RowGroup(label: 'Sending later', children: [
            for (final m in list)
              SettingsRow(
                icon: 'bell',
                title: m.text,
                subtitle: scheduleLabel(DateTime.fromMillisecondsSinceEpoch(m.scheduledFor), DateTime.now()),
                trailing: BareIcon('x', label: 'Cancel', color: p.danger, onTap: () async {
                  final ok = await context.store.cancelScheduled(m);
                  if (!mounted) return;
                  if (!ok) Toaster.show(context, 'Couldn’t cancel it on your Mac.', icon: 'alert');
                  setState(() => _f = context.store.scheduledFor(widget.chat));
                }),
              ),
            Padding(padding: const EdgeInsets.all(8), child: Text('Hold the send button to schedule a message.', style: skin.caption(p))),
          ]),
        );
      },
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
            : Text(label, style: skin.caption(p)),
      ),
    );
  }
}

class _EventLine extends StatelessWidget {
  final Message m;
  final bool unsent;
  const _EventLine(this.m, {this.unsent = false});
  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal, store = context.store;
    final who = m.isFromMe ? 'You' : (m.handle != null ? store.nameFor(m.handle!.address) : 'Someone');
    final text = unsent
        ? '$who unsent a message'
        : m.groupTitle != null
            ? '$who named the group “${m.groupTitle}”'
            : '$who updated the group';
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
  final VoidCallback? onDoubleTap;
  const _BubbleRow({required this.chat, required this.m, required this.showName, required this.tail, this.reactions, this.status, required this.onLong, this.onDoubleTap});

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
      parts.add(Padding(padding: const EdgeInsets.only(bottom: 4), child: _AttachmentView(a: a, outgoing: out, onLong: onLong)));
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

    if (m.dateEdited != null) {
      parts.add(Padding(padding: const EdgeInsets.only(top: 2, left: 6, right: 6), child: Text('Edited', style: skin.caption(p).copyWith(fontSize: 11))));
    }
    Widget bubble = Column(crossAxisAlignment: out ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: parts);
    if (m.sending || m.queued) bubble = Opacity(opacity: .6, child: bubble);
    if (onDoubleTap != null) bubble = GestureDetector(onDoubleTap: onDoubleTap, child: bubble);

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
                child: skin.surface(p, strong: true, radius: 14, padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), child: Text(reacts, style: const TextStyle(fontSize: 13))),
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
            Text(status!, style: skin.caption(p).copyWith(color: m.failed ? p.danger : p.text3)),
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
  final VoidCallback? onLong;
  const _AttachmentView({required this.a, required this.outgoing, this.onLong});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal, store = context.store;
    final r = BorderRadius.circular(18);
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
        onTap: localPath == null ? () => showPhoto(context, a) : null,
        onLongPress: onLong,
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
        thumb: localPath != null
            ? VideoThumbs.instance.get('local:$localPath', localPath)
            : (api != null ? VideoThumbs.instance.get(a.guid, api.attachmentUrl(a.guid), headers: api.headers) : null),
        onLongPress: onLong,
        onTap: canPlay ? () => localPath != null ? openVideo(context, file: localPath, title: a.transferName) : playAttachment(context, a) : null,
      );
    }
    final isLocalAudio = localPath != null && RegExp(r'\.(m4a|aac|mp3|caf|amr|wav)$', caseSensitive: false).hasMatch(localPath);
    if ((a.isAudio || isLocalAudio) && (localPath != null || store.api != null)) {
      return _AudioBubble(
        key: ValueKey('audio-${a.guid}'),
        outgoing: outgoing,
        file: localPath,
        url: localPath == null ? store.api!.attachmentUrl(a.guid) : null,
        headers: store.api?.headers ?? const {},
        onLong: onLong,
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
}

/// A voice message / audio file: play button, progress and length.
class _AudioBubble extends StatefulWidget {
  final bool outgoing;
  final String? file;
  final String? url;
  final Map<String, String> headers;
  final VoidCallback? onLong;
  const _AudioBubble({super.key, required this.outgoing, this.file, this.url, this.headers = const {}, this.onLong});
  @override
  State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble> {
  VideoPlayerController? _c;
  bool _loading = false;
  bool _error = false;

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    var c = _c;
    if (c == null) {
      setState(() => _loading = true);
      c = widget.file != null ? VideoPlayerController.file(File(widget.file!)) : VideoPlayerController.networkUrl(Uri.parse(widget.url!), httpHeaders: widget.headers);
      try {
        await c.initialize();
        c.addListener(() {
          if (mounted) setState(() {});
        });
        _c = c;
      } catch (_) {
        await c.dispose();
        if (mounted) {
          setState(() {
            _loading = false;
            _error = true;
          });
        }
        return;
      }
      if (mounted) setState(() => _loading = false);
    }
    final v = c.value;
    if (v.isPlaying) {
      await c.pause();
    } else {
      if (v.position >= v.duration) await c.seekTo(Duration.zero);
      await c.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    final fg = widget.outgoing ? skin.outgoingText(p) : p.text;
    final v = _c?.value;
    final dur = v?.duration ?? Duration.zero;
    final pos = v?.position ?? Duration.zero;
    final frac = dur.inMilliseconds == 0 ? 0.0 : (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
    final playing = v?.isPlaying ?? false;
    final shown = playing || pos > Duration.zero ? pos : dur;
    return Pressable(
      onTap: _error && widget.url != null ? () => openLink(widget.url!) : _toggle,
      onLongPress: widget.onLong,
      haptic: false,
      builder: (_) => skin.bubble(
        p,
        outgoing: widget.outgoing,
        child: SizedBox(
          width: 200,
          child: Row(children: [
            SizedBox(
              width: 30,
              height: 30,
              child: Center(child: _loading ? Spinner(size: 18, color: fg) : Ic(_error ? 'external' : (playing ? 'pause' : 'play'), size: 20, color: fg)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Stack(children: [
                  Container(height: 4, color: withA(fg, .25)),
                  FractionallySizedBox(widthFactor: frac, child: Container(height: 4, color: fg)),
                ]),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _error ? 'Open' : (dur == Duration.zero ? 'Voice' : '${shown.inMinutes}:${(shown.inSeconds % 60).toString().padLeft(2, '0')}'),
              style: skin.caption(p).copyWith(color: withA(fg, .8), fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ]),
        ),
      ),
    );
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
                    shape: BoxShape.circle,
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
