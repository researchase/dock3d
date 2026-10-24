shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
#include "res://watercolor/watercolor.gdshaderinc"

uniform float width = 10.0;

varying vec3 lp;
void vertex() { lp = VERTEX; }

void fragment() {
	// a dry-brush line along the front edge of the shelf
	float x = lp.x * width;
	float u = lp.x + 0.5;
	float ends = min(u, 1.0 - u) * width;
	float skip = smoothstep(0.35, 0.55, wc_fbm(vec2(x * 2.5, 1.0)));
	ALBEDO = vec3(0.28, 0.16, 0.30) * wc_paper(vec2(x, 0.0));
	ALPHA = 0.7 * skip * smoothstep(0.0, 0.8, ends - wc_noise(vec2(x * 3.0, 0.0)));
}
