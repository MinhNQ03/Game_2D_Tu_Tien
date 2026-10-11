extends Resource
class_name StorySceneCatalogData
## StorySceneCatalogData — Aetheria data (every authored story scene, Phase 20).

@export var entries: Array[StorySceneData] = []


func entry(scene_id: StringName) -> StorySceneData:
	for scene in entries:
		if scene != null and scene.id == scene_id:
			return scene
	return null


func has(scene_id: StringName) -> bool:
	return entry(scene_id) != null


func text_keys() -> Array[StringName]:
	var keys: Array[StringName] = []
	for scene in entries:
		if scene != null:
			keys.append_array(scene.text_keys())
	return keys


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	var seen := {}
	for i in entries.size():
		var scene := entries[i]
		if scene == null:
			errors.append("scene %d is null" % i)
			continue
		errors.append_array(scene.validation_errors())
		if seen.has(scene.id):
			errors.append("duplicate scene id '%s'" % scene.id)
		seen[scene.id] = true
	return errors
