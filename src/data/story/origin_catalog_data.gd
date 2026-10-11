extends Resource
class_name OriginCatalogData
## OriginCatalogData — Aetheria data (the five Origins, Phase 20, D-072).
##
## The set is FROZEN canon (CL-09): exactly these five ids, byte for byte. Adding a sixth or
## renaming one is a core-design change with a decision record, not a content edit — so the
## catalog itself refuses any other shape.

const FROZEN_IDS: Array[StringName] = [
	&"origin_ho_tieu", &"origin_de_tu_bi_loai", &"origin_lang_y", &"origin_nghe_nhan",
	&"origin_thu_thu",
]

@export var entries: Array[OriginData] = []


func entry(origin_id: StringName) -> OriginData:
	for origin in entries:
		if origin != null and origin.id == origin_id:
			return origin
	return null


func has(origin_id: StringName) -> bool:
	return entry(origin_id) != null


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for origin in entries:
		if origin != null:
			out.append(origin.id)
	return out


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	var seen := {}
	for i in entries.size():
		var origin := entries[i]
		if origin == null:
			errors.append("origin %d is null" % i)
			continue
		errors.append_array(origin.validation_errors())
		if seen.has(origin.id):
			errors.append("duplicate origin id '%s'" % origin.id)
		seen[origin.id] = true
		if not FROZEN_IDS.has(origin.id):
			errors.append("'%s' is not one of the five frozen Origins (CL-09)" % origin.id)
	for frozen in FROZEN_IDS:
		if not seen.has(frozen):
			errors.append("the frozen Origin '%s' is missing (CL-09)" % frozen)
	return errors
