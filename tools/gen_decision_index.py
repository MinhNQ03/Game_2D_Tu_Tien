#!/usr/bin/env python3
"""Decision index generator for the Aetheria Knowledge Hub.

WHY THIS EXISTS
---------------
`docs/DECISIONS.md` is the ONE authoritative decision record (freeze rule). A
hand-maintained copy of its statuses in a second file would drift (L-014: a doc
that contradicts its owner is a bug). This generator deterministically extracts
decision IDs, titles, statuses, dates, and GitHub-compatible anchors from the
source file so `docs/knowledge/DECISION_INDEX.md` is always reproducible.

It never invents a status: entries without a recorded status are listed as
"Not recorded", and any heading the parser cannot understand is reported loudly
(exit 1) instead of being silently dropped.

RULES
-----
- Source: `docs/DECISIONS.md`. Output: `docs/knowledge/DECISION_INDEX.md`.
- Skips the non-decision `## How to add a decision` how-to block.
- Handles three status locations: inline in the heading (`## D-001 — t — **Accepted** (date)`),
  the first body line (`**Status:** ...`, which may wrap), or absent entirely.
- Preserves the source's exact status wording (Accepted, Open, SUPERSEDED, DONE,
  ADOPTED, free text...). Never infers Accepted from silence.

USAGE
-----
    python3 tools/gen_decision_index.py                  # regenerate the index
    python3 tools/gen_decision_index.py --check           # exit 1 if index is stale
    python3 tools/gen_decision_index.py --selftest        # parser unit tests

Exit code 0 = ok, 1 = unparsed entries / stale index / test failure, 2 = bad invocation.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SOURCE = REPO / "docs" / "DECISIONS.md"
OUTPUT = REPO / "docs" / "knowledge" / "DECISION_INDEX.md"

HEADING_RE = re.compile(r"^## (D-[0-9]+(?:[A-Z]| [A-Z]+(?:-[A-Z]+)?)?)(.*)$")
INLINE_STATUS_RE = re.compile(r"^(.*) — \*\*(.+?)\*\*(?: \((.+?)\))?\s*$")
STATUS_LINE_RE = re.compile(r"^\*\*Status:\*\*\s*(.+?)\s*$")
DATE_RE = re.compile(r"(\d{4}-\d{2}-\d{2})")
NON_DECISION_HEADINGS = {"How to add a decision"}


@dataclass
class Decision:
    id: str
    title: str
    status: str
    date: str
    anchor: str
    line: int


@dataclass
class ParseResult:
    decisions: list = field(default_factory=list)
    unparsed: list = field(default_factory=list)  # (line_no, text, reason)
    warnings: list = field(default_factory=list)


def github_anchor(heading_text: str) -> str:
    """GitHub-compatible heading anchor.

    Mirrors html-pipeline's TableOfContentsFilter: lowercase, drop every char
    that is not a word char / space / hyphen, then map each remaining space to
    a hyphen (no collapsing — GitHub keeps the double hyphen from " — ").
    """
    t = heading_text.lower()
    t = re.sub(r"[^\w \-]", "", t, flags=re.UNICODE)
    return t.replace(" ", "-").strip("-")


def parse(source_text: str) -> ParseResult:
    result = ParseResult()
    lines = source_text.splitlines()
    # Collect (line_no, heading_text) for every ## heading.
    headings: list[tuple[int, str]] = []
    for i, line in enumerate(lines):
        m = HEADING_RE.match(line)
        if m:
            headings.append((i, line[3:]))
    seen_anchors: dict[str, int] = {}
    for idx, (line_no, heading) in enumerate(headings):
        if heading.strip() in NON_DECISION_HEADINGS:
            continue
        m = HEADING_RE.match("## " + heading)
        assert m  # already matched
        dec_id, rest = m.group(1), m.group(2).strip()
        # rest starts with " — " separator after the id; strip it.
        if rest.startswith("— "):
            rest = rest[2:]
        elif rest.startswith("—"):
            rest = rest[1:].lstrip()
        title, status, date = rest, "Not recorded", "—"
        im = INLINE_STATUS_RE.match(rest)
        if im:
            title, status = im.group(1).strip(), im.group(2).strip()
            dm = DATE_RE.search(im.group(3) or "")
            if dm:
                date = dm.group(1)
        else:
            # Look at the first non-blank body line for a **Status:** line.
            end = headings[idx + 1][0] if idx + 1 < len(headings) else len(lines)
            body_line = ""
            for j in range(line_no + 1, end):
                if lines[j].strip():
                    body_line = lines[j].strip()
                    # Join wrapped continuation lines (indented or plain text, not a new block).
                    k = j + 1
                    while k < end and lines[k].strip() and not lines[k].startswith(("#", ">", "-", "*", "|", "`")):
                        # Stop joining if the next line looks like a new sentence start is fine;
                        # we only need the first clause for the status.
                        body_line += " " + lines[k].strip()
                        k += 1
                        if len(body_line) > 300:
                            break
                    break
            sm = STATUS_LINE_RE.match(body_line)
            if sm:
                status_text = sm.group(1)
                # Take the first clause (split on " — ", " · ", or " (" patterns are kept simple:
                # status is the text up to the first "·" or " — " separator).
                status = re.split(r"\s+[·—]\s+", status_text)[0].strip().rstrip(".")
                dm = DATE_RE.search(status_text)
                if dm:
                    date = dm.group(1)
            elif body_line == "":
                result.warnings.append(f"line {line_no + 1}: {dec_id} has an empty body")
        if not title:
            result.unparsed.append((line_no + 1, heading, "empty title after parsing"))
            continue
        anchor = github_anchor(heading)
        # De-duplicate anchors the way GitHub does.
        if anchor in seen_anchors:
            seen_anchors[anchor] += 1
            anchor = f"{anchor}-{seen_anchors[anchor]}"
        else:
            seen_anchors[anchor] = 0
        result.decisions.append(
            Decision(id=dec_id, title=title, status=status, date=date, anchor=anchor, line=line_no + 1)
        )
    return result


def render(result: ParseResult) -> str:
    out: list[str] = []
    out.append("# Decision Index — Aetheria")
    out.append("")
    out.append("> **Generated file — do not edit by hand.** Regenerate with")
    out.append("> `python3 tools/gen_decision_index.py`. The authoritative record is")
    out.append("> [`docs/DECISIONS.md`](../DECISIONS.md); every entry links back to it.")
    out.append(">")
    out.append("> Status wording is preserved exactly as written in the source.")
    out.append("> `Not recorded` means the source entry states no status — it is **not**")
    out.append("> inferred as Accepted.")
    out.append("")
    out.append(f"Parsed {len(result.decisions)} decisions from `docs/DECISIONS.md`.")
    out.append("")
    out.append("| ID | Title | Status | Date |")
    out.append("|---|---|---|---|")
    for d in result.decisions:
        title = d.title.replace("|", "\\|")
        out.append(f"| {d.id} | [{title}](../DECISIONS.md#{d.anchor}) | {d.status} | {d.date} |")
    out.append("")
    if result.warnings:
        out.append("## Warnings")
        out.append("")
        for w in result.warnings:
            out.append(f"- {w}")
        out.append("")
    if result.unparsed:
        out.append("## UNPARSED — needs human attention")
        out.append("")
        out.append("These headings could not be parsed. Fix the parser or the source;")
        out.append("do not delete this section to go green.")
        out.append("")
        for line_no, text, reason in result.unparsed:
            out.append(f"- line {line_no}: `{text}` — {reason}")
        out.append("")
    return "\n".join(out)


def selftest() -> int:
    failures = 0

    def check(name: str, cond: bool) -> None:
        nonlocal failures
        if not cond:
            print(f"SELFTEST FAIL: {name}")
            failures += 1

    # F1: inline status.
    r = parse("## D-001 — Foo bar — **Accepted** (2026-10-02)\n")
    check("F1 count", len(r.decisions) == 1 and not r.unparsed)
    d = r.decisions[0]
    check("F1 fields", d.id == "D-001" and d.title == "Foo bar" and d.status == "Accepted" and d.date == "2026-10-02")

    # F1 with semicolon date note and title parens (D-074 shape).
    r = parse("## D-074 — Product direction: online multiplayer-first (supersedes Stage-1 offline-first framing) — **Accepted** (2026-10-12)\n")
    d = r.decisions[0]
    check("F1 parens title", d.title == "Product direction: online multiplayer-first (supersedes Stage-1 offline-first framing)" and d.status == "Accepted")

    # F1 Open without date.
    r = parse("## D-005 — Save serialization format  — **Open**\n")
    d = r.decisions[0]
    check("F1 open", d.status == "Open" and d.date == "—")

    # F2: status on first body line, with wrap.
    r = parse("## D-070 — Phase 19: quest\n\n**Status:** DONE — decided in `735c394` before any Phase-19\nstate-changing code; built later.\n")
    d = r.decisions[0]
    check("F2 wrapped status", d.status == "DONE")

    # F2 with · separators.
    r = parse("## D-046 — Animated character\n\n**Status:** Accepted · **Phase:** D-046 · **Scope:** art\n")
    d = r.decisions[0]
    check("F2 kv status", d.status == "Accepted")

    # F3: no status anywhere -> Not recorded, not dropped.
    r = parse("## D-059 — Phase 13: Items and the satchel\n\n**Built.** `ItemData` stuff.\n")
    d = r.decisions[0]
    check("F3 not recorded", d.status == "Not recorded" and len(r.decisions) == 1 and not r.unparsed)

    # F4/F5: special ids; D-055 collision-safe.
    r = parse("## D-055 — Base\n\n**Status:** Accepted\n\n## D-055 FOLLOW-UP — Follow up\n\n**Status:** Accepted\n")
    check("F4 ids", [d.id for d in r.decisions] == ["D-055", "D-055 FOLLOW-UP"])
    r = parse("## D-057A — Foo\n\n**Status:** Accepted\n")
    check("F5 id", r.decisions[0].id == "D-057A")

    # F6: how-to block skipped.
    r = parse("## How to add a decision\n\nSome how-to text.\n")
    check("F6 skipped", len(r.decisions) == 0 and not r.unparsed)

    # Anchor: em-dash removed, spaces to hyphens, lowercase.
    check("anchor", github_anchor("D-074 — Product direction: online (x)") == "d-074--product-direction-online-x")

    # Full-file parse: every `## D-nnn` heading parses, none is left unparsed. The expected
    # count is read from the file itself (a new decision is not a selftest failure); the floor
    # guards against a parse that silently drops the history.
    text = SOURCE.read_text(encoding="utf-8")
    full = parse(text)
    headings = len(re.findall(r"^## D-\d{3}", text, re.MULTILINE))
    check("full count==headings", len(full.decisions) == headings)
    check("full count>=75", len(full.decisions) >= 75)
    check("full unparsed==0", len(full.unparsed) == 0)
    ids = [d.id for d in full.decisions]
    check("D-074 present", "D-074" in ids)
    check("D-075 present", "D-075" in ids)
    check("D-009 superseded", any(d.id == "D-009" and "SUPERSEDED" in d.status for d in full.decisions))
    check("D-059 not recorded", any(d.id == "D-059" and d.status == "Not recorded" for d in full.decisions))
    check("D-005 open", any(d.id == "D-005" and d.status == "Open" for d in full.decisions))
    # Anchors unique.
    anchors = [d.anchor for d in full.decisions]
    check("anchors unique", len(set(anchors)) == len(anchors))

    if failures:
        print(f"gen_decision_index selftest: {failures} failure(s)")
        return 1
    print("gen_decision_index selftest: all passed")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Generate docs/knowledge/DECISION_INDEX.md from docs/DECISIONS.md")
    parser.add_argument("--check", action="store_true", help="exit 1 if the index is stale")
    parser.add_argument("--selftest", action="store_true", help="run parser unit tests")
    args = parser.parse_args(argv)
    if args.selftest:
        return selftest()
    if not SOURCE.exists():
        print(f"error: source not found: {SOURCE}", file=sys.stderr)
        return 2
    result = parse(SOURCE.read_text(encoding="utf-8"))
    text = render(result)
    if args.check:
        if not OUTPUT.exists():
            print(f"error: index missing: {OUTPUT}", file=sys.stderr)
            return 1
        current = OUTPUT.read_text(encoding="utf-8")
        if current != text:
            print(f"error: {OUTPUT} is stale — regenerate with tools/gen_decision_index.py", file=sys.stderr)
            return 1
        if result.unparsed:
            print(f"error: {len(result.unparsed)} unparsed decision heading(s)", file=sys.stderr)
            return 1
        print("decision index is current")
        return 0
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(text, encoding="utf-8")
    print(f"wrote {OUTPUT} ({len(result.decisions)} decisions)")
    for line_no, heading, reason in result.unparsed:
        print(f"UNPARSED line {line_no}: {heading} — {reason}", file=sys.stderr)
    for w in result.warnings:
        print(f"warning: {w}", file=sys.stderr)
    return 1 if result.unparsed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
