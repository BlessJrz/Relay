import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../api/models.dart';
import '../push/push.dart';
import '../state/share_intake.dart';
import '../state/store.dart';
import '../skins/skin.dart';
import '../state/ui_state.dart';
import '../state/updater.dart';
import 'kit/controls.dart';
import 'kit/nav.dart';
import 'kit/overlays.dart';
import 'kit/scope.dart';
import 'screens/chat_list.dart';
import 'screens/conversation.dart';
import 'screens/relay_screen.dart';
import 'screens/settings_screen.dart';
import 'tutorial/coach.dart';

/// Main app frame. Folded: one pane + floating nav bar. Unfolded (≥700 dp): side
/// rail + chat list + open conversation side by side.
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  StreamSubscription<MsgBanner>? _banners;
  bool _wide = false;
  int _shownTab = 0;
  int _dir = 1; // which way the last tab change went, for the slide

  @override
  void initState() {
    super.initState();
    ui.openChat.addListener(_onOpenChat);
    ShareIntake.listen(_onShared);
    // A quiet look for a newer build on GitHub (at most every 6 hours).
    if (Platform.isAndroid) {
      Future.delayed(const Duration(seconds: 4), () async {
        if (!mounted) return;
        final u = await Updater.instance.checkQuietly(context.settings.prefs);
        if (u == null || !mounted) return;
        Toaster.show(context, 'Tap to install', title: 'Relay build ${u.build} is ready', icon: 'download', duration: const Duration(seconds: 6), onTap: () => showUpdatePrompt(context, u));
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _banners?.cancel();
    final store = context.store;
    _banners = store.banners.listen((b) async {
      if (!mounted) return;
      final s = store;
      // In the background the push from the Mac does this; on screen, show a
      // real notification (heads-up) so it's seen even inside another chat.
      if (!Push.instance.appInForeground) return;
      final shown = await Push.instance.showWhileOpen(s.settings.prefs, b.chat.guid, b.message, title: b.chat.isGroup ? s.titleFor(b.chat) : null);
      if (shown || !mounted) return;
      Toaster.show(
        context,
        b.message.text.isNotEmpty ? b.message.text : (b.message.attachments.isNotEmpty ? '📎 Attachment' : 'New message'),
        title: b.chat.isGroup ? '${s.titleFor(b.chat)} · ${b.message.handle != null ? s.nameFor(b.message.handle!.address).split(' ').first : ''}' : s.titleFor(b.chat),
        icon: 'chat',
        onTap: () => ui.openChat.value = b.chat.guid,
      );
    });
  }

  @override
  void dispose() {
    _banners?.cancel();
    ui.openChat.removeListener(_onOpenChat);
    ShareIntake.stop();
    super.dispose();
  }

  /// On the folded screen, opening a chat pushes a full-screen conversation.
  void _onOpenChat() {
    final g = ui.openChat.value;
    if (g == null || _wide || !mounted) return;
    if (ui.tab.value > 1) ui.tab.value = 0;
    final nav = Navigator.of(context);
    nav.popUntil((r) => r.isFirst);
    pushScreen(context, (c) => _ConversationScreen(chatGuid: g)).then((_) {
      if (ui.openChat.value == g && !_wide) ui.openChat.value = null;
    });
  }

  /// Something was shared to Relay from another app: pick a chat, then send it.
  Future<void> _onShared(SharedContent c) async {
    if (!mounted) return;
    final chat = await showSkSheet<Chat>(context, title: 'Send to…', builder: (sc) => _SharePicker(content: c));
    if (chat == null || !mounted) return;
    final store = context.store;
    ui.openChat.value = chat.guid;
    final text = c.text?.trim() ?? '';
    for (final path in c.paths) {
      await store.sendFile(chat, File(path));
    }
    if (text.isNotEmpty) await store.sendText(chat, text);
  }

  void _open(Chat c) {
    if (_wide && ui.tab.value > 1) ui.tab.value = 0;
    // Tapping the chat that's already "open" (e.g. after folding) must still show it.
    if (ui.openChat.value == c.guid && !_wide) {
      _onOpenChat();
    } else {
      ui.openChat.value = c.guid;
    }
  }

  List<NavItem> _items(Store s) => [
        NavItem('chat', 'Chats', badge: s.totalUnread),
        const NavItem('users', 'Groups'),
        const NavItem('server', 'Mac'),
        const NavItem('sliders', 'Settings'),
      ];

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    // Screen width, not the space left over: the keyboard shrinks the space
    // every frame as it slides up, and that used to rebuild everything.
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return SizedBox.expand(child: Builder(builder: (context) {
      if (wide != _wide) {
        _wide = wide;
        // Folding while a chat is pushed: pop it and show it in the side pane instead.
        if (wide) {
          WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.of(context).popUntil((r) => r.isFirst));
        } else {
          // Folding with a chat open: carry it over to the front screen.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_wide && ui.openChat.value != null) _onOpenChat();
          });
        }
      }
      return ValueListenableBuilder<int>(
        valueListenable: ui.tab,
        builder: (context, tab, _) {
          if (tab != _shownTab) {
            _dir = tab > _shownTab ? 1 : -1;
            _shownTab = tab;
          }
          // Chat data changes are handled by the screens themselves; this frame
          // only needs to know which chat is open (and the tutorial).
          return ListenableBuilder(
          listenable: Listenable.merge([ui.openChat, ui.showTips]),
          builder: (context, _) {
            final body = wide ? _wideBody(tab) : _narrowBody(tab);
            // fit: expand so the frame always fills the screen. (Without it the
            // zero-size tutorial placeholder below sized the whole frame to 0x0.)
            return Stack(fit: StackFit.expand, children: [
              Positioned.fill(
                child: PopScope(
                  // Designs without a tab bar: Back closes Settings / Mac status first.
                  canPop: skin.layout == AppLayout.standard || tab < 2,
                  onPopInvokedWithResult: (didPop, _) {
                    if (!didPop) ui.tab.value = 0;
                  },
                  child: body,
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: ui.showTips,
                builder: (context, show, _) => show
                    ? Positioned.fill(
                        child: CoachMarks(onDone: () {
                          ui.showTips.value = false;
                          context.settings.tipsDone = true;
                        }),
                      )
                    : const Positioned(left: 0, top: 0, width: 0, height: 0, child: SizedBox.shrink()),
              ),
            ]);
          },
        );
        },
      );
    }));
  }

  Widget _page(int tab, {required bool wide}) => switch (tab) {
        1 => ChatListPane(groupsOnly: true, wide: wide, selected: ui.openChat.value, onOpen: _open),
        2 => RelayScreen(wide: wide),
        3 => SettingsScreen(wide: wide),
        _ => ChatListPane(wide: wide, selected: ui.openChat.value, onOpen: _open),
      };

  /// Cross-fade with a short slide in the direction you're moving. The page
  /// sits in its own layer so the animation just moves a finished picture.
  Widget _switcher(int tab, Widget page) => AnimatedSwitcher(
        duration: context.sc.d(const Duration(milliseconds: 340)),
        reverseDuration: context.sc.d(const Duration(milliseconds: 220)),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, if (current != null) current]),
        transitionBuilder: (child, a) {
          final incoming = child.key == ValueKey<int>(tab);
          final dx = (incoming ? .05 : -.05) * _dir;
          return FadeTransition(
            opacity: a,
            child: SlideTransition(position: Tween<Offset>(begin: Offset(dx, 0), end: Offset.zero).animate(a), child: child),
          );
        },
        child: KeyedSubtree(key: ValueKey<int>(tab), child: RepaintBoundary(child: page)),
      );

  /// Settings or Mac status opened from a design without a tab bar: full
  /// screen with a back button.
  Widget _subPage(int tab) {
    final mq = MediaQuery.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(8, mq.padding.top + 6, 8, 0),
        child: Row(children: [BareIcon('back', label: 'Back', onTap: () => ui.tab.value = 0)]),
      ),
      Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: _page(tab, wide: false))),
    ]);
  }

  Widget _narrowBody(int tab) {
    final mq = MediaQuery.of(context);
    if (context.skin.layout != AppLayout.standard) {
      final t = tab >= 2 ? tab : 0;
      return _switcher(t, t == 0 ? ChatListPane(selected: ui.openChat.value, onOpen: _open) : _subPage(t));
    }
    return Stack(fit: StackFit.expand, children: [
      Positioned.fill(child: _switcher(tab, _page(tab, wide: false))),
      Positioned(
        left: 0,
        right: 0,
        bottom: mq.padding.bottom + 18,
        child: Center(
          child: KeyedSubtree(
            key: ui.showTips.value ? ui.keys['nav'] : null,
            // Only the unread badge needs live chat data.
            child: ListenableBuilder(
              listenable: context.store,
              builder: (context, _) => SkNavBar(items: _items(context.store), index: tab, onTap: (i) => ui.tab.value = i),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _wideBody(int tab) {
    if (context.skin.layout != AppLayout.standard) return _wideAlt(tab);
    final mq = MediaQuery.of(context);
    final p = context.pal, skin = context.skin;
    // No side rail: the list and the open page share the whole screen, and the
    // Groups / Settings buttons live in the list's header.
    final listW = (mq.size.width * .38).clamp(300.0, 440.0);
    final open = ui.openChat.value;
    final rightPage = tab >= 2 ? tab : 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(10, mq.padding.top + 8, 10, mq.padding.bottom + 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: listW,
          child: skin.surface(
            p,
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 0),
            reduceEffects: context.settings.reduceMotion,
            child: ChatListPane(
              wide: true,
              groupsOnly: tab == 1,
              selected: open,
              onOpen: _open,
              rightPage: rightPage,
              onGroups: () => ui.tab.value = tab == 1 ? 0 : 1,
              onSettings: () => ui.tab.value = tab == 3 ? 0 : 3,
              onMac: () => ui.tab.value = tab == 2 ? 0 : 2,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: skin.surface(
            p,
            padding: rightPage == 0 ? EdgeInsets.zero : const EdgeInsets.fromLTRB(18, 14, 18, 0),
            reduceEffects: context.settings.reduceMotion,
            child: rightPage != 0
                ? _switcher(tab, _page(tab, wide: true))
                : open == null
                    ? _Placeholder()
                    : AnimatedSwitcher(
                        duration: context.sc.d(const Duration(milliseconds: 300)),
                        transitionBuilder: (c, a) => skin.transition(a, c),
                        child: ConversationPane(key: ValueKey(open), chatGuid: open, wide: true),
                      ),
          ),
        ),
      ]),
    );
  }

  /// Unfolded screen for Pinned / Material / Folders.
  Widget _wideAlt(int tab) {
    final mq = MediaQuery.of(context);
    final p = context.pal, skin = context.skin;
    final layout = skin.layout;
    final open = ui.openChat.value;
    final rightPage = tab >= 2 ? tab : 0;
    final listW = (mq.size.width * (layout == AppLayout.material ? .42 : .36)).clamp(290.0, 460.0);
    void settings() => ui.tab.value = tab == 3 ? 0 : 3;
    void mac() => ui.tab.value = tab == 2 ? 0 : 2;

    final edge = layout != AppLayout.material; // chat runs under the status bar
    final topPad = edge ? mq.padding.top : 0.0;
    final right = rightPage != 0
        ? Padding(padding: EdgeInsets.fromLTRB(18, 14 + topPad, 18, 0), child: _switcher(tab, _page(tab, wide: true)))
        : open == null
            ? Padding(padding: EdgeInsets.only(top: topPad), child: _Placeholder())
            : AnimatedSwitcher(
                duration: context.sc.d(const Duration(milliseconds: 260)),
                transitionBuilder: (c, a) => skin.transition(a, c),
                child: ConversationPane(key: ValueKey(open), chatGuid: open, wide: true),
              );
    final list = ChatListPane(wide: true, selected: open, onOpen: _open, rightPage: rightPage, onSettings: settings, onMac: mac);

    if (layout == AppLayout.material) {
      return Padding(
        padding: EdgeInsets.only(top: mq.padding.top, bottom: mq.padding.bottom),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(width: listW, child: Padding(padding: const EdgeInsets.only(left: 8), child: list)),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(8, 8, 10, 10),
              decoration: BoxDecoration(color: Color.lerp(p.bg, p.surface, .7), borderRadius: BorderRadius.circular(28)),
              clipBehavior: Clip.antiAlias,
              child: right,
            ),
          ),
        ]),
      );
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (layout == AppLayout.folders) FolderRail(onSettings: settings, onMac: mac, rightPage: rightPage),
      Container(
        width: listW,
        padding: EdgeInsets.only(top: mq.padding.top, bottom: mq.padding.bottom),
        decoration: BoxDecoration(
          color: layout == AppLayout.pinned ? p.surface : p.bg,
          border: Border(right: BorderSide(color: p.line, width: .6)),
        ),
        child: list,
      ),
      Expanded(child: Padding(padding: EdgeInsets.only(bottom: mq.padding.bottom), child: right)),
    ]);
  }
}

