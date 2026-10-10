# ECONOMY_CRAFTING_DESIGN — Aetheria

> **Owner of:** resource sources, processing, sinks, the market model, anti-inflation policy, and
> the grind philosophy.
> Phases 13–17 implement slices of this; the crafting/economy content phases implement the rest.
>
> **IMPLEMENTED — the shop / trading slice (Phases 13 + 17, D-059 / D-065):**
> - player-held **Linh Thạch is an item** (`item_linh_thach`, an `ItemData` stack in
>   `InventoryState`); the player's funds are the count of that stack — there is no wallet number;
> - `InventoryState.exchange`: an all-or-nothing remove-and-add, the only way a trade moves goods;
> - one shop (`ShopData` / `ShopState` / `ShopService`): finite and unlimited stock, buy and
>   sell, prices moved by ONE relationship dimension of the keeper's regard for the customer,
>   with a validated no-arbitrage bound;
> - `SectState.resources` (spirit stones / pills / manpower / blood crystals) as sect-level
>   holdings — a different owner and a different scale from the player's bag.
>
> **NOT IMPLEMENTED — everything else in this document:** gathering, processing, professions,
> crafting and recipes, the regional market (§7), contribution, travel and information sinks,
> anti-inflation policy as a running system.
>
> **What moves a price today (Phase 18, D-066):** talking to the keeper. A dialogue answer may
> raise or lower his regard through `RelationshipService`; the shop reads the same edge, so
> Kha Thản's affinity of +40 is 8% off and −30 is 9% dearer. Nothing else changes a price —
> no supply, no region, no time.

---

## 1. The one rule

**Every currency and every resource must have at least one real SINK.** A resource with sources
and no sink becomes a meaningless growing number, and a world where numbers only grow has no
economy — just an odometer. This is checked per-resource in §6.

## 2. The chain

```
SOURCES → PROCESSING → SINKS
              ↕
           MARKET
```

Processing is what makes the economy a *game* rather than a shop: raw things are not useful, and
turning them into useful things is where profession skill, knowledge and choice live. The market
is a pressure valve between all three, not a separate system.

## 3. Sources

| Source | Yields | Design job |
|---|---|---|
| **Combat** | monster materials, drops | makes fighting feed building |
| **Gathering** | linh thảo (herbs), khoáng sản (ore), vein residue | rewards knowing *where*, and realm-gated places |
| **Exploration** | caches, bí cảnh finds, **knowledge** | rewards curiosity; the only source whose main yield is non-material |
| **Professions** | refined/processed goods | rewards investment in a lane |
| **Quests** | targeted rewards, access, reputation | the designer's lever for pacing |
| **Dungeons** | concentrated materials, signature items | the "I earned this" source |
| **World events** | unusual, time-bound resources | makes the living world materially relevant |

