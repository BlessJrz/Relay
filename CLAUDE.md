# Relay — notes for Claude Code

Relay is a custom Android app (Flutter) that lets the owner use iMessage group
chats from a Samsung Galaxy Z Fold7. It talks to **BlueBubbles Server** running
on an old MacBook (broken screen, kept awake, reached through a Cloudflare
tunnel URL). It replaces the official BlueBubbles Android app.

## How it's built and shipped

- No local Flutter is needed: **GitHub Actions builds everything**
  (`.github/workflows/build.yml`, Flutter 3.47.7). Every push to `main`:
  1. runs `flutter analyze` (errors only) and `flutter test --reporter expanded`,
     and pushes the log to the orphan branch `ci-test` (`test.log`);
  2. builds `flutter build apk --release --build-number=<run number>`;
  3. on failure pushes logs to branch `ci-logs`;
  4. publishes the APK as `Relay-<N>.apk` on the rolling prerelease
     **`latest`**: https://github.com/BlessJrz/Relay/releases/tag/latest
- Read results: `gh api repos/BlessJrz/Relay/contents/test.log?ref=ci-test -H "Accept: application/vnd.github.raw"`
- Signing uses the committed shared keystore, so updates install over the top.
  (The PC build path in `tool/setup.ps1` / `Build Relay.bat` uses a different key.)
- Android application id is `com.bluebubbles.messaging` (it must match the
  Firebase Android app set up on the Mac for push). Kotlin sources live under
  `android/app/src/main/kotlin/com/bluebubbles/relay/`.
- Keep all tests green: `test/shell_smoke_test.dart` renders every design ×
  folded (410 dp) / unfolded (880 dp) × light/dark and fails on any build/layout
  error; `keyboard_test`, `store_logic_test` (chat ordering + bubble contrast ≥ 4:1),
  `sync_test` (real HttpServer fake Mac), `links_test`.

## Code map (`lib/`)

- `api/bb_api.dart` — BlueBubbles REST v1 (password in the `guid` query param):
  `/ping`, `/server/info`, `POST /chat/query`, `/chat/:guid/message`,
  `/message/text`, `/message/attachment`, `/attachment/:guid/download`,
  `/message/react`, `/chat/:guid/read` (Private API), `/chat/new`,
  `/contact?extraProperties=avatar`, `/chat/:guid/icon`, `/fcm/client`.
  Socket.IO v4 for live events. Server QR = JSON `[password, url]`.
- `state/store.dart` — chats/messages, socket + polling fallback, unread
  (kept on the phone), connectivity watcher, notification clearing.
- `state/settings.dart` — prefs (password in flutter_secure_storage), design,
  accents, pinned chats.
- `state/avatars.dart` — contact/group/custom photos cached as files.
- `push/push.dart` — FCM + local notifications (background isolate handler).
- `skins/` — `Skin` base (`skin.dart`), `minimal.dart` (Modern Minimal),
  `messengers.dart` (`FlatSkin` + `PinnedSkin`, `MaterialSkin`, `FoldersSkin`).
  `Skin.layout` (`AppLayout.standard|pinned|material|folders`) switches the
  *arrangement*, not just colours.
- `ui/shell.dart` — folded = one pane (+ floating tab bar only for standard);
  unfolded (≥700 dp) = list + conversation side by side (Folders adds a rail).
  Settings/Mac open full screen with Back in the tab-bar-less designs.
- `ui/screens/chat_list.dart` — standard list + `AltChatList` / `AltChatRow`
  (pinned grid, folder tabs, Start chat FAB…).
- `ui/screens/conversation.dart` — per-design headers (Pinned: blurred header
  floating over the list), bubbles, composers; video tiles → `video_view.dart`.
- `ui/kit/` — design-neutral controls that draw through the current skin.
- `android/.../MainActivity.kt` — 120 Hz request + Share-menu receiver
  (MethodChannel `relay/share`).
- `tools/archive/` — Docker/Python job for the owner's UGREEN NAS that writes a
  plain-text log of every conversation.

## Working style the owner likes

- He tests on the phone and sends screenshots; reply short and plain, no jargon.
- After a change: push, wait for CI, then tell him the build number and the
  release link above. Don't claim on-device behaviour you haven't seen.
- Colours he likes: black, red, white, blue. Avoid emoji-as-icons in the UI.

## Open ideas / not done

- Pinned design: make the bottom composer see-through too (offered).
- Reply-from-watch (RemoteInput on notifications) not built.
- Calls / voice messages aren't supported.
