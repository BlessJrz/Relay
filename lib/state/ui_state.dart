import 'package:flutter/widgets.dart';

/// The chat on screen. [show] also works for the chat that's already the
/// value (hidden behind Settings, or after folding): it still tells the shell.
class OpenChat extends ValueNotifier<String?> {
  OpenChat() : super(null);
  void show(String guid) {
    if (value == guid) {
      notifyListeners();
    } else {
      value = guid;
    }
  }
}

/// View state that must survive a design switch (which rebuilds the whole tree).
class UiState {
  final tab = ValueNotifier<int>(0);
  final openChat = OpenChat();
  final showTips = ValueNotifier<bool>(false);
  final search = ValueNotifier<String>('');

  /// Folders design: 0 all, 1 unread, 2 groups, 3 people.
  final folder = ValueNotifier<int>(0);

  /// Targets for the in-app tutorial spotlight.
  final keys = <String, GlobalKey>{
    'nav': GlobalKey(debugLabel: 'nav'),
    'search': GlobalKey(debugLabel: 'search'),
    'status': GlobalKey(debugLabel: 'status'),
    'plus': GlobalKey(debugLabel: 'plus'),
  };
}

final ui = UiState();
