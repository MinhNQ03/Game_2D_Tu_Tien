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
TE = "actor_carter_te"
PEOPLE = [SHEN, LIN, KO, TE]

FLAGS = [
    ("flag_heard_village_business",
     "The player has heard one of the village's two problems out (taken or declined)."),
    ("flag_heard_elder_account",
     "The elder has given his account of the Night to the player."),
    ("flag_heard_road_ahead",
     "The player has been told what is coming to the frontier and where the road leads."),
    ("flag_outpost_issue",
     "The elder has issued the outpost's blade, coat and primer to the player, on account."),
    ("flag_lam_asked",
     "Lam Nguyet asked the player to keep her re-measuring quiet, and got no promise."),
    ("flag_lam_settled",
     "How the matter of her readings was settled: 1 kept quiet, 2 told to the elder.", 2),
    ("flag_asked_carter_load",
     "The player asked the carter what he hauls, and was told pine."),
    ("flag_vein_broke",
     "The vein under the woods has broken; what the rupture left is in the world."),
    ("flag_night_over",
     "The Night is past: 1 the player stood until the last creature fell, 2 they withdrew.", 2),
    ("flag_ko_night_said",
     "Kha Than has said his one line about how the player met the Night."),
    ("flag_lin_origin_said",
     "Lam Nguyet's one line to this Origin has been said (a line is said once, AUD-13)."),
    ("flag_te_origin_said",
     "What this Origin notices about the carter's load has been noticed."),
    # --- the Act-I bridge (D-073) ---
    ("flag_sheet_shown",
     "Who was shown the torn sheet FIRST: 1 Lam Nguyet, 2 Kha Than, 3 Tham Bat Ky.", 3),
    ("flag_lin_sheet_said",
     "Lam Nguyet has said what she will say about the sheet (read it, or refused to)."),
    ("flag_ko_sheet_said", "Kha Than has said what he will say about the sheet."),
    ("flag_shen_sheet_said", "Tham Bat Ky has said what he will say about the sheet."),
    ("flag_lin_shaft_said", "Lam Nguyet has answered the news of the sealed shaft."),
    ("flag_ko_shaft_said", "Kha Than has answered the news of the sealed shaft."),
    ("flag_shen_shaft_said", "Tham Bat Ky has answered the news of the sealed shaft."),
    ("flag_trail_origin_said",
     "What this Origin alone notices on the trail to the shaft has been noticed."),
    # --- the §6 hook beats (one per Origin with a playable canon hook line) ---
    ("flag_te_guard_said",
     "What the Hộ Tiêu alone notices about the carter's guard has been noticed."),
    ("flag_ko_wounds_said",
     "What the Lang Y alone notices about wounds on the trail has been noticed."),
    ("flag_te_appraise_said",
     "What the Nghệ Nhân alone notices appraising the carter's goods has been noticed."),
    ("flag_lin_residue_said",
     "What the Thủ Thư alone notices in Lam Nguyet's residue has been noticed."),
]

