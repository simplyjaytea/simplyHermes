# Installing on the iPhone (no Apple Developer account)

CI builds an unsigned `simplyHermes-unsigned.ipa` on every run (artifact `simplyHermes-unsigned-ipa`).
SideStore re-signs it with a free Apple ID and installs it on the iPhone.

1. Open the latest green CI run on GitHub, Artifacts, download `simplyHermes-unsigned-ipa`, unzip it.
2. Open the `.ipa` in SideStore (Files app, or share it to SideStore) and install.
3. Free-account signing expires every 7 days; SideStore refreshes it in the background while the iPhone is on the same network as its refresh helper, or when opened.

## Free-account limits to design around

- At most 3 sideloaded apps and 10 new App IDs per week per Apple ID.
- No paid capabilities: push notifications, iCloud, Associated Domains. App Groups and a shared Keychain group are not guaranteed: SideStore rewrites the bundle id and may drop these entitlements, so the app must work without them (fall back to its own Keychain and app container).
- Background modes that need special entitlements are not available.

SideStore setup on a Linux machine is a one-time manual step for JT and is not done by CI.

## Widgets and Live Activity (WP-63/64)

The app ships two extensions: `simplyHermesWidgets` (Bots widget, Lock Screen widgets, Control Center controls, Live Activity) and `simplyHermesShare` (the share sheet). A SideStore install uses 3 App IDs. There is no third extension.

Check once on the first sideloaded build:

1. Add the Bots widget to the Home Screen. If it shows bots and "Updated … ago", the App Group works. If it shows "Open simplyHermes to see your bots" even after opening the app, SideStore dropped the App Group: widgets stay in that state, while Live Activity buttons still work (they run in the app through App Intents).
2. Start a chat turn and lock the phone: the Live Activity shows Stop; with an approval waiting, Deny and Approve. Approve asks for Face ID.
3. Settings, turn on Keep bots live, start a long turn, leave the app: the Live Activity keeps updating. With it off, the activity shows "Open simplyHermes to refresh" about 90 seconds after the app is suspended.

## Siri, controls, share sheet and Spotlight (WP-63)

The App Intents run in the app, and the controls and the Share extension never open a connection to a server: they leave a request for the app (in memory, or in a file in the App Group) and the app carries it out. CI cannot press the Action button, open Control Center or share from another app, so check these once on the first sideloaded build:

1. Siri and Shortcuts: say "Ask simplyHermes" and answer what Siri asks. The message goes to the chat you used last and the app opens. "Ask <bot> in simplyHermes" picks a bot; bot names appear after the app has connected once. "Run routine" is not offered because routines (WP-44) are not built.
2. Action button: Settings, Action Button, Shortcut, choose simplyHermes and then Open Quick Entry. Press the button: simplyHermes opens with a box to type in. A request that waits for more than two minutes is dropped, so the box never appears by surprise later.
3. Control Center: edit the controls and add Ask Hermes, Stop all turns and Keep bots live. Ask Hermes opens the same box. Keep bots live follows the switch in Settings. If SideStore dropped the App Group, Keep bots live reads "Unavailable" and Stop all turns cannot show a count; Ask Hermes still works.
4. Share sheet: share text, a web link, a photo or a file from another app and choose simplyHermes. Pick New chat or a recent chat and tap Send. The sheet closes, simplyHermes opens and sends the message. iOS can refuse to let a share sheet open an app. If simplyHermes does not open, the message waits and is sent the next time you open the app. Photos are shrunk to 2048 pixels. A file can be 20 MB, and a share can hold 25 MB in all. Without the App Group the sheet says that sharing is not available.
5. Spotlight: search for a chat title or a bot name. Only titles and names are indexed, never message text. A chat result opens that chat; a bot result starts a new chat as that bot. Results can take a minute to appear after the first launch.
