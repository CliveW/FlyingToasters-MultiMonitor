# Flying Toasters on macOS 26 — Investigation Notes

Status: **suspicions only — no code changes**. Captures what we currently
believe is going on, what would need verification, and what features the
codebase could plausibly expose if/when the configure-sheet path is repaired.

## Reported symptoms

1. **Persistence is broken across the board.** Sliders move in the Options
   sheet, Done is pressed, but nothing reopens at the chosen values.
2. **First-open-per-user asymmetry.** A fresh recipient sees our custom
   Options sheet the very first time they open it. After dismissing, the same
   user never sees our sheet again on subsequent opens — they get a generic
   macOS screen-saver dialog instead.
3. **Other users see the generic dialog from the start.** Users who weren't
   the original installer never get our custom sheet at all; they see what
   looks like macOS's default screen-saver options.

## System-architecture facts (verified, macOS 26.5, build 25F71)

These are the ground rules our `.saver` is now operating under. Everything
below references this picture.

| Old (≤ macOS 13) | macOS 26 |
|---|---|
| `legacyScreenSaverConfigure` helper loaded the `.saver` and called `-configureSheet` directly | `Wallpaper.appex` (System Settings extension, bundle id `com.apple.Wallpaper-Settings.extension`) loads the `.saver` to surface its Options UI |
| `legacyScreenSaver` hosted the running animation | `WallpaperLegacyExtension.appex` (bundle id `com.apple.wallpaper.extension.legacy`) hosts the animation |
| Both ran in the same effective container; prefs flowed through `ScreenSaverDefaults` | Two **separate sandboxed App Extensions** with **separate containers**. NSUserDefaults no longer shared. |
| Almost all Apple savers were `.saver` bundles | Apple-shipped savers are XPC extensions with `EXExtensionPointIdentifier = com.apple.wallpaper` (e.g. `WallpaperImageExtension.appex`). The remaining `.saver` bundles (e.g. `/System/Library/Screen Savers/FloatingMessage.saver`) **ship with no configure-sheet** (no nib in Resources, no `configureSheet` symbol) — Apple has effectively stopped exercising the old API in their own code. |

Both relevant extensions carry `com.apple.security.app-sandbox = true`. Their
only home-relative file system exception is
`com.apple.security.temporary-exception.files.home-relative-path.read-write
/Library/Screen Savers/`. **No** exception for `~/Library/Preferences/ByHost/`,
no app-group, no shared user-defaults container.

The `WallpaperKit` framework that the wallpaper extensions speak through is
not exposed as a public framework on disk (no
`/System/Library/Frameworks/WallpaperKit.framework`, no headers in
`/System/Library/PrivateFrameworks/WallpaperKit.framework`). Third-party
extensions cannot link against it.

## Symptom 1 — Settings don't save

This part is well-understood and we attempted a targeted fix
(`ToasterDefaults` now writes a plain plist to
`~/Library/Screen Savers/Flying Toasters.prefs.plist`, replacing the previous
`ScreenSaverDefaults` flow). Persistence is still unconfirmed end-to-end on
macOS 26. Active suspicions, in priority order:

### S1.A — Sandbox redirect on `pw_dir`-derived paths

We use `getpwuid(getuid())->pw_dir` to escape the App Extension's
container-redirected `NSHomeDirectory()`. The directory-service path is
generally not redirected by sandboxd, so the resulting URL points at the real
user home. Plausible failure modes:

