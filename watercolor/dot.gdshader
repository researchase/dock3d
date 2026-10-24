shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
#include "res://watercolor/watercolor.gdshaderinc"

uniform vec4 color : source_color = vec4(0.18, 0.22, 0.45, 1.0);
uniform float strength = 0.0;
uniform float seed = 0.0;

void fragment() {
	// a little ink blot with a darker dried rim
	vec2 c = UV - vec2(0.5);
	float ang = atan(c.y, c.x);
	float r = length(c) * 2.0 + (wc_noise(vec2(ang * 1.6 + seed, seed)) - 0.5) * 0.35;
	float body = 1.0 - smoothstep(0.42, 0.55, r);
	float rim = smoothstep(0.25, 0.5, r) * body;
	ALBEDO = color.rgb * (1.0 - 0.4 * rim) * wc_paper(UV + seed);
	ALPHA = body * (0.55 + 0.4 * rim) * strength;
}
