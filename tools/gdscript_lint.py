#!/usr/bin/env python3
"""GDScript static lint gate for Aetheria (D-033).

WHY THIS EXISTS
---------------
Godot is not invocable on the dev machine (D-009), so the only place real GDScript
compilation happens is CI. That made a whole class of bug invisible until a CI round:
L-020 shipped because `var x := some_variant_func()` is a *warning-as-error* that stops
`sect_state.gd` from compiling, which silently unregisters `class_name SectState` and
turns every call site into the misleading runtime error
`Nonexistent function 'create_from_template' in base 'GDScript'`.

This linter is pure Python (no Godot, no deps), so it runs INSTANTLY on save and in CI.
It deliberately implements only rules it can decide with ZERO false positives — a noisy
gate gets ignored. Everything it cannot know (type mismatches, missing members on a
dynamically typed base) stays the job of `tools/parse_check.gd` + the headless suite
(`08-ai-review-protocol.md`: parse/compile passing is still not "done").

RULES
-----
GD001 variant-infer   `var x := <Variant expression>` — infers a Variant-typed local,
                      which this project treats as an ERROR (warnings-as-errors), so the
                      whole script fails to compile and its `class_name` never registers.
                      Fix: declare the type (`var x: Variant = ...`) and cast at the typed
                      assignment, or wrap in a coercion (`int(...)`, `String(...)`).
GD002 private-access  `other._member` where `_member` is declared in a DIFFERENT file.
                      An underscore member is that class's private API; reaching into it
                      from another class couples callers to internals
                      (`04-coding-standards.md`). Same-file access via another receiver is
                      allowed (that is legal same-class access). Godot engine virtuals
                      (`_ready`, `_process`, ...) are exempt here.
GD003 line-too-long   Over the project line budget, which Godot's own diagnostics flag.

USAGE
-----
    python tools/gdscript_lint.py                 # scan src/ tests/ tools/ (CI)
    python tools/gdscript_lint.py --changed       # only files git reports as changed (hook)
    python tools/gdscript_lint.py --paths src     # scan a subtree
    python tools/gdscript_lint.py file1.gd ...    # scan specific files

`--changed` is what the on-save hook uses: it CHECKS only the .gd files you actually
touched (modified, staged, or untracked), which keeps the hook near-instant, while the
private-member INDEX is still built across the whole project — GD002 compares a member
against the file that owns it, so a partial index would silently miss violations.

Exit code 0 = clean, 1 = at least one violation, 2 = bad invocation.
Output is `path:line:col: CODE message`, one per line (editor-clickable).
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

# --- Configuration -----------------------------------------------------------

DEFAULT_SCAN_DIRS = ("src", "tests", "tools")
MAX_LINE_LENGTH = 100
TAB_WIDTH = 4

# Godot-owned virtuals: underscore-prefixed by engine convention, not "our" private API.
# Referencing them cross-file is not an encapsulation break (whether a TEST should *call*
# them to fake gameplay input is a separate, documented rule — L-017).
ENGINE_VIRTUALS = frozenset({
    "_ready", "_init", "_process", "_physics_process", "_input", "_unhandled_input",
    "_unhandled_key_input", "_shortcut_input", "_draw", "_enter_tree", "_exit_tree",
    "_notification", "_to_string", "_get", "_set", "_get_property_list",
    "_property_can_revert", "_property_get_revert", "_validate_property",
    "_get_configuration_warnings", "_integrate_forces", "_gui_input", "_can_drop_data",
    "_drop_data", "_get_drag_data", "_make_custom_tooltip", "_structured_text_parser",
    "_initialize", "_iteration", "_finalize",
})

# Receivers that are "this object" — accessing own privates through them is legal.
SELF_RECEIVERS = frozenset({"self", "super"})

# Built-in methods that return Variant regardless of receiver, so `:=` infers Variant.
VARIANT_METHODS = frozenset({
    "get", "call", "callv", "call_deferred", "get_meta", "parse_string", "get_setting",
    "get_value", "bind",
})

# Wrapping an expression in one of these pins a concrete type, so `:=` is safe.
COERCION_CALLS = frozenset({
    "int", "float", "bool", "str", "String", "StringName", "NodePath", "RID",
    "Vector2", "Vector2i", "Vector3", "Vector3i", "Vector4", "Vector4i",
    "Color", "Rect2", "Rect2i", "Transform2D", "Transform3D", "Basis", "Quaternion",
    "Plane", "AABB", "Projection", "Array", "Dictionary", "Callable", "Signal",
    "PackedByteArray", "PackedInt32Array", "PackedInt64Array", "PackedFloat32Array",
    "PackedFloat64Array", "PackedStringArray", "PackedVector2Array",
    "PackedVector3Array", "PackedColorArray",
    "absi", "absf", "abs", "roundi", "roundf", "round", "floori", "floorf", "floor",
    "ceili", "ceilf", "ceil", "maxi", "maxf", "max", "mini", "minf", "min",
    "clampi", "clampf", "clamp", "snappedi", "snappedf", "snapped",
    "len", "size", "hash", "is_instance_valid", "typeof",
})

IDENT = r"[A-Za-z_][A-Za-z0-9_]*"
PRIV = r"_[A-Za-z][A-Za-z0-9_]*"

RE_FUNC_RETURNS_VARIANT = re.compile(
    rf"^\s*(?:static\s+)?func\s+({IDENT})\s*\(.*\)\s*->\s*Variant\s*:"
)
RE_DEF_VAR = re.compile(rf"^\s*(?:@export[^\s]*\s+)?(?:static\s+)?var\s+({PRIV})")
RE_DEF_FUNC = re.compile(rf"^\s*(?:static\s+)?func\s+({PRIV})\s*\(")
RE_DEF_CONST = re.compile(rf"^\s*const\s+({PRIV})")
RE_DEF_SIGNAL = re.compile(rf"^\s*signal\s+({PRIV})")
RE_DEF_CLASS = re.compile(rf"^\s*class\s+({PRIV})")
RE_DEF_ENUM = re.compile(rf"^\s*enum\s+({PRIV})")
_DEF_PATTERNS = (
    RE_DEF_VAR, RE_DEF_FUNC, RE_DEF_CONST, RE_DEF_SIGNAL, RE_DEF_CLASS, RE_DEF_ENUM,
)

# `var name := expr` — only the type-INFERRING form can silently become Variant.
RE_INFER_ASSIGN = re.compile(rf"^\s*var\s+({IDENT})\s*:=\s*(.+?)\s*$")

# `<receiver>._member` — receiver is an identifier or a closing bracket (chained call).
RE_PRIVATE_ACCESS = re.compile(rf"({IDENT}|\)|\])\s*\.\s*({PRIV})")


# --- Source scrubbing --------------------------------------------------------

def strip_noncode(line: str, in_block: str | None) -> tuple[str, str | None]:
    """Blank out comments and string literals so regexes only see real code.

    Characters are replaced by spaces (never deleted) so reported columns still line up
    with the original source. Returns the scrubbed line and the still-open block-string
    delimiter (or None).
    """
    out: list[str] = []
    i = 0
    n = len(line)
    while i < n:
        if in_block is not None:
            if line.startswith(in_block, i):
                out.append(" " * len(in_block))
                i += len(in_block)
                in_block = None
            else:
                out.append(" ")
                i += 1
            continue
        ch = line[i]
        if ch == "#":
            out.append(" " * (n - i))
            break
        if line.startswith('"""', i) or line.startswith("'''", i):
            in_block = line[i:i + 3]
            out.append("   ")
            i += 3
            continue
        if ch in ('"', "'"):
            quote = ch
            out.append(" ")
            i += 1
            while i < n:
                if line[i] == "\\":
                    out.append("  ")
                    i += 2
                    continue
                if line[i] == quote:
                    out.append(" ")
                    i += 1
                    break
                out.append(" ")
                i += 1
            continue
        out.append(ch)
        i += 1
    return "".join(out), in_block


