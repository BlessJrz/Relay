import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../kit/controls.dart';
import '../kit/icons.dart';
import '../kit/overlays.dart';
import '../kit/scope.dart';

class MacStep {
  final String id;
  final String icon;
  final String title;
  final String short;
  final List<String> how;
  final String? tip;
  final String? link;
  final bool optional;
  const MacStep(this.id, this.icon, this.title, this.short, this.how, {this.tip, this.link, this.optional = false});
}

/// Everything the Mac needs, in order. Shown in the setup guide and in Settings.
const macSteps = <MacStep>[
  MacStep('screen', 'monitor', 'Get the Mac ready', 'Power, a screen for setup, and an update',
      [
        'Plug the Mac into power. It will run all the time.',
        'Broken built-in screen? Connect any monitor or TV with HDMI or a USB‑C adapter. You only need it for this setup.',
        'Connect the Mac to Wi‑Fi (or Ethernet — even better).',
        'If you can, install macOS updates first (Apple menu → System Settings → General → Software Update).',
      ],
      tip: 'After setup you can unplug the monitor. If you ever need to see the Mac again, use Screen Sharing from another computer.'),
  MacStep('messages', 'chat', 'Sign in to Messages', 'Use the same Apple ID as your iPhone',
      [
        'Open the Messages app on the Mac.',
        'Sign in with the Apple ID you use for iMessage on your iPhone.',
        'Open Messages → Settings → iMessage. Under “You can be reached at”, tick your phone number and email.',
        'Open your group chat on the Mac and send a test message. If it goes through here, the relay will work.',
      ],
      tip: 'Your phone number only shows up on the Mac while your iPhone is signed in to the same Apple ID. Keep the iPhone powered on during setup and for the first week, then test before putting it away.'),
  MacStep('install', 'server', 'Install BlueBubbles Server', 'Free and open source',
      [
        'On the Mac, open the link below and download the .dmg file at the bottom of the page.',
        'In Finder → Downloads, right‑click the .dmg and choose Open. (It is unsigned, so a normal double‑click is blocked.)',
        'Drag BlueBubbles into Applications, then right‑click the installer disk and Eject it.',
        'Open BlueBubbles from Applications. The setup wizard starts.',
      ],
      link: 'https://github.com/BlueBubblesApp/bluebubbles-server/releases/latest'),
  MacStep('perms', 'lock', 'Allow Full Disk Access', 'Lets the server read your messages',
      [
        'In the wizard’s Permissions step, click the Full Disk Access button.',
        'System Settings opens at Privacy & Security → Full Disk Access. Turn on BlueBubbles.',
        'Accessibility is optional — you can skip it.',
      ]),
  MacStep('firebase', 'bell', 'Turn on notifications', 'Firebase, so replies reach you instantly',
      [
        'In the wizard’s Notifications step, the easiest option is to sign in with Google and let it create everything.',
        'Prefer manual? Choose Manual Setup and follow the video there: create a free Firebase project, add a Firestore database, add an Android app with package name com.bluebubbles.messaging, then drop the two downloaded files into the server.',
        'This also lets Relay find your Mac automatically if its web address changes.',
      ],
      tip: 'Without this step Relay still works, but only delivers messages while the app is open.',
      link: 'https://docs.bluebubbles.app/server/installation-guides/manual-setup'),
  MacStep('connection', 'link', 'Set a password & connection', 'Then save it',
      [
        'In the Connection step, type a strong server password.',
        'Click the floppy‑disk icon next to it to save. (Easy to miss!)',
        'Leave Proxy Service on Cloudflare. If big videos fail to send later, switch it to zrok.',
      ]),
  MacStep('awake', 'sparkle', 'Keep the Mac awake', 'So the relay never sleeps',
      [
        'In BlueBubbles Settings, turn on “Keep macOS Awake”.',
        'Want to close the lid? Install the free app Amphetamine from the App Store, enable closed‑lid mode, and add it to Login Items.',
        'Turn on “Launch on startup” and “Auto restart” in BlueBubbles Settings so it comes back after power cuts.',
      ]),
  MacStep('privateapi', 'shield', 'Private API (optional)', 'Reactions, replies, typing, read receipts',
      [
        'Skip this for now — everything else works without it.',
        'It needs a macOS security feature (SIP) partly turned off, so only do it on a Mac that’s just for the relay.',
        'Follow the official guide when you’re ready.',
      ],
      link: 'https://docs.bluebubbles.app/private-api/installation',
      optional: true),
];

