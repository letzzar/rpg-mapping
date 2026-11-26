class_name TokenPainter
extends RefCounted
## Dibujo 2D de una ficha con personaje (PROYECTO §10.2, ADR 034): retrato
## recortado en círculo o, sin retrato, silueta de su complexión con los
## colores de su aspecto; aro del color del bando. Lo usan la vista 2D y la
## vista previa del diseñador de personajes.

const BG: Color = Color("efe4c8")
const RIM: Color = Color("f7dc8e")


## `portrait`: textura del retrato (null = silueta). `side_col.a` se aplica a
## todo (ficha arrastrada, semitransparente).
static func draw(ci: CanvasItem, sheet: CharacterSheet, center: Vector2, radius: float, side_col: Color, portrait: Texture2D) -> void:
	var inner: float = radius * 0.84
	var alpha: float = side_col.a
	if portrait != null:
		var pts: PackedVector2Array = PackedVector2Array()
		var uvs: PackedVector2Array = PackedVector2Array()
		for k: int in 32:
			var dir: Vector2 = Vector2.from_angle(TAU * k / 32.0)
			pts.append(center + dir * inner)
			uvs.append(Vector2(0.5, 0.5) + dir * 0.5)
		ci.draw_colored_polygon(pts, Color(1, 1, 1, alpha), uvs, portrait)
	else:
		ci.draw_circle(center, inner, Color(BG, alpha))
		draw_silhouette(ci, sheet.look, center, inner, alpha)
	ci.draw_arc(center, radius - (radius - inner) * 0.5, 0.0, TAU, 40, side_col, radius - inner)
	ci.draw_arc(center, radius, 0.0, TAU, 40, Color(RIM, alpha), maxf(1.0, radius * 0.06))


## Silueta sencilla vista de frente, dentro del círculo de radio `r`.
static func draw_silhouette(ci: CanvasItem, look: CharacterLook, c: Vector2, r: float, alpha: float) -> void:
	var cat: LookCatalog = LookCatalog.load_default()
	var b: LookCatalog.Body = cat.body(look.body)
	var family: String = b.family if b != null else "humanoid"
	var skin: Color = Color(cat.color_of(look, "skin"), alpha)
	var cloth: Color = Color(cat.color_of(look, "cloth"), alpha)
	var hair: Color = Color(cat.color_of(look, "hair"), alpha)
	match family:
		"quadruped":
			ci.draw_rect(Rect2(c + Vector2(-0.6, -0.05) * r, Vector2(1.0, 0.4) * r), skin)
			ci.draw_circle(c + Vector2(0.45, -0.2) * r, 0.25 * r, skin)
			for x: float in [-0.5, -0.25, 0.1, 0.3]:
				ci.draw_rect(Rect2(c + Vector2(x, 0.3) * r, Vector2(0.12, 0.35) * r), skin)
		"flyer":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.85, -0.2) * r, c + Vector2(0, 0.05) * r,
				c + Vector2(0.85, -0.2) * r, c + Vector2(0, 0.35) * r]), hair)
			ci.draw_circle(c + Vector2(0, 0.1) * r, 0.28 * r, skin)
			ci.draw_circle(c + Vector2(0, -0.25) * r, 0.2 * r, skin)
		_:
			var w: float = b.width if b != null else 1.0
			# Hombros: elipse bajo la cabeza recortada al círculo de la ficha.
			var sh: PackedVector2Array = PackedVector2Array()
			for k: int in 24:
				var p: Vector2 = Vector2(0, 0.8) + Vector2.from_angle(TAU * k / 24.0) * Vector2(0.62 * w, 0.55)
				if p.length() > 0.98:
					p = p.normalized() * 0.98
				sh.append(c + p * r)
			ci.draw_colored_polygon(sh, cloth)
			ci.draw_circle(c + Vector2(0, -0.2) * r, 0.33 * r, skin)
			ci.draw_arc(c + Vector2(0, -0.22) * r, 0.33 * r, PI * 1.05, TAU * 0.98, 16, hair, 0.14 * r)
