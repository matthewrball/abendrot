# Abendrot — Messaging & Campaigns (reusable campaign material)

> **Companion to `docs/marketing/evidence-base.md`** — which is the single source of truth for every
> science claim. **Every science claim in this file traces to a claim or citation in the evidence
> base. Do not add a science claim here that is not grounded there.** If you are tempted to, stop and
> add it to the "❓ Needs founder/legal review" list at the bottom instead.
>
> **Binding guardrails (from `evidence-base.md` §"four launch-critical guardrails" + plan §13 + FTC):**
> 1. **Couple warmth with brightness.** Never imply warmth alone delivers the circadian benefit.
>    Always pair "removes blue light" with "and lower your brightness."
> 2. **Red is circadian-SPARING / low-melanopic, NEVER red-light-therapy / photobiomodulation.**
>    This is an imagery guardrail too, not just a wording one.
> 3. **Never juxtapose a product claim with sleep-latency / melatonin data** (it implies a sleep
>    benefit our own cited RCT — Duraccio 2021 — failed to find). Keep product claim and citation in
>    separate breaths.
> 4. **Precise spectral/CCT numbers are illustrative standard-curve modeling, not measured product
>    output.** Never say "Abendrot reduces your melanopic exposure by X%."
>
> **Banned phrases (non-exhaustive, see evidence-base "⛔ DO NOT CLAIM"):** "clinically proven",
> "proven to improve sleep", "cures/treats insomnia", "improves sleep" (as a promised outcome),
> "blue light damages your eyes", "cures/prevents eye strain", "lower Kelvin = more protective"
> (as a guarantee), "red light therapy", "zero circadian effect / circadian-inert".
>
> Last updated 2026-06-17.

---

## 1. Positioning & value proposition

### One-line positioning statement
**Abendrot is the free, open-source Mac app that warms the color temperature of *every* display — including the buttonless Apple panels f.lux and Night Shift quietly fail on — with zero telemetry and every line of code open to read.**

### Elevator pitch (2 sentences)
Abendrot is a tiny, native macOS menu-bar app that warms your screen's color temperature across all your displays in the evening — built-in *and* external, including the Apple Studio Display, Pro Display XDR, and LG UltraFine, where Night Shift and f.lux can do nothing. It's free forever, fully open source with no telemetry, and at its warmest everyday setting it removes the display's blue output entirely — the wavelength band the body's clock is tuned to detect.

### Longer paragraph
Most "warm your screen" tools were built for one display and one generation of Mac. Apple's Night Shift skips most external monitors (and tints others pink); f.lux and the other gamma-based apps silently do nothing on the newest Apple Silicon and can't touch buttonless Apple displays at all. Abendrot was built the other way around: it tries real hardware and white-point warming first, falls back gracefully, and tells you — per display — exactly which method is in use, so it never silently no-ops. The science it leans on is narrow and honest: the wavelengths that matter most to the circadian system at night are in the blue (~459–490 nm) [Brainard 2001; Thapan 2001; CIE S 026:2018], and that is exactly the band Abendrot's warming attenuates first — blue output reaches zero at approximately 1900K. It does *not* dim, so for the evening light habits the research describes, you'll want to lower your brightness too. Abendrot is general-wellness, not a medical device: it links the peer-reviewed research rather than asserting outcomes, ships with no account and no tracking, and is MIT-licensed so you can audit every line.

**Why this is the true, differentiating lead (all grounded):**
- Warms **every** display incl. buttonless Apple panels (UltraFine / Studio Display / Pro Display XDR) — plan §2.2, §25 part 2: gamma + the CoreDisplay white-point path warm these where DDC physically cannot, and where Night Shift / f.lux fail.
- **Open-source, MIT, zero telemetry by default** — plan §2.2, §3, §11.
- **Zero blue-light emission at its warmest everyday setting (~1900K)** — evidence base Approved Claim #1 ("blue output reaches zero at approximately 1900K"). *Caveat:* "everyday warmest" = the ~1900K floor where blue is fully removed; the slider can go warmer (candle range) but that only removes residual green and costs legibility (evidence base, engineering footnote; plan §25 directives).
- Always pair the blue-removal line with **"and lower your brightness"** (Guardrail 1).

---

## 2. Brand voice

Calm, honest, anti-hype, evidence-led, privacy-respecting. The app should feel like dusk: warm, quiet, premium, trustworthy (plan §1, §5.1). We invite rather than warn; we cite rather than assert.

