import 'package:flutter/widgets.dart';

import '../../push/push.dart';
import '../../skins/skin.dart';
import '../../state/settings.dart';
import '../../state/store.dart';
import '../../state/ui_state.dart';
import '../../state/updater.dart';
import '../kit/controls.dart';
import '../kit/icons.dart';
import '../kit/overlays.dart';
import '../kit/scope.dart';
import '../lock.dart';
import '../setup/mac_guide.dart';
import '../setup/qr_scan.dart';
import 'chat_list.dart';
import 'relay_screen.dart';

class SettingsScreen extends StatelessWidget {
  final bool wide;
  const SettingsScreen({super.key, this.wide = false});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal, s = context.settings;
    final top = wide ? 8.0 : MediaQuery.of(context).padding.top + 8;

    final appearance = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const RowGroup(children: [_UpdateRow()]),
      const SizedBox(height: 18),
      const SectionLabel('Design'),
      // All four designs in one short row.
      SkCard(
        padding: const EdgeInsets.all(8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < DesignId.values.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(child: _DesignTile(DesignId.values[i])),
          ],
        ]),
      ),
      const SizedBox(height: 18),
      SkCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Light / dark', style: skin.headline(p)),
          const SizedBox(height: 10),
          SkSegmented(
            options: const ['Light', 'Dark', 'Auto'],
            index: s.mode.index,
            expand: true,
            onChanged: (i) => s.mode = ThemeModeChoice.values[i],
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: Text('Accent colour', style: skin.headline(p))),
            for (var i = 0; i < skin.accents.length; i++)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Pressable(
                  onTap: () => s.setAccent(s.design, i),
                  builder: (_) => AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 30,
                    height: 30,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: s.accentFor(s.design) == i ? p.text : withA(p.text, 0), width: 2),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: p.dark ? skin.accents[i].dark : skin.accents[i].light,
                        boxShadow: [BoxShadow(color: withA(p.dark ? skin.accents[i].dark : skin.accents[i].light, .5), blurRadius: 8)],
                      ),
                    ),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 18),
          const _HighlightPicker(),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: Text('Text size', style: skin.headline(p))),
            Text('${(s.textScale * 100).round()}%', style: skin.callout(p).copyWith(color: p.accent)),
          ]),
          const SizedBox(height: 6),
          SkSlider(value: (s.textScale - .85) / .4, divisions: 8, onChanged: (v) => s.textScale = .85 + v * .4),
        ]),
      ),
      const SizedBox(height: 18),
      RowGroup(label: 'Motion', children: [
        SettingsRow(icon: 'sparkle', title: 'Animations', subtitle: 'Transitions, press effects, live backgrounds', trailing: SkToggle(value: s.animations, onChanged: (v) => s.animations = v)),
        SettingsRow(icon: 'activity', title: 'Reduce motion', subtitle: 'Calmer backgrounds, less blur, saves battery', trailing: SkToggle(value: s.reduceMotion, onChanged: (v) => s.reduceMotion = v)),
      ]),
    ]);

    final connection = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      RowGroup(label: 'Mac relay', children: [
        SettingsRow(icon: 'link', title: 'Server address & password', subtitle: s.serverUrl.isEmpty ? 'Not set' : s.serverUrl, chevron: true, onTap: () => showConnectionSheet(context)),
        SettingsRow(icon: 'shield', title: 'Private API', subtitle: 'Reactions, replies and typing', chevron: true, onTap: () => showPrivateApiHelp(context)),
        SettingsRow(icon: 'monitor', title: 'Mac setup checklist', subtitle: 'Everything the Mac needs, step by step', chevron: true, onTap: () => showMacGuide(context)),
      ]),
      const SizedBox(height: 18),
      RowGroup(label: 'Notifications', children: [
        SettingsRow(
          icon: 'bell',
          title: 'Push notifications',
          subtitle: 'Get messages even when Relay is closed',
          trailing: SkToggle(
            value: s.pushEnabled,
            onChanged: (v) async {
              s.pushEnabled = v;
              if (v) {
                final err = await Push.instance.register(context.store);
                if (err != null && context.mounted) showSkDialog(context, title: 'Notifications', body: err, icon: 'bell');
              }
            },
          ),
        ),
        SettingsRow(icon: 'eye', title: 'Show message text', subtitle: 'Off shows “New message” only', trailing: SkToggle(value: s.notificationPreviews, onChanged: (v) => s.notificationPreviews = v)),
        SettingsRow(icon: 'monitor', title: 'Warn me if my Mac goes offline', subtitle: 'After a few minutes without an answer, while Relay is running', trailing: SkToggle(value: s.macOfflineAlert, onChanged: (v) => s.macOfflineAlert = v)),
        SettingsRow(icon: 'sparkle', title: 'Send a test notification', chevron: true, onTap: () async {
          await Push.instance.requestPermission();
          await Push.instance.test();
        }),
      ]),
      const SizedBox(height: 18),
      RowGroup(label: 'Privacy', children: [
        SettingsRow(
          icon: 'lock',
          title: 'Lock with fingerprint',
          subtitle: 'Ask for your fingerprint or PIN to open Relay',
          trailing: SkToggle(
            value: s.appLock,
            onChanged: (v) async {
              // Check it works before turning it on, so nobody gets locked out.
              if (v && !await unlockWithBiometrics('Turn on the Relay lock')) return;
              s.appLock = v;
            },
          ),
        ),
      ]),
    ]);

    final help = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      RowGroup(label: 'Help', children: [
        SettingsRow(icon: 'book', title: 'Replay setup guide', subtitle: 'Walk through connecting again', chevron: true, onTap: () => s.setupDone = false),
        SettingsRow(icon: 'sparkle', title: 'Show tips again', subtitle: 'Re-run the in-app tutorial', chevron: true, onTap: () {
          ui.tab.value = 0;
          ui.showTips.value = true;
        }),
        SettingsRow(icon: 'help', title: 'Troubleshooting', subtitle: 'When messages don’t come through', chevron: true, onTap: () => showTroubleshooting(context)),
      ]),
      const SizedBox(height: 18),
      RowGroup(children: [
        SettingsRow(
          icon: 'logout',
          iconColor: p.danger,
          title: 'Disconnect & reset',
          titleColor: p.danger,
          subtitle: 'Forget this Mac and all settings on this phone',
          onTap: () => showSkDialog(context, title: 'Reset Relay?', body: 'This forgets your server address and password and restarts the setup guide. Nothing on your Mac changes.', icon: 'alert', actions: [
            const DialogAction('Cancel'),
            DialogAction('Reset', primary: true, onTap: () async {
              context.store.disconnect();
              await s.resetAll();
            }),
          ]),
        ),
      ]),
      const SizedBox(height: 14),
      Center(
        child: ListenableBuilder(
          listenable: Updater.instance,
          builder: (context, _) {
            final u = Updater.instance;
            final v = [
              'Relay${u.version.isEmpty ? '' : ' ${u.version}'}',
              if ((u.current ?? 0) > 0) 'build ${u.current}',
              'uses BlueBubbles Server on your Mac',
            ].join(' · ');
            return Text(v, textAlign: TextAlign.center, style: skin.caption(p));
          },
        ),
      ),
    ]);

    // Two columns only when there's real room for them (not in a narrow side pane).
    List<Widget> columns(bool twoCol) => twoCol
        ? [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: appearance),
              const SizedBox(width: 18),
              Expanded(child: Column(children: [connection, const SizedBox(height: 18), help])),
            ]),
          ]
        : [appearance, const SizedBox(height: 18), connection, const SizedBox(height: 18), help];

    return LayoutBuilder(
      builder: (context, k) => ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(wide ? 4 : 18, top, wide ? 4 : 18, wide ? 24 : 130),
        children: [
          if (!wide) const Eyebrow('Relay'),
          const Heading('Settings'),
          const SizedBox(height: 16),
          ...columns(wide && k.maxWidth >= 860),
        ],
      ),
    );
  }
}

