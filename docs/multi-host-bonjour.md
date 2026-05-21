# Multi-Host Flying Toasters: Bonjour-Bridged World

Research notes for extending the saver so peers on the same LAN share one
toaster swarm — a toaster flying off the right edge of *your* screen could
land at the left edge of your neighbour's, as if every Mac in the room was
one continuous desktop.

Status: design exploration, no code yet.

## Goal in one sentence

When two or more Macs on the same LAN are running Flying Toasters, they
discover each other over Bonjour, agree on a shared time base, and exchange
particle-spawn events so that the *same* virtual world is rendered on every
host — extending the cross-display experience we already have on a single
Mac to the cross-host case.

## What we have today (the relevant prior art in this codebase)

The single-host multi-display feature on branch `multi-monitor-spatial`
already provides most of the machinery:

- [`ToasterWorld`](../Flying%20Toasters/ToasterWorld.m) is a process-wide
  singleton holding **all** toaster + cloud state across **all** attached
  displays. There is no per-screen state in the simulation; each
  `ScreenSaverScene` only **renders** the global world into its own
  display's local coordinate space using `screenOriginInGlobal`.
- Particle positions are pure functions of `CFAbsoluteTime`: a particle is
  defined by `(origin, velocity, birthTime, textures)` and its position at
  time `t` is `origin + velocity * (t - birthTime)`. Render is stateless.
- All views share an NSScreen union as `globalBounds`. Particles spawn at
  one edge of the union and reap when they exit the union margin.

The cross-host extension is straightforward to describe given that
machinery: just make `ToasterWorld`'s particle set and `globalBounds`
**shared across processes on different hosts** rather than just across
displays on a single host.

## Sandbox state (verified)

`legacyScreenSaver.appex`, the host process that loads our `.saver` on
macOS 26, ships with the relevant network entitlements:

```
com.apple.security.network.client = true
com.apple.security.network.server = true
```

That's enough for **outbound TCP/UDP connections**, **listening TCP/UDP
sockets**, **mDNS registration**, **mDNS browsing**, and
**Multipeer Connectivity**. No additional entitlement needed on our side
(we already inherit these from the host).

What is **not** verified yet: whether the sandbox grants
`com.apple.private.networkextension` or similar that some VPN/network apps
need — we don't need any of those.

## Two architecture options

### Option A — raw Bonjour over `Network.framework`

- Each saver publishes `_flyingtoasters._tcp.local.` with TXT records:
  `host-id` (UUID), `screen-geom` (encoded NSScreen union rect), `protocol-version`.
- Each saver browses for the same service type, filters out itself.
- On discovering a peer, open a TCP connection (`NWConnection`) and
  exchange a small framed wire protocol.

Pros:
- Full control over the wire format.
- Easy to debug with `Wireshark` / `dns-sd`.
- Maps onto `NWConnection` cleanly with modern API.

Cons:
- We hand-roll connection lifecycle (reconnect, peer churn, NAT-on-same-LAN
  edge cases).
- We hand-roll framing.

### Option B — `MultipeerConnectivity.framework` ★ recommended

- Apple framework specifically for "device-on-the-same-LAN-talk-to-each-other"
  scenarios. Built on top of Bonjour + an encrypted transport.
- Provides `MCNearbyServiceAdvertiser`, `MCNearbyServiceBrowser`,
  `MCSession`. Automatic discovery, encryption, and reliable + unreliable
  data channels.
- Available since macOS 10.10. No special entitlement beyond
  `network.client` + `network.server` for sandboxed clients.
- Peer-to-peer mesh up to eight peers by default; larger meshes possible
  with custom `MCSession` configuration.

Pros:
- Discovery, key exchange, encryption, reconnect-on-loss all handled.
- One reliable + one unreliable channel per peer — exactly what we need.
- Saves ~300 lines of `NWConnection` glue.

Cons:
- We pay the MCSession API's bias for a fixed peer set; toasters and
  laptops walk in and out of range frequently. Adapter code needed.
- The serialisation contract is "send `NSData`"; we still pick our own
  wire format.

**Recommendation: B.** The simpler API beats the marginal benefit of
custom Bonjour at MVP scope.

## Data model: what we exchange between hosts

