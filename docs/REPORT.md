# Relay: project report

Last updated 27 Oct 2026. Covers builds 1–49 and full release v1.0.0.

This report explains what Relay is, how it is put together, what has been built, and the decisions and gotchas behind it. It is written so a new Claude Code session, or a person, can pick the project up cold. The short operating notes are in `CLAUDE.md` at the repo root.

---

## 1. What Relay is

Relay is a custom **Android app written in Flutter** that lets the owner use **iMessage**, including group chats, on a **Samsung Galaxy Z Fold7**. It replaces the official BlueBubbles Android client.

How it reaches iMessage:

```
Fold7 (Relay) ──HTTPS/Socket.IO──► Cloudflare tunnel URL ──► old MacBook running BlueBubbles Server ──► Messages.app / iMessage
        ▲                                                                     │
        └────────────── Firebase Cloud Messaging (data-only pushes) ◄─────────┘
```

The Mac:
- **The Mac** is an old MacBook with a broken screen. It is kept awake, signed in to iMessage, and runs **BlueBubbles Server**.
- **Internet access** comes from a **Cloudflare tunnel URL**, so there's no port forwarding.
- **Private API.** BlueBubbles' **Private API** helper is turned on. Reactions, replies, edit, unsend, read receipts and typing indicators need it.

- **Push:** BlueBubbles sends FCM data messages through a Firebase project created during Mac setup. Relay downloads that Firebase config from the Mac at runtime (`/fcm/client`), so **nothing Firebase-specific is baked into the APK**. The Android application id must therefore be `com.bluebubbles.messaging`, which matches the Firebase Android app that BlueBubbles registers.
- **Code:** https://github.com/BlessJrz/Relay (public).
- **Downloads:** rolling test build at https://github.com/BlessJrz/Relay/releases/tag/latest; full release at https://github.com/BlessJrz/Relay/releases/tag/v1.0.0.

### Owner preferences

- Tests on the phone and sends screenshots. Wants **short, plain replies without jargon**.
- Likes **black, red, white and blue**. No emoji as UI icons.
- After every change: push, wait for CI, then tell him **the build number and the `latest` link**. Never claim on-device behaviour that hasn't been seen.

---

## 2. Tech stack

| Area | Choice |
|---|---|
| Framework | Flutter **3.47.7** (stable), Dart SDK `>=3.4.0`. It uses `flutter/widgets.dart` with its own design kit, not Material widgets. |
| Server API | BlueBubbles REST v1 + Socket.IO v4 (`socket_io_client`) |
| Push | `firebase_core`, `firebase_messaging` (data-only), `flutter_local_notifications` ^18 |
| Storage | `shared_preferences` for most things; `flutter_secure_storage` for the server password |
| Media | `video_player`, `image_picker`, `gal` (save to gallery), `record` (voice notes, AAC-LC .m4a), `path_provider` |
| Other | `connectivity_plus`, `mobile_scanner` (QR setup), `local_auth` (fingerprint lock), `url_launcher`, `google_fonts`, `flutter_svg` |
| Native | `MainActivity.kt` (extends **FlutterFragmentActivity**, which `local_auth` needs) |
| CI | GitHub Actions on ubuntu-latest, Java 17 |

Fonts are warmed up at start: Inter, Outfit, Rubik, Manrope and JetBrains Mono.

---

## 3. Build, test and release pipeline

**No local Flutter was used during development.** Every push to `main` runs `.github/workflows/build.yml`:

1. `flutter pub get`, then `flutter analyze`. Errors are collected, plus a line `ANALYZE SUMMARY: N warnings, M infos` and `LINT …` lines.
2. `flutter test --reporter expanded`.
3. The combined log is force-pushed as `test.log` to the orphan branch **`ci-test`**. Read it with:
   ```
   gh api "repos/BlessJrz/Relay/contents/test.log?ref=ci-test" -H "Accept: application/vnd.github.raw"
   ```
4. `flutter build apk --release --build-number=<run number>`.
5. If the build fails, `errors.txt` is pushed to the orphan branch **`ci-logs`**.
6. The APK is published as `Relay-<run>.apk` on the rolling prerelease **`latest`**. The old one is deleted each time.
7. **Full release:** if `RELEASE_VERSION` (currently `1.0.0`) names a version with no release yet, CI publishes `v<ver>` with `Relay-<ver>.apk` and `RELEASE_NOTES.md` as the notes, marked Latest. To ship 1.1, bump the file and the notes.

