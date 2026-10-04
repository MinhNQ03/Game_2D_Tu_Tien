extends RefCounted
class_name RelationshipEndpoint
## RelationshipEndpoint — Aetheria domain (one end of a relationship edge).
##
## A TYPED reference to a party in the relationship graph (`docs/RELATIONSHIP_SYSTEM.md` §4):
## a `{ kind, id }` pair, never a bare String. `kind` distinguishes a Character instance from
## a Sect from a Faction, so the character instance "player", a sect id "player" and a faction
## id "player" (hypothetically) can never collide. This keeps the graph referentially
## unambiguous and the save format explicit.
##
## Pure domain: a `RefCounted` with NO Node / scene / presentation dependency
## (`03-architecture.md`: domain must not import presentation). Serializes to plain data
## (`{ "kind": "character", "id": "player" }`).

## What a relationship endpoint can be. CHARACTER = a `CharacterState.instance_id`;
## SECT = a `SectState.id` (Phase 06); FACTION = a `FactionState.id`, an internal political
## group inside a sect (Phase 07, D-042).
##
## FACTION is appended, never inserted, and the enum int is never serialized (the tokens
## below are), so adding it cannot shift the meaning of an existing save.
enum Kind { CHARACTER, SECT, FACTION }

## Stable string tokens used in serialization (JSON-friendly, order-independent, never an
## enum int that could drift if the enum is reordered). The single source of truth for the
## kind <-> token mapping.
const KIND_CHARACTER := "character"
const KIND_SECT := "sect"
const KIND_FACTION := "faction"

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


## A faction (an internal political group within a sect, Phase 07). Typed separately from
## SECT so a faction id can never be mistaken for the sect that contains it — the two live in
## different id namespaces and a collision would silently merge a faction's politics into its
## parent sect's diplomacy.
static func for_faction(faction_id: StringName) -> RelationshipEndpoint:
	return RelationshipEndpoint.new(Kind.FACTION, faction_id)


# --- Validity ----------------------------------------------------------------

## True when the endpoint is well-formed: a known kind and a non-empty id.
func is_valid() -> bool:
	return kind >= 0 and kind < Kind.size() and id != &""


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

## The serialized token for this endpoint's kind. A `match`, not a chain of ternaries: with
## three kinds a ternary chain would silently fall through to "character" for any kind it did
## not name, which is how an unhandled kind becomes a plausible-looking wrong endpoint rather
## than a loud bug.
func kind_token() -> String:
	match kind:
		Kind.SECT:
			return KIND_SECT
		Kind.FACTION:
			return KIND_FACTION
		_:
			return KIND_CHARACTER


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
		KIND_FACTION:
			return Kind.FACTION
		_:
			return -1
