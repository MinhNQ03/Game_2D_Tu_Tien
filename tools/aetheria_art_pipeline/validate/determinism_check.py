"""The pixel stages are deterministic: same passes in, same bytes out (D-063).

Python randomizes str hashing per process (PYTHONHASHSEED), so anything that breaks a tie by
set or hash order can give different pixels from one run to the next — the pixelizer did, until
`pixelize._majority`. This runs the REAL build commands once per hash seed and compares every
file they write, byte for byte.

  python3 validate/determinism_check.py                       # seeds 1 2, every stage
  python3 validate/determinism_check.py --seeds 1 2 3 --stages props icons

The stages write where the game reads (the shipped art), exactly as a normal build does; what
remains afterwards is the last run's output. Needs the Blender passes in work/ (gitignored) and
the system Python with PIL. Exit status 1 on any difference.
"""
import argparse
import glob
import hashlib
import os
import subprocess
import sys

VALIDATE = os.path.dirname(os.path.abspath(__file__))
PIPE = os.path.dirname(VALIDATE)
ROOT = os.path.dirname(os.path.dirname(PIPE))

# In dependency order: the UI kit frames the portraits the actor stage writes.
STAGES = {
    "props": [os.path.join(PIPE, "build.py"), "props"],
    "icons": [os.path.join(PIPE, "build.py"), "icons"],
    "actors": [os.path.join(PIPE, "build.py"), "all-pixel"],
    "ui": [os.path.join(PIPE, "ui", "ui_kit.py")],
}
# Written by a stage without a "wrote" line (the portraits are build products in work/).
UNLISTED = {"actors": "tools/aetheria_art_pipeline/work/*/portrait.png"}


def run(stages, seed):
    """Run the stages under one hash seed; return {repo-relative path: sha256} of their output."""
    env = dict(os.environ, PYTHONHASHSEED=str(seed))
    written = set()
    for stage in stages:
        out = subprocess.run([sys.executable] + STAGES[stage], cwd=ROOT, env=env,
                             capture_output=True, text=True)
        if out.returncode != 0:
            sys.exit("stage %s failed under seed %s:\n%s" % (stage, seed, out.stderr[-2000:]))
        for line in out.stdout.splitlines():
            if line.startswith("wrote "):
                path = line.split()[1]
                written.add(os.path.relpath(path, ROOT) if os.path.isabs(path) else path)
        if stage in UNLISTED:
            written.update(os.path.relpath(p, ROOT)
                           for p in glob.glob(os.path.join(ROOT, UNLISTED[stage])))
    digests = {}
    for rel in sorted(written):
        with open(os.path.join(ROOT, rel), "rb") as f:
            digests[rel] = hashlib.sha256(f.read()).hexdigest()
    return digests


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--seeds", nargs="+", default=["1", "2"])
    ap.add_argument("--stages", nargs="+", default=list(STAGES), choices=list(STAGES))
    args = ap.parse_args(argv)
    if len(args.seeds) < 2:
        sys.exit("give at least two seeds")
    stages = [s for s in STAGES if s in args.stages]
    runs = {seed: run(stages, seed) for seed in args.seeds}
    first = args.seeds[0]
    differing = set()
    for seed in args.seeds[1:]:
        if set(runs[seed]) != set(runs[first]):
            differing.update(set(runs[seed]) ^ set(runs[first]))
        for rel, digest in runs[first].items():
            if runs[seed].get(rel) != digest:
                differing.add(rel)
    print("compared %d files across hash seeds %s (stages: %s)"
          % (len(runs[first]), " ".join(args.seeds), " ".join(stages)))
    for rel in sorted(differing):
        print("  DIFFERS: %s" % rel)
    print("DETERMINISTIC" if not differing else "NOT DETERMINISTIC: %d file(s)" % len(differing))
    return 1 if differing else 0


if __name__ == "__main__":
    sys.exit(main())
