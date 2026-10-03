extends TestCase
## Unit tests for Localization (src/infrastructure/localization.gd).
## Fresh instance per test so language changes don't leak between tests.

const LocScript := preload("res://src/infrastructure/localization.gd")


func _make() -> Node:
	var loc: Node = LocScript.new()
	add_to_tree(loc)  # _ready() loads the CSV
	return loc


func test_en_key_resolves() -> void:
	var loc := _make()
	loc.set_language("en")
	assert_eq(loc.t("UI_MENU_NEW_GAME"), "New Game", "en lookup")
	free_node(loc)


func test_vi_key_resolves() -> void:
	var loc := _make()
	loc.set_language("vi")
	assert_eq(loc.t("UI_MENU_NEW_GAME"), "Trò chơi mới", "vi lookup")
	free_node(loc)


func test_language_switching() -> void:
	var loc := _make()
	assert_eq(loc.get_language(), "en", "default language is en")
	assert_true(loc.set_language("vi"), "switch to vi")
	assert_eq(loc.get_language(), "vi")
	assert_eq(loc.t("UI_MENU_QUIT"), "Thoát", "vi after switch")
	assert_true(loc.set_language("en"), "switch back to en")
	assert_eq(loc.t("UI_MENU_QUIT"), "Quit", "en after switch")
	free_node(loc)


func test_unsupported_language_rejected() -> void:
	var loc := _make()
	assert_false(loc.set_language("fr"), "unsupported language rejected")
	assert_eq(loc.get_language(), "en", "language unchanged after rejection")
	free_node(loc)


func test_missing_key_returns_key() -> void:
	var loc := _make()
	# Documented behavior: missing key returns the key itself (warns in dev), never crashes.
	assert_false(loc.has_key("NOT_A_REAL_KEY"))
	assert_eq(loc.t("NOT_A_REAL_KEY"), "NOT_A_REAL_KEY", "missing key echoes the key")
	free_node(loc)


func test_args_substitution() -> void:
	var loc := _make()
	loc.set_language("en")
	assert_eq(loc.t_args("UI_TEST_GREETING", {"name": "Mo"}), "Hello Mo", "en substitution")
	loc.set_language("vi")
	assert_eq(loc.t_args("UI_TEST_GREETING", {"name": "Mo"}), "Xin chào Mo", "vi substitution")
	# A key with no placeholder is returned unchanged.
	assert_eq(loc.t_args("UI_MENU_QUIT", {"name": "x"}), "Thoát", "no placeholder unchanged")
	free_node(loc)


## Phase-04 keys (character identity, menu subtitle, HUD hints) must exist in BOTH languages
## (`07-localization.md` testing rule: no key used in content is missing a vi/en value, and
## the HUD-hint keys carry the {key} placeholder the display-label API substitutes).
func test_phase04_keys_exist_in_both_languages() -> void:
	var loc := _make()
	var keys := [
		"CHARACTER_PLAYER_NAME", "CHARACTER_PLAYER_TITLE", "CHARACTER_PLAYER_ORIGIN",
		"UI_MENU_SUBTITLE", "UI_HUD_INTERACT_HINT", "UI_HUD_MENU_HINT",
		"UI_MENU_SETTINGS", "UI_HUD_INTERACT_ACTION", "UI_HUD_MENU_ACTION",
	]
	for key in keys:
		assert_true(loc.has_key(key), "key '%s' exists in the table" % key)
		loc.set_language("en")
		assert_ne(loc.t(key), key, "en value present for '%s'" % key)
		loc.set_language("vi")
		assert_ne(loc.t(key), key, "vi value present for '%s'" % key)
	free_node(loc)


func test_hud_hint_substitutes_key_placeholder() -> void:
	var loc := _make()
	loc.set_language("en")
	assert_eq(loc.t_args("UI_HUD_INTERACT_HINT", {"key": "E"}), "E Interact",
		"interact hint substitutes the key label")
	assert_eq(loc.t_args("UI_HUD_MENU_HINT", {"key": "Esc"}), "Esc Menu",
		"menu hint substitutes the key label")
	free_node(loc)


## Phase-06 Sect keys (names, doctrines, ranks, type labels, HUD/panel labels) must exist in
## BOTH languages so the Sect UI never shows a raw key or a blank (`07-localization.md`).
func test_phase06_sect_keys_exist_in_both_languages() -> void:
	var loc := _make()
	var keys := [
		"SECT_AZURE_CLOUD_NAME", "SECT_AZURE_CLOUD_DOCTRINE",
		"SECT_CRIMSON_FLAME_NAME", "SECT_CRIMSON_FLAME_DOCTRINE",
		"SECT_RANK_OUTER_DISCIPLE", "SECT_RANK_INNER_DISCIPLE", "SECT_RANK_CORE_DISCIPLE",
		"SECT_RANK_ELDER", "SECT_RANK_SECT_MASTER",
		"SECT_RANK_FLAME_INITIATE", "SECT_RANK_FLAME_ADEPT", "SECT_RANK_FLAME_OVERLORD",
		"SECT_TYPE_ORTHODOX", "SECT_TYPE_DEMONIC", "SECT_TYPE_NEUTRAL", "SECT_TYPE_HIDDEN",
		"UI_HUD_SECT_NONE", "UI_SECT_PANEL_TITLE", "UI_SECT_PANEL_DOCTRINE", "UI_SECT_PANEL_TYPE",
		"UI_SECT_PANEL_TIER", "UI_SECT_PANEL_RANK", "UI_SECT_PANEL_REPUTATION",
		"UI_SECT_PANEL_INFLUENCE", "UI_SECT_PANEL_TERRITORY", "UI_SECT_PANEL_RESOURCES",
		"UI_SECT_PANEL_NONE", "UI_SECT_PANEL_TOGGLE",
	]
	for key in keys:
		assert_true(loc.has_key(key), "sect key '%s' exists in the table" % key)
		loc.set_language("en")
		assert_ne(loc.t(key), key, "en value present for '%s'" % key)
		loc.set_language("vi")
		assert_ne(loc.t(key), key, "vi value present for '%s'" % key)
	free_node(loc)
