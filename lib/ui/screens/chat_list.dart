import 'package:flutter/widgets.dart';

import '../../api/models.dart';
import '../../skins/skin.dart';
import '../../state/store.dart';
import '../../state/ui_state.dart';
import '../kit/controls.dart';
import '../kit/icons.dart';
import '../kit/motion.dart';
import '../kit/overlays.dart';
import '../kit/scope.dart';
import 'new_chat.dart';

String timeLabel(int ms) {
  if (ms == 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }
  if (diff == 1) return 'Yesterday';
  if (diff < 7) return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];
  return '${d.month}/${d.day}/${d.year % 100}';
}

/// Online / connecting / offline chip, tappable to open the Mac tab.
class ConnChip extends StatelessWidget {
  final bool showLatency;
  const ConnChip({super.key, this.showLatency = false});
  @override
  Widget build(BuildContext context) {
    final store = context.store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final (label, kind) = switch (store.conn) {
          Conn.online => store.liveLinkDown ? ('Live link off', 'warn') : ('Online', 'ok'),
          Conn.connecting => ('Connecting', 'warn'),
          Conn.badPassword => ('Wrong password', 'bad'),
          Conn.notConfigured => ('Not set up', 'idle'),
          Conn.offline => ('Offline', 'bad'),
        };
        return Pressable(
          onTap: () => ui.tab.value = 2,
          builder: (_) => StatusChip(label, kind: kind),
        );
      },
    );
  }
}

class ChatListPane extends StatefulWidget {
  final bool groupsOnly;
  final bool wide;
  final String? selected;
  final ValueChanged<Chat> onOpen;
  // Unfolded screen only: buttons that replace the side rail.
  final VoidCallback? onGroups;
  final VoidCallback? onSettings;
  final VoidCallback? onMac;
  final int rightPage; // 0 = chat, 2 = Mac status, 3 = settings
  const ChatListPane({super.key, this.groupsOnly = false, this.wide = false, this.selected, required this.onOpen, this.onGroups, this.onSettings, this.onMac, this.rightPage = 0});

  @override
  State<ChatListPane> createState() => _ChatListPaneState();
}

class _ChatListPaneState extends State<ChatListPane> {
  final _search = TextEditingController(text: ui.search.value);
  bool _pulled = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(Store s, Chat c, String q) {
    if (q.isEmpty) return true;
    final l = q.toLowerCase();
    if (s.titleFor(c).toLowerCase().contains(l)) return true;
    if ((c.lastMessage?.text ?? '').toLowerCase().contains(l)) return true;
    return c.participants.any((p) => p.address.toLowerCase().contains(l));
  }

  Future<void> _refresh() async {
    await context.store.refreshChats();
  }

