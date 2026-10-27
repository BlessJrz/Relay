import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'push/push.dart';
import 'state/settings.dart';
import 'state/store.dart';
import 'state/ui_state.dart';
import 'ui/kit/scope.dart';
import 'ui/setup/setup_flow.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // If any part of a screen fails to draw, show what went wrong instead of a blank area.
  ErrorWidget.builder = (d) => Container(
        color: const Color(0xEE300010),
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: Text(
            'Relay hit a drawing error. Screenshot this and send it to Claude:\n\n${d.exceptionAsString()}\n\n${d.stack.toString().split('\n').take(8).join('\n')}',
            style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 12, decoration: TextDecoration.none),
          ),
        ),
      );

  final settings = await Settings.load();
  final store = Store(settings);
  await store.avatars.init();

  // Push: start Firebase with the config the Mac gave us last time (if any),
  // and register the handler that shows notifications while Relay is closed.
  await Push.initFirebase(settings.prefs);
  FirebaseMessaging.onBackgroundMessage(relayBackgroundPush);
  await Push.instance.initLocal();
  Push.instance.onOpenChat = (g) => ui.openChat.value = g;
  final launch = await Push.instance.launchChat();

  runApp(RelayApp(settings: settings, store: store));
  unawaited(_warmFonts());
  await store.start();
  if (launch != null) ui.openChat.value = launch;
}

/// Downloads every font the three designs use in the background once, so
/// switching designs or tabs never waits on a font (and works offline after).
Future<void> _warmFonts() async {
  try {
    await GoogleFonts.pendingFonts([
      for (final w in [FontWeight.w400, FontWeight.w500, FontWeight.w600, FontWeight.w700, FontWeight.w800]) GoogleFonts.inter(fontWeight: w),
      for (final w in [FontWeight.w400, FontWeight.w500, FontWeight.w600, FontWeight.w700]) GoogleFonts.outfit(fontWeight: w),
      for (final w in [FontWeight.w400, FontWeight.w500, FontWeight.w600, FontWeight.w700]) GoogleFonts.rubik(fontWeight: w),
      for (final w in [FontWeight.w500, FontWeight.w600, FontWeight.w700, FontWeight.w800]) GoogleFonts.manrope(fontWeight: w),
      for (final w in [FontWeight.w400, FontWeight.w500, FontWeight.w700]) GoogleFonts.jetBrainsMono(fontWeight: w),
    ]);
  } catch (_) {}
}

class RelayApp extends StatefulWidget {
  final Settings settings;
  final Store store;
  const RelayApp({super.key, required this.settings, required this.store});
  @override
  State<RelayApp> createState() => _RelayAppState();
}

class _RelayAppState extends State<RelayApp> with WidgetsBindingObserver {
  Brightness _platform = WidgetsBinding.instance.platformDispatcher.platformBrightness;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => setState(() => _platform = WidgetsBinding.instance.platformDispatcher.platformBrightness);

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    Push.instance.appInForeground = s == AppLifecycleState.resumed;
    widget.store.appActive = s == AppLifecycleState.resumed;
    // Leaving the app with the keyboard up: close it, so coming back shows the
    // whole chat instead of a gap where the keyboard used to be.
    if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    if (s == AppLifecycleState.resumed && widget.settings.setupDone) {
      widget.store.onResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) {
        final s = widget.settings;
        final skin = skins[s.design]!;
        final p = paletteFor(s, _platform);
        return AppScope(
          settings: s,
          store: widget.store,
          skin: skin,
          p: p,
          child: MaterialApp(
            title: 'Relay',
            debugShowCheckedModeBanner: false,
            // Material is only used for text input plumbing; every visible
            // control is drawn by the selected design.
            theme: ThemeData(
              brightness: p.dark ? Brightness.dark : Brightness.light,
              scaffoldBackgroundColor: p.bg,
              splashFactory: NoSplash.splashFactory,
              highlightColor: Colors.transparent,
              textSelectionTheme: TextSelectionThemeData(cursorColor: p.accent, selectionColor: p.tint, selectionHandleColor: p.accent),
            ),
            scrollBehavior: const _NoGlow(),
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: (p.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
                  statusBarColor: Colors.transparent,
                  systemNavigationBarColor: Colors.transparent,
                  systemNavigationBarContrastEnforced: false,
                ),
                // Make room for the keyboard everywhere (there's no Scaffold to do it):
                // shrink the app above the keyboard, and tell screens the bottom
                // safe area is already covered so they don't add a second gap.
                child: ColoredBox(
                  color: p.bg,
                  child: Padding(
                  padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
                  child: MediaQuery(
                  data: mq.copyWith(
                    textScaler: TextScaler.linear(s.textScale),
                    viewInsets: mq.viewInsets.copyWith(bottom: 0),
                    padding: mq.padding.copyWith(bottom: (mq.padding.bottom - mq.viewInsets.bottom).clamp(0.0, double.infinity)),
                  ),
                  // Transparent Material only so text fields work; it draws nothing.
                  child: Material(
                    type: MaterialType.transparency,
                    child: DefaultTextStyle(
                      style: skin.body(p),
                      child: _DesignFade(fadeKey: '${s.design}-${p.dark}', color: p.bg, enabled: s.animations, child: child!),
                    ),
                  ),
                ),
                ),
                ),
              );
            },
            home: const _Root(),
          ),
        );
      },
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();
  @override
  Widget build(BuildContext context) {
    final sc = context.sc;
    return sc.skin.background(
      sc.p,
      animate: sc.ambient,
      child: AnimatedSwitcher(
        duration: sc.d(const Duration(milliseconds: 450)),
        transitionBuilder: (c, a) => sc.skin.transition(a, c),
        child: sc.settings.setupDone ? const Shell(key: ValueKey('shell')) : const SetupFlow(key: ValueKey('setup')),
      ),
    );
  }
}

/// When the design or light/dark changes, fade in from the new background so
/// the switch feels smooth instead of a hard cut.
class _DesignFade extends StatelessWidget {
  final String fadeKey;
  final Color color;
  final bool enabled;
  final Widget child;
  const _DesignFade({required this.fadeKey, required this.color, required this.enabled, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      child,
      if (enabled)
        IgnorePointer(
        key: ValueKey(fadeKey),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 1, end: 0),
          duration: const Duration(milliseconds: 480),
          curve: Curves.easeOutCubic,
          builder: (_, v, __) => v <= 0.01 ? const SizedBox.shrink() : ColoredBox(color: color.withOpacity(v)),
        ),
      ),
    ]);
  }
}

class _NoGlow extends ScrollBehavior {
  const _NoGlow();
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
}