class MacChecklist extends StatelessWidget {
  final bool compact;
  const MacChecklist({super.key, this.compact = false});
  @override
  Widget build(BuildContext context) {
    final s = context.settings;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final done = s.macStepsDone;
        return SkCard(
          padding: const EdgeInsets.all(6),
          child: Column(children: [
            for (var i = 0; i < macSteps.length; i++) ...[
              if (i > 0) const SkDivider(indent: 56),
              _StepRow(step: macSteps[i], done: done.contains(macSteps[i].id)),
            ],
          ]),
        );
      },
    );
  }
}

class _StepRow extends StatelessWidget {
  final MacStep step;
  final bool done;
  const _StepRow({required this.step, required this.done});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal, s = context.settings;
    final hud = skin.upperHeadings;
    return Pressable(
      onTap: () => showMacStep(context, step),
      scale: .985,
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Row(children: [
          Pressable(
            onTap: () => s.toggleMacStep(step.id),
            builder: (_) => AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: done ? p.accent : withAlpha0(p.accent),
                shape: hud ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: hud ? BorderRadius.circular(3) : null,
                border: Border.all(color: done ? p.accent : p.text3, width: 1.5),
                boxShadow: done ? [BoxShadow(color: p.glow, blurRadius: 10)] : const [],
              ),
              child: AnimatedOpacity(duration: const Duration(milliseconds: 200), opacity: done ? 1 : 0, child: Ic('check', size: 16, color: p.onAccent, stroke: 2.8)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(step.title, style: skin.headline(p).copyWith(fontSize: 15.5, decoration: done ? TextDecoration.lineThrough : null, decorationColor: p.text3))),
                if (step.optional) ...[const SizedBox(width: 8), Text(hud ? 'OPTIONAL' : 'Optional', style: skin.caption(p).copyWith(color: p.warning))],
              ]),
              const SizedBox(height: 2),
              Text(step.short, style: skin.callout(p)),
            ]),
          ),
          Ic('chevron', size: 18, color: p.text3),
        ]),
      ),
    );
  }
}

Color withAlpha0(Color c) => c.withOpacity(0);

void showMacStep(BuildContext context, MacStep step) {
  showSkSheet(context, title: step.title, builder: (c) {
    final skin = c.skin, p = c.pal;
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < step.how.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 28,
                height: 28,
                child: skin.well(p, radius: skin.upperHeadings ? 3 : 14, child: Center(child: Text('${i + 1}', style: skin.callout(p).copyWith(color: p.accent, fontWeight: FontWeight.w700)))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Padding(padding: const EdgeInsets.only(top: 3), child: Text(step.how[i], style: skin.body(p)))),
            ]),
          ),
        if (step.tip != null) ...[
          skin.well(
            p,
            radius: skin.upperHeadings ? 6 : 16,
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Ic('info', size: 20, color: p.accent),
              const SizedBox(width: 10),
              Expanded(child: Text(step.tip!, style: skin.callout(p).copyWith(color: p.text))),
            ]),
          ),
          const SizedBox(height: 14),
        ],
        if (step.link != null)
          SkButton('Copy link for the Mac', icon: 'copy', primary: false, expand: true, onTap: () {
            Clipboard.setData(ClipboardData(text: step.link!));
            Toaster.show(c, 'Copied: ${step.link}', icon: 'check');
          }),
        const SizedBox(height: 10),
        SkButton('Mark as done', icon: 'check', expand: true, onTap: () {
          if (!c.settings.macStepsDone.contains(step.id)) c.settings.toggleMacStep(step.id);
          Navigator.of(c).pop();
        }),
      ]),
    );
  });
}

void showMacGuide(BuildContext context) {
  showSkSheet(context, title: 'Mac setup checklist', builder: (c) => const SingleChildScrollView(child: MacChecklist()));
}
