import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';

import 'kit/controls.dart';
import 'kit/icons.dart';
import 'kit/scope.dart';

final _auth = LocalAuthentication();

/// Asks for a fingerprint / face / phone PIN. Returns true when unlocked.
Future<bool> unlockWithBiometrics(String reason) async {
  try {
    if (!await _auth.isDeviceSupported()) return true; // no lock on this phone: don't trap the user
    return await _auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
  } catch (_) {
    return false;
  }
}

/// Covers the app until you unlock it.
class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const LockScreen({super.key, required this.onUnlocked});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _try());
  }

  Future<void> _try() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await unlockWithBiometrics('Unlock Relay');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) widget.onUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    return skin.background(
      p,
      animate: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            skin.accentTile(p, size: 72, child: Ic('lock', size: 32, color: p.onAccent)),
            const SizedBox(height: 18),
            Text('Relay is locked', style: skin.title(p)),
            const SizedBox(height: 8),
            Text('Use your fingerprint or phone PIN to open your messages.', textAlign: TextAlign.center, style: skin.callout(p)),
            const SizedBox(height: 22),
            SkButton('Unlock', icon: 'lock', busy: _busy, onTap: _try),
          ]),
        ),
      ),
    );
  }
}
