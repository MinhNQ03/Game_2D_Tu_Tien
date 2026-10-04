# MAP_DUNGEON_DESIGN — Aetheria

> **Owner of:** map grammar, **access gating** (the authoritative answer to "how does the player
> get in?"), map loops and revisit value, dungeon grammar, boss placement, world travel, and the
> **quest taxonomy + quality rules** (§7).
> Realm vocabulary: `docs/PROGRESSION_CULTIVATION_DESIGN.md`. Geography: `docs/WORLD_BIBLE.md`.
> Map/SceneRouter mechanics already exist (Phase 03); dungeons are Phase 21, bosses Phase 22,
> quests Phase 19. **No gameplay implemented here.**

---

## 1. Every map must justify itself

A map may only be authored if it answers all of these. "We need another area" is not an answer.

narrative purpose · gameplay purpose · visual identity · combat identity · resource identity ·
social identity · realm range (threat rating) · **access condition** · exits · shortcuts ·
secrets · relevant NPCs · relevant quests · dungeon · boss · **reasons to revisit**.

**Anti-pattern: the large empty map.** Size is not content. A smaller map with three reasons to be
there beats a large one with none. The shipped maps are deliberately roomy because they are
prototype layouts reserved for later NPC/encounter content (D-036) — that is a known, recorded
state, not the target.

## 2. Map grammar

| Kind | Job |
|---|---|
| **Hub** | safety, services, NPCs, quest sources, the social centre of a châu |
| **Field** | traversal, gathering, encounters, the connective tissue |
| **Resource site** | a reason to go somewhere specific (regional material) |
| **Bí cảnh / secret** | reward for curiosity and knowledge |
| **Dungeon** | authored, concentrated challenge (§5) |
| **Boss arena** | the chapter exam (§6) |
| **Vein site** | cultivation ground; also territory, therefore also politics |

## 3. ACCESS GATING (authoritative — resolves C-002)

**Level is NEVER an access gate.** Not for maps, dungeons, worlds, quests, techniques or
dialogue. The level→map pattern (`Lv 10–30`) is reinterpreted as an advisory **threat rating**
(`PROGRESSION_CULTIVATION_DESIGN.md` §6).

Access is a **layered gate**: a place may require any combination of —

| Gate | Example |
|---|---|
| **Realm** | the qi here is unsafe below Tiên Thiên |
| **Quest / story** | the pass is closed until the frontier arc resolves |
| **Knowledge** | you must know how to read the gate's inscription (CL-14) |
| **Sect standing** | a sect's territory is open to its disciples |
| **Faction standing** | a faction controls the only road |
| **World state** | the vein is in flood; the route exists only afterwards |
| **Item / technique** | a key, a talisman, a traversal technique |
| **World gate** | crossing the Hải Giới (§4) |

Design rules:
1. **At least one gate must be non-numeric** for any significant location — otherwise it is level
   gating with extra steps.
2. **A gate must be legible before it is passable.** The player should be able to see the locked
   thing and understand *what kind* of key it needs. An invisible gate is a bug, not mystery.
3. **Prefer "you may enter and die" over "you may not enter"** wherever it is survivable. Advisory
   threat preserves the prepared down-realm victory (`WORLD_BIBLE.md` §5) and respects the player.
4. `MapData` must never gain a `min_level` field. It gains an advisory `threat_rating` and a
   structured `access_requirements` list when Phase 12+ needs them.

## 4. World travel is progression

Never *"level 20 = new world."* Crossing the Hải Giới requires a **combination**: realm +
knowledge + technique + quest + relationship or standing + an artifact/world gate + a world-state
condition.

The canonical shape of a world-travel arc:

```
discover a broken gate → investigate → learn WHY it exists → obtain the knowledge/technique
   → establish access → enter the Tiểu Giới → learn a different cultivation tradition
   → survive → return → the consequences spread back into the Main World
```

Each step is a different *kind* of gameplay (exploration, investigation, cultivation, survival,
social), which is what makes arrival feel earned. The return leg is mandatory: a world the player
visits and never hears from again was wallpaper after all.

## 5. Dungeon grammar

A dungeon is **not** "a small map with stronger enemies." Every dungeon defines:

**narrative justification** (why does this place exist in the world?) · **unique visual identity**
· **a unique gameplay gimmick** (one mechanic that is this dungeon's idea) · **encounter variety**
· **an environmental mechanic** · **shortcut/checkpoint** · **elite or mini-boss** where useful ·
**final boss** · **reward identity** (what only this dungeon gives) · **a replay reason**.

The gimmick is the acceptance test. If a dungeon's one-line pitch is "it's a cave with spiders",
it is a field map with a door.

## 6. Boss placement

Bosses are the chapter exam: a boss **tests mechanics introduced earlier in its chapter**
(`COMBAT_DESIGN.md` §8), and defeating it produces a **post-boss world consequence** — a changed
route, a changed faction balance, a revealed record. A boss with no world consequence is a loot
piñata.

## 7. Quest taxonomy and quality (authoritative)

**Categories:** Main Story · Character · Sect · Faction · Relationship · Exploration · Mystery ·
Cultivation Trial · Bounty · Dungeon · Profession · World Event · Hidden.

**Every major quest defines:** source · motivation · objective · obstacle · gameplay activity ·
social dimension · choice · reward · consequence · future callback.

**The two-dimension rule.** A strong quest meaningfully combines **at least two** of: combat ·
exploration · investigation · social choice · resource management. A single-dimension quest is
filler — and "kill 10 wolves" is only acceptable when it is *actually about* something else (the
wolves are mutated by the broken vein, and the player is establishing that fact).

**Quest outcomes may affect:** a relationship · sect standing · faction standing · the economy ·
access · information · world state · a future quest. A quest whose only output is XP and coins has
not participated in the world.

**Quests arise from the world, not from a quest-giver's job description** — characters, sects and
politics produce objectives (`GAME_FLOW.md` §1b), which is why the social systems were built
first (D-011).

## 8. Map loop design

Prefer loops over corridors:

```
HUB → FIELD → RESOURCE → QUEST → COMBAT → SECRET → DUNGEON → BOSS
    → STORY REVEAL → SHORTCUT / NEW ROUTE → HUB
```

The shortcut closing the loop is what makes a cleared area feel *owned* rather than finished.

## 9. Revisit value (anti-respawn)

Every important map must have **several** reasons to return. Enemy respawns are not one of them.

new realm (previously unsafe areas open) · a new technique (traversal reaches new ground) · a new
NPC relationship · a faction change (control of a road changed hands) · a world-state change ·
a hidden quest now solvable · a new resource in season · a new route · a new dungeon path · a
world event.

**Design consequence:** maps must be authored with *reserved space* for later unlocks — a ledge
that is unreachable now, a sealed door, a flooded path. This is cheap to author up front and
impossible to retrofit convincingly.

## 10. Dependencies

- Already implemented: `MapData`/`MapExit`/`MapCatalog` + `WorldRuntime` + `SceneRouter` with
  transactional transitions and data-driven camera bounds (Phase 03, D-021/D-022/D-036).
- Needs for gating: Cultivation (12) for realm, Quest (19)/Story (20) for flags, Sect (06, done)
  and Faction (07) for standing, World Simulation (08) for world state, Item (13) for keys.
- Needed by: Dungeon (21), Boss (22), Economy (regional resources), Quest (19), World travel.
- **Extensibility:** adding a map/dungeon/boss/region is a `.tres` + a content scene registered by
  `scene_key`. No core edit (`GAME_FLOW.md` §2).

## 11. Explicitly NOT frozen

Map dimensions · threat-rating boundaries · encounter density · spawn rates · dungeon length ·
boss HP/phase timings · reward tables. Frozen: the justification checklist, the gating model, the
world-travel shape, dungeon/boss/quest grammar, and the revisit obligation.
