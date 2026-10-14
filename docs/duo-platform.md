# iPhone Duo platform notes (WP-02)

What the app knows about the iPhone Duo and how it reads the fold. Facts marked **SDK** were read from the iOS 27.1 SDK headers on the CI runner (Xcode 27.1 Release Candidate). Facts marked **Press** come from secondary sources and have not been checked against Apple documentation. Facts marked **Open** need a real device or the Duo simulator.

## Posture API

- **SDK** `UIHingeInteraction` (UIKit, iOS 27.1). Add it to a view with `view.addInteraction(UIHingeInteraction { interaction, update in ... })`. The handler runs with the initial state and again on every change. `update.hinge` is `nil` when the view is not in a hierarchy that provides hinge updates (for example on a device without a hinge).
- **SDK** `UIHinge` has `status` and `angle`. `angle` is in radians. The system says angle rate and precision are policy and may change, so use `status` where it is enough.
- **SDK** `UIHinge.Status`: `unknown` (0), `closed` (1), `partiallyOpen` (2), `fullyOpen` (3).
- **SDK** SwiftUI has no hinge symbol in the Swift interface of the 27.1 simulator SDK (searched for `onHingeChange`, `Hinge`, `ReservedRegion`). The app therefore reads the hinge through UIKit inside a hidden `UIViewRepresentable`. **Press** reports an `onHingeChange` modifier; it did not show up in the SDK, so do not rely on it.
- The system reports no named "half-fold" or "tent". `PosturePolicy` derives them: `partiallyOpen` is half-fold, and `partiallyOpen` at or below 75° is tent. **Open**: the 75° tent threshold is a guess. Use the debug view on a real Duo to calibrate it (`PosturePolicy.tentMaxDegrees`). Laptop-style half-fold sits near 90° to 120°, so a tent that is opened wider than the threshold will show as half-fold.
- Without a hinge (regular iPhones, the iOS 27.0 simulator) the posture is `flat` and the shell lays out from the size class and screen size alone.

## Reserved regions

- **SDK** `UIView.reservedRegions(of:)` and `UIView.reservedRegions(of:options:)` (iOS 27.1) return `UIViewReservedRegion` objects with `identifier`, `kind`, `frame` (in the view's coordinate space, including margins), `margins` and `isActive`. Kinds: occlusion (an element covers the area, such as the inner camera) and division (the fold, where an element should split in two).
- Both are marked `NS_REFINED_FOR_SWIFT`, so the Swift names are not guessable. The debug view reads them through the Objective-C runtime (`reservedRegionsOfKind:options:`) and prints frame and active state. Replace this with the typed API once the Swift names are confirmed.

## Layout containers

- **SDK** `UIArrangementViewController` with `UISplitArrangement` and `UIOverlayArrangement` place views around the fold (split or overlay). Not used yet: the shell uses `NavigationSplitView` and its own half-fold layout. Revisit when WP-21 needs the transcript to sit exactly on one half.
- **Press** the inner display has regular width and regular height size classes while the device stays an iPhone.

## Screens

| Display | Pixels | Points (estimate) |
| --- | --- | --- |
| Outer | 1398 × 2034 | 466 × 678 |
| Inner, portrait | 1878 × 2670 | 626 × 890 |
| Inner, landscape | 2670 × 1878 | 890 × 626 |

The point sizes are the pixel sizes divided by 3 and match `DuoPreviewPosture`. **Open**: confirm from the debug view's `size` row on the Duo simulator.

## Simulator

- **SDK** Xcode 27.1 lists a `iPhone Duo` device type (`com.apple.CoreSimulator.SimDeviceType.iPhone-Duo`).
- The macOS runner image currently has only the iOS 27.0 runtime. The CI job tries to download 27.1 and creates a Duo device on the newest runtime. On 27.0 the hinge APIs are absent, so the app runs with `flat` posture. The app guards all hinge code with `#available(iOS 27.1, *)`.
- **Open** whether the Duo simulator can script postures. Xcode 27.1's Device Hub reportedly can open, close, rotate and partly fold. CI cannot drive it, so fold/unfold behavior is covered by the debug layout menu test in WP-21 and by manual checks.
- **Open** whether the simulator exposes the Apple system language model (Foundation Models). Checked in WP-61.

## Debug view

Launch with `-HermesScreen postureDebug` to open `PostureDebugView`. Rows (accessibility ids `posture.<row>`): `posture`, `hinge.status`, `hinge.angle`, `posture.source`, `size`, `sizeClass.horizontal`, `sizeClass.vertical`, `orientation`, `safeArea`, `regions.count`, then one line per reserved region. `-HermesPosture flat|halfFolded|tent` forces a posture.

CI runs `PostureDebugUITests` (labels exist and print) and uploads `posture-debug.png` with the simulator screenshots.

## Manual check (JT, sideloaded build)

Open the app with the launch argument (or ask for a Settings entry) and fold through every posture. Write down for each: hinge status, angle, size, size classes and region count. Send them back to calibrate `tentMaxDegrees` and confirm the point sizes.

## Not decided here

- Scene state transfer between displays, Split View two-window behavior and the keyboard in half-fold need a real device. They are listed for the first device test.
