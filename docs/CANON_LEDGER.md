# CANON_LEDGER — Aetheria

> The single list of **frozen facts**. If a name, number, hierarchy or world law is here, it is
> canon and changing it requires a `docs/DECISIONS.md` entry (see §Change control at the end).
> Design *reasoning* lives in the bibles; this file is the short, citable answer to "is X canon,
> and what exactly is it called?"
>
> Frozen by **D-039** (Master Game Design Freeze v2.1). Every entry is ORIGINAL to Aetheria.
>
> **Why a ledger separate from the bibles:** a bible explains and therefore gets rewritten. A
> ledger is a lookup table that must stay stable, so content authors and future phases cite
> short ids (`CL-02`) instead of paraphrasing a paragraph that may have moved.

---

## CL-01 — Terminology: the three categories of "forbidden"

Aetheria's central ambiguity depends on never collapsing these. Prose must pick one
deliberately.

| Term | Category | Means | Who decides |
|---|---|---|---|
| **Ma Đạo** | a named tradition | a specific cultivation lineage with its own texts and sects | self-identified |
| **Tà Đạo** | a political category | anything the orthodox institutions have PROSCRIBED | the Thiên Khế + great sects |
| **Cấm Pháp** | a factual category | methods that genuinely, physically damage the practitioner or the world | observable reality |

A method may be **Tà Đạo but not Cấm Pháp** (suppressed knowledge that is merely inconvenient to
institutions) or **Cấm Pháp but not Ma Đạo** (an orthodox technique whose true cost was hidden).
`SectType.DEMONIC` is the ORTHODOX LABEL, not a moral verdict (see `CONTRADICTION_REGISTER.md`
C-004).

## CL-02 — The cultivation hierarchy (FROZEN)

Five numbered macro realms + two structural-only tiers. Nine layers inside each numbered realm.

| # | Realm | Layers | One-line meaning |
|---|---|---|---|
| 0 | **PHÀM** (Mortal) | — | no cultivation; the baseline the world is built for |
| 1 | **HẬU THIÊN** (Acquired Heaven) | 1–9 | the body is opened and refined by effort |
| 2 | **TIÊN THIÊN** (Innate Heaven) | 1–9 | qi becomes self-sustaining; a true cultivator |
| 3 | **NGỰ THIÊN** (Commanding Heaven) | 1–9 | authority over an external domain; a regional power |
| 4 | **TRỌNG THIÊN** (Layered Heaven) | 1–9 | interaction with world law itself; a world-scale actor |
| 5 | **THÁI THIÊN** (Ultimate Heaven) | structural | endgame tier — purpose and meaning frozen, abilities NOT designed |
| 6 | **VÔ THIÊN** (Void Heaven) | structural | the unknown beyond; exists to keep the ladder open forever |

- Realm ids are `realm_pham`, `realm_hau_thien`, `realm_tien_thien`, `realm_ngu_thien`,
  `realm_trong_thien`, `realm_thai_thien`, `realm_vo_thien`.
- Localization keys follow `REALM_<NAME>_NAME` / `_DESC` (`07-localization.md`).
- The conventional Luyện Khí / Trúc Cơ / Kim Đan ladder is **NOT canon** and must not appear in
  content (C-001).
- Full semantics, the nine-layer meanings and the master realm table:
  `docs/PROGRESSION_CULTIVATION_DESIGN.md`.

## CL-03 — The nine layers (meaning, not numbers)

Inside any numbered realm, layers mean the same KIND of thing, so a player who learns the shape
once can read it in every realm:

1 Foundation · 2 Expansion · 3 Mastery · 4 Transformation · 5 Consolidation ·
6 Manifestation · 7 **Đạo Cơ** (personal Dao seed) · 8 World Touch · 9 Threshold.

Layers 7 and 9 are the two that must always change what the player can DO
(`PROGRESSION_CULTIVATION_DESIGN.md` §3).

## CL-04 — Cosmology (FROZEN)

```
VÔ GIỚI                      the unknown beyond (endgame, structural only)
  └── HẢI GIỚI               the World Sea — the medium/boundary between worlds
        ├── HẠO NGUYÊN GIỚI  the MAIN WORLD (5 đại vực, 12 châu)
        ├── TIỂU GIỚI        Minor Worlds (reachable, specialised, lesser scale)
        ├── TÀN GIỚI         Lost / Sealed Worlds (civilisation gone, knowledge intact)
        └── HỦ GIỚI          Corrupted / Fallen Worlds (broken by cultivation catastrophe)
```

## CL-05 — The Main World: HẠO NGUYÊN GIỚI — five đại vực

| Đại vực | Character | Shipped content anchored here |
|---|---|---|
| **Thiên Nguyên Vực** | orthodox heartland; seat of the Thiên Khế | Thanh Vân Tông (`sect_azure_cloud`) |
| **Huyết Mạc Vực** | heterodox traditions; the orthodox call it tà đạo | Xích Diễm Tông (`sect_crimson_flame`) |
| **Vân Hải Vực** | neutral; trade, information, mercenary cultivation | — |
| **Cổ Tích Vực** | ruins and bí cảnh; the past is physically present | — |
| **Hoang Vực** | the wild frontier; thin administration, unstable veins | **the player's starting châu** |

