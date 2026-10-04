# SOCIAL_DESIGN — Aetheria

> **Owner of:** the character bible template, relationship consequences, sect design *as a
> designer authors it*, faction/politics design, and what world simulation must produce as
> CONTENT.
> Relationship mechanics are already implemented and owned by `docs/RELATIONSHIP_SYSTEM.md`
> (dimensions, service, store). Sect mechanics by `docs/SECT_SYSTEM.md`. Sim architecture by
> `docs/WORLD_SIMULATION.md`. This document does not restate those; it says what the DESIGN must
> put into them.
>
> Phase 07 (Faction), 08 (World Sim), 17 (NPC) implement the parts not yet built.

---

## 1. Why the social systems came first

Character → Relationship → Sect → Faction → World Simulation were built in Phases 04–08, **before**
NPC/Dialogue/Quest/Story (D-011). That ordering is the single most important structural decision in
the project, and it is worth stating why, because every later phase depends on it holding:

a quest system built *first* would have owned its own NPCs, its own standing numbers and its own
flags. Every later system would then have had to either duplicate that state or negotiate with it.
By building the social substrate first, quests become **consumers** — they read and drive the one
relationship graph, the one sect roster, the one world state. That is what makes "the world
remembers what you did at hour 3" cheap at hour 100 instead of impossible.

## 2. Character bible — every major named NPC

A named NPC is not a quest terminal. Required fields (authoring template in
`CONTENT_BIBLE.md`):

identity · age category · origin · profession · cultivation (realm + path) · personality traits ·
**goal** · **fear** · **secret** · **public belief** · **private belief** · relationships · sect ·
faction · loyalties · conflicts · possible fate · quest links · **death conditions** ·
**escape conditions** · **recruitment conditions** · future callbacks.

Three of these do the heavy lifting:

- **goal / fear / secret** give the character agency. A character with a goal acts when the player
  is not looking (that is what world simulation is *for*); a character with a fear can be moved;
  a character with a secret is worth talking to twice.
- **public belief vs private belief** is the mechanism for the whole Thiên Khế ambiguity at human
  scale. An orthodox elder who privately doubts the covenant is a far better scene than an
  exposition dispenser.
- **death / escape / recruitment conditions** make a character's fate *reactive* instead of
  scripted. The same elder can die, flee or join depending on accumulated state — one authored
  character, several possible histories.

**NPCs are data-driven Characters** using the same `CharacterState` as the player
(`CHARACTER_SYSTEM.md`, implemented). No special-casing in either direction.

## 3. Relationship consequences

The six dimensions are frozen and implemented: **affinity · trust · respect · fear · rivalry ·
debt** (CL-12). No single relationship score. **No morality bar may ever replace them.**

The design vocabulary (already stated as intent in `NARRATIVE_DIRECTION.md` §4 and carried
forward — these become authored `RelationshipRuleData` entries, not code):

| Action | Effect |
|---|---|
| Help a stranger | affinity ↑, trust ↑ |
| Keep a promise | trust ↑, respect ↑ |
| Break a promise | trust ↓ — **and the history persists** |
| Defeat a rival fairly | respect ↑ *and* rivalry ↑ |
| Humiliate a rival | fear ↑, respect may ↓ |
| Rescue someone who owed you | debt shifts |
| Intimidate the weak | fear ↑, affinity ↓ |
| Betray your sect | individual edges shift; sect standing changes; faction consequences; future quests change |

Two properties that must survive into implementation:

1. **Dimensions can move in opposite directions at once.** "Respect up, rivalry up" is the whole
   reason six dimensions exist instead of one. Any rule that moves all dimensions the same way is
   a design smell.
2. **History is bounded but real.** Edges carry a bounded change log (implemented:
   `RelationshipEdge` history + config capacity). Design may rely on "this person remembers that
   you lied" without relying on an unbounded ledger.

## 4. Sect design (what an author must create)

A sect must feel like an organisation, not a buff vendor. Required: doctrine · Dao interpretation ·
cultivation philosophy · favoured weapons · favoured techniques · territory · economy · resources ·
political goals · **internal factions** · taboos · secrets · social culture · relationship culture ·
**attitude toward Tà Đạo** · attitude toward other sects · attitude toward world travel.

**Two hard rules:**
- **Every major sect must have a defensible internal logic.** No "good sect vs bad sect" (C-005).
  The test: can an intelligent, decent person explain why they joined? If not, rewrite the doctrine.
