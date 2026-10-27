# Relay

An Android app for your iMessage chats. Your Mac runs the free **BlueBubbles Server**, which sends and receives iMessages, and Relay is the app on your Galaxy Z Fold7 that talks to it.

- **Four designs, switchable any time:** Pinned (big title + pinned chats), Material (one rounded sheet + Start chat), Folders (folder tabs and rail) and Modern Minimal. Each has light, dark and auto modes, its own accent colours, and its own animations. Change them in **Settings → Design**.
- **Folded and unfolded layouts:** one pane on the cover screen; list and conversation side by side when unfolded, edge to edge.
- **Built-in setup guide:** a step-by-step Mac checklist, QR pairing, and a connection test, plus a replayable tips tour.
- **Messaging:**
  - live messages over a socket connection, push notifications through your own Firebase project
  - photos, videos (with thumbnails, played inside Relay), voice messages and files; save any photo or video to your phone
  - swipe a message to reply, double-tap to heart it, reactions and typing (Private API)
  - edit and unsend your own messages (Private API, macOS 13+), and **send later** (hold the send button)
  - a "New messages" line and a jump-to-latest button
  - drafts are kept per chat; anything you send while the Mac is unreachable waits and goes out when it's back
- **Notifications:** reply or mark read right from the notification (works from a watch too); mute any chat; an alert if the Mac stops answering.
- **Chats:** pin, mute, mark read/unread (swipe or long-press); a Photos, videos & links page for every chat.
- **Privacy:** optional fingerprint / PIN lock.
- **Also:** share photos and text to Relay from other apps; an optional NAS archive (`tools/archive`).

## Build the app (Windows)

1. Double-click **`Build Relay.bat`**. The script:
   - installs anything that's missing (Java 17, the Android SDK, Flutter),
   - builds the app,
   - saves it as **`Relay.apk`** in this folder.

   The first run downloads about 2 GB and takes 15–30 minutes. Later builds take about 2 minutes.
2. Install the app on your phone. Use either option:
   - **USB:** turn on Developer options and USB debugging on the phone, plug it in, and run the script again. It installs the app automatically.
   - **Copy the file:** copy `Relay.apk` to the phone (USB, Google Drive or Quick Share), open it, and allow "Install unknown apps" when asked.

If anything fails, the full output is in `build-log.txt`.

## First launch

The app walks you through everything:

1. **Set up your Mac.** This is a checklist. Tap any step for detailed instructions.
2. **Connect.** Scan the QR code from BlueBubbles Server, or type the server URL and password.
3. **Test & sync.** The app checks that the Mac is reachable, the password is right, iMessage works, notifications are on, and your chats have synced.

## Notes

- **Package name:** the app uses the package name `com.bluebubbles.messaging`. Push notifications need this, because the server's Firebase project registers that name. The downside is that the official BlueBubbles app can't be installed at the same time as Relay.
- **Server URL changes:** the Cloudflare URL changes every time the Mac restarts the server. If notifications (Firebase) are set up, Relay finds the new URL by itself.
- **Code layout:** all visuals live in `lib/skins/`, one file per design. Screens never hard-code a look; they ask the current design how to draw things.
