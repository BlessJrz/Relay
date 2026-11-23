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
- Keep all tests green (85 at 1.2.0; `updater_test` uses a local fake GitHub): `test/motion_test.dart` drives the animations
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

## Rules learned in the 1.1 bug sweep

- Never hand a Mac URL (`attachmentUrl` has the password in `?guid=`) to another app
  or the browser. Use `openRemoteFile` (`state/media_open.dart`): downloads to
  cache `open/`, then `relay/media` → `openFile` through the FileProvider.
- `ConversationPane._owner`: only the newest pane sets/clears `store.openChat`
  (fold/unfold keeps two alive for a moment). Mark read only when `store.appActive`.
- Reactions: one per person, newest wins. "New messages" line is frozen once the chat
  has loaded (`_unreadKey`). Failed/queued messages always show their status.
- Store: `connect()` is single-flight; failures keep a 45 s ping running and a later
  successful ping does the full connect. A socket drop sets `liveLinkDown`, not
  offline. Queued sends check the Mac (`_findSent`) before re-sending.
- Don't edit files with PowerShell `Set-Content`/`-replace`: it garbles UTF-8
  (… ’ “ —). Use the Edit tool.

## Rules learned in 1.1.2

- Never unfocus the composer while the app is pausing (`didChangeAppLifecycleState`):
  Android's keyboard gets stuck half open on return. Only on resume, and only when
  the lock screen is about to cover the chat. If the keyboard was up on the way out
  (sampled at `inactive`), resume re-shows it (`TextInput.show`): Android closes it
  behind Relay's back and Flutter keeps its space (black gap) until a keyboard
  animation finishes. The real fix is native: `MainActivity.resyncKeyboardInsets()`
  (onResume + window focus) finds the `FlutterView` and calls its
  `onApplyWindowInsets(rootWindowInsets)` directly, past the engine's
  `ImeSyncDeferringInsetsCallback`, which otherwise swallows every insets update
  while it waits for an IME animation's `onEnd` that never comes.
  **1.1.6:** calling it once on resume wasn't enough (the window's insets were still
  stale then, and later real updates were swallowed again). `MainActivity` now
  replaces Flutter's helper on the FlutterView with its own `KeyboardInsetsSync`
  (same per-frame IME animation, `setWindowInsetsAnimationCallback` +
  `setOnApplyWindowInsetsListener`): it stops waiting after the animation's duration
  + 400 ms, is reset on pause / focus loss, and re-applies `rootWindowInsets` at 0,
  250, 700 and 1500 ms after resume/focus. Installed lazily from
  `resyncKeyboardInsets()` (API 30+; older phones keep the 1.1.4 path).
- `Arrive` clips only while growing (`ClipRect` with `Clip.none` after): a plain
  `SizeTransition` clips forever and cut the reaction pill off. The pill sits inside
  the row (padding 16, `top: 0`), never above it. `motion_test` checks both.
- Anything drawn over a chat background photo goes through `_readable()` /
  `_soft()` (times, "Delivered", names, "New messages", "Replying to…", empty text).
- The Mac-offline notification: `_armOfflineAlert()` fires only when `appActive`,
  after a fresh `_measure()`. Pings (`_pingTick`) are skipped in the background unless
  something is queued: a sleeping phone can't reach anything, that's not the Mac.
- `ui.openChat.show(g)` (not `.value = g`) for every "open this chat" path: it also
  works for the chat that's already the value (hidden behind Settings or after a fold).
- `connect()` runs `_ensureStarted()` (caches, queue, network watcher), so tests that
  call `connect()` need `TestWidgetsFlutterBinding.ensureInitialized()` and
  `HttpOverrides.global = null` (see `sync_test`).
- `_pollNow(announce: false)` on resume: push already notified; don't banner it again.

## Sending big videos (1.1.5)

- `state/video_shrink.dart`: videos over 25 MB are re-encoded before upload by
  `MainActivity.shrinkVideo` (MethodChannel `relay/media` → `shrinkVideo`, Media3
  Transformer: H.264 + AAC, short side ≤ 1080, bitrate sized for ~60 MB, 1.2–8 Mbps).
  Cloudflare tunnels reject request bodies over 100 MB (413). If shrinking fails the
  original is sent. Media3 artifacts in `android/app/build.gradle.kts` must match the
  media3 version `video_player_android` uses (1.9.2 at the time).