  @override
  Widget build(BuildContext context) {
    if (context.skin.layout != AppLayout.standard) {
      return AltChatList(
        wide: widget.wide,
        selected: widget.selected,
        onOpen: widget.onOpen,
        onSettings: widget.onSettings ?? () => ui.tab.value = 3,
        onMac: widget.onMac ?? () => ui.tab.value = 2,
        rightPage: widget.rightPage,
      );
    }
    final skin = context.skin, p = context.pal, store = context.store;
    final title = widget.groupsOnly ? 'Groups' : 'Messages';
    final topPad = widget.wide ? 4.0 : MediaQuery.of(context).padding.top + 8;
    // Tutorial targets live on the Chats tab only, and only carry their keys while the tutorial is showing.
    final isFirst = !widget.groupsOnly && ui.showTips.value;
    return ListenableBuilder(
      listenable: Listenable.merge([store, ui.showTips, store.settings.drafts]),
      builder: (context, _) {
        final q = _search.text.trim();
        final list = store.chats.where((c) => (!widget.groupsOnly || c.isGroup) && _matches(store, c, q)).toList();
        // While searching, or when the list is too short to scroll, keep pulling in older chats.
        if (store.chatsHasMore && !store.chatsLoadingMore && !store.chatsLoading && (q.isNotEmpty || list.length < 14)) {
          WidgetsBinding.instance.addPostFrameCallback((_) => store.loadMoreChats());
        }
        final index = {for (var i = 0; i < list.length; i++) list[i].guid: i};
        return NotificationListener<ScrollUpdateNotification>(
          onNotification: (n) {
            if (n.metrics.pixels < -90 && !_pulled && !store.chatsLoading) {
              _pulled = true;
              Haptics.confirm();
              _refresh().whenComplete(() => _pulled = false);
            }
            // Near the bottom: bring in older chats.
            if (n.metrics.extentAfter < 900 && store.chatsHasMore && !store.chatsLoadingMore) {
              store.loadMoreChats();
            }
            return false;
          },
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(widget.wide ? 4 : 20, topPad, widget.wide ? 4 : 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (!widget.wide) const Eyebrow('Relay · iMessage bridge'),
                          const SizedBox(height: 2),
                          Heading(title, large: !widget.wide),
                        ]),
                      ),
                      if (store.chatsLoading) const Padding(padding: EdgeInsets.only(right: 10, bottom: 10), child: Spinner(size: 18)),
                      if (widget.wide && widget.onGroups != null) ...[
                        KeyedSubtree(
                          key: ui.showTips.value ? ui.keys['nav'] : null,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            SkIconButton('users', size: 42, color: widget.groupsOnly ? p.accent : null, onTap: widget.onGroups),
                            const SizedBox(width: 6),
                            SkIconButton('sliders', size: 42, color: widget.rightPage == 3 ? p.accent : null, onTap: widget.onSettings),
                          ]),
                        ),
                        const SizedBox(width: 6),
                      ],
                      KeyedSubtree(
                        key: isFirst ? ui.keys['plus'] : null,
                        child: SkIconButton('plus', size: widget.wide ? 42 : 46, onTap: () => showNewChat(context)),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      KeyedSubtree(
                        key: isFirst ? ui.keys['status'] : null,
                        child: widget.onMac == null ? const ConnChip() : GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onMac, child: const ConnChip()),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          store.latency != null && store.conn == Conn.online ? 'Mac · ${store.latency!.inMilliseconds} ms' : (store.lastError ?? ''),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: skin.callout(p),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    KeyedSubtree(
                      key: isFirst ? ui.keys['search'] : null,
                      child: SkField(
                        controller: _search,
                        hint: 'Search messages',
                        icon: 'search',
                        onChanged: (v) {
                          ui.search.value = v;
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                  ]),
                ),
              ),
              if (store.conn == Conn.notConfigured || (store.chats.isEmpty && store.conn != Conn.online && !store.chatsLoading))
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: widget.wide ? 4 : 20),
                  sliver: SliverToBoxAdapter(child: _Empty(conn: store.conn, error: store.lastError)),
                )
              else if (list.isEmpty && !store.chatsLoading)
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: widget.wide ? 4 : 20),
                  sliver: SliverToBoxAdapter(
                    child: SkCard(
                      child: Text(q.isNotEmpty ? 'No chats match “$q”.' : (widget.groupsOnly ? 'No group chats yet.' : 'No chats yet.'), style: skin.callout(p)),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(widget.wide ? 4 : 16, 0, widget.wide ? 4 : 16, 0),
                  sliver: DecoratedSliver(
                    decoration: skin.listDecoration(p),
                    sliver: SliverPadding(
                      padding: const EdgeInsets.all(6),
                      // Rows are built only as they scroll into view.
                      sliver: SliverList.builder(
                        itemCount: list.length,
                        findChildIndexCallback: (key) => key is ValueKey<String> ? index[key.value] : null,
                        itemBuilder: (context, i) => Glide(
                          key: ValueKey(list[i].guid),
                          index: i,
                          child: Column(
                            children: [
                              if (i > 0) const SkDivider(indent: 76),
                              Stagger(
                                index: i,
                                child: ChatSwipe(chat: list[i], child: ChatRow(chat: list[i], selected: list[i].guid == widget.selected, onTap: () => widget.onOpen(list[i]))),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: widget.wide ? 28 : 130,
                  child: store.chatsLoadingMore ? const Center(child: Spinner(size: 18)) : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ChatRow extends StatelessWidget {
  final Chat chat;
  final bool selected;
  final VoidCallback onTap;
  const ChatRow({super.key, required this.chat, required this.onTap, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal, store = context.store;
    final unread = store.unreadCount(chat);
    final typing = store.typing.contains(chat.guid);
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(children: [
        skin.avatar(p, store.initialsFor(chat), 50, chat.guid.hashCode.abs(), group: chat.isGroup, image: store.avatars.forChat(chat)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(store.titleFor(chat), maxLines: 1, overflow: TextOverflow.ellipsis, style: skin.headline(p))),
              const SizedBox(width: 8),
              Text(
                timeLabel(chat.lastDate),
                style: skin.caption(p).copyWith(fontSize: 11.5).copyWith(color: unread > 0 ? p.accent : p.text3),
              ),
            ]),
            const SizedBox(height: 3),
            Row(children: [
              Expanded(
                child: Text(
                  draftPreview(context, chat) != null ? 'Draft: ${draftPreview(context, chat)}' : store.previewFor(chat),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: skin.callout(p).copyWith(
                    color: draftPreview(context, chat) != null ? p.danger : (typing ? p.accent : (unread > 0 ? p.text : p.text2)),
                    fontStyle: typing ? FontStyle.italic : null,
                  ),
                ),
              ),
              if (unread > 0) ...[const SizedBox(width: 8), CountBadge(unread)],
              if (chat.isSms) ...[const SizedBox(width: 6), Text('SMS', style: skin.caption(p).copyWith(color: p.success))],
            ]),
          ]),
        ),
      ]),
    );
    return Pressable(
      onTap: onTap,
      scale: .985,
      builder: (_) => skin.selectedFace(p, selected: selected, radius: 20, child: body),
    );
  }
}

class _Empty extends StatelessWidget {
  final Conn conn;
  final String? error;
  const _Empty({required this.conn, this.error});
  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    final (icon, title, body) = switch (conn) {
      Conn.notConfigured => ('link', 'Not connected yet', 'Run the setup guide to connect Relay to your Mac.'),
      Conn.badPassword => ('lock', 'Wrong password', 'The server password changed on your Mac. Update it in Settings → Mac relay.'),
      Conn.connecting => ('wifi', 'Connecting to your Mac…', 'This usually takes a second.'),
      _ => ('alert', 'Can’t reach your Mac', error ?? 'Make sure the Mac is awake and BlueBubbles Server is running.'),
    };
    return SkCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [IconTile(icon), const SizedBox(width: 14), Expanded(child: Text(title, style: skin.headline(p)))]),
        const SizedBox(height: 10),
        Text(body, style: skin.callout(p)),
        const SizedBox(height: 16),
        Row(children: [
          if (conn == Conn.notConfigured)
            Expanded(child: SkButton('Start setup', icon: 'sparkle', onTap: () => context.settings.setupDone = false))
          else ...[
            Expanded(child: SkButton('Retry', primary: true, icon: 'refresh', onTap: () => context.store.connect())),
            const SizedBox(width: 12),
            Expanded(child: SkButton('Help', primary: false, icon: 'help', onTap: () => showTroubleshooting(context))),
          ],
        ]),
      ]),
    );
  }
}

