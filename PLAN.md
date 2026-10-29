# WiFi Mapper — iOS app plan

## Context
The repo `ravitej-sistla/wifi-mapper` is empty (branch `claude/dreamy-ramanujan-qaea3u`, no commits). The user wants an iOS app that walks the property with an iPhone or iPad on their mesh Wi-Fi, samples signal strength together with precise GPS, and builds a heatmap. Maps can be saved, updated or versioned, and listed by last-updated time. A saved map can be reloaded to show your live position on it. The home screen always shows the live strength of the current Wi-Fi ("Connect to Wi-Fi" when you're not on it), and you can check the strength at your current spot on a saved map without recording. No logins. Cellular signal is out of scope for now.

Decisions from the user:
- **Signal measurement:** build both **Hybrid** (NEHotspotNetwork `signalStrength` blended with link quality) and **Link-quality only**, selectable in the app, with a way to compare them. We'll pick the default later based on real-world results.
- **Positioning:** GPS (Core Location, best accuracy) with an accuracy filter.
- **Build:** Mac with Xcode and a paid developer account. Target iOS 17+, SwiftUI + SwiftData. This environment is Linux, so I'll ship Swift sources plus an XcodeGen `project.yml`. I can't compile it here.

## Key design: store raw metrics, score at render time
Each sample stores **all raw measurements** (apple signalStrength, RTT, jitter, packet loss, throughput, BSSID). The 0–100 score is computed when the map is drawn, by a `ScoringMode` (`.hybrid` / `.linkQuality`). So one walk can be viewed under either mode, and a side-by-side comparison is possible without walking twice. That answers "which performs better" directly.

## Project layout
```
project.yml                      # XcodeGen: iOS 17, bundle id, entitlements, Info.plist keys
README.md                        # build steps (brew install xcodegen; xcodegen; set Team), field-test guide
WiFiMapper/
  WiFiMapperApp.swift            # @main, SwiftData ModelContainer, inject services
  WiFiMapper.entitlements        # com.apple.developer.networking.wifi-info
  Models/
    WiFiMap.swift                # @Model: id, name, createdAt, updatedAt, version, parentMapID, samples (cascade)
    SignalSample.swift           # @Model: lat, lon, hAccuracy, timestamp, ssid, bssid, appleStrength?, rttMs?, jitterMs?, lossPct?, throughputMbps?
    ScoringMode.swift            # enum hybrid/linkQuality + score(sample)->Double? ; default stored in @AppStorage
  Services/
    LocationService.swift        # CLLocationManager, kCLLocationAccuracyBest, auth, live location stream, accuracy filter (default ≤ 10 m, configurable)
    WiFiInfoService.swift        # NEHotspotNetwork.fetchCurrent → ssid, bssid, signalStrength; NWPathMonitor → onWiFi / onCellular / offline
    LinkQualityProbe.swift       # NWConnection TCP-handshake RTT to the gateway (×5 → median RTT, jitter, loss); optional small throughput fetch
    GatewayResolver.swift        # default gateway via sysctl route table, falling back to en0 subnet .1; user override in Settings
    SignalMonitor.swift          # @Observable; combines the above into a live reading every ~2 s (used by Home + Recording)
    RecordingSession.swift       # sample when moved ≥ 2 m or every 3 s, after the accuracy filter; append to a WiFiMap
  Heatmap/
    HeatmapOverlay.swift         # MKOverlay covering the sample bounds (+ padding)
    HeatmapRenderer.swift        # MKOverlayRenderer: IDW interpolation on a grid (~1 m cells), red→yellow→green ramp, alpha fades with distance from samples
    HeatmapMapView.swift         # UIViewRepresentable MKMapView (satellite hybrid), overlay, user dot, optional sample dots
    Interpolator.swift           # IDW value at a coordinate (shared by renderer + "value here")
  Views/
    HomeView.swift               # app info card, LIVE strength gauge (or "Connect to Wi-Fi"), SSID/mesh node BSSID, buttons: New Recording, Check Here; history list
    LiveSignalCard.swift         # gauge showing the score for the selected mode, plus raw values
    HistoryListView.swift        # @Query sorted by updatedAt desc; swipe delete, rename
    RecordingView.swift          # live map building as you walk, sample count, current reading, Stop → Save (new map) / append to existing
    MapDetailView.swift          # reload a map: heatmap + live position + "here: 72 (live: 65)"; actions: Continue/Update, Save as New Version, mode picker
    CheckHereView.swift          # without recording: find saved maps whose bounds contain the current location (most recent first), show interpolated value at your spot vs live reading
    CompareModesView.swift       # same map rendered under both modes side by side + stats (score spread, correlation of score vs. RTT/throughput)
    SettingsView.swift           # default scoring mode, accuracy threshold, gateway override, throughput probe on/off + URL
```

## Behavior details
- **Live signal (Home):** `NWPathMonitor` decides the state. Wi-Fi → show score + SSID + BSSID (which mesh node). Cellular-only or offline → "Not on Wi-Fi. Connect to Wi-Fi to see signal strength." (no cellular metrics).
- **Hybrid score:** `0.5 * appleStrength*100 + 0.5 * linkScore`. If `appleStrength` is nil or 0, it falls back to `linkScore` and the UI flags "Apple strength unavailable".
- **Link score:** RTT mapped (≤5 ms → 100, ≥150 ms → 0), with penalties for jitter and loss. If enabled, throughput is blended in (log scale). Probes are lightweight: about 5 TCP handshakes to the gateway on port 80, each with a 1 s timeout. A refused connection still yields a valid RTT.
- **Update vs. new version:** "Update" appends new samples to the same map and bumps `updatedAt`. "Save as New Version" copies the samples into a new `WiFiMap` (version+1, same parentMapID lineage) and appends new samples there. History sorts by `updatedAt` desc and shows the version badge.
- **Reload + current location:** MapDetailView centers on the map, shows the blue dot, and continuously shows the interpolated value at your location next to the live reading.
- **Permissions/Info.plist:** `NSLocationWhenInUseUsageDescription` (also required for the SSID/BSSID API), `NSLocalNetworkUsageDescription` (gateway probe), and `UIBackgroundModes: location` plus `NSLocationAlwaysAndWhenInUseUsageDescription` so recording keeps going with the screen locked.

## Implementation steps
1. `project.yml`, entitlements, app entry point, SwiftData models, README.
2. Services: Location, WiFiInfo, GatewayResolver, LinkQualityProbe, SignalMonitor.
3. Scoring modes + Interpolator (pure Swift, with unit tests in `WiFiMapperTests/` for scoring and IDW).
4. Heatmap overlay/renderer/map view.
5. Views: Home, History, Recording, MapDetail, CheckHere, CompareModes, Settings.
6. Commit and push to `claude/dreamy-ramanujan-qaea3u` (no PR unless asked).

## Verification
- In this environment: `swiftc -parse` syntax checks of the sources, if a Swift toolchain is available; otherwise careful review. I'll say plainly that the code was not compiled for iOS here.
- On the user's Mac: `brew install xcodegen && xcodegen generate`, open `WiFiMapper.xcodeproj`, set the Team, enable the "Access Wi-Fi Information" capability, then run on a device (the simulator has no real Wi-Fi APIs). Run unit tests with ⌘U.
- Field test: record one walk through the house and yard, open Compare Modes, and check which mode tracks real dead zones better (for example, a slow-streaming spot). Then set that mode as the default in Settings.

## Progress (as of this commit)
Done: all of the files above, plus `Views/Format.swift`, and the `Route`/`Router` navigation in `WiFiMapperApp.swift`.
- Built with Xcode 26.2 for the iOS Simulator, with no errors or warnings. One fix was needed: `NWPath` is ambiguous between Network and NetworkExtension.
- `WiFiMapperTests/`: 18 tests (scoring, IDW, stats) pass on the simulator.
- The app launches on the simulator and shows Home plus the location prompt.

Ads (added after the first build): AdMob native card on Home, full-screen ad after saving a recording, "Remove ads" purchase (StoreKit 2), consent via UMP + ATT. Ads pause during recordings because ad traffic would skew link-quality readings. Checked in the simulator with test ads: the native ad renders and Google's native ad validator reports no issues. The full-screen ad and the purchase flow have not been tried yet.

Not yet verified: anything that needs a real device on real Wi-Fi (SSID/BSSID/signal strength, router probe, GPS recording, background recording). The field test is next.
