# WORLD_BIBLE — Aetheria

> **Owner of:** cosmology, geography, the Thiên Khế, the historical Tà Đế, the sect/faction roster
> as it exists IN THE WORLD, and the rules that make all of it hold together.
> Frozen names live in `docs/CANON_LEDGER.md` (cite `CL-nn`); this document explains WHY they are
> what they are. Narrative *sequence* belongs to `docs/NARRATIVE_MASTER_PLAN.md`.
>
> Everything here is ORIGINAL to Aetheria. The design takes **structural** inspiration from
> cultivation fiction — an enormous power hierarchy, a Main World above lesser worlds, suppressed
> history — and nothing else: no characters, biographies, sects, techniques, artifacts, world
> names, plots or text from any existing novel or game.

---

## 1. The one-sentence world

**Hạo Nguyên Giới is a world that survived a cultivation catastrophe by agreeing to be governed
— and has spent the age since then forgetting that the agreement was a choice.**

Every system in Aetheria is a consequence of that sentence. The realms are what the agreement
rations. The sects are who administers it. The Tà Đạo is what it excludes. The frontier is where
it is too thin to hold. The Tà Đế is the last person who refused it.

## 2. World laws (the physics the player can rely on)

These are not flavour; content may not contradict them.

1. **Cultivation draws on spiritual veins (linh mạch).** Qi is not ambient and infinite — it
   wells up through a finite network of veins. A vein is therefore *territory, infrastructure
   and politics simultaneously*, which is why sects are geographic and why a frontier matters.
2. **Veins can break.** Overdraw, careless technique, or deliberate rupture destabilises a vein:
   wildlife mutates, qi becomes unsafe to cultivate, and the damage spreads along the network.
   This is the mechanism behind both the historical catastrophe and `ĐÊM VỠ MẠCH` (CL-08).
3. **Power gaps between macro realms are real** (CL-02). A Tiên Thiên cultivator does not lose to
   a Hậu Thiên one because of plot convenience. See §5 for the only legitimate ways down-realm
   victory happens.
4. **A realm changes what you ARE, not just what you hit for.** Perception, lifespan, movement,
   what qi you can safely touch, and what the world's institutions owe you all shift at a macro
   boundary (`PROGRESSION_CULTIVATION_DESIGN.md` §4).
5. **Worlds are separated by the Hải Giới (World Sea), not by distance.** Travel between worlds
   requires a gate and the knowledge to use it — never merely a long walk or a level
   (`MAP_DUNGEON_DESIGN.md` §3).
6. **Records are artefacts, not facts.** Every archive in the world was written by somebody with
   interests. The game never hands the player an omniscient narrator.

## 3. Cosmology

```
VÔ GIỚI  ───────── the unknown beyond. Structural only: it exists so the ladder never ends.
   │
HẢI GIỚI ───────── the World Sea: the medium between worlds, and the reason they are separate.
   │                Crossing it is an achievement, not a journey.
   ├── HẠO NGUYÊN GIỚI   the MAIN WORLD — 5 đại vực, 12 châu. Strongest known civilisation.
   ├── TIỂU GIỚI         Minor Worlds — lesser scale, SPECIALISED traditions.
   ├── TÀN GIỚI          Lost/Sealed Worlds — the people are gone, the knowledge is not.
   └── HỦ GIỚI           Corrupted/Fallen Worlds — broken by a cultivation catastrophe.
```

