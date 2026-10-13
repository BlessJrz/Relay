import 'dart:async';

import 'package:flutter/widgets.dart';

import '../api/models.dart';
import '../state/store.dart';
import '../state/ui_state.dart';
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

  @override
  void initState() {
    super.initState();
    ui.openChat.addListener(_onOpenChat);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _banners?.cancel();
    _banners = context.store.banners.listen((b) {
      if (!mounted) return;
      final s = context.store;
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

  void _open(Chat c) => ui.openChat.value = c.guid;

  List<NavItem> _items(Store s, bool hud) => [
        NavItem('chat', 'Chats', badge: s.totalUnread),
        const NavItem('users', 'Groups'),
        NavItem('server', hud ? 'Server' : 'Mac'),
        NavItem('sliders', hud ? 'Config' : 'Settings'),
      ];

  @override
  Widget build(BuildContext context) {
    final store = context.store, skin = context.skin;
    return SizedBox.expand(child: LayoutBuilder(builder: (context, k) {
      final wide = k.maxWidth >= 700;
      if (wide != _wide) {
        _wide = wide;
        // Folding while a chat is pushed: pop it and show it in the side pane instead.
        if (wide) WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.of(context).popUntil((r) => r.isFirst));
      }
      return ValueListenableBuilder<int>(
        valueListenable: ui.tab,
        builder: (context, tab, _) => ListenableBuilder(
          listenable: Listenable.merge([store, ui.openChat]),
          builder: (context, _) {
            final items = _items(store, skin.upperHeadings);
            final body = wide ? _wideBody(tab, items) : _narrowBody(tab, items);
            // fit: expand so the frame always fills the screen. (Without it the
            // zero-size tutorial placeholder below sized the whole frame to 0x0.)
            return Stack(fit: StackFit.expand, children: [
              Positioned.fill(child: body),
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
        ),
      );
    }));
  }

  Widget _page(int tab, {required bool wide}) => switch (tab) {
        1 => ChatListPane(groupsOnly: true, wide: wide, selected: ui.openChat.value, onOpen: _open),
        2 => RelayScreen(wide: wide),
        3 => SettingsScreen(wide: wide),
        _ => ChatListPane(wide: wide, selected: ui.openChat.value, onOpen: _open),
      };

  Widget _narrowBody(int tab, List<NavItem> items) {
    final mq = MediaQuery.of(context);
    return Stack(fit: StackFit.expand, children: [
      Positioned.fill(
        child: AnimatedSwitcher(
          duration: context.sc.d(const Duration(milliseconds: 300)),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (c, a) => context.skin.transition(a, c),
          child: KeyedSubtree(key: ValueKey(tab), child: _page(tab, wide: false)),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: mq.padding.bottom + 18,
        child: Center(
          child: KeyedSubtree(
            key: ui.keys['nav'],
            child: SkNavBar(items: items, index: tab, onTap: (i) => ui.tab.value = i),
          ),
        ),
      ),
    ]);
  }

  Widget _wideBody(int tab, List<NavItem> items) {
    final mq = MediaQuery.of(context);
    final p = context.pal, skin = context.skin;
    final listTabs = tab == 0 || tab == 1;
    final listW = (mq.size.width * .34).clamp(260.0, 380.0);
    final open = ui.openChat.value;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, mq.padding.top + 12, 16, mq.padding.bottom + 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        KeyedSubtree(key: ui.keys['nav'], child: SkNavRail(items: items, index: tab, onTap: (i) => ui.tab.value = i)),
        const SizedBox(width: 16),
        if (listTabs) ...[
          SizedBox(
            // Give the conversation the larger share; the list takes about a third.
            width: listW,
            child: skin.surface(p, padding: const EdgeInsets.fromLTRB(10, 14, 10, 0), reduceEffects: context.settings.reduceMotion, child: _page(tab, wide: true)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: skin.surface(
              p,
              padding: EdgeInsets.zero,
              reduceEffects: context.settings.reduceMotion,
              child: open == null
                  ? _Placeholder()
                  : AnimatedSwitcher(
                      duration: context.sc.d(const Duration(milliseconds: 300)),
                      transitionBuilder: (c, a) => skin.transition(a, c),
                      child: ConversationPane(key: ValueKey(open), chatGuid: open, wide: true),
                    ),
            ),
          ),
        ] else
          Expanded(
            child: AnimatedSwitcher(
              duration: context.sc.d(const Duration(milliseconds: 300)),
              transitionBuilder: (c, a) => skin.transition(a, c),
              child: KeyedSubtree(key: ValueKey(tab), child: _page(tab, wide: true)),
            ),
          ),
      ]),
    );
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
