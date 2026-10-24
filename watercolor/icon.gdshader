shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
#include "res://watercolor/watercolor.gdshaderinc"

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float brightness = 1.0;
uniform float reflection = 0.0;   // 1 = reflection lying on the shelf
uniform float seed = 0.0;         // per-icon variation
uniform float wet = 0.0;          // 0..1, extra bleed while hovered

void fragment() {
	vec2 uv = UV;
	float fade = 1.0;
	if (reflection > 0.5) {
		uv.y = 1.0 - UV.y;
		fade = (1.0 - smoothstep(0.0, 0.8, UV.y)) * 0.38;
	}
	vec2 np = uv * 4.0 + seed * 7.13 + TIME * 0.03;

	// pigment wobble: hand-painted shapes never follow the line exactly
	vec2 warp = (vec2(wc_fbm(np), wc_fbm(np + 5.2)) - 0.5) * (0.035 + 0.025 * wet);
	vec2 wuv = uv + warp;

	vec4 sharp = texture(tex, wuv);
	vec4 soft = textureLod(tex, wuv, 3.5 + wet);   // bled pigment
	vec4 wide = textureLod(tex, wuv, 5.0);

	// pigment spreads into wet paper: blend toward the blurred version
	vec3 col = mix(sharp.rgb, soft.rgb, 0.45);
	// watercolor is translucent and a little desaturated
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(lum), col, 0.85);
	col = mix(col, vec3(1.0), 0.12);

	// ragged, blooming silhouette
	float edge_n = wc_fbm(uv * 9.0 + seed * 3.1);
	float a_src = mix(sharp.a, soft.a, 0.6);
	float alpha = smoothstep(0.25 + 0.3 * edge_n, 0.55 + 0.3 * edge_n, a_src);

	// pigment pools and darkens at the rim and at colour boundaries
	float rim = clamp(alpha - wide.a * 0.9, 0.0, 1.0) + (1.0 - smoothstep(0.0, 0.25, alpha - 0.05)) * alpha;
	float inner = clamp(length(sharp.rgb - wide.rgb) * 1.4, 0.0, 1.0);
	col *= 1.0 - 0.45 * clamp(rim * 1.6 + inner * 0.5, 0.0, 1.0);

	// granulation + paper grain
	float paper = wc_paper(uv * 1.3 + seed);
	col *= paper;
	alpha *= mix(0.78, 1.0, wc_fbm(uv * 30.0 + seed));

	// faint halo of pigment that wicked out into the paper
	vec3 halo_col = soft.rgb / max(soft.a, 0.05);
	halo_col = mix(halo_col, vec3(1.0), 0.25) * paper;
	float border = smoothstep(0.0, 0.14, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)));
	float halo = soft.a * border * 0.3 * smoothstep(0.3, 0.7, wc_fbm(uv * 6.0 + seed + 11.0)) * (1.0 + wet);
	float body = alpha * sharp.a * 0.35 + alpha * 0.65;
	float a_out = body + halo * (1.0 - body);
	vec3 c_out = (col * body + halo_col * halo * (1.0 - body)) / max(a_out, 0.001);

	ALBEDO = c_out * brightness;
	ALPHA = a_out * fade * 0.95;
}