def scrub_file(text: str) -> list[str]:
    """Scrub every line of a file, carrying block-string state across lines."""
    scrubbed: list[str] = []
    in_block: str | None = None
    for raw in text.splitlines():
        code, in_block = strip_noncode(raw, in_block)
        scrubbed.append(code)
    return scrubbed


# --- Expression analysis -----------------------------------------------------

def outermost_callee(expr: str) -> str | None:
    """Name of the call that produces `expr`'s value, or None if `expr` is not a call.

    Finds the '(' matching the final ')' and reads the identifier in front of it, so
    `int(d.get("x"))` -> "int" (safe) while `d.get("x")` -> "get" (Variant), and
    `a.get_store().get_sect(k)` -> "get_sect" (the actual producer).
    """
    expr = expr.strip()
    if not expr.endswith(")"):
        return None
    depth = 0
    open_idx = -1
    for idx in range(len(expr) - 1, -1, -1):
        ch = expr[idx]
        if ch == ")":
            depth += 1
        elif ch == "(":
            depth -= 1
            if depth == 0:
                open_idx = idx
                break
    if open_idx <= 0:
        return None
    head = expr[:open_idx].rstrip()
    match = re.search(rf"({IDENT})$", head)
    return match.group(1) if match else None


def yields_variant(expr: str, variant_funcs: frozenset[str]) -> str | None:
    """Return the offending callee name if `expr` evaluates to an untyped Variant."""
    expr = expr.strip()
    while expr.startswith("await "):
        expr = expr[len("await "):].strip()
    # An explicit cast pins the type: `foo() as Array[StringName]`.
    if re.search(r"\sas\s+[A-Za-z_]", expr):
        return None
    callee = outermost_callee(expr)
    if callee is None:
        return None
    if callee in COERCION_CALLS:
        return None
    if callee in VARIANT_METHODS or callee in variant_funcs:
        return callee
    return None


