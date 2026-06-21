#!/usr/bin/env python3
"""
scrub-planning-tells.py — remove private-planning references from PUBLIC source.

The private build repo annotates code, scripts, manifests and docs with plan/contract
section refs (§4.1, §21-E5, …), doc paths (docs/research/…, docs/release/RELEASE.md),
internal vocabulary ("Mode A"/"Mode B", "Wave-1", "Lane A/C/E", "dev/dogfood"), and
"founder". The public mirror must carry NONE of these. This pass strips them while
keeping the substantive prose, across every synced file type (Swift, shell, YAML,
Ruby cask templates, plists, XML templates, man pages, Markdown).

It is deterministic and idempotent; sync-public.sh's `grep` gate is the hard guarantee
(anything missed fails the build).

Usage: scrub-planning-tells.py <public-repo-root>

Scope: TARGETS below MUST mirror the file/tree set that sync-public.sh copies into the
public mirror. Every synced path is scrubbed here AND gated by sync-public.sh; the two
lists must stay in lockstep.
"""
import re
import sys
import pathlib

ROOT = pathlib.Path(sys.argv[1])

# Trees (recursed for known text extensions) and individual files synced to public.
# KEEP IN SYNC with sync-public.sh's sync_tree/copy_file calls and its grep gate.
TARGET_TREES = [
    "App/Sources",
    "App/Resources",
    "WarmthKit/Sources",
    "WarmthKit/Tests",
    "scripts/dmg",
    "scripts/release",
    "cli/Sources",
    "cli/Tests",
    "cli/completions",
]
TARGET_FILES = [
    "WarmthKit/Package.swift",
    "project.yml",
    ".github/workflows/ci.yml",
    "cli/Package.swift",
    "cli/Package.resolved",
    "AGENTS.md",
    "docs/abendrot.1",
    "README.md",
]
# Extensions scrubbed when walking the trees above (plus extensionless completions/man).
TEXT_SUFFIXES = {
    ".swift", ".sh", ".yml", ".yaml", ".xml", ".plist", ".rb", ".template",
    ".md", ".1", ".bash", ".zsh", ".resolved", ".json", "",
}

