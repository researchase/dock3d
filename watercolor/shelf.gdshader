shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, blend_mix;
#include "res://watercolor/watercolor.gdshaderinc"

uniform float width = 10.0;   // world width, so brush texture never stretches
uniform float depth = 1.7;

varying vec3 wn;
varying vec3 lp;

void vertex() {
	wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	lp = VERTEX;
}

void fragment() {
	vec3 n = normalize(wn);
	float zn = lp.z / depth;                   // -0.5 (back) .. 0.5 (front)
	vec2 p = vec2(lp.x * width, lp.z);   // roughly world units
	// two overlapping washes: indigo at the back, warm rose toward the front
	vec3 indigo = vec3(0.32, 0.40, 0.68);
	vec3 rose = vec3(0.86, 0.55, 0.62);
	vec3 teal = vec3(0.36, 0.66, 0.70);
	float t = clamp(zn + 0.5 + (wc_fbm(p * 0.6) - 0.5) * 0.7, 0.0, 1.0);
	float drift = wc_fbm(p * 0.25 + 3.0);
	vec3 col = mix(mix(indigo, teal, drift), rose, smoothstep(0.35, 0.95, t));

	// brush-stroke silhouette: ragged ends and a wavy back edge
	float u = (lp.x + 0.5);                       // 0..1 along the shelf
	float ends = min(u, 1.0 - u) * width;          // distance from the ends in world units
	float ragged = wc_fbm(vec2(lp.x * width * 1.5, zn * 4.0));
	float mask = smoothstep(0.0, 0.6, ends - ragged * 0.9);
	float back = smoothstep(0.0, 0.3, zn + 0.5 - ragged * 0.3);

	float a;
	if (n.y > 0.5) {
		a = 0.78 * mask * back;
		// pigment pooling where the wash dried: darker rim near edges
		float rim = 1.0 - smoothstep(0.0, 0.25, min(ends - ragged * 0.9, (zn + 0.5 - ragged * 0.3) * 3.0));
		col *= 1.0 - 0.35 * rim;
	} else if (n.z > 0.5) {
		// front face: deeper, more saturated stroke
		col = mix(col, vec3(0.45, 0.25, 0.42), 0.45);
		a = 0.78 * mask;
		float drip = wc_fbm(vec2(lp.x * width * 2.0, 0.0));
		a *= smoothstep(-0.5 - drip * 0.6, 0.2, lp.y / 0.1 * 0.5);
	} else {
		a = 0.0;
	}
	col *= wc_paper(p * 0.35);
	a *= mix(0.7, 1.0, wc_fbm(p * 6.0));
	ALBEDO = col;
	ALPHA = a;
}