**Signing:** the committed keystore `android/keystore/relay-shared.jks` is used, so every CI build installs over the previous one and keeps the setup. The PC build path (`tool/setup.ps1`, `Build Relay.bat`) uses a different key. An APK built that way **will not install over a CI build** unless the app is uninstalled first, which loses the setup.

**The cloud session's limits:** it couldn't push tags, create releases, or use the GraphQL API, which is why CI does all the releasing. Claude Code on a PC with `gh auth` won't have those limits, but keeping releases in CI is still the clean path.

### Tests (`test/`), 35 passing at build 49

| File | What it guards |
|---|---|
| `shell_smoke_test.dart` | Renders every design × folded (410 dp) / unfolded (880 dp) × light/dark. Fails on any build or layout exception. |
| `keyboard_test.dart` | The composer stays above the keyboard; insets behave. |
| `store_logic_test.dart` | Chat ordering. Outgoing bubble vs text contrast ≥ 4:1 for every skin and accent. |
| `sync_test.dart` | Talks to a real `HttpServer` fake Mac: syncing, edits/unsends, the offline send queue. |
| `links_test.dart` | Link finding, Open Graph parsing (incl. unquoted attributes), YouTube id extraction. |
| `features_test.dart` | Send-later presets/labels, `firstUnreadIndex`, drafts/mutes/pins in settings. |

The analyzer is at 0 warnings. 4 `sort_child_properties_last` infos remain in `setup_flow.dart` and are harmless.

---

## 4. Code map

```
lib/
  main.dart                 start-up, lifecycle, app lock, push hooks, font warm-up
  api/
    bb_api.dart             BlueBubbles REST client
    models.dart             Chat, Message, Handle, Attachment (+ JSON parsing)
    socket.dart             Socket.IO wrapper (live events)
  state/
    store.dart              THE app state (ChangeNotifier): chats, messages, sync, queue, banners
    settings.dart           prefs: server/password, design, accents, pins, mutes, drafts, toggles
    avatars.dart            contact/group/custom photos cached as files
    link_preview.dart       link finding + previews (YouTube/oEmbed/Open Graph)
    video_thumbs.dart       downloads videos to a cache and grabs a frame natively
    media_save.dart         stream attachment to a file, then save to gallery (gal)
    schedule.dart           send-later presets, labels, first-unread index
    share_intake.dart       Android Share-menu intake
    ui_state.dart           global ValueNotifiers (openChat, folder, showTips…)
  push/push.dart            FCM + local notifications, background isolate, actions
  skins/
    skin.dart               Skin base class, Palette, AppLayout enum
    minimal.dart            "Modern Minimal" skin (standard layout)
    messengers.dart         FlatSkin + PinnedSkin / MaterialSkin / FoldersSkin
  ui/
    shell.dart              folded vs unfolded layout, tabs, banners → notifications
    lock.dart               fingerprint lock screen
    kit/                    design-neutral controls drawn through the current skin
      controls.dart (SkField, SkButton, RowGroup, Pressable, Spinner…)
      overlays.dart (Toaster, sheets: bottom sheet folded / centered card unfolded)
      icons.dart (Ic: hand-drawn SVG-path icon set) · nav.dart · scope.dart · link_text.dart
    screens/
      chat_list.dart        standard list + AltChatList/AltChatRow, pinned grid, folders, swipes
      conversation.dart     the chat screen (largest file, ~1.5k lines)
      chat_media.dart       per-chat Photos/videos & Links page, photo viewer, save
      video_view.dart       full-screen player + Apple-style VideoTile
      new_chat.dart · relay_screen.dart (Mac status) · settings_screen.dart
    setup/                  first-run flow, QR scanner, Mac setup guide
    tutorial/coach.dart     first-run coach marks
android/app/src/main/
  AndroidManifest.xml       permissions, share intents, notification action receiver
  kotlin/com/bluebubbles/relay/MainActivity.kt
tool/icon/                  make.py + apply_b.py (app icon + notification icon generator)
tool/android_res/           icon/launch resources; tool/setup.ps1 copies them into android/app/src/main/res (CI uses the committed android/ res directly)
tools/archive/              Docker/Python job for the owner's UGREEN NAS: plain-text chat log
```

### How the pieces talk