**Regional identity is mandatory.** A resource must come from somewhere specific
(`WORLD_BIBLE.md`'s five vực each have a material character) — otherwise maps are interchangeable
and there is no reason to travel or trade. Example: vein-adjacent material from the Hoang Vực
frontier is *unsurveyed*, which is exactly why a Vân Hải trader wants it cheaply
(`NARRATIVE_MASTER_PLAN.md` §4) — the economy and the inciting event are the same fact.

## 4. Processing (professions)

| Profession | Takes | Makes |
|---|---|---|
| **Thợ Thạch** (stonecutter) | raw vein material, ore | refined spirit stones, cores |
| **Tinh Luyện** (refiner) | herbs, materials | reagents, essences |
| **Chế Tạo** (artificer) | refined inputs | equipment, pháp khí, phù (talismans) |
| **Đan Sư** (alchemist) | reagents | pills — cultivation and combat consumables |

Professions are **data-driven recipes**, not classes. A recipe may require: inputs · a profession
level · a **knowledge** id · a realm · a location/facility · a tool. That last set is what lets a
recipe be a *discovery* rather than a menu item.

**Knowledge-gated recipes READ the Knowledge Core; crafting never owns knowledge state** (D-040 /
C-012). The Knowledge Core (`KnowledgeStore`/`KnowledgeService`) lands in **Phase 12**, so by the
time a knowledge-gated recipe exists its owner already does — crafting queries it and must not
keep a private "recipes the player has learned about" set alongside it.
See `PROGRESSION_CULTIVATION_DESIGN.md` §7a.

## 5. Sinks

| Sink | Consumes | Why it is a good sink |
|---|---|---|
| **Cultivation** | spirit stones, pills | the primary sink: progress itself costs |
| **Crafting / refining** | materials, reagents | converts, with loss |
| **Equipment upgrade / repair** | materials, currency | recurring, scales with power |
| **Consumables** | pills, talismans | burned permanently in play |
| **Sect contribution** | resources, currency | buys rank, access, techniques (ties the economy to the social system) |
| **Travel** | currency, keys, gate costs | makes world travel cost something |
| **Profession advancement** | materials + failed attempts | the lane pays for itself |
| **Information** | currency | **buying knowledge** — a sink unique to Aetheria's design |
| **Prestige (optional)** | surplus | end-of-curve surplus drain; never power |

## 6. Source ↔ sink audit (Audit I)

Every frozen resource, checked:

| Resource | Sources | Sinks | Verdict |
|---|---|---|---|
| **Linh Thạch** (spirit stones) | combat, gathering, quests, trade | cultivation, crafting, contribution, travel, information | OK — the main currency, heavily drained |
| **Đan Dược** (pills) | alchemy, dungeons, quests | consumed in cultivation and combat | OK — burned by design |
| **Linh Thảo** (herbs) | gathering, world events | alchemy inputs | OK |
| **Khoáng Sản** (ore) | gathering, dungeons | stonecutting/artificing inputs | OK |
| **Monster materials** | combat | crafting, recipes | OK |
| **Huyết Tinh** (blood crystals) | heterodox sources, Huyết Mạc content | Cấm Pháp methods, heterodox crafting | OK — deliberately narrow; its scarcity is a social signal |
| **Nhân Lực** (manpower) | sect-level, not player-held | sect operations (Phase 07+) | OK — sect-scope only; must never become a player currency |
| **Tri Thức** (knowledge) | exploration, records, dialogue, purchase | gates; **never consumed** | **Deliberate exception** — knowledge is permanent by design (CL-14). It is not a currency and is exempt from the sink rule. |

## 7. Market

The market exists to connect regions, not to be a trading minigame. Requirements:

- **Prices reflect scarcity and place.** The same material is worth different amounts in different
  vực — that is the whole reason to move goods.
- **Relationships and standing affect access and price**, reading the existing relationship graph
  and sect/faction standing (`SOCIAL_DESIGN.md`) — not a separate "merchant favour" number.
- **Some goods are not for sale to the player yet** — access is a reward, which makes standing
  materially valuable.
- A **black market** exists for proscribed goods (Tà Đạo materials, suppressed records), with
  social risk attached. This is how the economy expresses CL-01.

## 8. Anti-inflation policy

The failure state: late-game players hold so much currency that nothing has a price, and every
earlier reward becomes insulting.

1. **The primary sink scales with progress.** Cultivation costs rise with realm, so the main
   money drain grows exactly as income grows.
2. **Consumables are burned, not banked.** Pills and talismans leave the economy permanently.
3. **Conversion has loss.** Processing is not 1:1; refining destroys value as well as creating it.
4. **Rewards are increasingly non-monetary at high realm:** access, knowledge, standing,
   territory. These cannot inflate because they are not fungible.
5. **No infinite repeatable high-yield loop.** A repeatable activity must have a diminishing or
   bounded yield per period; the designer's lever is quality, not quantity.
6. **Never solve inflation by raising prices alone** — that taxes new players to punish veterans.
   Add a sink, or make the reward non-monetary.

## 9. Grind philosophy

Grinding is **appropriate** for cultivation fantasy — the fantasy is partly about accumulated
effort. But every repeatable activity must answer: *what does the player gain besides a bigger
number?*

| Lane | Loop | Non-numeric payoff |
|---|---|---|
| **Combat grind** | enemy → material → crafting → stronger build | a build you chose, not a number you accrued |
| **Cultivation grind** | spiritual site → tu luyện → breakthrough preparation | a **capability** and a social position (realm) |
| **Profession grind** | gather → refine → craft → trade | self-sufficiency, and goods others want |
| **Exploration grind** | discover → knowledge → access | understanding — the mystery advances |

**Hard rule: the main story is never gated behind bulk repetition.** Grind is optional
depth, an accelerator, and a lane for players who enjoy it — never a toll gate on the narrative.
A quest may require *a* rare material; it may not require fifty of a common one.

## 10. Dependencies

- Needs: Item (13) for inventory, Equipment (14), Combat (09) for drops, Cultivation (12) for the
  primary sink, **Knowledge Core (12) for knowledge-gated recipes (read-only)**, Map (03) for
  regional identity, NPC (17) for shops, Quest (19) for targeted rewards, World Simulation (08)
  for market movement and event-bound resources.
- Any randomness (drops, market movement) uses the **deterministic stream-scoped RNG seam
  introduced in Phase 08** — never a global `rand*()` (C-010).
- Needed by: Equipment, Crafting, Sect contribution (07+), Dungeon rewards (21), Boss rewards (22).
- `SectState.resources` already exists and is sect-scoped. **Player currency is a separate
  concern** and must not be modelled by extending the sect resource dictionary.

## 11. Explicitly NOT frozen

Every number: prices, drop rates, yields, conversion ratios, cultivation costs, profession curves,
market elasticity, black-market premiums. Frozen: the chain, the source and sink *sets*, the
per-resource audit obligation, the anti-inflation policy, and the grind-purpose rule.
