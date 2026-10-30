shader_type canvas_item;
// Ground chunks: alpha < 1 marks water (sea, river, pond). The water shimmers with
// soft travelling glints computed in world space, so chunk seams never show.

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	float m = 1.0 - smoothstep(0.72, 0.9, col.a);
	if (m > 0.01) {
		vec2 px = world;
		float wave = sin(px.x * 0.08 + TIME * 1.3 + sin(px.y * 0.055 + TIME * 0.4) * 2.5);
		float band = sin(px.y * 0.42 + TIME * 0.9 + px.x * 0.01);
		float glint = smoothstep(0.9, 1.0, wave * band);
		vec3 lit = col.rgb + glint * vec3(0.16, 0.18, 0.17);
		lit *= 0.985 + 0.03 * sin(TIME * 0.7 + px.x * 0.007 + px.y * 0.011);
		col.rgb = mix(col.rgb, lit, m);
	}
	COLOR = vec4(col.rgb, 1.0);
}
