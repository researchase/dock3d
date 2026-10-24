shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float brightness = 1.0;
uniform float reflection = 0.0;   // 1 = mirror image lying on the glass shelf
uniform float seed = 0.0;         // unused here; shared interface with the watercolor shader
uniform float wet = 0.0;          // used as hover highlight

void fragment() {
	vec2 uv = UV;
	float fade = 1.0;
	if (reflection > 0.5) {
		uv.y = 1.0 - UV.y;
		fade = (1.0 - smoothstep(0.0, 0.75, UV.y)) * 0.35;
	}
	vec4 c = texture(tex, uv);
	ALBEDO = c.rgb * (brightness + wet * 0.08);
	ALPHA = c.a * fade;
}