# --- Indexing ----------------------------------------------------------------

def collect_gd_files(roots: list[Path], repo: Path) -> list[Path]:
    """Every .gd file under `roots` (files pass through), skipping dot-directories."""
    files: list[Path] = []
    for root in roots:
        if root.is_file() and root.suffix == ".gd":
            files.append(root)
            continue
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*.gd")):
            try:
                parts = path.relative_to(repo).parts
            except ValueError:
                parts = path.parts
            if any(part.startswith(".") for part in parts):
                continue
            files.append(path)
    seen: set[Path] = set()
    unique: list[Path] = []
    for path in files:
        resolved = path.resolve()
        if resolved not in seen:
            seen.add(resolved)
            unique.append(path)
    return unique


def relpath(path: Path, repo: Path) -> str:
    try:
        return path.resolve().relative_to(repo).as_posix()
    except ValueError:
        return path.as_posix()


def changed_gd_files(repo: Path) -> list[Path]:
    """The .gd files git reports as modified, staged or untracked.

    Keeps the on-save hook proportional to what you edited instead of the whole project.
    Returns [] (meaning "nothing to check") if git is unavailable or this is not a repo —
    the hook then stays silent rather than failing a save.
    """
    commands = (
        ["git", "diff", "--name-only", "--diff-filter=ACMR"],
        ["git", "diff", "--name-only", "--cached", "--diff-filter=ACMR"],
        ["git", "ls-files", "--others", "--exclude-standard"],
    )
    names: list[str] = []
    for command in commands:
        try:
            done = subprocess.run(
                command, cwd=repo, capture_output=True, text=True, timeout=20, check=False
            )
        except (OSError, subprocess.SubprocessError):
            return []
        if done.returncode != 0:
            return []
        names.extend(done.stdout.splitlines())
    out: list[Path] = []
    seen: set[str] = set()
    for name in names:
        name = name.strip()
        if not name.endswith(".gd") or name in seen:
            continue
        seen.add(name)
        candidate = repo / name
        if candidate.is_file():
            out.append(candidate)
    return out


def build_index(
    files: list[Path], repo: Path
) -> tuple[frozenset[str], dict[str, set[str]]]:
    """Index Variant-returning function names and which file owns each private member."""
    variant_funcs: set[str] = set()
    private_owner: dict[str, set[str]] = {}
    for path in files:
        rel = relpath(path, repo)
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for code in scrub_file(text):
            found = RE_FUNC_RETURNS_VARIANT.match(code)
            if found:
                variant_funcs.add(found.group(1))
            for pattern in _DEF_PATTERNS:
                hit = pattern.match(code)
                if hit:
                    private_owner.setdefault(hit.group(1), set()).add(rel)
                    break
    return frozenset(variant_funcs), private_owner


# --- Rules -------------------------------------------------------------------

