## Relay 1.1.4

Your iMessage chats on the Galaxy Z Fold7, through BlueBubbles Server on your Mac.

**1.1.4:** the black gap under the composer after switching apps with the keyboard open is gone for real. Android now tells Relay the true keyboard state the moment you come back.

**1.1.3:** Relay brings the keyboard back when you return to a chat you left with it open, the way Google Messages does.

**1.1.2**
- Switching to another app with the keyboard open no longer leaves Relay stuck behind a half-open keyboard when you come back.
- Reactions on messages that just arrived show whole instead of being cut off at the top.
- The "New messages" line is readable on any chat background photo.
- "Your Mac isn't answering" only shows while you're using Relay and after a fresh check, so a phone that was asleep no longer blames the Mac.
- Coming back to Relay no longer re-announces messages your phone already notified you about.
- Tapping a notification or banner for the chat you already had selected now shows it (it used to do nothing behind Settings).
- Unfolding no longer closes the camera, a video or the media page you had open.
- A slow send the Mac finished anyway no longer shows twice, and "Try again" won't send a second copy.
- Links still open when the chat redraws while you're pressing one.
- "Replying to…" and the empty-chat text are readable on a background photo.
- Opening two files with the same name (every voice message) opens the right one.
- Relay opens even if the phone's secure storage refuses the saved password; it just asks for it again.

**1.1.1:** your own messages show on the right again (in 1.1.0 they could appear on the left).

**Install:** download `Relay-1.1.4.apk` below and open it on your phone. It installs over any earlier Relay build and keeps your chats and settings. From now on you can also update from inside the app: **Settings → Check for updates**.

### New in 1.1
- **Google Messages look (Material design):** a big "Relay Messages" title that snaps into a slim top bar when you scroll, a darker list with rounded corners, roomier rows with a small iMessage/SMS bubble on each picture, and a rounded highlight when you press a chat. Unfolded, it's the slim bar on the left with the chat beside it.
- **Smoother everywhere:** new messages grow in, typing dots slide in and out, chats glide to the top when a message arrives, and screens slide (iPhone style) or fade quickly (Material, like Google). Fewer redraws, so scrolling stays smooth.
- **Camera with recent photos:** the camera button opens a live camera with your recent photos and videos underneath. Shoot, or pick several and send them in order.
- **Chat backgrounds:** set your own photo behind any chat (Chat details → Chat background). Times, "Delivered" and names sit on a see-through pill so they stay readable.
- **Your own highlight colour:** pick the colour for "Messages", unread badges and unread times (Settings → Highlight colour).
- **Updates inside the app:** Relay checks GitHub for new builds, tells you when one is ready, then downloads and installs it.
- **Links open in their own app:** TikTok, YouTube, Instagram and others open in their apps as a separate window, so Relay stays free to use.
- **Tidier Settings:** all four designs in one row.

### Fixed
- Messages could be sent twice after a network drop; Relay now checks before re-sending.
- Relay now keeps trying to reconnect if the Mac wasn't reachable when it started.
- Messages that arrived while a chat was loading no longer disappear for a moment.
- "Try again" on a failed photo, video or voice message re-sends it instead of deleting it.
- Failed messages keep their "Not delivered" note even after you send more.
- Changing a reaction no longer shows both the old and the new one.
- The "New messages" line no longer jumps to messages that arrive while you're reading.
- Unfolding with a chat open no longer brings notifications for the chat you're reading.
- Files and videos opened in another app are downloaded inside Relay first, so your Mac's password never leaves the app.
- Videos you send play from your phone instead of downloading back from the Mac.
- Camera: flipping cameras, using it with the microphone turned off, and keeping a video if you leave mid-recording.
- Many smaller layout, colour and timing fixes.

### What's in Relay
- **Four designs:** Pinned, Material, Folders and Modern Minimal, each with its own layout, light/dark mode and accent colours, folded or unfolded.
- **Messaging:** swipe to reply, double-tap to heart, edit and unsend, send later (hold the send button), voice messages, photos and videos that play inside Relay, a "New messages" line and a jump-to-latest button.
- **Never lose a message:** drafts are kept per chat, and anything sent while the Mac is unreachable goes out by itself when it's back.
- **Notifications:** reply or mark read from the notification (also from your watch), mute any chat, and a warning if the Mac stops answering.
- **Chats:** pin, mute and mark read or unread by swiping or long-pressing; a Photos, videos & links page per chat; save any photo or video.
- **More:** fingerprint lock, link previews, sharing to Relay from other apps, and an optional NAS archive (`tools/archive`).

Some features need the **Private API** on your Mac (Settings → Mac relay → Private API): reactions, replies, editing, unsending and read receipts.