- **`Store`** is one `ChangeNotifier`, reached through `context.store` from `ui/kit/scope.dart` (`AppScope`). It owns the API client, the socket and the polling timer. Widgets listen with `ListenableBuilder`.
- **`Settings`** is a separate `ChangeNotifier` (`context.settings`). Changing it rebuilds the whole app, because design and palette come from it. **Draft changes deliberately do *not* notify Settings.** They bump `settings.drafts` (a `ValueNotifier<int>`) that only the chat lists listen to. Rebuilding the whole app while typing upset the keyboard.
- **Skins** decide colours, fonts, bubble shapes and the **layout** (`AppLayout.standard | pinned | material | folders`), so a design changes arrangement, not just paint. UI code switches on `context.skin.layout`.
- **Folded vs unfolded:** below 700 dp, `Shell` shows one pane and pushes the conversation full screen. At 700 dp and up it shows list + conversation side by side (Folders adds a left rail). The Pinned and Folders right panes are edge to edge, with no top padding.

---

## 5. BlueBubbles API used

The password goes in the `guid` query parameter on every request. The server QR code is JSON `[password, url]`.

| Purpose | Endpoint |
|---|---|
| Health/info | `GET /ping`, `GET /server/info` |
| Chats | `POST /chat/query` (with `lastMessage`, participants), `GET /chat/:guid/message`, `POST /chat/new`, `POST /chat/:guid/read` (Private API), `GET /chat/:guid/icon` |
| Send | `POST /message/text` (method `private-api` when available, with `selectedMessageGuid` for replies), `POST /message/attachment` (multipart) |
| React | `POST /message/react` |
| Edit | `POST /message/:guid/edit` with `{editedMessage, backwardsCompatibilityMessage, partIndex}` |
| Unsend | `POST /message/:guid/unsend` with `{partIndex}` |
| Send later | `POST /message/schedule` with `{type:'send-message', payload:{chatGuid,message,method}, scheduledFor, schedule:{type:'once'}}`; `GET /message/schedule`; `DELETE /message/schedule/:id` |
| Attachments | `GET /attachment/:guid/download` |
| Contacts | `GET /contact?extraProperties=avatar` |
| Push | `GET /fcm/client` (Firebase config), device registration |

Socket events handled: `new-message`, `updated-message`, `message-send-error`, typing, group name and participant changes.

**API gotchas learned the hard way:**
- `/attachment/:guid/download` **with width/height/quality resizing strips EXIF rotation**, which made photos sideways or upside-down. Relay downloads the original and shrinks it on the phone (`ResizeImage(width: 720)`).
- The server has **no video thumbnails**. Relay downloads the video to `vcache/*.vid` (600 MB cache cap, skips files over 150 MB). It then grabs a frame with Android's `MediaMetadataRetriever` through the MethodChannel `relay/media` → `videoThumb`. A remote URL for the retriever didn't work, so it has to be a local file. Failures aren't retried in the same session.
- Edit/unsend must target the text part (`partIndex`), so they're only offered on your own text-only messages when the Private API is on.
- Sync compares `dateEdited` and `dateRetracted` so edits and unsends show up.

---

## 6. Features (what's been built)

### Designs, which replaced the original Liquid Glass / Neumorphism / Monochrome Luxe skins

- **Pinned** (default, inspired by Apple Messages, Inter font):
  - Pinned-contacts grid at the top, seeded automatically with your top 3 chats.
  - A **blurred, translucent header that floats over the chat** (`_pinnedHeaderH = 78`).
  - A compact pill composer.
- **Material** (inspired by Google Messages, Outfit): rounded panels, a "Start chat" FAB, a pill composer with attach/camera/gallery.
- **Folders** (inspired by Telegram, Rubik): folder tabs, or a folder rail when unfolded; a pencil FAB; coloured sender names inside group bubbles.
- **Modern Minimal** (kept from before): standard layout with a floating tab bar.

Accents were adjusted so text on outgoing bubbles always passes 4:1 contrast, and a test enforces it. The four designs without a tab bar open Settings and Mac as full pages with Back.

### Messaging

