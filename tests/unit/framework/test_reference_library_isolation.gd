extends TestCase
## Reference material never enters the Godot resource pipeline (D-057, D-057A §10).
##
## `docs/design_refs/` holds LOCAL design-reference libraries — the Aetheria xianxia moodboards,
## the Foozle/Kenney source packs — which are reference-only by classification
## (`docs/ASSET_LICENSES.md`). Being gitignored kept them out of the repository, and that was
## mistaken for keeping them out of `res://`: Godot scans and imports every image under the
## project root, so the moodboards were imported into `.godot/imported/` like game textures —
## listed in the FileSystem dock, draggable into a scene, and included by any "export all
## resources" build. Nothing failed, because nothing looked.
##
## The mechanism is ONE tracked `docs/.gdignore`, so every clone and every future pack dropped
## anywhere under `docs/` is covered without anyone remembering a per-pack ignore file.

const DOCS_ROOT := "res://docs"
const IGNORE_MARKER := "res://docs/.gdignore"


## The mechanism exists. This is not a spelling guard (L-040): `.gdignore` IS the property — it
## is the only thing Godot reads to decide that a directory is not part of the project.
func test_docs_is_excluded_from_the_godot_resource_pipeline() -> void:
	assert_true(FileAccess.file_exists(IGNORE_MARKER),
		("%s exists, so Godot never scans, imports or exports anything under docs/ — without "
			+ "it, every reference image there is imported as a game texture") % IGNORE_MARKER)


## And it is effective: no file under docs/ carries a Godot import sidecar.
##
## A `.import` next to a docs file means the engine treated it as a resource at some point —
## either before the marker existed or because the marker stopped working. On a clone without
## the local reference libraries this walks only Markdown, which is why the walk itself is
## asserted to have visited real files, and why the detection rule is proven separately below.
func test_nothing_under_docs_carries_a_godot_import_sidecar() -> void:
	var files := _files_under(DOCS_ROOT)
	assert_true(files.size() >= 30,
		"the walk visited the docs tree (%d files) — a broken walk would pass vacuously"
			% files.size())
	assert_eq(_import_sidecars(files), [],
		"no file under docs/ has been imported by Godot (reference material is not a resource)")


## The detection rule is not vacuous: the exact sidecars that shipped are reported.
func test_an_import_sidecar_is_detected() -> void:
	var planted := [
		"res://docs/ROADMAP.md",
		"res://docs/design_refs/aetheria_xianxia/AETHERIA_MOODBOARD_01.png",
		"res://docs/design_refs/aetheria_xianxia/AETHERIA_MOODBOARD_01.png.import",
		"res://docs/design_refs/aetheria_xianxia/08_vfx/08_vfx_reference.png.import",
	]
	assert_eq(_import_sidecars(planted), [planted[2], planted[3]],
		"both planted sidecars are reported, and the plain files beside them are not")


func _import_sidecars(paths: Array) -> Array:
	var found := []
	for path in paths:
		if String(path).ends_with(".import"):
			found.append(path)
	return found


## Every file under `root`, recursively. DirAccess reads the real directory, which `.gdignore`
## does not hide — it only stops the IMPORTER — so this sees exactly what is on disk.
func _files_under(root: String) -> Array:
	var out := []
	var pending: Array[String] = [root]
	while not pending.is_empty():
		var dir_path: String = pending.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			var full := "%s/%s" % [dir_path, entry]
			if dir.current_is_dir():
				pending.append(full)
			else:
				out.append(full)
			entry = dir.get_next()
		dir.list_dir_end()
	return out
