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
