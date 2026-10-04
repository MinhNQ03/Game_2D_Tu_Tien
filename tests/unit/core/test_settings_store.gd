extends TestCase
## Unit tests for SettingsStore (player preferences on disk, D-035).
##
## Persistence is high-risk: a preference must round-trip, a write must NOT lose unrelated
## keys, and a missing or corrupt file must never block boot. Every test binds the store to
## a SCRATCH path under `user://` and deletes it afterwards, so the suite never reads or
## clobbers the developer's real `settings.cfg` and no test can see another's writes — disk
## is shared state and the L-010 isolation rule applies to it too.
##
## SettingsStore is a RefCounted, so there is nothing to free (L-019 applies to Nodes).

const StoreScript := preload("res://src/infrastructure/settings_store.gd")

const TEMP_PATH := "user://test_settings_store.cfg"


func before_each() -> void:
	_remove_temp()


func after_each() -> void:
	_remove_temp()


func _remove_temp() -> void:
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(TEMP_PATH)


func _store() -> SettingsStore:
	return StoreScript.new(TEMP_PATH)


## Pre-write a config at the scratch path (simulating an existing preferences file).
func _seed(values: Dictionary) -> void:
	var config := ConfigFile.new()
	for key in values:
		config.set_value(StoreScript.SECTION, String(key), values[key])
	assert_eq(config.save(TEMP_PATH), OK, "seed config saved")


func test_store_binds_to_the_injected_path() -> void:
	assert_eq(_store().get_path(), TEMP_PATH, "the store uses the path it was given")
	assert_eq(StoreScript.new().get_path(), StoreScript.CONFIG_PATH,
		"the default path is the real preferences file")


## First run: no file at all. Must report "nothing stored" so the caller falls back to its
## own default, and must NOT create a file just by being asked.
func test_missing_file_reports_no_preference() -> void:
	assert_false(FileAccess.file_exists(TEMP_PATH), "no config exists yet")
	assert_eq(_store().get_language(), "", "a missing file reports no stored language")
	assert_false(FileAccess.file_exists(TEMP_PATH), "reading did not create the file")


func test_language_round_trips() -> void:
	assert_true(_store().set_language("en"), "writing succeeds")
	assert_eq(_store().get_language(), "en",
		"a fresh store reads back what the previous one wrote")
	assert_true(_store().set_language("vi"), "overwriting succeeds")
	assert_eq(_store().get_language(), "vi", "the overwrite is visible")


## The store must LOAD-MODIFY-SAVE, not overwrite the file, so a preference owned by someone
## else is not silently destroyed when the language changes.
func test_writing_one_key_preserves_other_keys() -> void:
	_seed({StoreScript.KEY_LANGUAGE: "en", "unrelated": 42})
	assert_true(_store().set_language("vi"), "language write succeeds")

	var reread := ConfigFile.new()
	assert_eq(reread.load(TEMP_PATH), OK, "config re-loads")
	assert_eq(String(reread.get_value(StoreScript.SECTION, StoreScript.KEY_LANGUAGE, "")),
		"vi", "the updated key changed")
	assert_eq(int(reread.get_value(StoreScript.SECTION, "unrelated", 0)), 42,
		"the unrelated key survived the write")


## A corrupt file must not wedge the store forever: reading degrades to "no preference" and
## the next write replaces the garbage rather than refusing to save.
func test_corrupt_file_degrades_then_recovers() -> void:
	var f := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	assert_not_null(f, "scratch file opened")
	f.store_string("this is not a valid ConfigFile \x00\x01 [[[")
	f.close()

	assert_eq(_store().get_language(), "",
		"an unreadable file reports no preference instead of raising")
	assert_true(_store().set_language("vi"), "the store rewrites a corrupt file")
	assert_eq(_store().get_language(), "vi", "the value reads back after recovery")


## The store is DUMB storage: the language vocabulary belongs to Localization, so an
## unknown code is persisted verbatim and validated by the caller on read (Main rejects it).
func test_store_does_not_own_the_language_vocabulary() -> void:
	assert_true(_store().set_language("zz"), "the store stores an arbitrary code")
	assert_eq(_store().get_language(), "zz", "and reads it back verbatim")
