shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, blend_mix;

uniform float width = 10.0;
uniform float depth = 2.2;

varying vec3 wn;
varying vec3 lp;

void vertex() {
	wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	lp = VERTEX;
}

void fragment() {
	vec3 n = normalize(wn);
	float zn = lp.z / depth + 0.5;      // 0 back .. 1 front
	float u = lp.x + 0.5;               // 0..1 along the shelf
	// soft rounded ends
	float ends = smoothstep(0.0, 0.25, min(u, 1.0 - u) * width);
	vec3 col;
	float a;
	if (n.y > 0.5) {
		// frosted glass: darker smoky back, bright toward the front lip
		col = mix(vec3(0.45, 0.50, 0.60), vec3(0.93, 0.96, 1.0), smoothstep(0.0, 1.0, zn));
		a = mix(0.30, 0.55, zn);
		// faint specular streak across the glass
		a += 0.10 * exp(-pow((zn - 0.78) * 9.0, 2.0));
	} else if (n.z > 0.5) {
		col = vec3(0.97, 0.98, 1.0);
		a = 0.75;
	} else {
		col = vec3(0.85, 0.9, 1.0);
		a = 0.2;
	}
	ALBEDO = col;
	ALPHA = a * ends;
}
