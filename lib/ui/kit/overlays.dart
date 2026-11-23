import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../skins/skin.dart';
import 'controls.dart';
import 'icons.dart';
import 'motion.dart';
import 'scope.dart';

/// Opens a full screen that slides in from the right (see [SlideRoute]).
Future<T?> pushScreen<T>(BuildContext context, WidgetBuilder b) =>
    Navigator.of(context).push<T>(SlideRoute<T>(b, scope: context.sc));

class DialogAction {
  final String label;
  final bool primary;
  final bool destructive;
  final VoidCallback? onTap;
  const DialogAction(this.label, {this.primary = false, this.destructive = false, this.onTap});
}

Future<void> showSkDialog(BuildContext context, {required String title, String? body, Widget? content, String icon = 'info', List<DialogAction> actions = const [DialogAction('OK', primary: true)]}) {
  final scope = context.sc;
  return Navigator.of(context).push(PageRouteBuilder(
    opaque: false,
    barrierDismissible: true,
    barrierColor: withA(const Color(0xFF000000), scope.p.dark ? .5 : .32),
    transitionDuration: scope.d(const Duration(milliseconds: 340)),
    reverseTransitionDuration: scope.d(const Duration(milliseconds: 200)),
    pageBuilder: (c, a, s) => AppScope(
      settings: scope.settings,
      store: scope.store,
      skin: scope.skin,
      p: scope.p,
      child: _Dialog(title: title, body: body, content: content, icon: icon, actions: actions),
    ),
    transitionsBuilder: (c, a, s, child) {
      final cv = CurvedAnimation(parent: a, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
      return FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: .92, end: 1.0).animate(cv), child: child));
    },
  ));
}

class _Dialog extends StatelessWidget {
  final String title;
  final String? body;
  final Widget? content;
  final String icon;
  final List<DialogAction> actions;
  const _Dialog({required this.title, this.body, this.content, required this.icon, required this.actions});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: skin.surface(
            p,
            strong: true,
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 60, height: 60, child: skin.well(p, radius: 30, child: Center(child: Ic(icon, size: 28, color: p.accent)))),
              const SizedBox(height: 14),
              Heading(title, large: false, align: TextAlign.center),
              if (body != null) ...[const SizedBox(height: 8), Text(body!, textAlign: TextAlign.center, style: skin.callout(p))],
              if (content != null) ...[const SizedBox(height: 14), content!],
              const SizedBox(height: 20),
              Row(children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(
                    child: SkButton(
                      actions[i].label,
                      primary: actions[i].primary,
                      height: 48,
                      onTap: () {
                        Navigator.of(context).pop();
                        actions[i].onTap?.call();
                      },
                    ),
                  ),
                ],
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet that slides up with the design's surface.
Future<T?> showSkSheet<T>(BuildContext context, {required WidgetBuilder builder, String? title}) {
  final scope = context.sc;
  return Navigator.of(context).push<T>(PageRouteBuilder<T>(
    opaque: false,
    barrierDismissible: true,
    barrierColor: withA(const Color(0xFF000000), scope.p.dark ? .45 : .28),
    transitionDuration: scope.d(const Duration(milliseconds: 380)),
    reverseTransitionDuration: scope.d(const Duration(milliseconds: 240)),
    pageBuilder: (c, a, s) => AppScope(
      settings: scope.settings,
      store: scope.store,
      skin: scope.skin,
      p: scope.p,
      child: Builder(builder: (c2) => _Sheet(title: title, child: builder(c2))),
    ),
    transitionsBuilder: (c, a, s, child) {
      final cv = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
      if (MediaQuery.of(c).size.width >= 700) {
        // Centered card: a quick fade and grow instead of sliding up the whole screen.
        return FadeTransition(opacity: cv, child: ScaleTransition(scale: Tween(begin: .94, end: 1.0).animate(cv), child: child));
      }
      return SlideTransition(position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(cv), child: child);
    },
  ));
}

class _Sheet extends StatelessWidget {
  final String? title;
  final Widget child;
  const _Sheet({this.title, required this.child});
  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    final mq = MediaQuery.of(context);
    // Unfolded: a compact card in the middle of the screen. Folded: a sheet
    // from the bottom. Either way it's only as tall as what's in it.
    final wide = mq.size.width >= 700;
    // The app already shrinks above the keyboard, so measure the space that's
    // really left (and stay below the status bar).
    return LayoutBuilder(
      builder: (context, k) => Align(
      alignment: wide ? Alignment.center : Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: wide ? 480 : 640, maxHeight: math.max(160.0, math.min(k.maxHeight * .92, k.maxHeight - mq.padding.top - 12))),
        child: Padding(
          padding: EdgeInsets.fromLTRB(10, 0, 10, wide ? 10 + mq.viewInsets.bottom : 10 + mq.viewInsets.bottom + mq.padding.bottom),
          child: skin.surface(
            p,
            strong: true,
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (!wide)
                Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: p.text3, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              if (title != null) ...[
                Row(children: [
                  Expanded(child: Heading(title!, large: false)),
                  SkIconButton('x', size: 38, onTap: () => Navigator.of(context).pop()),
                ]),
                const SizedBox(height: 12),
              ],
              Flexible(child: child),
            ]),
          ),
        ),
      ),
      ),
    );
  }
}

