"""Headless entry for the Blender side of the Aetheria art pipeline (D-062).

    blender -b -P tools/aetheria_art_pipeline/blender/cli.py -- <actor> [<actor> ...]
    blender -b -P tools/aetheria_art_pipeline/blender/cli.py -- --save <actor>

Resolve the actor first on the system-Python side (`build.py resolve <actor>`), then run this,
then `build.py pixel <actor>`. `--save` writes the canonical master .blend
(blender/aetheria_cultivator.blend) from the named actor instead of rendering.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PIPE = os.path.dirname(HERE)
os.environ["AETHERIA_PIPE"] = PIPE
for path in (HERE, os.path.join(PIPE, "model")):
    if path not in sys.path:
        sys.path.insert(0, path)

import build_actor  # noqa: E402


def main(argv):
    args = argv[argv.index("--") + 1:] if "--" in argv else []
    if not args:
        print(__doc__)
        return 2
    if args[0] == "--save":
        actor = args[1]
        build_actor.build(os.path.join(PIPE, "work", actor, "spec.json"))
        build_actor.set_mode("beauty")
        print(build_actor.save(os.path.join(HERE, "aetheria_cultivator.blend")))
        return 0
    for actor in args:
        print(build_actor.build_and_render_all(actor))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
