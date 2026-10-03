extends RefCounted
class_name RelationshipEndpoint
## RelationshipEndpoint — Aetheria domain (one end of a relationship edge).
##
## A TYPED reference to a party in the relationship graph (`docs/RELATIONSHIP_SYSTEM.md` §4):
## a `{ kind, id }` pair, never a bare String. `kind` distinguishes a Character instance from
## a Sect, so the character instance "player" and a sect id "player" (hypothetically) can
## never collide. This keeps the graph referentially unambiguous and the save format explicit.
##
## Pure domain: a `RefCounted` with NO Node / scene / presentation dependency
## (`03-architecture.md`: domain must not import presentation). Serializes to plain data
## (`{ "kind": "character", "id": "player" }`).

## What a relationship endpoint can be. CHARACTER = a `CharacterState.instance_id`;
## SECT = a `SectState.id` (structural support only in Phase 05 — the real SectState arrives
## in Phase 06, `docs/RELATIONSHIP_SYSTEM.md` §10).
enum Kind { CHARACTER, SECT }

## Stable string tokens used in serialization (JSON-friendly, order-independent, never an
## enum int that could drift if the enum is reordered). The single source of truth for the
## kind <-> token mapping.
const KIND_CHARACTER := "character"
const KIND_SECT := "sect"

var kind: int = Kind.CHARACTER
var id: StringName = &""


func _init(endpoint_kind: int = Kind.CHARACTER, endpoint_id: StringName = &"") -> void:
	kind = endpoint_kind
	id = endpoint_id


# --- Factories (intent-revealing) --------------------------------------------

static func for_character(character_id: StringName) -> RelationshipEndpoint:
	return RelationshipEndpoint.new(Kind.CHARACTER, character_id)


static func for_sect(sect_id: StringName) -> RelationshipEndpoint:
	return RelationshipEndpoint.new(Kind.SECT, sect_id)


# --- Validity ----------------------------------------------------------------

## True when the endpoint is well-formed: a known kind and a non-empty id.
func is_valid() -> bool:
	return (kind == Kind.CHARACTER or kind == Kind.SECT) and id != &""


# --- Identity / comparison ---------------------------------------------------

## Value equality (same kind + same id). Endpoints are compared by value, not reference.
func equals(other: RelationshipEndpoint) -> bool:
	return other != null and other.kind == kind and other.id == id


## A stable comparison key `"<kind_token>:<id>"` used for canonical ordering of a symmetric
## edge's endpoints (`docs/RELATIONSHIP_SYSTEM.md` §4 symmetric contract) and for deterministic
## serialization. Kind first, then id — so ordering is total and reproducible.
func compare_key() -> String:
	return "%s:%s" % [kind_token(), String(id)]


## Lexicographic order relative to `other`: <0 if self precedes, 0 if equal, >0 if after.
func compare_to(other: RelationshipEndpoint) -> int:
	var a := compare_key()
	var b := other.compare_key()
	if a < b:
		return -1
	if a > b:
		return 1
	return 0


# --- Serialization (plain data) ----------------------------------------------

func kind_token() -> String:
	return KIND_SECT if kind == Kind.SECT else KIND_CHARACTER


func to_dict() -> Dictionary:
	return {"kind": kind_token(), "id": String(id)}


## Parse an endpoint from plain data. Returns null (never a half-built endpoint) on a
## malformed payload so the caller fails closed (`04-coding-standards.md`: validate at the
## boundary, no silent partial). Does NOT `push_error` — the owning store reports with edge
## context.
static func from_dict(data: Variant) -> RelationshipEndpoint:
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var dict: Dictionary = data
	var token := String(dict.get("kind", ""))
	var parsed_kind := kind_from_token(token)
	if parsed_kind < 0:
		return null
	var parsed_id := StringName(String(dict.get("id", "")))
	if parsed_id == &"":
		return null
	return RelationshipEndpoint.new(parsed_kind, parsed_id)


## Map a serialized token to a Kind, or -1 if unknown (used for fail-closed hydrate).
static func kind_from_token(token: String) -> int:
	match token:
		KIND_CHARACTER:
			return Kind.CHARACTER
		KIND_SECT:
			return Kind.SECT
		_:
			return -1
