# Product Hunt launch

> Claims must comply with `docs/marketing/evidence-base.md` guardrails (couple warmth with "lower brightness"; red = circadian-sparing, never therapy; no sleep-outcome promises).

Self-launch (keep the maker narrative). Tuesday/Wednesday/Thursday, **12:01 am PT**. Free + open source converts well here.

> Voice: calm, poetic-but-precise, non-medical, no exclamation marks, no "please upvote." Lead with the reliability/designer hook for this audience (§21.5); health stays the brand story, not the pitch headline.

---

## Listing fields

**Name:** Abendrot

**Tagline (≤60 chars):**
- Primary: `Screen warmth that works on every Mac display`
- Alternates: `Open-source circadian screen warmth for macOS` · `Warm your Mac's screen — on every display`

<!-- [FLAG] PH tagline char limit and any topic constraints change over time — verify live before submitting. -->

**Topics:** Mac · Design Tools · Open Source · Productivity · Health & Fitness _(verify current PH topic taxonomy)_

**Description (short):**
> Abendrot is a free, open-source menu-bar app that warms your Mac's screen in the evening — reliably, across every display, including the external monitors and newest Apple Silicon Macs where the old tools quietly fail. Hold a hotkey to reveal true color for color-critical work. MIT-licensed, no telemetry by default.

**Links:** Website `abendrot.app` · GitHub `github.com/matthewrball/abendrot` · Direct download.

---

## Gallery plan (order matters — first frame is the hook)

1. **Hero shot** — a Mac on a warm desk at dusk, screen visibly warm, menu-bar popover open. Bake a real, true number into the mock (a DopeDrop-style "tiny native" proof). The "aha" in one frame.
2. **The warm shift (animated/GIF)** — the same screen easing from cool to warm; the signature moment.
3. **Every display** — built-in + an external monitor side by side, both warm, each showing its method badge (`Hardware` / `Gamma` / `Overlay`). This is the differentiator no incumbent can show.
4. **Reveal True Color** — hold-the-hotkey frame: warmth lifts to accurate color across all displays. The designer hero feature.
5. **The popover** — simple mode: on/off, warmth slider, mode segmented control, per-display status. Liquid Glass beauty shot.
6. **Advanced + Settings** — a glimpse of per-display curves / per-app exclusions, framed as "simple by default, deep when you want it."
7. **Open source** — a real `WarmthKit` code snippet (the DDC write) with "read every line." Trust proof for the NightOwl-burned crowd.
8. **The science (tasteful)** — one hedged, cited snippet card. General wellness, not medical.

<!-- [FLAG] Gallery assets come from Lane C (brand) + Lane B (real UI). Use real screenshots once the
     UI exists; do not ship faked numbers. The v0.9 designer beta (§21.5) exists specifically to
     harvest real Liquid-Glass screenshots for this gallery. -->

---

## Demo concept (15–30s, muted autoplay loop)

A single calm take, no narration, soft optional tone:

1. **0–4s** — Dusk desk. Cursor opens the menu-bar popover. Plain.
2. **4–10s** — Drag the warmth slider; the _whole_ screen — and the external monitor beside it — eases warm together. Method badges tick to `Hardware` / `Overlay`.
3. **10–18s** — Cut to a photo being edited. Hold ⌥⌘T → color snaps true across both displays; release → warmth eases back over ~120ms ("lift the veil").
4. **18–24s** — Pull back: menu-bar glyph glowing amber, everything calm. End card: wordmark + `abendrot.app` + "Free · open source · every display."

Crafted render, not a Loom. ≤8 MB for the GIF variant.

---

## First maker comment (post within 5 minutes)

> Hi Product Hunt — I made Abendrot.
>
> It started with an annoyance I couldn't fix: f.lux and Night Shift either ignore my external monitor or, on my newest Mac, quietly stop warming the screen at all — the system says it worked, but nothing changes. So I built the thing I wanted: a tiny, native menu-bar app that warms your screen in the evening and _actually lands_ on every display — built-in panels, the Studio Display, the Pro Display XDR, an LG UltraFine, the newest Apple Silicon — by trying real hardware color temperature first and falling back to a universal overlay when it has to. And it tells you which method each display is using, instead of silently doing nothing.
>
> For designers and photographers there's a hold-to-Reveal-True-Color hotkey: press and hold, accurate color comes back across every display; let go and the warmth eases back.
>
> It's MIT-licensed and open source — you can read every line, including the analytics code, which is off by default. No account, no telemetry by default, no paywall. Free forever.
>
> The reason I care about evening warmth is circadian: warmer, dimmer light at night is gentler on the body clock. I link the research rather than making health claims about it — it's a general-wellness tool, not a medical device.
>
> I'd genuinely value your honest feedback, and I'm especially curious whether it behaves on _your_ display setup — that's the whole point. I'll be here all day answering everything.

<!-- [FLAG] Founder voice check: this is first-person as the maker. Adjust the origin anecdote to the
     founder's real experience. Reply to every comment within ~15 min; be ready for skeptical-of-health
     and "does it work on X monitor" questions. Do NOT ask for upvotes anywhere. -->

---

## Day-of logistics

- Notify supporters in **4–5 staggered timezone waves** (feedback framing, never "upvote").
- Reply to every comment within ~15 min for the first hours (~85% of top-10 correlate with the early maker reply).
- Keep the repo and download live and un-gated; have the README polished _before_ submitting.
- Pin the launch in repo Discussions; cross-link from Show HN and socials per `timeline.md`.
