# Reddit launch

Per-subreddit drafts. **Verify each sub's live rules before posting** (self-promo windows, flair, "I made this" requirements vary and change). Lead with free + open source, **disclose authorship every time**, put media in-post, ask for **feedback, not upvotes**. Never post identical cross-posts in the same hour; space them out (see `timeline.md`).

> Voice: calm, precise, non-medical, no exclamation marks. In sleep/health subs, no medical claims — link research, don't assert outcomes.

<!-- [FLAG] Several of these subs (r/macOS, r/sleep, r/opensource) have strict self-promo / no-app-launch
     rules and may require mod permission or a specific day/flair. Confirm before each post; when in doubt,
     ask the mods. r/HubermanLab and r/Biohackers are extra sensitive to promo — go last, low-key, non-promo. -->

---

## r/macapps (primary — dev-friendly, highest intent)

**Title:** `[Free / Open Source] Abendrot – a menu-bar app that warms your screen on every display, including external monitors and new Apple Silicon`

**Body:**
> I built Abendrot, a free and open-source (MIT) macOS menu-bar app that warms your screen color temperature in the evening — and, unlike Night Shift or f.lux, it works reliably on external monitors and on the newest Apple Silicon Macs, where the older gamma-based apps quietly stop doing anything.
>
> It uses a layered engine: real hardware color temperature (DDC) where the display supports it, and a universal Metal overlay everywhere else, so it works on built-in panels, Studio Display, Pro Display XDR, LG UltraFine, etc. It shows you which method each display is using instead of silently failing. There's also a hold-to-Reveal-True-Color hotkey for color-critical work.
>
> Native Swift, menu-bar only, no Electron, no telemetry by default, no account, free forever.
>
> Repo: github.com/matthewrball/abendrot · Site: abendrot.app · [demo GIF in post]
>
> I'm the developer — would genuinely value feedback, especially if it misbehaves on your specific monitor or Mac. That reliability-on-every-display part is the whole reason I made it.

---

## r/macOS (discussion framing — not a launch ad)

**Title:** `Why do f.lux and Night Shift fail on external monitors (and new Macs)? I dug into it and built an open-source fix`

**Body:**
> Something that's bugged me for ages: Night Shift often does nothing on my external monitor (or tints it pink), and on my newest Mac, f.lux-style gamma warming silently stopped working — the system reports success but the screen never changes.
>
> The short version of why: most of these apps warm the screen by writing a gamma table, and on recent Apple Silicon under Tahoe that call succeeds but produces no visible effect. Buttonless Apple displays also expose no DDC color control.
>
> I ended up building a small open-source (MIT) menu-bar app, Abendrot, that tries hardware control first and falls back to a universal overlay so it works on every display — and tells you which method each display is using. Sharing partly because the underlying macOS quirk seems worth knowing about regardless of my app.
>
> Repo: github.com/matthewrball/abendrot (I'm the developer). Curious whether others have hit the same external-monitor / new-Mac warming failures.

---

## r/QuantifiedSelf (data / method framing)

**Title:** `[OSS] Abendrot – open-source Mac screen warmth with transparent, opt-in, anonymous analytics`

**Body:**
> Abendrot is a free, open-source (MIT) macOS app that warms your screen in the evening across every display. Sharing here because of the data posture, which this sub tends to care about:
>
> - No telemetry by default. Analytics are opt-in, anonymous, aggregate, ≤8 categorical events, no identifiers, EU-hosted or self-hosted — and the analytics code is open, so you can verify it.
> - It follows the system sunset schedule (read-only) or a custom one, and reports which warmth method each display is using.
>
> On the science: I treat it as general wellness, not medicine — I link the circadian research (melanopic dose, ipRGCs, individual variability) rather than claiming sleep improvements. Happy to discuss the evidence honestly, including where it's weak.
>
> Repo: github.com/matthewrball/abendrot. I'm the developer; feedback on the data model and the science framing especially welcome.

---

## r/eyestrain (high-intent — but be careful with claims)

**Title:** `[Free / OSS] A Mac screen-warmth app – and an honest note about what blue light does and doesn't do`

**Body:**
> I made Abendrot, a free open-source macOS app that warms your screen in the evening across every display. Posting here with a deliberate caveat, because this sub deserves honesty over hype:
>
> Ophthalmologists (AAO) find no good evidence that screen blue light damages your eyes, and digital eye strain comes mainly from reduced blinking and focusing effort — so warming your screen is **not** an eye-strain cure, and I won't pretend it is. What Abendrot does is reduce evening blue-light exposure (a circadian/sleep-comfort thing) and give you a softer screen at night, which some people simply find more comfortable. For actual eye strain, the evidence points to the 20-20-20 habit, blinking, breaks, and good brightness/distance.
>
> If a warmer evening screen sounds comfortable to you, the repo is github.com/matthewrball/abendrot (I'm the developer). Feedback welcome — including pushback on the framing.

<!-- [FLAG] This post intentionally does NOT claim eye-strain benefit. Keep it that way. Any edit that
     implies Abendrot treats/prevents eye strain must be rejected. -->

---

## r/sleep (NO medical claims — strict)

**Title:** `[Open Source] A free Mac app for warmer evening screens – I link the circadian research instead of making sleep claims`

**Body:**
> I built Abendrot, a free, open-source macOS app that warms your screen color temperature in the evening across every display. I want to be careful in this sub: **I'm not claiming it will improve your sleep.** It reduces evening short-wavelength (blue) light from your screen, which the circadian research associates with the body clock — but effects on real-world sleep are individual and often modest, and warming without also dimming does less than people assume.
>
> So rather than make a claim, I link the sources (Zeitzer 2000, Schoellhorn 2023, Brown 2022 consensus) and let you read them. It's a general-wellness tool, not a medical device.
>
> Repo: github.com/matthewrball/abendrot (I'm the developer). I'd value feedback on whether the science framing feels honest.

<!-- [FLAG] r/sleep often restricts product posts and medical claims. Verify rules / get mod OK first.
     Absolutely no "helps you sleep / treats insomnia" language. -->

---

## r/opensource (license + repo framing)

**Title:** `Abendrot – MIT-licensed native Swift macOS app for screen warmth (no telemetry by default, read every line)`

**Body:**
> Abendrot is a native Swift 6 (SwiftUI + AppKit) macOS menu-bar app that warms your screen across every display in the evening. MIT-licensed, no telemetry by default, no account, free forever — built deliberately as the auditable, trustworthy alternative after the NightOwl hidden-botnet incident soured this category.
>
> The engine (`WarmthKit`) is a separate Swift package with headless tests: a DDC hardware path plus a universal Metal-overlay fallback, with per-display transparency about which method is active. Opt-in analytics use open-source Aptabase and you can read exactly what's sent.
>
> Repo: github.com/matthewrball/abendrot. I'm the developer; contributions and code review very welcome — especially bug reports from display setups I can't test on.

---

## Later / lower-key (go after the above, non-promo tone): r/freesoftware, r/Biohackers, r/HubermanLab

- **r/freesoftware:** same as r/opensource, emphasize MIT + no telemetry; verify it allows app posts.
- **r/Biohackers / r/HubermanLab:** these communities are rigorous and promo-averse. Only post if rules allow; lead with the honest science framing (melanopic dose, >50-fold individual variability), reference (don't tag-spam) the science communicators, and make it clearly non-promotional. When in doubt, participate first and don't post the app at all.
