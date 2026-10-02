extends RefCounted
class_name DamageRules
## DamageRules — Aetheria domain (pure game rules).
##
## The ONE place damage math lives (`docs/DATA_SCHEMA.md` §2, `docs/ARCHITECTURE.md` §2:
## "rules sit in domain, pure and unit-testable"). No node/scene dependencies, so it runs
## headless and is trivially testable. Presentation/gameplay NEVER recompute damage; they
## call this (`docs/MULTIPLAYER_PLAN.md` §4: presentation never decides outcomes).
##
## PHASE 02 SCOPE — a MINIMAL, DETERMINISTIC slice of the documented formula:
##   raw        = attacker.attack            (no skill power/flat yet — Phase 09)
##   mitigated  = raw * defense_factor
##                defense_factor = ATTACK_SCALE / (ATTACK_SCALE + target.defense)
##   final      = max(1, round(mitigated))   (no crit/resist/technique/equipment yet)
##
## Deliberately NOT included (added by the phase that owns them, each with a consumer):
## skill power_mult/flat_power, elemental resist, crit (needs seeded RNG — the `RNG`
## autoload is deferred, D-017), technique_mult, equipment_mult. This is NOT a combat
## system and does not resolve the combat timing model (D-007 stays Open) — it only
## answers "how much does one hit subtract", which is model-agnostic.

## Attack-scaling constant for the defense curve. A tunable the full data model will move
## into content later; kept here as the single named constant for the Phase-02 slice so it
## is not a bare magic number at the call site. Higher = defense matters less.
const ATTACK_SCALE: int = 100

## Minimum damage any landed hit deals, so defense can never fully negate a hit
## (`DATA_SCHEMA.md` §2: `final = max(1, …)`).
const MIN_DAMAGE: int = 1


## Compute the integer damage one hit deals, given the attacker's attack and the target's
## defense. Deterministic and pure. Negative inputs are treated as 0 (callers pass stat
## values that are already validated >= 0, but the rule is defensive at its boundary).
static func compute_hit(attacker_attack: int, target_defense: int) -> int:
	var atk: int = max(0, attacker_attack)
	var defending: int = max(0, target_defense)
	var defense_factor: float = float(ATTACK_SCALE) / float(ATTACK_SCALE + defending)
	var mitigated: float = float(atk) * defense_factor
	return max(MIN_DAMAGE, int(round(mitigated)))
