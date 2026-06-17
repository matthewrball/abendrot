# Launch timeline (T-6 weeks → T-0 → T+14)

Sequenced, not one blast (§14): soft pre-launch / build-in-public → coordinated **Product Hunt + Show HN** day → awesome-* PRs + newsletters → sustained. Aligned with the confirmed **staged-beta strategy** (§21.6: 0.1 → 0.2 → 0.3 → 1.0) and the **v0.9 designer beta** (§21.5).

> Reminder: T-0 is the **branded 1.0** moment, which arrives only after the hardware matrix passes. The public betas before it are for validation and screenshot-harvesting, not the big launch.

<!-- [FLAG] Signing/notarization is a launch-time decision (Wave-1 founder note). The 1.0 GTM copy
     assumes a signed+notarized 1.0. If any pre-1.0 PUBLIC beta ships unsigned, each public post for it
     must include a first-launch Gatekeeper note and must NOT claim "notarized." Keep load-bearing trust
     claims to "open source, auditable, no telemetry by default" until notarized builds ship. -->

---

## T-6 → T-5 weeks — Foundation

- App, README, and landing page reaching releasable polish (Lanes A/B/D); brand locked (Lane C).
- **Reserve social handles** (@abendrotapp / @getabendrot; check @abendrot) across X / Mastodon / Bluesky.
- Make the **GitHub repo public**, with: README (draft → live), `LICENSE` (MIT), `PRIVACY.md`, `CONTRIBUTING`, `CODE_OF_CONDUCT`, `SECURITY`, 20 topics, custom social-preview, Discussions on.
- Stand up `abendrot.app` (with OG/Twitter cards) + the matthewball.me/abendrot 301 redirect; verify cards render.
- Draft all launch assets (this folder): PH gallery + demo, Show HN comment, Reddit per-sub posts, social threads.

## T-4 → T-3 weeks — Build in public + first public beta

- Start the **build-in-public** cadence (X/Mastodon/Bluesky): pinned intro + Thread A; post the repo. 3–5 posts/week.
- Ship **public beta 0.1** (overlay + hotkey + schedule + DMG + notarization path) for real-hardware validation. _(If unsigned, include the Gatekeeper note.)_
- Begin authentic engagement with indie-Mac-dev / design / FOSS / circadian communities — relationships first.
- Capture the canonical **warm-shift demo clip** (reused everywhere).

## T-2 weeks — Designer beta + assets

- Ship **0.2** (DDC opt-in + restore tooling) and **v0.9 designer beta** to X/Mastodon (§21.5) — harvest real Liquid-Glass-UI screenshots for the PH gallery and Thread C.
- Post Thread B (Reveal True Color) and Thread C (the look).
- Finalize PH gallery (real screenshots), the 15–30s demo, and pre-write every Reddit post.
- Ship **0.3** (Sparkle auto-update) so the update path is proven before 1.0.

## T-1 week — Press + rehearsal

- Pitch press privately with embargoed access: MacStories/AppStories (personal pitch), Indie Dev Monday, iOS Dev Weekly (offer a "how I built the warmth engine" technical post), Console.dev.
- Rehearse the PH + Show HN choreography; confirm 1.0 build passes the hardware matrix and is **signed + notarized + stapled**, with a clean Gatekeeper first-launch.
- Post Thread D (the honest science).
- Line up supporter waves (feedback framing, never "upvote").
- Prepare AlternativeTo listing (as an f.lux / Night Shift alternative) to publish at T-0.

## T-0 — Launch day (one orchestrated day)

1. **12:01 am PT** — Product Hunt self-launch; **first maker comment within 5 min**; staggered timezone supporter waves; reply to every comment within ~15 min.
2. **~9 am–12 pm ET** — Show HN (repo URL); author top-comment immediately, leading with the reliability/engineering hook; be present for hard questions.
3. **Reddit** — r/macapps first, then r/macOS, r/QuantifiedSelf, r/eyestrain, r/sleep, r/opensource — staggered, never identical, never same hour; disclose authorship; ask feedback not upvotes.
4. **Socials** — launch-day post across X / Mastodon / Bluesky.
5. **Publish** the AlternativeTo listing.
6. Keep download + repo un-gated and live; pin the launch in repo Discussions.

## T+1 → T+14 — Sustain & compound

- Reply to everything; convert good feedback into issues and quick fixes; ship visible patch updates (signals active maintenance — the anti-Ice cautionary tale).
- Open clean **awesome-\* PRs** (`jaywcjlove/awesome-mac`, macOS app lists) per each CONTRIBUTING — only now that the README is polished and there's traction.
- Publish the **"how I built the warmth engine"** technical post; pitch it to the dev newsletters.
- Capture social proof as earned (stars, PH rank, HN points, download_count) and add to README/landing.
- Begin SEO on the converting terms ("free open source screen warmth / f.lux alternative for Mac").

## T+2 → T+8 weeks — Channel sequencing

- Sequence remaining channels (9to5Mac / MacRumors / AppleInsider post-traction; lower-key biohacking/sleep communities, non-promo).
- Keep shipping; widen the DDC panel-capability database from real-world bug reports; let reliability-on-every-display remain the proof of the circadian-health story.

---

## Pre-launch go/no-go checklist (gate T-0)

- [ ] 1.0 passes the real-hardware matrix (M5 Tahoe + DDC + Apple panel + overlay everywhere).
- [ ] 1.0 **signed + notarized + stapled**; clean Gatekeeper first-launch on a fresh Mac; Sparkle vN-1→vN update verified.
- [ ] README polished and live; PRIVACY.md, LICENSE, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY present.
- [ ] abendrot.app live with working OG/Twitter cards; 301 redirect verified.
- [ ] All health/science copy passed a final hedged-language review (no medical claims).
- [ ] PH gallery + demo + first maker comment ready; Show HN comment ready; all Reddit posts pre-written and rule-checked.
- [ ] Download links un-gated; Homebrew tap live; download_count tracking confirmed.