void showTroubleshooting(BuildContext context) {
  showSkSheet(
    context,
    title: 'Can’t connect?',
    builder: (c) {
      final skin = c.skin, p = c.pal;
      Widget tip(String icon, String t, String b) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IconTile(icon, size: 36),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: skin.headline(p).copyWith(fontSize: 15)), const SizedBox(height: 2), Text(b, style: skin.callout(p))])),
            ]),
          );
      return SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          tip('monitor', 'Is the Mac awake?', 'Turn on “Keep macOS Awake” in BlueBubbles, or use Amphetamine if the lid is closed. Plug the Mac into power.'),
          tip('server', 'Is BlueBubbles Server running?', 'Open it on the Mac. The home screen should say the server is running and show a URL.'),
          tip('refresh', 'Did the URL change?', 'Cloudflare URLs change when the server restarts. Relay looks up the new one automatically if notifications are set up; otherwise scan the QR code again in Settings → Mac relay.'),
          tip('lock', 'Password', 'It must match the server password on the Mac exactly, including capitals.'),
          tip('wifi', 'Network', 'Try switching the phone between Wi‑Fi and mobile data. Some networks block tunnels.'),
        ]),
      );
    },
  );
}

void showNewChat(BuildContext context) => showSkSheet(context, title: 'New message', builder: (c) => const NewChatSheet());


// =====================================================================
// Pinned, Material and Folders layouts
// =====================================================================

/// A plain icon you can tap (no button face), 46 dp.
class BareIcon extends StatelessWidget {
  final String icon;
  final VoidCallback? onTap;
  final Color? color;
  final double size;
  final String? label;
  const BareIcon(this.icon, {super.key, this.onTap, this.color, this.size = 23, this.label});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label ?? icon,
        child: Pressable(
          onTap: onTap,
          scale: .9,
          builder: (pressed) => SizedBox(width: 46, height: 46, child: Center(child: Ic(icon, size: size, color: color ?? context.pal.text))),
        ),
      );
}

