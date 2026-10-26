"""Headless entry for the Blender side of the Aetheria art pipeline (D-062).

    blender -b -P tools/aetheria_art_pipeline/blender/cli.py -- <actor> [<actor> ...]
    blender -b -P tools/aetheria_art_pipeline/blender/cli.py -- --save <actor>
    blender -b -P tools/aetheria_art_pipeline/blender/cli.py -- --props [<prop> ...]
    blender -b -P tools/aetheria_art_pipeline/blender/cli.py -- --only <anim>[:<dir>] <actor>

Resolve the actor first on the system-Python side (`build.py resolve <actor>`), then run this,
then `build.py pixel <actor>`. `--save` writes the canonical master .blend
(blender/aetheria_cultivator.blend) from the named actor instead of rendering.
`--only idle:down` re-renders the gameplay passes of that animation (and direction) alone, over
the frames already in work/<actor>/frames: the fast loop while fixing one pose (a full actor is
about 3 minutes, one animation a fraction of it). Finish with a full render before shipping.
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
    if args[0] == "--props":
        import build_props
        print(build_props.render_props(os.path.join(PIPE, "work", "props", "spec.json"),
                                       only=args[1:] or None))
        return 0
    if args[0] == "--only":
        if len(args) != 3:
            print(__doc__)
            return 2
        anim, _, direction = args[1].partition(":")
        spec_path = os.path.join(PIPE, "work", args[2], "spec.json")
        # a typo must fail loudly, never exit 0 having rendered nothing
        if anim not in build_actor.load_spec(spec_path)["animations"] or \
                (direction and direction not in [d for d, _ in build_actor.DIRECTIONS]):
            print("unknown animation or direction: %s" % args[1])
            return 2
        build_actor.build(spec_path)
        build_actor.render_frames(spec_path, anims=[anim],
                                  directions=[direction] if direction else None)
        return 0
    for actor in args:
        print(build_actor.build_and_render_all(actor))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
