# Install the alpha with SideStore

Alpha builds are not signed by Apple. SideStore signs the app with your free Apple ID on your iPhone, so no paid Apple Developer account is needed.

## One-time setup

1. Install SideStore on the iPhone. Follow the setup guide at https://sidestore.io for your iOS version. The guide includes a one-time step that uses a computer.
2. Make sure the iPhone can reach SideStore's refresh helper on your Wi-Fi network, or open SideStore to refresh the app manually.

## Install a build

1. On the iPhone, open https://github.com/simplyjaytea/simplyHermes/releases and pick the newest release marked **Pre-release**.
2. Download `simplyHermes-<version>.ipa`. Safari saves it to Files.
3. Open SideStore, go to **My Apps**, tap **+**, and choose the `.ipa` from Files. You can also share the file to SideStore.
4. SideStore signs the app with your Apple ID and installs it.
5. If iOS asks you to trust the developer, open Settings > General > VPN & Device Management and trust your Apple ID.

To update, install the newer `.ipa` the same way.

## Keep it working

- A free Apple ID signs an app for 7 days. SideStore refreshes it in the background when the iPhone reaches the refresh helper, or when you open SideStore. Refresh before it expires, or the app stops opening.
- A free Apple ID can have only a few sideloaded apps active at once. Remove apps you do not use.

## Limits in this alpha

- Free signing may drop the App Group and the shared Keychain. Widgets, the Share extension and Spotlight depend on them. The app is meant to work without them. Check the first install as described in `docs/sideloading.md`.
- There are no push notifications. Live Activities run only while the app runs.
- The open issues for this build are in `docs/alpha-known-issues.md`. Report what you find through the app's bug report screen.
