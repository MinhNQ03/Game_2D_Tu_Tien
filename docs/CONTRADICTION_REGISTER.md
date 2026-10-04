# CONTRADICTION_REGISTER — Aetheria

> Output of the **Master Game Design Freeze v2.1** audit (D-039). Every entry is a REAL
> disagreement found between two things that already existed in this repository (a steering
> file, a design doc, shipped `.tres` content, shipped `locale/aetheria.csv` prose, or the
> design overview poster supplied by the project owner). Nothing here is hypothetical.
>
> **Rule:** a contradiction is not closed by deleting one side. It is closed by naming the
> AUTHORITATIVE OWNER and recording what the other side must become. Where closing it would
> change runtime behaviour or shipped content, the resolution is recorded as a **content debt**
> bound to a named phase — this freeze changes no code and no content.
>
> Status vocabulary: **RESOLVED** (canon decided, docs aligned in this freeze) ·
> **CONTENT DEBT** (canon decided, shipped data/prose must follow in a named phase) ·
> **WATCH** (not yet a defect, but it will become one if a later phase is careless).

---

## C-001 — The realm ladder: conventional Luyện Khí → Trúc Cơ vs. an original hierarchy
- **Side A (steering, binding):** `.kiro/steering/02-game-design.md` glossary —
  "*Cảnh giới | Realm | A major cultivation tier (e.g. **Luyện Khí → Trúc Cơ → …**). Gates
  power & content.*"
- **Side B (freeze requirement):** the design brief forbids defaulting to that ladder and
  requires an original macro hierarchy (Phàm / Hậu Thiên → Tiên Thiên → … → Trọng Thiên → beyond).
- **Affected:** Cultivation (Phase 12), Map gating, Dungeon gating, World travel, Sect rank
  meaning, NPC threat language, every future realm/technique/map `.tres`, all `REALM_*`
  localization keys.
- **Why it matters:** this is the single most expensive thing to change late. Realm ids leak
  into content filenames, save data, map access rules, and thousands of future strings. It had
  to be decided before any of them exist — and today **none exist**, which is why this is the
  right moment.
- **Resolution — RESOLVED.** The conventional ladder was only ever an *illustrative example* in
  a glossary row, never authored anywhere: no realm id, no `.tres`, no locale key, and no code
  references it (Phase 12 is NOT STARTED). The freeze adopts the original five-macro-realm
  hierarchy **PHÀM → HẬU THIÊN → TIÊN THIÊN → NGỰ THIÊN → TRỌNG THIÊN**, plus the two
  structural-only tiers **THÁI THIÊN** and **VÔ THIÊN**. Steering 02's glossary row is corrected
  to point at the owner instead of carrying an example ladder.
- **Authoritative owner:** `docs/PROGRESSION_CULTIVATION_DESIGN.md` §2 (hierarchy) and
  `docs/CANON_LEDGER.md` CL-02 (the frozen names).

## C-002 — Map access by LEVEL vs. access by REALM
- **Side A (design poster, supplied):** the map strip labels maps by level band —
  "Tân Thủ Thôn (Lv 1–10)", "Thanh Vân Sơn (Lv 10–30)", "Huyết Ma Địa (Lv 30–50)",
  "Cấm Vực (Lv 50+)".
- **Side B (steering, binding):** `.kiro/steering/02-game-design.md` progression contract —
  "*content gating keys off **cảnh giới**; fine power tuning keys off **level***". The freeze
  brief independently forbids `Level 20 = new planet` gating.
- **Affected:** Map (Phase 03, implemented), Dungeon (21), World travel, Quest availability,
  Progression (11), Cultivation (12).
- **Why it matters:** level-gating is the default a team drifts into because it is the easiest
  number to compare. Once two maps ship with a `min_level` field, the whole access model is
  level-shaped and realms become decorative.
- **Resolution — RESOLVED.** Level is **never** an access gate. The poster's level bands are
  reinterpreted as **THREAT RATINGS** — advisory "recommended power" shown to the player — not
  permissions. Access is a layered gate of realm + quest/story + knowledge + sect/faction
  standing + world state + key item/technique (`docs/MAP_DUNGEON_DESIGN.md` §3). `MapData` must
  never gain a `min_level` field; it gains an advisory `threat_rating` and a structured
  `access_requirements` list when Phase 12+ needs them.
- **Authoritative owner:** `docs/MAP_DUNGEON_DESIGN.md` §3 (gating) · threat vocabulary in
  `docs/PROGRESSION_CULTIVATION_DESIGN.md` §6.