def check_file(
    path: Path,
    repo: Path,
    variant_funcs: frozenset[str],
    private_owner: dict[str, set[str]],
    max_line_length: int,
) -> list[str]:
    rel = relpath(path, repo)
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        return [f"{rel}:1:1: GD000 cannot read file ({exc})"]

    raw_lines = text.splitlines()
    code_lines = scrub_file(text)
    problems: list[str] = []

    for num, (raw, code) in enumerate(zip(raw_lines, code_lines), start=1):
        # GD003 — line budget (tabs expanded so the measure matches what an editor shows).
        width = len(raw.expandtabs(TAB_WIDTH))
        if width > max_line_length:
            problems.append(
                f"{rel}:{num}:{max_line_length + 1}: GD003 line is {width} chars "
                f"(limit {max_line_length})"
            )

        # GD001 — `:=` inferring from a Variant expression.
        infer = RE_INFER_ASSIGN.match(code)
        if infer:
            name, rhs = infer.group(1), infer.group(2)
            callee = yields_variant(rhs, variant_funcs)
            if callee is not None:
                col = code.index(":=") + 1
                problems.append(
                    f"{rel}:{num}:{col}: GD001 '{name} :=' infers Variant from "
                    f"'{callee}(...)' -> the script will NOT compile "
                    f"(warning-as-error). Declare 'var {name}: Variant = ...' and cast "
                    f"at the typed assignment, or wrap in a coercion."
                )

        # GD002 — cross-file private member access.
        for match in RE_PRIVATE_ACCESS.finditer(code):
            receiver, member = match.group(1), match.group(2)
            if receiver in SELF_RECEIVERS or member in ENGINE_VIRTUALS:
                continue
            owners = private_owner.get(member)
            if not owners or rel in owners:
                continue
            owner_list = ", ".join(sorted(owners))
            problems.append(
                f"{rel}:{num}:{match.start(2) + 1}: GD002 '{receiver}.{member}' reaches "
                f"into private API owned by {owner_list} -> expose an intent-revealing "
                f"public method instead."
            )

    return problems


# --- Self-test ---------------------------------------------------------------

def selftest() -> int:
    """Prove each rule fires on known-bad input and stays silent on known-good input.

    This gate is load-bearing (CI blocks on it), so it must not be trusted on faith: a
    linter that silently stops matching is worse than no linter. The GD001 cases below are
    the REAL L-020 lines from `sect_state.gd` plus the fix that replaced them.
    """
    failures: list[str] = []

    def check(label: str, got: object, want: object) -> None:
        if got != want:
            failures.append(f"  {label}: got {got!r}, want {want!r}")

    variant_funcs = frozenset({"_parse_unique_id_array"})

    # GD001 must FIRE on the exact shapes that broke the Phase-06 build (L-020).
    check(
        "GD001 fires on a repo '-> Variant' helper",
        yields_variant('_parse_unique_id_array(d.get("territory", []))', variant_funcs),
        "_parse_unique_id_array",
    )
    check(
        "GD001 fires on a bare Dictionary.get()",
        yields_variant('d.get("influence", 0)', variant_funcs),
        "get",
    )
    check(
        "GD001 fires on duck-typed .call()",
        yields_variant('node.call("get_phase")', variant_funcs),
        "call",
    )
    # GD001 must STAY SILENT on the forms that actually pin a type (the L-020 fix).
    check(
        "GD001 silent on an int() coercion",
        yields_variant('int(d.get("influence", 0))', variant_funcs),
        None,
    )
    check(
        "GD001 silent on nested StringName(String(...))",
        yields_variant('StringName(String(d.get("id", "")))', variant_funcs),
        None,
    )
    check(
        "GD001 silent on an explicit 'as' cast",
        yields_variant("_parse_unique_id_array(v) as Array[StringName]", variant_funcs),
        None,
    )
    check(
        "GD001 silent on a normally-typed call chain",
        yields_variant('svc.get_store().get_sect(&"sect_a")', variant_funcs),
        None,
    )
    check(
        "GD001 silent on a plain constructor",
        yields_variant("SectState.new()", variant_funcs),
        None,
    )

    # outermost_callee picks the value PRODUCER, not the first call it sees.
    check("outermost_callee unwraps nesting", outermost_callee("int(a.get(1))"), "int")
    check("outermost_callee on a chain", outermost_callee("a.b().c()"), "c")
    check("outermost_callee on a non-call", outermost_callee("some_ident"), None)

    # Comments and strings must never be seen as code (no false GD001/GD002 from docs).
    code, block = strip_noncode('var x := d.get("k")  # var y := d.get("z")', None)
    check("comment is scrubbed", "y" in code, False)
    check("code before comment survives", "var x" in code, True)
    check("no block string left open", block, None)
    _, block = strip_noncode('text = """open', None)
    check("block string opens", block, '"""')
    code, block = strip_noncode("still inside  d._private", block)
    check("block string body is scrubbed", "_private" in code, False)

    # GD002 matching: receiver + member are captured, chained receivers work, engine
    # virtuals are exempt while project privates are not.
    match = RE_PRIVATE_ACCESS.search("\tsect._set_leader(character_id)")
    check("GD002 regex captures receiver", match.group(1) if match else None, "sect")
    check("GD002 regex captures member", match.group(2) if match else None, "_set_leader")
    chained = RE_PRIVATE_ACCESS.search("svc.get_store()._templates")
    check(
        "GD002 regex handles a chained receiver",
        chained.group(2) if chained else None,
        "_templates",
    )
    check("GD002 skips a self receiver", "self" in SELF_RECEIVERS, True)
    check("engine virtual is exempt", "_ready" in ENGINE_VIRTUALS, True)
    check("project private is not exempt", "_set_leader" in ENGINE_VIRTUALS, False)

    # Definition patterns must index every private member kind.
    check("indexes 'var _x'", bool(RE_DEF_VAR.match("var _territory: Array = []")), True)
    check("indexes 'static func _x'", bool(RE_DEF_FUNC.match("static func _edge_id(a):")), True)
    check("indexes 'const _X'", bool(RE_DEF_CONST.match("const _LIMIT := 3")), True)
    check("ignores public 'var x'", bool(RE_DEF_VAR.match("var territory: Array = []")), False)

    if failures:
        print("[gdlint] SELFTEST FAIL:")
        for failure in failures:
            print(failure)
        return 1
    print("[gdlint] SELFTEST PASS")
    return 0