- The Wallpaper.appex sandbox profile in macOS 26 may apply additional path
  redirection through `vnode_lookup` that the directory-service workaround
  doesn't beat. Need to confirm with `sandbox-exec`-style trace or `log
  show --predicate 'subsystem == "com.apple.sandbox.reporting"'` during a
  slider change.
- Atomic write via `NSDictionary writeToURL:error:` creates a temporary
  sibling file first (e.g. `.dat.nosync.<id>`). The sandbox profile *might*
  permit the final rename target but block the temp file. Worth testing with
  a non-atomic write to see if the file appears.

### S1.B — Sliders' IBActions are firing but the dictionary is reloaded between events

`_persistValue:forKey:` does `load → mutate → write` on every setter call.
If two sliders are moved quickly, write A starts → write B reads from disk
before write A's atomic rename completes → write B clobbers A's update with
A's pre-change view. Currently low risk (sliders aren't moved that fast by a
human) but worth flagging for any future "all three changes weren't saved"
report.

### S1.C — `WallpaperLegacyExtension` reads from a different container than `Wallpaper.appex` writes to

If S1.A *does* allow writes, they may still land at a location only
`Wallpaper.appex` can reach. The animation host has the *same* sandbox
exception on paper, but exceptions are interpreted on the kernel side and
extension hosts may apply additional vnode filters. The acceptance test is:
does the file appear under `~/Library/Screen Savers/` after slider movement?
If yes, does the animation pick up changes after restart?

### S1.D — The `exit(0)` hack in `screenSaverWillStop`

`FlyingToasterScreenSaverView.m:127` calls `exit(0)` to work around a macOS
14+ memory-retention issue. On macOS 26 the host process being force-killed
is `WallpaperLegacyExtension.appex`, an *App Extension*. Extensions that
crash repeatedly may be marked stale by `pkd`/ExtensionKit, with downstream
effects on what bundles the system is willing to surface (see S2.A below).

## Symptom 2 — "First open shows ours; later opens show generic"

This is the most diagnostic symptom and the one we have the least data on.
Hypotheses in priority order:

### S2.A — `pkd` / ExtensionKit caches a "this bundle is borked" verdict

`Wallpaper.appex` loads `.saver` bundles via XPC at the moment Options is
clicked. If the load surface throws — a missing localization, an Auto Layout
constraint violation under Liquid Glass's new sheet chrome, a nib loaded
twice due to the helper being short-lived, etc. — the System Settings UI
may fall back to a stock "generic screensaver options" pane and **persist
that fallback in `~/Library/Daemon Containers/.../Caches/ExtensionInfo*`**
or in `pkd`'s on-disk plist. Next open: cache hit on the bad verdict.

Verification:
- `log show --predicate 'subsystem == "com.apple.extensionkit" OR subsystem
  == "com.apple.pkd"' --last 1h` filtered for the bundle id around the
  moment of first-vs-second open.
- Check `~/Library/Caches/com.apple.systempreferences.cache.*` and the
  `Wallpaper.appex` container's `Library/Caches/` for entries keyed by our
  bundle id.

### S2.B — Configure-sheet returning an `NSWindow` directly is no longer the contract

`FlyingToasterScreenSaverView -configureSheet` returns an `NSWindow*` that
is presented as a sheet on the Settings pane. In macOS 26, the host is no
longer an `NSWindow`-backed app — it's an XPC extension pumping AppKit
through XPC to System Settings. The first-time invocation may marshal an
`NSWindow` through this bridge successfully; the *second* invocation finds
the window has already been retained/inserted into a parent hierarchy and
silently fails to display, falling back to a default sheet.

Notable: Apple's own remaining legacy `.saver` (FloatingMessage) ships
**without** a configure sheet. They have removed all real-world testing of
this code path inside Apple.

### S2.C — Nib loading from inside an App Extension is one-shot

`-initWithWindowNibName:` triggers a nib load from the bundle's Resources.
In some App Extension contexts, `NSBundle` caches a "this nib has already
been loaded for this owner" decision and refuses the second load
silently — particularly with `releasedWhenClosed="NO"` on the window, which
our xib sets. The window survives the first dismissal; reuse paths may not
have been tested by Apple's new host.

### S2.D — The xib targets Xcode-8-era IB tooling

The xib reports `toolsVersion="15705"` (Xcode 9.x) with
`targetRuntime="MacOSX.Cocoa"` and `fixedFrame="YES"` on every control.
Modern System Settings panes use Auto Layout exclusively and live inside
a Liquid Glass material chrome. The first render may succeed by accident;
later renders, when System Settings has resized/relayouted its sheet
container, may collapse our content to zero size — at which point the
host could substitute a default UI to avoid an empty sheet.

### S2.E — Code-signature trust differs per user

Our bundle is signed with **Apple Development: Clive Wright (7K842RRZZ9)**,
team `2QA67VV372`, no notarization, no hardened runtime. On macOS 26 the
wallpaper extensions are themselves sandboxed and may invoke an additional
`SecStaticCodeCheckValidity` pass before loading a third-party `.saver`.
The result of that check can plausibly be:

- *First user (developer)* — trusted because the dev cert is in their
  login keychain.
- *Other users* — same machine, different login keychain, no dev cert →
  signature check soft-fails → host loads the bundle for *animation*
  (no UI risk) but refuses to load its nib for the configure sheet,
  substituting a generic options panel.

This is the strongest candidate for the "all other users see generic"
half of the report. Worth checking with
`spctl -a -v "/Users/<other-user>/Library/Screen Savers/Flying Toasters.saver"`
on the friend's machine, plus `log show --predicate 'subsystem ==
"com.apple.securityd"'` during their Options click.

