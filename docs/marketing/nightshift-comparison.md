# Abendrot vs Apple Night Shift — verified comparison (marketing)

> Adversarially-verified competitor comparison for marketing use. Provenance: `nightshift-comparison` workflow
> (32 findings, **17 citable** of 32 after verification). Last updated 2026-06-18.
> Companion: `evidence-base.md` (the science) · `messaging-and-campaigns.md` (campaign copy).

## ⚠️ Read first — honesty corrections to the original hypothesis
- **Night Shift is NOT "built-in only."** It works on Apple's own external displays (Studio Display, Pro Display XDR) and some LG UltraFine. The real, defensible differentiators are **depth of warming** (Abendrot ~1900K blue-to-zero vs Night Shift ~2700–3400K) and **reliability/coverage on third-party externals** — NOT a flat "built-in only."
- **Night Shift does NOT "remove no blue."** It reduces blue, just not to zero. Never claim it leaves all the blue.
- **Apple publishes no Kelvin value.** Every Night Shift Kelvin figure is a third-party estimate — always use the hedged range (~2700–3400K), never a hard number, and keep iOS-measured figures labeled iOS (not macOS).
- **Comparative advertising naming Apple is legally permitted (16 CFR §14.15)** *if* each claim is truthful + substantiated and the basis is identified — substantiation must be held BEFORE publishing.

## Night Shift — verified facts
### Warmest CCT

Apple publishes NO Kelvin spec for macOS Night Shift (verified citable, finding [0]): the slider is labeled only "Less Warm" / "More Warm" (support.apple.com/en-us/102191). Every Kelvin figure is therefore a third-party ESTIMATE, not an Apple-confirmed colorimeter reading.

Best verified answer: Night Shift's warmest setting is estimated at roughly 2700-3400K (incandescent-to-halogen range) and does NOT reach the ~1900K candlelight / blue-channel-near-zero point. Specific anchors, all citable: Iris founder Daniel Georgiev estimates "around 3400K" (iristech.co, 2017, finding [10]); f.lux's comparison says Apple "limits to maybe 2700K (give or take a few hundred Kelvin)" (finding [10]); the only hard instrument readings are on iOS, not macOS — ~2854K (Steemit spectrometer, iPhone SE) and ~3026K (PhoneArena colorimeter, iPhone 6 Plus, iOS 9.3, 2016/2017, finding [1]). No source places Night Shift at or below 2000K.

Uncertainty: all data is 2016-2019; Apple has not documented a change but the figures vary by device/OS and are estimates. Present as a RANGE (~2700-3400K), never a single hard number; keep iOS-measured figures explicitly labeled as iOS, not macOS.

### Blue / melanopic removal

At its DEFAULT setting, Night Shift removes LESS THAN ~30% of blue light's biological (melanopic) impact, and f.lux removes roughly 4-5x more blue by default. This is citable (findings [6], [11], [18]) ONLY when attributed: it is f.lux co-founder/CTO Michael Herf's own spectrometer-based measurement (Photo Research PR-655), posted on the f.lux forum in 2017 (macOS 10.12.4 era). It must be attributed to Herf/f.lux and dated 2017 — it is a partisan competitor's self-measurement, not an independent or current lab figure. Preserve Herf's framing "impact blue light has on your body" rather than flattening to "<30% of blue photons."

Independently and evergreen-true (no attribution needed): Night Shift REDUCES blue light but does NOT eliminate short-wavelength blue. Its warmest setting never drives the blue channel to zero.

A 2026 single-author SpyderX colorimeter analysis by neuroscientist Patrick Mineault measured ~60% blue (S-cone) and ~40% green reduction at warmest with red unchanged, and MODELED ~52% less melanopic/ipRGC light (~half remains) — but this is finding [28], citable=FALSE (self-published Substack, the 52% is modeled from an eyeballed spectrum, not measured). Treat as uncertain corroboration only; do not cite as a hard measurement.

Do NOT claim Night Shift "removes no blue" — that is false; it reduces blue, just not to zero.

### Display coverage

Night Shift works reliably on the BUILT-IN display and on Apple's own buttonless external displays (Studio Display, Pro Display XDR support Night Shift + True Tone with a compatible Mac — citable, finding [4]; though some pro reference-mode presets can disable it). On generic THIRD-PARTY external monitors it is officially conditional and widely reported as inconsistent.

