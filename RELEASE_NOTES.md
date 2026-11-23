## Relay 1.2.0

Your iMessage chats on the Galaxy Z Fold7, through BlueBubbles Server on your Mac.

**Install:** download `Relay-1.2.0.apk` below and open it on your phone, or use **Settings → Check for updates** inside Relay. It installs over any earlier build and keeps your chats and settings.

### New in 1.2
- **Photos with a message:** whatever you pick or shoot now waits in a small tray above the text box. Add a message (or more photos), then send it all with one tap: the photos go first, your message right after, like on an iPhone. Tap the small x on a picture to take it off. The tray is kept if you fold, unfold or switch chats.
- **Several at once, and from the keyboard:** everything you tick in the photo picker goes into the tray in the order you picked it, and so do GIFs, stickers and pictures from your keyboard.
- **Photos stay on your phone:** a photo from your Mac is downloaded once. After that it shows straight away when you scroll back or open Relay again, instead of loading from the Mac each time. Opening a photo full screen shows it at once and sharpens it, with no black screen first.
- **Message times:** hold a message to see when it was sent, delivered and read.
- **A banner gets out of the way** when you open the chat it's about, and banners now slide away instead of vanishing.

### Smoother in 1.2
- The chat no longer jumps when a link preview or video appears: they're drawn at their final size from the start (previews are remembered between launches).
- A photo you send keeps its real shape from the first moment instead of starting square and snapping.
- The text box no longer dips and bounces when the keyboard opens or closes.
- Opening and closing a chat starts cleanly: the list behind it and the chat itself are no longer redrawn in the first frames of the animation.
- Scrolling a long chat past the "jump to latest" point no longer hitches, and video tiles scroll more easily.
- The top chats no longer fade in again every time you scroll back up to them.
- Buttons and rows light up on a quick tap (before, only if you held them).
- "Replying to…" and the photo tray open and close smoothly instead of popping.
- Big replies from your Mac (chat pages, contact photos) are read in the background, and text styles, chat titles and drafts are worked out once instead of on every redraw.
- Flipping the Google-style header back mid-way starts moving at once.

### Earlier fixes

**1.1.7:** pick several photos and videos at once in the photo picker.

**1.1.6:** the black space under the composer after switching apps is fixed properly. Relay now uses its own keyboard tracking instead of the one built into Flutter, and that one can't get stuck waiting for a keyboard that already closed.

**1.1.5:** big videos from your Photos app send now. Relay makes videos over 25 MB smaller on the phone first (the chat shows "Making the video smaller to send…"), so they fit through your Mac's tunnel and upload faster. If a photo or video still can't send, Relay says why, and "Try sending again" sends the same file.

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