Twelve **châu** (provinces) are distributed across the five vực; only the starting châu is
specified in detail at freeze time (`WORLD_BIBLE.md` §4). Adding a châu is content.

## CL-06 — THIÊN KHẾ (the Heaven Covenant)

An ancient covenant/order that regulates spiritual veins, dangerous methods, resource access and
inter-sect balance. **Orthodox history:** it ended the age of catastrophe and protects
civilisation. **Hidden evidence:** it also *rations* cultivation — and rationing requires
institutions to administer it, which is where its real power lives. Both readings are supported
by in-world evidence; neither is revealed as "the twist". Full treatment: `WORLD_BIBLE.md` §6.

## CL-07 — The historical TÀ ĐẾ

One historical figure, three incompatible records — this is deliberate and permanent:

| Tradition | Name used | Claim |
|---|---|---|
| Orthodox (Thiên Khế archives) | **Tà Đế** — personal name struck out | a tyrant who broke the veins and was put down |
| Heterodox (Huyết Mạc lineages) | **Khai Mạch Nhân** (the Vein-Opener) | a liberator who tried to end the rationing |
| Neutral scholarship (Vân Hải) | **Hạ Vô Tướng** — an attested person | a Ngự Thiên cultivator whose records were edited afterwards |

The player is **NOT** their reincarnation, descendant, or heir, and inherits none of their power
(`NARRATIVE_MASTER_PLAN.md` §3). The player may eventually earn, accept, reject or redefine the
TITLE. There is no `evil_score`, morality bar or alignment anywhere in Aetheria.

## CL-08 — ĐÊM VỠ MẠCH (the Night the Vein Broke)

The inciting event. A major frontier spiritual vein destabilises in the player's starting châu.
It is **not** a random disaster: it has actors, motive and beneficiaries, and someone suppresses
the evidence. The player is present by circumstance, is not chosen, and leaves with
**information**, not power. Full causal chain: `NARRATIVE_MASTER_PLAN.md` §4.

## CL-09 — The five Origins (gender-independent)

`origin_hо_tieu` **Hộ Tiêu Thất Bại** (failed caravan escort) · `origin_de_tu_bi_loai`
**Đệ Tử Bị Loại** (rejected sect candidate) · `origin_lang_y` **Lang Y Du Phương** (wandering
healer) · `origin_nghe_nhan` **Nghệ Nhân Thất Sủng** (disgraced artisan) ·
`origin_thu_thu` **Thủ Thư Cấm Lục** (keeper of forbidden records).

Origin is **run-scoped data referenced by id**, never a class and never a fork of the character
model. It modifies story context, starting relationships, small resources and personal quests.
It does **not** determine weapon, sect, morality, cultivation path or ending
(`NARRATIVE_MASTER_PLAN.md` §6).

## CL-10 — Weapon families (FROZEN)

`weapon_kiem` **Kiếm** (sword) · `weapon_dao` **Đao** (sabre) · `weapon_thuong` **Thương**
(spear) · `weapon_cung` **Cung** (bow) · `weapon_phap_truong` **Pháp Trượng** (staff/implement).
Roles and identities: `COMBAT_DESIGN.md` §4. Adding a family is a core-design change requiring a
`DECISIONS.md` entry; adding a *weapon* within a family is content.

## CL-11 — Shipped ids ↔ canonical places

Ids are stable and never renamed; display text may be revised by a content pass (C-008).

| Shipped id | Canonical place | Where |
|---|---|---|
| `map_hub` | **Thôn Lạc Hà** — the frontier village | starting châu, Hoang Vực |
| `map_field` | **Rừng Vỡ Mạch** — the woods over the unstable vein | starting châu, Hoang Vực |
| `region_azure_peak` | **Thanh Vân Phong** | Thiên Nguyên Vực |
| `region_cloud_vale` | **Vân Cốc** | Thiên Nguyên Vực |
| `region_scarlet_wastes` | **Xích Hoang** | Huyết Mạc Vực |
| `sect_azure_cloud` | **Thanh Vân Tông** (orthodox, tier 3) | Thiên Nguyên Vực |
| `sect_crimson_flame` | **Xích Diễm Tông** (heterodox, tier 3) | Huyết Mạc Vực |

## CL-12 — Relationship dimensions (UNCHANGED, re-frozen)

`affinity` · `trust` · `respect` · `fear` · `rivalry` · `debt`. No single relationship score, and
no morality bar may ever replace them (`RELATIONSHIP_SYSTEM.md` §2 — already implemented).

## CL-13 — The two progression axes (UNCHANGED, re-frozen)