### Voice rules
1. **Cite, don't assert.** Name the mechanism and link the paper; never claim the downstream health outcome. ("Research identifies the blue band as the dominant circadian input [Brainard 2001]" — not "Abendrot fixes your sleep.")
2. **Always couple blue-removal with brightness.** Any sentence about evening light benefit pairs "removes blue" with "lower your brightness too." Warmth alone is not the whole story (Guardrail 1; Zeitzer 2000).
3. **Speak in melanopic terms, not Kelvin guarantees.** Kelvin is a convenient label, not a circadian proxy — melanopic content is what matters (Esposito & Houser 2022). Never say "lower Kelvin = more protective."
4. **Red is sparing, not therapy.** Warm/red light is "circadian-sparing / low-melanopic," never photobiomodulation or "red-light therapy." Holds for imagery too — no clinical/treatment visual cues (Guardrail 2).
5. **No medical claims, no hype punctuation.** No "clinically proven," "cures," "treats." No exclamation marks, no growth-hack CTAs, no urgency (plan §5.1).
6. **Lead with what's verifiable.** Reliability on every display, open source, no telemetry — these are demonstrable. Health is the *story*; reliability is the *proof* (plan §2.3).

### Say this / not that
| Say this | Not that |
|---|---|
| "Reduces your screen's blue-light output at night — and lower your brightness too." | "Improves your sleep." / "Helps you fall asleep faster." |
| "Warm/red light is circadian-sparing — it puts far less energy in the blue band the body clock detects." | "Red-light therapy for better rest." / "Healing red light." |
| "Research links short-wavelength blue light to nighttime melatonin regulation [Brainard 2001]." | "Blue light damages your eyes." |
| "An open-source app that warms every display; audit the code yourself." | "Clinically proven screen warming." |
| "Melanopic content — not the Kelvin number — is what matters; we remove the blue." | "Lower Kelvin means more protection." |
| "Supports healthy evening light habits." | "Treats insomnia / cures eye strain." |
| "At ~1900K the display's blue output reaches zero (illustrative of the warming curve)." | "Abendrot cuts your melanopic exposure by X%." |

---

## 3. Taglines (all §13-safe)

