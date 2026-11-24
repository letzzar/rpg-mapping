// Material de la vista 3D (ADR 025): sin luces, color por vértice (en sRGB,
// con la niebla y la luz del modelo ya horneadas) y oscurecimiento por
// distancia a la cámara para dar profundidad en 1ª persona. Funciona igual en
// Forward+ y en Compatibility (WebGL 2).
shader_type spatial;
render_mode unshaded, cull_disabled;

// Distancia (m) a la que empieza y termina el oscurecimiento. Con
// fade_end <= fade_start no se oscurece (vista cenital).
uniform float fade_start = 0.0;
uniform float fade_end = 0.0;
uniform vec3 fade_color : source_color = vec3(0.17, 0.11, 0.08);

varying float view_dist;

void vertex() {
	view_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	// Los colores de vértice se escriben en sRGB: se pasan a lineal.
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	if (fade_end > fade_start) {
		float k = clamp((view_dist - fade_start) / (fade_end - fade_start), 0.0, 1.0);
		c = mix(c, fade_color, k);
	}
	ALBEDO = c;
}
