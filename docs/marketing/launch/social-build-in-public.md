# Build-in-public — X / Mastodon / Bluesky

Start 2–4 weeks before launch. Mirror across all three platforms (Croissant/Indigo or manual). Post the repo early. Engage authentically with indie-Mac-dev, design, FOSS, and circadian/sleep communities **for weeks before any ask**.

> Voice: calm, precise, poetic-but-precise, non-medical, no exclamation marks, no growth-hack CTAs. Show the work; let the warm-shift clips do the selling. Hashtags sparingly: #buildinpublic #indiedev #macOS #opensource.
>
> Reference (don't tag-spam): indie-Mac devs (Sindre Sorhus, Jordi Bruin), MacStories/Viticci; for science framing, _reference_ Huberman/Hattar-style ideas rather than tagging people.

<!-- [FLAG] Handle reservation: per name-clearance.md, reserve a qualified handle (@abendrotapp /
     @getabendrot; bare @abendrot may be free — verify). Confirm handles before the first post. -->

---

## Pinned intro post (week −4, with the repo)

> Abendrot — a free, open-source macOS app that warms your screen in the evening, on every display.
>
> Built it because f.lux and Night Shift quietly fail on external monitors and the newest Apple Silicon — the system says it warmed the screen, and nothing happens.
>
> Native Swift. Read every line: github.com/matthewrball/abendrot

_(Attach: a short warm-shift clip.)_

---

## Thread A — "why I'm building this" (week −4 / −3)

1/ Most screen-warming apps were built for an older Mac. On my newest one, f.lux-style warming silently stopped working — the gamma call returns success and the screen never changes. I went down the rabbit hole and started building a fix in the open.

2/ The cause: most night-mode apps write a gamma table (`CGSetDisplayTransferByTable`). On recent Apple Silicon under Tahoe that call succeeds but produces no visible warmth. So the app _looks_ like it's working. It isn't.

3/ External monitors are their own mess — Night Shift often does nothing or tints them pink, and buttonless Apple displays expose no DDC color control at all.

4/ So Abendrot tries real hardware control first (DDC), then a universal Metal overlay that works on _every_ display — and it tells you which method each display is using, instead of silently failing.

5/ Native Swift, menu-bar only, MIT, no telemetry by default. Free forever. Building it in public here — repo's up: github.com/matthewrball/abendrot

---

## Thread B — the signature feature (week −2)

1/ A small thing I'm proud of in Abendrot: hold a hotkey and warmth lifts across _every_ display — accurate true color for color-critical work. Let go and it eases back over ~120ms, like lifting a veil. _(clip)_

2/ It's built on `KeyboardShortcuts`, so it needs no Accessibility permission. A watchdog auto-resumes warmth if a key-up ever gets lost, so you never get stuck in true-color.

3/ For designers and photographers this is the whole pitch: warmth all evening, accurate color the instant you need it.

---

## Thread C — Liquid Glass / the look (week −2, harvest screenshots from v0.9 designer beta)

1/ The Abendrot popover, in Tahoe's Liquid Glass. Warmth is the default state of the UI; pure white is reserved for exactly one moment — Reveal True Color — so accuracy reads as an event. _(screenshots)_

2/ Quiet, native, tiny. No Electron. A Mac-assed Mac app. _(beauty shot)_

<!-- [FLAG] Thread C depends on real UI screenshots from the v0.9 designer beta (§21.5). Don't post mockups
     as if shipped. -->

---

## Thread D — the honest science (week −1)

1/ Why warm your screen at night at all? Your eyes have a non-visual sensor (~480nm) that helps tell your brain it's day or night. Warmer, dimmer evenings mean less of that signal. Abendrot links the research instead of making claims.

2/ Being honest: the eye-_damage_ blue-light scare is overblown (ophthalmologists agree), and warming without dimming does little — it's the melanopic _dose_ that matters, and sensitivity varies 50-fold between people.

3/ So Abendrot is a small, sensible nudge, not a magic sleep button. General wellness, not medicine. Sources in the repo.

---

## Launch-day post (T-0)

> Abendrot is out — free, open-source screen warmth for macOS that works on every display, even the ones the old tools fail on.
>
> Live on Product Hunt and Show HN today. Honest feedback means everything, especially if it misbehaves on your setup.
>
> abendrot.app · github.com/matthewrball/abendrot

<!-- [FLAG] If the T-0 build is an unsigned beta, do not imply "signed/notarized." Keep load-bearing
     claims to "open source, auditable, no telemetry by default." -->

---

## Cadence & engagement notes

- 3–5 posts/week in the warm-up window: progress, clips, a quirk you fixed, a screenshot.
- Reply and engage in others' threads for weeks before launch; relationships first, ask last.
- Reuse the warm-shift clip relentlessly — it's the strongest asset across every channel.
