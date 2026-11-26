class_name PartyVision
extends RefCounted
## Lo que ve el grupo de jugadores en un nivel (ADR 024): fichas de bando
## "player" y "ally" no ocultas como observadores, luces de los objetos y, si
## se pide, la luz que lleva cada ficha. La usan las tres vistas (niebla
## coherente entre 2D, 3D y 1ª persona) y la UI para explorar al mover.

const VIEWER_PARTY: String = "party"
const SIDES_IN_PARTY: PackedStringArray = ["player", "ally"]
## Id del sentido (en los perfiles y en CharacterSheet.senses) que deja ver
## en la oscuridad como en penumbra (ADR 034).
const SENSE_DARKVISION: String = "darkvision"


class Options:
	extends RefCounted
	## Todo el nivel iluminado (sala con luz natural, o el DM lo decide).
	var ambient_lit: bool = false
	## Luz que lleva cada ficha del grupo (casillas; 0 = ninguna).
	var carried_bright: int = 0
	var carried_dim: int = 0
	var range_cells: int = Visibility.DEFAULT_RANGE
	var darkvision_cells: int = 0


class Result:
	extends RefCounted
	## Visibility.DARK/DIM/BRIGHT por casilla.
	var light: PackedByteArray = PackedByteArray()
	## 0 = no visible; DIM/BRIGHT = visible con esa luz.
	var visible: PackedByteArray = PackedByteArray()
	var viewer_count: int = 0


static func party_tokens(doc: MapDocument, level_index: int) -> Array[MapToken]:
	var out: Array[MapToken] = []
	for t: MapToken in doc.tokens:
		if t.level == level_index and not t.hidden and SIDES_IN_PARTY.has(t.side):
			out.append(t)
	return out


## Casillas de visión en la oscuridad del personaje de la ficha (sentido
## SENSE_DARKVISION de su hoja, en pies → casillas hacia abajo); 0 sin él.
static func darkvision_cells_of(t: MapToken, profile: SystemProfile) -> int:
	if t.sheet == null or profile == null or profile.cell_ft <= 0 or not t.sheet.senses.has(SENSE_DARKVISION):
		return 0
	return t.sheet.senses[SENSE_DARKVISION] / profile.cell_ft


static func compute(doc: MapDocument, level_index: int, profile: SystemProfile, opts: Options) -> Result:
	var r: Result = Result.new()
	var lvl: MapLevel = doc.level(level_index)
	if lvl == null:
		return r
	var lights: Array[Visibility.LightSource] = Visibility.object_lights(lvl)
	var viewers: Array[Visibility.Viewer] = []
	for t: MapToken in party_tokens(doc, level_index):
		var v: Visibility.Viewer = Visibility.Viewer.new()
		v.cells = doc.token_cells(t, profile) if profile != null else [t.cell]
		v.range_cells = opts.range_cells
		v.darkvision_cells = maxi(opts.darkvision_cells, darkvision_cells_of(t, profile))
		viewers.append(v)
		if opts.carried_dim > 0:
			lights.append(Visibility.LightSource.make(t.cell, opts.carried_bright, opts.carried_dim))
	r.viewer_count = viewers.size()
	r.light = Visibility.light_map(lvl, lights, opts.ambient_lit)
	r.visible = Visibility.visible_map(lvl, viewers, r.light)
	return r
