"""The project skill pack: every real skill is uploadable to claude.ai, the index names every skill,
the ZIPs are reproducible, and the worker and planner prompts point at the pack."""

import os
import tempfile
import unittest
import zipfile
from pathlib import Path

from tests.helpers import AI, REAL_REPO as REAL, RepoCase, item

import package_skills as ps
from autopilot import prompts
from autopilot.state import empty_state, new_item

try:
    import yaml
except ImportError:  # the supervisor is stdlib-only; system Python has PyYAML for the art pipeline
    yaml = None

SKILLS = REAL / ".claude" / "skills"

# description values YAML reads differently from the text written (comment, null, bool, number,
# an alias, a block scalar, a sequence, a broken or inner quote, a nested mapping)
UNSAFE_DESCRIPTIONS = ["Run it: then stop.", "Use it #now", "#comment text", ">folded", "*alias",
                       '"half-quoted', '"a" b"', "- use when X", "? x", "] x", "ends with colon:",
                       "yes", "null", "123", "2026-01-01",
                       "0x1F", "0b101", "1.5e+3", "2026-01-01T00:00:00", ".inf", "Tab\t#x"]
SAFE_DESCRIPTIONS = ["Does one thing - use when X.", "Godot 4.7 + GDScript — traps, .uid files",
                     '"Run it: then stop."', "'it''s quoted'", "x" * 200]


def write_skill(root: Path, folder: str, head: str, body: str = "# body\n") -> Path:
    d = root / folder
    d.mkdir(parents=True)
    (d / "SKILL.md").write_text(f"---\n{head}\n---\n\n{body}", encoding="utf-8")
    return d


class RealSkills(unittest.TestCase):
    def test_every_real_skill_validates(self):
        dirs = ps.skill_dirs(SKILLS)
        self.assertGreaterEqual(len(dirs), 10)
        for d in dirs:
            self.assertEqual(ps.validate(d), [], d.name)

    def test_index_names_every_skill(self):
        index = (SKILLS / "README.md").read_text(encoding="utf-8")
        for d in ps.skill_dirs(SKILLS):
            self.assertIn(f"`{d.name}`", index)

    def test_charter_is_kept_verbatim_beside_its_summary(self):
        charter = SKILLS / "aetheria-studio-charter" / "references" / "CHARTER.md"
        text = charter.read_text(encoding="utf-8")
        for heading in ("## 0. YOUR MISSION", "## 11. SAFETY, AUTHORITY AND PROTECTED PROJECT STATE",
                        "## 14. INITIAL EXECUTION DIRECTIVE", "**FINAL DIRECTIVE**"):
            self.assertIn(heading, text)
        self.assertIn("references/CHARTER.md", (charter.parents[1] / "SKILL.md").read_text(encoding="utf-8"))


