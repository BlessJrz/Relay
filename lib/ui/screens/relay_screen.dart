import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../state/store.dart';
import '../kit/controls.dart';
import '../kit/icons.dart';
import '../kit/overlays.dart';
import '../kit/scope.dart';
import 'chat_list.dart';
import 'settings_screen.dart';

/// "Server" tab: health of the Mac relay.
class RelayScreen extends StatelessWidget {
  final bool wide;
  const RelayScreen({super.key, this.wide = false});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal, store = context.store, settings = context.settings;
    final top = wide ? 8.0 : MediaQuery.of(context).padding.top + 8;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final info = store.info;
        final online = store.conn == Conn.online;
        final cards = <Widget>[
          SkCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                skin.accentTile(p, size: 50, child: Ic('server', size: 25, color: p.onAccent)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Your Mac', style: skin.headline(p)),
                    Text(info != null ? 'macOS ${info.osVersion} · BlueBubbles ${info.serverVersion}' : 'BlueBubbles Server', style: skin.callout(p)),
                  ]),
                ),
                const ConnChip(),
              ]),
              const SizedBox(height: 16),
              skin.well(
                p,
                radius: 16,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  Expanded(child: Text(settings.serverUrl.isEmpty ? 'No server URL' : settings.serverUrl, maxLines: 1, overflow: TextOverflow.ellipsis, style: skin.mono(p))),
                  Pressable(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: settings.serverUrl));
                      Toaster.show(context, 'Server URL copied', icon: 'check');
                    },
                    builder: (_) => Ic('copy', size: 18, color: p.accent),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: SkButton('Reconnect', primary: false, icon: 'refresh', onTap: () => store.connect())),
                const SizedBox(width: 12),
                Expanded(child: SkButton('Edit', icon: 'link', onTap: () => showConnectionSheet(context))),
              ]),
            ]),
          ),
          SkCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('Latency', style: skin.headline(p))),
                Text(store.latency != null ? '${store.latency!.inMilliseconds} ms' : '—', style: skin.headline(p).copyWith(color: p.accent)),
              ]),
              const SizedBox(height: 12),
              store.latencyHistory.isEmpty
                  ? Text('Measured every 45 seconds while Relay is open.', style: skin.callout(p))
                  : Sparkline(store.latencyHistory, height: 54),
            ]),
          ),
          RowGroup(label: 'Features', children: [
            SettingsRow(icon: 'chat', title: 'Send & receive', subtitle: online ? 'Working' : 'Waiting for your Mac', trailing: StatusChip(online ? 'OK' : 'Off', kind: online ? 'ok' : 'bad')),
            SettingsRow(
              icon: 'shield',
              title: 'Private API',
              subtitle: 'Reactions, replies, typing, read receipts',
              trailing: StatusChip(info == null ? '—' : (info.canUsePrivateApi ? 'On' : 'Off'), kind: info?.canUsePrivateApi == true ? 'ok' : 'warn'),
              onTap: () => showPrivateApiHelp(context),
            ),
            SettingsRow(icon: 'bell', title: 'Push notifications', subtitle: settings.pushEnabled ? 'Delivered through your Firebase project' : 'Turned off', trailing: StatusChip(settings.pushEnabled ? 'On' : 'Off', kind: settings.pushEnabled ? 'ok' : 'idle')),
            SettingsRow(icon: 'wifi', title: 'Tunnel', subtitle: info?.proxyService.isNotEmpty == true ? info!.proxyService : 'Unknown', trailing: const SizedBox()),
          ]),
          if (store.lastError != null && !online)
            SkCard(
              child: Row(children: [
                Ic('alert', color: p.warning),
                const SizedBox(width: 12),
                Expanded(child: Text(store.lastError!, style: skin.callout(p))),
              ]),
            ),
          SkButton('Troubleshooting', primary: false, icon: 'help', expand: true, onTap: () => showTroubleshooting(context)),
        ];
        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(wide ? 4 : 18, top, wide ? 4 : 18, wide ? 20 : 130),
          children: [
            if (!wide) const Eyebrow('Relay status'),
            Heading('Your Mac'),
            const SizedBox(height: 16),
            for (var i = 0; i < cards.length; i++) Padding(padding: const EdgeInsets.only(bottom: 16), child: Stagger(index: i, child: cards[i])),
          ],
        );
      },
    );
  }
}

void showPrivateApiHelp(BuildContext context) {
  showSkSheet(context, title: 'Private API (optional)', builder: (c) {
    final skin = c.skin, p = c.pal;
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          'Without it, Relay can still send and receive every message. With it you also get tapback reactions, threaded replies, typing indicators and read receipts.',
          style: skin.body(p),
        ),
        const SizedBox(height: 14),
        Text('Turning it on requires partly disabling a macOS security feature (SIP) on the Mac. Only do this on a Mac you use just for the relay. Follow the official BlueBubbles guide: docs.bluebubbles.app → Private API setup.', style: skin.callout(p)),
        const SizedBox(height: 14),
        SkButton('Copy guide link', icon: 'copy', expand: true, onTap: () {
          Clipboard.setData(const ClipboardData(text: 'https://docs.bluebubbles.app/private-api/installation'));
          Navigator.of(c).pop();
          Toaster.show(context, 'Link copied — open it on your Mac', icon: 'check');
        }),
      ]),
    );
  });
}
