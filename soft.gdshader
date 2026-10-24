shader_type canvas_item;

// The parent folder's wall, rendered on its own and shown softly out of focus behind the current one.
uniform float radius = 2.4;

void fragment() {
	vec3 rgb = vec3(0.0);
	float a = 0.0;
	float w = 0.0;
	for (int x = -3; x <= 3; x++) {
		for (int y = -3; y <= 3; y++) {
			float k = exp(-float(x * x + y * y) / 8.0);
			vec4 c = texture(TEXTURE, UV + vec2(float(x), float(y)) * TEXTURE_PIXEL_SIZE * radius);
			rgb += c.rgb * c.a * k;   // premultiplied, so transparent edges don't darken
			a += c.a * k;
			w += k;
		}
	}
	COLOR = vec4(rgb / max(a, 1e-4), a / w);
}