/// Unread count in the design's badge colour.
class UnreadBadge extends StatelessWidget {
  final int n;
  const UnreadBadge(this.n, {super.key});
  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: skin.badge(p), borderRadius: BorderRadius.circular(11)),
      child: Text(n > 99 ? '99+' : '$n', style: skin.caption(p).copyWith(color: skin.onBadge(p), fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

const folderNames = ['All', 'Unread', 'Groups', 'People'];
const folderIcons = ['chat', 'bell', 'users', 'smile'];

bool inFolder(Store s, Chat c, int folder) => switch (folder) {
      1 => s.isUnread(c),
      2 => c.isGroup,
      3 => !c.isGroup,
      _ => true,
    };

int folderUnread(Store s, int folder) => s.chats.where((c) => s.isUnread(c) && inFolder(s, c, folder)).length;

/// Long-press menu for a chat in the list.
void showChatMenu(BuildContext context, Chat chat) {
  final s = context.settings, store = context.store;
  showSkSheet(context, title: store.titleFor(chat), builder: (c) {
    final pinned = s.isPinned(chat.guid);
    final muted = s.isMuted(chat.guid);
    void go(void Function() f) {
      Navigator.of(c).pop();
      f();
    }

    return RowGroup(children: [
      SettingsRow(icon: 'pin', title: pinned ? 'Unpin' : 'Pin to top', onTap: () => go(() => s.togglePin(chat.guid))),
      if (store.isUnread(chat))
        SettingsRow(icon: 'check', title: 'Mark as read', onTap: () => go(() => store.markRead(chat)))
      else if (chat.lastMessage != null && !chat.lastMessage!.isFromMe)
        SettingsRow(icon: 'bell', title: 'Mark as unread', onTap: () => go(() => store.markUnread(chat))),
      SettingsRow(icon: muted ? 'bell' : 'belloff', title: muted ? 'Unmute' : 'Mute notifications', onTap: () => go(() => s.toggleMute(chat.guid))),
    ]);
  });
}

/// The chat list for the Pinned, Material and Folders designs.
class AltChatList extends StatefulWidget {
  final bool wide;
  final String? selected;
  final ValueChanged<Chat> onOpen;
  final VoidCallback onSettings;
  final VoidCallback onMac;
  final int rightPage;
  const AltChatList({super.key, required this.wide, this.selected, required this.onOpen, required this.onSettings, required this.onMac, this.rightPage = 0});
  @override
  State<AltChatList> createState() => _AltChatListState();
}

class _AltChatListState extends State<AltChatList> {
  final _search = TextEditingController(text: ui.search.value);
  late bool _searchOpen = ui.search.value.isNotEmpty;
  bool _pulled = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(Store s, Chat c, String q) {
    if (q.isEmpty) return true;
    final l = q.toLowerCase();
    if (s.titleFor(c).toLowerCase().contains(l)) return true;
    if ((c.lastMessage?.text ?? '').toLowerCase().contains(l)) return true;
    return c.participants.any((p) => p.address.toLowerCase().contains(l));
  }

  Widget _searchField({bool autofocus = false}) => KeyedSubtree(
        key: ui.showTips.value ? ui.keys['search'] : null,
        child: SkField(
          controller: _search,
          hint: 'Search',
          icon: 'search',
          autofocus: autofocus,
          onChanged: (v) {
            ui.search.value = v;
            setState(() {});
          },
        ),
      );

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _search.clear();
        ui.search.value = '';
      }
    });
  }

  void _menu() {
    showSkSheet(context, title: 'Relay', builder: (c) {
      return RowGroup(children: [
        SettingsRow(icon: 'sliders', title: 'Settings', onTap: () {
          Navigator.of(c).pop();
          widget.onSettings();
        }),
        SettingsRow(icon: 'server', title: 'Mac status', onTap: () {
          Navigator.of(c).pop();
          widget.onMac();
        }),
        SettingsRow(icon: 'compose', title: 'New message', onTap: () {
          Navigator.of(c).pop();
          showNewChat(context);
        }),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal, store = context.store, s = context.settings;
    final layout = skin.layout;
    final mq = MediaQuery.of(context);
    final wide = widget.wide;
    final tips = ui.showTips.value;
    return ListenableBuilder(
      listenable: Listenable.merge([store, ui.showTips, ui.folder, s, store.settings.drafts]),
      builder: (context, _) {
        final q = _search.text.trim();
        final folder = layout == AppLayout.folders ? ui.folder.value : 0;

        // Pinned chats (Pinned design): first time, pin your three most recent.
        var pins = <Chat>[];
        if (layout == AppLayout.pinned) {
          if (!s.pinsSeeded && store.chats.length >= 3) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!s.pinsSeeded) s.pinnedChats = store.chats.take(3).map((c) => c.guid).toList();
            });
          }
          if (q.isEmpty) pins = s.pinnedChats.map(store.chatByGuid).whereType<Chat>().take(9).toList();
        }
        final pinSet = {for (final c in pins) c.guid};
        final list = store.chats.where((c) => !pinSet.contains(c.guid) && inFolder(store, c, folder) && _matches(store, c, q)).toList();
        if (store.chatsHasMore && !store.chatsLoadingMore && !store.chatsLoading && (q.isNotEmpty || list.length < 14)) {
          WidgetsBinding.instance.addPostFrameCallback((_) => store.loadMoreChats());
        }
        final index = {for (var i = 0; i < list.length; i++) list[i].guid: i};
        final showStatus = store.conn != Conn.online || store.liveLinkDown;
        final hPad = wide ? 12.0 : 16.0;
        final topPad = wide ? 10.0 : mq.padding.top + 6;

        // ------------------------------------------------ header
        Widget header;
        switch (layout) {
          case AppLayout.pinned:
            header = Padding(
              padding: EdgeInsets.fromLTRB(hPad - 6, topPad, hPad - 6, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  KeyedSubtree(
                    key: tips ? ui.keys['nav'] : null,
                    child: Pressable(
                      onTap: widget.onSettings,
                      builder: (_) => Padding(padding: const EdgeInsets.all(10), child: Text('Settings', style: skin.body(p).copyWith(color: p.accent, fontWeight: FontWeight.w500))),
                    ),
                  ),
                  const Spacer(),
                  if (store.chatsLoading) const Padding(padding: EdgeInsets.only(right: 8), child: Spinner(size: 18)),
                  KeyedSubtree(key: tips ? ui.keys['plus'] : null, child: BareIcon('compose', color: p.accent, label: 'New message', onTap: () => showNewChat(context))),
                ]),
                Padding(padding: const EdgeInsets.fromLTRB(6, 2, 6, 10), child: Text('Messages', style: wide ? skin.title(p).copyWith(fontWeight: FontWeight.w800) : skin.display(p))),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: _searchField()),
              ]),
            );
          case AppLayout.material:
            header = Padding(
              padding: EdgeInsets.fromLTRB(hPad + 4, topPad + 8, hPad - 4, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [const TextSpan(text: 'Relay '), TextSpan(text: 'Messages', style: TextStyle(color: skin.badge(p)))]),
                      style: wide ? skin.title(p) : skin.display(p),
                    ),
                  ),
                  if (store.chatsLoading) const Padding(padding: EdgeInsets.only(right: 4), child: Spinner(size: 18)),
                  BareIcon(_searchOpen ? 'x' : 'search', label: 'Search', onTap: _toggleSearch),
                  const SizedBox(width: 4),
                  KeyedSubtree(
                    key: tips ? ui.keys['nav'] : null,
                    child: Semantics(
                      button: true,
                      label: 'Settings',
                      child: Pressable(
                        onTap: widget.onSettings,
                        builder: (_) => Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: p.surface2, border: Border.all(color: widget.rightPage == 3 ? skin.badge(p) : p.accent, width: 2.5)),
                          child: Center(child: Ic('sliders', size: 19, color: p.text)),
                        ),
                      ),
                    ),
                  ),
                ]),
                if (_searchOpen) ...[const SizedBox(height: 10), _searchField(autofocus: true)],
              ]),
            );
          case AppLayout.folders:
          case AppLayout.standard:
            header = Container(
              color: wide ? null : p.surface,
              padding: EdgeInsets.fromLTRB(wide ? hPad : 4, topPad, wide ? hPad : 6, wide ? 8 : 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (!wide)
                  Row(children: [
                    KeyedSubtree(key: tips ? ui.keys['nav'] : null, child: BareIcon('menu', label: 'Menu', onTap: _menu)),
                    const SizedBox(width: 6),
                    Expanded(child: Text('Relay', style: skin.display(p))),
                    if (store.chatsLoading) const Padding(padding: EdgeInsets.only(right: 4), child: Spinner(size: 18)),
                    BareIcon(_searchOpen ? 'x' : 'search', label: 'Search', onTap: _toggleSearch),
                  ]),
                if (wide || _searchOpen) Padding(padding: EdgeInsets.fromLTRB(wide ? 0 : 10, 4, wide ? 0 : 6, 8), child: _searchField(autofocus: !wide)),
                if (!wide) _FolderTabs(store: store),
              ]),
            );
        }

        final status = Padding(
          padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 4),
          child: Row(children: [
            KeyedSubtree(key: tips ? ui.keys['status'] : null, child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onMac, child: const ConnChip())),
            const SizedBox(width: 10),
            Expanded(child: Text(store.lastError ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: skin.caption(p))),
          ]),
        );

        Widget rowFor(int i) => ChatSwipe(
              chat: list[i],
              child: AltChatRow(
                chat: list[i],
                wide: wide,
                selected: list[i].guid == widget.selected,
                onTap: () => widget.onOpen(list[i]),
                onLong: () => showChatMenu(context, list[i]),
              ),
            );

        final listSliver = SliverList.builder(
          itemCount: list.length,
          findChildIndexCallback: (key) => key is ValueKey<String> ? index[key.value] : null,
          itemBuilder: (context, i) => Glide(key: ValueKey(list[i].guid), index: i, child: Stagger(index: i, child: rowFor(i))),
        );

        final scroll = NotificationListener<ScrollUpdateNotification>(
          onNotification: (n) {
            if (n.metrics.pixels < -90 && !_pulled && !store.chatsLoading) {
              _pulled = true;
              Haptics.confirm();
              store.refreshChats().whenComplete(() => _pulled = false);
            }
            if (n.metrics.extentAfter < 900 && store.chatsHasMore && !store.chatsLoadingMore) store.loadMoreChats();
            return false;
          },
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(child: header),
              if (showStatus || tips) SliverToBoxAdapter(child: status),
              if (pins.isNotEmpty)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 6),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisExtent: wide ? 108 : 128, crossAxisSpacing: 8, mainAxisSpacing: 6),
                    delegate: SliverChildBuilderDelegate(
                      (c, i) => _PinTile(chat: pins[i], size: wide ? 60 : 74, onTap: () => widget.onOpen(pins[i]), onLong: () => showChatMenu(context, pins[i])),
                      childCount: pins.length,
                    ),
                  ),
                ),
              if (store.conn == Conn.notConfigured || (store.chats.isEmpty && store.conn != Conn.online && !store.chatsLoading))
                SliverPadding(padding: EdgeInsets.all(hPad), sliver: SliverToBoxAdapter(child: _Empty(conn: store.conn, error: store.lastError)))
              else if (list.isEmpty && pins.isEmpty && !store.chatsLoading)
                SliverPadding(
                  padding: EdgeInsets.all(hPad + 8),
                  sliver: SliverToBoxAdapter(
                    child: Text(q.isNotEmpty ? 'No chats match “$q”.' : (folder == 0 ? 'No chats yet.' : 'Nothing in ${folderNames[folder]}.'), style: skin.callout(p), textAlign: TextAlign.center),
                  ),
                )
              else if (layout == AppLayout.material)
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: wide ? 0 : 8),
                  sliver: DecoratedSliver(
                    decoration: BoxDecoration(color: p.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
                    sliver: SliverPadding(padding: const EdgeInsets.only(top: 8), sliver: listSliver),
                  ),
                )
              else
                SliverPadding(padding: const EdgeInsets.only(top: 4), sliver: listSliver),
              SliverToBoxAdapter(
                child: Container(
                  height: wide ? 90 : 120,
                  color: layout == AppLayout.material && list.isNotEmpty ? p.surface : null,
                  margin: EdgeInsets.symmetric(horizontal: layout == AppLayout.material && !wide ? 8 : 0),
                  child: store.chatsLoadingMore ? const Center(child: Spinner(size: 18)) : null,
                ),
              ),
            ],
          ),
        );

        // Floating "new message" button (Material and Folders).
        Widget? fab;
        if (layout == AppLayout.material) {
          fab = Semantics(
            button: true,
            label: 'Start chat',
            child: Pressable(
              onTap: () => showNewChat(context),
              builder: (pressed) => Container(
                height: 56,
                padding: const EdgeInsets.fromLTRB(16, 0, 20, 0),
                decoration: BoxDecoration(
                  color: p.accent,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 16, offset: Offset(0, 6))],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Ic('chat', size: 21, color: p.onAccent),
                  const SizedBox(width: 10),
                  Text('Start chat', style: skin.headline(p).copyWith(color: p.onAccent, fontWeight: FontWeight.w600, fontSize: 16)),
                ]),
              ),
            ),
          );
        } else if (layout == AppLayout.folders && !wide) {
          fab = Semantics(
            button: true,
            label: 'New message',
            child: Pressable(
              onTap: () => showNewChat(context),
              builder: (pressed) => Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(shape: BoxShape.circle, color: p.accent, boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 14, offset: Offset(0, 4))]),
                child: Center(child: Ic('pencil', size: 23, color: p.onAccent)),
              ),
            ),
          );
        }

        return Stack(children: [
          Positioned.fill(child: scroll),
          if (fab != null)
            Positioned(
              right: 18,
              bottom: (wide ? 16 : mq.padding.bottom + 18),
              child: KeyedSubtree(key: tips && layout != AppLayout.pinned ? ui.keys['plus'] : null, child: fab),
            ),
        ]);
      },
    );
  }
}