The saver world reduces to:

1. **Global bounds** — the union of every participating host's NSScreen
   union, expressed in some shared coordinate system. Has to be elected,
   not just computed.
2. **Spawn events** — when a particle is born, every peer must know
   `(particleId, kind, origin, velocity, birthTime, textureSet, alpha,
   zPosition, size)`.
3. **Reap events** — implicit, since position is a function of time and
   every host runs the same exit-the-bounds check.
4. **Pref changes** — out of scope. Each host keeps its own visual
   settings.

In a single host today, `_spawnToasterAtTime:` and `_spawnCloudAtTime:` are
the only places particles come into being. They run inside
`tickAtTime:`, which runs every frame on every display, but the singleton
guards make it run once per simulation step. With multi-host, we need to
elect **which host gets to spawn** so we don't duplicate.

### Topology choice

Three patterns considered:

1. **Mesh of equals.** Every host independently decides when to spawn. We
   gossip spawn events. Problem: race conditions on `particleId`
   uniqueness, double-spawn during clock drift.
2. **Single elected leader.** One host (chosen by lowest UUID or first to
   advertise) is the only host that spawns. Others mirror its decisions.
   Simple, deterministic, but a leader-disconnect storm is annoying.
3. **Sharded by region.** Each host owns spawn rights for the slice of
   `globalBounds` corresponding to its own displays. Particles entering
   another host's slice get "handed off" via a message.