class Validation(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_a_valid_skill_passes(self):
        d = write_skill(self.root, "good-skill", "name: good-skill\ndescription: Does one thing - use when X.")
        self.assertEqual(ps.validate(d), [])

    def test_yaml_unsafe_descriptions_are_rejected_and_safe_ones_pass(self):
        for i, desc in enumerate(UNSAFE_DESCRIPTIONS):
            d = write_skill(self.root, f"bad-{i}", f"name: bad-{i}\ndescription: {desc}")
            self.assertIn("must be plain text", " ".join(ps.validate(d)), desc)
        for i, desc in enumerate(SAFE_DESCRIPTIONS):
            d = write_skill(self.root, f"ok-{i}", f"name: ok-{i}\ndescription: {desc}")
            self.assertEqual(ps.validate(d), [], desc)

    def test_a_second_line_cannot_smuggle_a_longer_description(self):
        d = write_skill(self.root, "multi", "name: multi\ndescription: " + "x" * 150 + "\n  " + "y" * 100)
        self.assertIn("second line", " ".join(ps.validate(d)))
        nested = write_skill(self.root, "nested", "name: nested\ndescription: d\nmetadata:\n  owner: aetheria")
        self.assertEqual(ps.validate(nested), [])

    def test_a_key_without_a_space_is_not_a_field(self):
        d = write_skill(self.root, "nospace", "name:nospace\ndescription: d")
        self.assertIn("not 'key: value'", " ".join(ps.validate(d)))

    @unittest.skipUnless(yaml, "PyYAML not installed")
    def test_the_validator_agrees_with_a_yaml_parser(self):
        for desc in UNSAFE_DESCRIPTIONS + SAFE_DESCRIPTIONS:
            text = f"name: agree\ndescription: {desc}"
            fields, problems = ps.frontmatter(f"---\n{text}\n---\n")
            try:
                parsed = yaml.safe_load(text)
            except yaml.YAMLError:
                parsed = None
            yaml_reads_text = (isinstance(parsed, dict) and isinstance(parsed.get("description"), str)
                               and parsed["description"] == fields.get("description"))
            self.assertEqual(problems == [], yaml_reads_text, desc)

    def test_limits_and_identity(self):
        long_desc = write_skill(self.root, "long", "name: long\ndescription: " + "x" * 201)
        self.assertIn("201 chars", " ".join(ps.validate(long_desc)))
        at_limit = write_skill(self.root, "limit", "name: limit\ndescription: " + "x" * 200)
        self.assertEqual(ps.validate(at_limit), [])
        renamed = write_skill(self.root, "folder", "name: other\ndescription: d")
        self.assertIn("differs from its folder", " ".join(ps.validate(renamed)))
        upper = write_skill(self.root, "Upper", "name: Upper\ndescription: d")
        self.assertIn("lowercase", " ".join(ps.validate(upper)))
        reserved = write_skill(self.root, "claude-helper", "name: claude-helper\ndescription: d")
        self.assertIn("reserved", " ".join(ps.validate(reserved)))
        extra = write_skill(self.root, "extra", "name: extra\ndescription: d\nmodel: x")
        self.assertIn("unknown frontmatter keys: model", " ".join(ps.validate(extra)))
        no_fm = self.root / "nofm"
        no_fm.mkdir()
        (no_fm / "SKILL.md").write_text("# no frontmatter\n", encoding="utf-8")
        self.assertIn("frontmatter", " ".join(ps.validate(no_fm)))

    def test_one_bad_skill_fails_the_run_and_nothing_is_written(self):
        write_skill(self.root, "good-skill", "name: good-skill\ndescription: d")
        write_skill(self.root, "bad", "name: wrong\ndescription: d")
        out = self.root / "out"
        self.assertEqual(ps.main(["--skills", str(self.root), "--out", str(out)]), 1)
        self.assertFalse(out.exists())

    def test_check_mode_passes_a_valid_pack_without_writing_and_an_empty_root_fails(self):
        write_skill(self.root / "pack", "good-skill", "name: good-skill\ndescription: d")
        out = self.root / "out"
        self.assertEqual(ps.main(["--check", "--skills", str(self.root / "pack"), "--out", str(out)]), 0)
        self.assertFalse(out.exists())
        out.mkdir()
        (out / "renamed-away.zip").write_bytes(b"old")
        self.assertEqual(ps.main(["--skills", str(self.root / "pack"), "--out", str(out)]), 0)
        self.assertEqual(sorted(p.name for p in out.iterdir()), [".gdignore", "good-skill.zip"])
        (self.root / "empty").mkdir()
        self.assertEqual(ps.main(["--check", "--skills", str(self.root / "empty")]), 1)
        self.assertEqual(ps.main(["--check", "--skills", str(self.root / "missing")]), 1)


class Packaging(unittest.TestCase):
    def test_zip_has_the_folder_at_its_root_and_is_reproducible(self):
        with tempfile.TemporaryDirectory() as t:
            root = Path(t)
            d = write_skill(root / "src", "pack-me", "name: pack-me\ndescription: d")
            (d / "references").mkdir()
            (d / "references" / "notes.md").write_text("n\n", encoding="utf-8")
            (d / "__pycache__").mkdir()
            (d / "__pycache__" / "x.pyc").write_bytes(b"\0")
            (d / ".cache").mkdir()
            (d / ".cache" / "x").write_text("hidden\n", encoding="utf-8")
            a = ps.package(d, root / "a")
            for f in d.rglob("*"):  # a later checkout has other mtimes and modes: bytes must not move
                os.utime(f, (1_000_000, 1_000_000))
            os.chmod(d / "SKILL.md", 0o600)
            b = ps.package(d, root / "b")
            self.assertEqual(a.read_bytes(), b.read_bytes())
            with zipfile.ZipFile(a) as zf:
                self.assertEqual(zf.namelist(), ["pack-me/SKILL.md", "pack-me/references/notes.md"])
                self.assertTrue(all(i.date_time == ps.ZIP_DATE for i in zf.infolist()))


class PromptsPointAtThePack(RepoCase):
    def state(self):
        st = empty_state({"id": "c", "branch": "feat/test", "base_sha": self.base, "mode": "test",
                          "scopes_allowed": ["test"]})
        it = new_item(item("t1"))
        st["items"][it["id"]] = it
        st["order"].append(it["id"])
        return st

    def test_worker_and_planner_prompts_name_the_skill_map_and_charter(self):
        cfg = self.cfg()
        st = self.state()
        task = prompts.render_task_prompt(cfg, st, st["items"]["t1"], self.base, "feat/test")
        self.assertIn(".claude/skills/README.md", task)
        self.assertEqual(prompts.validate_task_prompt(cfg, st, st["items"]["t1"], task), [])
        self.assertIn(".claude/skills/aetheria-studio-charter", prompts.render_planner_prompt(cfg, st, ""))
        for path in (".claude/skills/README.md", ".claude/skills/aetheria-studio-charter/SKILL.md"):
            self.assertTrue((REAL / path).is_file(), path)

    def test_every_file_the_prompts_point_at_is_policy(self):
        from autopilot import knowledge
        files = {p.relative_to(REAL).as_posix() for p in knowledge.policy_files(REAL)}
        for path in (".claude/skills/README.md", ".claude/skills/aetheria-studio-charter/SKILL.md",
                     ".claude/skills/aetheria-studio-charter/references/CHARTER.md"):
            self.assertIn(path, files)


if __name__ == "__main__":
    unittest.main()