- Swipe a message to reply; double-tap to ❤️ (tapback); long-press for actions. Option menus are **small popups**: a centered card when unfolded, a bottom sheet when folded, never full screen.
- **Edit and unsend** (Private API, macOS 13+), with an "Edited" label and an unsent event line.
- **Send later:** hold the send button, then pick a preset or a date and time. Scheduled messages are listed in the chat and can be cancelled.
- **Voice messages:** with an empty box, the send button becomes a mic. Recording uses AAC-LC .m4a, so iPhones see an audio attachment rather than a native voice-memo bubble. Audio bubbles play in-line.
- Photos (pinch-zoom viewer, save), camera button, videos with **Apple-style tiles** (the frame fills a rounded bubble, with a frosted play button and length label) that play inside Relay.
- **Link previews:**
  - YouTube: thumbnail from `i.ytimg.com` and title from YouTube oEmbed, with a play button.
  - TikTok, Spotify, Vimeo and SoundCloud via their oEmbed.
  - Everything else via Open Graph. Relay asks as `facebookexternalhit` first, because Instagram, TikTok, X and Reddit only give preview tags to bots, then as Chrome. It reads only until `</head>`.
  - Failures retry after 2 minutes, and a plain domain card shows if no preview comes back.
  - iPhone `.pluginPayloadAttachment` rich-link files are hidden.
- "New messages" divider and a jump-to-latest button.
- **Drafts** are kept per chat. The list shows "Draft: …" in red/accent.
- **Offline send queue:** sends that fail with status 0/502/503/530 (the Mac is unreachable) are queued in prefs (`send_queue`) and go out automatically when the connection returns. The queue flushes on reconnect, after a successful ping, and during polling. A 408/504 is marked **failed** instead, because the Mac may have sent it, and retrying could duplicate it.
- The composer starts each message with a capital letter. The Samsung keyboard can't keep caps lock after a send; see gotchas.

### Chats

- Pin, mute, and mark read or unread by swiping (right: read/unread, left: mute) or long-pressing.
- Unread state is **kept on the phone** (`last_read` in prefs) and merged with notification "Mark read" actions when the app comes back.
- A per-chat **Photos, videos & links** page. Save any photo or video to the gallery; saving streams to a file, so big videos don't fill memory.
- Group names, participants, custom group photos and contact photos (cached).
- Share to Relay from other apps (`relay/share` channel) opens a chat picker.

### Notifications

- **Background:** a data-only FCM wakes `relayBackgroundPush`, which runs in a separate isolate and reloads prefs. It builds a `MessagingStyle` notification that keeps the last 6 lines per chat (`notif_lines_<chat>`).
  - **Reply** (RemoteInput) and **Mark read** actions. They work from a watch too.
  - The actions run in a background isolate. If Relay is running, they're forwarded to the live app via `IsolateNameServer` port `relay_notification_actions`; otherwise they're sent straight to the Mac.
  - The manifest **must** contain `com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver`.
- **Foreground (build 47):** a message in a chat you're *not looking at* shows a real heads-up notification. Both the FCM `onMessage` path and the socket/poll banner path go through `Push.showWhileOpen`, deduplicated by message guid. It falls back to the in-app toast if notifications are switched off.
- Muted chats never notify. The open chat never notifies, unless the app is locked.
- **Mac offline alert:** if the Mac stops answering for 3 minutes, Relay shows a status notification (channel `status`, id 7001). It's skipped when the phone itself has no network.
- The notification small icon is `@drawable/ic_stat_relay`, a white silhouette of the app icon.

### Security and other

- An optional **fingerprint lock** (`local_auth`, needs FlutterFragmentActivity + `USE_BIOMETRIC`). It relocks after 30 s away, and read receipts aren't sent while locked.
- **App icon "B"** with the matching notification icon. Both are generated by `tool/icon/make.py` + `apply_b.py`: PIL + numpy, supersampled at 2160 px, with the foreground pulled out by rendering over black and over white.
- **Keyboard:** the app unfocuses on pause, so coming back doesn't leave a keyboard-sized gap.
- **Display:** 120 Hz requested natively.
- **NAS archive** (`tools/archive`): an optional Docker job that writes every conversation to plain text.

---

## 7. How it was built (process)

- Work happened in a cloud session with **no Flutter SDK**. Code was edited in a working copy, synced into the git clone by a small script, committed, and pushed. CI was the compiler and test runner: results come from the `ci-test` branch, and build failures from `ci-logs`.
- Every UI change was checked by `shell_smoke_test` across all designs and both screen sizes before the owner saw it. The owner then tested on the Fold7 and sent screenshots.
- A separate review agent audited the code before v1.0.0. Its findings were all fixed:
  - the missing notification action receiver
  - duplicate sends from queue timeouts
  - the queue getting stuck
  - false Mac-offline alerts
  - read receipts sent while locked
  - audio still playing after leaving a chat
  - recording carrying over between chats
  - edit/unsend hitting the attachment part
  - whole videos loaded into memory when saving
  - sync missing edits and unsends
