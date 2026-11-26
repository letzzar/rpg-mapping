class_name RoomLibrary
extends RefCounted
## Biblioteca local de estancias (E3, ADR 038): un fichero por estancia en
## `user://rooms/<id corto>.rpgm-map.json` (formato MapFile, solo con los
## deltas de contenido). El id corto (RPGU1) la recupera de aquí; en otro
## equipo hace falta el código para compartir (RPGS1) o el fichero.
##
## `dir` se puede cambiar (las pruebas usan una carpeta propia).

const DEFAULT_DIR: String = "user://rooms/"

var dir: String = DEFAULT_DIR


class Entry:
	extends RefCounted
	var id: String = ""
	## Nombre de la estancia (su primera sala con nombre, o su tipo).
	var name: String = ""
	var kind: String = ""


## Clave i18n del último error de save() ("" si fue bien).
var last_error: String = ""


func _init(p_dir: String = DEFAULT_DIR) -> void:
	dir = p_dir if p_dir.ends_with("/") else p_dir + "/"


## Guarda la estancia (solo su contenido) y devuelve su id corto; "" si no
## se pudo (sin código o error de escritura; el motivo en `last_error`).
func save(doc: MapDocument) -> String:
	last_error = ""
	var content: MapFile.LoadResult = RoomContent.content_only(doc)
	if content.doc == null:
		last_error = content.error
		return ""
	var id: String = RoomContent.short_id(content.doc)
	DirAccess.make_dir_recursive_absolute(dir)
	var f: FileAccess = FileAccess.open(_path(id), FileAccess.WRITE)
	if f == null:
		last_error = "ROOM_ERR_SAVE"
		return ""
	f.store_string(MapFile.to_json(content.doc))
	f.close()
	return id


func has(id: String) -> bool:
	return FileAccess.file_exists(_path(id))


## Abre la estancia `id` (canónico). Error ROOM_ERR_NOT_IN_LIBRARY si no está.
func load_room(id: String) -> MapFile.LoadResult:
	if not has(id):
		var res: MapFile.LoadResult = MapFile.LoadResult.new()
		res.error = "ROOM_ERR_NOT_IN_LIBRARY"
		return res
	return MapFile.from_json(FileAccess.get_file_as_string(_path(id)))


## Quita la estancia de la biblioteca. true si estaba.
func remove(id: String) -> bool:
	return has(id) and DirAccess.remove_absolute(_path(id)) == OK


## Estancias guardadas, ordenadas por id.
func entries() -> Array[Entry]:
	var out: Array[Entry] = []
	# Sin la carpeta (biblioteca vacía) get_files_at da un error del motor.
	if not DirAccess.dir_exists_absolute(dir):
		return out
	var files: PackedStringArray = DirAccess.get_files_at(dir)
	files.sort()
	for f: String in files:
		if not f.ends_with(MapFile.EXTENSION):
			continue
		var e: Entry = Entry.new()
		e.id = f.trim_suffix(MapFile.EXTENSION)
		var res: MapFile.LoadResult = MapFile.from_json(FileAccess.get_file_as_string(dir + f))
		if res.doc == null:
			continue
		for r: MapRoom in res.doc.level(0).rooms:
			if r.kind != MapRoom.KIND_ENTRANCE:
				e.name = r.label
				e.kind = r.kind
				break
		out.append(e)
	return out


func _path(id: String) -> String:
	return dir + id + MapFile.EXTENSION
