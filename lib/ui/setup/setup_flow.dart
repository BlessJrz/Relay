import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../push/push.dart';
import '../../skins/skin.dart';
import '../../state/store.dart';
import '../../state/ui_state.dart';
import '../kit/controls.dart';
import '../kit/icons.dart';
import '../kit/scope.dart';
import 'mac_guide.dart';
import 'qr_scan.dart';

/// First-run guide: Welcome → Set up your Mac → Connect → Test & sync.
class SetupFlow extends StatefulWidget {
  const SetupFlow({super.key});
  @override
  State<SetupFlow> createState() => _SetupFlowState();
}

class _SetupFlowState extends State<SetupFlow> {
  int step = 0;
  bool forward = true;
  late final _url = TextEditingController(text: context.settings.serverUrl);
  late final _pw = TextEditingController(text: context.settings.password);

  @override
  void dispose() {
    _url.dispose();
    _pw.dispose();
    super.dispose();
  }

  void go(int s) => setState(() {
        forward = s > step;
        step = s;
      });

  void finish() {
    final st = context.settings;
    ui.tab.value = 0;
    st.tipsDone = false;
    ui.showTips.value = true;
    st.setupDone = true;
  }

  static const _names = ['Welcome', 'Set up your Mac', 'Connect', 'Test & sync'];

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    final mq = MediaQuery.of(context);
    final wide = mq.size.width >= 700;
    final pages = [
      _Welcome(onStart: () => go(1), onHaveServer: () => go(2)),
      _MacStepPage(onBack: () => go(0), onNext: () => go(2)),
      _ConnectPage(url: _url, pw: _pw, onBack: () => go(1), onNext: () => go(3)),
      _TestPage(url: _url, pw: _pw, onBack: () => go(2), onDone: finish),
    ];
    final page = AnimatedSwitcher(
      duration: context.sc.d(const Duration(milliseconds: 380)),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, a) {
        final dx = forward ? .08 : -.08;
        return FadeTransition(
          opacity: a,
          child: SlideTransition(position: Tween(begin: Offset(child.key == ValueKey(step) ? dx : -dx, 0), end: Offset.zero).animate(a), child: child),
        );
      },
      child: KeyedSubtree(key: ValueKey(step), child: pages[step]),
    );

    if (!wide) {
      return Padding(padding: EdgeInsets.only(top: mq.padding.top, bottom: mq.padding.bottom), child: page);
    }
    // Unfolded: steps on the left, content on the right.
    return Padding(
      padding: EdgeInsets.fromLTRB(20, mq.padding.top + 16, 20, mq.padding.bottom + 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 270,
          child: skin.surface(
            p,
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              skin.accentTile(p, size: 54, child: Ic('bolt', size: 26, color: p.onAccent)),
              const SizedBox(height: 14),
              const Heading('Set up Relay', large: false),
              const SizedBox(height: 18),
              for (var i = 0; i < _names.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Pressable(
                    onTap: i <= step ? () => go(i) : null,
                    builder: (_) => skin.selectedFace(
                      p,
                      selected: i == step,
                      radius: 16,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        child: Row(children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: i < step ? p.accent : null,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: i <= step ? p.accent : p.text3, width: 1.5),
                            ),
                            child: i < step ? Ic('check', size: 15, color: p.onAccent, stroke: 2.8) : Text('${i + 1}', style: skin.callout(p).copyWith(color: i == step ? p.accent : p.text3, fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 12),
                          Text(_names[i], style: skin.headline(p).copyWith(fontSize: 15, color: i > step ? p.text2 : p.text)),
                        ]),
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              skin.well(
                p,
                radius: 16,
                padding: const EdgeInsets.all(12),
                child: Row(children: [Ic('book', size: 18, color: p.accent), const SizedBox(width: 10), Expanded(child: Text('Tap any Mac step for detailed instructions.', style: skin.caption(p).copyWith(color: p.text2)))]),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(child: skin.surface(p, padding: EdgeInsets.zero, child: page)),
      ]),
    );
  }
}

