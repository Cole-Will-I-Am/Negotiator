# Negotiator — Gatekeeper Art Prompts

A reusable recipe for generating each level's **chat background** (and its intro still) so they all
share the look of the Mossback Bridge and the Star-Gate. Feed these to an image generator
(Gemini / Midjourney / etc.). One good portrait per gatekeeper serves the **chat background**, a
cropped **home-card thumbnail**, and (if the eyes are clear) the **blinking-eyes intro**.

## Why the composition matters (it's a chat background, not just art)
The chat sits *on top* of this image, so the picture has to leave room:
- **Portrait / vertical** (fills a tall phone screen — request 9:16 or taller).
- **The gatekeeper is recessed in shadow in the UPPER THIRD**, with its **two eyes glowing** in the
  dark — that glow is the focal point (and it's what I animate for the blink).
- **The LOWER TWO-THIRDS is calm, dark, atmospheric** (fog / water / mist / sand) — quiet and
  uncluttered, because that's where the chat bubbles overlay. Not bright, not busy.
- A warm light near the top (a low moon / lantern / star) for glow.
- The app adds a top+bottom dark scrim for legibility, so a moody, slightly-dark image is *ideal*.

## The master template (fill the {blanks})
> A {setting} at night. {architecture} frames the upper third; recessed in its shadow, a
> {gatekeeper} watches, its two {eye_color} eyes glowing softly in the gloom — the focal point. A
> {light_source} glows near the top. The lower two-thirds is open and quiet: {foreground}, thin
> drifting mist, dark and calm. **Style:** painterly storybook matte painting, classical romantic
> oil-painting feel, volumetric fog, moonlit nocturne, moody chiaroscuro, muted earthy palette
> ({palette}) with warm amber key light, dreamlike, highly detailed, cinematic vertical composition.
> **Avoid:** no text, no watermark, no people, no modern objects, not scary, no menacing teeth, no
> harsh close-up face, no bright or cluttered foreground, not flat, not cartoon. **Aspect 9:16.**

Keep the **Style** and **Avoid** lines identical every time — that's what makes the set feel like one
game. Only change the {blanks}.

---

## Ready-to-paste prompts

### Level 2 — Seraphine, the Star-Gate (needed now)
> A moonlit desert of broken marble colonnades at night. A great ruined Star-Gate of dark stone,
> carved with constellations, frames the upper third; recessed in its shadow an ancient stone Sphinx
> — lion body, folded eagle wings, a serene woman's face — watches, her two golden eyes glowing
> softly in the gloom, the focal point. A low pale moon and faint drifting stardust glow near the
> top. The lower two-thirds is open and quiet: pale sand, fallen pillars, a still silver reflecting
> pool, thin drifting mist, dark and calm. Style: painterly storybook matte painting, classical
> romantic oil-painting feel, volumetric fog, moonlit nocturne, moody chiaroscuro, muted earthy
> palette (sand-parchment, deep umber, cool stone) with warm amber key light, dreamlike, highly
> detailed, cinematic vertical composition. Avoid: no text, no watermark, no people, no modern
> objects, not scary, no menacing teeth, no harsh close-up face, no bright or cluttered foreground,
> not flat, not cartoon. Aspect 9:16.

### Level 3 candidate — the Fae Bargainer (will-o'-the-wisp)
> A black, mirror-still fen at midnight under a thin sliver moon. Twisted willow and tall reed
> silhouettes frame the upper third; hidden among the reeds, a mischievous hearth-fae / will-o'-the-
> wisp watches, its two small green-gold eyes and a flickering lantern-flame glowing in the dark, the
> focal point. The lower two-thirds is open and quiet: still black water, low mist, floating motes of
> pale green wisp-light, lily pads, dark and calm. Style: painterly storybook matte painting,
> classical romantic oil-painting feel, volumetric fog, moonlit nocturne, moody chiaroscuro, muted
> earthy palette (bog-green, slate, deep teal) with green-gold wisp-light, dreamlike, highly detailed,
> cinematic vertical composition. Avoid: no text, no watermark, no people, no modern objects, not
> scary, no menacing teeth, no harsh close-up face, no bright or cluttered foreground, not cartoon.
> Aspect 9:16.

### Level 3 candidate — the Grieving Spirit (lighthouse ghost)
> A storm-worn clifftop and a derelict stone lighthouse at night, cold moon, sea-fog rolling in. The
> lighthouse stands in the upper third; within its dark, broken lantern-room a translucent grieving
> spirit lingers, two pale blue-white eyes glowing softly in the gloom, the focal point. One faint
> warm gleam in the distance. The lower two-thirds is open and quiet: wet black rock, distant surf,
> thick low sea-mist, a faint reflected shimmer, dark and melancholy. Style: painterly storybook
> matte painting, classical romantic oil-painting feel, volumetric fog, moonlit nocturne, moody
> chiaroscuro, muted earthy palette (slate, drowned blue, bone) with a cold blue-white glow, dreamlike,
> highly detailed, cinematic vertical composition. Avoid: no text, no watermark, no people, no modern
> objects, not scary, no harsh close-up face, no bright or cluttered foreground, not cartoon. Aspect 9:16.

---

## Handing it off
- Generate a **portrait** image (any resolution; I downscale + optimize).
- **The glowing eyes in shadow are the key element** — keep them clear; that's what lets me paint an
  "eyes-closed" frame and animate the blink, and it ties the set together.
- Send the file; I wire it in as `chat_bg_<levelId>` (and an intro cinemagraph if the eyes are crisp)
  — zero code on your end.
