# Schedule Toggle — Inspiration Brief

**Control:** an either-or selector in Settings → Schedule that picks between **Sunset** (warm
automatically around local sunset) and **Always on** (warm around the clock). Today: a small
ember-gradient segmented pill. Goal: bigger, more custom, more artful — **Apple Liquid Glass** and
**macOS-native** directions, buildable later in SwiftUI.

The single most useful precedent for us is hiding in plain sight: **macOS's own Appearance setting.**
Set Appearance to **Auto** and the Mac switches light→dark "based on the Night Shift schedule you set,
and if no schedule is set, based on **sunrise and sunset times**." Apple has *already* shipped the exact
either-or we're designing — "follow the sun" vs. "stay put" — and rendered it as **three big square
preview tiles** (Light / Dark / Auto), each a literal miniature of the choice. That tile-as-preview idiom,
plus Night Shift's sunset→sunrise scheduling, is our north star for "native + legible + on-theme."

---

## 1. Apple Liquid Glass — what defines it, and how Apple uses it for *selection*

Liquid Glass is the system-wide material introduced at WWDC25 (iOS 26 / macOS Tahoe 26). Apple's own
description: a **translucent material that "reflects and refracts its surroundings"**, carries
**specular highlights** that "dynamically react to movement," and whose **color is informed by
surrounding content and intelligently adapts between light and dark environments.** It is a *functional
layer that sits above content* and "dynamically morphs as users need more options or move between
different parts of an app." ([Apple Newsroom](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/), [Meet Liquid Glass — WWDC25](https://developer.apple.com/videos/play/wwdc2025/219/))

The five properties to nail (and which our `tokens.json` glass recipe already gestures at):

- **Translucency + real blur** — frosted surface that lets the warm ground show through (`backdrop-filter`).
- **Specular top sheen** — a bright highlight along the top edge; Apple's reads as *wet glass*, and it
  *tracks motion/pointer*. (We have `.sheen::after` + a pointer-tracked `.spec` layer already.)