/// Your own colour for "Messages", unread badges and times: a few swatches,
/// plus a rainbow slider for any colour.
class _HighlightPicker extends StatelessWidget {
  const _HighlightPicker();

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal, s = context.settings;
    final mine = s.highlight;
    final designDefault = skin.badge(skin.palette(p.dark, s.accentFor(s.design)));
    Widget dot(Color c, bool on, VoidCallback tap, {String? label, Widget? inner}) => Semantics(
          button: true,
          selected: on,
          label: label,
          child: Pressable(
            onTap: tap,
            builder: (_) => AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 34,
              height: 34,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: on ? p.text : withA(p.text, 0), width: 2)),
              child: Container(
                decoration: BoxDecoration(shape: BoxShape.circle, color: c, border: Border.all(color: withA(p.text, .15))),
                child: inner,
              ),
            ),
          ),
        );
    final hue = mine == null ? 0.0 : HSVColor.fromColor(mine).hue / 360;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('Highlight colour', style: skin.headline(p))),
        Text('"Messages", unread', style: skin.caption(p)),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: [
        dot(designDefault, mine == null, () => s.highlight = null, label: 'Design default', inner: Center(child: Text('A', style: skin.caption(p).copyWith(color: Skin.inkOn(designDefault), fontWeight: FontWeight.w700)))),
        for (final c in highlightChoices) dot(highlightFor(c, p.dark), mine?.toARGB32() == c.toARGB32(), () => s.highlight = c),
      ]),
      const SizedBox(height: 12),
      // Any colour: slide along the rainbow.
      Stack(alignment: Alignment.center, children: [
        Positioned(
          left: 13,
          right: 13,
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: LinearGradient(colors: [for (var h = 0; h <= 360; h += 30) HSVColor.fromAHSV(1, h.toDouble() % 360, .68, 1).toColor()]),
            ),
          ),
        ),
        Opacity(
          opacity: 0, // invisible: it only catches the drag; the rainbow and knob are drawn around it
          child: SkSlider(value: hue, divisions: 72, onChanged: (v) => s.highlight = HSVColor.fromAHSV(1, (v * 360) % 360, .68, 1).toColor()),
        ),
        IgnorePointer(
          child: Align(
            alignment: Alignment(-1 + 2 * hue, 0),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: mine ?? designDefault,
                border: Border.all(color: const Color(0xFFFFFFFF), width: 3),
                boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 5)],
              ),
            ),
          ),
        ),
      ]),
    ]);
  }
}