## C-003 — "The player has no sect standing" vs. the shipped build enrolling them in a sect
- **Side A (narrative, binding):** `docs/NARRATIVE_DIRECTION.md` §1 — the player begins
  "*with **no sect standing**, no reputation, and no destiny handed to them*".
- **Side B (shipped runtime):** `data/sects/sect_catalog.tres` sets
  `player_start_sect_id = sect_azure_cloud` / `player_start_rank_id = rank_outer`, and
  `docs/GAME_FLOW.md` status reports "*New Game enrols the player into the authored start sect
  (Azure Cloud, at Outer Disciple)*". `SectRuntime.start_session()` now FAILS CLOSED if that
  enrolment does not succeed (D-037).
- **Affected:** Narrative premise, Prologue, Sect (06, implemented), Quest (19), Story (20),
  the Act-II "join a sect" beat, the Tà Đế identity arc (a player who was handed a sect cannot
  *earn* standing).
- **Why it matters:** this is the premise of the whole game. If the player is an Azure Cloud
  disciple in minute one, "a nobody earns a place" is already false, and the entire Act-I/II
  structure (frontier → first contacts → chosen affiliation) has nothing left to dramatise.
- **Resolution — CONTENT DEBT (Phase 17/19 — NPC/Quest, when sect joining becomes playable).**
  Canon: **the player starts with NO sect.** Narrative side A wins. The enrolment is a
  Phase-06 *scaffold* whose only purpose was to make the sect substrate observable (a HUD chip
  and a panel need a member to render). It is honest scaffolding, not canon. The data model
  already supports the canonical state: `player_start_sect_id` accepts `&""`, and
  `SectRuntime` handles "no start sect" as a first-class path. The debt is: flip that field to
  `&""` and move joining into content **in the phase that can actually dramatise joining** —
  flipping it today would strip the only sect UI the game currently has, trading a true
  premise for a blank panel and losing live coverage of the sect path.
- **Authoritative owner:** premise → `docs/NARRATIVE_MASTER_PLAN.md` §2 ·
  mechanism → `docs/SOCIAL_DESIGN.md` §4.

## C-004 — "Tà Đạo" (design language) vs. `SectType.DEMONIC` / "Ma Đạo" (shipped enum + prose)
- **Side A (freeze requirement):** "Tà Đạo must NOT automatically equal evil"; some forbidden
  methods are genuinely dangerous, others are merely *knowledge suppressed by institutions*.
  The poster labels the second great domain "Huyết Mạc (**tà đạo**)".
- **Side B (shipped):** `SectTemplateData.SectType` is `{ ORTHODOX, DEMONIC, NEUTRAL, HIDDEN }`
  and `locale/aetheria.csv` renders `SECT_TYPE_DEMONIC` as "Demonic / **Ma Đạo**".
- **Affected:** Sect (06), Faction (07), all sect `.tres`, the Thiên Khế mystery, player
  identity, the meaning of the Tà Đế title.
