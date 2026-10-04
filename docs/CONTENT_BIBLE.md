# CONTENT_BIBLE — Aetheria

> **Owner of:** the authoring template for every content type — what fields a thing must have
> before it can be called finished.
> Rules those fields must satisfy live in the design bibles; this is the checklist an author works
> from. Data *shapes* (actual `@export` names) are `docs/DATA_SCHEMA.md`'s; this document is about
> **design completeness**, not serialization.
>
> The universal rule it serves: **adding content is data + content scenes, never a core edit**
> (`GAME_FLOW.md` §2).

---

## 1. Every content type must declare

Before the per-type templates, the six things *all* content must answer:

**identity** (a stable id that never changes once shipped) · **purpose** (what design job it does)
· **dependencies** (what must exist for it to work) · **gates** (what the player needs to reach
it) · **outputs** (what the player gets) · **consequences** (what changes in the world) ·
**localization** (every user-facing string is a key) · **UI exposure** (where the player sees it)
· **multiplayer consideration** (personal / shared / instance — `MULTIPLAYER_PLAN.md`).

Two conventions that are non-negotiable:
- **Ids are permanent.** Changing a shipped id is a breaking content change requiring a
  `DECISIONS.md` entry (`07-localization.md` applies the same rule to keys).
- **No literal user-facing text.** Ever. vi + en both required (`07-localization.md`).

## 2. Character

identity · age category · origin · profession · cultivation (realm + layer + path) · personality
traits · **goal** · **fear** · **secret** · **public belief** · **private belief** · relationships
(initial edges) · sect · faction · loyalties · conflicts · possible fate · quest links ·
**death conditions** · **escape conditions** · **recruitment conditions** · future callbacks ·
visual profile ref.

*Done when:* an author can say what this character wants, what they are hiding, and under what
conditions they die, flee or join. See `SOCIAL_DESIGN.md` §2 for why those three.

## 3. Origin (`OriginData`)

id · name key · description key · **personal problem** · **hook into Đêm Vỡ Mạch** · starting
advantage · starting disadvantage · starting relationships · starting items/resources ·
early personal quest ref · **long-term callback** · convergence point.

*Constraints:* gender-independent; **run-scoped, referenced by id** — never a subclass of the
character template (C-011). Must not determine weapon, sect, morality, cultivation path or ending.
The five frozen Origins: CL-09.

## 4. Sect

identity (id, name key, emblem) · type (the orthodox *label*, CL-01) · tier · **doctrine key** ·
Dao interpretation · cultivation philosophy · favoured weapons · favoured techniques ·
**rank ladder** (ordered; `authority` strictly increasing — validated, D-037) · territory ·
economy/resources · political goals · **internal factions** · taboos · secrets · social culture ·
attitude toward Tà Đạo · attitudes toward other sects · attitude toward world travel ·
default diplomacy (**must be symmetric and non-conflicting** — validated, D-038).

*Done when:* a decent person could explain why they joined, **and** the sect contains a real
internal disagreement (`SOCIAL_DESIGN.md` §4).

## 5. Faction

id · name key · leader · members · **goals** · influence · resources · stance · attitude toward
player · attitudes toward other factions · methods · allies · enemies · succession concern ·
internal dispute.

*Done when:* its goals can be advanced or frustrated by player action, and it disagrees with at
least one sibling faction about something specific.

## 6. Realm / layer

realm id · name key · layer index + layer meaning (CL-03) · what new capability appears ·
**what the player can DO that they could not** · perception/traversal/lifespan effects · social
authority · eligible sect rank · access unlocked (map/dungeon/world) · economic effect ·
NPC reaction shift · threat class · narrative role.

*Rejected if:* the only answer to "what can I do now?" is a stat increase
(`PROGRESSION_CULTIVATION_DESIGN.md` §1 rule 2).

## 7. Technique (công pháp)

id · name key · description key · cultivation method taught · resource behaviour · combat
behaviour · passives · active interactions · movement effect · **weapon compatibility** ·
**technique compatibility AND incompatibility** · risk/price · social consequence · reputation
consequence · proscribed status (Tà Đạo / Cấm Pháp / neither — CL-01) · knowledge prerequisite ·
realm prerequisite · story relevance.

*Rejected if:* it is a flat `+X%` modifier, or it is compatible with everything
(`COMBAT_DESIGN.md` §5).

## 8. Weapon / Equipment / Item

**Weapon:** family (CL-10) · role · range · mobility · control · attack pattern · resource
interaction · technique interaction · skill identity.
**Equipment:** slot · stat modifiers (through the one damage formula) · set/technique synergy ·
realm requirement · source · upgrade path.
**Item:** type · stack rule · use effect · source · **sink** (`ECONOMY_CRAFTING_DESIGN.md` §1) ·
rarity · region of origin.

*Constraint:* equipment modifies a build; it must not BE the build (`COMBAT_DESIGN.md` §6).

## 9. Skill / Pet