Apple's own concession (verbatim, current, citable [0][25]): "Night Shift performance on external displays depends on the characteristics of the display." (support.apple.com/en-us/102191, last updated 2026-02-10.)

Documented failure mode (citable [16][25]): on some unsupported external displays the slider can be set but does not take effect and reverts to "Less Warm." A known cause is macOS misclassifying the monitor (typically over HDMI) as a TV, which disables Night Shift. The community workaround is the third-party tool BetterDisplay, which spoofs the display role as "Computer Monitor" (BetterDisplay official wiki, citable [7][16]). Night Shift is also unavailable on DisplayLink and Sidecar displays; for those, even BetterDisplay must fall back to a Metal color-temperature overlay (BetterDisplay wiki, citable [7]; DisplayLink's own support site corroborates).

Do NOT say "Night Shift only works on the built-in display" (false — finding [29], it works on named external displays) or "most third-party monitors are unsupported" as a flat Apple fact (overstated — many unlisted monitors do work; the real gate is monitor-vs-TV classification). Frame as: officially conditional + widely reported inconsistent on third-party externals.

Note: Abendrot's "gamma path warms every display" is genuine differentiation in COVERAGE/RELIABILITY, but gamma-table adjustment is not unique to Abendrot (BetterDisplay also uses it). Contrast on "works where Night Shift is unsupported/unreliable," not on the technique being novel.

### Genuine strengths (be fair)

Genuine, citable strengths to acknowledge so the comparison reads as honest (findings [4][9][14][19][26]): Night Shift is FREE, built into macOS (no install, no purchase), zero-setup in the everyday sense, system-integrated, and schedulable automatically from sunset-to-sunrise or on a custom schedule. It works reliably on the built-in display and on Apple's own buttonless external displays (Studio Display, Pro Display XDR, with a compatible Mac, including True Tone). Reviewers (iMore 2018) find it genuinely sufficient for mainstream users who aren't on screens right before bed or don't have sleep trouble. It is lightweight (an OS-level gamma shift, no separate app to run).

Minor precision: "zero-setup" is slightly generous — sunset-to-sunrise scheduling requires Location Services. Drop "syncs across Apple devices" (unsupported — finding [9]). Drop "battery/perf efficient" unless separately sourced — iMore makes no such claim (finding [14]).

The honest differentiation is DEPTH of warming (Abendrot reaches ~1900K blue-zero; Night Shift bottoms out ~2700-3400K) and CROSS-DISPLAY reliability — not the absence of a feature.

## Comparison table (verified, sourced)

| Dimension | Apple Night Shift | Abendrot | Source |
|---|---|---|---|
| **Warmest color temperature** | ~2700-3400K (third-party estimate; Apple publishes no Kelvin value). iOS instrument readings ~2854-3026K. Never reaches ~1900K candlelight. | Everyday warmest ~1900K (blackbody curve drives blue channel to its practical minimum); opt-in expanded range goes warmer toward pure red. | Apple Support 102191 (no Kelvin); iristech.co 2017 (~3400K); f.lux fwd (~2700K); PhoneArena/Steemit iOS measurements [0][1][10] |
| **Blue / melanopic reduction (default)** | Removes <30% of blue light's biological impact at default; f.lux removes ~4-5x more (per f.lux CTO Michael Herf, 2017, spectrometer). Reduces blue, does not eliminate it. | At ~1900K the blackbody-based warming curve drives the display's blue channel to its practical zero. | M. Herf, f.lux forum, 2017 (macOS 10.12.4) [6][11][18] |
| **Display coverage** | Built-in + Apple's own external displays (Studio Display, Pro Display XDR) + select LG UltraFine; inconsistent on generic third-party monitors; unavailable on DisplayLink/Sidecar. | Warms every display including buttonless Apple displays via its gamma path (OS-level), DDC hardware path, and Metal overlay floor. | Apple Support 102191; 102147; BetterDisplay wiki [0][4][7][25] |
| **External-display reliability** | Apple: performance 'depends on the characteristics of the display.' Users report the slider reverting to 'Less Warm'; macOS misdetects some HDMI monitors as TVs, disabling it. Community fix: BetterDisplay role spoof. | Per-display method shown (gamma / DDC / overlay); works on buttonless Apple displays. | Apple Support 102191 (2026-02-10); MacRumors thread 2341729; BetterDisplay wiki [16][25] |
| **Cost / install / integration** | Free, built into macOS, zero-install, system-integrated, schedulable sunset-to-sunrise or custom. (Genuine strength.) | Free, open-source (MIT), native menu-bar app; install required. Zero telemetry by default. | Apple Support 102191; mac-help shift-to-warmer-colors [4][9][19] |
| **Kelvin transparency** | No Kelvin values published; slider labeled only 'Less Warm'/'More Warm.' | Shows color temperature and which warming method each display uses; Reveal-True-Color hotkey. | Apple Support 102191 [0] |

## Quantitative benefit (the headline argument)

Honest, cited, illustrative framing:

1) ATTRIBUTED competitor measurement (citable, dated): Per f.lux co-founder/CTO Michael Herf (2017, Photo Research PR-655 spectrometer, macOS 10.12.4), Night Shift's default settings remove under ~30% of blue light's biological impact, and f.lux removes roughly 4-5x more blue by default [6][11][18].

