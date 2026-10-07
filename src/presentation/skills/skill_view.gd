extends RefCounted
class_name SkillView
## SkillView — Aetheria presentation DTO (the skill dock's contents, Phase 15). Built from the
## `SkillRuntime` and pushed to the HUD through `WorldRuntime`; keys, icons and numbers only.

var qi: float = 0.0
var qi_max: int = 0
## One per LEARNED technique, by key: { "slot", "technique_id", "name_key", "icon", "element",
## "cooldown_left", "cooldown_total", "qi_cost", "ready" }.
var slots: Array[Dictionary] = []


static func make(runtime: SkillRuntime) -> SkillView:
	var view := SkillView.new()
	if runtime == null or not runtime.is_session_active():
		return view
	view.qi = runtime.qi()
	view.qi_max = runtime.qi_capacity()
	for technique in runtime.catalog().entries:
		if not runtime.knows(technique.id):
			continue
		var left := runtime.cooldown_left(technique.id)
		view.slots.append({
			"slot": technique.slot, "technique_id": technique.id,
			"name_key": technique.name_key, "icon": technique.skill.icon,
			"element": technique.skill.element,
			"cooldown_left": left, "cooldown_total": technique.skill.cooldown,
			"qi_cost": technique.skill.qi_cost,
			"ready": left <= 0.0 and runtime.qi() >= float(technique.skill.qi_cost)
				and runtime.casting() == null,
		})
	view.slots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["slot"]) < int(b["slot"]))
	return view