- With Claude Code on a PC you can install Flutter 3.47.7 and run `flutter analyze` / `flutter test` locally. That's much faster than waiting for CI. Keep CI as the source of the installable APK, because of the shared signing key.

---

## 8. Build history (highlights)

| Builds | What changed |
|---|---|
| early | Core client: setup flow with QR scanning, chat list, conversation, socket + polling, push, original three skins + Modern Minimal, NAS archive |
| | Keyboard gap fix after leaving the app; in-app video playback |
| | Three new layouts (Pinned / Material / Folders) replace Liquid Glass, Neumorphism and Monochrome Luxe |
| | Pinned header made translucent and smaller; unfolded edge-to-edge; settings in one column when unfolded; photo rotation fix |
| | Video thumbnails (download + native frame grab), then Apple-style video tiles |
| → v1.0.0 | QoL batch: swipe reply, double-tap heart, new-messages line, jump button, edit/unsend, send later, voice, notification reply/mark read, mute, Mac offline alert, save to phone, media page, camera, chat swipes, drafts, offline queue, fingerprint lock; code cleanup + review fixes; **full release v1.0.0** |
| | Option menus as small popups instead of full-screen sheets |
| 46 | New app icon B + matching notification icon |
| 47 | Heads-up notifications for other chats while Relay is open; composer auto-capitalises; drafts no longer rebuild the app |
| 48 | Link previews: bot user agent first, head-only reading, retry, fallback card, hide rich-link payload files |
| 49 | YouTube previews (thumbnail + title via oEmbed, play button); TikTok/Spotify/Vimeo/SoundCloud oEmbed |

---

## 9. Gotchas and decisions to remember

- **Samsung keyboard caps lock:** clearing the text box after send changes the IME's composing region. Flutter's Android `TextInputPlugin` then calls `restartInput`, and the Samsung keyboard resets Shift. Android's Flutter embedding also ignores `TextInput.updateConfig`, so the capitalization mode can't be switched on the fly. The current answer is `TextCapitalization.sentences`. Don't spend time on keyed TextFields or readOnly toggles: they close the input connection and hide the keyboard.
- **Don't notify `Settings` for high-frequency changes** (drafts, typing). It rebuilds the whole MaterialApp-level tree.
- **Notifications:** `handleData` (background) and `showWhileOpen` (foreground) are separate paths. Only the main isolate dedupes by guid, so don't show from the main isolate while the app is in the background. The background FCM isolate already does that, and both would append the same line.
- **Video thumbnails** need a local file for `MediaMetadataRetriever`.
- **Photos:** never use the server's resize parameters (EXIF loss).
- **Null-aware collection elements (`?expr`)** aren't allowed under SDK 3.4; use `whereType`.
- `AndroidNotificationAction` in FLN 18 has no `semanticAction`.
- Firebase must stay runtime-configured. Don't add a `google-services.json`.
- **Bulk regex edits caused breakage once** (de-HUD script mangled code). Make targeted edits and let CI/tests confirm.

---

## 10. Open ideas / not done

- Calls aren't possible (BlueBubbles can't place FaceTime calls).
- Voice notes arrive on iPhones as audio files, not native voice-memo bubbles.
- No Wear OS app; watch replies work through the notification's Reply action.
- X/Twitter and Instagram previews depend on those sites serving tags to bots. If they stop, consider a dedicated handler like the YouTube one.
- Link previews are fetched by the phone directly. Fetching them through the Mac would need a server plugin.
- Possible next steps: confirm link previews for ordinary sites on the device; native-style tapback picker; message search; per-chat notification sounds.

---

## 11. Moving to Claude Code: checklist

1. `git clone https://github.com/BlessJrz/Relay` on the PC (or let Claude Code clone it). Everything lives in the repo: Flutter code, Android project, CI, keystore, icon tools.
2. Optional: install Flutter **3.47.7** + Java 17 so `flutter analyze` and `flutter test` run locally.
3. Claude Code reads **`CLAUDE.md`** automatically; this report is linked from it.
4. Keep shipping by pushing to `main`, then read `ci-test`, then grab the APK from the `latest` release.
5. For a new full release, bump `RELEASE_VERSION`, update `RELEASE_NOTES.md`, and push.
6. Don't build an installable APK locally with a different key, or it won't install over the current app.
