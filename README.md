# Flying Toasters — Multi-Monitor

> macOS screensaver. One shared swarm of After-Dark-style flying toasters
> that crosses every attached display, with a full set of live-preview
> options. Targets macOS 26 (Tahoe).

A substantial extension of [Robert Venturini's FlyingToasters](https://github.com/robertventurini/FlyingToasters)
that turns the saver from a single-display recreation into a true
multi-monitor experience with rich, immediately-applied settings.

![Image of FlyingToasters](https://github.com/robertventurini/FlyingToasters/blob/master/FlyingToasters.gif)

## What this fork adds

### One shared world across every display

In the original, each attached display ran an independent population of
toasters — sprites that exited one monitor never appeared on another.
Here, a process-wide [`ToasterWorld`](Flying%20Toasters/ToasterWorld.m)
singleton owns the entire toaster + cloud population. Each
[`ScreenSaverView`](Flying%20Toasters/FlyingToasterScreenSaverView.m)
registers its `NSScreen` frame and renders its slice of the same world.
Sprite positions are pure functions of `CFAbsoluteTime`, so per-display
scenes stay in sync without any explicit coordination.

The "Number of Toasters" preference is treated as a per-monitor density
and multiplied by `globalDesktopArea / largestSingleScreenArea`, so even
L-shaped or T-shaped layouts with display gaps stay populated.

### Nine live options

Every setting applies to the running preview within ~1 second of moving
the slider — no need to close System Settings to see your change. All
controls are sliders (or checkbox) with tick marks; no inscrutable
numeric inputs.

| Setting | Range | What it does |
|---|---|---|
| **Toasters per Display** | 1 – 20 | Density of the swarm |
| **Flight Speed** | Slow → Fast (5 ticks: Snail / Slow / Medium / Fast / Lightning) | How quickly each sprite traverses its own diagonal |
| **Wing-Flap Speed** | Slow → Fast (9 ticks, 200–40 ms/frame) | How fast the toasters flap their wings |
| **Flight Direction** | SW ↔ NW (with live label below: "down-left" / "up-left") | Which way the swarm flies |
| **Toast / Toaster Ratio** | 0 – 100 % | Probabilistic mix of toast vs intact toasters |
| **Fast Toaster Frequency** | Off → 100 % | Chance any given toaster spawns as the "fast" variant |
| **Toast Level** | Light / Golden / Dark / Burnt | Browning level applied to toast sprites |
| **Cloud Cover** | Clear → Overcast (0 – 20) | Procedural cloud sprites drifting in a parallax layer behind the toasters |
| **Constant density across displays** | checkbox | Scale the toaster count so each display gets the same density; otherwise the slider value is the *total* population |

### macOS 26 (Tahoe) compatibility

macOS 26 introduced a fundamentally new screensaver hosting model —
`legacyScreenSaver.appex` is now a sandboxed App Extension with sharp
limitations on file-system writes, nib loading, and process lifetime.
The Apple-shipped legacy `.saver` bundles (e.g. `FloatingMessage`) gave
up entirely and now ship without configure sheets at all. This fork
keeps the configure sheet alive on macOS 26 by:

- **Programmatic UI.** The xib is gone. The prefs window is now an
  `NSView` hierarchy built in code, which sidesteps a class of macOS 26
  nib-loading bugs that left other legacy savers showing the generic
  "no options available" sheet.
- **Sandbox-correct preferences storage.** Writes go to
  `NSApplicationSupportDirectory` (sandbox-redirected to the
  `legacyScreenSaver.appex` container — `~/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Application Support/Flying Toasters/prefs.plist`),
  which is the one location the saver host is allowed to write. The
  `~/Library/Preferences/ByHost/` path that older savers use returns
  EPERM under macOS 26.
- **Cross-process live preview.** The Options UI and the running
  preview animator can spawn into separate `legacyScreenSaver.appex`
  processes, so the in-process `NSNotification` we use for instant apply
  can't reach the renderer. To get the live-preview behaviour, the
  animation loop polls the prefs plist once per second on a wall-clock
  throttle (one ~290-byte read; negligible cost).
- **macOS 26 deployment target.** No legacy code paths or `@available`
  branches for older OSes.

### Investigation notes

While building this, every non-trivial macOS-26 quirk was documented as
it came up. Useful reading if you're working on a similar project:

- [`docs/macos26-prefs-investigation.md`](docs/macos26-prefs-investigation.md)
  — the full multi-day investigation into why `.saver` configure
  sheets fail on macOS 26, where prefs writes actually go inside the
  new sandboxed hosts, and what works.
- [`docs/multi-host-bonjour.md`](docs/multi-host-bonjour.md) — design
  notes for a future direction: Bonjour/MultipeerConnectivity-bridged
  multi-Mac swarms where toasters fly across hosts on the same LAN.

## Requirements

- macOS 26 (Tahoe) or later. Deployment target is `26.0`.
  - On macOS 14–15 the architecture relies on `legacyScreenSaver`
    hosting every per-display `ScreenSaverView` instance in a single
    process, which is the behaviour from Sonoma onwards; the saver
    will install and run but most of the macOS-26-specific fixes
    won't apply.
- Apple Silicon or Intel Mac. Universal `arm64 + x86_64` binary.

## Install

Build from source. A pre-notarized binary distribution may follow in
a later release; for now the source path is the supported route:

```sh
git clone https://github.com/CliveW/FlyingToasters-MultiMonitor
cd FlyingToasters-MultiMonitor
xcodebuild -project "Flying Toasters.xcodeproj" \
           -scheme "Flying Toasters" \
           -configuration Release build
cp -R "$(xcodebuild -showBuildSettings -scheme 'Flying Toasters' -configuration Release | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2}')/Flying Toasters.saver" \
       ~/Library/Screen\ Savers/
```

You'll need Xcode 17 or later, and a free Apple Developer account
configured in Xcode for the local code-signing identity. Then in
System Settings → Screen Saver, pick **Flying Toasters** and click
**Options** to configure.

## Uninstall

```sh
bash scripts/uninstall.sh
```

Kills the wallpaper / screensaver host processes, removes the
user-level `.saver` bundle and prefs plist, sweeps the macOS-26
sandboxed-extension containers and wallpaper-agent caches, and
prompts for sudo only if a system-level install exists. The script
verifies the system is clean at the end. Safe to re-run; idempotent.

## Build & run from source

Open `Flying Toasters.xcodeproj` in Xcode 17 or later. The
`Flying Toasters` scheme builds the `.saver` bundle directly into
`~/Library/Screen Savers/` via the project's `INSTALL_PATH`.

The `Flying Toaster Test` scheme is a regular `.app` that hosts the
saver view full-screen for faster iteration — useful when you don't
want to wait for System Settings to pick up bundle changes.

## Architecture in one paragraph

`FlyingToasterScreenSaverView` is the `ScreenSaverView` subclass macOS
instantiates per display. It hosts a SpriteKit
[`FlyingToastersView`](Flying%20Toasters/FlyingToastersView.m) which
presents a [`ScreenSaverScene`](Flying%20Toasters/ScreenSaverScene.m).
The scene queries a process-wide
[`ToasterWorld`](Flying%20Toasters/ToasterWorld.m) singleton for the
current particle set each frame and renders the slice of those
particles intersecting its display, transformed into local
coordinates via `screenOriginInGlobal`. Particle positions are pure
functions of `(origin, velocity, birthTime)`, so multiple scenes
across multiple displays stay perfectly in sync with zero
inter-thread communication. Preferences live in
[`ToasterDefaults`](Flying%20Toasters/ToasterDefaults.m), which posts
an `NSNotificationCenter` event on every write so the running
world re-reads its inputs immediately; a 1-second wall-clock poll
inside `ToasterWorld.tickAtTime:` handles the cross-process case
where the prefs UI and the preview animator live in different
processes.

## Roadmap

Possible next directions (no commitments — see the design doc for
each):

- **Multi-host Bonjour swarm.** Discover other Macs on the same LAN
  via MultipeerConnectivity and exchange particle-spawn events so a
  toaster flying off your screen appears at your neighbour's.
  [Design doc + honest assessment of what's actually achievable](docs/multi-host-bonjour.md).
- **Manual per-host layout UI** so the multi-host transitions can
  be geometrically faithful, not just plausible.
- **Cloud Cover assets.** Procedural CG cloud sprites work but
  proper hand-drawn or sourced cloud art would look better.
- **Toaster style variants** (Winged Toast, Bach Toaster, …) — the
  texture-loading path is already factored for additional sets, just
  needs the sprite art.

## Credits

- **Original Flying Toasters screensaver implementation:**
  [Robert Venturini](https://github.com/robertventurini/FlyingToasters)
- **Toaster + toast sprite art:** Originally sourced from
  [Bryan Braun's After Dark CSS](https://github.com/bryanbraun/after-dark-css),
  © 1989 Berkeley Systems Inc.
- **Multi-monitor extension:** Clive Wright — shared `ToasterWorld`
  singleton, per-monitor density scaling, coordinate-system-robust
  screen matching for external displays.
- **macOS 26 compatibility & preferences UI:**
  [Jordan Eunson](https://github.com/jordaneunson) — programmatic
  `NSView` prefs controller, sandbox-correct preferences storage in
  the legacyScreenSaver container, cross-process live-preview poll,
  the nine-option settings inventory (cloud cover, flight direction,
  wing-flap speed, toast/toaster ratio, fast-toaster frequency,
  scale-density), and the full macOS-26 investigation write-up.

## License

MIT — see [LICENSE](LICENSE).
