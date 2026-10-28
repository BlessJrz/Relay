# Relay — notes for Claude Code

**Full project report (architecture, features, API, history, gotchas): `docs/REPORT.md`. Read it first.**

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
- **Full releases:** bump `RELEASE_VERSION` (and update `RELEASE_NOTES.md`) on main;
  CI then publishes `v<version>` with `Relay-<version>.apk` as the Latest release.
  (This session can't push tags or create releases directly; CI does it.)
- Read results: `gh api repos/BlessJrz/Relay/contents/test.log?ref=ci-test -H "Accept: application/vnd.github.raw"`
- Signing uses the committed shared keystore, so updates install over the top.
  (The PC build path in `tool/setup.ps1` / `Build Relay.bat` uses a different key.)
- Android application id is `com.bluebubbles.messaging` (it must match the
  Firebase Android app set up on the Mac for push). Kotlin sources live under
  `android/app/src/main/kotlin/com/bluebubbles/relay/`.
- Keep all tests green (60 at build 56; `updater_test` uses a local fake GitHub): `test/motion_test.dart` drives the animations
  (new messages growing in, typing dots, chats sliding to the top) in every design and
  both fold states; `test/home_header_test.dart` scrolls the home list (Material's big
  title must snap back open) and opens a chat with a background photo; `camera_sheet_test`; `test/shell_smoke_test.dart` renders every design ×
  folded (410 dp) / unfolded (880 dp) × light/dark and fails on any build/layout
  error; `keyboard_test`, `store_logic_test` (chat ordering + bubble contrast ≥ 4:1),
  `sync_test` (real HttpServer fake Mac, offline queue), `links_test`, `features_test`.
- Locally (optional): install Flutter 3.47.7 + Java 17 and run `flutter analyze` and
  `flutter test` before pushing. Don't sideload a locally built APK: it's signed with a
  different key and won't install over the CI build.

## Code map (`lib/`)

- `api/bb_api.dart` — BlueBubbles REST v1 (password in the `guid` query param):
  `/ping`, `/server/info`, `POST /chat/query`, `/chat/:guid/message`,
  `/message/text`, `/message/attachment`, `/attachment/:guid/download`,
  `/message/react`, `/message/:guid/edit`, `/message/:guid/unsend`, `/message/schedule`,
  `/chat/:guid/read` (Private API), `/chat/new`,
  `/contact?extraProperties=avatar`, `/chat/:guid/icon`, `/fcm/client`.
  `api/socket.dart`: Socket.IO v4 for live events. Server QR = JSON `[password, url]`.
- `state/store.dart` — chats/messages, socket + polling fallback, unread
  (kept on the phone), offline send queue, Mac-offline alert, edit/unsend/schedule,
  in-app banners stream.
- `state/settings.dart` — prefs (password in flutter_secure_storage), design,
  accents, pins, mutes, drafts (own `drafts` notifier — never notify Settings for
  drafts), app lock, toggles.
- `state/link_preview.dart` — YouTube (oEmbed + i.ytimg thumbnail), oEmbed sites,
  then Open Graph (bot user agent first). `state/video_thumbs.dart`, `media_save.dart`,
  `schedule.dart`.
- `state/avatars.dart` — contact/group/custom photos cached as files.
- `push/push.dart` — FCM + local notifications. Background isolate handler
  (`relayBackgroundPush`), Reply/Mark read actions (forwarded to the live app via
  IsolateNameServer port `relay_notification_actions`), `showWhileOpen` for
  heads-up notifications about other chats while Relay is open.
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
- `android/.../MainActivity.kt` — FlutterFragmentActivity (for local_auth), 120 Hz
  request, Share-menu receiver (MethodChannel `relay/share`), video frame grab
  (MethodChannel `relay/media` → `videoThumb`, local file path only).
- `tool/icon/` — app icon + notification icon (`ic_stat_relay`) generator.
- `tools/archive/` — Docker/Python job for the owner's UGREEN NAS that writes a
  plain-text log of every conversation.

## Smoothness rules (build 52)

- `ConversationPane` listens to the store itself and redraws only when its own
  fingerprint (`_sig`) changes; typing and the recording timer use their own
  `ValueNotifier`s. Don't wrap it in a `ListenableBuilder(store)` again.
- `Shell` doesn't listen to the store (only the nav badge does) and reads the
  screen width with `MediaQuery.sizeOf`, not `LayoutBuilder` (the keyboard
  shrinks the constraints every frame).
- Motion pieces live in `ui/kit/motion.dart`: `Arrive` (new message grows in),
  `Glide` (list rows slide to a new index), `SlideRoute` (iPhone-style push with
  the screen below drifting left), `Haptics` (tap / confirm / hold).
- Message list items are keyed `m:<tempGuid ?? guid>` with
  `findChildIndexCallback`, so state stays with its message when new ones arrive.
- Wrappers that animate must keep the same widget tree when idle (don't swap
  `child` for `Transform(child)`), or the row underneath gets rebuilt.

## Google Messages look (build 54, Material design)

- Home: `_BigTitleHeader` (chat_list.dart) sits above the list (not in the scroll
  view) and has two states only, like Google: big centred "Relay Messages" or a small
  title on the 64 dp bar. A user swipe up (list offset > 0) snaps it small in 600 ms (owner's pick)
  (`_head` controller); a swipe down at the top snaps it big. Unfolded and while
  searching it's always small. The rounded top of the list (`capH`) is drawn in the
  header. Folded: header `p.surface2` over a `p.surface` list.
- Highlight colour (Settings → Highlight colour; prefs `highlight_color`): goes into
  `Palette.highlight` in `paletteFor`, and `Skin.badge` uses it, so "Messages",
  unread badges/times and drafts all follow it. Null = the design's own red.
- Rows: 80 dp, regular-weight names (bold when unread), a small bubble on the picture
  (blue iMessage / green SMS), a rounded pill highlight on press. FAB: icon-only rounded
  square in `skin.fab` / `skin.onFab` (deep blue at night).
- Chats open/close with a 190 ms fade + small nudge (`SlideRoute._fadeIn`), not the
  iPhone slide; the other designs keep the slide.
- Chat backgrounds: Chat details → "Chat background" (`Avatars.pickBackgroundFor`, files
  `w_*.jpg` in the avatars folder, prefs key `chat_backgrounds`). `_ChatBackground` in
  conversation.dart draws it at full screen height from the top (so it doesn't zoom when
  the keyboard opens), fades it in, and dims it a little. Works in every design.

## In-app updates (build 56)

- Settings → top row "Check for updates" (`state/updater.dart`): reads the `latest`
  release from the GitHub API, picks the highest `Relay-<N>.apk`, compares N with the
  app's versionCode (MethodChannel `relay/media` → `appBuild`; CI sets it from the run
  number). Downloads to cache `updates/` and calls `installApk`, which opens Android's
  installer through a FileProvider (`${applicationId}.relay.files`,
  `res/xml/relay_files.xml`); needs `REQUEST_INSTALL_PACKAGES`. Same keystore, so it
  installs over the top. The Shell also checks quietly on launch (every 6 h at most)
  and shows a tap-to-install banner once per build. Keep the APK name `Relay-<N>.apk`.
- Links open via `relay/media` → `openUrl` (ACTION_VIEW + NEW_TASK, preferring the
  app over the browser), so TikTok etc. open as their own app, not stacked in Relay.

## Working style the owner likes

- He tests on the phone and sends screenshots; reply short and plain, no jargon.
- After a change: push, wait for CI, then tell him the build number and the
  release link above. Don't claim on-device behaviour you haven't seen.
- Colours he likes: black, red, white, blue. Avoid emoji-as-icons in the UI.

## Open ideas / not done

- Reply-from-watch works through the notification's Reply action (no Wear OS app).
- Calls aren't supported (BlueBubbles can't place FaceTime calls).
- Voice messages are sent as .m4a audio files, so iPhones show them as an audio
  attachment rather than a native voice-memo bubble.
