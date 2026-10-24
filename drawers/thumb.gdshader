shader_type spatial;
render_mode depth_prepass_alpha, cull_back;

// photo / video frame printed on the drawer front: cover-fit with rounded corners
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec2 quad_size = vec2(0.84, 0.5);
uniform float tex_aspect = 1.0;
uniform float radius = 0.06;
uniform float has_tex = 0.0;
uniform float dim = 0.0;
uniform float fade = 1.0;
uniform vec4 placeholder : source_color = vec4(0.91, 0.87, 0.80, 1.0);

void fragment() {
	vec2 uv = UV;
	float qa = quad_size.x / quad_size.y;
	if (tex_aspect > qa) {
		uv.x = 0.5 + (uv.x - 0.5) * qa / tex_aspect;
	} else {
		uv.y = 0.5 + (uv.y - 0.5) * tex_aspect / qa;
	}
	vec3 c = mix(placeholder.rgb, texture(tex, uv).rgb, has_tex);
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), dim * 0.45) * (1.0 - dim * 0.2);
	vec2 p = (UV - 0.5) * quad_size;
	vec2 q = abs(p) - (quad_size * 0.5 - radius);
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
	ALBEDO = c;
	ROUGHNESS = 0.5;
	SPECULAR = 0.35;
	ALPHA = (1.0 - smoothstep(-0.004, 0.0, d)) * fade;
}
