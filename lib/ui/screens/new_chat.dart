import 'package:flutter/widgets.dart';

import '../../state/ui_state.dart';
import '../kit/controls.dart';
import '../kit/overlays.dart';
import '../kit/scope.dart';

class NewChatSheet extends StatefulWidget {
  const NewChatSheet({super.key});
  @override
  State<NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends State<NewChatSheet> {
  final _to = TextEditingController();
  final _msg = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _to.dispose();
    _msg.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final addrs = _to.text.split(RegExp(r'[,;\n]')).map((a) => a.trim()).where((a) => a.isNotEmpty).toList();
    if (addrs.isEmpty || _msg.text.trim().isEmpty) {
      Toaster.show(context, 'Add at least one phone number or email, and a message.', icon: 'alert');
      return;
    }
    setState(() => _busy = true);
    final err = await context.store.startChat(addrs, _msg.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      Toaster.show(context, err, icon: 'alert');
      return;
    }
    final opened = context.store.openChat;
    Navigator.of(context).pop();
    if (opened != null) ui.openChat.value = opened;
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Send to one person or several (that makes a group). Use phone numbers with country code, or Apple ID emails.', style: skin.callout(p)),
        const SizedBox(height: 14),
        SkField(controller: _to, hint: '+1 555 123 4567, friend@icloud.com', icon: 'users', keyboard: TextInputType.emailAddress, autofocus: true),
        const SizedBox(height: 12),
        SkField(controller: _msg, hint: 'Message', icon: 'chat', maxLines: 4),
        const SizedBox(height: 18),
        SkButton('Send', icon: 'send', expand: true, busy: _busy, onTap: _send),
      ]),
    );
  }
}
