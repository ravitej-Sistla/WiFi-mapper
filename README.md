# WiFi Mapper

An iOS app that builds a Wi-Fi heatmap of your property. Walk around with an iPhone or iPad on your Wi-Fi; the app pairs signal readings with precise GPS and paints a red → yellow → green map over satellite imagery. Maps are saved on the device (no account), can be updated or saved as new versions, and can be reopened to see the expected signal where you're standing.

See [PLAN.md](PLAN.md) for the design.

## Build

Requirements: a Mac with Xcode 16 or later, an Apple Developer account, and an iPhone or iPad on iOS 17+.

```sh
brew install xcodegen
xcodegen generate
open WiFiMapper.xcodeproj
```

In Xcode:
1. Select the **WiFiMapper** target → **Signing & Capabilities**, pick your **Team**. You can also set `DEVELOPMENT_TEAM` in `project.yml` so it survives regenerating the project.
2. Check that **Access Wi-Fi Information** is listed. `project.yml` adds it through the entitlements file. Without it iOS won't report the network name, the mesh node (BSSID) or Apple's signal strength.
3. Run on a **real device**. The simulator has no real Wi-Fi APIs.

Run the unit tests with ⌘U, or from the command line:

```sh
xcodebuild test -project WiFiMapper.xcodeproj -scheme WiFiMapper \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
```

Re-run `xcodegen generate` after adding or removing source files.

Debug builds accept two launch arguments for checking the UI in the simulator, which can't take real readings. Set them in Xcode under Product → Scheme → Edit Scheme → Arguments:
- `-demoData` adds a sample "Home & garden" map near Apple Park if the app has no maps yet.
- `-demoScreen map|compare|record|checkHere|settings` opens that screen at launch.

Set the simulator's location to the demo map with `xcrun simctl location booted set 37.3347,-122.0090`.

The app icon is drawn in code by a short CoreGraphics script; `WiFiMapper/Assets.xcassets/AppIcon.appiconset/AppIcon.png` is its 1024 × 1024 output.

## Permissions

- **Location (While Using):** places readings on the map. iOS also requires it to read the Wi-Fi network name. Choose **Precise**.
- **Local Network:** lets the app time connections to your router to measure link quality.
- Recording keeps going with the screen locked (blue location indicator); the app stops measuring in the background otherwise.

## How signal is measured

Each sample stores raw measurements; the 0–100 score is computed when a map is drawn, so every recording can be viewed in either mode:

- **Link quality:** round-trip time of TCP handshakes to your router (5 per reading), with penalties for jitter and lost probes. If throughput is enabled in Settings, download speed is blended in.
- **Hybrid:** the average of Apple's `NEHotspotNetwork.signalStrength` and the link-quality score. iOS often reports 0 for apps that aren't hotspot helpers; then Hybrid falls back to link quality and the app says so.

The router is assumed to be the first address on your Wi-Fi subnet (for example `192.168.4.1`). If yours differs, set it in **Settings → Router address**.

## Field test

1. Pick a default mode in Settings (either is fine to start).
2. Tap **New Recording** and walk slowly through the house and yard. Pause briefly in rooms. The GPS figure must stay under the accuracy limit (10 m by default) for readings to count, so indoor coverage can be patchy.
3. Stop and save, then open the map → **⋯ → Compare scoring modes**.
4. Check which map matches spots you know are bad (for example, where video stalls). Set that mode as the default in Settings.
5. Later, use **⋯ → Continue recording** to fill gaps, or **Record as new version** after moving a mesh node, so you can compare before and after.