2) ILLUSTRATIVE melanopic model (label as model, not measurement): Applying the CIE S026 melanopic action spectrum to equal-brightness blackbody spectra, a ~1900K white retains materially less residual melanopic ("blue") stimulus than a warmer-only ~2700-3400K Night-Shift-range white. Published melanopic-ratio tables anchor the direction: a 2700K source has a melanopic ratio ~0.45-0.52 of a 6500K/D65 white (XAL/Fagerhult/Zumtobel, finding [23], citable=false on the Night Shift anchor but the physics tables are sound) — and 1900K is warmer still. Present the percentage gap (modeled ~30-46% less residual melanopic content at 1900K vs the Night Shift range, equal brightness) ONLY as an illustrative model, never a device measurement or health outcome.

3) SCIENTIFIC CAVEAT (citable [26]): CCT alone is "not a suitable proxy for the biological potency of light" (Esposito & Houser, Scientific Reports, 2022). So Kelvin-based melanopic claims must stay illustrative, not health claims.

4) Physical floor (citable [24]): ~1900K is approximately where the standard blackbody-to-sRGB warming curve drives blue to its practical minimum (Tanner Helland algorithm: Blue=0 at T<=1900K; vendian.org table), and roughly the coolest blackbody color a standard sRGB panel can chromatically follow (techmind.org). This independently supports Abendrot's ~1900K "blue-to-zero" everyday-warmest design choice.

## What others say (sourced corroboration)

Independent corroboration that Night Shift under-warms versus dedicated tools (use as attributed sentiment, not measured fact):

- iMore (2018, citable [14]): Night Shift is a "set-it-and-forget-it" option that's "just fine" for users who aren't on screens right before bed and don't have trouble sleeping — but f.lux "goes a little bit deeper." Fair acknowledgement that it is adequate for mainstream users.
- MacRumors community thread 2341729 (Apr 2022-Jul 2025, citable [16][25]): ~9 distinct users report Night Shift failing/reverting on external monitors (LG 38WN95C-W, Dell G3223Q, LG C1 OLED, Samsung); root cause = macOS misdetecting monitors as TVs; fix = BetterDisplay reclassification.
- BetterDisplay official wiki + DisplayLink's own support site (citable [7]): confirm Night Shift is unavailable on DisplayLink/Sidecar and that HDMI monitors are sometimes misdetected as TVs.

CORRECTION to the founder's hypothesis: "Night Shift only works on the built-in display" is FALSE (finding [29], citable=false because the cited source misattributes a removed Apple list) — Night Shift officially works on named external displays including Apple's Studio Display and Pro Display XDR. The defensible claim is about DEPTH of warming and reliability/coverage on third-party externals, NOT a flat "built-in only." Note: the widely cited "f.lux only goes past 3400K with an unlock" framing is also wrong (finding [8]) — f.lux reaches 1900K "Candle" on its default slider; ~3400K is roughly where Night Shift bottoms out, not an f.lux gate.

Non-citable corroboration (uncertainty only): House of Moth lux-meter test (2019) and Patrick Mineault's 2026 SpyderX analysis (~60% blue cut, ~52% melanopic modeled) both point the same direction but are findings [13]/[28], citable=false — do not present their hard numbers as established.

## ✅ Marketing-safe claims (ready to use, hedged + attributed)