class _FolderTabs extends StatelessWidget {
  final Store store;
  const _FolderTabs({required this.store});
  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(children: [
        for (var i = 0; i < folderNames.length; i++)
          Builder(builder: (context) {
            final on = ui.folder.value == i;
            final n = folderUnread(store, i);
            return Semantics(
              selected: on,
              button: true,
              child: Pressable(
                onTap: () => ui.folder.value = i,
                scale: .96,
                builder: (_) => AnimatedContainer(
                  duration: skin.moveDuration,
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: on ? p.accent : const Color(0x00000000), width: 3))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(folderNames[i], style: skin.callout(p).copyWith(color: on ? p.accent : p.text2, fontWeight: FontWeight.w500)),
                    if (n > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        constraints: const BoxConstraints(minWidth: 19),
                        height: 19,
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: on ? p.accent : p.inset, borderRadius: BorderRadius.circular(10)),
                        child: Text('$n', style: skin.caption(p).copyWith(color: on ? p.onAccent : p.text2, fontSize: 11, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ]),
                ),
              ),
            );
          }),
      ]),
    );
  }
}

/// Folder rail on the unfolded screen (Folders design).
class FolderRail extends StatelessWidget {
  final VoidCallback onSettings;
  final VoidCallback onMac;
  final int rightPage;
  const FolderRail({super.key, required this.onSettings, required this.onMac, this.rightPage = 0});
  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal, store = context.store;
    final mq = MediaQuery.of(context);
    Widget item(String icon, String label, bool on, VoidCallback onTap, {int count = 0}) => Semantics(
          button: true,
          selected: on,
          label: label,
          child: Pressable(
            onTap: onTap,
            scale: .95,
            builder: (_) => AnimatedContainer(
              duration: skin.moveDuration,
              width: 66,
              padding: const EdgeInsets.symmetric(vertical: 8),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(color: on ? p.tint : const Color(0x00000000), borderRadius: BorderRadius.circular(12)),
              child: Stack(clipBehavior: Clip.none, children: [
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Center(child: Ic(icon, size: 22, color: on ? p.accent : p.text2)),
                  const SizedBox(height: 4),
                  Center(child: Text(label, style: skin.caption(p).copyWith(color: on ? p.accent : p.text2, fontSize: 11))),
                ]),
                if (count > 0) Positioned(top: -2, right: 8, child: Transform.scale(scale: .85, child: UnreadBadge(count))),
              ]),
            ),
          ),
        );
    return ListenableBuilder(
      listenable: Listenable.merge([store, ui.folder]),
      builder: (context, _) => Container(
        width: 78,
        color: Color.lerp(p.bg, const Color(0xFF000000), p.dark ? .35 : .04),
        padding: EdgeInsets.only(top: mq.padding.top + 12, bottom: mq.padding.bottom + 12),
        child: Column(children: [
          for (var i = 0; i < folderNames.length; i++)
            item(folderIcons[i], folderNames[i], rightPage == 0 && ui.folder.value == i, () {
              ui.folder.value = i;
              if (rightPage != 0) ui.tab.value = 0;
            }, count: folderUnread(store, i)),
          const Spacer(),
          item('server', 'Mac', rightPage == 2, onMac),
          KeyedSubtree(key: ui.showTips.value ? ui.keys['nav'] : null, child: item('sliders', 'Settings', rightPage == 3, onSettings)),
          const SizedBox(height: 4),
          IconButtonPlain(onTap: () => showNewChat(context)),
        ]),
      ),
    );
  }
}