# --- Entry point -------------------------------------------------------------

def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Static lint gate for GDScript (no Godot required).",
    )
    parser.add_argument(
        "--selftest", action="store_true",
        help="Verify the rules themselves fire/stay silent correctly, then exit.",
    )
    parser.add_argument(
        "--changed", action="store_true",
        help="Check only the .gd files git reports as changed (fast on-save mode).",
    )
    parser.add_argument(
        "files", nargs="*", type=Path,
        help="Specific .gd files to check (defaults to the project scan dirs).",
    )
    parser.add_argument(
        "--paths", nargs="+", default=None,
        help=f"Directories to scan (default: {' '.join(DEFAULT_SCAN_DIRS)}).",
    )
    parser.add_argument(
        "--repo", type=Path, default=Path(__file__).resolve().parent.parent,
        help="Project root (defaults to the parent of tools/).",
    )
    parser.add_argument(
        "--max-line-length", type=int, default=MAX_LINE_LENGTH,
        help=f"Line budget for GD003 (default {MAX_LINE_LENGTH}).",
    )
    args = parser.parse_args(argv)

    if args.selftest:
        return selftest()

    repo: Path = args.repo.resolve()
    if not repo.is_dir():
        print(f"[gdlint] not a directory: {repo}", file=sys.stderr)
        return 2

    # The private-member index must always span the WHOLE project, otherwise a
    # single-file (hook) run cannot tell "private member owned elsewhere" from
    # "unknown name" and would silently miss GD002.
    index_files = collect_gd_files([repo / d for d in DEFAULT_SCAN_DIRS], repo)
    variant_funcs, private_owner = build_index(index_files, repo)

    if args.files:
        targets = collect_gd_files([p.resolve() for p in args.files], repo)
    elif args.changed:
        targets = changed_gd_files(repo)
    else:
        scan_dirs = args.paths if args.paths is not None else list(DEFAULT_SCAN_DIRS)
        targets = collect_gd_files([(repo / d) for d in scan_dirs], repo)

    if not targets:
        print("[gdlint] no .gd files to check")
        return 0

    problems: list[str] = []
    for path in targets:
        problems.extend(
            check_file(path, repo, variant_funcs, private_owner, args.max_line_length)
        )

    for problem in problems:
        print(problem)

    if problems:
        codes: dict[str, int] = {}
        for problem in problems:
            code = problem.split(": ", 1)[1].split(" ", 1)[0]
            codes[code] = codes.get(code, 0) + 1
        summary = ", ".join(f"{code}={count}" for code, count in sorted(codes.items()))
        print(
            f"\n[gdlint] FAIL: {len(problems)} problem(s) in "
            f"{len(targets)} file(s) ({summary})"
        )
        return 1

    print(f"[gdlint] PASS: {len(targets)} file(s) clean")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
