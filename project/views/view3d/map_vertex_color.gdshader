// Material de la vista 3D (ADR 025): sin luces, color por vértice (en sRGB,
// con la niebla y la luz del modelo ya horneadas) y oscurecimiento por
// distancia a la cámara para dar profundidad en 1ª persona. Funciona igual en
// Forward+ y en Compatibility (WebGL 2).
//
// Texturas procedurales (ADR 041), sin ficheros de imagen: se calculan con la
// posición en el mundo y modulan el color del vértice (no lo sustituyen, así
// la niebla y la luz horneadas siguen valiendo).
// - pattern 1 (suelo): losas de una casilla con junta y tono propio; si el
//   color es verde, hierba; si es azul, agua con ondas.
// - pattern 2 (paredes): hiladas de piedra en las caras verticales.
// - pattern 3 (muebles y detalles): veta de madera en los colores pardos.
shader_type spatial;
render_mode unshaded, cull_disabled;

// Distancia (m) a la que empieza y termina el oscurecimiento. Con
// fade_end <= fade_start no se oscurece (vista cenital).
uniform float fade_start = 0.0;
uniform float fade_end = 0.0;
uniform vec3 fade_color : source_color = vec3(0.17, 0.11, 0.08);
uniform int pattern = 0;
// Lado de la casilla en metros (losas alineadas con la rejilla).
uniform float cell_m = 1.5;
// 0 = sin texturas (colores lisos, como antes).
uniform float texture_strength = 1.0;

varying float view_dist;
varying vec3 world_pos;
varying vec3 world_normal;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	view_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Losas: tono por losa, junta oscura y grano fino.
float flagstone(vec2 p) {
	vec2 cell = p / cell_m;
	vec2 id = floor(cell);
	vec2 f = fract(cell);
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float grout = smoothstep(0.0, 0.035, edge);
	float tone = 0.9 + 0.14 * hash12(id);
	float grain = 0.94 + 0.08 * vnoise(p * 9.0);
	return tone * grain * mix(0.62, 1.0, grout);
}

// Hiladas de piedra: filas de 0,3 m con juntas verticales al tresbolillo.
float bricks(vec3 p, vec3 n) {
	float along = abs(n.x) > abs(n.z) ? p.z : p.x;
	float row = floor(p.y / 0.3);
	float u = along / 0.55 + (mod(row, 2.0) * 0.5);
	float fu = fract(u);
	float fv = fract(p.y / 0.3);
	float edge = min(min(fu, 1.0 - fu) * 0.55 / 0.3, min(fv, 1.0 - fv));
	float mortar = smoothstep(0.0, 0.06, edge);
	float tone = 0.88 + 0.14 * hash12(vec2(floor(u), row));
	return tone * mix(0.7, 1.0, mortar) * (0.95 + 0.07 * vnoise(vec2(along, p.y) * 8.0));
}

void fragment() {
	// Los colores de vértice se escriben en sRGB: se pasan a lineal.
	vec3 base = COLOR.rgb;
	float k_tex = 1.0;
	bool green = base.g > base.r * 1.08 && base.g > base.b * 1.08;
	bool blue = base.b > base.r * 1.15 && base.b > base.g * 1.02;
	// Pardo marcado (madera: puertas y muebles, r/g ≈ 1,45). La piedra de las
	// paredes (#8f7b62, r/g ≈ 1,16) es más gris y lleva hiladas.
	bool brown = base.r > base.g * 1.3 && base.g > base.b * 1.15;
	if (pattern == 1 && world_normal.y > 0.5) {
		if (blue) {
			k_tex = 0.92 + 0.1 * sin(world_pos.x * 3.1 + vnoise(world_pos.xz * 1.7) * 6.0);
		} else if (green) {
			k_tex = 0.85 + 0.25 * vnoise(world_pos.xz * 6.0) * vnoise(world_pos.xz * 1.3);
		} else {
			k_tex = flagstone(world_pos.xz);
		}
	} else if (pattern == 2 && abs(world_normal.y) < 0.5 && !brown && !blue) {
		k_tex = bricks(world_pos, world_normal);
	} else if (pattern == 2 && brown) {
		k_tex = 0.94 + 0.06 * sin(world_pos.y * 40.0 + vnoise(world_pos.xz * 5.0) * 5.0);
	} else if (pattern == 3) {
		if (brown) {
			float ring = sin((world_pos.x + world_pos.z) * 18.0 + vnoise(world_pos.xz * 4.0 + world_pos.y) * 7.0);
			k_tex = 0.93 + 0.07 * ring;
		}
	}
	base *= mix(1.0, k_tex, texture_strength);
	vec3 c = pow(base, vec3(2.2));
	if (fade_end > fade_start) {
		float k = clamp((view_dist - fade_start) / (fade_end - fade_start), 0.0, 1.0);
		c = mix(c, fade_color, k);
	}
	ALBEDO = c;
}