class _Dots extends StatelessWidget {
  final int cur;
  const _Dots(this.cur);
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Row(children: [
      for (var i = 0; i < 4; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          margin: const EdgeInsets.only(right: 6),
          width: i == cur ? 26 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: i <= cur ? p.accent : withAlpha35(p.text3),
            borderRadius: BorderRadius.circular(4),
            // Keep list length constant: easeOutBack overshoot would otherwise
            // scale the removed shadow by a negative factor (assert in debug).
            boxShadow: [BoxShadow(color: i == cur ? p.glow : withA(p.glow, 0), blurRadius: 8)],
          ),
        ),
    ]);
  }
}

Color withAlpha35(Color c) => c.withOpacity(.35);

/// Shared page scaffold: scrollable body + footer buttons.
class _Page extends StatelessWidget {
  final int? dots;
  final String? eyebrow;
  final String? title;
  final String? subtitle;
  final List<Widget> children;
  final Widget footer;
  final VoidCallback? onSkip;
  const _Page({this.dots, this.eyebrow, this.title, this.subtitle, required this.children, required this.footer, this.onSkip});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    return Column(children: [
      Expanded(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
          children: [
            if (dots != null) ...[_Dots(dots!), const SizedBox(height: 18)],
            if (eyebrow != null)
              Row(children: [
                Eyebrow(eyebrow!),
                const Spacer(),
                if (onSkip != null) Pressable(onTap: onSkip, builder: (_) => Text('Skip', style: skin.callout(p))),
              ]),
            if (title != null) ...[const SizedBox(height: 6), Heading(title!)],
            if (subtitle != null) ...[const SizedBox(height: 8), Text(subtitle!, style: skin.body(p).copyWith(color: p.text2))],
            const SizedBox(height: 18),
            ...children,
          ],
        ),
      ),
      Padding(padding: const EdgeInsets.fromLTRB(20, 6, 20, 18), child: footer),
    ]);
  }
}

Widget _two(String? left, VoidCallback? onLeft, String right, VoidCallback? onRight, {bool busy = false, String? rightIcon}) => Row(children: [
      if (left != null) ...[Expanded(child: SkButton(left, primary: false, onTap: onLeft)), const SizedBox(width: 12)],
      Expanded(child: SkButton(right, onTap: onRight, busy: busy, icon: rightIcon)),
    ]);

// ------------------------------------------------------------------ 0 · Welcome

