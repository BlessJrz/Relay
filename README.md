# Relay

An Android app for your iMessage chats. Your Mac runs the free **BlueBubbles Server**, which sends and receives iMessages, and Relay is the app on your Galaxy Z Fold7 that talks to it.

- **Four designs, switchable any time:** Pinned (big title + pinned chats), Material (one rounded sheet + Start chat), Folders (folder tabs and rail) and Modern Minimal. Each has light, dark and auto modes, its own accent colours, and its own animations. Change them in **Settings → Design**.
- **Folded and unfolded layouts:**
  - On the cover screen you get one pane with a floating nav bar.
  - Unfolded, you get a side rail with the chat list and the open conversation side by side.
- **Built-in setup guide:** a step-by-step Mac checklist, QR pairing, and a connection test.
- **In-app tips:** a short spotlight tour that you can replay from Settings.
- **Messaging:**
  - live messages over a socket connection
  - push notifications through your own Firebase project
  - photos and files
  - reactions, replies and typing indicators (these need the Private API on the Mac)

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
