shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec4 color : source_color = vec4(0.6, 0.88, 1.0, 1.0);
uniform float strength = 0.0;
uniform float seed = 0.0;

void fragment() {
	// small glowing "app is running" light
	float d = length(UV - vec2(0.5)) * 2.0;
	float core = 1.0 - smoothstep(0.12, 0.3, d);
	float glow = pow(max(1.0 - d, 0.0), 2.5) * 0.7;
	ALBEDO = mix(color.rgb, vec3(1.0), core * 0.7);
	ALPHA = clamp(core + glow, 0.0, 1.0) * strength;
}
