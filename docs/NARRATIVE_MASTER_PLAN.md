# NARRATIVE_MASTER_PLAN — Aetheria

> **Owner of:** the premise, the prologue, the Origin system, the gender policy, the act
> structure, the reveal ladder, and the branch/convergence policy.
> World *facts* belong to `docs/WORLD_BIBLE.md`; frozen names to `docs/CANON_LEDGER.md`.
> This document specifies narrative ARCHITECTURE. It implements no story engine
> (that is Phase 20) and writes no dialogue.
>
> It supersedes nothing in `docs/NARRATIVE_DIRECTION.md` — that document remains the short
> narrative north-star and its six invariants (§6 there) are carried forward verbatim. This is
> the long form it always pointed at.

---

## 1. The story this game is telling

Not *"a chosen one must save the world."*
But: **"a stranger earns a place in a dangerous world, then discovers that the world itself is
more complicated than its official story."**

The two halves are load-bearing and in that order. The first half is the whole of Acts I–III and
is intimate: a handful of people, a few favours and grudges, one unstable vein. The second half
only becomes available *because* of the first — the player learns the world is lying to them
through relationships and standing they built themselves, not through a prophecy.

## 2. Premise and player identity (FROZEN)

The player begins as **nobody**: no rank, no sect, no reputation, no destiny, no inherited power
(C-003 — the current build's sect enrolment is Phase-06 scaffolding, not canon). They are a
**PHÀM** or early **HẬU THIÊN** newcomer in the Hoang Vực frontier — the one domain in the Main
World where standing is not already allocated (`WORLD_BIBLE.md` §4.5).

The player is a Character under the same authoritative `CharacterState` model as everyone else,
with the same relationship edges. **No story system may ever special-case the player out of the
core systems** (`NARRATIVE_DIRECTION.md` §6, preserved).

What the player accumulates — and what the world reads back — is: power · knowledge ·
reputation · relationships · status · sect influence · faction influence · access · wealth ·
techniques · breakthroughs. **Identity is derived from that history. There is no morality bar.**

## 3. "Tà Đế" as an emergent identity

The title is not a class, a checkbox, an ending or a meter. It is what *other people* eventually
call the player, and different people will mean completely different things by it: tyrant · rebel
· savior · heretic · world-breaker · reformer · usurper · a slur invented by enemies · a name the
player claims · a name the player refuses.

**How it is computed (design contract, not an implementation):** at the moments the story asks
"what is this person?", it reads the same persistent state everything else reads — cultivation
path and realm, which techniques are known (and which are Cấm Pháp), knowledge discovered, the
relationship graph, sect and faction standing, world events caused, and the record of major
decisions. It never reads a single hidden score, because a single score would make the question
have one answer.

Two consequences the design must preserve:
- **A compassionate player can become Tà Đế.** Reforming or destroying the covenant harms the
  institutions that write history; the people it protected will name the player accordingly. The
  title tracks *consequence*, not cruelty.
- **A ruthless player can avoid it.** A player who serves the covenant efficiently is an
  enforcer, not a heretic — however many people they hurt doing it.
- **The player may reject the title**, and the world must still react coherently: refusal is a
  public act that some factions read as humility and others as a feint.

## 4. ĐÊM VỠ MẠCH — the inciting event (full causal chain)

The one event every later thread hangs from. It satisfies the §11 causality rule completely,
because if the inciting event is arbitrary nothing downstream can be earned.

- **CAUSE.** The frontier vein beneath Rừng Vỡ Mạch has been drawn on beyond its surveyed
  allocation for years. The survey that would have caught it is the responsibility of a
  lesser orthodox outpost that has been reporting nominal figures.
- **ACTORS.** (1) the outpost that falsified the survey; (2) a Vân Hải trading interest buying
  unsurveyed qi-dense material cheaply from the overdraw; (3) a Huyết Mạc-aligned group who
  consider an unsurveyed vein legitimately *free*; (4) the frontier settlements who live on it.
- **MOTIVATION.** The outpost needs its quota to look met or it loses its own allocation. The
  trader needs cheap material. The heterodox group needs access the covenant denies them.
  Nobody in this chain wants the vein to break.
- **TRIGGER.** A heterodox extraction attempt during a period of already-critical overdraw. Not
  sabotage — **miscalculation on top of a lie.**
- **PLAYER INVOLVEMENT.** Circumstantial, and determined by Origin (§6): escorting the caravan,
  treating the first mutated-beast casualties, appraising the material, or recognising a symbol
  in the records. **The player is not chosen and is not the target.**
- **IMMEDIATE RESULT.** Spiritual creatures mutate; travellers disappear; a caravan is attacked;
  local resources become unstable and unsafe to cultivate.
- **SOCIAL CONSEQUENCE.** The outpost suppresses the evidence — because the evidence is of its
  own falsified survey, not of the heterodox group. Several actors benefit from the chaos being
  blamed on heterodox cultivators, which is the version that reaches the great sects.
- **SYSTEM CONSEQUENCE.** Relationship edges form with the frontier's few named characters;
  local resource availability shifts; a sect becomes interested in the châu.
- **WORLD CONSEQUENCE.** A vein failure in the Hoang Vực is a covenant matter. Attention arrives.
- **FUTURE PAYOFF.** The suppressed survey is the player's first physical proof that orthodox
  records are *edited for institutional convenience* — the thread that runs through Acts VI–VII
  to the Thiên Khế itself. **What the player gets from Đêm Vỡ Mạch is information, not power.**

**Who benefits:** the outpost (if blame lands elsewhere), the trader (scarcity raises prices),
the faction that wants the covenant's frontier administration shown to be failing.
**Who loses:** the frontier settlements, the heterodox group who are blamed for a break they
caused by accident and not by design, and eventually the outpost.

## 5. The prologue — the first 30–60 minutes (FROZEN)

Resolves C-007. The `PROLOGUE` box in `GAME_FLOW.md` §1/§3.3 means exactly this.

| # | Beat | Player does | Design job |
|---|---|---|---|
| 1 | **Character creation** | gender, appearance, Origin | identity is the player's, not the game's |
| 2 | **Origin vignette** | one short scene unique to the Origin | establishes the personal problem (§6) |
| 3 | **Frontier arrival** | enter Thôn Lạc Hà | teach movement + the hub; show thin administration |
| 4 | **First social contacts** | meet 3–4 named characters | seed the relationship graph with real people |
| 5 | **First small problem** | a local, mundane, solvable task | teach that the world has its own business |
| 6 | **First relationship decisions** | choose who to help / how | first real edges: affinity/trust/respect |
| 7 | **ĐÊM VỠ MẠCH** | the vein breaks | the world acts without the player's permission |
| 8 | **First combat / exploration** | survive mutated creatures in Rừng Vỡ Mạch | teach combat verbs under pressure |
| 9 | **First consequence** | the aftermath; someone suppresses evidence | teach that actions and lies both persist |
| 10 | **First cultivation step** | first deliberate tu luyện | teach the second axis exists |
| 11 | **First mystery** | find the suppressed survey fragment | hand over *information*, never power |
| 12 | **Entry into the larger world** | the frontier is no longer the whole map | open the motivation ladder (§7) |

**The player must leave the prologue holding all five:** (1) an immediate practical goal,
(2) a personal goal from their Origin, (3) at least one relationship they care about, (4) an
unanswered mystery, (5) a concrete reason to continue. If a prologue revision drops one of
these, it is incomplete.

**What the prologue must NOT do:** grant a legendary artifact, reveal the Thiên Khế, name the
Tà Đế, assign a sect, or declare the player special.

## 6. The Origin system (FROZEN)

Five Origins, **all gender-independent** (CL-09). Origin is **run-scoped data referenced by id**
— an `OriginData` content resource, not a class, not a subclass, and not a fork of
`CharacterTemplateData` (C-011, `CONTENT_BIBLE.md`).

**Origin modifies:** story context · starting relationships · small starting resources ·
personal quests · some dialogue framing.
**Origin never determines:** weapon · sect · morality · cultivation path · ending.

| Origin | Personal problem | Hook into Đêm Vỡ Mạch | Starting advantage | Starting disadvantage | Long-term callback |
|---|---|---|---|---|---|
| **Hộ Tiêu Thất Bại** `origin_ho_tieu` | a caravan under your protection was destroyed; you are blamed | you are escorting the caravan that is attacked | combat footing; caravan contacts | debt and a damaged name | who destroyed the first caravan — and why the records disagree |
| **Đệ Tử Bị Loại** `origin_de_tu_bi_loai` | you failed a sect examination you should have passed | you were on the road home when the vein broke | formal cultivation grounding | resentment; a rival who passed | the examination was allocated, not judged |
| **Lang Y Du Phương** `origin_lang_y` | a patient died of something you now suspect was not a disease | you treat the first mutated-beast casualties | herbal/alchemical knowledge | no combat training; obligations | the "disease" was vein corruption, and someone knew |
| **Nghệ Nhân Thất Sủng** `origin_nghe_nhan` | your workshop was ruined by a patron's accusation | you are appraising the caravan's material | crafting/appraisal; can read materials | poverty; a powerful enemy | the material you appraised should not have existed |
| **Thủ Thư Cấm Lục** `origin_thu_thu` | your mentor vanished leaving incomplete records | you recognise a symbol in the vein's residue | literacy in proscribed records | watched by people who want the records | the mentor was tracing the same edited chronology |

**Convergence.** Every Origin funnels into the same Act-I hub and the same Đêm Vỡ Mạch, and every
personal thread eventually resolves into the Thiên Khế question. The threads differ in *who the
player's problem is with*, not in which world they inhabit.

## 7. The motivation ladder

Every major arc climbs the same ladder, and no arc may skip a rung:

immediate survival/practical → personal goal → regional problem → sect/faction problem →
world problem → multi-world problem → the truth about cultivation → the Tà Đế question.

The rung exists to stop the classic failure where a level-3 newcomer is asked to care about the
fate of the cosmos. Scale is *earned*, like everything else.

## 8. Act structure

Divergence happens *inside* acts; acts themselves converge. There are no parallel campaigns.

| Act | Title | Scale | Core question |
|---|---|---|---|
| **I** | **KẺ VÔ DANH** | one frontier châu | can I survive and matter here? |
| **II** | **CON ĐƯỜNG TU LUYỆN** | a sect, a rivalry | what path am I cultivating, and who taught me? |
| **III** | **QUYỀN LỰC** | sect politics, region | who really decides things? |
| **IV** | **NGŨ VỰC** | the Main World | the world is larger and its records do not agree |
| **V** | **NGOẠI GIỚI** | first Tiểu Giới | cultivation itself could have been done differently |
| **VI** | **VẾT TÍCH TÀ ĐẾ** | history | who was erased, and by whom? |
| **VII** | **THIÊN KHẾ** | the covenant | preserve, reform, destroy or replace it? |
| **VIII** | **TRỌNG THIÊN** | world law | what does power at this scale owe anyone? |
| **IX** | **TÀ ĐẾ** | identity | **what does Tà Đế mean?** |
| **X** | **ENDGAME** | accumulated world | what world did I actually leave behind? |

Act II is where a sect is **chosen** (C-003) — the first major affiliation decision, made with
enough information to mean something. Act IX's question is deliberately not "who"; by then the
player knows who, and the open question is what the word will mean now that they have filled it
in.

## 9. The reveal ladder

Nine layers, strictly ordered. A phase may not reveal layer N+1 to make a scene land.

1 Something is wrong (a vein broke) → 2 Someone caused it → 3 A sect knows more than it admits →
4 Historical records contradict each other → 5 Different worlds remember different versions →
6 Cultivation itself contains hidden assumptions → 7 The truth about the Thiên Khế →
8 The truth about the historical Tà Đế → 9 What the player will do with that truth.

Layers 1–3 are Acts I–III; 4–5 are IV–V; 6–8 are VI–VIII; 9 is IX–X. The permanently open
questions (CL-15) sit *past* layer 9 and are never closed.

### 9a. Clue-to-payoff ledger (the ONE place it is kept)

A clue the player can hold is a promise. This ledger lists every one that has SHIPPED, where
it is planted, what the player holds afterwards, the reveal layer it belongs to (§9), and
where it is owed an answer. **A phase that plants a clue adds its row; a phase that pays one
marks it PAID and names the scene; no phase may pay above the layer it is allowed (§9).**
Nothing here is new lore: every payoff is one this plan, `CANON_LEDGER.md` or a phase
handoff already states. A clue with no owed payoff is not allowed to ship (§11).

| # | Clue (what the player met) | Planted (phase · in-game source) | Held as | Layer | Owed payoff | Owner | Status |
|---|---|---|---|---|---|---|---|
| K-01 | the woods' vein "does not run quietly" | P12 · the Lạc Hà stele | `know_lac_ha_stele_record` | 1 | Đêm Vỡ Mạch itself — the vein breaks | Phase 20 | **PAID** (beat 7, the Night) |
| K-02 | Lâm Nguyệt's readings do not match the hall's | P20 · her confidence, `choice_lam_readings` | `flag_lam_settled` 1 kept / 2 told | 2 | who was drawing on the vein, shown as evidence | Phase 21 (the shaft's field book) | OPEN |
| K-03 | the creatures of the Night are not themselves | P20/D-073 · the wave's look, the vein's light | seen; no knowledge entry | 1 → 2 | what the over-drawn vein made of the thing nearest it | Phase 22 (the shaft's boss) | OPEN |
| K-04 | the outpost puts away what was found after the Night | P20 · the elder's account, beat 9 | `flag_heard_elder_account` | 3 | the outpost can no longer say the shaft was sealed (the shaft's post-boss world consequence); behind it, the falsified survey of §4 | Phase 22 (the consequence); the survey itself per §9, layer 3 | OPEN |
| K-05 | one torn page of the Terrace's survey | P20 · under the weighted stone, beat 11 | `know_survey_fragment` | 2 | the rest of the survey — the old surveyor's field book | Phase 21 | OPEN |
| K-06 | a survey is a line of four stakes; this is the old surveyor's hand | D-073 · showing the sheet to Lâm Nguyệt | `know_surveyors_line` | 2 | the fourth point is the shaft; his book is where he measured | Phase 21 | OPEN |
| K-07 | carts went up the track on nights the scout was paid to sleep | D-073 · showing the sheet to Kha Thản | `know_night_wheels` | 2 | what was taken out of the shaft (evidence, not a confession); WHO bought it is §4 ACTORS 2 and layer 3 | Phase 21 (what); layer 3 per §9 (who) | OPEN |
| K-08 | the elder says no such page was written and the shaft is sealed | D-073 · showing the sheet to the elder | `know_shaft_claim` | 3 | his word against the fresh wax on the door | Phase 22's post-boss world consequence | OPEN |
| K-09 | the third stake was pulled and the ground raked | D-073 · the socket in the clearing | `know_stake_socket` | 2 | the line was removed on purpose: physical evidence for K-04 (§4 SOCIAL CONSEQUENCE — the outpost suppresses the evidence) | Phase 21–22, with K-04 | OPEN |
| K-10 | the "sealed" shaft: fresh wax, ruts to the sill, a lock that takes a surveyor's rod | D-073 · the door in the NE rocks | `know_sealed_shaft` | 2 | the door opens (rod, never a level); the shaft was worked | Phase 21 | OPEN |
| K-11 | the carter's cart, wrecked, with pale vein-stone in its split crates | D-073 · the wreck in the woods | seen; the Thunder-Finger manual spilled from it | 2 | unsurveyed qi-dense material was being hauled out (§4 ACTORS 2: a trading interest buying it) — the buyer is layer 3 | Phase 21 (the material); layer 3 per §9 (the buyer) | OPEN |
| K-12 | each Origin's own problem, and the one thing only that Origin notices on the trail | P20 · the vignette; D-073 · the five Origin observations | `OriginData.observation_flags` | 2 | §6: each Origin's long-term callback; every personal thread resolves into the Thiên Khế question | per Origin, per §6 | OPEN |
| K-13 | who saw the sheet first | D-073 · `choice_sheet_shown` (lin / ko / shen) | the choice's record + one knowledge each | — | who stands with the player at the door; must never gate entry | Phase 21 | OPEN |
| K-14 | the escort's convoy report was sealed at Lạc Hà on the word of the carter who found the ashes — the carter who drove them in | experience upgrade · the elder's greeting to `origin_ho_tieu` | `know_convoy_report` | 2 | why the records disagree (§6 callback); WHO burned the convoy is not owed before layer 3 | per Origin, per §6 | OPEN |
| K-15 | Lâm Nguyệt passed in the disciple's place, does not know why, and was posted to the frontier; Qi takes crates to Cloud Vale before each trial | experience upgrade · `lin_rival` (`origin_de_tu_bi_loai`) | `know_trial_board` | 2 | "the examination was allocated, not judged" (§6 callback) | per Origin, per §6 | OPEN |
| K-16 | the porters out of the Lạc Hà woods grew grey nails and cold hands; Qi's is the last cart on that haul | experience upgrade · the watch's greeting to `origin_lang_y` (after the carter's hands) | `know_grey_hands` | 2 | the "disease" was the vein (§6 callback); "someone knew" is layer 3 | per Origin, per §6 | OPEN |
| K-17 | three notches are no outpost seal; what comes down from the woods rides Qi's cart only | experience upgrade · the watch's greeting to `origin_nghe_nhan` (after the crate stamp) | `know_three_notch` | 2 | "the material you appraised should not have existed" (§6 callback); the buyer is §4 ACTORS 2, layer 3 | per Origin, per §6 | OPEN |
| K-18 | the mark the mentor copied is the Lạc Hà survey's old notation, the reassigned surveyor's hand — seen lately on Qi's waybills | experience upgrade · `lin_notation` (`origin_thu_thu`) | `know_mentor_mark` | 2 | "the mentor was tracing the same edited chronology" (§6 callback); joins K-06 (the surveyor's line) | per Origin, per §6 | OPEN |

**The five leads converge on one cart (K-14..K-18).** Every Origin's first lead ends at Tề
Mộc's load — the canon's own convergence point (`STORY_NOTICED_CARTER_*`, the cart that breaks in
the Night, K-11): the player reaches the shared mystery through their own trouble, and nothing in
these rows names who buys, who ordered, or why the vein is failing now (CL-15).

**The survey is the long thread (§4 FUTURE PAYOFF):** K-05 → K-06 → K-10 → the field book
(Phase 21) → "orthodox records are edited for institutional convenience" → Acts VI–VII. Each
step may show only its own layer.

**Continuity and capability, not restated here.** The ten-act map is §8 and the reveal
ladder §9 of this document. What the player CAN DO, and how the four kinds of growth stay
apart — combat level and EXP, cảnh giới and tầng, technique mastery, knowledge — is owned by
`PROGRESSION_CULTIVATION_DESIGN.md` (§1 two axes, §4 the capability contract, §6 threat
rating in place of a level gate, §7 knowledge, §9 the master realm table, §10 dependencies)
and frozen in `CANON_LEDGER.md` CL-13 / CL-14. This ledger records only what the player has
been TOLD and is OWED.

## 10. Branching and convergence policy

**Branches read STATE, never scattered booleans:** relationships · sect state · faction state ·
quest state · story flags · world state · cultivation state · knowledge state. The shape is always
`STATE → CONDITION → BRANCH → CONSEQUENCE` (`02-game-design.md` branching contract).

**Do not branch to have branched.** A major choice must affect at least one of: a relationship ·
sect/faction standing · a reward · information · access · a future quest · world state · how the
ending is interpreted. Smaller choices legitimately change only dialogue, trust, a shortcut, quest
order or a reward — and then converge.

**Replayability comes from composition, not from forking the campaign:**
shared canon + personal Origin + relationship branches + faction branches + sect branches +
optional discoveries + convergence. Target: **70–85% shared macro canon, 15–30% meaningful
player-specific variation.**

## 11. Causality rule (binding on all content)

Every major event must define: **CAUSE → ACTORS → MOTIVATION → TRIGGER → PLAYER INVOLVEMENT →
IMMEDIATE RESULT → SOCIAL CONSEQUENCE → SYSTEM CONSEQUENCE → WORLD CONSEQUENCE → FUTURE PAYOFF.**

If the only reason an event exists is "the player needs a quest", it is **invalid**. The world has
its own causes; the player intersects them. Worked example: §4.

## 12. Gender policy (FROZEN)

Gender is **character identity**; Origin is **narrative context**. Male and female playthroughs
are the same game.

**May vary:** prologue perspective framing · personal memories · selected dialogue · relationship
framing · optional character scenes · a small number of personal quest beats.
**May not vary:** major world events · the act structure · the reveal ladder · sect/faction
politics · the Thiên Khế and Tà Đế canon · any system rule.

Explicitly forbidden: a "Male Campaign A vs Female Campaign B" split. The brief's male example
(failed caravan escort) and female example (keeper of forbidden records) are **Origins available
to any gender** (§6) — they are examples of narrative architecture, not gendered content and not
stereotypes.

## 13. The social consequence loop

The loop that makes the world feel alive, and the reason the social systems were built before the
story systems (D-011):

```
PLAYER ACTION → WORLD CHANGE → CHARACTER REACTION → RELATIONSHIP CHANGE
   → SECT / FACTION REACTION → QUEST / STORY CHANGE → WORLD SIMULATION
   → NEW EVENT → PLAYER DECISION → PLAYER IDENTITY
```

Mechanics: `SOCIAL_DESIGN.md`. The narrative requirement is that **every major story beat enters
this loop rather than bypassing it** — a story that mutates its own private flags instead of the
relationship/sect state is the failure mode this architecture exists to prevent.

## 14. Multiplayer narrative contract (no networking now)

Four separate kinds of state, frozen here so a later co-op layer cannot destroy personal canon:

| State | Scope | Later |
|---|---|---|
| **Personal story state** | per player | never shared; Player A's chapter cannot advance or erase Player B's |
| **World chronicle state** | per world/shard | may be shared or instantiated |
| **Party / instance state** | temporary | co-op dungeon/boss runs |
| **Social state** | shared | relationships, sects, factions, guild-like structures |

**The acceptance test:** two players at different points in their personal story must be able to
party, run a dungeon, fight a boss, split loot and join a world event **without** either story
state being forced to match. Detail: `MULTIPLAYER_PLAN.md`.

## 15. What this document does NOT do

No dialogue, no quest definitions, no story engine, no scripted scenes, no chapter data (the
clue ledger of §9a lists what shipped content has promised; it authors none). Those are
Phases 17–20. This is the architecture those phases must satisfy — and the reason a chapter will
be *content* rather than an engine edit.