### S2.F — Localization-table absence

Apple's modern `.saver` (FloatingMessage) ships with 30+ `.lproj`
directories, an `InfoPlist.loctable`, and explicit language metadata.
Ours ships with none. macOS 26 may require localization resolution to
succeed before presenting a configure sheet from a sandboxed extension;
absence could fall to default UI.

## Symptom 3 — "Other users see generic"

Largely covered by S2.E. Other plausible angles:

### S3.A — Per-user `~/Library/Screen Savers/` ownership

The bundle lives under the **installing user's** home. Other users on the
same machine see it only if a copy lives in `/Library/Screen Savers/`.
The friend may have moved a copy system-wide; that copy would still carry
the dev signature, exposing them to S2.E.

### S3.B — Per-user state in `wallpaper.agent`'s container

`~/Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/com.apple.wallpaper.caches/screenSaver-<bundle-path>/`
exists per user and caches thumbnails / introspection results. Other users
may be seeing a cache that was poisoned the first time they tried to open
Options — see S2.A.

## What `WallpaperKit`-shape support would actually require

Best evidence so far points at "legacy configure-sheet is on borrowed
time". A robust macOS 26 fix likely requires re-shaping the project as an
**App Extension** (`.appex`) with `EXExtensionPointIdentifier =
com.apple.wallpaper`, which is the form *every* shipped Apple screensaver
now takes. That framework is currently private, so this path is blocked on
either:

- A public WallpaperKit SDK in a future macOS 26.x or 27, or
- Reverse-engineering the XPC protocol (not a stable target).

Until then, options are:

1. Keep the legacy `.saver`, accept that the configure sheet is unreliable
   on macOS 26, and remove it from the user contract (ship defaults only,
   no settings UI). FloatingMessage.saver is the precedent.
2. Keep the legacy `.saver` with a *file*-watcher that re-reads
   `~/Library/Screen Savers/Flying Toasters.prefs.plist` and ship a tiny
   non-extension companion app to edit that plist directly — completely
   sidestepping the configure-sheet API.
3. Wait for WallpaperKit to be made public, then port.

## Settings inventory

After review, the target user-facing set is **11 settings**. Two candidates
were explicitly pruned (see below).

| #  | Setting | Value type | Range / values | Status |
|----|---|---|---|---|
| 1  | **Flight Speed** | integer (enum) | 5 positions: Snail / Slow / Medium / Fast / Lightning | Current — in xib |
| 2  | **Toast Level** | integer (enum) | 4 positions: Light / Golden Brown / Dark / Burnt | Current — in xib |
| 3  | **Density** (toasters per display) | integer | 1 – 20 | Current — in xib (per-monitor on `multi-monitor-spatial`) |
| 4  | **Cloud Cover** | integer | 0 – N (0 = clear sky) | Latent — needs new sprites + a parallax background layer |
| 5  | **Toaster Style** | string (or integer index) | preset name: "Classic" / "Winged Toast" / "Bach Toaster" / … | Latent — texture loader at `ToasterWorld._toasterTextures` is already factored |
| 6  | **Flight Direction** | integer (enum) — *or* float (degrees) | 8-way compass, or 0 – 359° | Latent — currently hard-coded down-left 45° |
| 7  | **Background Color** | color (3 floats RGB, or `#RRGGBB` string) | full colour space | Latent — currently `[NSColor blackColor]` |
| 8  | **Toast / Toaster Ratio** | float | 0.0 – 1.0 (fraction that are toast) | Latent — currently fixed at 50% via `idx % 2` |
| 9  | **Fast-Toaster Frequency** | integer | 0 – 100 (percent chance each non-toast spawn becomes fast) | Shipped in v1.8 |
| 10 | **Wing-Flap Speed** | float | seconds-per-frame, e.g. 0.04 – 0.20 | Latent — currently `kAnimFrameDuration = 0.085` |
| 11 | **Scale density across displays** | boolean | on / off | Latent — currently always on; only meaningful on `multi-monitor-spatial` |

### Explicitly dropped during this review