- **Every major sect must contain internal disagreement.** A unanimous organisation has no politics,
  and politics is the gameplay. Worked examples for both shipped sects: `WORLD_BIBLE.md` §8.

**Joining is earned, not granted.** The player starts with no sect (C-003); affiliation is an Act-II
decision made with enough information to matter (`NARRATIVE_MASTER_PLAN.md` §8). Membership flows
through `SectService` so the **roster stays authoritative** and `CharacterState.sect_id` remains a
derived cache (D-015, implemented and verified).

## 5. Faction / politics design (Phase 07)

Factions are **internal** to organisations. Each defines: goals · leader · influence · attitudes ·
methods · allies · enemies · resources · succession concerns · internal disputes.

Politics must be **emergent from data**, not scripted: faction influence, goals and attitude
scalars plus the relationship graph among their members drive outcomes — succession, schism, purge,
coup — resolved as rules over data on simulation ticks (`SECT_SYSTEM.md` §7, the existing contract).

**The escalation ladder the player can climb:**

```
individual → faction → sect → regional politics → world state
```

The design requirement is that each rung is *reachable from the one below*. A player who cannot
affect an individual can never affect a sect; a player who has befriended the right three people
should be able to tip a succession. That is the payoff for the relationship system existing.

## 6. The social consequence loop (the core principle)

```
PLAYER ACTION → WORLD CHANGE → CHARACTER REACTION → RELATIONSHIP CHANGE
   → SECT / FACTION REACTION → QUEST / STORY CHANGE → WORLD SIMULATION
   → NEW EVENT → PLAYER DECISION
```

**Binding on all content:** a story or quest beat must enter this loop rather than bypass it. A
quest that mutates a private flag instead of the relationship/sect state has opted out of the
world — it is the exact failure this architecture was built to prevent.

**Different observers may read the same action differently.** Sparing an enemy raises trust with
one faction and reads as weakness to another. This is not a special case; it is the normal
consequence of per-edge, per-faction attitudes, and it is how a player ends up being called Tà Đế
by some people and savior by others for the *same* act.

## 7. World simulation as a content engine (Phase 08)

The existing architecture is LOD — Near real-time, Far abstract, deterministic, seeded,
save-resumable (`WORLD_SIMULATION.md`). Never full AI for hundreds of NPCs per frame
(`05-performance-testing.md`).

What the simulation must *produce*, from a design point of view: NPC schedules · resource changes ·
breakthroughs · deaths · sect tension · political changes · wars · economic movement · relationship
changes · world events.

**Its job is to create SITUATIONS, not to run a spreadsheet.** The design test for any simulated
quantity: *could a player ever walk into a consequence of this?* An elder breaking through changes
a succession; a vein depleting changes a market and a quest; a war moves a road. A simulated number
no player can encounter is cost without content.

**The player must be able to feel that the world moved without them** — that is the entire return
on this system, and it is what makes "the world remembered what I did" credible.

## 8. Can the player be socially powerful without being the strongest?

Yes, and the design must protect this. Realm gates *authority* (`PROGRESSION_CULTIVATION_DESIGN.md`
§4), but influence also flows from relationships, debts, knowledge and faction position. A Tiên
Thiên cultivator who knows what the orthodox archives edited, holds three elders' debts and can
reach a Vân Hải trading house is a genuine political actor among Ngự Thiên peers.

The converse must also hold: **power must not make the social systems irrelevant.** At high realm,
force stops being the cheap option — a Trọng Thiên actor who solves everything by violence
provokes a coalition. Social systems scale by changing *who* must be negotiated with, not by being
bypassed.

## 9. Dependencies

- Implemented: Character (04), Relationship (05), Sect core (06).
- Phase 07 (Faction) needs: Sect + Relationship. Phase 08 (World Sim) needs: Character + Sect +
  Faction + Relationship + a seeded RNG (C-010) + a world clock.
- Needed by: NPC (17), Dialogue (18), Quest (19), Story (20), Economy (market access), Map (road
  control), and the Tà Đế identity read (`NARRATIVE_MASTER_PLAN.md` §3).
- **Extensibility:** adding a character, sect, faction or relationship is data. Confirmed against
  the §15 simulation in `CONTENT_BIBLE.md`.

## 10. Explicitly NOT frozen

Dimension ranges and deltas per event · faction influence maths · simulation tick rates · LOD
distances · attitude thresholds · succession probabilities. Frozen: the six dimensions, the
character bible field set, the two sect rules, the escalation ladder, the consequence loop, and the
"simulation must produce situations" test.
