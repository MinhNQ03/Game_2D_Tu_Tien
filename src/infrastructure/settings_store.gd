extends RefCounted
class_name SettingsStore
## SettingsStore — Aetheria infrastructure (player preferences on disk, D-035).
##
## A tiny `ConfigFile` wrapper over `user://settings.cfg` for choices the PLAYER makes about
## the application itself (currently: language). It is the first persistence in the project,
## and it is deliberately NOT the save-game system: no run/session/world data goes here.
## `SaveService` (Phase 23) owns gameplay saves and will be separate.
##
## It is a plain `RefCounted`, NOT an autoload: the autoload budget is justified per entry
## (`03-architecture.md`, D-017) and one owner (`Localization`) is enough for now. Anything
## else that needs a preference constructs its own instance — the file is the shared state.
##
## FAILURE POLICY: reading or writing preferences must NEVER block the game. Every operation
## degrades to "no preference" + a warning, so a missing/corrupt/read-only file means the
## caller falls back to its own default rather than failing to boot.

const CONFIG_PATH := "user://settings.cfg"

## ConfigFile section holding application preferences.
const SECTION := "application"

## Key for the UI language code ("vi"/"en").
const KEY_LANGUAGE := "language"

## File this instance reads/writes. Defaults to the real preferences file; tests pass a
## scratch path so they never read or clobber the developer's own settings (disk is shared
## state, and the L-010 isolation rule applies to it just as much as to /root).
var _path: String = CONFIG_PATH


func _init(path: String = CONFIG_PATH) -> void:
	_path = path


## The file this store is bound to (for tests + diagnostics).
func get_path() -> String:
	return _path


## The saved language code, or "" when nothing is stored (or the file can't be read).
## The CALLER validates the value against its own supported set — this store is dumb
## storage and must not own the language vocabulary.
func get_language() -> String:
	return String(_read_value(KEY_LANGUAGE, ""))


## Persist the language code. Returns false (with a warning) if the write failed, so a
## caller can report it; nothing in the game depends on the write succeeding.
func set_language(code: String) -> bool:
	return _write_value(KEY_LANGUAGE, code)


# --- ConfigFile plumbing -----------------------------------------------------

## Read one preference. Returns `fallback` when the file is absent (first run — normal and
## silent) or unreadable (warned: a corrupt file is worth knowing about).
func _read_value(key: String, fallback: Variant) -> Variant:
	if not FileAccess.file_exists(_path):
		return fallback  # first run: no preferences yet, not an error
	var config := ConfigFile.new()
	var err := config.load(_path)
	if err != OK:
		push_warning("[settings] cannot read %s (error %d); using defaults" % [_path, err])
		return fallback
	return config.get_value(SECTION, key, fallback)


## Write one preference, preserving any other keys already in the file (load-modify-save,
## so a future setting added by another owner is not clobbered).
func _write_value(key: String, value: Variant) -> bool:
	var config := ConfigFile.new()
	if FileAccess.file_exists(_path):
		var load_err := config.load(_path)
		if load_err != OK:
			# Corrupt file: start a fresh one rather than refusing to save forever.
			push_warning("[settings] %s unreadable (error %d); rewriting it"
				% [_path, load_err])
	config.set_value(SECTION, key, value)
	var err := config.save(_path)
	if err != OK:
		push_warning("[settings] cannot write %s (error %d); choice not persisted"
			% [_path, err])
		return false
	return true
