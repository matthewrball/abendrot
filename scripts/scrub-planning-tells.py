#!/usr/bin/env python3
"""
scrub-planning-tells.py — remove private-planning references from PUBLIC source comments.

The private build repo annotates code with plan/contract section refs (§4.1, §21-E5, …),
doc paths (docs/research/…), "founder", etc. The public mirror must carry NONE of these.
This pass strips them while keeping the substantive comment prose. It is deterministic and
idempotent; sync-public.sh's `grep` gate is the hard guarantee (anything missed fails the build).

Usage: scrub-planning-tells.py <public-repo-root>
"""
import re
import sys
import pathlib

ROOT = pathlib.Path(sys.argv[1])
TARGETS = ["App/Sources", "WarmthKit/Sources", "WarmthKit/Tests"]

# 1) Explicit rewrites for refs that carry useful prose, inline (non-paren) refs, multi-line
#    parens, and doc paths — applied first so the worthwhile text survives the blunt pass below.
EXPLICIT = [
    # doc paths -> neutral phrases (longest / backticked first)
    ("`docs/engine/ddc-protocol-spec.md` §5", "the DDC protocol spec"),
    ("`docs/engine/ddc-protocol-spec.md`", "the DDC protocol spec"),
    ("docs/engine/ddc-protocol-spec.md", "the DDC protocol spec"),
    ("`docs/engine/overlay-multiply-decision.md`", "the overlay-compositing notes"),
    ("docs/engine/overlay-multiply-decision.md", "the overlay-compositing notes"),
    ("docs/research/max-warmth-circadian-research.md", "the circadian research"),
    ("docs/research/reference-macos-app-skills.md", "platform reference"),
    # inline (non-parenthetical) section refs
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
]

# 2) Blunt removal of any remaining single-line parenthetical that contains a section ref,
#    plus stray inline tokens. Run AFTER the explicit pass. The character classes exclude `"`
#    so a `(…§…)` *inside* a Swift string literal (e.g. a @Test name) only loses the citation,
#    never the surrounding quotes — preventing "unterminated string literal".
PAREN_WITH_SECTION = re.compile(r'[ \t]*\([^)\n"]*§[^)\n"]*\)')
INLINE_SECTION = re.compile(r"[ \t]*§[0-9][0-9A-Za-z.‑E\-]*")  # e.g. §25, §21‑E14, §4.1

def clean_comment_artifacts(line: str) -> str:
    stripped = line.lstrip()
    # Only touch pure comment lines, so code spacing is never altered.
    if not (stripped.startswith("//") or stripped.startswith("*")):
        return line
    indent = line[: len(line) - len(stripped)]
    body = stripped
    body = re.sub(r"\(\s*\)", "", body)        # empty parens
    body = re.sub(r"\(\s+", "(", body)          # space after (
    body = re.sub(r"\s+\)", ")", body)          # space before )
    body = re.sub(r"\s+([.,;:])", r"\1", body)  # space before punctuation
    body = re.sub(r"(?<=\S)  +", " ", body)     # collapse internal double spaces
    body = re.sub(r"(//+)\s*\.\s+", r"\1 ", body)  # "// . Foo" -> "// Foo"
    body = re.sub(r"(//+)\s*—\s+", r"\1 ", body)   # "// — Foo" -> "// Foo"
    body = body.rstrip()
    return indent + body

def scrub(text: str) -> str:
    for old, new in EXPLICIT:
        text = text.replace(old, new)
    text = PAREN_WITH_SECTION.sub("", text)
    text = INLINE_SECTION.sub("", text)
    text = "\n".join(clean_comment_artifacts(l) for l in text.split("\n"))
    return text

changed = 0
for rel in TARGETS:
    base = ROOT / rel
    if not base.exists():
        continue
    for path in base.rglob("*.swift"):
        original = path.read_text()
        scrubbed = scrub(original)
        if scrubbed != original:
            path.write_text(scrubbed)
            changed += 1
print(f"scrub-planning-tells: rewrote {changed} file(s)")