/// "Check for updates": asks GitHub for the newest build and installs it.
class _UpdateRow extends StatefulWidget {
  const _UpdateRow();
  @override
  State<_UpdateRow> createState() => _UpdateRowState();
}

class _UpdateRowState extends State<_UpdateRow> {
  final u = Updater.instance;

  @override
  void initState() {
    super.initState();
    u.currentBuild().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _tap() async {
    if (u.checking || u.progress != null) return;
    final found = u.available ?? await u.check();
    if (!mounted) return;
    if (found != null) {
      showUpdatePrompt(context, found);
    } else if (u.error == null) {
      Toaster.show(context, 'You have the newest build', icon: 'check');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ListenableBuilder(
      listenable: u,
      builder: (context, _) {
        final mine = (u.current ?? 0) > 0 ? 'build ${u.current}' : null;
        final String subtitle;
        if (u.progress != null) {
          subtitle = 'Downloading… ${(u.progress! * 100).round()}%';
        } else if (u.checking) {
          subtitle = 'Checking GitHub…';
        } else if (u.available != null) {
          subtitle = 'Build ${u.available!.build} is ready · tap to install';
        } else if (u.error != null) {
          subtitle = u.error!;
        } else if (u.lastChecked != null) {
          subtitle = 'Up to date${mine == null ? '' : ' · $mine'}';
        } else {
          subtitle = mine == null ? 'Get the newest build from GitHub' : 'You have $mine';
        }
        return SettingsRow(
          icon: 'download',
          iconColor: u.available != null ? p.accent : null,
          title: u.available != null ? 'Install update' : 'Check for updates',
          subtitle: subtitle,
          trailing: u.checking || u.progress != null ? const Spinner(size: 18) : null,
          chevron: !u.checking && u.progress == null,
          onTap: _tap,
        );
      },
    );
  }
}

/// "Build N is ready" with Install / Later.
void showUpdatePrompt(BuildContext context, UpdateInfo info) {
  final mb = info.size > 0 ? ' (${(info.size / 1048576).toStringAsFixed(0)} MB)' : '';
  showSkDialog(
    context,
    title: 'Update ready',
    icon: 'download',
    body: 'Relay build ${info.build} is on GitHub$mb. It installs over this one; your chats and settings stay.',
    actions: [
      const DialogAction('Later'),
      DialogAction('Install', primary: true, onTap: () async {
        // Ask GitHub again first: the `latest` release is rebuilt on every
        // push, so an older download link may be gone.
        final up = Updater.instance;
        if (up.progress != null) return; // already downloading
        final fresh = up.checking ? info : await up.check();
        if (fresh == null && up.error == null) {
          if (context.mounted) Toaster.show(context, 'You have the newest build', icon: 'check');
          return;
        }
        final u = fresh ?? info; // GitHub unreachable: try the link we have
        if (context.mounted) Toaster.show(context, 'Downloading build ${u.build}…', icon: 'download');
        final err = await up.install(u);
        if (err != null && context.mounted) Toaster.show(context, err, icon: 'alert');
      }),
    ],
  );
}

/// A live miniature of each design, drawn by that design itself.
class _DesignTile extends StatelessWidget {
  final DesignId d;
  const _DesignTile(this.d);

  @override
  Widget build(BuildContext context) {
    final s = context.settings, cur = context.skin, curP = context.pal;
    final skin = skins[d]!;
    final p = skin.palette(curP.dark, s.accentFor(d));
    final selected = s.design == d;
    // Small enough that all four fit on one row; the bubbles scale with the tile.
    Widget bar(double w, double h, Widget Function() face, Alignment a) => Align(
          alignment: a,
          child: FractionallySizedBox(widthFactor: w, child: SizedBox(height: h, child: face())),
        );
    return Semantics(
      button: true,
      selected: selected,
      label: d.label,
      child: Pressable(
        onTap: () => s.design = d,
        builder: (_) => cur.selectedFace(
          curP,
          selected: selected,
          radius: 14,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
            child: Column(children: [
              SizedBox(
                height: 76,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: skin.background(
                    p,
                    animate: false,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        SizedBox(height: 9, child: skin.surface(p, radius: 5, child: const SizedBox())),
                        const SizedBox(height: 6),
                        bar(.62, 10, () => skin.bubble(p, outgoing: true, child: const SizedBox()), Alignment.centerRight),
                        const SizedBox(height: 4),
                        bar(.5, 10, () => skin.bubble(p, outgoing: false, child: const SizedBox()), Alignment.centerLeft),
                        const Spacer(),
                        bar(.5, 8, () => skin.buttonFace(p, primary: true, pressed: false, radius: 5, child: const SizedBox()), Alignment.center),
                      ]),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                d == DesignId.minimal ? 'Minimal' : d.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: cur.caption(curP).copyWith(fontSize: 11.5, color: selected ? curP.accent : curP.text2, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Edit server URL and password, with QR scan and a live test.
void showConnectionSheet(BuildContext context) {
  showSkSheet(context, title: 'Mac relay', builder: (c) => const _ConnectionForm());
}

class _ConnectionForm extends StatefulWidget {
  const _ConnectionForm();
  @override
  State<_ConnectionForm> createState() => _ConnectionFormState();
}

class _ConnectionFormState extends State<_ConnectionForm> {
  late final _url = TextEditingController(text: context.settings.serverUrl);
  late final _pw = TextEditingController(text: context.settings.password);
  bool _busy = false;
  bool _show = false;
  String? _result;

  @override
  void dispose() {
    _url.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final r = await scanServerQr(context);
    if (r != null) {
      setState(() {
        _url.text = r.$1;
        _pw.text = r.$2;
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    final (info, latency, err) = await Store.test(_url.text, _pw.text);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _result = err;
      });
      return;
    }
    // Grab these first: the sheet may be closed while saving.
    final settings = context.settings, store = context.store;
    await settings.saveServer(_url.text.trim(), _pw.text);
    await store.connect();
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pop();
    Toaster.show(context, 'Connected · ${latency!.inMilliseconds} ms · macOS ${info!.osVersion}', icon: 'check');
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SkButton('Scan QR code from your Mac', icon: 'scan', primary: false, expand: true, onTap: _scan),
        const SizedBox(height: 14),
        SkField(controller: _url, hint: 'https://xxxx.trycloudflare.com', icon: 'link', keyboard: TextInputType.url),
        const SizedBox(height: 10),
        SkField(
          controller: _pw,
          hint: 'Server password',
          icon: 'lock',
          obscure: !_show,
          trailing: Pressable(onTap: () => setState(() => _show = !_show), builder: (_) => Padding(padding: const EdgeInsets.only(left: 8), child: Ic(_show ? 'eyeoff' : 'eye', size: 18, color: p.text3))),
        ),
        if (_result != null) ...[
          const SizedBox(height: 12),
          Row(children: [Ic('alert', size: 18, color: p.danger), const SizedBox(width: 8), Expanded(child: Text(_result!, style: skin.callout(p).copyWith(color: p.danger)))]),
        ],
        const SizedBox(height: 16),
        SkButton('Test & save', icon: 'check', expand: true, busy: _busy, onTap: _save),
      ]),
    );
  }
}



