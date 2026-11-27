// Pixel art (ADR 047): la vista 3D a baja resolución, con pocos tonos por
// canal para que se parezca a una paleta limitada.
shader_type canvas_item;

uniform float levels = 14.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	COLOR = vec4(floor(c.rgb * levels + 0.5) / levels, c.a);
}
