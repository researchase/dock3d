shader_type spatial;
render_mode shadow_to_opacity, depth_draw_never, specular_disabled, cull_disabled;

// Invisible ground: only the cubes' soft shadows show, falling onto the desktop behind.
void fragment() {
	ALBEDO = vec3(0.10, 0.07, 0.04);
}