- **Sound.** After Dark 2.0 played a wing-flap SFX. Out of scope.
- **Frame Rate as a user setting.** Currently `1/30.0` at
  [FlyingToasterScreenSaverView.m:24](../Flying%20Toasters/FlyingToasterScreenSaverView.m#L24).
  On modern hardware (Apple silicon, ProMotion or not) **60 fps is
  comfortable everywhere** — adopt `1/60.0` as a constant rather than a
  user choice.

### Storage in plist terms

All eleven reduce to plist-friendly primitives. NSNumber covers
integer/float/boolean; NSString covers presets; Background Color is either
an NSArray of three NSNumbers or a single NSString (`#RRGGBB`).

### Per-setting rationale and code anchors

- **Cloud Cover** — `FlyingToastersView.m:25` currently sets a flat black
  background. A parallax cloud layer would attach to `ScreenSaverScene`
  with sprites loaded the same way `ToasterWorld` loads toasters.
- **Toaster Style** — sprite picker only; the existing `_toasterTextures`
  method just walks four named files, so additional preset sets are a
  resource-pack change plus a path-prefix variable.
- **Flight Direction** — spawn-edge selection and velocity vector are one
  function (`_spawnParticleAtTime:` at
  [ToasterWorld.m:164-204](../Flying%20Toasters/ToasterWorld.m#L164-L204)).
- **Background Color** — one line at
  [FlyingToastersView.m:25](../Flying%20Toasters/FlyingToastersView.m#L25);
  trivially exposed via `NSColorWell`. Persist as `[r, g, b]` NSArray.
- **Toast / Toaster Ratio** — change `idx % 2 == 1` at
  [ToasterWorld.m:169](../Flying%20Toasters/ToasterWorld.m#L169) to a
  probability test (e.g. `arc4random_uniform(100) < toastPercent`).
- **Fast-Toaster Frequency** — `idx % 8 == 0` at
  [ToasterWorld.m:170](../Flying%20Toasters/ToasterWorld.m#L170); slider
  changes the divisor; 0 disables fast toasters entirely.
- **Wing-Flap Speed** — `kAnimFrameDuration` const at
  [ScreenSaverScene.m:12](../Flying%20Toasters/ScreenSaverScene.m#L12)
  becomes an instance property fed from prefs.
- **Scale density across displays** — already implemented per-monitor on
  `multi-monitor-spatial`
  ([ToasterWorld.m:91-92](../Flying%20Toasters/ToasterWorld.m#L91-L92));
  the checkbox toggles whether `count * areaFactor` applies or not.

## Verification plan (read-only, safe to run)

These are the next steps before any further code changes. None of them
modify state.

1. **Where do writes go?** While the prefs sheet is open, in a separate
   shell:
   ```
   log stream --predicate 'subsystem == "com.apple.sandbox.reporting" AND (process == "Wallpaper" OR process == "WallpaperLegacyExtension")' --info
   ```
   Move a slider. Any `deny file-write*` lines tell us the sandbox
   verdict and the target path.

2. **Does the prefs plist appear?** After moving a slider:
   ```
   ls -la "$HOME/Library/Screen Savers"
   find "$HOME/Library/Containers" -name "Flying*.plist" -mtime -1
   ```

3. **What does pkd / ExtensionKit think about our bundle?**
   ```
   pluginkit -mAvv -p com.apple.wallpaper | grep -A2 -B2 "Flying\|robert-venturini"
   log show --predicate 'subsystem == "com.apple.extensionkit"' --last 30m \
     | grep -i "Flying\|robert-venturini"
   ```

4. **Why does the second open fall back?** Repeat Options open with this
   running and diff the streams:
   ```
   log stream --predicate '(process == "Wallpaper" OR process ==
     "WallpaperLegacyExtension" OR subsystem == "com.apple.pkd") AND
     messageType == 16'
   ```

5. **Other-user reproduction.** On the friend's machine, with a second
   user account that's never opened Options:
   ```
   spctl -a -v "$HOME/Library/Screen Savers/Flying Toasters.saver"
   codesign -dvvv "$HOME/Library/Screen Savers/Flying Toasters.saver" 2>&1 \
     | grep -E "Authority|TeamIdentifier"
   ```

## Open questions for the next session

- Confirm friend's OS minor version (`sw_vers`) — macOS 26.0 vs 26.5 may
  matter; the extension architecture has shipped fixes between dot releases.
- Did the friend distribute the `.saver` by copying the bundle, or by
  installing a signed/notarized `.pkg`? Distribution method directly
  affects S2.E.
- Are the "other users" who see the generic sheet on the **same Mac** as
  the friend, or on **different Macs**?
- Was `~/Library/Screen Savers/Flying Toasters.saver` copied to
  `/Library/Screen Savers/` (system-wide) on any of the affected machines?