**Why this shape and not a flat continent:** a single landmass can only grow by adding more of
itself, so its twentieth region is its fifth region with a different palette. A layered cosmos
grows by adding *kinds* of place — and, more importantly, it lets the player's understanding of
the world expand, which is the actual progression fantasy ("the visible world is one layer of a
much larger reality"). The UI is built to make that expansion legible (`UI_UX_BIBLE.md` §6).

**Why four categories of non-main world:** each answers a different design need, and anything
that does not answer one of them should not be built (§9).

| Category | Design job |
|---|---|
| **Tiểu Giới** | teach the player a cultivation tradition the Main World does not have |
| **Tàn Giới** | deliver *knowledge* and history — the archive the orthodox record contradicts |
| **Hủ Giới** | deliver danger and consequence — what a broken vein network becomes at world scale |
| **Vô Giới** | keep the hierarchy open; a horizon, not a destination |

## 4. The Main World: Hạo Nguyên Giới

Five **đại vực** (great domains), twelve **châu** (provinces). The vực are not nations — they are
*regimes of cultivation*: each one has a different answer to the question "who may draw on the
veins, and at what cost?"

### 4.1 Thiên Nguyên Vực — the orthodox heartland
Seat of the Thiên Khế. Dense, administered vein networks; the great orthodox sects; formal
examination into cultivation. Stability is real here and so is the ceiling: a disciple's access
is allocated. **Houses:** Thanh Vân Tông (CL-11). **Player arrives late** — this is Act IV, and
it should feel like entering a capital.

### 4.2 Huyết Mạc Vực — the heterodox domain
Traditions the orthodox classify as tà đạo (CL-01). Methods here extract more from a vein and
more from the cultivator; progress is faster and the price is physical. Not a land of villains —
a land that made the opposite trade. **Houses:** Xích Diễm Tông.

### 4.3 Vân Hải Vực — the neutral domain
Trade, information, mercenary cultivation, and the only serious *neutral scholarship* in the
world — which is why the third record of the Tà Đế survives here (CL-07). Sells to both sides and
depends on neither; the Thiên Khế tolerates it because an unaligned archive is also a useful one.

### 4.4 Cổ Tích Vực — the domain of ruins
Bí cảnh and remains from before the covenant. The past is physically present and physically
dangerous. This is where Tàn Giới gates are found, and where the official chronology starts to
visibly not fit the evidence.

### 4.5 Hoang Vực — the wild frontier *(the player starts here)*
Thin administration, unstable veins, mortals and tán tu living beside the lesser outposts of
larger powers. **This is the only vực where a nobody can accumulate standing**, because it is the
only one where standing is not already allocated — which is precisely why the game starts here
and why `NARRATIVE_DIRECTION.md` §1's "big enough to matter to no one important yet" is correct
canon.

**The starting châu** holds `map_hub` → **Thôn Lạc Hà** and `map_field` → **Rừng Vỡ Mạch**
(CL-11). The vein beneath Rừng Vỡ Mạch is the one that breaks (CL-08). The other eleven châu are
named and detailed when their content phase arrives — adding a châu is content, not design.

## 5. Power gaps, and the only honest ways to win down-realm

World law 3 says gaps are real. But a game in which the stronger number always wins has no
tactics, so canon fixes an explicit, closed list of legitimate reasons a lower-realm character
beats a higher one. Content must use one of these and *show* it:

superior technique · superior build interaction · preparation · terrain · environmental advantage
· an injured or distracted opponent · a Cấm Pháp price paid · artifact interaction · a
psychological or social lever · a knowledge advantage · a specific matchup.

**Forbidden:** "the player pressed a button harder". A down-realm victory with no named reason
invalidates the hierarchy, and once the hierarchy is invalid the entire progression fantasy is
decorative.

## 6. THIÊN KHẾ — the Heaven Covenant

**What everyone agrees on.** An age ago the vein network was collapsing — the catastrophe that
produced the Hủ Giới. A covenant was made. Since then, the veins are surveyed, allocated and
protected; certain methods are proscribed; inter-sect war has a ceiling; and the world has not
broken again.

**The orthodox reading.** The Thiên Khế is civilisation. Without allocation, every sect overdraws
every vein, and the catastrophe repeats. The proscriptions are safety rules written in blood.

**What the evidence also supports.** Allocation requires *allocators*. The covenant did not
merely stop the bleeding; it created a permanent institutional interest in the bleeding being
*possible*. Several proscribed methods, on examination, are not dangerous at all — they are
merely methods that let a cultivator draw without going through the survey. And the proscribed
list has grown in every era, while the recorded justifications have become shorter.

**Neither reading is "the twist."** Both are true at once, which is why the player's decision in
Act VII is a real decision. Four stances, each with a coherent world reaction:

| Stance | What the world does |
|---|---|
| **Preserve** | the orthodox owe the player; the heterodox mark them an enforcer; the ceiling stays |
| **Reform** | both sides distrust the player; the reform creates new factions and new beneficiaries |
| **Destroy** | access opens to everyone, including those who will overdraw; a second catastrophe becomes possible |
| **Replace** | the player becomes an allocator — and inherits the exact institutional interest they objected to |

The fourth is the designed trap, and it is the most natural route to being called Tà Đế by people
who are not wrong.

## 7. The historical Tà Đế

One person, three records (CL-07), and the game never adjudicates between them — it gives the
player all three plus the physical evidence and lets them conclude.

- **Orthodox:** a tyrant who broke the veins out of ambition and was put down. Personal name
  struck from the archives — *a detail that is itself evidence*, since the orthodox record
  otherwise names its enemies gladly.
- **Heterodox:** **Khai Mạch Nhân**, the Vein-Opener — someone who tried to end the rationing and
  was destroyed for it.
- **Neutral (Vân Hải):** **Hạ Vô Tướng**, an attested Ngự Thiên cultivator whose documents show
  signs of later editing — in both directions.

**The player is not their heir.** No reincarnation, no bloodline, no inherited artifact, no
destiny. What the player can inherit is the *question*: the same world, the same covenant, the
same choice. When the world eventually calls the player Tà Đế, it will be using a word whose
meaning the player has spent a hundred hours filling in — which is why Act IX's question is "what
does Tà Đế mean?" and not "who is Tà Đế?"

## 8. Sects as they exist in the world

Sect *mechanics* are `SOCIAL_DESIGN.md` §4; here is who actually exists, and the rule that every
future sect must satisfy: **it must have a defensible internal logic and an internal
disagreement.** No sect may be authored as simply good or simply evil (C-005).

### Thanh Vân Tông — `sect_azure_cloud` · orthodox · tier 3 · Thiên Nguyên Vực
Doctrine (shipped): *"Ride the clouds; temper the heart before the blade."* Allocation-compliant,
examination-based, genuinely cares about its disciples' survival — and genuinely enforces a
ceiling on them. **Internal disagreement (authored in Phase 07, D-042):** those who believe the
ceiling is the price of not repeating the catastrophe, versus those who have watched talented
disciples age out of their potential waiting for an allocation.

Three factions now carry that argument (`data/factions/`). None is the villain (C-005) — each is
the correct answer to a different question:

- **Vân Đài — the Cloud Terrace** · `faction_azure_terrace` · LOYALIST · influence 45.
  The elders who administer the examination. The ceiling is the price of not repeating the
  catastrophe; the allocation is not a cage, it is the reason there is still a sect to belong to.
  They are neither fools nor hypocrites: they know exactly what the allocation costs the young
  and have decided it is the lesser cost. *Goals:* keep the covenant reading · keep the
  examination with the elders.
- **Khai Lộ — Open the Road** · `faction_azure_open_road` · REFORMIST · influence 38.
  They have buried disciples who died of waiting, not of danger. Crucially they are
  **institutionalists**: they want the allocation re-argued through petition and re-examination,
  not broken — which is what makes this a quarrel between two defensible readings of one covenant
  rather than a rebellion against it. *Goals:* widen the sect's allocation · re-read the covenant
  as a floor, not a ceiling.
- **Biên Vân — the Frontier Cloud** · `faction_azure_frontier` · RADICAL · influence 31.
  The third position the disagreement implies but never states: both other sides argue about how
  the *allocated* veins should be divided, and the Hoang Vực was never allocated. They do not
  break the covenant; they work a gap in it. The Cloud Terrace calls that evasion in spirit, and
  Khai Lộ calls it a distraction from the fight that actually matters. *Goals:* seek the
  unallocated veins · fund the frontier expeditions.

**The shape of the fight.** Biên Vân declares a rivalry with the Cloud Terrace and **nothing**
toward Khai Lộ: the two share a grievance and reject each other's method, so their relation is
left as an open question for gameplay to settle rather than authored content. That makes Biên Vân
the sect's genuine swing vote, and it means the player's choice of side actually moves something.
At the shipped influences the sect reads **contested** (45 vs 38) with the Cloud Terrace holding
sway — so the first thing the politics panel tells a new player is that this is a live fight, not
a settled hierarchy.

The player starts in this sect (C-003) but belongs to **no faction**: taking a side is a gameplay
act, never an authored identity (D-042).

### Xích Diễm Tông — `sect_crimson_flame` · heterodox · tier 3 · Huyết Mạc Vực
Doctrine (canon; shipped text is a Phase-06 placeholder — C-005): *the covenant rations
cultivation to preserve the institutions that administer it, and a sect that accepts rationing
accepts a ceiling on its disciples' lives.* Their methods genuinely cost the body — that is Cấm
Pháp, a price they argue is worth paying. **Internal disagreement (canon, NOT yet authored as
factions):** those who pay the price from their own bodies, and those who extract it from others.
The orthodox record describes the second group as if it were the whole sect, and inside Xích Diễm
that accusation is a live political wound.

This split is real canon and binding on whoever authors it, but D-042 deliberately did **not**
ship it as faction content: the player cannot reach Xích Diễm yet, and politics for a sect nobody
can visit is content with no consumer. It is authored in the phase that makes the sect reachable.

### Mutual enmity
Shipped as symmetric `ENEMY` in both templates, and validated as a mutual pair (D-038). It is a
doctrinal war about the covenant, not a grudge.

## 9. The rule for adding a world (anti-wallpaper)

A new world may only be authored if it can answer **all** of these. "It is a new area" is not an
answer.

reason to exist · narrative purpose · gameplay purpose · unique visual identity · unique ecology
· unique resources · unique economy · unique cultivation possibility · unique history ·
connection to other worlds · relevance to the wider canon.

The acceptance test: **the player must be able to say "this world taught me something the Main
World did not."** If the honest answer is "it has stronger monsters", it is a map, not a world —
author it as a region of an existing world instead.

## 10. Extensibility

Adding a world · châu · region · sect · faction · historical event · bí cảnh · world gate is
**data + content scenes**, routed through existing systems (`CONTENT_BIBLE.md`). This document
constrains *what is coherent*, never *what the engine supports*. If a desirable addition cannot
be expressed as data, that is a design defect and goes to `DECISIONS.md`.