**LEVEL/XP** = fine-grained, combat-derived, smooth power. **CẢNH GIỚI** = chunky, gated,
unlocks *capability and access*. They are never collapsed into one number, and **level is never
an access gate** (C-002, `02-game-design.md`).

## CL-14 — Knowledge (TRI THỨC) is a third progression concept

Not XP and not a realm: a serializable record of what the player has LEARNED, which gates
hidden techniques, world gates, dialogue options, alternate quest solutions, crafting methods and
forbidden paths (`PROGRESSION_CULTIVATION_DESIGN.md` §7).

**Ownership + phase (frozen, D-040 / C-012):** the **Knowledge Core** lands in **Phase 12** with
its own authoritative domain owner — `KnowledgeStore` + `KnowledgeService`, no autoload. Only that
service may mutate the authoritative collection. Cultivation, Technique and Crafting **read**;
Dialogue, Quest and Story **grant through the service**; NPC/content **expose opportunities**.
**Story does not own knowledge, Quest does not own knowledge, and knowledge is never a private
story flag.** Full model: `PROGRESSION_CULTIVATION_DESIGN.md` §7a.

## CL-16 — Deterministic RNG is seeded, stream-scoped, and introduced in Phase 08

One run/world seed fanning out into per-subsystem streams (world sim · combat · enemy AI · loot ·
future instances). Introduced with **World Simulation (P-08)**, the first genuine consumer;
**Combat (P-09) reuses it** rather than introducing its own. Frozen properties: deterministic ·
seeded · injectable · subsystem/stream-scoped · serializable where required ·
presentation-independent · **no global `rand*()` in domain code**. Not an autoload. One
subsystem's extra random call must never shift another subsystem's future sequence. Shape:
`SYSTEM_DEPENDENCY_MATRIX.md` §4c; save requirement: `SAVE_FORMAT.md` §3b.

## CL-17 — Thanh Vân Tông's three factions, and how faction standing is represented

**The landscape (shipped, D-042).** Thanh Vân Tông (CL-11) holds three internal factions, each a
defensible answer to a different question — none is the villain (C-005):
**Vân Đài** (`faction_azure_terrace`, LOYALIST) the ceiling is the price of not repeating the
catastrophe · **Khai Lộ** (`faction_azure_open_road`, REFORMIST) institutionalists who have buried
disciples that died of waiting, and want the allocation re-argued, not broken · **Biên Vân**
(`faction_azure_frontier`, RADICAL) who work a gap in the covenant rather than break it, since the
Hoang Vực was never allocated. Biên Vân is rival to Vân Đài and declares **nothing** toward
Khai Lộ: they share a grievance and reject each other's method, which makes Biên Vân the sect's
swing vote. The sect is **contested**, not settled.

**The player belongs to no faction.** The start sect is a scaffold (C-003); a faction allegiance
is a gameplay act, never authored. Phase 07 enrols nobody.

**Xích Diễm Tông's split** (those who pay the price from their own bodies vs those who extract it
from others) is equally canon and binding, but deliberately **not yet authored as factions** —
the sect is unreachable, and politics for a place the player cannot visit has no consumer.

**Representation (frozen).** A faction is NOT a field on `SectState`: it names its
`parent_sect_id` and lives in its own store. Faction↔Faction and Faction↔Player **standings are
relationship EDGES** (`RelationshipEndpoint.Kind.FACTION`), never inline scalars — `affinity` and
`rivalry` are two of the six frozen dimensions (CL-12), so a faction-side copy would be a second
source of truth for one question. `FactionState` carries only the DECLARED relation. Membership
defers to the sect roster (D-015), one seat per sect. Politics rules are deterministic with
explicit tie-breaks and use **no RNG** (that seam is CL-16 / P-08).

## CL-15 — Unresolved mysteries (deliberately open)

These are canon *questions*, reserved so no phase accidentally answers them early:
who authored the Thiên Khế and under what pressure · what Hạ Vô Tướng actually did at the veins ·
why the Hoang Vực veins are failing NOW · what the Tàn Giới civilisations were fleeing ·
whether a sixth đại vực was removed from the records. Reveal order:
`NARRATIVE_MASTER_PLAN.md` §9.

---

## Change control

Changing anything above requires a `docs/DECISIONS.md` entry recording:
**OLD · NEW · WHY · IMPACT · AFFECTED CONTENT · AFFECTED SYSTEMS · MIGRATION/COMPATIBILITY**.

Critical canon (always requires an entry): protagonist identity · the Origin model · world law ·
Thiên Khế · the realm hierarchy (CL-02/03) · the world hierarchy (CL-04/05) · any major sect or
faction · the historical Tà Đế · core progression (CL-13/14) · **state ownership and phase of a
core substrate (CL-14, CL-16)** · economy architecture · multiplayer narrative semantics.

**Tunable without an entry** (balance, not canon): XP curves, damage numbers, HP, drop rates,
currency amounts, cultivation speed, cooldowns, spawn rates, grind duration, threat ratings.
