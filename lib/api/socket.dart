import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

enum SocketState { disconnected, connecting, connected, badPassword }

class SocketEvent {
  final String type;
  final dynamic data;
  SocketEvent(this.type, this.data);
}

/// Real-time connection to BlueBubbles Server (Socket.IO v4, same origin as REST).
/// The server silently drops sockets with a wrong password, so a connect that is
/// immediately followed by a disconnect is reported as [SocketState.badPassword].
class SocketService {
  io.Socket? _socket;
  Timer? _keepAlive;
  int _missed = 0;
  DateTime? _connectedAt;

  final _events = StreamController<SocketEvent>.broadcast();
  final _state = StreamController<SocketState>.broadcast();
  SocketState state = SocketState.disconnected;

  Stream<SocketEvent> get events => _events.stream;
  Stream<SocketState> get states => _state.stream;

  static const _forward = [
    'new-message',
    'updated-message',
    'message-send-error',
    'typing-indicator',
    'chat-read-status-changed',
    'group-name-change',
    'participant-added',
    'participant-removed',
    'participant-left',
    'new-server',
  ];

  void _set(SocketState s) {
    state = s;
    _state.add(s);
  }

  void connect(String origin, String password, Map<String, String> headers) {
    disconnect();
    _set(SocketState.connecting);
    final s = io.io(
      origin,
      io.OptionBuilder()
          .setQuery({'guid': password})
          .setTransports(['websocket', 'polling'])
          .setExtraHeaders(headers)
          .disableAutoConnect()
          .enableForceNew()
          .enableReconnection()
          .setReconnectionDelay(1500)
          .setReconnectionDelayMax(10000)
          .build(),
    );
    _socket = s;

    // Callbacks from a socket we've already replaced are ignored.
    s.onConnect((_) {
      if (!identical(s, _socket)) return;
      _connectedAt = DateTime.now();
      _missed = 0;
      _set(SocketState.connected);
      _startKeepAlive();
    });
    s.onDisconnect((reason) {
      if (!identical(s, _socket)) return;
      // Only the server hanging up right away means a wrong password; our own
      // reconnects and network drops don't.
      final quick = reason == 'io server disconnect' &&
          _connectedAt != null &&
          DateTime.now().difference(_connectedAt!) < const Duration(seconds: 2);
      _connectedAt = null;
      _set(quick ? SocketState.badPassword : SocketState.disconnected);
    });
    s.onConnectError((_) {
      if (identical(s, _socket)) _set(SocketState.disconnected);
    });
    s.onReconnectAttempt((_) {
      if (identical(s, _socket) && state != SocketState.badPassword) _set(SocketState.connecting);
    });

    for (final name in _forward) {
      s.on(name, (data) => _events.add(SocketEvent(name, data)));
    }
    s.connect();
  }

  /// The server only notices dead sockets after ~3 minutes, so we ping with an
  /// acknowledged request every 30 s and rebuild after two misses.
  void _startKeepAlive() {
    _keepAlive?.cancel();
    _keepAlive = Timer.periodic(const Duration(seconds: 30), (_) {
      final s = _socket;
      if (s == null || !s.connected) return;
      var answered = false;
      s.emitWithAck('get-fcm-client', null, ack: (_) {
        answered = true;
        _missed = 0;
      });
      Future.delayed(const Duration(seconds: 10), () {
        if (!identical(s, _socket)) return; // replaced meanwhile
        if (!answered) {
          _missed++;
          if (_missed >= 2) {
            _missed = 0;
            s.disconnect();
            s.connect();
          }
        }
      });
    });
  }

  void reconnect() {
    final s = _socket;
    if (s == null) return;
    s.disconnect();
    s.connect();
  }

  void disconnect() {
    _keepAlive?.cancel();
    final s = _socket;
    _socket = null; // first, so its own "disconnect" callback is ignored
    s?.dispose();
    _connectedAt = null;
    if (state != SocketState.disconnected) _set(SocketState.disconnected);
  }
}
