# Cinematic Cutscenes — Build Blueprint (for Claude Code)

**Goal:** Add full-screen, cinematic ("4K-quality") video cutscenes to the Negotiator iOS app —
an **intro** that plays before the player approaches the bridge, and a **win** flourish (the
Gloaming Gate opening) after a successful negotiation — without disturbing the working
conversation core.

**Read this whole doc before writing code.** It is split into:
1. Decisions already made (don't relitigate)
2. The asset pipeline (how the footage gets made — this is the part with an external dependency)
3. The in-app implementation (fully specified against the real codebase)
4. Acceptance criteria

---

## 0. Critical honesty / scope

There is no animation tooling or video-generation capability on the VPS or in this repo. The
cutscene **footage itself** must come from one of two sources, decided by the owner:

- **(A) Generated** via an external text-to-video service (Runway / Kling / Sora-class) reachable
  by API key, OR
- **(B) Supplied** — the owner provides key art / clips / stills and we animate around them.

**Until source (A) or (B) is wired, the app ships a procedural SpriteKit placeholder** (see §3.5)
behind the *same* `CutscenePlayer` interface, so all app-side plumbing is built, testable, and
done now; swapping in real footage later is a one-file change. **Do not block the app work on the
footage.** Build the player against the placeholder first.

**"4K" caveat to encode in the pipeline:** master at 4K if the generator emits it, but **ship a
1080×2340 (or 1170×2532) portrait H.265/HEVC** encode. An iPhone panel cannot resolve 4K at 6";
shipping literal 4K only bloats the bundle. Target cinematic *quality*, not the 4K *number*.
Cutscenes live as **on-demand resources / streamed**, never fattening the base download.

---

## 1. Decisions already made

- Two cutscenes for build 1: **`intro`** ("approach the bridge") and **`win`** ("the Gloaming
  Gate opens"). Wire the architecture for an arbitrary set keyed by id; only these two have assets.
- Cutscenes are **skippable** (tap-to-skip after 0.6s, always-visible "Skip" affordance) and
  **never block** reaching gameplay. A failed/missing video must fall through to the existing flow.
- The intro plays **once per fresh negotiation start**, gated by a "reduce/skip cinematics"
  setting and respecting `UIAccessibility.isReduceMotionEnabled` (still shows a static poster
  frame + audio-off, then proceeds).
- Art direction: **stylized, atmospheric** — silhouettes, Gloaming sky, drifting fog, amber glow.
  Bartholomew's two amber eyes blink open in the dark. **The eyes must read lonely/ancient/curious,
  NOT predatory** — onboarding tells players to *befriend or out-lawyer* him; menacing art would
  mis-prime them to bully, which the engine is designed to bounce. This is a hard art note.
- Palette must match `Theme.swift` exactly: Gloaming sky from `paper`→`troll`→`ink`; eyes/glow use
  `gold` `#C8902B` / `amber` `#B5642A`; gate light uses `mine` `#CBA13F`.

---

## 2. Asset pipeline (external dependency)

This section is for whoever runs the generation step; the app does not depend on it at build time.

### 2.1 Shot list — `intro` (~7–9s)
1. **0.0–2.0s** Black → a misty night-wood fades up: layered drifting fog, gradient Gloaming sky,
   a low moon (the icon motif). Slow push-in.
2. **2.0–4.5s** Bridge silhouette resolves in parallax (foreground reeds, mid bridge, far moon).
3. **4.5–6.5s** Beneath the bridge, two **amber eyes blink open** in the dark — slow, heavy-lidded,
   curious. A low rumble (audio).
4. **6.5–9.0s** Title card: *"The Mossback Bridge"* in serif, fades in over the held scene.
   Holds for the "Approach the bridge" CTA / auto-advance.

### 2.2 Shot list — `win` (~4–5s)
1. **0.0–1.5s** The riddle-word (rendered text) dissolves into drifting motes of gold light.
2. **1.5–3.5s** The **Gloaming Gate opens** in a wash of `mine`-gold light, fog parting.
3. **3.5–5.0s** Light blooms to near-white → clean cut to debrief.

### 2.3 Generation (source A) — prompt seeds
Author 16:9 or portrait shots per the list; consistent seed/style across shots for continuity.
Negative prompts: *no photoreal faces, no gore, no menacing teeth, no modern objects.* Style:
*painterly storybook silhouette, volumetric fog, moonlit, muted parchment-and-moss palette,
warm amber key light.* Generate → review → upscale → assemble (see 2.4).

### 2.4 Assembly / encode (run on a box that HAS ffmpeg; NOT required in-app)
```bash
# Concatenate shots, add audio bed, encode to shipping HEVC portrait.
ffmpeg -i intro_concat.mp4 -i rumble.m4a -map 0:v -map 1:a \
  -c:v libx265 -tag:v hvc1 -crf 24 -preset slow \
  -vf "scale=1170:2532:force_original_aspect_ratio=increase,crop=1170:2532" \
  -c:a aac -b:a 128k -movflags +faststart intro.mp4
# Poster frame for reduce-motion / load:
ffmpeg -i intro.mp4 -vf "select=eq(n\,80)" -vframes 1 intro_poster.jpg
```
Deliver `intro.mp4 / intro_poster.jpg / win.mp4 / win_poster.jpg`. Place under
`Negotiator/Resources/Cutscenes/` (NEW group) OR register as On-Demand Resources tagged
`cutscenes` (preferred — keeps base download lean). Wire the tag in `project.yml`.

---

## 3. In-app implementation (fully specified)

All paths under `Negotiator/Negotiator/Negotiator/Sources/`. Use existing `Palette`, `Type`,
`Metrics`, `Haptics` from `Theme/Theme.swift`. Match the project's SwiftUI + `@MainActor`
`GameStore` patterns. The app is assembled via **XcodeGen** (`project.yml`) — after adding files,
update `project.yml` if a new group/resource needs declaring, since there is no `.xcodeproj` to
edit by hand.

### 3.1 New model — cutscene identity
Add to `Sources/App/Models.swift`:
```swift
enum Cutscene: String, CaseIterable {
    case intro, win
    var videoName: String { rawValue }       // intro.mp4 / win.mp4
    var posterName: String { rawValue + "_poster" }
}
```

### 3.2 Router — new Screen case
In `Sources/App/GameStore.swift`, extend the existing enum (do NOT rename existing cases):
```swift
enum Screen: Equatable { case loading, onboarding, home, cutscene, conversation, debrief }
```
Add published state for the active cutscene + what to do when it ends:
```swift
@Published var activeCutscene: Cutscene?
private var afterCutscene: (() -> Void)?
```
Add a setting (persist via `LocalStore`, mirror `hasOnboarded`):
```swift
@Published var cinematicsEnabled: Bool   // default true; backed by local.cinematicsEnabled
```

### 3.3 Flow integration (the only behavioral edits)
**Intro** — wrap the existing `startGame()`. Today `HomeView`'s "Approach the bridge" calls
`store.startGame()`. Insert the cutscene *before* the network session start so it masks latency:

```swift
// HomeView button now calls store.approachBridge()
func approachBridge() {
    guard shouldPlay(.intro) else { startGame(); return }
    play(.intro) { [weak self] in self?.startGame() }   // start AFTER intro finishes
}

private func shouldPlay(_ c: Cutscene) -> Bool {
    cinematicsEnabled && !UIAccessibility.isReduceMotionEnabled || /* reduce-motion shows poster */ cinematicsEnabled
}

func play(_ c: Cutscene, then: @escaping () -> Void) {
    afterCutscene = then
    activeCutscene = c
    screen = .cutscene
}

func cutsceneFinished() {
    activeCutscene = nil
    let cont = afterCutscene; afterCutscene = nil
    cont?()                  // for .intro this runs startGame(), which sets screen=.conversation
}
```
**Important:** `startGame()` already sets `screen = .conversation` on success and surfaces
`errorText` on failure. So after the intro, if the session start fails, the player lands back via
the existing error path — verify `cutsceneFinished()`→`startGame()` does not leave us stranded on
`.cutscene`. If `startGame()` errors, route to `.home` (it currently stays put / shows error on
home). Add: on start failure, `screen = .home`.

**Win** — the win currently flows in `ConversationView.winBanner` → "See how you did" →
`store.toDebrief()` → `screen = .debrief`. Insert the win cutscene on that transition only:
```swift
func toDebrief() {
    guard shouldPlay(.win) else { screen = .debrief; return }
    play(.win) { [weak self] in self?.screen = .debrief }
}
```
Do **not** auto-play win on the `won` flag flip — keep the existing read-the-final-line → banner
beat intact; the cutscene fires only when the player taps through. This preserves the working rhythm.

### 3.4 The player view — `Sources/Views/CutsceneView.swift` (NEW)
A full-screen `AVPlayer` host with skip, poster fallback, reduce-motion handling, and a hard
safety timeout so a stuck/missing video can never trap the player.

Requirements:
- `AVPlayerLayer` via a `UIViewRepresentable` (`PlayerContainer`), `videoGravity = .resizeAspectFill`,
  black letterbox background (`Color.black.ignoresSafeArea()`).
- Resolve the URL: first `Bundle.main.url(forResource:withExtension:"mp4")`; if ODR, request the
  resource tag and show the poster + spinner until available, with a 4s cap → skip.
- **Skip affordance:** after 0.6s show a top-right "Skip" capsule (use `Type.label`,
  `Palette.trollText` on `.black.opacity(0.4)`); the whole screen is tappable to skip. Skipping or
  natural end both call `store.cutsceneFinished()` (for intro) / the `then` closure path.
- Observe `AVPlayerItemDidPlayToEndTime` → finish. Add `.task`/timer **safety timeout** =
  clip length + 2s → force-finish (covers a decode stall).
- **Reduce-motion / cinematics-off path:** if `UIAccessibility.isReduceMotionEnabled`, do not play
  video — show the poster image full-screen for 1.2s (no audio) then finish. If
  `!cinematicsEnabled`, finish immediately (caller still gets its `then`).
- Audio: configure `AVAudioSession` `.ambient` so it respects the silent switch and never
  interrupts music. Fade not required.
- Title-card text for `intro` ("The Mossback Bridge") is **baked into the video**, not overlaid —
  keeps one source of truth. (If owner prefers a live SwiftUI overlay, expose an optional overlay
  closure; default nil.)
- Wire into `RootView.swift` switch: `case .cutscene: CutsceneView()`.

### 3.5 Placeholder footage (ship NOW, before real assets)
Because no real `intro.mp4`/`win.mp4` exists yet, `CutsceneView` must degrade gracefully **and**
there must be something cinematic to look at. Implement a SpriteKit fallback used when the mp4 is
absent:
- New `Sources/Views/CutsceneScene.swift`: a `SKScene` (wrapped in `UIViewRepresentable`
  `ProceduralCutscene`) that renders the intro beats procedurally — `SKEmitterNode` drifting fog,
  a gradient Gloaming sky (`paper`→`troll`→`ink`), a parallax bridge silhouette (`SKShapeNode`
  /`SKSpriteNode` from a vector), and **two amber eyes** (two glowing `SKShapeNode`s, `gold`) that
  scale-Y 0→1 to "blink open," with a soft pulsing glow. Honor the lonely-not-menacing note: slow
  easing, warm glow, no sharp shapes.
- `CutsceneView` resolution order: real mp4 → else `ProceduralCutscene` for `.intro` → else (win,
  no asset) a 1.2s gold-bloom `LinearGradient` animation → finish.
- The procedural intro is genuinely shippable on its own and doubles as the art-direction proof
  on-device. Keep it even after real footage lands (low-data / fallback).

### 3.6 Settings toggle
Add a "Cinematics" toggle to `HowToPlayView` (or a small settings sheet) bound to
`store.cinematicsEnabled`. Persist in `LocalStore` (`hasSeenPhaseHint` shows the pattern). Label:
"Play cutscenes" with subtext "Turn off for faster, motion-free play."

---

## 4. Acceptance criteria

- [ ] Fresh start: tapping **"Approach the bridge"** plays the intro (real mp4 if present, else the
      procedural scene), then lands in `.conversation` with the existing opening message — and the
      negotiation works exactly as before.
- [ ] Intro masks `startSession` latency (session starts during/after the clip, not before it).
- [ ] If `startSession` fails after the intro, player lands on `.home` with the existing
      `errorText`, never stuck on a black `.cutscene` screen.
- [ ] **Skip** appears after 0.6s; tapping anywhere skips; skip and natural-end both advance once
      (no double-advance, no re-entrancy — guard `afterCutscene` is consumed once).
- [ ] Win: read final troll line → "You talked your way in" banner → "See how you did" → **win
      cutscene** → debrief. The `won` haptic and banner beat are unchanged.
- [ ] Reduce Motion ON: shows a static poster ~1.2s, no audio, then proceeds. Cinematics OFF:
      proceeds instantly. Neither path breaks the flow.
- [ ] Silent switch respected; cutscene audio never stops the user's music.
- [ ] No real mp4 in bundle → procedural intro plays; app fully usable. (Proves the no-assets path.)
- [ ] `project.yml` updated for the new `Resources/Cutscenes` group and/or ODR tag; XcodeGen
      regenerates cleanly; TestFlight pipeline unaffected.
- [ ] Base app download is not inflated by 4K masters (assets are 1080–1170px HEVC and/or ODR).

## 5. File-change summary (for the PR)
- EDIT `Sources/App/Models.swift` — add `Cutscene` enum.
- EDIT `Sources/App/GameStore.swift` — `Screen.cutscene`, cutscene state, `approachBridge()`,
  `play/cutsceneFinished()`, `toDebrief()` wrap, start-failure→home, `cinematicsEnabled`.
- EDIT `Sources/App/LocalStore.swift` — persist `cinematicsEnabled`.
- EDIT `Sources/App/RootView.swift` — `case .cutscene`.
- EDIT `Sources/Views/MetaViews.swift` — `HomeView` button → `approachBridge()`.
- EDIT `Sources/Views/ConversationView.swift` — none required (win path goes through `toDebrief()`).
- EDIT `Sources/Views/HowToPlayView.swift` — cinematics toggle.
- NEW  `Sources/Views/CutsceneView.swift` — AVPlayer host + skip + fallbacks.
- NEW  `Sources/Views/CutsceneScene.swift` — SpriteKit procedural intro (placeholder + low-data).
- EDIT `project.yml` — resources/ODR.
- ADD  `Resources/Cutscenes/{intro,win}.mp4 + *_poster.jpg` when footage is delivered.

**Order of work:** Models/Store/Router plumbing → CutsceneView with procedural fallback →
flow wiring → settings → (later) drop in real mp4s. Ship after the procedural path passes
acceptance; real footage is an asset swap, no code change.