class IconButtonPlain extends StatelessWidget {
  final VoidCallback onTap;
  const IconButtonPlain({super.key, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Semantics(
      button: true,
      label: 'New message',
      child: Pressable(
        onTap: onTap,
        builder: (_) => Container(width: 48, height: 48, decoration: BoxDecoration(shape: BoxShape.circle, color: p.accent), child: Center(child: Ic('pencil', size: 20, color: p.onAccent))),
      ),
    );
  }
}

/// Big circle for a pinned chat, with a little preview bubble when it's unread.
class _PinTile extends StatelessWidget {
  final Chat chat;
  final double size;
  final VoidCallback onTap;
  final VoidCallback onLong;
  const _PinTile({required this.chat, required this.size, required this.onTap, required this.onLong});
  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal, store = context.store;
    final unread = store.isUnread(chat);
    return Pressable(
      onTap: onTap,
      onLongPress: onLong,
      scale: .94,
      builder: (_) => Column(children: [
        SizedBox(
          height: size + 16,
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
            skin.avatar(p, store.initialsFor(chat), size, chat.guid.hashCode.abs(), group: chat.isGroup, image: store.avatars.forChat(chat)),
            if (unread)
              Positioned(
                top: 0,
                left: 10,
                right: -4,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(11), border: Border.all(color: p.bg, width: 2)),
                    child: Text(store.previewFor(chat), maxLines: 1, overflow: TextOverflow.ellipsis, style: skin.caption(p).copyWith(color: p.text, fontSize: 11)),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (unread) ...[Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: p.accent)), const SizedBox(width: 4)],
          Flexible(child: Text(store.titleFor(chat), maxLines: 1, overflow: TextOverflow.ellipsis, style: skin.caption(p).copyWith(color: p.text, fontSize: 12.5))),
        ]),
      ]),
    );
  }
}

