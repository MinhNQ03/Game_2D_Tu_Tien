extends Node
## Localization — Aetheria infrastructure (autoload "Localization").
##
## Thin service over a key→string table (D-008: Godot CSV translations). Call sites use
## stable keys and never see literal user-facing strings. The backing store is loaded
## from `locale/aetheria.csv` at runtime so lookups are deterministic and testable
## headless, independent of the editor's .translation import step.
##
## Public API: t(key), t_args(key, {name: value}), set_language(code), get_language(),
##             has_key(key), available_languages().
## (We use `t`/`t_args` rather than overriding Godot's built-in Object.tr().)
##
## Missing-key behavior (documented, see docs/TEST_PLAN.md / DEBUGGING.md): return the key
## itself and push_warning in dev — never crash, never return an empty string silently.

const DEFAULT_LANGUAGE := "en"
const SUPPORTED_LANGUAGES := ["en", "vi"]
const CSV_PATH := "res://locale/aetheria.csv"

## _table[key][lang] -> String
var _table: Dictionary = {}
var _language: String = DEFAULT_LANGUAGE
var _loaded: bool = false


func _ready() -> void:
	_ensure_loaded()


## Idempotent load so tests can use the service without a full autoload boot.
func _ensure_loaded() -> void:
	if _loaded:
		return
	_load_csv(CSV_PATH)
	_loaded = true


func _load_csv(path: String) -> void:
	_table.clear()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[loc] cannot open translation CSV: %s" % path)
		return
	var header := f.get_csv_line()  # e.g. ["keys","en","vi"]
	if header.size() < 2 or header[0] != "keys":
		push_error("[loc] malformed CSV header in %s (expected 'keys' first column)" % path)
		f.close()
		return
	var lang_cols: Array[String] = []
	for i in range(1, header.size()):
		lang_cols.append(header[i])
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() == 0 or (row.size() == 1 and row[0] == ""):
			continue
		var key := row[0]
		if key == "":
			continue
		var entry: Dictionary = {}
		for i in range(lang_cols.size()):
			var col_index := i + 1
			entry[lang_cols[i]] = row[col_index] if col_index < row.size() else ""
		_table[key] = entry
	f.close()


# --- Public API -------------------------------------------------------------

func get_language() -> String:
	return _language


func available_languages() -> Array:
	return SUPPORTED_LANGUAGES.duplicate()


## Sets the active language. Rejects unsupported codes loudly. Emits language_changed via
## EventBus (if present) and syncs Godot's TranslationServer locale for any native tr().
func set_language(code: String) -> bool:
	if not SUPPORTED_LANGUAGES.has(code):
		push_warning("[loc] unsupported language '%s'; keeping '%s'" % [code, _language])
		return false
	if code == _language:
		return true
	_language = code
	TranslationServer.set_locale(code)
	var bus := get_node_or_null("/root/EventBus")
	if bus != null and bus.has_method("emit_language_changed"):
		bus.call("emit_language_changed", code)
	return true


func has_key(key: String) -> bool:
	_ensure_loaded()
	return _table.has(key)


## Resolve a key to the current language. Falls back to the default language, then to the
## key itself (with a dev warning). Never crashes.
func t(key: String) -> String:
	_ensure_loaded()
	if not _table.has(key):
		push_warning("[loc] missing key: %s" % key)
		return key
	var entry: Dictionary = _table[key]
	if entry.has(_language) and String(entry[_language]) != "":
		return String(entry[_language])
	if entry.has(DEFAULT_LANGUAGE) and String(entry[DEFAULT_LANGUAGE]) != "":
		return String(entry[DEFAULT_LANGUAGE])
	push_warning("[loc] key '%s' has no value for '%s' or default" % [key, _language])
	return key


## Resolve a key and substitute {placeholders} from `args`. Unknown placeholders are left
## untouched. Avoids string concatenation so grammar stays per-language.
func t_args(key: String, args: Dictionary) -> String:
	var text := t(key)
	for arg_key in args.keys():
		text = text.replace("{%s}" % str(arg_key), str(args[arg_key]))
	return text
