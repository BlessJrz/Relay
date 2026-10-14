import 'package:flutter/material.dart' show TextEditingController;
import 'package:flutter/widgets.dart';

import '../../api/models.dart';
import '../../state/store.dart';
import '../../state/ui_state.dart';
import '../kit/controls.dart';
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
    final skin = context.skin, p = context.pal, store = context.store;
    final title = widget.groupsOnly ? 'Groups' : 'Messages';
    final topPad = widget.wide ? 4.0 : MediaQuery.of(context).padding.top + 8;
    // Tutorial targets live on the Chats tab only, and only carry their keys while the tutorial is showing.
    final isFirst = !widget.groupsOnly && ui.showTips.value;
    return ListenableBuilder(
      listenable: Listenable.merge([store, ui.showTips]),
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
                          style: skin.upperHeadings ? skin.caption(p) : skin.callout(p),
                        ),
                      ),
                      if (skin.upperHeadings && store.latencyHistory.isNotEmpty) SizedBox(width: 70, child: Sparkline(store.latencyHistory, height: 16)),
                    ]),
                    const SizedBox(height: 14),
                    KeyedSubtree(
                      key: isFirst ? ui.keys['search'] : null,
                      child: SkField(
                        controller: _search,
                        hint: skin.upperHeadings ? 'search messages' : 'Search messages',
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
                        itemBuilder: (context, i) => Column(
                          key: ValueKey(list[i].guid),
                          children: [
                            if (i > 0) const SkDivider(indent: 76),
                            Stagger(
                              index: i,
                              child: ChatRow(chat: list[i], selected: list[i].guid == widget.selected, onTap: () => widget.onOpen(list[i])),
                            ),
                          ],
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
                style: (skin.upperHeadings ? skin.caption(p) : skin.caption(p).copyWith(fontSize: 11.5)).copyWith(color: unread > 0 ? p.accent : p.text3),
              ),
            ]),
            const SizedBox(height: 3),
            Row(children: [
              Expanded(
                child: Text(
                  store.previewFor(chat),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: skin.callout(p).copyWith(color: typing ? p.accent : (unread > 0 ? p.text : p.text2), fontStyle: typing ? FontStyle.italic : null),
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
      builder: (_) => skin.selectedFace(p, selected: selected, radius: skin.upperHeadings ? 2 : 20, child: body),
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

