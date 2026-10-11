#!/usr/bin/env python3
"""Author the story catalog and the origin catalog as Godot .tres resources (Phase 20, D-072).

ONE source for three generated files: `data/story/story_catalog.tres`,
`data/story/origin_catalog.tres` and `data/story/story_scene_catalog.tres` are written by
this script and by nothing else. Edit the
tables below and re-run; do not hand-edit the .tres (the next run would silently undo it).

    python3 tools/author_story_data.py            # write both files
    python3 tools/author_story_data.py --check    # exit 1 if the files on disk differ

Text is NOT here: every string the player reads is a key into `locale/aetheria.csv`.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
D = "res://src/data/story/"

# --- trigger / condition / consequence kinds (the enums in src/data/story) -------------------
SCENE_ENDED, ARRIVED, CULTIVATED, FLAG, MET, CHOICE, KNOWS = range(7)
C_FLAG, C_ORIGIN, C_CHOICE, C_KNOWS = range(4)
Q_SET_FLAG, Q_REGARD, Q_KNOWLEDGE = range(3)
G_ITEM, G_KNOWLEDGE, G_REGARD = range(3)

S_CARD, S_CAPTION, S_LINE = range(3)

SHEN, LIN, KO = "actor_elder_shen", "actor_disciple_lin", "actor_scout_ko"
PEOPLE = [SHEN, LIN, KO]

FLAGS = [
    ("flag_heard_village_business",
     "The player has heard one of the village's two problems out (taken or declined)."),
    ("flag_heard_elder_account",
     "The elder has given his account of the Night to the player."),
    ("flag_heard_road_ahead",
     "The player has been told what is coming to the frontier and where the road leads."),
]

# (id, beat, title_key, [(option, record_key, [consequences])])
CHOICES = [
    ("choice_lam_readings", "beat_confidence", "STORY_CHOICE_LAM_READINGS", [
        ("kept", "STORY_CHOICE_LAM_READINGS_KEPT", [(Q_REGARD, LIN, "trust", 15)]),
        ("told", "STORY_CHOICE_LAM_READINGS_TOLD",
         [(Q_REGARD, SHEN, "trust", 10), (Q_REGARD, LIN, "affinity", -15)]),
    ]),
    ("choice_night_stand", "beat_night", "STORY_CHOICE_NIGHT_STAND", [
        ("stood", "STORY_CHOICE_NIGHT_STAND_STOOD", [(Q_REGARD, KO, "respect", 10)]),
        ("withdrew", "STORY_CHOICE_NIGHT_STAND_WITHDREW", [(Q_REGARD, KO, "affinity", -5)]),
    ]),
]

# Beats entered with a scene: beat -> scene id, or ORIGIN_VIGNETTE for the run's own.
ORIGIN_VIGNETTE = "<origin>"
ENTRY_SCENES = {"beat_road": ORIGIN_VIGNETTE, "beat_arrival": "scene_arrival"}


def vignette(stem):
    key = "STORY_SCENE_VIGNETTE_%s_" % stem
    return [(S_CARD, key + "PLACE", key + "TIME", "")] + [
        (S_CAPTION, key + str(i), "", "") for i in (1, 2, 3)]


# scene id -> [(kind, text_key, sub_key, speaker_id)]
SCENES = {
    "scene_arrival": [
        (S_CARD, "STORY_SCENE_ARRIVAL_PLACE", "STORY_SCENE_ARRIVAL_TIME", ""),
        (S_CAPTION, "STORY_SCENE_ARRIVAL_1", "", ""),
        (S_CAPTION, "STORY_SCENE_ARRIVAL_2", "", ""),
    ],
}

M5 = "NARRATIVE_MASTER_PLAN.md §5 beat %d"
# (id, key stem, source, trigger, branches); a branch is ([conditions], next)
PROLOGUE = [
    ("beat_road", "ROAD", M5 % 2, (SCENE_ENDED, "", [], 1), [([], "beat_arrival")]),
    ("beat_arrival", "ARRIVAL", M5 % 3, (MET, "", PEOPLE, 1), [([], "beat_contacts")]),
    ("beat_contacts", "CONTACTS", M5 % 4, (MET, "", PEOPLE, 3),
     [([], "beat_village_business")]),
    ("beat_village_business", "BUSINESS", M5 % 5,
     (FLAG, "flag_heard_village_business", [], 1), [([], "beat_confidence")]),
    ("beat_confidence", "CONFIDENCE", M5 % 6, (CHOICE, "choice_lam_readings", [], 1),
     [([], "beat_warning")]),
    ("beat_warning", "WARNING", M5 % 7 + "; §4 TRIGGER", (ARRIVED, "map_field", [], 1),
     [([], "beat_night")]),
    ("beat_night", "NIGHT", M5 % 8 + "; §4 IMMEDIATE RESULT",
     (CHOICE, "choice_night_stand", [], 1), [([], "beat_aftermath")]),
    ("beat_aftermath", "AFTERMATH", M5 % 9 + "; §4 SOCIAL CONSEQUENCE",
     (FLAG, "flag_heard_elder_account", [], 1), [([], "beat_settle")]),
    ("beat_settle", "SETTLE", M5 % 10, (CULTIVATED, "", [], 1), [
        ([(C_CHOICE, "choice_lam_readings", "kept")], "beat_sheet_told"),
        ([], "beat_sheet_found"),
    ]),
    ("beat_sheet_told", "SHEET_TOLD", M5 % 11 + "; §4 FUTURE PAYOFF; D-072 §5",
     (KNOWS, "know_survey_fragment", [], 1), [([], "beat_leaving")]),
    ("beat_sheet_found", "SHEET_FOUND", M5 % 11 + "; §4 FUTURE PAYOFF; D-072 §5",
     (KNOWS, "know_survey_fragment", [], 1), [([], "beat_leaving")]),
    ("beat_leaving", "LEAVING", M5 % 12 + "; §4 WORLD CONSEQUENCE",
     (FLAG, "flag_heard_road_ahead", [], 1), [([], "beat_standing")]),
]
STANDING = ("beat_standing", "STANDING", "NARRATIVE_MASTER_PLAN.md §8 Act I: KẺ VÔ DANH")

# (id, key stem, [grants]); a grant is (kind, payload..., reason)
ORIGINS = [
    ("origin_ho_tieu", "HO_TIEU", [
        (G_ITEM, "item_kiem_thanh_thiet", 1,
         "An escort keeps their blade when everything else is taken (§6: combat footing)."),
        (G_REGARD, SHEN, "affinity", -10,
         "Word of the lost caravan reached the outpost first (§6: a damaged name)."),
    ]),
    ("origin_de_tu_bi_loai", "DE_TU_BI_LOAI", [
        (G_KNOWLEDGE, "know_dan_khi_quyet",
         "A candidate is drilled in the first breathing method (§6: formal grounding)."),
        (G_REGARD, LIN, "rivalry", 15,
         "Lâm Nguyệt passed the examination the player did not (§6: a rival who passed)."),
    ]),
    ("origin_lang_y", "LANG_Y", [
        (G_ITEM, "item_bo_huyet_dan", 2,
         "A travelling healer carries what they compound (§6: herbal knowledge)."),
    ]),
    ("origin_nghe_nhan", "NGHE_NHAN", [
        (G_KNOWLEDGE, "know_vein_stone_grades",
         "An artisan reads a stone's cut and seal at a glance (§6: can read materials)."),
    ]),
    ("origin_thu_thu", "THU_THU", [
        (G_KNOWLEDGE, "know_survey_notation",
         "A keeper of old records knows how a survey is set down (§6: literacy in records)."),
        (G_REGARD, SHEN, "affinity", -15,
         "The outpost was told to watch for a keeper of proscribed records (§6: watched)."),
    ]),
]


# Scenes that happen somewhere else (the map behind them is covered): every vignette.
ELSEWHERE = set()
for _oid, _stem, _grants in ORIGINS:
    SCENES["scene_vignette_%s" % _oid[len("origin_"):]] = vignette(_stem)
    ELSEWHERE.add("scene_vignette_%s" % _oid[len("origin_"):])


def sn(value):
    return '&"%s"' % value


class Doc:
    """A .tres under construction: ext resources, sub resources, then the root."""

    def __init__(self, script_class, scripts):
        self.script_class = script_class
        self.ext = {}
        self.ext_lines = []
        for name in scripts:
            ext_id = "s_%s" % name
            self.ext[name] = ext_id
            self.ext_lines.append('[ext_resource type="Script" path="%s%s.gd" id="%s"]'
                                  % (D, name, ext_id))
        self.subs = []

    def sub(self, script, sub_id, fields):
        lines = ['[sub_resource type="Resource" id="%s"]' % sub_id,
                 'script = ExtResource("%s")' % self.ext[script]]
        lines += ["%s = %s" % pair for pair in fields]
        self.subs.append("\n".join(lines))
        return 'SubResource("%s")' % sub_id

    def array(self, script, refs):
        return 'Array[ExtResource("%s")]([%s])' % (self.ext[script], ", ".join(refs))

    def render(self, root_script, fields):
        steps = len(self.ext_lines) + len(self.subs) + 1
        head = '[gd_resource type="Resource" script_class="%s" load_steps=%d format=3]' % (
            self.script_class, steps)
        root = ["[resource]", 'script = ExtResource("%s")' % self.ext[root_script]]
        root += ["%s = %s" % pair for pair in fields]
        return "\n\n".join([head, "\n".join(self.ext_lines)] + self.subs
                           + ["\n".join(root)]) + "\n"


def names(values):
    return "Array[StringName]([%s])" % ", ".join(sn(v) for v in values)


def story_catalog():
    doc = Doc("StoryCatalogData", [
        "story_catalog_data", "story_chapter_data", "story_beat_data", "story_trigger_data",
        "story_branch_data", "story_condition_data", "story_flag_data", "story_choice_data",
        "story_option_data", "story_consequence_data"])
    flags = [doc.sub("story_flag_data", "F_%s" % fid,
                     [("id", sn(fid)), ("purpose", '"%s"' % purpose)])
             for fid, purpose in FLAGS]
    choices = []
    for cid, beat, title, options in CHOICES:
        option_refs = []
        for oid, record, consequences in options:
            refs = []
            for i, (kind, who, dimension, delta) in enumerate(consequences):
                refs.append(doc.sub("story_consequence_data", "Q_%s_%s_%d" % (cid, oid, i), [
                    ("kind", kind), ("character_id", sn(who)), ("dimension", sn(dimension)),
                    ("delta", delta)]))
            option_refs.append(doc.sub("story_option_data", "O_%s_%s" % (cid, oid), [
                ("id", sn(oid)), ("record_key", sn(record)),
                ("consequences", doc.array("story_consequence_data", refs))]))
        choices.append(doc.sub("story_choice_data", "C_%s" % cid, [
            ("id", sn(cid)), ("beat_id", sn(beat)), ("title_key", sn(title)),
            ("options", doc.array("story_option_data", option_refs))]))
    beats = []
    for bid, stem, source, (kind, subject, subjects, count), branches in PROLOGUE:
        trigger = doc.sub("story_trigger_data", "T_%s" % bid, [
            ("kind", kind), ("subject_id", sn(subject)), ("subjects", names(subjects)),
            ("count", count)])
        branch_refs = []
        for i, (conditions, nxt) in enumerate(branches):
            cond_refs = [doc.sub("story_condition_data", "K_%s_%d_%d" % (bid, i, j), [
                ("kind", ckind), ("choice_id", sn(choice)), ("option_id", sn(option))])
                for j, (ckind, choice, option) in enumerate(conditions)]
            branch_refs.append(doc.sub("story_branch_data", "B_%s_%d" % (bid, i), [
                ("conditions", doc.array("story_condition_data", cond_refs)),
                ("next_beat_id", sn(nxt))]))
        entry = ENTRY_SCENES.get(bid, "")
        beats.append(doc.sub("story_beat_data", "BEAT_%s" % bid, [
            ("id", sn(bid)), ("objective_key", sn("STORY_BEAT_%s_OBJECTIVE" % stem)),
            ("record_key", sn("STORY_BEAT_%s_RECORD" % stem)), ("reveal_layer", 1),
            ("source", '"%s"' % source),
            ("entry_scene_id", sn("" if entry == ORIGIN_VIGNETTE else entry)),
            ("plays_origin_vignette", "true" if entry == ORIGIN_VIGNETTE else "false"),
            ("trigger", trigger),
            ("branches", doc.array("story_branch_data", branch_refs))]))
    prologue = doc.sub("story_chapter_data", "CH_prologue", [
        ("id", sn("chapter_prologue")), ("title_key", sn("STORY_CHAPTER_PROLOGUE_TITLE")),
        ("act", 0), ("max_reveal_layer", 1),
        ("beats", doc.array("story_beat_data", beats))])
    bid, stem, source = STANDING
    standing = doc.sub("story_beat_data", "BEAT_%s" % bid, [
        ("id", sn(bid)), ("objective_key", sn("STORY_BEAT_%s_OBJECTIVE" % stem)),
        ("reveal_layer", 1), ("source", '"%s"' % source), ("terminal", "true")])
    act_one = doc.sub("story_chapter_data", "CH_act1", [
        ("id", sn("chapter_ke_vo_danh")), ("title_key", sn("STORY_CHAPTER_KE_VO_DANH_TITLE")),
        ("act", 1), ("max_reveal_layer", 3),
        ("beats", doc.array("story_beat_data", [standing]))])
    return doc.render("story_catalog_data", [
        ("chapters", doc.array("story_chapter_data", [prologue, act_one])),
        ("flags", doc.array("story_flag_data", flags)),
        ("choices", doc.array("story_choice_data", choices)),
        ("start_beat_id", sn(PROLOGUE[0][0]))])


def origin_catalog():
    doc = Doc("OriginCatalogData", ["origin_catalog_data", "origin_data", "origin_grant_data"])
    entries = []
    for oid, stem, grants in ORIGINS:
        refs = []
        for i, grant in enumerate(grants):
            kind, reason = grant[0], grant[-1]
            fields = [("kind", kind)]
            if kind == G_ITEM:
                fields += [("item_id", sn(grant[1])), ("count", grant[2])]
            elif kind == G_KNOWLEDGE:
                fields += [("knowledge_id", sn(grant[1]))]
            else:
                fields += [("character_id", sn(grant[1])), ("dimension", sn(grant[2])),
                           ("delta", grant[3])]
            fields.append(("reason", '"%s"' % reason))
            refs.append(doc.sub("origin_grant_data", "G_%s_%d" % (oid, i), fields))
        key = "ORIGIN_%s_" % stem
        entries.append(doc.sub("origin_data", "ORIGIN_%s" % oid, [
            ("id", sn(oid)), ("name_key", sn(key + "NAME")),
            ("problem_key", sn(key + "PROBLEM")), ("edge_key", sn(key + "EDGE")),
            ("cost_key", sn(key + "COST")), ("goal_key", sn(key + "GOAL")),
            ("vignette_scene_id", sn("scene_vignette_%s" % oid[len("origin_"):])),
            ("grants", doc.array("origin_grant_data", refs))]))
    return doc.render("origin_catalog_data",
                      [("entries", doc.array("origin_data", entries))])


def scene_catalog():
    doc = Doc("StorySceneCatalogData",
              ["story_scene_catalog_data", "story_scene_data", "story_scene_step_data"])
    entries = []
    for scene_id in sorted(SCENES):
        refs = [doc.sub("story_scene_step_data", "STEP_%s_%d" % (scene_id, i), [
            ("kind", kind), ("text_key", sn(text)), ("sub_key", sn(sub)),
            ("speaker_id", sn(speaker))])
            for i, (kind, text, sub, speaker) in enumerate(SCENES[scene_id])]
        entries.append(doc.sub("story_scene_data", "SCENE_%s" % scene_id, [
            ("id", sn(scene_id)),
            ("elsewhere", "true" if scene_id in ELSEWHERE else "false"),
            ("steps", doc.array("story_scene_step_data", refs))]))
    return doc.render("story_scene_catalog_data",
                      [("entries", doc.array("story_scene_data", entries))])


def main():
    outputs = {
        ROOT / "data/story/story_catalog.tres": story_catalog(),
        ROOT / "data/story/origin_catalog.tres": origin_catalog(),
        ROOT / "data/story/story_scene_catalog.tres": scene_catalog(),
    }
    if "--check" in sys.argv:
        stale = [str(p.relative_to(ROOT)) for p, text in outputs.items()
                 if not p.exists() or p.read_text(encoding="utf-8") != text]
        if stale:
            print("[author_story_data] STALE (re-run without --check): %s" % ", ".join(stale))
            return 1
        print("[author_story_data] up to date")
        return 0
    for path, text in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        print("[author_story_data] wrote %s" % path.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
