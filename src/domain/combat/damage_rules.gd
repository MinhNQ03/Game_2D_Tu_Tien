extends RefCounted
class_name DamageRules
## DamageRules — Aetheria domain (pure game rules).
##
## The ONE place damage math lives (`docs/DATA_SCHEMA.md` §2, `docs/ARCHITECTURE.md` §2:
## "rules sit in domain, pure and unit-testable"). No node/scene dependencies, so it runs
## headless and is trivially testable. Presentation/gameplay NEVER recompute damage; they
## call this (`docs/MULTIPLAYER_PLAN.md` §4: presentation never decides outcomes).
##
## SCOPE (Phase 02 slice, extended in Phase 09 with the two terms that had a consumer):
##   raw        = attacker.attack * power_multiplier      (power: Phase 09, AttackData)
##   mitigated  = raw * defense_factor
##                defense_factor = ATTACK_SCALE / (ATTACK_SCALE + target.defense)
##   crit       = mitigated * critical_multiplier         (crit: Phase 09, seeded stream)
##   final      = max(1, round(…))
##
## WHY POWER AND CRIT LANDED HERE AND NOT IN THE COMBAT CODE. The Phase-02 docstring said
## these two belonged to "the phase that owns them", and the temptation in Phase 09 was to
## apply them where the attack is resolved — which would have put damage math in two places
## and made this class a lie about being the one place it lives. The multiplication is the
## formula; `CombatService` decides WHETHER a hit crits (it owns the seeded roll) and passes
## the answer in.
##
## Both new parameters DEFAULT to the Phase-02 behaviour, so the three existing call sites are
## unchanged and a caller that does not care about power or crit cannot accidentally get them.
##
## Still deliberately NOT included (no consumer yet): flat skill power, elemental resistance,
## technique_mult, equipment_mult. Those scalars belong to công pháp / equipment / elements,
## which own their own data; this function must not grow a parameter per future system.

## Attack-scaling constant for the defense curve. A tunable the full data model will move
## into content later; kept here as the single named constant for the Phase-02 slice so it
## is not a bare magic number at the call site. Higher = defense matters less.
const ATTACK_SCALE: int = 100

## Minimum damage any landed hit deals, so defense can never fully negate a hit
## (`DATA_SCHEMA.md` §2: `final = max(1, …)`).
const MIN_DAMAGE: int = 1


## Multiplier used when a hit does not crit. Named rather than written as a bare `1.0` at the
## call site, so "a normal hit is unscaled" is stated once.
const NO_CRIT_MULTIPLIER: float = 1.0


## Compute the integer damage one hit deals. Deterministic and pure — identical inputs always
## produce an identical number, which is what lets a combat sequence be reproduced from a seed.
##
## `power_multiplier` comes from the `AttackData` being swung; `critical_multiplier` is
## `AttackData.critical_multiplier` when the caller's seeded roll crit, and
## `NO_CRIT_MULTIPLIER` otherwise. This function does NOT roll: a rule that drew its own
## randomness could not be unit-tested without also pinning an RNG, and the decision "did this
## crit" belongs to the service that owns the seeded combat stream.
##
## Defensive at its boundary (callers pass already-validated stats): negative stats are treated
## as 0, and a non-positive multiplier is treated as 1.0 rather than silently zeroing a hit —
## a hit that landed always subtracts at least `MIN_DAMAGE` (`DATA_SCHEMA.md` §2).
static func compute_hit(
		attacker_attack: int,
		target_defense: int,
		power_multiplier: float = 1.0,
		critical_multiplier: float = NO_CRIT_MULTIPLIER) -> int:
	var atk: int = max(0, attacker_attack)
	var defending: int = max(0, target_defense)
	var power: float = power_multiplier if power_multiplier > 0.0 else 1.0
	var crit: float = critical_multiplier if critical_multiplier > 0.0 else NO_CRIT_MULTIPLIER
	var defense_factor: float = float(ATTACK_SCALE) / float(ATTACK_SCALE + defending)
	var mitigated: float = float(atk) * power * defense_factor * crit
	return max(MIN_DAMAGE, int(round(mitigated)))
