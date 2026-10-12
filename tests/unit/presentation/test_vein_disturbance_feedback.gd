extends TestCase
## The broken vein's disturbance beat (VFX starter set, brief I1): at each surge's crest a
## pale ring spreads from the fissure and qi streaks stand up, then settle. The beat is the
## site's own `flow_factor` — the same deterministic function the runtime gathers by — so
## what the eye sees and what a cultivator receives agree. A STEADY vein has no beat.

const FeedbackScript := preload(
	"res://src/presentation/cultivation/vein_disturbance_feedback.gd")
const SiteScript := preload("res://src/gameplay/cultivation/cultivation_site.gd")
const SiteDataScript := preload("res://src/data/cultivation/cultivation_site_data.gd")

const STEP := 1.0 / 60.0


func _site(stability: int) -> CultivationSite:
	var data: CultivationSiteData = SiteDataScript.new()
	data.id = &"site_test_beat"
	data.name_key = &"SITE_TEST_BEAT"
	data.qi_per_second = 5.0
	data.radius_px = 52.0
	data.stability = stability
	var site: CultivationSite = SiteScript.new()
	site.site = data
	site.add_child(FeedbackScript.new())
	add_to_tree(site)
	return site


func _feedback(site: CultivationSite) -> VeinDisturbanceFeedback:
	return site.get_child(0) as VeinDisturbanceFeedback


func test_a_steady_vein_never_pulses() -> void:
	var site := _site(CultivationSiteData.Stability.STEADY)
	var feedback := _feedback(site)
	for i in 1200:
		feedback.advance(STEP)
		assert_false(feedback.is_pulsing(),
			"a steady vein has no beat (fired at t=%.2f)" % (float(i) * STEP))
	free_node(site)


## The crest fires the pulse: the flow rising through SURGE_FLOW, from the site's own beat.
func test_a_broken_veins_crest_fires_the_pulse() -> void:
	var site := _site(CultivationSiteData.Stability.BROKEN)
	var feedback := _feedback(site)
	assert_false(feedback.is_pulsing(), "no pulse before the first crest")
	var fired_at := -1
	for i in 1800:
		feedback.advance(STEP)
		if feedback.is_pulsing():
			fired_at = i
			break
	assert_true(fired_at >= 0, "a broken vein's crest fires the pulse within 30 s")
	assert_true(feedback.flow_now() >= VeinDisturbanceFeedback.SURGE_FLOW,
		"the pulse fires ON the crest (flow %.2f)" % feedback.flow_now())
	free_node(site)


## The pulse settles: it ends on its own, inside its authored lifetime, and the beat can
## fire again afterwards.
func test_the_pulse_settles_and_ends() -> void:
	var site := _site(CultivationSiteData.Stability.BROKEN)
	var feedback := _feedback(site)
	var fired := false
	var ended := false
	for i in 3600:
		feedback.advance(STEP)
		if feedback.is_pulsing():
			fired = true
		elif fired:
			ended = true
			break
	assert_true(fired and ended, "the pulse fires and then settles by itself")
	assert_true(feedback.pulse_progress() == 0.0, "no progress once settled")
	free_node(site)


## The beat is deterministic: the same steps fire the pulse at the same step, twice.
func test_the_beat_is_deterministic() -> void:
	var first := _fire_step()
	var second := _fire_step()
	assert_eq(first, second, "the same beat, the same crest (step %d)" % first)


func _fire_step() -> int:
	var site := _site(CultivationSiteData.Stability.BROKEN)
	var feedback := _feedback(site)
	var fired_at := -1
	for i in 1800:
		feedback.advance(STEP)
		if feedback.is_pulsing():
			fired_at = i
			break
	free_node(site)
	return fired_at
