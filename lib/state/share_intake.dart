import 'package:flutter/services.dart';

/// What another app shared to Relay.
class SharedContent {
  final List<String> paths;
  final String? text;
  const SharedContent(this.paths, this.text);
  bool get isEmpty => paths.isEmpty && (text == null || text!.trim().isEmpty);

  static SharedContent? parse(dynamic raw) {
    if (raw is! Map) return null;
    final c = SharedContent(
      [for (final p in (raw['paths'] as List? ?? const [])) p.toString()],
      raw['text']?.toString(),
    );
    return c.isEmpty ? null : c;
  }
}

/// Receives items from Android's Share menu (see MainActivity.kt).
class ShareIntake {
  static const _ch = MethodChannel('relay/share');

  static Future<void> listen(void Function(SharedContent) onShare) async {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'shared') {
        final c = SharedContent.parse(call.arguments);
        if (c != null) onShare(c);
      }
    });
    try {
      final c = SharedContent.parse(await _ch.invokeMethod('initial'));
      if (c != null) onShare(c);
    } catch (_) {}
  }

  static void stop() => _ch.setMethodCallHandler(null);
}