- `Store.sendFile` returns the failure reason (413/408 mapped to plain words) and the
  chat shows it in a toast; `store.preparing` drives "Making the video smaller to send…".
  Upload timeout is 10 minutes. Since 1.2 the work is in `_deliverFile` (shared with
  `sendBundle`, which returns the same kind of reason for the whole send).

## Photos with a message, and the 1.2 smoothness pass

- **Attachment tray:** nothing is sent the moment it's picked. Gallery (multi-pick),
  the camera sheet ("Add N" / "Use this"), "Record a video" and pictures/GIFs inserted
  from the keyboard (`SkField.onInsertContent`) all go through `_attach` into
  `_ConversationPaneState._trays` (static, per chat, so it survives fold/unfold and
  switching chats). `_AttachTray` draws it; `_compose` (0 nothing / 1 files / 2 text)
  drives the send button. Send → `Store.sendBundle(chat, files, text)`: every bubble
  shows at once, files upload in order, the text goes last. After each upload
  `_restamp` moves what's still waiting to after the Mac's copy (the Mac's time is
  later than the phone's placeholder times, so without it bubbles swap places
  mid-send). The waiting caption is in `_heldCaptions` (prefs `held_captions`):
  `_claimTemp` skips it, and if Relay dies mid-upload it comes back as that chat's
  draft. If the Mac stops answering, the remaining files are marked failed at once
  and the text goes to the normal queue. A reply applies to the text only; photos
  sent alone leave the "Replying to…" strip up. The tray belongs to the chat, not
  the pane: `_attach(guid, …)` writes even if the pane was swapped by a fold while
  the picker was open, and `_trayRev` tells whichever pane is showing. Voice
  messages and "Send to…" from other apps still send at once. Send later is
  text-only. `test/attach_test.dart` + five `sync_test` cases cover it;
  `ConversationPane.debugAttach` is the test hook.
- **Nothing may change height after it's built** (the list is `reverse: true`, so a
  row that grows below the screen shoves everything you're reading):
  `LinkPreviews.peek` (previews saved in prefs `link_previews`, loaded in `main`),
  `VideoThumbs.peek` / `warm()`, `VideoTile(ready:, aspectHint:)`, `PhotoShapes` (the
  tray's small decode teaches the sent bubble its shape). New async content: give it
  its final size from a cache or reserve the box.
- **Mac photos go through `MacPhoto`** (`state/photo_cache.dart`), never
  `NetworkImage`: downloaded once to cache `photos/` (500 MB cap), keyed by attachment
  guid, wrapped in `ResizeImage`. The image cache is raised to 256 MB in `main`.
- **Rebuild rules added:** the jump-to-latest button listens to `_jump` itself (no
  `setState` in `_onScroll`); `_sig()` counts loading/error only while the chat is
  empty; folded, the Shell does not listen to `ui.openChat`; drafts, chat titles /
  initials (`Expando`, reset by `contactsRev`) and text styles (`memoFont`) are cached;
  replies over 100k chars are decoded with `compute`.
- **Keyboard:** `main.dart` zeroes `viewInsets` below its `Padding` and leaves
  `padding` alone. Android already reduces `padding.bottom` by what the keyboard
  covers; subtracting again made the composer dip (`keyboard_test` checks this).
- **Small motion pieces:** `_Reveal` (strip that opens/closes keeping its contents on
  the way out) for the reply strip and tray; `Toaster` leaves with an animation and
  `Toaster.dismiss(tag)` drops a chat's banner when that chat opens; `Pressable`
  holds its pressed look 90 ms after a quick tap; `Stagger(enabled:)` only while a
  list is first appearing; video tiles use a plain disc, not a `BackdropFilter`.
- **This checkout can be behind GitHub.** Other sessions ship releases too (1.1.5 to
  1.1.7 landed while 1.2.0 was being written). `git fetch` and look at
  `origin/main` before starting work and again before pushing; rebase, don't force.

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