class _Placeholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        skin.accentTile(p, size: 70, child: Text('💬', style: skin.title(p))),
        const SizedBox(height: 16),
        const Heading('Pick a chat', large: false),
        const SizedBox(height: 6),
        Text('Your conversations open here on the big screen.', style: skin.callout(p)),
      ]),
    );
  }
}

class _ConversationScreen extends StatelessWidget {
  final String chatGuid;
  const _ConversationScreen({required this.chatGuid});
  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    return skin.background(p, animate: context.sc.ambient, child: ConversationPane(chatGuid: chatGuid));
  }
}

/// "Send to…" list shown when something is shared to Relay.
class _SharePicker extends StatefulWidget {
  final SharedContent content;
  const _SharePicker({required this.content});
  @override
  State<_SharePicker> createState() => _SharePickerState();
}

class _SharePickerState extends State<_SharePicker> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal, store = context.store;
    final q = _q.text.trim().toLowerCase();
    final chats = store.chats.where((c) => q.isEmpty || store.titleFor(c).toLowerCase().contains(q)).take(40).toList();
    final n = widget.content.paths.length;
    final what = [
      if (n > 0) '$n file${n == 1 ? '' : 's'}',
      if ((widget.content.text ?? '').trim().isNotEmpty) 'text',
    ].join(' + ');
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Sharing $what', style: skin.callout(p)),
      const SizedBox(height: 10),
      SkField(controller: _q, hint: 'Search chats', icon: 'search', onChanged: (_) => setState(() {})),
      const SizedBox(height: 8),
      ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .5),
        child: ListView.builder(
          shrinkWrap: true,
          physics: const BouncingScrollPhysics(),
          itemCount: chats.length,
          itemBuilder: (c, i) => ChatRow(chat: chats[i], onTap: () => Navigator.of(context).pop(chats[i])),
        ),
      ),
    ]);
  }
}