# (id, beat, title_key, [(option, record_key, [consequences])])
CHOICES = [
    # Bound to no beat: she confides when the player has taken part in the village's
    # business, which a player who talks to everyone first may reach before beat 6 is current.
    # The beat then completes the moment it is entered - a decision is never refused for
    # having been made early.
    ("choice_lam_readings", "", "STORY_CHOICE_LAM_READINGS", [
        ("kept", "STORY_CHOICE_LAM_READINGS_KEPT",
         [(Q_REGARD, LIN, "trust", 15), (Q_SET_FLAG, "flag_lam_settled", "", 1)]),
        ("told", "STORY_CHOICE_LAM_READINGS_TOLD",
         [(Q_REGARD, SHEN, "trust", 10), (Q_REGARD, LIN, "affinity", -15),
          (Q_SET_FLAG, "flag_lam_settled", "", 2)]),
    ]),
    ("choice_night_stand", "beat_night", "STORY_CHOICE_NIGHT_STAND", [
        ("stood", "STORY_CHOICE_NIGHT_STAND_STOOD",
         [(Q_REGARD, KO, "respect", 10), (Q_SET_FLAG, "flag_night_over", "", 1)]),
        ("withdrew", "STORY_CHOICE_NIGHT_STAND_WITHDREW",
         [(Q_REGARD, KO, "affinity", -5), (Q_SET_FLAG, "flag_night_over", "", 2)]),
    ]),
    # The Act-I bridge (D-073 §1): WHO is shown the torn sheet first. One decision, three
    # answers, each a different person's regard and a different piece of what happened. Bound
    # to its beat: the conversations offer it only once the prologue has ended (a flag), so the
    # beat is entered - and its scene told - before it can be answered. The regard moves are
    # first impressions of a confidence (+10, +5) and of a threat (-10): well inside the
    # ceiling, and the one that falls is on the dimension that can fall.
    ("choice_sheet_shown", "beat_whose_hand", "STORY_CHOICE_SHEET_SHOWN", [
        ("lin", "STORY_CHOICE_SHEET_SHOWN_LIN",
         [(Q_REGARD, LIN, "trust", 10), (Q_KNOWLEDGE, "know_surveyors_line", "", 0),
          (Q_SET_FLAG, "flag_sheet_shown", "", 1), (Q_SET_FLAG, "flag_lin_sheet_said", "", 1)]),
        ("ko", "STORY_CHOICE_SHEET_SHOWN_KO",
         [(Q_REGARD, KO, "trust", 5), (Q_KNOWLEDGE, "know_night_wheels", "", 0),
          (Q_SET_FLAG, "flag_sheet_shown", "", 2), (Q_SET_FLAG, "flag_ko_sheet_said", "", 1)]),
        ("shen", "STORY_CHOICE_SHEET_SHOWN_SHEN",
         [(Q_REGARD, SHEN, "affinity", -10), (Q_KNOWLEDGE, "know_shaft_claim", "", 0),
          (Q_SET_FLAG, "flag_sheet_shown", "", 3), (Q_SET_FLAG, "flag_shen_sheet_said", "", 1)]),
    ]),
]

# Beats entered with a scene: beat -> scene id, or ORIGIN_VIGNETTE for the run's own.
ORIGIN_VIGNETTE = "<origin>"
ENTRY_SCENES = {"beat_road": ORIGIN_VIGNETTE, "beat_arrival": "scene_arrival",
                "beat_warning": "scene_night_warning", "beat_night": "scene_night_rupture",
                "beat_aftermath": "scene_morning_after",
                # Act I opens on the road ahead; it comes to rest in front of a sealed door.
                "beat_whose_hand": "scene_road_ahead", "beat_standing": "scene_shaft_sealed"}
# beat -> (encounter id, the choice it answers, option when cleared, option when left)
ENCOUNTERS = {"beat_night": ("field_night", "choice_night_stand", "stood", "withdrew",
                             "flag_vein_broke")}
