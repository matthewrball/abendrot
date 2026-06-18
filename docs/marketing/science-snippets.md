# The science, hedged

Short, cited, general-wellness snippets for the "The Science" panel (app), the landing page, and the README. Source material: `docs/research/research-sweep-main.json` → `science`.

## Hard rules (do not break)

Abendrot is a **general-wellness tool, not a medical device.** Every line below is written to that standard. When in doubt, cite the source and let the reader judge — do not assert an outcome.

**Never say:**
- "clinically proven"
- "treats insomnia" / "cures" / "fixes your sleep"
- "cures eye strain" / "prevents eye strain"
- "blue light damages your eyes"
- any promise that Abendrot will improve _your_ sleep

**Prefer:**
- "supports healthy evening light habits"
- "reduces blue-light exposure at night"
- "may help" / "is associated with" / "research suggests"
- link the research instead of asserting the result

Individual sensitivity to evening light varies more than 50-fold ([Phillips 2019](https://www.pnas.org/doi/10.1073/pnas.1901824116)), so we never imply a single setting is right — or "safe" — for everyone. And warming a screen _without also dimming it_ blunts the benefit, because intensity (melanopic dose) is the real lever ([Schoellhorn 2023](https://pmc.ncbi.nlm.nih.gov/articles/PMC9974389/)). Abendrot is a small, sensible nudge, not a magic sleep button.

---

## Easter-egg snippets (each cited, ready to ship)

Each snippet is one or two calm sentences plus a "Read the research" link. They can surface playfully in the app's "The Science" panel; none is preachy, none makes a medical claim.

### 1. Your eyes have a third light sensor

Beyond the rods and cones you see with, your eyes carry a non-visual sensor — melanopsin, in special retinal cells (ipRGCs) — most sensitive to blue light around **~480 nm**. It helps tell your brain whether it's day or night.

> Source: Lucas RJ, Peirson SN, Berson DM, Brown TM, et al. (2014), _Trends in Neurosciences_ 37(1):1–9 — foundational ipRGC review. https://pmc.ncbi.nlm.nih.gov/articles/PMC4699304/

### 2. Evening light is louder than you'd think

The circadian system is sensitive to evening light: most of the melatonin suppression seen under bright light already happens at fairly modest indoor levels. In a landmark study, dim room light (~106 lux) produced about **88%** of the suppression of much brighter light.

> Source: Zeitzer JM, Dijk DJ, Kronauer RE, Brown EN, Czeisler CA (2000), _The Journal of Physiology_ 526(3):695–702. https://pmc.ncbi.nlm.nih.gov/articles/PMC2270041/

### 3. It's the blue content, not just the brightness

What drives the circadian effect of a display is its **melanopic** (short-wavelength) content more than overall brightness. In a controlled study, melatonin suppression scaled with melanopic dose, while plain brightness (lux) didn't predict it — reducing melanopic content lowered the impact with little visible change.

> Source: Schoellhorn I, Stefani O, Lucas RJ, Spitschan M, et al. (2023), _Communications Biology_ 6:228. https://pmc.ncbi.nlm.nih.gov/articles/PMC9974389/

### 4. Bright by day, dim and warm at night, dark while you sleep

An expert scientific consensus suggests, for circadian health: at least **250 lux** melanopic EDI during the day, no more than **10 lux** in the three hours before bed, and no more than **1 lux** during sleep. These are population-level targets for healthy adults, and they explicitly account for big individual variability.

> Source: Brown TM, Brainard GC, Cajochen C, Czeisler CA, et al. (2022), _PLoS Biology_ 20(3):e3001571. https://journals.plos.org/plosbiology/article?id=10.1371/journal.pbio.3001571

### 5. There's no one "right" setting

The light level needed to suppress melatonin by half ranges from roughly **6 lux to 350 lux** across healthy adults — a **more than 50-fold** difference. The most sensitive people respond to dim reading light; the least sensitive need bright office light. So personalize, and don't trust any single "safe for everyone" number.

> Source: Phillips AJK, Vidafar P, Burns AC, McGlashan EM, et al. (2019), _PNAS_ 116(24):12019–12024. https://www.pnas.org/doi/10.1073/pnas.1901824116

### 6. Screen blue light won't damage your eyes

Ophthalmologists find no good evidence that the blue light from screens damages your eyes or causes macular degeneration. Digital eye strain — tired, dry eyes after a long session — comes mainly from reduced blinking and focusing effort, and it causes no lasting damage.

> Source: American Academy of Ophthalmology, "Should You Be Worried About Blue Light?" (accessed 2026). https://www.aao.org/eye-health/tips-prevention/should-you-be-worried-about-blue-light

### 7. The 20-20-20 habit

For tired eyes, the evidence-aligned moves aren't about blue light at all: every **20 minutes**, look at something at least **20 feet** away for at least **20 seconds**, and remember to blink and take breaks.

> Source: American Academy of Ophthalmology, "Eye Strain: How to Prevent Tired Eyes" (accessed 2026) — states the 20-20-20 rule verbatim. https://www.aao.org/eye-health/diseases/what-is-eye-strain

---

## Professional use case — circadian habits *and* color-critical accuracy

A snippet for the landing page / README "for professionals" angle. Keep it about *workflow*, not health outcomes — it makes no medical claim, and the one factual claim it makes (that warming shifts color) is the uncontroversial, observable mechanism.

### Keep your evening habit without compromising the work

People who work in color — designers, photographers and retouchers, video colorists, and clinicians reading medical imaging — face a real tension at night: a warmed screen is gentler on evening light habits, but warming a display **shifts its color** and is therefore unsuitable for color-critical judgment. That's not a flaw to argue away; it's physics. Warming a screen reduces its short-wavelength (blue) output, which is precisely *why* it can support healthier evening light habits ([Schoellhorn 2023](https://pmc.ncbi.nlm.nih.gov/articles/PMC9974389/)) — and equally why it can't be trusted for matching a print, grading a frame, or judging a scan.

Abendrot's answer is **Reveal True Color**: hold the hotkey and warmth lifts across *every* display, returning accurate color for as long as you hold it; release and warmth eases back. So the color-critical moment is explicit and momentary — you warm by default through the evening, and step out to true color only for the comparison that needs it, then step back.

A few honest boundaries, so this stays a workflow claim and not an overreach:

- **It is not a calibration tool.** Reveal True Color suspends *Abendrot's own* warming so the panel returns to its underlying state; it does not calibrate, profile, or certify your display. Color-managed work still depends on a properly calibrated, profiled monitor.
- **"Accurate" means "Abendrot is out of the way."** The fidelity you get back is your display's own — Reveal removes the warming layer, nothing more.
- **Clinical / regulated workflows have their own rules.** Medical-imaging displays are governed by calibration and QA standards (and often regulated software); treat Reveal True Color as a convenience for keeping a personal evening habit, never as a substitute for a validated, compliant reading setup.

> Mechanism cited: warming a screen lowers melanopic (short-wavelength) content — Schoellhorn et al. (2023), _Communications Biology_ 6:228. https://pmc.ncbi.nlm.nih.gov/articles/PMC9974389/ · No medical claim is made here; Abendrot is a general-wellness tool, not a medical device.

---

## Honest nuance (keep this nearby, don't hide it)

A trustworthy science panel says the unflattering parts too. These are good to surface in a "the honest version" expander.

- **Warming alone may not be enough.** Some trials found that warming a screen _without_ dimming it had little measurable effect on melatonin or sleep, because intensity was the real driver. Abendrot encourages lowering brightness in the evening too, not just warming. ([Schoellhorn 2023](https://pmc.ncbi.nlm.nih.gov/articles/PMC9974389/); [Hoehn et al., 2024, _Brain Communications_ 6(3):fcae173](https://academic.oup.com/braincomms/article/6/3/fcae173/7675955))
- **Effects on real-world sleep are often small or mixed.** Physiological melatonin changes don't always translate into measurably better sleep. ([Hoehn 2024](https://academic.oup.com/braincomms/article/6/3/fcae173/7675955))
- **Blue-blocking glasses are not a proven fix.** A Cochrane review found blue-light-filtering lenses probably make little or no difference to eye strain, with weak evidence for sleep benefit. (We're an evening-light tool, not eyewear — but honesty matters.) ([Singh et al., 2023, _Cochrane_ CD013244](https://www.cochranelibrary.com/cdsr/doi/10.1002/14651858.CD013244.pub2/full))
- **Blue-enriched light is good — at the right time.** Higher-color-temperature light boosts daytime alertness; the same property makes it counterproductive close to bedtime. Timing, not villainy. ([Chellappa et al., 2011, _PLoS ONE_ 6(1):e16429](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0016429))

---

## Primary sources (full list)

| # | Study | Source | Used for |
|---|---|---|---|
| 1 | Lucas et al. (2014) | _Trends Neurosci_ 37(1):1–9 | ipRGC / ~480 nm "third sensor" |
| 2 | Zeitzer et al. (2000) | _J Physiol_ 526(3):695–702 | sensitivity to dim evening light |
| 3 | Chang et al. (2015) | _PNAS_ 112(4):1232–1237 | screens before bed delay sleep/melatonin |
| 4 | Schoellhorn et al. (2023) | _Communications Biology_ 6:228 | melanopic content > brightness |
| 5 | Brown et al. (2022) | _PLoS Biology_ 20(3):e3001571 | 250 / 10 / 1 lux melanopic EDI consensus |
| 6 | Phillips et al. (2019) | _PNAS_ 116(24):12019–12024 | >50-fold individual variability |
| 7 | Chellappa et al. (2011) | _PLoS ONE_ 6(1):e16429 | blue-enriched light & alertness |
| 8 | Hoehn et al. (2024) | _Brain Communications_ 6(3):fcae173 | real-world effects small/mixed |
| 9 | Singh et al. (2023) | _Cochrane_ CD013244 | blue-blocking lenses unproven |
| 10 | AAO (accessed 2026) | aao.org | screens don't damage eyes; eye-strain guidance |
| 11 | AAO (accessed 2026) | aao.org | 20-20-20 rule |

<!-- [FLAG] Every published health snippet should get a final hedged-language review before going
     live on any public surface (README, landing page, app). No medical claims; cite-don't-assert. -->