# ---------------------------------------------------------------------------
# 1) Explicit rewrites for refs that carry useful prose, inline (non-paren) refs,
#    multi-line parens, and doc paths — applied first so the worthwhile text
#    survives the blunt passes below.
# ---------------------------------------------------------------------------
EXPLICIT = [
    # --- doc paths -> neutral phrases (longest / backticked first) -----------
    ("`docs/engine/ddc-protocol-spec.md` §5", "the DDC protocol spec"),
    ("`docs/engine/ddc-protocol-spec.md`", "the DDC protocol spec"),
    ("docs/engine/ddc-protocol-spec.md", "the DDC protocol spec"),
    ("`docs/engine/overlay-multiply-decision.md`", "the overlay-compositing notes"),
    ("docs/engine/overlay-multiply-decision.md", "the overlay-compositing notes"),
    ("docs/research/max-warmth-circadian-research.md", "the circadian research"),
    ("docs/research/reference-macos-app-skills.md", "platform reference"),
    # internal release doc path (appears with and without §N suffix / "see ...")
    ("see docs/release/RELEASE.md, mode A vs mode B", "deferred until signing is enabled"),
    ("docs/release/RELEASE.md §6", "the release runbook"),
    ("docs/release/RELEASE.md §4", "the release runbook"),
    ("docs/release/RELEASE.md \"$99 checklist\"", "the release runbook"),
    ("docs/release/RELEASE.md -> \"$99 account -> what to supply\"", "the release runbook"),
    ("see docs/release/RELEASE.md", "see the release runbook"),
    ("(see RELEASE.md: local machine, key in login keychain)",
     "(local machine, key in login keychain)"),
    ("see RELEASE.md", "see the release runbook"),
    ("(see RELEASE.md)", "(see the release runbook)"),
    ("RELEASE.md", "the release runbook"),
    # internal plan path in the build README
    ("- Plan & docs: [`docs/abendrot-plan.md`](docs/abendrot-plan.md)\n", ""),
    ("docs/abendrot-plan.md", "the project docs"),

    # --- inline (non-parenthetical) section refs (Swift comment prose) -------
    # multi-line parenthetical the blunt single-line paren pass can't span:
    # strip the "plan §N.N" lead-in but keep the tab list.
    ("(plan §4.4 tabs:", "(tabs:"),
    ("Post-§25 policy:", "Policy:"),
    ('the §25 "enabled but never warms" fix', 'the "enabled but never warms" fix'),
    ("This is the §25 fix", "This is the fix"),
    ("(§25 fix: the fallback", "(the fallback"),
    ("refined by the §25 hardware test", "refined by the hardware test"),
    ("(verified on hardware, §25)", "(verified on hardware)"),
    ("§18 RESOLVED (2026-06-17, see the overlay-compositing notes): a *true*", "A *true*"),
    ("alpha-over warm tint (§18 RESOLVED: a true multiply is impossible here)",
     "alpha-over warm tint (a true multiply is impossible here)"),
    # prose-bearing parens — keep the explanation, drop the citation
    ('(§21.3 "make the glass feel wet")', ""),
    ('(plan §5.5, §21.4 "3-3-1 variation strategy")', ""),
    ("(§21.3 critical a11y/brand fix)", "(critical a11y/brand fix)"),
    ("(§21.3 — the popover grows, it does not open a new window)",
     "(the popover grows, it does not open a new window)"),
    ('the "liquid expansion" of §21.3 — the popover', 'the "liquid expansion" — the popover'),
    ("(plan §5.2 — no spinners)", "(no spinners)"),
    ("(§9, invariant 7)", "(invariant 7)"),
    ("(§4 capability", "(capability"),
    ("(invariant 1 + §4.1 honest badges)", "(invariant 1 + honest badges)"),
    ("no-permission promise, §21‑E1)", "no-permission promise)"),
    ("(§25 — the \"external gamma is unreliable\" assumption was disproven on hardware.)",
     "(the \"external gamma is unreliable\" assumption was disproven on hardware.)"),
    ("(`.interactiveSpring`, see `revealSpring`) (§21.3", "(`.interactiveSpring`, see `revealSpring`) ("),
    ("the signature is the reveal spring (§21.3 — `.interactiveSpring`, see `revealSpring`)",
     "the signature is the reveal spring (`.interactiveSpring`, see `revealSpring`)"),
    # inline TODO / MARK / multi-line paren fragments
    ("hook (TODO §21‑E7): defaults", "hook: defaults"),
    ("detection — §25.J (DRAFT)", "detection"),
    ("(TODO §21‑E7)", ""),
    ("(contract §3 identity,", "(stable identity,"),
    ('§9 "re-applies per-display state")', 're-applies per-display state)'),
    ("snapshot + dirty flag, §9)", "snapshot + dirty flag)"),
    (", §21‑E8)", ")"),
    ("the founder selects the final accent ramp + icon before lock",
     "the final accent ramp + icon are not yet locked"),

    # --- release/build scripts: prose-bearing section + plan refs ------------
    ("DESIGN RULE (plan §21.2):", "DESIGN RULE:"),
    ("SIGNING RULE (plan §21.2):", "SIGNING RULE:"),
    ("Release gate (§21.2):", "Release gate:"),
    ("(plan §21.2 \"Homebrew cask", "(the Homebrew cask"),
    ("Contract requirements (§21.2):", "Cask requirements:"),
    ("Distribution plan (§9):", "Distribution:"),
    ("is load-bearing (plan §2.4):", "is load-bearing:"),
    ("DEVIATION FROM plan §2.4 / spec §5 path", "DEVIATION FROM the planned path"),
    ("(plan §2.4 verification additions)", "(strict verification)"),
    ("the helper is signed inside-out as part of the notarized bundle (plan §2.4)",
     "the helper is signed inside-out as part of the notarized bundle"),
    ("macOS 26 \"Tahoe\" floor (plan §3 deployment target)",
     "macOS 26 \"Tahoe\" deployment-target floor"),
    ("Plan §3 (Developer ID, notarized, outside the Mac App Store) + §9 (Hardened",
     "Developer ID, notarized, outside the Mac App Store, with the Hardened"),
    ("(would block private-framework dlopen + IOAVService per §9)",
     "(would block private-framework dlopen + IOAVService)"),
    ("Plan refs: §9 (notarytool submit --wait + stapler staple), §8/§21.2 release",
     "Notarization workflow: notarytool submit --wait + stapler staple, with release"),
    ("the audit trail; §21.2 \"parse notarytool log\")", "the audit trail)"),
    ("spctl -a -vvv is the §8 release gate", "spctl -a -vvv is the release gate"),
    ("the physical-hardware test matrix from plan §8 / §21.2.",
     "the physical-hardware test matrix."),
    ("Secret-handling rule (plan §9, §21.2):", "Secret-handling rule:"),
    ("See plan §9 (\"macOS 26 runner\").", "Requires a macOS 26 runner."),
    ("the headless suite (plan §8)", "the headless suite"),
    ("schedule parsing, state machine, identity keying, watchdog) per plan §8.",
     "schedule parsing, state machine, identity keying, watchdog)."),
    ("(plan §21.1 module split: WarmthCore is \"pure, no AppKit/IOKit\")",
     "(module split: WarmthCore is \"pure, no AppKit/IOKit\")"),
    ("from plan §8 / §21.2:", "matrix:"),
    ("LSUIElement = agent app: no Dock icon, no Cmd-Tab (plan §4.3)",
     "LSUIElement = agent app: no Dock icon, no Cmd-Tab"),
    ("permissions (contract §0.4)", "permissions"),
    # dmg scripts
    ("Why this exists (plan §9, §21.2):", "Why this exists:"),
    ("signing is enabled* (§21.2);", "signing is enabled;"),
    ("Plan refs: §9 (\"branded DMG — explicit requirement\"), §21.2 (two DMG modes),",
     "Two DMG modes (branded + plain),"),
    ("§21.4 (DMG as unboxing: split-screen cold->warm background so dragging the app",
     "with the DMG as unboxing: split-screen cold->warm background so dragging the app"),
    ("when signing is enabled (§21.2); the pretty", "when signing is enabled; the pretty"),
    ("moves the icon across the cold->warm gradient — the unboxing demo (§21.4).",
     "moves the icon across the cold->warm gradient — the unboxing demo."),
    ("Required for the branded \"unboxing\" DMG (plan §21.4)",
     "Required for the branded \"unboxing\" DMG"),
    ("Art direction (the demo-by-dragging idea, §21.4)",
     "Art direction (the demo-by-dragging idea)"),
    ("Reduce-Transparency / a11y note (§21.3):", "Reduce-Transparency / a11y note:"),
    ("DMG brand assets — Lane C deliverable contract", "DMG brand assets"),
    # WarmthKit test comment
    ("the §21‑E14\n", "the documented\n"),
    ("the §21‑E14 ", "the documented "),

    # --- "Mode A" / "Mode B" vocabulary -> neutral signing states -----------
    ("Mode-B default", "credential-less default"),
    ("Mode-B safe", "credential-less safe"),
    ("For headless CI / Mode B,", "For headless CI without credentials,"),
    ("(Mode A)", "(when signing is enabled)"),
    ("(Mode B)", "(when signing is deferred)"),
    ("Mode A only", "signing-enabled only"),
    ("In Mode B (no Apple account)", "When signing is deferred (no Apple account)"),
    ("runs end-to-end TODAY in Mode B", "runs end-to-end TODAY without credentials"),
    ("Mode B = deferred", "signing deferred"),
    ("(Mode B dev/dogfood)", "(unsigned local builds)"),
    ("Mode B / --unsigned", "--unsigned"),
    ("At Mode A,", "When signing is enabled,"),
    ("UNSIGNED pre-release (Mode B)", "UNSIGNED pre-release"),
    ("Notarize + staple (Mode A) / clean skip (Mode B)",
     "Notarize + staple when signing is enabled / clean skip otherwise"),
    ("Mode A signing identity", "signing identity"),
    ("(Mode A) notarize", "When signing is enabled: notarize"),
    ("MODE A (when the founder buys the $99 Apple Developer Program)",
     "WHEN SIGNING IS ENABLED (with an Apple Developer Program account)"),
    ("Credentials needed for Mode A", "Credentials needed when signing is enabled"),
    ("To enable notarization (Mode A)", "To enable notarization"),
    ("cleanly-skipped (Mode B)", "cleanly-skipped (no credentials)"),
    ("(Mode B — no Apple credentials configured)", "(no Apple credentials configured)"),
    ("Mode B (DEFAULT, runs TODAY, no Apple account)",
     "Default (runs TODAY, no Apple account)"),
    ("Mode A (activates ONLY when signing secrets are present)",
     "Signing path (activates ONLY when signing secrets are present)"),
    ("Signing secrets present -> Mode A available.",
     "Signing secrets present -> signing path available."),
    ("No signing secrets -> Mode B only (unsigned, plain DMG).",
     "No signing secrets -> unsigned, plain DMG only."),
    ("Build Abendrot.app (unsigned, Mode B)", "Build Abendrot.app (unsigned)"),
    ("Build plain DMG (Mode B default)", "Build plain DMG (default)"),
    ("App build (Mode B unsigned compile)", "App build (unsigned compile)"),
    ("No cert payload; Mode A cannot proceed. Exiting cleanly.",
     "No cert payload; signing cannot proceed. Exiting cleanly."),
    ("Used ONLY in Mode A (signing job).", "Used ONLY in the signing job."),
    ("sign-notarize job is skipped in Mode B", "sign-notarize job is skipped without credentials"),
    ("UNSIGNED dev/dogfood items (release.sh --unsigned)", "UNSIGNED items (release.sh --unsigned)"),
    ("mode A vs mode B", "signing enabled vs deferred"),
    # remaining bare "Mode A"/"Mode B" tokens (after the phrases above)
    ("Mode A", "signing-enabled mode"),
    ("Mode B", "credential-less mode"),

    # --- "dev/dogfood" vocabulary -> neutral ---------------------------------
    ("dev/dogfood only", "local testing only"),
    ("dev/dogfood path;", "local-testing path;"),
    ("dev/dogfood build", "local test build"),
    ("dev/dogfood release", "local test release"),
    ("UNSIGNED dev build", "UNSIGNED build"),
    ("an UNSIGNED dev/dogfood release", "an UNSIGNED local-test release"),

    # --- "Wave-1" / "Lane A/C/E" vocabulary ---------------------------------
    ("hosted via GitHub (raw) per Wave-1", "hosted via GitHub (raw)"),
    ("Binaries are hosted on GitHub Releases (Wave-1 decision),",
     "Binaries are hosted on GitHub Releases,"),
    ("HOSTING (Wave-1 decision):", "HOSTING:"),
    ("Wave-1 founder decision (signing", "the deferred-signing decision (signing"),
    ("the Wave-1 founder decision", "the deferred-signing decision"),
    ("Placeholders that depend on\n# Lane A (scheme/app name) are env vars at the top.",
     "Configurable placeholders (scheme/app name) are env vars at the top."),
    ("---- PLACEHOLDERS (confirm with Lane A) ----", "---- PLACEHOLDERS ----"),
    ("PLACEHOLDER bundle id — confirm with Lane A (e.g. app.abendrot.Abendrot).",
     "PLACEHOLDER bundle id (e.g. app.abendrot.Abendrot)."),
    ("Lane A must set SUFeedURL + SUPublicEDKey", "The app must set SUFeedURL + SUPublicEDKey"),
    ("PLACEHOLDERS: confirm with Lane A once Package.swift / xcodeproj land",
     "PLACEHOLDERS: confirm once Package.swift / xcodeproj land"),
    ("create with Lane A; defaults used", "defaults used"),
    ("Placeholder note: Lane A (engine) has NOT finalized the Xcode/SPM scheme",
     "Placeholder note: the Xcode/SPM scheme is NOT finalized"),
    ("(Lane A TBD)", "(TBD)"),
    ("or tell Lane E the\nnew numbers", "or update them here"),
    ("owned by Lane C (brand)", "brand-owned"),

    # --- "founder" -> neutral -----------------------------------------------
    ("the founder buys", "the maintainer buys"),
    ("the founder's login keychain", "the maintainer's login keychain"),
    ("the founder's 10-char Team ID", "the maintainer's 10-char Team ID"),
    ("the founder's Mac", "the maintainer's Mac"),
    ("the founder labels", "the maintainer labels"),
    # prose-bearing "founder" / dogfood phrasings in app source comments
    ("because the founder dogfoods the Release build.",
     "because the maintainer tests the Release build."),
    ("reopen the freshly-built app from the founder's Release build path",
     "reopen the freshly-built app from the local Release build path"),
    ("the dogfooding \"restart from latest build\" the founder otherwise runs by hand",
     "the \"restart from latest build\" otherwise run by hand"),
    ("founder bug fix —", "bug fix —"),
    ("founder-chosen default", "default"),
    ("pending founder design direction", "pending final design direction"),
    ("founder request, Session 11", "by request"),
    ("(founder pick)", "(default pick)"),
    ("(founder:", "(by preference:"),
    ("(founder)", ""),
    ("(founder).", "."),
    # internal doc path in an app-source comment
    ("Wording from docs/marketing/evidence-base.md claim #5", "Wording from the evidence base, claim #5"),
    ("docs/marketing/evidence-base.md", "the evidence base"),

    # --- "Lane X" organizational labels (build/brand/CI) -> neutral ----------
    ("(Lane B, app UI)", "(app UI)"),
    ("Lane E (Release Engineering & CI).", "Release engineering & CI."),
    ("Lane C dependency (BLOCKING for final art, NON-blocking for function):",
     "Brand-asset dependency (BLOCKING for final art, NON-blocking for function):"),
    ("OWNED BY LANE C\n#   (brand)", "brand-owned\n#   "),
    ("(see GEOMETRY block). Lane C: design the background to these coordinates, or\n#   tell Lane E new numbers.",
     "(see GEOMETRY block). Design the background to these coordinates, or update them here."),
    ("# Lane C art (placeholder until delivered)", "# brand art (placeholder until delivered)"),
    ("GEOMETRY (RESERVED for Lane C's split-screen cold->warm background).",
     "GEOMETRY (RESERVED for the split-screen cold->warm background)."),
    ("# Lane C: paint the gradient + the connecting arrow to land under these points.",
     "# Paint the gradient + the connecting arrow to land under these points."),
    ("include only if Lane C has delivered it.", "include only if the brand art has been delivered."),
    ("NOTE — Lane C background not found", "NOTE — branded background not found"),
]

