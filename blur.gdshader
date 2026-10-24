shader_type canvas_item;

// The desktop picture behind the open drawers: blurred (mip levels + a few taps) and dimmed a touch.
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.10, 0.08, 0.06, 1.0);

void fragment() {
	float lod = amount * 5.2;
	vec2 step = TEXTURE_PIXEL_SIZE * exp2(lod) * 0.9;
	vec3 c = vec3(0.0);
	float w = 0.0;
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			float k = exp(-float(x * x + y * y) / 4.0);
			c += textureLod(TEXTURE, UV + vec2(float(x), float(y)) * step, lod).rgb * k;
			w += k;
		}
	}
	c /= w;
	c = mix(c, tint.rgb, 0.28 * amount);
	COLOR = vec4(c, smoothstep(0.0, 0.35, amount));
}