- Apple publishes no Kelvin value for Night Shift — its slider is labeled only 'Less Warm' to 'More Warm.' Abendrot shows the actual color temperature and the warming method for every display. (Source: Apple Support, support.apple.com/en-us/102191, 2026.)
- Independent estimates put Night Shift's warmest setting around 2700-3400K — incandescent-to-halogen warmth. Abendrot's everyday-warmest ~1900K reaches candlelight, where a blackbody-based curve drives the display's blue channel to its practical minimum. (Apple publishes no figure; estimates from Iris/iristech.co 2017 and f.lux.)
- According to f.lux co-founder Michael Herf (2017 spectrometer measurement), Night Shift's default settings remove under 30% of blue light's biological impact, and f.lux removes roughly 4-5x more blue by default. Night Shift reduces blue light, but does not eliminate it.
- Apple states that 'Night Shift performance on external displays depends on the characteristics of the display.' Abendrot warms every display — built-in and external, including buttonless Apple displays — via its gamma, DDC, and overlay engine. (Source: Apple Support 102191, updated 2026-02-10.)
- On some external monitors, macOS misdetects the display as a TV and disables Night Shift; users resort to the third-party tool BetterDisplay to make it stick. (Sources: MacRumors thread 2341729; BetterDisplay official wiki.)
- Night Shift is unavailable on DisplayLink and Sidecar displays. (Source: BetterDisplay wiki; DisplayLink support.)
- Night Shift is free, built into macOS, and great for set-it-and-forget-it use on the built-in display. Abendrot is for people who want deeper warmth and reliable warming across every external display. (Fairness framing.)
- Illustrative only: warming a display to ~1900K substantially reduces residual melanopic ('blue') stimulus versus a warmer-only setting in the ~2700-3400K range at equal brightness — though correlated color temperature alone is not a reliable proxy for light's biological potency (Esposito & Houser, Scientific Reports, 2022). Not a health claim.

## ⛔ DO NOT CLAIM

- Do NOT say 'Night Shift removes no blue light' or 'leaves all the blue' — false; it reduces blue, just not to zero (per Herf's own <30% / f.lux measurements).
- Do NOT state any Night Shift Kelvin value as an Apple-confirmed or measured fact (e.g. 'Night Shift bottoms out at exactly 3400K' or 'exactly 2700K') — Apple publishes none; all figures are third-party ESTIMATES. Always use a hedged range (~2700-3400K).
- Do NOT present iOS spectrometer readings (~2854K, ~3026K) as macOS measurements — keep the iOS-vs-macOS distinction explicit.
- Do NOT say 'Night Shift only works on the built-in display' — false; it works on named external displays including Apple Studio Display and Pro Display XDR.
- Do NOT say 'most third-party monitors are unsupported' as a flat Apple fact — many unlisted monitors work; the real gate is monitor-vs-TV classification.
- Do NOT present the <30% / 4-5x figures as current, independent, or neutral facts — attribute to f.lux co-founder Michael Herf and date them 2017 (macOS 10.12.4).
- Do NOT cite the 2017 'Night Shift brightens the screen on warmer settings' behavior as present-tense — it is a 9-year-old vendor self-measurement and may not persist.
- Do NOT present the modeled ~52% melanopic / ~60% blue SpyderX figures (Mineault 2026) as measured or peer-reviewed — the melanopic figure is modeled from an eyeballed spectrum on a self-published blog.
- Do NOT make medical/sleep outcome claims — quantify only in melanopic/spectral terms and label CCT-based melanopic claims as illustrative (CCT is 'not a suitable proxy' — Esposito & Houser 2022).
- Do NOT imply the gamma-warming technique is unique to Abendrot — BetterDisplay also uses gamma tables; contrast on coverage/reliability instead.
- Do NOT claim Night Shift 'syncs across Apple devices' or is 'battery/perf efficient' — unsupported by sources.
- Do NOT use the unsourced '~70% melanopic reduction at 1900K' figure as fact — label as estimate or drop.

## Uncertainties

Night Shift WARMEST Kelvin is the biggest uncertainty: Apple publishes no value, estimates span ~2700-3400K, and the only hard instrument readings (~2854K, ~3026K) are iOS, not macOS, and date to 2016-2017. Use a range, never a hard number.

The <30% / 4-5x blue-removal figures are a 2017 partisan self-measurement by f.lux's own CTO (macOS 10.12.4, ~9 years old). Qualitatively still holds (Night Shift's mechanism is a warm CCT shift, not a dark signal), but the exact percentages may differ on current hardware/OS. Always attribute and date.