# 1b) Generic vocabulary sweep — a safety net for any tell phrasing not enumerated
#     above, so the gate stays green even on lines we did not hand-map. Word-boundary
#     replacements keep the prose readable.
GENERIC_VOCAB = [
    (re.compile(r"\bLane [A-Z]\b"), "the team"),
    (re.compile(r"\bfounder['’]s\b"), "maintainer's"),
    (re.compile(r"\bfounder\b"), "maintainer"),
    (re.compile(r"\bdogfooding\b"), "testing"),
    (re.compile(r"\bdogfoods\b"), "tests"),
    (re.compile(r"\bdogfood\b"), "test"),
]

# ---------------------------------------------------------------------------
# 2) Blunt removal of any remaining single-line parenthetical that contains a
#    section ref, plus stray inline tokens. Run AFTER the explicit pass. The
#    character classes exclude `"` so a `(…§…)` *inside* a string literal (e.g. a
#    @Test name) only loses the citation, never the surrounding quotes —
#    preventing "unterminated string literal".
# ---------------------------------------------------------------------------
PAREN_WITH_SECTION = re.compile(r'[ \t]*\([^)\n"]*§[^)\n"]*\)')
INLINE_SECTION = re.compile(r"[ \t]*§[0-9][0-9A-Za-z.‑E\-/]*")  # e.g. §25, §21‑E14, §4.1