/// Short message at the top of the screen (used for errors and in-app message banners).
class Toaster {
  static OverlayEntry? _entry;
  static Timer? _t;

  /// [tag] names what the banner is about (a chat's id for a new-message
  /// banner), so it can be taken down early with [dismiss].
  static void show(BuildContext context, String text, {String icon = 'info', String? title, VoidCallback? onTap, Duration duration = const Duration(seconds: 3), String? tag}) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final scope = context.sc;
    _tag = tag;
    _t?.cancel();
    // The one already showing leaves (quickly) as the new one comes in.
    final old = _entry, oldKey = _key;
    if (old != null) _leave(old, oldKey);
    final key = GlobalKey<_ToastState>();
    late OverlayEntry e;
    e = OverlayEntry(
      builder: (c) => AppScope(
        settings: scope.settings,
        store: scope.store,
        skin: scope.skin,
        p: scope.p,
        child: _Toast(key: key, text: text, icon: icon, title: title, onTap: () {
          if (_entry == e) {
            _t?.cancel();
            _entry = null;
            _key = null;
          }
          _leave(e, key);
          onTap?.call();
        }),
      ),
    );
    _entry = e;
    _key = key;
    overlay.insert(e);
    _t = Timer(duration, () {
      if (_entry != e) return;
      _entry = null;
      _key = null;
      _leave(e, key);
    });
  }

  static GlobalKey<_ToastState>? _key;
  static String? _tag;

  /// Takes the banner down now if it's the one tagged [tag] (you opened the
  /// chat it was announcing, so it's only in the way).
  static void dismiss(String tag) {
    final e = _entry;
    if (e == null || _tag != tag) return;
    _t?.cancel();
    final key = _key;
    _entry = null;
    _key = null;
    _tag = null;
    _leave(e, key);
  }

  /// Slides the banner back up and fades it, then takes it off the screen
  /// (it used to vanish in one frame).
  static void _leave(OverlayEntry e, GlobalKey<_ToastState>? key) {
    final s = key?.currentState;
    if (s == null) {
      // Not drawn yet (two banners in the same frame): it's in the overlay
      // but `mounted` is still false, so take it out directly.
      try {
        e.remove();
      } catch (_) {}
    } else {
      s.leave().whenComplete(() {
        if (e.mounted) e.remove();
      });
    }
  }
}

class _Toast extends StatefulWidget {
  final String text;
  final String? title;
  final String icon;
  final VoidCallback onTap;
  const _Toast({super.key, required this.text, this.title, required this.icon, required this.onTap});
  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420), reverseDuration: const Duration(milliseconds: 180))..forward();
  bool _leaving = false;

  Future<void> leave() async {
    if (_leaving || !mounted) return;
    _leaving = true;
    try {
      await _c.reverse().orCancel;
    } on TickerCanceled {
      // Taken off the screen mid-way (the app closed, a test ended).
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    final text = widget.text, title = widget.title, icon = widget.icon;
    final top = MediaQuery.paddingOf(context).top + 10;
    return Positioned(
      top: top,
      left: 12,
      right: 12,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: AnimatedBuilder(
            animation: _c,
            // Drops in with a little overshoot; leaves straight up, no bounce.
            builder: (_, c) {
              final v = _leaving ? Curves.easeIn.transform(_c.value) : Curves.easeOutBack.transform(_c.value);
              return IgnorePointer(
                ignoring: _leaving,
                child: Transform.translate(offset: Offset(0, -40 * (1 - v)), child: Opacity(opacity: v.clamp(0.0, 1.0), child: c)),
              );
            },
            child: Pressable(
              onTap: widget.onTap,
              builder: (_) => skin.surface(
                p,
                strong: true,
                radius: 24,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  Ic(icon, size: 20, color: p.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      if (title != null) Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: skin.headline(p).copyWith(fontSize: 14.5)),
                      Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: skin.callout(p).copyWith(color: title == null ? p.text : p.text2)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
