extends RefCounted
class_name PetView
## PetView — Aetheria presentation DTO (what the HUD shows about the linh thú, Phase 16).
##
## A read-only snapshot built by `PetRuntime.build_view()` and pushed through `WorldRuntime` →
## `MapBase` → `GameplayHUD`, the route every other view takes. Localization KEYS and plain
## numbers only — never a `PetStore`, never the pet's node.

## The player owns a pet (with none, the HUD shows nothing about pets at all).
var available: bool = false
var name_key: StringName = &""
## Derived from XP (D-064); 0 when unavailable.
var level: int = 0
## Its body is in the world right now.
var out: bool = false
## It fell and cannot be called yet.
var recovering: bool = false


static func make_empty() -> PetView:
	return PetView.new()