# Comment-line prefixes by file kind, so we only normalize whitespace artifacts
# inside comments and never touch code/markup spacing.
COMMENT_PREFIXES = ("//", "*", "#", ".\\\"")  # Swift, block-comment, shell/yaml/ruby, man-page


def clean_comment_artifacts(line: str) -> str:
    stripped = line.lstrip()
    # Only touch comment lines, so code spacing is never altered.
    if not stripped.startswith(COMMENT_PREFIXES):
        return line
    indent = line[: len(line) - len(stripped)]
    body = stripped
    # Remove empty parens left behind by citation removal, but NOT an empty paren
    # glued to an identifier/backtick (e.g. `.supported()` in a doc comment is a
    # code reference, not a planning leftover) — that would corrupt the prose AND
    # be non-idempotent (`(())` -> `()` -> ``).
    body = re.sub(r"(?<![\w`)])\(\s*\)", "", body)  # standalone empty parens only
    body = re.sub(r"\(\s+", "(", body)           # space after (
    body = re.sub(r"\s+\)", ")", body)           # space before )
    body = re.sub(r"\s+([.,;:])", r"\1", body)   # space before punctuation
    body = re.sub(r"(?<=\S)  +", " ", body)      # collapse internal double spaces
    body = re.sub(r"(//+)\s*\.\s+", r"\1 ", body)   # "// . Foo" -> "// Foo"
    body = re.sub(r"(//+)\s*—\s+", r"\1 ", body)    # "// — Foo" -> "// Foo"
    body = re.sub(r"(#+)\s*—\s+", r"\1 ", body)     # "# — Foo" -> "# Foo"
    body = body.rstrip()
    return indent + body


def scrub(text: str) -> str:
    for old, new in EXPLICIT:
        text = text.replace(old, new)
    for pat, repl in GENERIC_VOCAB:
        text = pat.sub(repl, text)
    text = PAREN_WITH_SECTION.sub("", text)
    text = INLINE_SECTION.sub("", text)
    text = "\n".join(clean_comment_artifacts(l) for l in text.split("\n"))
    return text


def iter_target_paths():
    for rel in TARGET_TREES:
        base = ROOT / rel
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if path.is_file() and path.suffix.lower() in TEXT_SUFFIXES:
                yield path
    for rel in TARGET_FILES:
        path = ROOT / rel
        if path.is_file():
            yield path


changed = 0
for path in iter_target_paths():
    try:
        original = path.read_text()
    except (UnicodeDecodeError, OSError):
        continue  # skip binary / unreadable files
    scrubbed = scrub(original)
    if scrubbed != original:
        path.write_text(scrubbed)
        changed += 1
print(f"scrub-planning-tells: rewrote {changed} file(s)")