/// One chat in the list, drawn the way the current design lays it out.
class AltChatRow extends StatelessWidget {
  final Chat chat;
  final bool wide;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLong;
  const AltChatRow({super.key, required this.chat, required this.wide, required this.selected, required this.onTap, required this.onLong});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal, store = context.store, s = context.settings;
    final unread = store.unreadCount(chat);
    final isUnread = store.isUnread(chat);
    final typing = store.typing.contains(chat.guid);
    final draft = draftPreview(context, chat);
    final preview = draft != null ? 'Draft: $draft' : store.previewFor(chat);
    final previewColor = draft != null ? skin.badge(p) : null;
    final muted = s.isMuted(chat.guid);
    final time = timeLabel(chat.lastDate);
    final img = store.avatars.forChat(chat);
    final seed = chat.guid.hashCode.abs();
    final title = store.titleFor(chat);
    Widget body;

    switch (skin.layout) {
      case AppLayout.pinned:
        final av = wide ? 44.0 : 50.0;
        body = Padding(
          padding: EdgeInsets.fromLTRB(2, 10, wide ? 12 : 16, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 16,
              height: av,
              child: Center(child: isUnread ? Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: p.accent)) : null),
            ),
            skin.avatar(p, store.initialsFor(chat), av, seed, group: chat.isGroup, image: img),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line, width: .6))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: skin.headline(p))),
                    const SizedBox(width: 6),
                    if (muted) ...[Ic('belloff', size: 13, color: p.text3), const SizedBox(width: 4)],
                    Text(time, style: skin.callout(p).copyWith(fontSize: 13.5)),
                    const SizedBox(width: 4),
                    Ic('chevron', size: 14, color: p.text3),
                  ]),
                  const SizedBox(height: 2),
                  Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis, style: skin.callout(p).copyWith(color: previewColor ?? (typing ? p.accent : p.text2), fontSize: 14.5)),
                ]),
              ),
            ),
          ]),
        );
      case AppLayout.material:
        final av = wide ? 48.0 : 52.0;
        Widget avatar;
        if (chat.isGroup && img == null && chat.participants.length >= 2) {
          final a = store.nameFor(chat.participants[0].address), b = store.nameFor(chat.participants[1].address);
          String ini(String n) => n.trim().isEmpty ? '?' : n.trim()[0].toUpperCase();
          final small = av * .66;
          avatar = SizedBox(
            width: av,
            height: av,
            child: Stack(children: [
              Positioned(left: 0, top: 0, child: skin.avatar(p, ini(a), small, seed)),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? Color.alphaBlend(p.tint, p.surface) : p.surface, width: 2.5)),
                  child: skin.avatar(p, ini(b), small - 5, seed + 1),
                ),
              ),
            ]),
          );
        } else {
          avatar = skin.avatar(p, store.initialsFor(chat), av, seed, group: chat.isGroup, image: img);
        }
        final w = isUnread ? FontWeight.w700 : FontWeight.w400;
        body = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(children: [
            avatar,
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: skin.headline(p).copyWith(fontWeight: isUnread ? FontWeight.w700 : FontWeight.w500))),
                  const SizedBox(width: 8),
                  if (muted) ...[Ic('belloff', size: 13, color: p.text3), const SizedBox(width: 4)],
                  Text(time, style: skin.caption(p).copyWith(fontSize: 12.5, fontWeight: w, color: isUnread ? skin.badge(p) : p.text2)),
                ]),
                const SizedBox(height: 3),
                Row(children: [
                  Expanded(child: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: skin.callout(p).copyWith(fontWeight: w, color: previewColor ?? (typing ? p.accent : (isUnread ? p.text : p.text2))))),
                  if (unread > 0) ...[const SizedBox(width: 8), UnreadBadge(unread)],
                ]),
              ]),
            ),
          ]),
        );
      case AppLayout.folders:
      case AppLayout.standard:
        final av = wide ? 48.0 : 54.0;
        final cut = draft != null ? 6 : (chat.isGroup || preview.startsWith('You: ') ? preview.indexOf(': ') : -1);
        final who = cut > 0 && cut < 24 ? preview.substring(0, cut + 2) : '';
        final rest = who.isEmpty ? preview : preview.substring(who.length);
        final mine = chat.lastMessage?.isFromMe ?? false;
        final read = chat.lastMessage?.dateRead != null;
        body = Padding(
          padding: EdgeInsets.fromLTRB(wide ? 10 : 14, 8, wide ? 10 : 14, 0),
          child: Row(children: [
            skin.avatar(p, store.initialsFor(chat), av, seed, group: chat.isGroup, image: img),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.only(bottom: 9),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: wide ? const Color(0x00000000) : p.line))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    if (chat.isGroup) ...[Ic('users', size: 15, color: p.text2), const SizedBox(width: 5)],
                    Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: skin.headline(p).copyWith(fontWeight: FontWeight.w600, fontSize: 16))),
                    if (muted) ...[Ic('belloff', size: 13, color: p.text3), const SizedBox(width: 4)],
                    if (mine) ...[Ic(read ? 'checks' : 'check', size: 16, color: p.accent), const SizedBox(width: 4)],
                    Text(time, style: skin.caption(p).copyWith(fontSize: 12.5, color: p.text2)),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [TextSpan(text: who, style: TextStyle(color: previewColor ?? p.accent)), TextSpan(text: rest)]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: skin.callout(p).copyWith(color: typing ? p.accent : p.text2),
                      ),
                    ),
                    if (unread > 0) ...[const SizedBox(width: 8), UnreadBadge(unread)] else if (s.isPinned(chat.guid)) ...[const SizedBox(width: 8), Ic('pin', size: 15, color: p.text3)],
                  ]),
                ]),
              ),
            ),
          ]),
        );
    }

    return Pressable(
      onTap: onTap,
      onLongPress: onLong,
      scale: .99,
      builder: (_) => skin.selectedFace(p, selected: selected, radius: skin.layout == AppLayout.material ? 22 : (wide ? 12 : 0), child: body),
    );
  }
}