class _Welcome extends StatelessWidget {
  final VoidCallback onStart;
  final VoidCallback onHaveServer;
  const _Welcome({required this.onStart, required this.onHaveServer});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    Widget node(String icon, String label) => Column(children: [
          SizedBox(width: 46, height: 46, child: skin.well(p, radius: 16, child: Center(child: Ic(icon, size: 22, color: p.accent)))),
          const SizedBox(height: 6),
          Text(label, style: skin.caption(p).copyWith(color: p.text2)),
        ]);
    Widget arrow() => Padding(padding: const EdgeInsets.only(bottom: 18), child: Text('›', style: skin.headline(p).copyWith(color: p.accent, fontSize: 20)));
    return _Page(
      footer: _two('I have a server', onHaveServer, 'Start setup', onStart),
      children: [
        const SizedBox(height: 20),
        Center(child: Stagger(index: 0, child: skin.accentTile(p, size: 92, child: Ic('bolt', size: 44, color: p.onAccent)))),
        const SizedBox(height: 22),
        const Stagger(index: 1, child: Heading('Welcome to Relay', align: TextAlign.center)),
        const SizedBox(height: 10),
        Stagger(
          index: 2,
          child: Text('Your iMessage group chats, on your Galaxy. Your Mac handles iMessage; this app is the remote.', textAlign: TextAlign.center, style: skin.body(p).copyWith(color: p.text2)),
        ),
        const SizedBox(height: 24),
        Stagger(
          index: 3,
          child: SkCard(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
            child: FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: [
              node('phone', 'This phone'),
              arrow(),
              node('link', 'Tunnel'),
              arrow(),
              node('server', 'Your Mac'),
              arrow(),
              node('chat', 'iMessage'),
            ].expand((w) => [w, const SizedBox(width: 6)]).toList())),
          ),
        ),
        const SizedBox(height: 16),
        const Stagger(
          index: 4,
          child: RowGroup(label: 'You will need', children: [
            SettingsRow(icon: 'monitor', title: 'A Mac signed in to iMessage', subtitle: 'Your old MacBook works — even with a broken screen'),
            SettingsRow(icon: 'server', title: 'BlueBubbles Server (free)', subtitle: 'We walk you through installing it'),
            SettingsRow(icon: 'sparkle', title: 'About 15 minutes', subtitle: 'Once. After that it just runs'),
          ]),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ 1 · Mac

class _MacStepPage extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onNext;
  const _MacStepPage({required this.onBack, required this.onNext});
  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    return _Page(
      footer: _two('Back', onBack, 'Next', onNext),
      dots: 1,
      eyebrow: 'Step 1 of 3',
      title: 'Set up your Mac',
      subtitle: 'Do these once, on the Mac. Tap a step for detailed instructions; tick it when done.',
      onSkip: onNext,
      children: [
        const MacChecklist(),
        const SizedBox(height: 16),
        skin.well(
          p,
          radius: 16,
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Ic('info', size: 20, color: p.accent),
            const SizedBox(width: 12),
            Expanded(child: Text('Broken screen? Plug in any monitor or TV for setup. After that the Mac can run with the lid closed.', style: skin.callout(p).copyWith(color: p.text))),
          ]),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ 2 · Connect

class _ConnectPage extends StatefulWidget {
  final TextEditingController url;
  final TextEditingController pw;
  final VoidCallback onBack;
  final VoidCallback onNext;
  const _ConnectPage({required this.url, required this.pw, required this.onBack, required this.onNext});
  @override
  State<_ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<_ConnectPage> {
  int tab = 0;
  bool show = false;
  String? error;

  Future<void> _scan() async {
    final r = await scanServerQr(context);
    if (r == null || !mounted) return;
    widget.url.text = r.$1;
    widget.pw.text = r.$2;
    HapticFeedback.mediumImpact();
    widget.onNext();
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData('text/plain');
    final t = d?.text?.trim();
    if (t == null || t.isEmpty) return;
    final qr = parseServerQr(t);
    setState(() {
      if (qr != null) {
        widget.url.text = qr.$1;
        widget.pw.text = qr.$2;
      } else {
        widget.url.text = t;
      }
    });
  }

  void _next() {
    if (widget.url.text.trim().isEmpty || widget.pw.text.isEmpty) {
      setState(() => error = 'Enter both the server URL and the password.');
      return;
    }
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    Widget content;
    if (tab == 0) {
      content = Pressable(
        onTap: _scan,
        builder: (_) => SkCard(
          padding: const EdgeInsets.all(22),
          child: Column(children: [
            SizedBox(width: 150, height: 150, child: CustomPaint(painter: _Corners(p.accent), child: Center(child: Ic('scan', size: 46, color: p.text3)))),
            const SizedBox(height: 16),
            Text('On your Mac, open BlueBubbles Server and click the QR icon on its home screen. Then tap here to scan it.', textAlign: TextAlign.center, style: skin.callout(p)),
            const SizedBox(height: 16),
            SkButton('Open camera', icon: 'scan', onTap: _scan),
          ]),
        ),
      );
    } else if (tab == 1) {
      content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Find these on the BlueBubbles Server home screen on your Mac.', style: skin.callout(p)),
        const SizedBox(height: 12),
        SkField(
          controller: widget.url,
          hint: 'Server URL (https://…trycloudflare.com)',
          icon: 'link',
          keyboard: TextInputType.url,
          trailing: Pressable(onTap: _paste, builder: (_) => Padding(padding: const EdgeInsets.only(left: 8), child: Ic('clipboard', size: 18, color: p.accent))),
        ),
        const SizedBox(height: 10),
        SkField(
          controller: widget.pw,
          hint: 'Server password',
          icon: 'lock',
          obscure: !show,
          trailing: Pressable(onTap: () => setState(() => show = !show), builder: (_) => Padding(padding: const EdgeInsets.only(left: 8), child: Ic(show ? 'eyeoff' : 'eye', size: 18, color: p.text3))),
        ),
        if (error != null) ...[const SizedBox(height: 10), Text(error!, style: skin.callout(p).copyWith(color: p.danger))],
        const SizedBox(height: 14),
        skin.well(
          p,
          radius: 16,
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Ic('lock', size: 18, color: p.accent),
            const SizedBox(width: 10),
            Expanded(child: Text('Your password is stored encrypted on this phone and only ever sent to your own Mac.', style: skin.caption(p).copyWith(color: p.text2))),
          ]),
        ),
      ]);
    } else {
      content = const RowGroup(children: [
        SettingsRow(icon: 'monitor', title: 'Where’s the QR code?', subtitle: 'BlueBubbles Server → home screen → the QR icon next to your server URL.'),
        SettingsRow(icon: 'link', title: 'What does the URL look like?', subtitle: 'Usually https://something.trycloudflare.com (or ngrok / zrok).'),
        SettingsRow(icon: 'lock', title: 'Forgot the password?', subtitle: 'Set a new one in the server’s Settings, click the floppy‑disk icon, then scan again.'),
        SettingsRow(icon: 'alert', title: 'URL keeps changing?', subtitle: 'Cloudflare gives a new one when the server restarts. With notifications set up, Relay finds it automatically.'),
      ]);
    }
    return _Page(
      footer: _two('Back', widget.onBack, 'Connect', _next),
      dots: 2,
      eyebrow: 'Step 2 of 3',
      title: 'Connect to your Mac',
      children: [
        SkSegmented(options: const ['Scan QR', 'Manual', 'Help'], index: tab, expand: true, onChanged: (i) => setState(() => tab = i)),
        const SizedBox(height: 16),
        AnimatedSwitcher(duration: const Duration(milliseconds: 260), child: KeyedSubtree(key: ValueKey(tab), child: content)),
      ],
    );
  }
}