- **Why it matters:** "Demonic/Ma Đạo" is a *verdict*. Baking a verdict into the type enum means
  the game has already decided who is evil, which destroys the central ambiguity ("the world may
  call you Tà Đế for completely different reasons").
- **Resolution — RESOLVED (vocabulary) + CONTENT DEBT (locale prose, Phase 24).** The enum stays
  as-is structurally — it is a closed archetype set, which is correct — but its MEANING is frozen
  as **an orthodox-institutional classification, not a moral fact**: `DEMONIC` names the
  tradition that the Thiên Khế and the orthodox sects *label* heterodox. Canon distinguishes
  three separate things that English/Vietnamese prose keeps collapsing:
  **Ma Đạo** (a named tradition) · **Tà Đạo** (anything the orthodox institutions have
  proscribed — a political category) · **Cấm Pháp** (methods that are genuinely, physically
  self-destructive — a factual category). A method can be Tà Đạo without being Cấm Pháp, and
  Cấm Pháp without being Ma Đạo. Locale debt: `SECT_TYPE_DEMONIC`'s display text becomes the
  in-world *label* ("Heterodox / Ma Đạo") during the Phase-24 localization pass.
- **Authoritative owner:** `docs/WORLD_BIBLE.md` §6 (the three categories) ·
  `docs/CANON_LEDGER.md` CL-07.

## C-005 — Crimson Flame's shipped doctrine is a "bad sect" voice
- **Side A (freeze requirement):** "*Avoid good sect vs bad sect. Every major sect should have
  defensible internal logic*" and "*A sect must contain internal disagreement*".
- **Side B (shipped prose):** `SECT_CRIMSON_FLAME_DOCTRINE` = "*Burn away all restraint; power
  is the only law. / Thiêu rụi mọi ràng buộc; sức mạnh là luật duy nhất.*"
- **Affected:** Sect content, Faction (07), the Huyết Mạc Vực domain, any future quest involving
  Xích Diễm Tông, C-004's ambiguity.
- **Why it matters:** that line is a villain announcing he is the villain. No one has ever
  joined an organisation whose stated doctrine is "we have no principles". It also makes the
  Tà Đạo ambiguity unplayable: if the heterodox sect's own charter says it is lawless, the
  orthodox verdict is simply correct.
- **Resolution — CONTENT DEBT (Phase 24 localization pass / first Xích Diễm content phase).**
  Canon gives Xích Diễm Tông a defensible doctrine: *the Thiên Khế rations cultivation to
  preserve the institutions that administer it; a sect that accepts rationing accepts a ceiling
  on its disciples' lives.* Their cultivation genuinely costs the body — that is Cấm Pháp, a
  real price they argue is worth paying, not a lack of ethics. Their internal split (Phase 07)
  is between those who pay that price themselves and those who extract it from others — the
  second group is what orthodox records describe as the whole sect. The doctrine KEY does not
  change (keys never change once shipped — `07-localization.md`); its vi/en TEXT is revised.
- **Authoritative owner:** `docs/WORLD_BIBLE.md` §8 (sect roster).

## C-006 — `GAME_FLOW.md` carries two stacked, partially stale status blocks
- **Side A:** the top status block is current (Phase 06 hardening, D-037).
- **Side B:** immediately beneath it, a second block says "*Status (as of Phase 03): early
  gameplay implemented … The branching-story / dialogue / quest / NPC flow below is still the
  design target*", and §3.3 separately re-states the Phase-03 implementation status.
- **Affected:** every contributor who reads the project's self-declared "central document"; the
  AI review protocol mandates reading it before any change (`08-ai-review-protocol.md`).
- **Why it matters:** two status headers invite the reader to trust whichever one they hit
  first, and the file is explicitly the one document everybody must read. This is the same
  defect class as L-014 (a contract that contradicts the code) applied to the flow doc.
- **Resolution — RESOLVED.** `GAME_FLOW.md` keeps exactly ONE status block (current), and the
  per-system "implementation status" notes stay where they belong — inside each §3.x system
  contract, which is the only place they cannot be mistaken for the global state.
- **Authoritative owner:** `docs/GAME_FLOW.md` (flow + per-system contracts) ·
  phase state → `docs/ROADMAP.md`.

## C-007 — The prologue is named in the flow but never defined anywhere
- **Side A:** `docs/GAME_FLOW.md` §1 and §3.3 both make `PROLOGUE` a first-class box in the
  player path, and §3.3 says it is "*the design target*" to be filled by Phase 04+.
- **Side B:** no document defines what the prologue *is*. `locale/aetheria.csv` contains only
  `UI_PROLOGUE_PLACEHOLDER` = "Prologue (shell) / Khởi đầu (bản khung)".
- **Affected:** Story (20), Quest (19), Dialogue (18), NPC (17), the Vertical Slice (27) —
  whose stated exit criterion is "prologue → village → quest → combat → progress → save".
- **Why it matters:** Phase 27's acceptance test references content no document specifies. A
  prologue invented at Phase 27 would be built on whatever systems happened to exist, which is
  exactly the "collection of disconnected systems" this freeze exists to prevent.
- **Resolution — RESOLVED.** The prologue is now fully specified beat-by-beat, including its
  causal chain, its exit conditions, and the five things the player must leave it holding.
- **Authoritative owner:** `docs/NARRATIVE_MASTER_PLAN.md` §4 (ĐÊM VỠ MẠCH) and §5 (the
  30–60 minute prologue).

## C-008 — Shipped map/region prose vs. the poster's world naming
- **Side A (shipped):** `UI_MAP_HUB_NAME` = "Village (hub) / Thôn làng (trung tâm)",
  `UI_MAP_FIELD_NAME` = "Forest Field / Khu rừng"; map ids `map_hub` / `map_field`; sect
  territory ids `region_azure_peak`, `region_cloud_vale`, `region_scarlet_wastes`.
- **Side B (poster):** named places — "Tân Thủ Thôn", "Thanh Vân Sơn", "Huyết Ma Địa",
  "Cấm Vực" — and a geography of 5 đại vực / 12 châu that no document describes.
- **Affected:** World Bible, Map (03), every future map `.tres`, `UI_MAP_*` keys, Quest text.
- **Why it matters:** the shipped names are generic engineering labels ("Village (hub)") that
  were never meant to be canon, while the poster's names have no geography behind them. Left
  alone, the first content phase invents a third naming scheme.
- **Resolution — RESOLVED (geography) + CONTENT DEBT (prose, first content phase).** The World
  Bible freezes the full geography and gives every shipped id a canonical place. The map **ids**
  are stable and do NOT change (`map_hub`/`map_field` are scene keys, and renaming ids is a
  breaking content change). Their *display* keys get canonical names when the frontier gets its
  content pass. Mapping is recorded in `docs/CANON_LEDGER.md` CL-11.
- **Authoritative owner:** `docs/WORLD_BIBLE.md` §3–§4.

## C-009 — The poster's phase grouping vs. `ROADMAP.md`'s actual phase numbers
- **Side A (poster):** "Phase 07–10: tông môn, phe phái, chính trị, quan hệ · 11–14: tu luyện,
  công pháp, kỹ năng, chiến đấu · 15–18: chế tạo, item, kinh tế · 19–22: nhiệm vụ, cốt truyện,
  dungeon, boss · 23–27: lưu trữ, UI/UX · 33–35: multiplayer".
- **Side B (`ROADMAP.md`, binding):** 07 Faction · 08 World Simulation · 09 Combat · 10 Enemy AI
  · 11 Progression · 12 Cultivation · 13 Item · 14 Equipment · 15 Skill · 16 Pet · 17 NPC ·
  18 Dialogue · 19 Quest · 20 Story · 21 Dungeon · 22 Boss · 23 Save · 24 Localization ·
  25 UI consolidation · 26 Audio/VFX · 27 Vertical Slice · 28 Audit · 29 Performance ·
  30 RC · 31 Offline Release · 32 MP readiness · 33 MP foundation · 34 MP gameplay.
- **Affected:** all phase references in every document; the UI-evolution-by-phase plan.
- **Why it matters:** the freeze brief itself lists UI work "Phase 09: Combat HUD, Phase 12:
  Cultivation UI, …" which happens to match `ROADMAP.md`, not the poster. Two numbering schemes
  would make every future "see Phase N" citation ambiguous.
- **Resolution — RESOLVED.** `ROADMAP.md` phase numbers are the ONLY phase vocabulary. The
  poster is a communication artifact (an at-a-glance overview for a human reader), explicitly
  **not** a planning source; its bands are a readable approximation of the same order. The
  audit found no necessary correction to the engineering sequence, so it is preserved unchanged.
- **Authoritative owner:** `docs/ROADMAP.md`.

## C-010 — World simulation requires seeded determinism, but there is no RNG owner yet
- **Side A:** `docs/WORLD_SIMULATION.md` and `docs/MULTIPLAYER_PLAN.md` §3/§7 both make
  **seeded, deterministic** RNG a hard requirement ("*World simulation using wall-clock time or
  unseeded RNG — breaks determinism*", listed as a risk to flag immediately).
- **Side B:** `.kiro/steering/03-architecture.md` lists `RNG` as *anticipated, added only when
  first needed*, and `GAME_FLOW.md` §3.1 confirms `Config`/`RNG`/`SaveService` are still planned.
  Five autoloads exist; none is an RNG.
- **Affected:** World Simulation (08), Combat (09), Enemy AI (10), Economy drops, Dungeon
  generation, Multiplayer readiness (32).
- **Why it matters:** determinism is not something that can be retrofitted after three systems
  have each called `randi()` directly. The first system that needs randomness establishes the
  pattern for all of them.
- **Resolution — RESOLVED (phase corrected in D-040; was WATCH).** The original resolution said
  "the first phase that needs randomness must introduce the seam" and then guessed that Combat
  (P-09) would be the first caller. That guess was **wrong and self-contradictory**: World
  Simulation is **P-08** and its determinism requirement is explicit, so the first consumer is
  P-08, one phase earlier. Frozen now:
  - **The deterministic RNG seam is introduced in PHASE 08, with World Simulation.**
  - **Phase 09 Combat consumes the seam P-08 established** — it does not introduce its own.
  - The seam is **stream-scoped**: one run/world seed fanning out into per-subsystem streams
    (world sim, combat, enemy AI, loot, future instances), so one subsystem's extra random call
    can never shift another subsystem's future sequence. Shape frozen in
    `docs/SYSTEM_DEPENDENCY_MATRIX.md` §4c.
  - Properties: deterministic · seeded · injectable · subsystem/stream-scoped · serializable
    where required · presentation-independent · **no global `rand*()` in domain code, ever**.
  - **No autoload** (D-017 budget stays at 5) — it is injected, like `RelationshipService`'s
    config. Class names, stream-id vocabulary, algorithm and serialized shape belong to P-08.
  - Save implication recorded in `docs/SAVE_FORMAT.md`: the world seed plus whatever stream state
    is needed to resume world evolution **exactly** must be restorable (P-23).
- **Authoritative owner:** `docs/SYSTEM_DEPENDENCY_MATRIX.md` §4c (the seam) ·
  `.kiro/steering/03-architecture.md` (autoload budget) · `docs/SAVE_FORMAT.md` (resume
  requirement).

## C-011 — `CHARACTER_PLAYER_ORIGIN` ships one fixed origin, but the design needs 3–5
- **Side A (shipped):** `locale/aetheria.csv` — `CHARACTER_PLAYER_ORIGIN` = "*Born in a remote
  mountain village. / Sinh ra ở một thôn làng vùng núi xa xôi.*"; `CHARACTER_PLAYER_NAME` =
  "Wanderer / Lữ khách"; `CHARACTER_PLAYER_TITLE` = "Mortal Seeker / Phàm nhân cầu đạo".
- **Side B (freeze requirement):** 3–5 selectable, gender-independent Origins, each with its own
  problem, hook, advantage, disadvantage and future callback.
- **Affected:** Character (04, implemented), Prologue, Story (20), character creation UI.
- **Why it matters:** `CharacterTemplateData` currently expresses origin as one localization key
  on one template. Five origins are not five templates — origin is a *property of a run*, chosen
  at character creation, and it must not fork the character data model.
- **Resolution — RESOLVED (model) + CONTENT DEBT (data, Phase 20/27).** Origin is frozen as
  **run-scoped authored data referenced by id** (`origin_id` on the run, resolving to an
  `OriginData` content resource), NOT a field baked into one player template and NOT a subclass.
  The shipped strings stay valid as the **default/unset** origin used by the current build and
  by tests. `CHARACTER_PLAYER_TITLE` = "Phàm nhân cầu đạo" is confirmed *consistent* with the new
  hierarchy: **PHÀM** is now a canonical realm name, so the shipped title reads correctly as
  "a mortal seeking the path".
- **Authoritative owner:** `docs/NARRATIVE_MASTER_PLAN.md` §6 (the five Origins) ·
  `docs/CONTENT_BIBLE.md` (the `OriginData` authoring template).

## C-012 — Knowledge's dependency owner and order were impossible
- **Side A (D-039, `SYSTEM_DEPENDENCY_MATRIX.md`):** the Knowledge row read
  `| Knowledge | P-19/20 | the story/quest state owner | …`, i.e. knowledge state owned by Story
  and Quest and arriving in Phases 19–20.
- **Side B (same freeze, two other documents):** `PROGRESSION_CULTIVATION_DESIGN.md` §10 lists
  **Cultivation (P-12)** as reading knowledge for breakthrough prerequisites, and **Technique
  (P-15)** as needing "Knowledge (14) for knowledge prerequisites"; the matrix's own Cultivation
  and Technique rows both list `Knowledge` under *Reads*.
- **Affected:** Cultivation (12), Technique (15), Crafting/Economy (13+), Dialogue (18),
  Quest (19), Story (20), every access gate that reads knowledge, and the save layout.
- **Why it matters:** this is a **backwards dependency** — P-12 cannot read authoritative state
  that only comes into existence at P-19. Left alone it would resolve itself in the worst
  available way: Phase 12 would invent a private "known things" dictionary to unblock itself,
  Phase 15 would add a second one, and Phase 20's Story engine would arrive to find two parallel
  sources of truth it has to reconcile — the exact failure D-015 had to be written to undo for
  sect membership. It would also have quietly demoted knowledge from "a third progression axis"
  to "a bag of story flags", losing the one mechanism that lets the Thiên Khế mystery be solved
  by understanding rather than by force.
- **Resolution — RESOLVED.**
  - **Knowledge Core is introduced in PHASE 12**, with its **own authoritative domain owner**:
    `KnowledgeStore` (collection) + `KnowledgeService` (single mutation path). No autoload, no
    global manager, no god object. Persistent domain state.
  - Core responsibilities only: named knowledge ids · acquired state · a deterministic grant
    path · query · persistence boundary · an observable `knowledge_gained` event.
  - **Ownership direction:** Cultivation **reads** · Technique **reads** · Crafting **reads** ·
    Dialogue/Quest/Story **grant and read through the service** · NPC/content **expose
    opportunities**. **No system but the service may mutate the collection.** Story does not own
    knowledge; Quest does not own knowledge; knowledge is never a private story flag.
  - **Phase model:** P-12 core substrate → P-15 Technique consumes prerequisites → P-17 content
    exposes opportunities → P-18 Dialogue grants → P-19 Quest grants → P-20 Story/history grants
    → later phases expand the catalogue. **The core exists before its producers** — the same
    shape as Phase 05, where the relationship graph shipped as a substrate with no producer and
    Phases 06+ became its producers (D-026).
  - **Phase 12 does not grow a story or quest engine to support this.** A store, a service, a
    grant path and an event is the whole core.
- **Authoritative owner:** `docs/PROGRESSION_CULTIVATION_DESIGN.md` §7a (the model) ·
  `docs/SYSTEM_DEPENDENCY_MATRIX.md` (the rows + §4b topology audit) · `docs/CANON_LEDGER.md`
  CL-14 (the frozen fact).

---

## Audit coverage

The freeze ran all 23 required audits (A–W). The table records what each one found; "clean"
means the audit was performed and produced no new contradiction beyond those above.

| Audit | Result |
|---|---|
| A Narrative causality | C-007 (prologue undefined). Every major event now carries the §52 causal chain. |
| B Character motivation | Clean — character template in `CONTENT_BIBLE.md` makes goal/fear/secret mandatory. |
| C Male/female origin | Clean — policy frozen (shared macro canon + per-origin personal thread). |
| D Cultivation hierarchy | **C-001.** |
| E Level vs realm | **C-002** (and steering 02's two-axis contract preserved). |
| F Realm → map | **C-002.** |
| G Realm → dungeon | Clean once C-002 resolved; dungeon access uses the same layered gate. |
| H Technique → weapon | Clean — compatibility matrix frozen in `COMBAT_DESIGN.md` §5. |
| I Economy source/sink | Clean — every frozen currency has ≥1 sink; verified in `ECONOMY_CRAFTING_DESIGN.md` §6. |
| J Grind quality | Clean — four lanes, each with a non-numeric payoff. |
| K Quest repetition | Clean — the two-dimension rule rejects bare "kill 10". |
| L Character relationship | Clean — six dimensions preserved; no morality scalar introduced. |
| M Sect / faction | **C-005.** |
| N World simulation | **C-010** (determinism owner). |
| O World travel | Clean — travel is a layered gate, never a level threshold. |
| P Main / Minor World | Clean — every world must justify its existence (`WORLD_BIBLE.md` §9). |
| Q Tà Đế identity | Clean — no `evil_score`; identity is derived from history. |
| R Thiên Khế logic | Clean — four player stances all produce coherent world reactions. |
| S Multiplayer canon | Clean — four-way state split frozen; no networking added. |
| T UI consistency | Clean — one visual language; per-phase evolution plan. |
| U Content extensibility | Clean — the §82 simulation passes as data + content scenes. |
| V Documentation contradiction | **C-004, C-006, C-008, C-011.** |
| W Roadmap dependency | **C-009** — no correction needed to the engineering order. |
| **X Dependency topology** (added D-040) | **C-010 (RNG phase), C-012 (Knowledge owner/order).** Both were backwards or inconsistent phase edges that the per-system matrix could not reveal; the full edge-by-edge check is `SYSTEM_DEPENDENCY_MATRIX.md` §4b. |

> **Why audit X was added.** Audits A–W each examined one *domain* (narrative, economy, maps, …)
> and all passed. The two defects found afterwards were not inside any one domain — they were
> **edges between phases**, visible only when the whole graph is read as a graph. A per-system
> matrix invites exactly this blind spot: every row can be locally correct while the ordering
> between rows is impossible. Audit X is now a permanent gate, and §4b states its rule: **no
> earlier phase may require authoritative state owned by a later phase.**