/// Swipe a chat right to mark it read / unread, left to mute / unmute.
class ChatSwipe extends StatelessWidget {
  final Chat chat;
  final Widget child;
  const ChatSwipe({super.key, required this.chat, required this.child});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal, store = context.store, s = context.settings;
    final unread = store.isUnread(chat);
    final muted = s.isMuted(chat.guid);
    final canUnread = chat.lastMessage != null && !chat.lastMessage!.isFromMe;
    Widget bg(Alignment align, Color color, String icon, String label) => Container(
          alignment: align,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(skin.layout == AppLayout.material ? 22 : 0)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Ic(icon, size: 22, color: const Color(0xFFFFFFFF)),
            const SizedBox(height: 3),
            Text(label, style: skin.caption(p).copyWith(color: const Color(0xFFFFFFFF), fontWeight: FontWeight.w600)),
          ]),
        );
    return Dismissible(
      key: ValueKey('swipe-${chat.guid}'),
      direction: canUnread || unread ? DismissDirection.horizontal : DismissDirection.endToStart,
      dismissThresholds: const {DismissDirection.startToEnd: .28, DismissDirection.endToStart: .28},
      background: bg(Alignment.centerLeft, p.accent, unread ? 'check' : 'bell', unread ? 'Read' : 'Unread'),
      secondaryBackground: bg(Alignment.centerRight, const Color(0xFF6B5CE7), muted ? 'bell' : 'belloff', muted ? 'Unmute' : 'Mute'),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          unread ? store.markRead(chat) : store.markUnread(chat);
        } else {
          s.toggleMute(chat.guid);
        }
        return false; // the row stays; only its state changes
      },
      child: child,
    );
  }
}

/// "Draft: …" / muted marker for chat rows.
String? draftPreview(BuildContext context, Chat chat) {
  final d = context.settings.draftFor(chat.guid).trim();
  return d.isEmpty ? null : d.replaceAll('\n', ' ');
}