**Canonical brand descriptor (founder pick, 2026-06-18 — use for GitHub About, meta titles, README lead, directory listings):**
> **Abendrot — a macOS app for your circadian rhythm.**
>
> Positioning, not a health-outcome claim (keep the "general wellness, not medical" framing nearby). This descriptor drops the "every display" differentiator, so always carry the moat in the adjacent line/subhead (e.g. "warms your screen on every display"). The evocative line (#2 below) stays the emotional hero.

1. ⭐ **Warm every display. Read every line.** *(reliability + open-source, the two demonstrable truths)*
2. ⭐ **Your screen, warming with the evening — on every display.** *(plan §1 north star, no health overclaim)*
3. ⭐ **The warmth app that still works on your newest Mac.** *(plan §2.2 #5; grounded in §25: gamma/white-point warm where f.lux silently fails)*
4. Less blue at night. Lower your brightness too. *(bakes Guardrail 1 into the tagline itself)*
5. Real warmth, every monitor — including the ones Night Shift skips.
6. Open source. No telemetry. No account. Just warmth.
7. Soften into the evening.
8. Built-in or external — warmth that doesn't quietly give up.
9. The blue is what the body clock notices. We turn it down.
10. Reveal true color the moment you need it.
11. A tiny, native Mac app that warms the whole desk.
12. Warmth you can audit.

**Top 3:** #1 *Warm every display. Read every line.* · #2 *Your screen, warming with the evening — on every display.* · #3 *The warmth app that still works on your newest Mac.*

---

## 4. Website copy blocks

### Hero headline + subhead — 3 options

**Option A (reliability-led — best for Show HN / PH / designer audience)**
> # Warmth that works on every display.
> A tiny, open-source Mac app that warms your color temperature across all your monitors — built-in and external, including the Apple displays Night Shift and f.lux can't touch. Free forever, no telemetry, lower your brightness too.

**Option B (circadian-story-led — best for the brand site)**
> # Your Mac's screen warms with the evening. On every display.
> Less blue light at night across all your monitors — and a hold-to-reveal hotkey for true color the instant you need it. Open source, runs entirely on your Mac. Pair it with lower brightness.

**Option C (open-source-trust-led)**
> # Screen warmth you can actually read the code for.
> Free, MIT-licensed, zero-telemetry color warming for every Mac display — including buttonless Apple panels. We tell you, per display, exactly how each one is being warmed.

### "How it works" — 3 short blurbs

**1 — Warms every display, the right way per screen.**
Abendrot tries real white-point and gamma warming first, with hardware (DDC) as an opt-in upgrade and a universal overlay as the floor — then shows you which method each display is using. No silent no-ops, including on buttonless Apple displays where other tools can do nothing.

**2 — Turns the blue down where it counts.**
Warming attenuates the display's blue primary first; by approximately 1900K the blue output reaches zero — and blue (~459–490 nm) is the band research identifies as the dominant circadian input [Brainard 2001; Thapan 2001; CIE S 026:2018]. For the evening light habits the science describes, lower your brightness alongside the warmth.

**3 — Reveal true color, instantly.**
Hold the hotkey to suspend warmth across every display for color-critical work; release and the warmth eases back. Designed for designers and photographers — no incumbent does this well across external monitors.

### "The Science" section copy (hedged, links the citation library)

> **A short, honest note — general wellness, not medical advice.**
>
> Your body has a third kind of light sensor in the retina — melanopsin-containing ipRGCs — that helps set your internal clock, and it is most sensitive to blue light around 480 nm [Berson 2002; Bailes & Lucas 2013]. The two foundational human studies of how evening light affects melatonin both point to the blue band (~459–464 nm) [Brainard 2001; Thapan 2001], and a controlled display study found it's the *melanopic* (short-wavelength) content of screen light — not its brightness or color appearance — that drives the effect [Schoellhorn 2023]. Abendrot is built to lower that blue content: its warming attenuates the blue primary, reaching zero blue at about 1900K.
>
> Two honest caveats we keep visible. First, **the dose matters as much as the color**: even moderate light suppresses melatonin, and the effect saturates surprisingly low [Zeitzer 2000], so warming helps most when you *also lower your brightness*. Second, **people vary enormously** — evening-light sensitivity differs more than 50-fold between individuals [Phillips 2019] — which is why Abendrot gives you an adjustable slider instead of one "correct" setting. Warm/red light is *circadian-sparing* (it puts little energy in the blue band the clock detects [Figueiro & Rea 2010]) — that's a low-melanopic property, not a "red-light therapy" health claim.
>
> We link the research instead of promising outcomes. → **[Read the citation library →]** *(links to `evidence-base.md` / the site's science references)*

### Privacy / open-source block

> **No account. No tracking. No telemetry by default. Read every line.**
>
> Abendrot runs entirely on your Mac. There's no sign-in, no cloud, and no analytics unless you explicitly opt in — it's off by default, anonymous and aggregate when on, and the app works fully if you decline. It's MIT-licensed and the full source is public, so you don't have to take our word for any of this: audit the code, build it yourself, or just read how the warmth engine works. The anti-telemetry-vacuum.

### FAQ (honest answers, 8 items)

**Does Abendrot work on external monitors?**
Yes — that's the point. It warms built-in and external displays, including buttonless Apple panels (Studio Display, Pro Display XDR, LG UltraFine) that don't expose hardware controls, where Night Shift and f.lux often do nothing. It shows you per display which warming method is active.

**Does it work on the newest Apple Silicon Macs?**
Yes. Several gamma-based warming tools silently stopped working on the latest Macs; Abendrot uses warming paths (including Apple's own white-point mechanism) that still warm those machines, and falls back to a universal overlay if needed — and it's honest in-app when a particular display can only be tinted, not truly warmed.

**Will this improve my sleep?**
We won't claim that — and we'd be suspicious of anyone who does. A randomized real-world study found no measurable sleep difference from a software blue-reduction mode [Duraccio 2021]. What Abendrot *demonstrably* does is reduce your screen's blue-light output at night. For the evening light habits the research describes, also lower your brightness.

**What does "removes blue light" actually mean?**
As you warm the display, Abendrot turns down its blue primary; by about 1900K the blue output reaches zero. Blue (~459–490 nm) is the band research identifies as the dominant input to the circadian system [Brainard 2001; Thapan 2001; CIE S 026:2018]. (The exact spectral numbers are standard-curve illustrations, not a measurement of your specific screen.)

**Is warmer (lower Kelvin) always better?**
Not as a rule. Kelvin isn't a reliable proxy for biological potency — melanopic content can vary roughly two-fold at the same color temperature [Esposito & Houser 2022]. Once the blue is gone (~1900K), going warmer mostly removes residual green and costs legibility. Pick what's comfortable; we don't promise that a lower number is "more protective."

**Is the warm/red look "red-light therapy"?**
No — and we're careful here. Warm/red light is *circadian-sparing*: it puts very little energy in the blue band the body clock detects [Figueiro & Rea 2010; CIE S 026:2018]. That's a low-melanopic property. It is **not** the same thing as "red-light therapy" / photobiomodulation health claims, which are a separate and far weaker evidence base. Abendrot makes no therapy claims.

**Does it need permissions or send any data?**
No special permissions for core warming, and no telemetry by default — no account, no tracking, runs locally. Optional anonymous usage stats are off by default and the app works fully without them.

**Is it really free, and can I see the code?**
Free forever, MIT-licensed, fully open source. No paywall, no "pro" tier gating the warmth. Read every line, file issues, or build it yourself.

---

## 5. Social launch campaign

> **⚠️ FOUNDER-GATED — DO NOT POST.** Every external post below (X/Twitter, Mastodon, LinkedIn, Show HN,
> Reddit) is **drafted only**. Posting, the public repo re-publish, and any live announcement are
> explicit founder gates (plan §22, §23). These are ready-to-use drafts, not scheduled content.

### X / Twitter (launch announcement)
> Abendrot is out: a free, open-source macOS menu-bar app that warms color temperature on **every** display — including the buttonless Apple panels (Studio Display, Pro Display XDR, UltraFine) where Night Shift & f.lux do nothing.
>
> No telemetry. No account. Read every line.
> Hold a hotkey to reveal true color instantly. ↓ [link]

### Mastodon (launch announcement)
> New: **Abendrot** — a tiny, native, MIT-licensed macOS app that warms your screen's color temperature across all your displays in the evening, built-in and external.
>
> It removes the display's blue output as it warms (blue ~459–490 nm is the band the circadian system is tuned to — pair it with lower brightness). Zero telemetry, runs entirely on your Mac, source is public. General wellness, not a medical device — we link the research, we don't overclaim.
>
> #macOS #opensource #buildinpublic [link]

### LinkedIn (launch announcement)
> I built Abendrot — a free, open-source macOS app that warms your display color temperature across every monitor you own, including the buttonless Apple displays that Night Shift and f.lux can't reliably warm.
>
> Three things I care about with it:
> • **Reliability:** it warms built-in and external displays and tells you, per display, exactly how — never silently doing nothing.
> • **Privacy:** zero telemetry by default, no account, MIT-licensed, fully auditable.
> • **Honesty:** it's general wellness, not a medical device. It reduces your screen's blue-light output at night (and you should lower brightness too) — it links peer-reviewed research instead of promising better sleep.
>
> Free forever. [link]

### Hacker News — "Show HN" blurb (technical, non-salesy)
> **Show HN: Abendrot – open-source macOS app that warms color temp on every display**
>
> Abendrot is a native Swift menu-bar app (MIT) that warms display color temperature across all connected displays. The motivating problem: gamma-based tools (f.lux, etc.) silently no-op on some recent Apple Silicon Macs, Night Shift skips/mis-tints many externals, and buttonless Apple displays (Studio Display, Pro Display XDR, UltraFine) expose no DDC controls at all.
>
> Approach: a layered engine that picks the best working method per display — Apple's CoreDisplay white-point shift / gamma table for a true white-point warm, optional hardware DDC RGB-gain as an upgrade on capable externals, and a Metal overlay as a universal floor — and reports which method each display is using instead of pretending. No privileged helper; no Accessibility permission; no telemetry by default.
>
> On the health framing: I've tried hard not to overclaim. The honest statement is "reduces blue-light output at night" (warming attenuates the blue primary, ~zero blue near 1900K), not "improves sleep" — a real RCT found no measurable sleep benefit from software blue reduction [Duraccio 2021]. The science panel links primary sources rather than asserting outcomes. Happy to get into the engine internals, the private-API gating, or the evidence base.
>
> Repo + .dmg: [link]

### Reddit r/macapps (technical, non-salesy)
> **[Free / Open Source] Abendrot — warms color temperature on every display, including buttonless Apple monitors**
>
> Author here (disclosing). I made Abendrot because Night Shift skips most of my external monitors and the gamma-based tools either tint pink or do nothing on newer Macs — and nothing reliably warms a Studio Display / Pro Display XDR / UltraFine, which expose no hardware color controls.
>
> What it does:
> - Warms built-in + external displays; picks the best working method per display (white-point / gamma / hardware DDC / overlay floor) and shows you which one is active.
> - Hold-to-"Reveal True Color" hotkey for color-critical work.
> - Menu-bar only, native Swift, MIT-licensed, no telemetry by default, no account.
>
> On health: it reduces your screen's blue-light output at night (pair it with lower brightness) — I deliberately don't claim it improves sleep. Science panel links the actual papers.
>
> Feedback very welcome, especially from anyone on a Studio Display or a newer Apple Silicon Mac. Repo + download: [link]

### 5-post educational thread outline (each post grounded in a specific cited fact)

> Tone: calm, factual, no product hard-sell until the final post. Each post = one cited fact. Founder-gated.

1. **The third light sensor.** Beyond rods and cones, your retina has melanopsin-containing ipRGCs — a distinct photoreceptor that helps set your circadian clock, most sensitive to blue light around 480–484 nm. *(Berson 2002; Bailes & Lucas 2013; Provencio 2000)*
2. **Why *blue* specifically.** The two foundational human studies of evening light and melatonin both land in the blue: peaks around 464 nm and 459 nm, most potent ~446–477 nm. *(Brainard 2001; Thapan 2001)*
3. **It's the melanopic content, not the brightness label.** A controlled display study showed the melanopic (short-wavelength) content of evening screen light — independent of luminance and color appearance — drives the effect on melatonin. *(Schoellhorn 2023)*
4. **But dose still matters — so dim, too.** Melatonin suppression saturates surprisingly low (half-maximal at only ~50–130 lux); the biggest win is leaving the bright, blue-rich zone — which means lowering brightness, not just warming color. *(Zeitzer 2000)*
5. **No single setting fits everyone.** Evening-light sensitivity varies more than 50-fold between people, so there's no universal "correct" warmth — which is why a slider, not a fixed number. *(Closing post: this is why Abendrot is adjustable, open source, and links the research instead of promising outcomes.)* *(Phillips 2019)*

> **Thread compliance note:** Posts 3 and 4 mention melatonin/sleep-latency science as *general* background — keep them in separate breaths from any "Abendrot does X" product sentence (Guardrail 3). The product mention lives only in post 5's closing line, framed as "adjustable + links the research," not "improves your sleep."

---

## 6. SEO

### Keyword targets

**Primary:**
- warm all monitors mac
- f.lux alternative apple silicon
- night shift external monitor
- reduce blue light external display mac
- warm color temperature studio display / pro display XDR / LG UltraFine

**Secondary:**
- open source f.lux alternative mac
- night shift not working external monitor
- screen warmth app mac open source
- warm screen mac no telemetry
- blue light reduction mac external monitor
- night shift M5 / Apple Silicon not warming
- reveal true color hotkey mac / momentary disable warmth
- menu bar screen dimmer warmth mac

### Meta-description options (3)
1. *Abendrot is a free, open-source macOS app that warms color temperature on every display — built-in and external, including Apple panels Night Shift and f.lux can't reliably warm. No telemetry, MIT-licensed.* (≈195 chars)
2. *Warm your Mac's screen across all monitors, including buttonless Apple displays. Open source, zero telemetry, reduces blue-light output at night. Free forever.* (≈158 chars)
3. *The open-source f.lux alternative for Apple Silicon: warms every external display, reveals true color on a hotkey, and links the research instead of overclaiming.* (≈162 chars)

### Title-tag patterns
- `Abendrot — Warm Every Display on macOS | Free & Open Source`
- `{Primary keyword} — Abendrot` (e.g. `Warm All Monitors on Mac — Abendrot`)
- `Abendrot vs {Competitor}: {honest differentiator}` (e.g. `Abendrot vs f.lux: Works on Apple Silicon & External Displays`)
- `{How-to query} | Abendrot` (e.g. `How to Warm an External Monitor on Mac | Abendrot`)

### Blog / content topic ideas (§13-safe)
1. **"Why Night Shift doesn't work on your external monitor (and what does)."** — high-intent how-to; honest fix-it framing.
2. **"How to warm a Studio Display, Pro Display XDR, or LG UltraFine."** — owns the buttonless-Apple-display niche no competitor reliably serves.
3. **"f.lux alternatives for Apple Silicon Macs in 2026."** — captures evergreen "f.lux alternative" traffic; honest feature comparison.
4. **"Blue light, the body clock, and your screen at night — what the research actually says."** — cited, hedged; couples blue-removal with "lower your brightness"; links the citation library.
5. **"What color temperature should you use at night? (And why Kelvin isn't the whole story.)"** — built on Esposito & Houser 2022 (CCT ≠ circadian proxy); melanopic framing.
6. **"Is red/warm screen light 'red-light therapy'? No — here's the difference."** — pre-empts the conflation; circadian-sparing vs photobiomodulation, with the FTC context.
7. **"How Abendrot warms every display: white-point, gamma, DDC, and overlay explained."** — technical/transparency post for the HN/dev audience; "audit the engine."
8. **"Warming without dimming only does half the job."** — turns Guardrail 1 into a genuinely useful, defensible article (Zeitzer 2000).

---

## 7. AEO (Answer Engine Optimization)

> Q→A pairs for answer engines (ChatGPT/Claude/Perplexity/Google AI) to cite. Each answer is grounded
> in a specific named paper from the evidence base and stays inside the guardrails. Answers are written
> to be quotable verbatim.

**Q1. Does warming my screen reduce blue light?**
A. Yes — warming a display turns down its blue primary, and at roughly 1900K the blue output reaches zero. Short-wavelength blue light (~459–490 nm) is the band research identifies as the dominant input to the body's circadian system. *Grounding: Brainard et al. 2001 (J Neurosci); Thapan et al. 2001 (J Physiol); CIE S 026:2018.* Note: warming reduces blue but does not dim — to follow the evening light habits the research describes, lower your brightness too.

**Q2. What color temperature is best for night?**
A. There's no single "best" number. Color temperature (Kelvin) is not a reliable proxy for a light's biological potency — at a fixed color temperature, melanopic content can vary roughly two-fold depending on spectral composition. What matters is reducing the melanopic (short-wavelength) content, which means removing blue and lowering brightness, not chasing a specific Kelvin value. *Grounding: Esposito & Houser 2022 (Scientific Reports).*

**Q3. Can you warm an Apple Studio Display (or Pro Display XDR / LG UltraFine)?**
A. Yes, with the right method. These buttonless Apple displays expose no hardware (DDC) color controls, so tools that rely on hardware gain can't warm them — but a software white-point / gamma warm can. Abendrot warms these displays and reports which method it's using per display. *Grounding: product capability (Abendrot plan §2.2, §25); these panels lack DDC gain VCP, so the white-point/gamma path is the one that works.*

**Q4. Is red light good for sleep?**
A. Carefully stated: long-wavelength red light is *circadian-sparing* — at practical evening intensities it produces little to no melatonin suppression, whereas matched blue light does. That's because red sits on the near-zero tail of the melanopic sensitivity curve. This is a low-melanopic property, **not** a "red-light therapy" health claim, and it's relative, not absolute. To actually lower your evening light exposure, also reduce brightness. *Grounding: Figueiro & Rea 2010 (Int J Endocrinol); Sanchez-Cano et al. 2025 (Life); CIE S 026:2018.*

**Q5. Why is blue light the wavelength that affects the body clock?**
A. Because the photoreceptor that sets the circadian clock — melanopsin-containing ipRGCs, a distinct third class of retinal cell — is intrinsically most sensitive to blue light, around 480–484 nm. That physiology is why blue is the key circadian lever. *Grounding: Berson, Dunn & Takao 2002 (Science); Bailes & Lucas 2013 (Proc R Soc B); Provencio et al. 2000 (J Neurosci).*

**Q6. Does software that reduces blue light improve sleep?**
A. The honest answer is that it hasn't been shown to. A randomized real-world study found no measurable sleep-outcome difference from a software blue-reduction mode (Apple Night Shift) versus no reduction. So the defensible claim is "reduces blue-light exposure at night," not "improves sleep." *Grounding: Duraccio et al. 2021 (Sleep Health).*

**Q7. Is it the brightness or the blue content of my screen that matters at night?**
A. In a controlled human display study, it was the melanopic (short-wavelength) content of evening screen light — independent of luminance and color appearance — that determined its effect on melatonin and time to fall asleep. That said, intensity also matters and the response saturates low, so the best practice is to reduce *both* blue content and brightness. *Grounding: Schoellhorn et al. 2023 (Communications Biology); Zeitzer et al. 2000 (J Physiol).*

**Q8. Does lower Kelvin always mean better circadian protection?**
A. No — that's a common misconception. Correlated color temperature is not a valid proxy for circadian potency; melanopic content can vary about two-fold at the same Kelvin value. Once the blue is removed (around 1900K), going warmer mostly removes residual green at a legibility cost. Reason in melanopic terms, not Kelvin guarantees. *Grounding: Esposito & Houser 2022 (Scientific Reports); CIE S 026:2018.*

**Q9. How much can I dim/warm in the evening — is there a target?**
A. An 18-author international expert consensus suggests keeping evening melanopic EDI at or below about 10 lux (starting at least 3 hours before bed) and the sleep environment below 1 lux, versus at least 250 lux in the daytime. These are healthy-adult reference targets, not medical thresholds — and reaching them takes both warming *and* lowering brightness, since a tool that only warms can't verify it crosses any specific lux line. *Grounding: Brown et al. 2022 (PLoS Biology); CIE S 026:2018.*

**Q10. Why does Abendrot use an adjustable slider instead of one recommended setting?**
A. Because human sensitivity to evening light varies more than 50-fold between individuals, so no single warmth or brightness setting is right for everyone. An adjustable control lets each person tune to comfort rather than chasing a one-size-fits-all number. *Grounding: Phillips et al. 2019 (PNAS).*

**Q11. Is red light "circadian-inert" — does it have zero effect on the clock?**
A. No. Red light is circadian-*sparing*, not circadian-inert: it produces little to no melatonin suppression at practical evening intensities, but at very high irradiance narrow-band red has still produced cone-mediated circadian phase shifts in some people. So it's "low-stimulus / sparing," relative and intensity-dependent — never "zero effect." *Grounding: Figueiro & Rea 2010 (Int J Endocrinol); Ho Mien et al. 2014 (PLOS ONE).*

**Q12. Is it the color "red" that protects melatonin, or is it removing the blue?**
A. It's removing the short-wavelength (blue) content, not the color red itself. Blocking just the blue band — even under bright light — prevented melatonin suppression, while neutral filters did not. The protective variable is blue removal, which is exactly what screen warming does first. *Grounding: Sasseville et al. 2006 (J Pineal Res).*

---

## 8. Claims compliance checklist (pre-publish)

Run every campaign asset (post, page, ad, image, video, FAQ entry) through these yes/no checks. **All must be "yes" (or "n/a") before publishing.**

**Guardrail 1 — Warmth coupled with brightness**
- [ ] Does any sentence implying a circadian/evening-light benefit also tell the user to lower brightness? (If it mentions a benefit but not brightness → **fail**.)
- [ ] Have we avoided implying that warmth *alone* delivers the benefit?

**Guardrail 2 — Red is circadian-sparing, not therapy**
- [ ] Is every red/warm-light reference framed as "circadian-sparing / low-melanopic," with no "therapy," "treatment," "healing," "photobiomodulation," or clinical implication — **in words AND imagery**?
- [ ] Do any visuals (red glow on skin/face, clinical/medical cues, treatment-device aesthetics) risk implying red-light therapy? (If yes → **fail**.)

**Guardrail 3 — Separate product claims from sleep/melatonin data**
- [ ] Is every "Abendrot does X" product sentence kept in a separate breath from any melatonin / sleep-latency / sleep-onset finding (no adjacency implying a sleep benefit)?
- [ ] Have we avoided promising "improves sleep" / "fall asleep faster" as an outcome?

**Guardrail 4 — Numbers are illustrative, not measured output**
- [ ] Are any spectral/CCT/percentage figures labeled as standard-curve illustrations (not "Abendrot reduces your melanopic exposure by X%")?
- [ ] Have we avoided presenting self-derived display M/P splits as peer-reviewed fact?

**Banned-phrase sweep**
- [ ] No "clinically proven," "cures/treats insomnia," "improves sleep" (as promise), "blue light damages your eyes," "cures/prevents eye strain," "lower Kelvin = more protective" (as guarantee), "red-light therapy," "zero circadian effect / circadian-inert."

**Grounding check**
- [ ] Does every science claim trace to a specific claim or paper in `evidence-base.md`? (If you can't name the source → don't publish; add it to the review list below.)

**External-post gate**
- [ ] Is this asset cleared by the founder for posting? (All external posts are founder-gated; default is **do not post**.)

---

## ❓ Needs founder / legal review

Items I deliberately did **not** state as fact because they're outside `evidence-base.md`'s grounding, or carry guardrail risk. Resolve before using in any asset.

1. **"Notarized" / "signed" trust language.** Plan §22 notes signing is *deferred* (no Apple Developer Program purchased yet); current builds may be unsigned/local. Don't hard-claim "notarized" until credentials are supplied. Use only the verifiable trust claims ("open source, auditable, no telemetry by default"). — *Needs: confirm signing/notarization status before any trust copy ships.*
2. **Specific RAM / bundle-size / "0% idle CPU" proof badges** (plan §10 lists `< 5 MB`, `~20 MB RAM`, `0% idle CPU`). These are real-number boasts that must be measured on the shipping build before publishing — I left exact figures out of the copy. — *Needs: measured numbers from the release build.*
3. **"Warms the newest Macs where f.lux can't" as a head-to-head claim.** Grounded in §25 (gamma/white-point warm base M5; f.lux's gamma path no-ops on M5 Pro/Max), but it's a competitor comparison and the gamma no-op is chip/OS-specific. Safe as stated ("still works on your newest Mac"); flag if we want to name f.lux directly in a comparison ad. — *Needs: founder OK on naming competitors in paid/comparison contexts + confirm the chip/OS matrix (§25 directive 4 testing).*
4. **Reaching the Brown 2022 ≤10 lux mEDI target.** The evidence base explicitly warns the app *cannot verify* it crosses any specific lux line (no luminance control / no mEDI measurement). I cite the targets as general reference only and never imply Abendrot reaches them — keep it that way. — *Needs: no action unless someone tries to claim compliance; flagged so they don't.*
5. **Exact "everyday warmest setting = zero blue" wording.** Grounded (~1900K = zero blue, Approved Claim #1), but §25 founder directive pushes the slider's max much warmer (~1500K candle range) for feel. Ensure marketing "warmest everyday setting" maps to the ~1900K *zero-blue* point, not the candle extreme (which only removes residual green and hurts legibility). — *Needs: confirm final default/clamp wording matches shipped slider.*
6. **Press/social-proof logos, star counts, download counts, PH/HN badges** (plan §10) — all "as earned," none real yet. Placeholders only. — *Needs: real metrics post-launch.*

---

## 9. Developer / AI-control positioning lane (capability story — NOT a health lane)

> **Scope guardrail for this section.** This is a **pure capability lane**: "Abendrot has a CLI; you can
> script screen warmth from the terminal; AI assistants can drive it." Every line here is verifiable by
> the binary existing — it does **not** add, alter, or sit adjacent to any circadian/sleep/melatonin
> claim. Keep this lane and the science lane in separate breaths (it inherits Guardrail 3 by simply not
> entering the health story at all). Where this lane mentions warmth, it's a *mechanical* statement
> ("set warmth to 0.8", "warmest point of the slider"), never a benefit promise.
>
> **Status (updated 2026-06-21):** the v1 CLI is **shipped and open-source** — `abendrot` is in the public
> repo (`github.com/matthewrball/abendrot`, CI green) and buildable from source today. A **signed
> one-command install** (Homebrew cask, notarized DMG) lands with **v1.0**. So: list the CLI as a real,
> available feature, with the signed install as the only "coming soon" note. **Do NOT market an MCP server
> or any other unshipped/forthcoming feature in public copy — leave it off entirely** (founder directive, 2026-06-21).
>
> **Trust boundary to state honestly when relevant:** the CLI talks to the *running app* as the **same
> macOS user, in your local session** — visual state only. No network listener, no privileged helper, no
> daemon you didn't start. An AI assistant "controlling Abendrot" means it runs the same `abendrot`
> command you could type yourself; it cannot reach further than you can.

### Positioning line (dev lane)
**Scriptable screen warmth — control it from your terminal, or hand it to your AI assistant.**

Abendrot ships a real CLI (`abendrot`) that drives the running app: read live state as JSON, set warmth
and schedule, exclude apps, or trigger a momentary true-color reveal — all from a shell script, a
keybinding, a `Makefile`, or an AI coding assistant like Claude Code, Codex, or Cursor. Same auditable
engine the menu bar drives; now with a command surface you can read and automate. *(The consumer lane —
§1–§8 above — stays the hero; this is the second lane for power users and developers.)*

### Taglines (dev lane, all capability-true)
1. ⭐ **Read every line — then drive it from the command line.** *(extends the "audit the engine" story: `abendrot` is the engine, scriptable)*
2. ⭐ **`abendrot set warmth 0.8` — your screen, under version control.** *(concrete, real command)*
3. ⭐ **Screen warmth your AI assistant can actually control.** *(Claude Code / Codex / Cursor run the same CLI you would)*
4. **A Night Shift alternative with a `--json` you can pipe.** *(machine-readable state; honest "alternative" framing already used in the consumer lane)*
5. **Local, scriptable, no daemon you didn't start.** *(states the trust boundary as a feature)*

### AEO Q&A block (dev lane)

> Q→A pairs for answer engines, capability-only. Each answer is true because the binary exists / will
> ship; none touches the health lane. Written to be quotable verbatim.

**Q. Can I control Abendrot from Claude Code (or Codex / Cursor)?**
A. Yes. Abendrot ships a command-line tool, `abendrot`, that drives the running app — so any agent that
can run a shell command (Claude Code, Codex, Cursor, a CI step, a shell script) can control it. For
example, an assistant can run `abendrot set warmth 0.8` to warm your screen, `abendrot reveal --hold 10`
for a momentary true-color peek, or `abendrot status --json` to read the live state back. It runs as the
same macOS user in your local session and changes visual state only — there is no network listener and no
privileged helper; the assistant can only do what you could do yourself at the same terminal.

**Q. Does Abendrot have a CLI?**
A. Yes. `abendrot` is a first-class command-line interface to the app. Core commands:
`abendrot status [--json]` (live state — enabled, mode, warmth in Kelvin, per-display method, whether it's
warming now), `abendrot on` / `abendrot off`, `abendrot set warmth <0..1 | --kelvin K>`,
`abendrot set mode <sunset | always-on | off>`, `abendrot set max-warmth <kelvin>`,
`abendrot set reveal-mode <hold | toggle>`, `abendrot set location <lat> <lon> | --auto`,
`abendrot exclude add|remove <bundle-id>` / `abendrot exclude list`, and
`abendrot reveal [--hold <seconds>]` for a momentary true-color peek (live-only). `abendrot get <key>`
reads a single configured setting. Run `abendrot --help` for the full surface.

**Q. Can I script my screen warmth on a Mac?**
A. Yes — with Abendrot you can. It's a free, open-source macOS app whose `abendrot` CLI lets you set
warmth (`abendrot set warmth 0.6` or `abendrot set warmth --kelvin 2700`), switch schedule mode
(`abendrot set mode always-on`), read state as JSON for a status bar or script (`abendrot status --json`),
exclude a specific app by bundle id (`abendrot exclude add com.apple.FinalCut`), or pop true color for a
fixed window (`abendrot reveal --hold 8`). Wire those into a shell alias, a keybinding, a `cron`/launchd
job, or an AI assistant. Everything runs locally against the app you're already running.

**Q. Is letting an AI assistant control my screen warmth safe?**
A. The surface is deliberately small. `abendrot` only adjusts Abendrot's own visual warming state on the
machine you're sitting at — it runs as the same macOS user, in your local session, with no network
listener and no privileged/root helper. An assistant "controlling Abendrot" is just running the same
`abendrot` command you could type; it can warm your screen or read status, and nothing beyond that. And
because the whole engine is open source, you can read exactly what each command does.

### SEO keyword list (dev lane)
- `abendrot cli`
- `control screen warmth from terminal mac`
- `claude code screen warmth`
- `scriptable night shift alternative`
- `mac color temperature api`

*(Secondary / long-tail, capability-true: `abendrot status --json`, `set screen warmth command line mac`,
`ai assistant control mac display`, `automate blue light reduction mac`, `script night shift mac`,
`mac warmth cli homebrew`.)*

### Dev-lane compliance note
This lane is capability-only by construction. Before publishing any dev-lane asset, still run it through
the §8 checklist — the relevant lines are the **banned-phrase sweep** (no health verbs sneaking into a
"set warmth" sentence) and **Guardrail 3** (keep these capability sentences out of adjacency with any
sleep/melatonin finding). Do NOT mention an MCP server or any other unshipped/forthcoming feature in public copy — leave it off.