The strongest modern measurement (Mineault SpyderX 2026: ~60% blue cut, ~52% melanopic modeled) is citable=FALSE — self-published, not peer-reviewed, melanopic figure modeled from an eyeballed spectrum. Usable only as directional corroboration.

The "2017 brightens-on-warmer-settings cancels the benefit" behavior cannot be assumed current.

The ~1900K = "blue channel to zero" framing is a gamut/RGB approximation (Helland/vendian say blue=0 at <=1900K; techmind says red primary can't follow the locus below ~1900K) — these are distinct facts that coincide near 1900K; do not present blue-zero as literally exact. f.lux's own guidance notes 1900K candle is "reducing how much blue is sent," not literally zero — hedge with "practical minimum."

Melanopic gap percentages (~30-46% at 1900K vs the Night Shift range) are an illustrative model, not a device measurement; CCT is not a reliable proxy for biological potency (Esposito & Houser 2022).

FTC/§13: comparative advertising naming Apple/Night Shift is affirmatively permitted (16 CFR §14.15) provided each claim is truthful, substantiated, and the basis is identified — substantiation must be held BEFORE publishing (FTC Substantiation Policy). The legal permission does not substantiate any specific technical claim; each still needs its own basis.

Apple's external-display support has historically been a named list (LED Cinema, Thunderbolt, LG UltraFine 4K/5K) that Apple has since removed from live docs in favor of the "depends on the characteristics of the display" caveat — avoid citing the old enumerated list as current Apple policy.

## Citable sources

- Apple Support — 'Use Night Shift on your Mac' (support.apple.com/en-us/102191, updated 2026-02-10) — no Kelvin value; 'Less Warm'/'More Warm' slider; external-display caveat
- Apple Support — Studio Display / Pro Display XDR True Tone + Night Shift (support.apple.com/en-us/102147; mac-studio display-settings guide apdab93667af) — Apple external displays supported
- Apple Support — 'Shift to warmer colors on your Mac' (mac-help mchl97bc676d) — scheduling, sunset-to-sunrise
- f.lux forum — Michael Herf, 'f.lux vs. Night Shift in macOS 10.12.4' (forum.justgetflux.com/topic/3655, 2017) — <30% blue impact, f.lux 4-5x more; PR-655 spectrometer
- iristech.co — Daniel Georgiev, 'Night Shift review macOS' (iristech.co/night-shift-review-macos, 2017) — ~3400K estimate
- PhoneArena — 'iOS 9.3's Night Shift explored' (phonearena.com, 2016) — colorimeter ~3026K (iOS)
- Steemit — @cryptos 'Technical Analysis: iPhone's Night Shift Mode' (2016) — spectrometer ~2854K (iOS)
- MacRumors Forums — 'Night Shift not taking effect on external display' (thread 2341729, 2022-2025) — external failures + BetterDisplay fix
- BetterDisplay official wiki — 'Enable Night Shift for televisions' (github.com/waydabber/BetterDisplay/wiki) — natively-connected only; DisplayLink/Sidecar excluded; TV misdetection; Metal fallback
- iMore — Lory Gil, 'Night Shift vs. f.lux: What's the difference?' (imore.com, 2018) — set-it-and-forget-it sufficiency
- techmind.org — W.A. Steer, 'Colour temperature / blackbody on monitors' (techmind.org/colour/coltemp.html, 2005/2008) — sRGB can't follow blackbody below ~1900K
- Tanner Helland — Kelvin-to-RGB algorithm (tannerhelland.com, 2012) + vendian.org blackbody RGB table — blue=0 at <=1900K
- Esposito & Houser — 'Correlated colour temperature is not a suitable proxy for the biological potency of light,' Scientific Reports (nature.com/articles/s41598-022-21755-7, 2022)
- XAL Lighting — melanopic ratio reference values / CIE S026 mDER (xal.com effect-and-correction-factors) — 2700K MR ~0.45-0.52
- 16 CFR §14.15 — FTC Statement of Policy Regarding Comparative Advertising (law.cornell.edu/cfr/text/16/14.15) + FTC Advertising Substantiation Policy Statement (1984)