**Skill:** id · active/passive · cost · cooldown · effect · element/status used (closed sets,
`COMBAT_DESIGN.md` §3) · technique gate · weapon gate · telegraph (if enemy-facing).
**Pet:** id · species · stats · skills · ally AI behaviour · acquisition condition · growth ·
what it adds that the player cannot do alone.

## 10. Map

id/scene key · name key · narrative purpose · gameplay purpose · visual identity · combat identity
· resource identity · social identity · threat rating (advisory) · **access requirements**
(layered — never level, C-002) · exits · shortcuts · secrets · NPCs · quests · dungeon · boss ·
**revisit reasons** (≥2) · reserved space for later unlocks.

*Rejected if:* it is large and empty, or its only access gate is numeric
(`MAP_DUNGEON_DESIGN.md` §1/§3).

## 11. Dungeon / Boss

**Dungeon:** id · narrative justification · visual identity · **one gameplay gimmick** · encounter
variety · environmental mechanic · checkpoint/shortcut · elite/mini-boss · final boss · reward
identity · replay reason.
**Boss:** id · story identity · chapter relation · combat identity · telegraph language (reusing
the global vocabulary) · phases · escalation · reward identity · **post-boss world consequence**.

*Rejected if:* the dungeon is "a map with stronger enemies", or the boss tests a mechanic the
chapter never taught.

## 12. Quest / Dialogue / Story chapter

**Quest:** id · category (`MAP_DUNGEON_DESIGN.md` §7) · source · motivation · objective · obstacle
· gameplay activity · **social dimension** · choice · reward · consequence · future callback ·
**≥2 of {combat, exploration, investigation, social choice, resource management}**.
**Dialogue:** id · speaker · nodes (all keys) · conditions read from STATE · choices → deltas via
the owning services (never a private flag) · knowledge granted.
**Story chapter:** id · act · entry condition · beats · reveal-ladder layer (`NARRATIVE_MASTER_PLAN.md`
§9) · branches (state→condition→branch→consequence) · convergence point · world-state changes.

## 13. World / World event / Resource / Recipe

**World:** id · category (Main/Tiểu/Tàn/Hủ) · the eleven justifications (`WORLD_BIBLE.md` §9) ·
gate requirements · cultivation tradition offered · what it teaches that the Main World does not.
**World event:** id · cause · actors · trigger condition · duration · effects on
character/sect/faction/economy/map · player participation · aftermath.
**Resource:** id · name key · tier · rarity · **region of origin** · sources · **sinks** ·
processing chain position.
**Recipe:** id · inputs · output · profession + level · knowledge prerequisite · facility/tool ·
failure behaviour · loss on conversion.

## 14. Review checklist (apply before calling any content done)

1. Every user-facing string is a key, with vi **and** en values.
2. Ids are stable, prefixed by type, `snake_case`.
3. All declared references resolve (the pattern D-037/D-038 enforced for sects: a dangling
   reference invalidates the catalog rather than being silently skipped).
4. No numeric-only access gate (C-002).
5. At least one consequence enters the social consequence loop (`SOCIAL_DESIGN.md` §6).
6. Every resource introduced has a sink (`ECONOMY_CRAFTING_DESIGN.md` §6).
7. No canon contradiction — check `CANON_LEDGER.md`.
8. No core system edit was required. If one was, it is a design defect → `DECISIONS.md`.

## 15. Extensibility test (Audit U — the brief's §82 simulation)

Hypothetical addition of **10 quests · 5 NPCs · 3 maps · 2 dungeons · 2 bosses · 3 techniques ·
2 weapons · 1 sect · 2 factions · 1 Minor World.** Can each be added as data + content scenes?

| Addition | Mechanism | Core edit? |
|---|---|---|
| 10 quests | `QuestData` × 10, objectives driven by existing EventBus events | No |
| 5 NPCs | `CharacterTemplateData` × 5 + visual profile refs + placement in a map scene | No |
| 3 maps | `MapData` × 3 + 3 content scenes + catalog entries (proven in Phase 03) | No |
| 2 dungeons | `DungeonData` × 2 + scenes, on the existing map+combat+loot systems | No |
| 2 bosses | `BossData` × 2 + scenes, using the global telegraph vocabulary | No |
| 3 techniques | `TechniqueData` × 3 — compatibility is authored data | No |
| 2 weapons | new weapons **within** the 5 frozen families | No |
| 1 sect | `SectTemplateData` + catalog entry (**proven** — that is exactly how Crimson Flame exists) | No |
| 2 factions | faction data on the sect template (Phase 07 model) | No |
| 1 Minor World | world data + maps + a world gate + a cultivation tradition as technique data | No |

**Two honest caveats:**
- A **new weapon FAMILY** (a sixth) IS a design change — it needs a role, a niche and a
  `DECISIONS.md` entry (CL-10). Adding weapons inside a family is content.
- A new **element or status** is likewise a closed-set change (`COMBAT_DESIGN.md` §3), because UI
  colour/icon language and content balance both depend on the set being closed.

Everything else passes. The result: **the design does not require core edits for content growth**,
which was the condition for freezing it.
