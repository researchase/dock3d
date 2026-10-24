// Shared watercolor helpers: value noise + fbm for paper grain and ragged edges.
float wc_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float wc_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(wc_hash(i), wc_hash(i + vec2(1, 0)), u.x),
			   mix(wc_hash(i + vec2(0, 1)), wc_hash(i + vec2(1, 1)), u.x), u.y);
}

float wc_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * wc_noise(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		a *= 0.5;
	}
	return v;
}

// cold-press paper: fine grain + larger soft mottling
float wc_paper(vec2 p) {
	return 0.82 + 0.12 * wc_fbm(p * 18.0) + 0.06 * wc_fbm(p * 3.0);
}