Recommend **(2)** for MVP, with leader election by lowest peer-ID. It maps
1:1 onto how `configureWith…` already works (first-write-wins → only the
leader's defaults seed the world; everyone else mirrors).

**Stretch:** swap to (3) for offline-tolerance. If your laptop leaves the
LAN, it keeps spawning its own particles inside its own union — and
re-joins seamlessly when it returns.

### Coordinate system

Two open sub-problems:

- **Origin alignment.** Each host's NSScreen union has its own (0, 0). How
  do we lay them out relative to one another? Three options:
  - **Auto-tile horizontally.** Place each new peer's union to the right
    of the existing global rect. Trivial to implement. Probably the right
    MVP — looks like "the toasters are flying across the room".
  - **User-declared layout.** Each host has a `peer-position` pref:
    *to the left of <UUID>*, *above <UUID>*, etc.
  - **Auto-detect via display name / network topology.** Unreliable.
- **Time base.** Both hosts run NTP-synced wall clock; `CFAbsoluteTime`
  drift on a LAN is typically <50 ms. Particle positions are time-pure,
  so any drift directly manifests as a position offset for hand-off
  particles. 50 ms × ~100 px/sec = ~5 px tear at the seam — acceptable.
  - Can refine with a periodic ping for offset estimation (one
    round-trip every few seconds, take the mean of the last N).

## Wire protocol sketch

Trivially small. Use `NSKeyedArchiver` or just `NSPropertyListSerialization`
on a plain dictionary. Each message:

```objc
@{
    @"v":   @1,                              // protocol version
    @"op":  @"spawn",                        // spawn | hello | bye | layout | ping | pong
    @"id":  @(particleId),
    @"kind":@(kind),
    @"ox":  @(origin.x), @"oy": @(origin.y),
    @"vx":  @(velocity.dx), @"vy": @(velocity.dy),
    @"bt":  @(birthTime),
    @"sz":  @(size),
    @"alp": @(alpha),
    @"z":   @(zPosition),
    @"tex": @"toaster" | @"toast" | @"cloud",
    @"lvl": @(toastLevel),   // for toast only
}
```

`hello`: peer announces with their NSScreen union, host ID, role hint.
`layout`: leader broadcasts the agreed multi-host bounding rect.
`spawn`: leader broadcasts a particle.
`ping`/`pong`: clock-drift estimation.
`bye`: graceful disconnect.

Reliable channel for `hello` / `layout` / `bye`; unreliable channel for
`spawn` / `ping`. Lost spawns are not catastrophic — the next spawn
arrives in tens of ms.

## Lifecycle realities

This is where the macOS 26 host model bites:

- `legacyScreenSaver.appex` is **short-lived**. It's launched when the
  preview opens, when the screensaver activates, and when the prefs UI
  appears. It is torn down soon after deactivation, often in seconds.
- Each spawn of the host process gets a fresh `MCSession` — discovery,
  handshake, leader election all happen from scratch.
- Realistic time-to-fully-connected on a healthy LAN with Multipeer
  Connectivity: 1–3 seconds of discovery + ~0.5 second handshake. The
  user might be unlocking the screen before the mesh is even formed.

Implications:

- **Optimise for fast convergence.** Cache the previous session's peer
  fingerprints in `ToasterDefaults`-style plist so reconnects skip
  discovery (just dial the cached IP+port).
- **Don't block the first frame on networking.** Render local-only
  toasters immediately; fade in peer toasters once the mesh is up.
- **Have a "single-host fallback"** that's indistinguishable from today's
  behaviour. If no peers are visible after N seconds, just be the saver
  you've always been.

## Visual edge case: peer toasters appearing at edges

The user's screens have one set of edges; the global world has another.
Without manual placement:

- **MVP behaviour:** peer toasters appear at the right edge of my
  global bounds (auto-tile horizontally) and fly leftward across my
  screens. From the user's perspective: it looks like extra toasters
  spawning at the right edge.
- **Better behaviour with manual layout:** peer toasters arrive exactly
  at the edge of my screen that abuts the peer's screen.

Layout config UI: a tiny sub-window in Options listing detected peers,
each draggable around a "room map". For MVP, skip — just rely on
auto-tile.

## Privacy / discovery considerations

- We're broadcasting a public mDNS service. Anyone on the LAN can see it.
- The TXT records include host UUID + screen geometry. Geometry is benign;
  UUID is a stable identifier across sessions per host.
- Mitigations:
  - Optional "Visible to neighbours" checkbox in prefs (default ON for the
    feature to make sense, but allow opt-out).
  - Encrypt payload (Multipeer Connectivity does this by default with
    `MCEncryptionRequired`).
- Not a concern: no PII in the wire format; nothing reaches the public
  internet.

## Effort estimate (rough)

| Phase | Scope | Days |
|---|---|---|
| Networking spike | Multipeer Connectivity inside `legacyScreenSaver.appex` — prove it can discover + connect at all | 1–2 |
| Wire protocol + leader election + spawn sync | Reliable channel for hello/layout/bye; unreliable for spawn; lowest-UUID leader | 2 |
| Coordinate sharing | Auto-tile horizontally; respect leader's bounds | 1 |
| Reconnection / churn handling | Cache peer fingerprints; fallback to local | 1 |
| Prefs UI | Visibility checkbox; list of currently-discovered peers | 1 |
| Multi-Mac testing | Two Macs minimum, ideally three; LAN + ad-hoc Wi-Fi cases | 2–3 |
| **Total** | **~8–10 dev days** | |

## Risks

- **Process churn worse than we think.** If `legacyScreenSaver.appex`
  dies between preview and screensaver activation, every transition costs
  a fresh handshake. May need to push for either a daemon (out of scope —
  another sandbox entitlement) or accept the cold start.
- **Apple may deprecate Multipeer Connectivity** in favour of
  `DeviceDiscoveryExtension` or `NetworkExtension`. The framework
  isn't actively developed but is still shipping in macOS 26. Worth
  re-checking before starting code.
- **Clock skew on poorly-NTP'd Macs** could make hand-offs look stuttery.
  Mitigation: leader broadcasts its `CFAbsoluteTime` periodically;
  followers compute offset and add it when interpreting `birthTime`.
- **Sandbox + Bonjour edge cases.** Have seen reports of `_local` mDNS
  registration failing intermittently from sandboxed extensions on macOS
  26. Will need to verify during the networking spike — and the
  fallback if it fails is the existing single-host saver, which is
  acceptable.

## Recommended MVP scope

If we did this:

1. Multipeer Connectivity, not raw Bonjour.
2. Leader = lowest peer-ID. Followers mirror. No region sharding.
3. Auto-tile horizontally — no manual room-map UI.
4. NTP wall clock only; no per-peer drift correction.
5. New checkbox in Options: **"Share toasters with neighbours on this
   network"**. Off by default — opt-in for privacy and to keep the
   baseline experience unchanged for existing users.
6. Single-host fallback if no peers in 5 seconds.

Defer until later:

- Manual peer arrangement.
- Region-sharded ownership.
- Per-peer drift correction.
- Pref synchronisation.
- Reactive gestures (click to toss a toaster at a neighbour).

## Next concrete steps

1. **Build a 20-line spike.** Inside `FlyingToasterScreenSaverView`,
   instantiate an `MCNearbyServiceAdvertiser` and `MCNearbyServiceBrowser`
   for `_flyingtoasters._mcs`. Log discoveries via `os_log`. Run on this
   Mac, run on a friend's Mac, see whether they find each other within
   five seconds. If yes, the whole thing is worth pursuing. If no,
   investigate sandbox first.
2. If (1) works, design the wire protocol concretely with a small
   `FTPeerMessage` class.
3. Wire spawn events into `_spawnToasterAtTime:` and
   `_spawnCloudAtTime:` such that only the leader spawns; everyone else
   receives.
4. Test cross-host visual hand-off — does a toaster crossing the seam
   look continuous?

## Reality check — what "seamless cross-host transitions" actually means

After writing the section above I went back and asked honestly: "could
we have multi-host multi-screen transitions, true to where a toaster
leaves one screen and exits the other, with no issues at all?" The
honest answer is no. The MVP gets close to a *plausible illusion*, but
*pixel-faithful spatial continuity across hosts* runs into several
issues that no code path makes go away on its own.

Ranked by how visible each is to an observer at the seam:

1. **No automatic spatial truth.** macOS gives us no way to learn where
   one Mac's screens sit relative to a peer's in physical space. Auto-tile
   horizontally is a *convention*, not a fact. True continuity needs a
   manual room-map declared by the user.
2. **Physical bezels and gaps.** Even with perfect spatial config, two
   laptops on a desk have several cm of dead space between their displays.
   A toaster crossing that gap will appear to teleport across it — only
   acceptable when the screens are nearly touching.
3. **Clock skew.** `position = origin + velocity × (t − birthTime)`. At
   typical LAN NTP skew (30 ms) and ~200 px/sec, the handoff is ~6 px off.
   Active drift-correction over MC can shrink this to ~5 ms, never zero.
4. **Process churn on macOS 26.** `legacyScreenSaver.appex` dies between
   preview, activation, and reactivation. Each new process spawn re-runs
   discovery + handshake (1–3 s of single-host mode every screen unlock).
5. **Cold-start window.** During the first 1–3 seconds after the saver
   activates, the mesh isn't formed yet. Brief previews may never show
   any peer toasters.
6. **Wi-Fi reliability.** Unreliable channel = lost spawn events on flaky
   networks. Reliable channel = added latency that makes (5) worse.
7. **Resolution / scale mismatch.** 5K Retina ↔ 1080p. Picking whether
   the global space is in points, pixels, or normalized units shows
   visible artifacts at the seam in every choice.
8. **Sandbox unverified.** The entitlements look right, but a real spike
   inside `legacyScreenSaver.appex` is still required before declaring
   the whole approach viable.

### What's actually deliverable

| Promise | Verdict |
|---|---|
| "Toasters appear at the right edge of my screen, look like they came from the room next door" | ✓ MVP scope. Auto-tile, ~1-second discovery, looks great in casual viewing. |
| "I can configure exactly where my friend's Mac is and have geometric continuity at the seam" | ✓ With manual room-map UI. Worth doing if the feature catches on. |
| "Pixel-perfect, frame-perfect continuous projection across the room as if every screen were one piece of glass" | ✗ A research project, not a feature. Physical bezels + clock skew + process churn make this aspirational at best. |

**Bottom line for a teammate:** the MVP makes it *look like the toasters
are flying through the room*. Most observers won't notice it isn't
spatially faithful. We should ship that and never claim more.

## Open questions for next session

- Do we care about same-iCloud-account-only discovery (like AirDrop in
  Contacts-only mode), or is "anyone on the LAN" fine?
- Should the leader rotate (anti-fairness) or stick (consistency)?
- Do you want peer toasters to look subtly different — e.g. a tint, or a
  small floating label of the host name as they cross the seam — so you
  can tell who they came from?