class _Corners extends CustomPainter {
  final Color c;
  _Corners(this.c);
  @override
  void paint(Canvas canvas, Size s) {
    const l = 26.0;
    final paint = Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final w = s.width, h = s.height;
    for (final path in [
      Path()..moveTo(0, l)..lineTo(0, 0)..lineTo(l, 0),
      Path()..moveTo(w - l, 0)..lineTo(w, 0)..lineTo(w, l),
      Path()..moveTo(0, h - l)..lineTo(0, h)..lineTo(l, h),
      Path()..moveTo(w - l, h)..lineTo(w, h)..lineTo(w, h - l),
    ]) {
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_Corners o) => o.c != c;
}

// ------------------------------------------------------------------ 3 · Test & sync

enum _St { wait, run, ok, warn, bad }

class _Check {
  final String label;
  _St st = _St.wait;
  String value = '';
  _Check(this.label);
}

class _TestPage extends StatefulWidget {
  final TextEditingController url;
  final TextEditingController pw;
  final VoidCallback onBack;
  final VoidCallback onDone;
  const _TestPage({required this.url, required this.pw, required this.onBack, required this.onDone});
  @override
  State<_TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<_TestPage> {
  final checks = [
    _Check('Mac reachable'),
    _Check('Password accepted'),
    _Check('iMessage signed in'),
    _Check('Private API'),
    _Check('Notifications'),
    _Check('Chats synced'),
  ];
  bool running = false;
  bool passed = false;
  String? problem;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  void _set(int i, _St st, [String v = '']) {
    if (!mounted) return;
    setState(() {
      checks[i].st = st;
      checks[i].value = v;
    });
  }

  Future<void> _run() async {
    setState(() {
      running = true;
      passed = false;
      problem = null;
      for (final c in checks) {
        c.st = _St.wait;
        c.value = '';
      }
    });
    final settings = context.settings, store = context.store;
    _set(0, _St.run);
    final (info, latency, err) = await Store.test(widget.url.text, widget.pw.text);
    if (err != null) {
      final auth = err.toLowerCase().contains('password');
      _set(0, auth ? _St.ok : _St.bad, auth ? 'OK' : 'Failed');
      _set(1, auth ? _St.bad : _St.wait, auth ? 'Wrong' : '');
      setState(() {
        running = false;
        problem = err;
      });
      return;
    }
    _set(0, _St.ok, '${latency!.inMilliseconds} ms');
    await Future.delayed(const Duration(milliseconds: 250));
    _set(1, _St.ok, 'OK');
    await Future.delayed(const Duration(milliseconds: 250));
    final im = info!.detectedImessage;
    _set(2, im == false ? _St.warn : _St.ok, im == false ? 'Check Messages' : 'OK');
    await Future.delayed(const Duration(milliseconds: 250));
    _set(3, info.canUsePrivateApi ? _St.ok : _St.warn, info.canUsePrivateApi ? 'On' : 'Optional');

    await settings.saveServer(widget.url.text.trim(), widget.pw.text);
    _set(4, _St.run);
    _set(5, _St.run);
    await store.connect();
    await Push.instance.requestPermission();
    final pushErr = settings.pushEnabled ? await Push.instance.register(store) : 'Off';
    _set(4, pushErr == null ? _St.ok : _St.warn, pushErr == null ? 'Ready' : 'Only while open');
    await store.refreshChats();
    _set(5, store.chats.isNotEmpty ? _St.ok : _St.warn, '${store.chats.length} chats');
    if (!mounted) return;
    setState(() {
      running = false;
      passed = true;
      if (pushErr != null && pushErr != 'Off') problem = pushErr;
    });
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    final done = checks.where((c) => c.st == _St.ok || c.st == _St.warn).length;
    return _Page(
      footer: passed
          ? SkButton('Finish', icon: 'check', expand: true, onTap: widget.onDone)
          : _two('Back', running ? null : widget.onBack, running ? 'Testing…' : 'Try again', running ? null : _run, busy: running),
      dots: 3,
      eyebrow: 'Step 3 of 3',
      title: passed ? 'You’re all set' : 'Checking everything',
      subtitle: passed ? 'Your Mac is relaying iMessage to this phone.' : 'We test the connection before you rely on it.',
      children: [
        SkCard(
          padding: const EdgeInsets.all(6),
          child: Column(children: [
            for (var i = 0; i < checks.length; i++) ...[
              if (i > 0) const SkDivider(indent: 44),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                child: Row(children: [
                  SizedBox(
                    width: 20,
                    child: checks[i].st == _St.run
                        ? const Spinner(size: 16)
                        : AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _color(p, checks[i].st),
                              boxShadow: checks[i].st == _St.wait ? const [] : [BoxShadow(color: _color(p, checks[i].st), blurRadius: 8)],
                            ),
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Text(checks[i].label, style: skin.headline(p).copyWith(fontSize: 15.5, color: checks[i].st == _St.wait ? p.text3 : p.text))),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      checks[i].value,
                      key: ValueKey(checks[i].value),
                      style: skin.callout(p).copyWith(color: _color(p, checks[i].st)),
                    ),
                  ),
                ]),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 16),
        SkCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('Progress', style: skin.headline(p))),
              Text('$done / ${checks.length}', style: skin.callout(p).copyWith(color: p.accent)),
            ]),
            const SizedBox(height: 10),
            IgnorePointer(child: SkSlider(value: done / checks.length, onChanged: (_) {})),
          ]),
        ),
        if (problem != null) ...[
          const SizedBox(height: 16),
          skin.well(
            p,
            radius: 16,
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Ic(passed ? 'info' : 'alert', size: 20, color: passed ? p.warning : p.danger),
              const SizedBox(width: 10),
              Expanded(child: Text(problem!, style: skin.callout(p).copyWith(color: p.text))),
            ]),
          ),
        ],
        if (passed) ...[
          const SizedBox(height: 16),
          skin.well(
            p,
            radius: 16,
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Ic('info', size: 20, color: p.accent),
              const SizedBox(width: 10),
              Expanded(child: Text('Tip: keep your iPhone on for a week while you test. If your friends text your phone number, check those messages arrive here before you put it away.', style: skin.callout(p).copyWith(color: p.text))),
            ]),
          ),
        ],
      ],
    );
  }

  Color _color(Palette p, _St s) => switch (s) {
        _St.ok => p.success,
        _St.warn => p.warning,
        _St.bad => p.danger,
        _St.run => p.accent,
        _St.wait => p.text3,
      };
}
