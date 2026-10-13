import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../kit/controls.dart';
import '../kit/icons.dart';
import '../kit/overlays.dart';
import '../kit/scope.dart';

/// BlueBubbles Server's QR code is the JSON array `[password, serverUrl]`.
(String, String)? parseServerQr(String raw) {
  try {
    final v = jsonDecode(raw);
    if (v is List && v.length >= 2) return (v[1].toString(), v[0].toString());
  } catch (_) {}
  return null;
}

/// Opens the camera. Returns (url, password) or null.
Future<(String, String)?> scanServerQr(BuildContext context) =>
    pushScreen<(String, String)?>(context, (c) => const _ScanScreen());

class _ScanScreen extends StatefulWidget {
  const _ScanScreen();
  @override
  State<_ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<_ScanScreen> with SingleTickerProviderStateMixin {
  final _cam = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  late final AnimationController _line = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);
  bool _done = false;
  String? _hint;

  @override
  void dispose() {
    _cam.dispose();
    _line.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture cap) {
    if (_done) return;
    for (final b in cap.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      final r = parseServerQr(raw);
      if (r != null) {
        _done = true;
        Navigator.of(context).pop(r);
        return;
      }
      setState(() => _hint = 'That QR code isn’t from BlueBubbles Server. Use the QR button on the server’s home screen.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    final mq = MediaQuery.of(context);
    const box = 250.0;
    return ColoredBox(
      color: const Color(0xFF000000),
      child: Stack(fit: StackFit.expand, children: [
        MobileScanner(
          controller: _cam,
          onDetect: _onDetect,
          errorBuilder: (ctx, err, _) => _ScanError(err, onRetry: () => _cam.start()),
        ),
        // Dim everything except the viewfinder.
        CustomPaint(painter: _MaskPainter(box)),
        Center(
          child: SizedBox(
            width: box,
            height: box,
            child: Stack(children: [
              CustomPaint(size: const Size(box, box), painter: _CornerPainter(p.accent, skin.upperHeadings)),
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _line,
                  builder: (_, __) => Padding(
                    padding: EdgeInsets.only(left: 14, right: 14, top: 14 + (box - 30) * _line.value),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(height: 2, decoration: BoxDecoration(color: p.accent, boxShadow: [BoxShadow(color: p.glow, blurRadius: 12)])),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
        Positioned(
          top: mq.padding.top + 12,
          left: 16,
          child: SkIconButton('x', onTap: () => Navigator.of(context).pop()),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: mq.padding.bottom + 30,
          child: skin.surface(
            p,
            strong: true,
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Ic('monitor', color: p.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _hint ?? 'On your Mac, open BlueBubbles Server, click the QR icon on the home screen, and point your camera at it.',
                  style: skin.callout(p).copyWith(color: p.text),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Shown instead of the camera when it can't start: says why, and how to get past it.
class _ScanError extends StatelessWidget {
  final MobileScannerException err;
  final VoidCallback onRetry;
  const _ScanError(this.err, {required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    final denied = err.errorCode == MobileScannerErrorCode.permissionDenied;
    final detail = err.errorDetails?.message ?? err.errorDetails?.code ?? err.errorCode.name;
    return ColoredBox(
      color: p.bg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Ic('monitor', color: p.accent),
            const SizedBox(height: 14),
            Text(denied ? 'Camera access is off' : 'The camera couldn’t start', style: skin.title(p), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              denied
                  ? 'Open Android Settings → Apps → Relay → Permissions → Camera → Allow, then come back and tap Try again.'
                  : 'Close other apps that may be using the camera and tap Try again. Or go back and type the server address and password in by hand.\n\n($detail)',
              style: skin.callout(p),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            Pressable(onTap: onRetry, builder: (_) => Padding(padding: const EdgeInsets.all(10), child: Text('Try again', style: skin.callout(p).copyWith(color: p.accent)))),
          ]),
        ),
      ),
    );
  }
}

class _MaskPainter extends CustomPainter {
  final double box;
  _MaskPainter(this.box);
  @override
  void paint(Canvas canvas, Size s) {
    final hole = Rect.fromCenter(center: s.center(Offset.zero), width: box, height: box);
    final path = Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & s), Path()..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(18))));
    canvas.drawPath(path, Paint()..color = const Color(0x99000000));
  }

  @override
  bool shouldRepaint(_MaskPainter o) => false;
}

class _CornerPainter extends CustomPainter {
  final Color c;
  final bool square;
  _CornerPainter(this.c, this.square);
  @override
  void paint(Canvas canvas, Size s) {
    const l = 34.0;
    final paint = Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = square ? StrokeCap.square : StrokeCap.round;
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
  bool shouldRepaint(_CornerPainter o) => o.c != c;
}
