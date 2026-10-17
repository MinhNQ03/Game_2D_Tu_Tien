#!/usr/bin/env python3
"""code_intel — the DATA side of Aetheria's code intelligence (experience upgrade).

GDScript symbols, definitions, real call sites, signatures, engine API and scene validation are
asked of GODOT ITSELF through GodotLens (`docs/GDSCRIPT_CODE_INTELLIGENCE.md`). Godot's language
server reads only `.gd` files, so it cannot answer the questions this project's DATA raises:
which `.tres` / `.tscn` names a resource or an id, where a localization key is defined and who
shows it, which generator writes a file. This tool answers those, read-only, from the files:

    python3 tools/code_intel.py res <res://path | uid://... | file name>   who loads this resource
    python3 tools/code_intel.py id <id>          where a data id (&"know_x", "origin_y") appears
    python3 tools/code_intel.py key <LOC_KEY>    the key's two strings and every place that uses it
    python3 tools/code_intel.py scene <res://x.tscn>   its scripts, resources, connections (and
                                                 whether each script/resource file exists)
    python3 tools/code_intel.py orphans          locale keys nothing references (a review list)
    python3 tools/code_intel.py --selftest

Every hit says WHAT KIND of reference it is — `data` (a .tres/.tscn field or ext_resource),
`code` (a .gd line outside a comment), `generator` (a tools/*.py that writes data), `comment`
(a .gd comment), `doc` (Markdown) — and never invents an edge: a textual match in a comment is
reported as a comment, not as a use. Deterministic (sorted output), standard library only, and
it writes nothing.
"""
import csv
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_DIRS = {".git", ".godot", "__pycache__", "work", "design_refs", "node_modules"}
KINDS = {".tres": "data", ".tscn": "data", ".gd": "code", ".py": "generator", ".md": "doc",
         ".csv": "data", ".godot": "data", ".cfg": "data", ".yaml": "generator"}


def _files():
    for base, dirs, names in os.walk(ROOT):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
        for name in sorted(names):
            if os.path.splitext(name)[1] in KINDS:
                yield os.path.join(base, name)


def _rel(path):
    return os.path.relpath(path, ROOT)


def _kind(path, line):
    ext = os.path.splitext(path)[1]
    if ext == ".gd" and line.lstrip().startswith("#"):
        return "comment"
    if ext == ".py" and not _rel(path).startswith("tools"):
        return "doc"
    return KINDS[ext]


def search(pattern):
    """Every (kind, file, line number, text) whose line matches `pattern` (a compiled regex)."""
    hits = []
    for path in _files():
        try:
            with open(path, encoding="utf-8") as f:
                for i, line in enumerate(f, 1):
                    if pattern.search(line):
                        hits.append((_kind(path, line), _rel(path), i, line.strip()[:140]))
        except UnicodeDecodeError:
            continue
    return hits


def _print(hits):
    order = {"data": 0, "code": 1, "generator": 2, "comment": 3, "doc": 4}
    for kind, path, number, text in sorted(hits, key=lambda h: (order[h[0]], h[1], h[2])):
        print("%-9s %s:%d  %s" % (kind, path, number, text))
    counts = {}
    for h in hits:
        counts[h[0]] = counts.get(h[0], 0) + 1
    print("-- %d hit(s): %s" % (len(hits), ", ".join("%s %d" % (k, counts[k])
                                                     for k in sorted(counts, key=order.get))))


def cmd_res(target):
    name = target.split("/")[-1]
    uid = None
    if target.startswith("res://"):
        disk = os.path.join(ROOT, target[len("res://"):])
        for side in (disk + ".import", disk + ".uid"):
            if os.path.exists(side):
                with open(side, encoding="utf-8") as f:
                    m = re.search(r'uid://[a-z0-9]+', f.read())
                    uid = m.group(0) if m else uid
    terms = [re.escape(target if target.startswith(("res://", "uid://")) else name)]
    if uid:
        terms.append(re.escape(uid))
        print("uid: %s" % uid)
    _print(search(re.compile("|".join(terms))))


def cmd_id(ident):
    _print(search(re.compile(r'(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])' % re.escape(ident))))


def _locale():
    with open(os.path.join(ROOT, "locale", "aetheria.csv"), encoding="utf-8", newline="") as f:
        rows = list(csv.reader(f))
    return rows[0], {r[0]: r[1:] for r in rows[1:] if r}


def cmd_key(key):
    header, rows = _locale()
    if key not in rows:
        print("NOT DEFINED in locale/aetheria.csv")
    else:
        for lang, text in zip(header[1:], rows[key]):
            print("%s: %s" % (lang, text))
    hits = [h for h in search(re.compile(r'(?<![A-Z0-9_])%s(?![A-Z0-9_])' % re.escape(key)))
            if not h[1].endswith(".csv")]
    _print(hits)


def cmd_scene(target):
    path = os.path.join(ROOT, target[len("res://"):]) if target.startswith("res://") else target
    with open(path, encoding="utf-8") as f:
        text = f.read()
    missing = 0
    for m in re.finditer(r'\[ext_resource type="([^"]+)"[^\]]*path="([^"]+)"', text):
        exists = os.path.exists(os.path.join(ROOT, m.group(2)[len("res://"):]))
        missing += 0 if exists else 1
        print("%-8s %-14s %s" % ("ok" if exists else "MISSING", m.group(1), m.group(2)))
    nodes = re.findall(r'\[node name="([^"]+)"', text)
    conns = re.findall(r'\[connection signal="([^"]+)" from="([^"]+)" to="([^"]+)" '
                       r'method="([^"]+)"', text)
    print("-- %d node(s), %d ext_resource(s) missing, %d connection(s)"
          % (len(nodes), missing, len(conns)))
    for signal, src, dst, method in conns:
        print("connection %s.%s -> %s.%s" % (src, signal, dst, method))
    if not conns:
        print("(no signal is wired in this scene: its connections are made in code — ask "
              "GodotLens gdscript_find/references for the .connect calls)")
    return 1 if missing else 0


def cmd_orphans():
    _, rows = _locale()
    corpus = []
    for path in _files():
        if path.endswith((".tres", ".tscn", ".gd", ".py")):
            with open(path, encoding="utf-8") as f:
                corpus.append(f.read())
    blob = "\n".join(corpus)
    for key in sorted(rows):
        if key != "keys" and not re.search(r'(?<![A-Z0-9_])%s(?![A-Z0-9_])' % re.escape(key),
                                           blob):
            # keys built at runtime from a prefix (e.g. "%s_NAME") are reported, not judged
            print(key)


def selftest():
    hits = search(re.compile(r'class_name StoryService'))
    assert any(h[1] == os.path.join("src", "domain", "story", "story_service.gd") for h in hits)
    assert _kind("x.gd", "  # a comment") == "comment"
    assert _kind("x.gd", "var a := 1") == "code"
    header, rows = _locale()
    assert header[:3] == ["keys", "en", "vi"] and "UI_MENU_NEW_GAME" in rows
    print("[code_intel] selftest PASS")
    return 0


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    if argv[0] == "--selftest":
        return selftest()
    cmd, args = argv[0], argv[1:]
    table = {"res": cmd_res, "id": cmd_id, "key": cmd_key, "scene": cmd_scene}
    if cmd == "orphans":
        cmd_orphans()
        return 0
    if cmd not in table or len(args) != 1:
        print(__doc__)
        return 2
    return table[cmd](args[0]) or 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
