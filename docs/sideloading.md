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

## Downloaded on-device models (WP-65c)

The app asks for the entitlement `com.apple.developer.kernel.increased-memory-limit` so a downloaded model has room to
load. Free-account signing may drop it, the same way it can drop App Groups. Check once on the first sideloaded build:

1. Settings > On-device models: download the smallest model, then choose Use this model.
2. Ask something in offline chat. If the Apple model answers instead, or the app closes during the first answer, iOS
   refused the memory: the entitlement was dropped, or the phone has too little free memory. The app checks
   `os_proc_available_memory()` before it loads a model and falls back to the Apple model, so the feature should degrade
   and not crash. The model list shows a caution on models that may not fit.
3. A download needs the model size (0.8 to 2.3 GB) plus 0.5 GB free on the phone. The files are not backed up, and Delete removes them.

## Widgets and Live Activity (WP-63/64)

The app ships one extension, `simplyHermesWidgets` (Bots widget, Lock Screen widgets, Live Activity), so a SideStore install uses 2 App IDs. The planned Share extension will be the third and last.

Check once on the first sideloaded build:

1. Add the Bots widget to the Home Screen. If it shows bots and "Updated … ago", the App Group works. If it shows "Open simplyHermes to see your bots" even after opening the app, SideStore dropped the App Group: widgets stay in that state, while Live Activity buttons still work (they run in the app through App Intents).
2. Start a chat turn and lock the phone: the Live Activity shows Stop; with an approval waiting, Deny and Approve. Approve asks for Face ID.
3. Settings, turn on Keep bots live, start a long turn, leave the app: the Live Activity keeps updating. With it off, the activity shows "Open simplyHermes to refresh" about 90 seconds after the app is suspended.