- **Lensing / refraction** — light is *bent and concentrated* at the rim, not just scattered; a thicker
  element "simulates a thicker material with deeper shadows and more pronounced lensing." Read as a
  tighter, brighter inset ring near the edge. ([MacSales teardown](https://eshop.macsales.com/blog/97650-blurry-or-beautiful-the-tweaks-and-tenets-of-apples-controversial-liquid-glass-design-in-macos-tahoe/))
- **Adaptive tint** — Apple says tint is for emphasis/CTA, applied *to the selected element only* — which
  maps perfectly to our rule: the chosen side wears the warm `--sunset` fill, the other stays clear glass.
- **Concentricity** — nested shapes share a center and corner family. Apple calls the **capsule** the
  hero shape and notes its geometry "naturally supports concentricity… the mirrored proportions of
  **sliders and switches**." For nested radii use container-concentric corners. ([Get to know the new design system — WWDC25](https://developer.apple.com/videos/play/wwdc2025/356/))

**How Apple applies glass to selection controls specifically:**

- WWDC: "tab bars, **segmented controls**, and sidebars all signal selection, navigation, and state in
  consistent ways." On macOS, **Mini/Small/Medium controls keep rounded rectangles**; **Large + X-Large
  use capsules.** So a *large* version of our control legitimately becomes a capsule — license to go big.
- The selected element is the one that **floats / morphs / lifts**: glass "gives way to content and
  dynamically morphs." The active segment should feel like a separate lit lozenge sitting *on* the track,
  not a recolored cell.
- SwiftUI gives the active piece life via `.glassEffect(.regular.interactive())`: **scale on press, a
  subtle bounce, a shimmer, and "touch-point illumination that radiates to nearby glass."** That radiating
  touch-light is the single most "Liquid Glass" microinteraction we can borrow for the selection moment.
  ([LiquidGlassReference](https://github.com/conorluddy/LiquidGlassReference)) Use `.regular` (not `.clear`)
  for small controls so they stay legible. Don't stack glass on glass.

**Our brand twist on the spec:** selected = `--sunset` fill **+** specular sheen **+** hairline
`rgba(255,255,255,.18)` rim **+** soft ember `--glow-soft`, so selection looks like *lit* glass.
Unselected/track = clear `.glass`. Selected label is dark ink `--indigo` (never cream — fails on gold).

---

## 2. Beautiful either-or / binary patterns in real products

First, the taxonomy that should steer the form (this is a real UX distinction, not pedantry):
a **switch** is for on/off where one state is the "default/quiet" one; a **segmented control** is for
*opposing, equal-weight* options like Light/Dark, Month/Year, Grid/List. **Sunset vs. Always on are
opposing peers, not on/off** — so segmented-control and side-by-side-tile forms are the most honest;
a single switch would wrongly imply "Always on = the on state of Sunset." Where a switch *can* work is
if we frame it as one continuous metaphor (a sun that either follows the horizon or locks at noon).
([Mobbin: Segmented Control](https://mobbin.com/glossary/segmented-control), [UX Drill: switches vs segmented](https://medium.com/@designwithkabi/ux-drill-18-switches-toggles-vs-segmented-controls-b3fbc5ac811b))

Specific products worth stealing the *interaction*, not the look:

- **macOS System Settings → Appearance (Light / Dark / Auto):** three **square preview tiles**, each a
  literal thumbnail of the result; the selected one gets a blue ring. The gold standard for "show the
  choice, don't just label it." Our Sunset tile *is* a tiny Abendrot scene; Always-on tile is steady warmth.
- **iOS / macOS Night Shift:** the closest functional sibling — "Sunset to Sunrise" schedule vs. a fixed
  custom time. Proves users already read "follow the sun" as a first-class scheduling mode.
- **Apple Weather:** condition-reactive backgrounds and the day-arc / sun-position language — the canonical
  Apple example of *time-of-day rendered as scene*, the aesthetic register our Sunset side should hit.
- **iOS system segmented control (the modern glass one):** a matched-geometry pill that *slides* between
  segments with a soft spring — exactly our current baseline mechanism, just smaller and plainer than we want.
- **Things 3:** restraint master — selection is a quiet fill + weight change + a small, *warm* spring;
  delight comes from timing and a single accent, never from chrome. Good calibration for our "restrained" end.
- **Linear:** ultra-crisp segmented toggles, fast and near-instant; the active segment is a subtly raised
  surface with a hairline. Reference for "fast, premium, not flashy."
- **Arc:** playful, springy, slightly over-animated theme/space switches — the upper bound of expressive
  motion before it tips into gimmick; useful as a *don't-exceed* marker.
- **Raycast:** as of v1.103 it adopted **Liquid Glass controls** in its UI — a current, real example of a
  third-party macOS app wearing this exact material on small controls. ([AlternativeTo](https://alternativeto.net/news/2025/9/raycast-v1-103-0-implements-liquid-glass-controls-and-comet-browser-support/))
- **Family / Flighty:** big, friendly, **card/tile choices** with generous touch targets, bold iconography,
  and a confident selected state (lift + glow). Reference for making a binary feel *premium and tactile*
  rather than utilitarian — directly relevant to "bigger, more custom, artful."

Pattern menu these suggest, ranked by fit: **(a) side-by-side choice tiles** (each a mini-scene — best
match to the Appearance precedent), **(b) large capsule segmented control** (native, safe, our baseline
grown up), **(c) one-track sun toggle** where a sun thumb slides between a horizon end and a noon end,
**(d) a dial / half-clock** (expressive, riskier).

---

## 3. Sunset / day-night / warmth metaphors — elegant vs. gimmicky

The metaphor is unusually well-matched here (the app is *literally* named for sunset glow), so we should
use it — but with restraint. What reads **elegant**:

- **A sun on the horizon** vs. **a sun held high/centered** — a clean, legible shorthand for
  "dips with the day" vs. "always up." One shape, two positions; very SwiftUI-able.
- **A gradient track that is a sky:** our `--sky` ramp (indigo → ember → gold) as the selection track,
  with the Sunset side living down where sky meets sun, Always-on up in the warm. Time-of-day as *space*.
- **Glow that behaves like the mode:** Sunset's glow **eases in** (matches "easing in beforehand"),
  Always-on's glow **holds steady and even.** The light *is* the explanation.
- **A subtle day→night arc** behind/under the control, the sun sitting at dusk for Sunset.

What tips into **gimmick** (avoid, or use only in the one "bold" concept, restrained):

- Twinkling stars, drifting clouds, rotating celestial bodies, mountain silhouettes, parallax scenery —
  the Dribbble day/night-toggle clichés. Cute once, noise in a Settings pane you see often.
- A literal analog clock with moving hands (over-literal; high motion cost; hard at small size).
- Anything that needs a raster image or can't survive `prefers-reduced-motion`.

Guidance from the field matches our instinct: these toggles span "a simple sun-moon toggle … to a fully
animated theme switch," and the *restrained* end ages far better in a utility. Daytime reads warm/gold,
dusk/night reads blue-shifted — which is exactly our palette, so the metaphor and the brand collapse into
one. ([day/night toggle survey](https://webtips.dev/how-to-make-an-animated-day-and-night-toggle-switch), [dark-mode design guide](https://www.jamesrobinson.io/post/a-guide-to-dark-mode-design))

---

## 4. Motion — how the best of these animate the change

Tie everything to the brand's signature warm ease: **`cubic-bezier(.22,.61,.36,1)`, ~140ms**
(`--ease-warm`, `--dur-base`). It's a gentle decelerate — light settling, not snapping.

- **Matched-geometry slide** (the baseline, done bigger): the selected lozenge *travels* between
  positions on `--ease-warm`; never cross-fade two cells. This is how iOS/Linear segmented controls feel
  premium. Keep it ~140–180ms at the larger size.
- **The Liquid Glass selection moment:** on commit, fire a **touch-point illumination** — a soft radial
  ember bloom from the click point that radiates outward and fades (the system's `.interactive()` glow),
  plus a tiny **scale 0.98→1 bounce** on the active element. One spring, one bloom — that's the delight.
- **Sun travel** (for slider/horizon concepts): animate sun **position + glow radius together**; let the
  glow lag the sun very slightly so light feels physical. Ease-warm in, never linear.
- **Glow as state, not decoration:** Sunset → glow eases *in* and warms; Always-on → glow is already
  full and steady. Animate the *difference* between the two glows during the switch.
- **Restraint rules:** one primary motion + one accent (slide + bloom, or sun-travel + glow). Stagger only
  if it clarifies. Respect `prefers-reduced-motion`: drop transforms/sun-travel, keep the instant state
  change and the final tint. (See `/design-motion-principles` — Emil's "motion should feel inevitable,"
  Krehel's spring discipline.)

---

## 5. Recommended directions to try (ranked, restrained → bold)

1. **Big segmented capsule, lit-glass thumb** — the baseline grown up: a large capsule track in clear
   `.glass`, the active half a `--sunset` lozenge with sheen + rim + `--glow-soft`, sliding on `--ease-warm`
   with a touch-bloom on commit. *Why:* lowest risk, unmistakably native + Liquid Glass, beats the baseline
   on size and delight alone. The safe winner.
2. **Choice tiles (mini-scenes)** — two side-by-side glass cards à la macOS Appearance: a **Sunset** tile
   showing a tiny sun-on-horizon over the `--sky` ramp, an **Always-on** tile showing steady warmth; selected
   tile lifts with ember glow + rim. *Why:* directly mirrors Apple's own either-or, *shows* the choice, and
   reads as the most "custom/artful" while still feeling system-native. Strongest all-rounder.
3. **Sky-track sun toggle** — one wide capsule whose fill is the `--sky` gradient; a glassy **sun thumb**
   slides from the **horizon** end (Sunset) to the **high/noon** end (Always on), glow easing in as it rises.
   *Why:* the metaphor and the control become one object; high delight, still legible with text labels under.
4. **Horizon switch** — a large switch where the thumb is a sun that drops to / sits on a drawn horizon line
   for Sunset and rides high for Always-on; track shifts dusk→day. *Why:* the most "toggle-native" way to honor
   the metaphor; charming, compact, very SwiftUI-friendly. Watch the on/off-implication caveat — label both ends.
5. **Day-arc selector** — a shallow arc (dawn→dusk) with the sun parked at dusk for Sunset and at apex for
   Always-on; clicking moves the sun along the arc on `--ease-warm`. *Why:* the most expressive *legible* idea;
   the "bold but not gimmicky" candidate. Higher build cost.
6. **Twin glow-orbs** — two large glass orbs/buttons side by side; Sunset's ember glow *pulses in* on select,
   Always-on's holds a steady full glow. *Why:* pares the whole idea down to "the light explains the mode";
   minimal, tactile, Family/Flighty-confident. Good contrast piece to the literal-scene tiles.
7. **(Bold, one-of) Half-clock dial** — a half-clock/dial where dusk is highlighted for Sunset and the full
   sweep for Always-on. *Why:* most distinctive, most risk (motion cost, small-size legibility); include only
   as the single "push it" concept, in glass, restrained.

**If I had to pick three to build:** **#2 (choice tiles)** for the artful, show-the-choice statement,
**#1 (big lit-glass capsule)** as the native safe winner, and **#3 (sky-track sun toggle)** as the
on-theme delight. Together they span restrained → expressive while all staying Liquid Glass + macOS-native.

---

### Sources
- [Apple — Apple introduces a delightful and elegant new software design (Liquid Glass)](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/)
- [WWDC25 — Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)
- [WWDC25 — Get to know the new design system (concentricity, capsule, control sizes)](https://developer.apple.com/videos/play/wwdc2025/356/)
- [conorluddy/LiquidGlassReference — glassEffect, .interactive(), tint, lensing](https://github.com/conorluddy/LiquidGlassReference)
- [MacSales — tenets of Liquid Glass in macOS Tahoe](https://eshop.macsales.com/blog/97650-blurry-or-beautiful-the-tweaks-and-tenets-of-apples-controversial-liquid-glass-design-in-macos-tahoe/)
- [Apple Support — Use a light or dark appearance on your Mac (Auto = sunset/sunrise)](https://support.apple.com/guide/mac-help/use-a-light-or-dark-appearance-mchl52e1c2d2/mac)
- [Apple Support — Use Night Shift on your Mac (Sunset to Sunrise schedule)](https://support.apple.com/en-us/102191)
- [Mobbin — Segmented Control best practices](https://mobbin.com/glossary/segmented-control)
- [UX Drill — Switches/Toggles vs. Segmented controls](https://medium.com/@designwithkabi/ux-drill-18-switches-toggles-vs-segmented-controls-b3fbc5ac811b)
- [AlternativeTo — Raycast v1.103 adopts Liquid Glass controls](https://alternativeto.net/news/2025/9/raycast-v1-103-0-implements-liquid-glass-controls-and-comet-browser-support/)
- [Webtips — Animated day/night toggle (complexity spectrum)](https://webtips.dev/how-to-make-an-animated-day-and-night-toggle-switch)
- [James Robinson — A guide to dark mode design (warm/cool time-of-day)](https://www.jamesrobinson.io/post/a-guide-to-dark-mode-design)