# (the fifth entry is the flag raised when the encounter begins)
# How the maps are LIT while a beat is current (D-073 §3): beat -> an ambience id that
# `tools/aetheria_art_pipeline/build.py ambience` writes from the Visual DNA. The Night is the
# evening it becomes due and the dark it happens in; every other beat is the map as authored.
AMBIENCE = {"beat_warning": "dusk", "beat_night": "night"}
# A one-time hint said when a beat completes (D-073 §4): beat -> (notice key, the action whose
# key the notice names). The Chronicle's key is taught when the book first has something in it
# worth opening - a record, and the first person met - and is never a permanent prompt.
HINTS = {"beat_arrival": ("UI_CHRONICLE_HINT", "chronicle")}



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
    "scene_night_warning": [
        (S_CARD, "STORY_SCENE_ARRIVAL_PLACE", "STORY_SCENE_WARNING_TIME", ""),
        (S_CAPTION, "STORY_SCENE_WARNING_1", "", ""),
        (S_CAPTION, "STORY_SCENE_WARNING_2", "", ""),
        (S_CAPTION, "STORY_SCENE_WARNING_3", "", ""),
    ],
    "scene_night_rupture": [
        (S_CARD, "STORY_SCENE_RUPTURE_PLACE", "STORY_SCENE_RUPTURE_TIME", ""),
        (S_CAPTION, "STORY_SCENE_RUPTURE_1", "", ""),
        (S_CAPTION, "STORY_SCENE_RUPTURE_2", "", ""),
        (S_CAPTION, "STORY_SCENE_RUPTURE_3", "", ""),
    ],
    "scene_road_ahead": [
        (S_CARD, "STORY_SCENE_ARRIVAL_PLACE", "STORY_SCENE_AHEAD_TIME", ""),
        (S_CAPTION, "STORY_SCENE_AHEAD_1", "", ""),
        (S_CAPTION, "STORY_SCENE_AHEAD_2", "", ""),
    ],
    # Told where the player stands, at the door (D-073): what the book says against what
    # the wax says.
    "scene_shaft_sealed": [
        (S_CAPTION, "STORY_SCENE_SHAFT_1", "", ""),
        (S_CAPTION, "STORY_SCENE_SHAFT_2", "", ""),
    ],
    "scene_morning_after": [
        (S_CARD, "STORY_SCENE_ARRIVAL_PLACE", "STORY_SCENE_MORNING_TIME", ""),
        (S_CAPTION, "STORY_SCENE_MORNING_1", "", ""),
        (S_CAPTION, "STORY_SCENE_MORNING_2", "", ""),
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
     (FLAG, "flag_heard_road_ahead", [], 1), [([], "beat_whose_hand")]),
]
# Act I, the bridge (D-073 §1): from the torn sheet to the door the book says is shut. Three
# beats on shipped systems, then the story rests. Each trigger is a fact an owner holds, so
# what the player already did counts the moment the beat is entered.
A1 = "D-073 §1; NARRATIVE_MASTER_PLAN.md §8 Act I, §4 FUTURE PAYOFF"
ACT_ONE = [
    ("beat_whose_hand", "WHOSE_HAND", A1, (CHOICE, "choice_sheet_shown", [], 1),
     [([], "beat_stake_line")]),
    ("beat_stake_line", "STAKE_LINE", A1, (KNOWS, "know_stake_socket", [], 1),
     [([], "beat_ruts")]),
    ("beat_ruts", "RUTS", A1, (KNOWS, "know_sealed_shaft", [], 1), [([], "beat_standing")]),
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
        (G_KNOWLEDGE, "know_drawn_pulse",
         "A healer reads a drawn pulse — the skill that names what is wrong (§6: can treat)."),
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


# What an Origin alone notices, kept on the record (D-073): (the flag its once-only line
# raises, the stem of its record key). Every Origin has one of each - which line that is
# differs per Origin and lives in the conversations; the Chronicle shows the ones said.
OBSERVATIONS = [("flag_te_origin_said", "CARTER"), ("flag_trail_origin_said", "TRAIL")]

# Per-origin extra observations (D-073): only origins with actual content get
# the flag. Lâm Nguyệt has Origin-specific lines for Đệ Tử (lin_rival) and
# Thủ Thư (lin_notation); the §6 hook beats add one more per Origin where the
# canon hook now has a playable line. The other origins have no such lines yet.
EXTRA_OBSERVATIONS = {
    "origin_ho_tieu": [("flag_te_guard_said", "GUARD")],
    "origin_de_tu_bi_loai": [("flag_lin_origin_said", "LIN")],
    "origin_lang_y": [("flag_ko_wounds_said", "WOUNDS")],
    "origin_nghe_nhan": [("flag_te_appraise_said", "APPRAISE")],
    "origin_thu_thu": [("flag_lin_origin_said", "LIN"), ("flag_lin_residue_said", "RESIDUE")],
}

# Scenes that happen somewhere else (the map behind them is covered): every vignette.
# Scenes that happen somewhere or somewhen else are drawn over an opaque ground.
ELSEWHERE = {"scene_morning_after", "scene_road_ahead"}
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
    flags = []
    for fid, purpose, *ceiling in FLAGS:
        fields = [("id", sn(fid)), ("purpose", '"%s"' % purpose)]
        if ceiling:  # an INT flag holding 0..ceiling
            fields += [("kind", 1), ("max_value", ceiling[0])]
        flags.append(doc.sub("story_flag_data", "F_%s" % fid, fields))
    choices = []
    for cid, beat, title, options in CHOICES:
        option_refs = []
        for oid, record, consequences in options:
            refs = []
            for i, (kind, who, dimension, delta) in enumerate(consequences):
                fields = [("kind", kind), ("character_id", sn(who)),
                          ("dimension", sn(dimension)), ("delta", delta)]
                if kind == Q_SET_FLAG:
                    fields = [("kind", kind), ("flag_id", sn(who)), ("value", delta)]
                elif kind == Q_KNOWLEDGE:
                    fields = [("kind", kind), ("knowledge_id", sn(who))]
                refs.append(doc.sub("story_consequence_data", "Q_%s_%s_%d" % (cid, oid, i),
                                    fields))
            option_refs.append(doc.sub("story_option_data", "O_%s_%s" % (cid, oid), [
                ("id", sn(oid)), ("record_key", sn(record)),
                ("consequences", doc.array("story_consequence_data", refs))]))
        choices.append(doc.sub("story_choice_data", "C_%s" % cid, [
            ("id", sn(cid)), ("beat_id", sn(beat)), ("title_key", sn(title)),
            ("options", doc.array("story_option_data", option_refs))]))
    def authored(table):
        return [one_beat(*row) for row in table]

    def one_beat(bid, stem, source, trigger_spec, branches):
        kind, subject, subjects, count = trigger_spec
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
        return doc.sub("story_beat_data", "BEAT_%s" % bid, [
            ("id", sn(bid)), ("objective_key", sn("STORY_BEAT_%s_OBJECTIVE" % stem)),
            ("record_key", sn("STORY_BEAT_%s_RECORD" % stem)), ("reveal_layer", 1),
            ("source", '"%s"' % source),
            ("entry_scene_id", sn("" if entry == ORIGIN_VIGNETTE else entry)),
            ("plays_origin_vignette", "true" if entry == ORIGIN_VIGNETTE else "false"),
            ("trigger", trigger),
            ("branches", doc.array("story_branch_data", branch_refs))]
            + ([("ambience_id", sn(AMBIENCE[bid]))] if bid in AMBIENCE else [])
            + ([("completion_hint_key", sn(HINTS[bid][0])),
                ("completion_hint_action", sn(HINTS[bid][1]))] if bid in HINTS else [])
            + ([("encounter_id", sn(ENCOUNTERS[bid][0])),
                ("encounter_choice_id", sn(ENCOUNTERS[bid][1])),
                ("encounter_cleared_option", sn(ENCOUNTERS[bid][2])),
                ("encounter_left_option", sn(ENCOUNTERS[bid][3])),
                ("encounter_flag_id", sn(ENCOUNTERS[bid][4]))]
               if bid in ENCOUNTERS else []))

    prologue = doc.sub("story_chapter_data", "CH_prologue", [
        ("id", sn("chapter_prologue")), ("title_key", sn("STORY_CHAPTER_PROLOGUE_TITLE")),
        ("act", 0), ("max_reveal_layer", 1),
        ("beats", doc.array("story_beat_data", authored(PROLOGUE)))])
    bid, stem, source = STANDING
    standing = doc.sub("story_beat_data", "BEAT_%s" % bid, [
        ("id", sn(bid)), ("objective_key", sn("STORY_BEAT_%s_OBJECTIVE" % stem)),
        ("reveal_layer", 1), ("source", '"%s"' % source),
        ("entry_scene_id", sn(ENTRY_SCENES.get(bid, ""))), ("terminal", "true")])
    act_one = doc.sub("story_chapter_data", "CH_act1", [
        ("id", sn("chapter_ke_vo_danh")), ("title_key", sn("STORY_CHAPTER_KE_VO_DANH_TITLE")),
        ("act", 1), ("max_reveal_layer", 3),
        ("beats", doc.array("story_beat_data", authored(ACT_ONE) + [standing]))])
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
            ("observation_flags", names(flag for flag, _s in OBSERVATIONS + EXTRA_OBSERVATIONS.get(oid, []))),
            ("observation_keys", names("STORY_NOTICED_%s_%s" % (place, stem)
                                       for _flag, place in OBSERVATIONS + EXTRA_OBSERVATIONS.get(oid, []))),
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
