extends Resource
class_name RealmLadderData
## RealmLadderData — Aetheria data (the ORDERED cảnh giới ladder, Phase 12).
##
## The whole hierarchy in one resource, in canon order (`CANON_LEDGER.md` CL-02):
## PHÀM → HẬU THIÊN → TIÊN THIÊN → NGỰ THIÊN → TRỌNG THIÊN → THÁI THIÊN → VÔ THIÊN. The order is
## the `order` field of each realm, and the validator refuses a ladder whose orders are not
## exactly 0..n-1 in sequence — "the next realm" is then `realms[order + 1]` and can never be
## ambiguous. Only the first realm may be layerless-and-attemptable (PHÀM); the canon realm ids
## are required, so a typo cannot quietly create a sixth macro realm.

## The canonical realm ids, in order (CL-02). A ladder must carry exactly these.
const CANON_IDS: Array[StringName] = [
	&"realm_pham", &"realm_hau_thien", &"realm_tien_thien", &"realm_ngu_thien",
	&"realm_trong_thien", &"realm_thai_thien", &"realm_vo_thien",
]

@export var id: StringName = &""
@export var realms: Array[RealmData] = []


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"":
		errors.append("id is empty")
	if realms.size() != CANON_IDS.size():
		errors.append("the ladder holds %d realms, canon has %d" % [realms.size(),
			CANON_IDS.size()])
		return errors
	for i in realms.size():
		var realm := realms[i]
		if realm == null:
			errors.append("realm %d is null" % i)
			continue
		if realm.id != CANON_IDS[i]:
			errors.append("realm %d is '%s', canon order names '%s' (CL-02)"
				% [i, realm.id, CANON_IDS[i]])
		if realm.order != i:
			errors.append("'%s' has order %d, its position is %d" % [realm.id, realm.order, i])
		for reason in realm.validation_errors():
			errors.append("%s: %s" % [realm.id, reason])
	return errors


## The realm with `realm_id`, or null.
func realm(realm_id: StringName) -> RealmData:
	for r in realms:
		if r != null and r.id == realm_id:
			return r
	return null


## The realm after `realm_id` in the ladder, or null at the top.
func next_of(realm_id: StringName) -> RealmData:
	var r := realm(realm_id)
	if r == null or r.order + 1 >= realms.size():
		return null
	return realms[r.order + 1]


## The ladder's floor: where every mortal begins.
func first() -> RealmData:
	return realms[0] if not realms.is_empty() else null
