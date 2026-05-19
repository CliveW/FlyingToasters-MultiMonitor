# Flying Toasters — Multi-Monitor

A multi-monitor enhancement of [Robert Venturini's FlyingToasters](https://github.com/robertventurini/FlyingToasters), the macOS screensaver that recreates the iconic After Dark 2.0 flying toasters.

In the original, each attached display runs an independent population of toasters — sprites that exit one monitor never appear on another. This fork unifies all displays into one virtual desktop: toasters fly **across** monitor boundaries, exiting one screen and arriving on the next at the matching position.

![Image of FlyingToasters](https://github.com/robertventurini/FlyingToasters/blob/master/FlyingToasters.gif)

## What's new

- **Shared world across all displays.** A process-wide `ToasterWorld` singleton owns the toaster population. Each `ScreenSaverView` registers its `NSScreen` frame and renders its slice of the same world. Sprite positions are pure functions of `CFAbsoluteTime`, so per-display scenes stay in sync without explicit coordination.
- **Density scales with virtual-desktop area.** The "Number of Toasters" preference is treated as a per-monitor density and multiplied by `globalDesktopArea / largestSingleScreenArea` so layouts with gaps (T-shapes, L-shapes) still feel populated.
- **Coordinate-system-robust screen matching.** For external displays where `NSWindow.screen` returns `nil` and `NSScreenNumber` is unavailable, the matching `NSScreen` is recovered by comparing `NSWindow.frame.origin.x + size` against `NSScreen.frame` — avoiding the AppKit/Quartz coordinate-system mismatch that those windows otherwise present.

## Requirements

- macOS 14 (Sonoma) or later. The architecture relies on `legacyScreenSaver` hosting every per-display `ScreenSaverView` instance in a single process, which is the behaviour from Sonoma onwards. On older macOS versions the screensaver will still install and run, but each display will revert to its own independent toaster population.
- Apple Silicon or Intel Mac. Tested on Apple Silicon with up to 4 displays.

## Build & install

The project is a vanilla Objective-C Xcode `.saver` target. Before building you'll need to set your own Apple Developer team under Signing & Capabilities — the public repo intentionally ships without one.

```sh
git clone https://github.com/CliveW/FlyingToasters-MultiMonitor.git
cd FlyingToasters-MultiMonitor
open "Flying Toasters.xcodeproj"
```

In Xcode, select the **Flying Toasters** target → Signing & Capabilities → pick your team. Then:

```sh
xcodebuild -scheme "Flying Toasters" -configuration Release \
  -derivedDataPath build clean build
cp -R "build/Build/Products/Release/Flying Toasters.saver" \
      ~/Library/Screen\ Savers/
```

Quit System Settings before installing — macOS holds a lock on `.saver` bundles while it's open and silently keeps the old code otherwise. Then select Flying Toasters in System Settings → Screen Saver.

To test full-screen without waiting for the idle timer:

```sh
open -a ScreenSaverEngine
```

## Caveats and known behaviours

- **Non-rectangular monitor layouts have dead zones.** When monitors are laid out in a T, L, or staggered shape, the bounding rectangle of the virtual desktop covers regions that aren't on any actual display. Toasters can transit invisibly through those gaps. You'll occasionally see a sprite vanish off one monitor's edge and reappear seconds later on another.
- **Spawn pattern is the original 45° down-left from top/right edges of the global rect.** Toasters that spawn near the global bottom-left corner have a short visible life because they exit the world quickly; sprites that enter from the top of an external monitor and traverse all the way across to the laptop in the opposite corner are visible the longest.

## Credits

This project is a derivative of **Robert Venturini's [FlyingToasters](https://github.com/robertventurini/FlyingToasters)**. All credit for the original ObjC screensaver implementation, the SpriteKit scene structure, the texture sequencing, and the wing-flap animation goes to him. The multi-monitor work in this fork is built entirely on top of that base.

The toaster and toast image assets come (via Robert's project) from Bryan Braun's [After Dark CSS](https://github.com/bryanbraun/after-dark-css). As Bryan notes there, those assets are © 1989 Berkeley Systems Inc.

## License

MIT — see [LICENSE](LICENSE). Original copyright Robert Venturini (2020); multi-monitor extensions copyright Clive Wright (2026).
