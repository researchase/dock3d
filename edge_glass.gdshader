shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform float width = 10.0;
varying vec3 lp;
void vertex() { lp = VERTEX; }

void fragment() {
	// crisp white highlight along the front lip
	float u = lp.x + 0.5;
	ALBEDO = vec3(1.0);
	ALPHA = 0.9 * smoothstep(0.0, 0.3, min(u, 1.0 - u) * width);
}
