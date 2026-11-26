extends GutTest
## Modelos 3D de los objetos y texturas procedurales (ADR 041).


func test_every_catalog_object_has_a_model() -> void:
	var models: ObjectModels = ObjectModels.load_default()
	assert_eq(models.error, "")
	var cat: ObjectCatalog = ObjectCatalog.load_default()
	for id: String in cat.ids:
		assert_true(models.has(id), "modelo de " + id)
	for id: String in models.ids():
		assert_true(cat.has(id), "el modelo %s es de un objeto del catálogo" % id)
		for s: LookCatalog.Shape in models.shapes(id):
			assert_ne(models.color_of(s.mat), Color.MAGENTA, "%s: material %s" % [id, s.mat])


func test_level_details_use_the_models() -> void:
	var d: MapDocument = MapDocument.create("square", 6, 6)
	d.level(0).fill_terrain(Terrain.FLOOR)
	var cat: ObjectCatalog = ObjectCatalog.load_default()
	var o: MapObject = cat.instantiate(cat.entry("barrel"), d.allocate_id(), Vector2i(2, 2), 0, "")
	assert_true(d.level(0).add_object(o))
	var opts: MapMeshBuilder.Options = MapMeshBuilder.Options.new()
	var root: Node3D = MapMeshBuilder.build_level(d, 0, opts)
	var details: MeshInstance3D = root.get_node("Details") as MeshInstance3D
	assert_not_null(details)
	var am: ArrayMesh = details.mesh as ArrayMesh
	var verts: int = am.surface_get_array_len(0)
	assert_gt(verts, 36 * 3, "más que una caja (36 vértices)")
	var aabb: AABB = details.mesh.get_aabb()
	assert_almost_eq(aabb.end.y, 0.9, 0.05, "la altura del barril")
	assert_almost_eq(aabb.get_center().x, d.grid.cell_to_pixel(Vector2i(2, 2), opts.cell_m).x, 0.05, "en su casilla")
	# Girado, la mesa larga cambia de eje.
	var t: MapObject = cat.instantiate(cat.entry("table_long"), d.allocate_id(), Vector2i(0, 4), 1, "")
	d.level(0).remove_object(o.id)
	assert_true(d.level(0).add_object(t))
	root.free()
	root = MapMeshBuilder.build_level(d, 0, opts)
	var box: AABB = (root.get_node("Details") as MeshInstance3D).mesh.get_aabb()
	assert_gt(box.size.z, box.size.x, "mirando al este, la mesa va de norte a sur")
	# Cada grupo con su patrón de textura.
	var floor_mat: ShaderMaterial = (root.get_node("Floor") as MeshInstance3D).mesh.surface_get_material(0)
	var pattern: int = floor_mat.get_shader_parameter("pattern")
	assert_eq(pattern, MapMeshBuilder.PATTERN_FLOOR)
	var cell_m: float = floor_mat.get_shader_parameter("cell_m")
	assert_almost_eq(cell_m, opts.cell_m, 0.001)
	root.free()
