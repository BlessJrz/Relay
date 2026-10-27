// Data models for the BlueBubbles Server REST + socket API.
// Field names follow the server's serializers (ChatSerializer, MessageSerializer,
// HandleSerializer, AttachmentSerializer). All dates are ms since epoch.

int? _int(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

bool _bool(dynamic v) => v == true || v == 1 || v == 'true';

class Handle {
  final String address;
  final String service;
  Handle({required this.address, this.service = 'iMessage'});

  factory Handle.fromJson(Map<String, dynamic> j) => Handle(
        address: (j['address'] ?? '').toString(),
        service: (j['service'] ?? 'iMessage').toString(),
      );
}

class Attachment {
  final String guid;
  final String? mimeType;
  final String? uti;
  final String transferName;
  final int totalBytes;
  final int? width;
  final int? height;
  final bool isSticker;
  final bool hidden;

  Attachment({
    required this.guid,
    this.mimeType,
    this.uti,
    required this.transferName,
    this.totalBytes = 0,
    this.width,
    this.height,
    this.isSticker = false,
    this.hidden = false,
  });

  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
        guid: (j['guid'] ?? '').toString(),
        mimeType: j['mimeType']?.toString(),
        uti: j['uti']?.toString(),
        transferName: (j['transferName'] ?? 'attachment').toString(),
        totalBytes: _int(j['totalBytes']) ?? 0,
        width: _int(j['width']),
        height: _int(j['height']),
        isSticker: _bool(j['isSticker']),
        hidden: _bool(j['hideAttachment']),
      );

  String get _ext => transferName.contains('.')
      ? transferName.split('.').last.toLowerCase()
      : '';

  bool get isImage {
    final m = mimeType ?? '';
    if (m.startsWith('image/')) return true;
    return const ['jpg', 'jpeg', 'png', 'gif', 'heic', 'heif', 'webp']
        .contains(_ext);
  }

  bool get isVideo {
    final m = mimeType ?? '';
    if (m.startsWith('video/')) return true;
    return const ['mov', 'mp4', 'm4v'].contains(_ext);
  }

  bool get isAudio {
    final m = mimeType ?? '';
    if (m.startsWith('audio/')) return true;
    return const ['caf', 'm4a', 'mp3', 'aac', 'amr'].contains(_ext);
  }

  String get sizeLabel {
    if (totalBytes <= 0) return '';
    if (totalBytes < 1024) return '$totalBytes B';
    if (totalBytes < 1024 * 1024) {
      return '${(totalBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Tapback reactions. The server sends `associatedMessageType` as strings such as
/// "love" or "-love" (removal), and "sticker".
const reactionEmoji = {
  'love': '❤️',
  'like': '👍',
  'dislike': '👎',
  'laugh': '😂',
  'emphasize': '‼️',
  'question': '❓',
};

class Message {
  final String guid;
  final String? tempGuid;
  final String text;
  final String? subject;
  final bool isFromMe;
  final Handle? handle;
  final int dateCreated;
  final int? dateDelivered;
  final int? dateRead;
  final int error;
  final List<Attachment> attachments;
  final String? associatedMessageGuid;
  final String? associatedMessageType;
  final int itemType;
  final int groupActionType;
  final String? groupTitle;
  final String? threadOriginatorGuid;
  final List<String> chatGuids;
  final int? dateEdited;
  final int? dateRetracted;

  /// Local-only: true while a send is in flight.
  final bool sending;

  /// Local-only: waiting for the Mac to be reachable again.
  final bool queued;

  /// Local-only: true when a send failed.
  final bool failed;

  Message({
    required this.guid,
    this.tempGuid,
    required this.text,
    this.subject,
    required this.isFromMe,
    this.handle,
    required this.dateCreated,
    this.dateDelivered,
    this.dateRead,
    this.error = 0,
    this.attachments = const [],
    this.associatedMessageGuid,
    this.associatedMessageType,
    this.itemType = 0,
    this.groupActionType = 0,
    this.groupTitle,
    this.threadOriginatorGuid,
    this.chatGuids = const [],
    this.dateEdited,
    this.dateRetracted,
    this.sending = false,
    this.queued = false,
    this.failed = false,
  });

  factory Message.fromJson(Map<String, dynamic> j) {
    final chats = (j['chats'] as List?) ?? const [];
    return Message(
      guid: (j['guid'] ?? '').toString(),
      tempGuid: j['tempGuid']?.toString(),
      text: (j['text'] ?? '').toString().replaceAll('￼', '').trim(),
      subject: j['subject']?.toString(),
      isFromMe: _bool(j['isFromMe']),
      handle: j['handle'] is Map
          ? Handle.fromJson(Map<String, dynamic>.from(j['handle']))
          : null,
      dateCreated: _int(j['dateCreated']) ?? DateTime.now().millisecondsSinceEpoch,
      dateDelivered: _int(j['dateDelivered']),
      dateRead: _int(j['dateRead']),
      error: _int(j['error']) ?? 0,
      attachments: ((j['attachments'] as List?) ?? const [])
          .whereType<Map>()
          .map((a) => Attachment.fromJson(Map<String, dynamic>.from(a)))
          // Rich-link data the sender's iPhone attaches; we draw our own card.
          .where((a) => !a.hidden && !a.transferName.toLowerCase().endsWith('pluginpayloadattachment'))
          .toList(),
      associatedMessageGuid: j['associatedMessageGuid']?.toString(),
      associatedMessageType: j['associatedMessageType']?.toString(),
      itemType: _int(j['itemType']) ?? 0,
      groupActionType: _int(j['groupActionType']) ?? 0,
      groupTitle: j['groupTitle']?.toString(),
      threadOriginatorGuid: j['threadOriginatorGuid']?.toString(),
      dateEdited: _int(j['dateEdited']),
      dateRetracted: _int(j['dateRetracted']),
      chatGuids: chats
          .whereType<Map>()
          .map((c) => (c['guid'] ?? '').toString())
          .where((g) => g.isNotEmpty)
          .toList(),
    );
  }

  Message copyWith({
    String? guid,
    bool? sending,
    bool? queued,
    bool? failed,
    int? dateDelivered,
    int? dateRead,
  }) =>
      Message(
        guid: guid ?? this.guid,
        tempGuid: tempGuid,
        text: text,
        subject: subject,
        isFromMe: isFromMe,
        handle: handle,
        dateCreated: dateCreated,
        dateDelivered: dateDelivered ?? this.dateDelivered,
        dateRead: dateRead ?? this.dateRead,
        error: error,
        attachments: attachments,
        associatedMessageGuid: associatedMessageGuid,
        associatedMessageType: associatedMessageType,
        itemType: itemType,
        groupActionType: groupActionType,
        groupTitle: groupTitle,
        threadOriginatorGuid: threadOriginatorGuid,
        chatGuids: chatGuids,
        dateEdited: dateEdited,
        dateRetracted: dateRetracted,
        sending: sending ?? this.sending,
        queued: queued ?? this.queued,
        failed: failed ?? this.failed,
      );

  /// A tapback (love/like/…) or its removal.
  bool get isReaction {
    final t = associatedMessageType;
    if (t == null || t.isEmpty || t == 'null' || t == '0') return false;
    final base = t.startsWith('-') ? t.substring(1) : t;
    return reactionEmoji.containsKey(base);
  }

  bool get isReactionRemoval => isReaction && associatedMessageType!.startsWith('-');

  String? get reactionKind {
    if (!isReaction) return null;
    final t = associatedMessageType!;
    return t.startsWith('-') ? t.substring(1) : t;
  }

  /// The message a reaction points at. Format is like "p:0/<guid>" or "bp:<guid>".
  String? get reactionTarget {
    final a = associatedMessageGuid;
    if (a == null) return null;
    final slash = a.lastIndexOf('/');
    if (slash >= 0) return a.substring(slash + 1);
    final colon = a.lastIndexOf(':');
    return colon >= 0 ? a.substring(colon + 1) : a;
  }

  /// Group events: name change, people added/removed, etc.
  bool get isGroupEvent => itemType != 0;

  bool get hasContent => text.isNotEmpty || attachments.isNotEmpty;

  DateTime get date => DateTime.fromMillisecondsSinceEpoch(dateCreated);
}

class Chat {
  final String guid;
  final int style; // 43 = group, 45 = 1:1
  final String chatIdentifier;
  final String displayName;
  final List<Handle> participants;
  final Message? lastMessage;

  Chat({
    required this.guid,
    required this.style,
    required this.chatIdentifier,
    required this.displayName,
    required this.participants,
    this.lastMessage,
  });

  factory Chat.fromJson(Map<String, dynamic> j) => Chat(
        guid: (j['guid'] ?? '').toString(),
        style: _int(j['style']) ?? 45,
        chatIdentifier: (j['chatIdentifier'] ?? '').toString(),
        displayName: (j['displayName'] ?? '').toString(),
        participants: ((j['participants'] as List?) ?? const [])
            .whereType<Map>()
            .map((h) => Handle.fromJson(Map<String, dynamic>.from(h)))
            .toList(),
        lastMessage: j['lastMessage'] is Map
            ? Message.fromJson(Map<String, dynamic>.from(j['lastMessage']))
            : null,
      );

  Chat copyWith({Message? lastMessage, String? displayName, List<Handle>? participants}) => Chat(
        guid: guid,
        style: style,
        chatIdentifier: chatIdentifier,
        displayName: displayName ?? this.displayName,
        participants: participants ?? this.participants,
        lastMessage: lastMessage ?? this.lastMessage,
      );

  bool get isGroup => style == 43 || guid.contains(';+;');
  bool get isSms => guid.startsWith('SMS');
  int get lastDate => lastMessage?.dateCreated ?? 0;
}

class Contact {
  final String name;
  final List<String> addresses;
  Contact({required this.name, required this.addresses});

  factory Contact.fromJson(Map<String, dynamic> j) {
    String name = (j['displayName'] ?? '').toString().trim();
    if (name.isEmpty) {
      name = '${j['firstName'] ?? ''} ${j['lastName'] ?? ''}'.trim();
    }
    if (name.isEmpty) name = (j['nickname'] ?? '').toString();
    final addrs = <String>[];
    for (final k in ['phoneNumbers', 'emails']) {
      for (final e in (j[k] as List?) ?? const []) {
        if (e is Map && e['address'] != null) addrs.add(e['address'].toString());
      }
    }
    return Contact(name: name, addresses: addrs);
  }
}

class ServerInfo {
  final String osVersion;
  final String serverVersion;
  final bool privateApi;
  final bool helperConnected;
  final String proxyService;
  final bool? detectedImessage;
  final String? icloudAccount;

  ServerInfo({
    required this.osVersion,
    required this.serverVersion,
    required this.privateApi,
    required this.helperConnected,
    required this.proxyService,
    this.detectedImessage,
    this.icloudAccount,
  });

  factory ServerInfo.fromJson(Map<String, dynamic> j) => ServerInfo(
        osVersion: (j['os_version'] ?? '').toString(),
        serverVersion: (j['server_version'] ?? '').toString(),
        privateApi: _bool(j['private_api']),
        helperConnected: _bool(j['helper_connected']),
        proxyService: (j['proxy_service'] ?? '').toString(),
        detectedImessage: j['detected_imessage'] == null
            ? null
            : (j['detected_imessage'] is bool
                ? j['detected_imessage'] as bool
                : j['detected_imessage'].toString().isNotEmpty),
        icloudAccount: j['detected_icloud']?.toString(),
      );

  /// True when reactions, typing indicators, read receipts and replies work.
  bool get canUsePrivateApi => privateApi && helperConnected;
}

/// Normalises a phone number or email so contacts can be matched to handles.
String normalizeAddress(String a) {
  final s = a.trim().toLowerCase();
  if (s.contains('@')) return s;
  final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
}


/// A message the Mac will send later.
class ScheduledMessage {
  final int id;
  final String chatGuid;
  final String text;
  final int scheduledFor;
  final String status;
  const ScheduledMessage({required this.id, required this.chatGuid, required this.text, required this.scheduledFor, required this.status});

  factory ScheduledMessage.fromJson(Map<String, dynamic> j) {
    final p = j['payload'] is Map ? Map<String, dynamic>.from(j['payload']) : const <String, dynamic>{};
    return ScheduledMessage(
      id: _int(j['id']) ?? 0,
      chatGuid: (p['chatGuid'] ?? '').toString(),
      text: (p['message'] ?? '').toString(),
      scheduledFor: _int(j['scheduledFor']) ?? 0,
      status: (j['status'] ?? '').toString(),
    );
  }

  bool get pending => status.isEmpty || status == 'pending';
}
