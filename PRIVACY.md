# Privacy Policy

_Last updated: {{DATE}} · Applies to: the Abendrot macOS application and the abendrot.app website._

<!-- [FLAG] Set {{DATE}} at publish. [FLAG] This policy is plain-language and written to match the
     real data flows in the plan (§11). Have a human (and ideally legal) confirm before publishing,
     especially the legal-basis and data-controller sections. Keep it consistent with the
     in-app Privacy tab and any Apple privacy disclosures (the "technical truth gap" risk). -->

Abendrot is a free, open-source macOS app that warms your screen in the evening. It is built privacy-first: **by default, Abendrot collects nothing about you, sends nothing off your Mac, and requires no account.**

This document explains exactly what data exists, when, and why — in plain language.

## The short version

- **No telemetry by default.** Analytics are **off** until you explicitly turn them on.
- **No account, ever.** Abendrot has no login, no profile, no email collection.
- **No tracking.** No cookies, no fingerprinting, no advertising IDs, no cross-site tracking.
- **No health data.** Abendrot never collects your schedule, sleep, location, or screen contents.
- **Runs on your Mac.** The app's features work entirely locally.
- **Auditable.** Abendrot is MIT-licensed and open source — you can read every line, including the analytics code.

## In-app analytics (opt-in, off by default)

Abendrot can optionally collect **anonymous, aggregate** usage statistics to help us understand which features matter and where the app breaks. This is **entirely optional** and **off until you choose to enable it** in a clear first-run panel or in Settings → Privacy. Every feature of Abendrot works fully whether or not you turn it on.

If you opt in, here is exactly what is and isn't involved.

### What we use

We use **[Aptabase](https://aptabase.com)** — an open-source, privacy-focused analytics tool — running in a privacy-preserving configuration.

<!-- [FLAG] Confirm the final hosting choice before publishing and state it precisely here:
     either Aptabase's EU-managed instance, or a self-hosted instance we run. The plan (§11)
     recommends "Aptabase, self-hosted or EU-managed." Name the actual data processor and region. -->

- **Hosting/region:** {{EU-managed Aptabase _or_ a self-hosted Aptabase instance we operate}}. Analytics data is processed in the EU.
- **No identifiers we control:** Aptabase does not use cookies, persistent device identifiers, or cross-session tracking. It derives a salted, daily-rotating, non-reversible value purely to estimate counts; we cannot use it to identify or follow you.

### The complete list of events

If you opt in, Abendrot may send a small number of **categorical, payload-free** events. This is the complete list:

1. **App activated** — that the app was used (no time-of-day, no schedule data).
2. **Warmth mode used** — which mode is in use (follow-sunset / schedule / manual), as a category only.
3. **Advanced mode enabled** — that advanced mode was turned on.
4. **Hotkey used** — a count that Reveal True Color was triggered (count only, no timing).
5. **Warmth method per display** — which method a display ended up using (`hardware` / `gamma` / `overlay`), so we know our reliability story holds on real hardware.
6. **App version** — the Abendrot version (e.g. `1.0.3`).
7. **macOS major version** — e.g. `26` (major only, not your full build).
8. **Anonymous retention cohort** — a coarse, anonymous signal of whether the app is still in use over time.

That is the maximum. There are **no more than eight** event categories, and none of them carries free-text, content, or anything tied to you.

### What we never collect

- Your warmth schedule, sleep times, or any health- or sleep-related data.
- Anything on your screen, screenshots, or screen recordings.
- Display serial numbers, EDID identifiers, or device serials.
- Your precise location or precise locale.
- Your IP address (Aptabase does not store it for our use).
- Email, name, or any account information (there is no account).
- Any identifier we can use to single you out.

## The website (abendrot.app)

The Abendrot website may count an anonymous **download-click** event using a cookieless, privacy-respecting analytics tool, with no cookies and no cross-site tracking, so we can see roughly how many people start a download. It sets no advertising or tracking cookies.

<!-- [FLAG] Confirm the website analytics tool (plan §11 suggests Plausible or Aptabase web — no GA4)
     and whether it is enabled at launch; if the site uses none, simplify this section. -->

We also report aggregate **download counts** from GitHub Releases (and, later, Homebrew's public aggregate analytics). These are sums of public download numbers — no personal data is involved.

## Auto-update

Abendrot checks for updates using [Sparkle](https://sparkle-project.org) over HTTPS. Checking for an update involves your Mac requesting an update file (an "appcast") from our release host. This is a normal network request to retrieve a file; we do not use it to build a profile of you. You can disable automatic update checks in Settings.

## System permissions

Abendrot is designed to need **as few system permissions as possible**:

- It does **not** require Accessibility permission.
- It does **not** require Screen Recording permission for its default behavior.
- It reads the system Night Shift schedule (when available) only to follow it; it never changes your Night Shift setting.

If a future, optional feature needs a permission, Abendrot will ask for it explicitly and explain why, and the feature will be optional.

## Legal basis, retention, and your rights (GDPR/UK GDPR)

- **Legal basis:** where analytics apply, our legal basis is your **consent** (you opt in), which you can withdraw at any time by turning analytics off.
- **Health-data caution:** Abendrot deliberately collects **no** health, sleep, or schedule data, so no special-category (Article 9) data is processed.
- **Retention:** anonymous, aggregate analytics are retained only as long as useful for product decisions and then aggregated or deleted. {{State the exact retention period for the chosen Aptabase configuration.}}
- **Your control:** because the analytics are anonymous and aggregate, we hold no data tied to you to access or erase. You can stop all collection instantly by disabling analytics in Settings → Privacy.

<!-- [FLAG] Identify the data controller (a named person or entity) and confirm retention period.
     For a free OSS personal project this is usually the maintainer; legal should confirm the
     wording and whether a controller name/contact must be published. -->

## Changes to this policy

If this policy changes, we will update it in the repository and note the date at the top. Material changes that would expand data collection will keep the opt-in, off-by-default principle intact.

## Contact

Questions about privacy? Open an issue or discussion on [GitHub](https://github.com/matthewrball/abendrot), or contact {{CONTACT_EMAIL}}.

<!-- [FLAG] Set {{CONTACT_EMAIL}} to a real, monitored address before publishing. -->
