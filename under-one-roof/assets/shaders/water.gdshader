shader_type canvas_item;
// Gentle animated shimmer on the sea, river and pond (water_mask.png marks water pixels).

uniform sampler2D water_mask : filter_nearest;

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	float m = texture(water_mask, UV).r;
	if (m > 0.5) {
		vec2 px = floor(UV / TEXTURE_PIXEL_SIZE);
		float wave = sin(px.x * 0.16 + TIME * 1.3 + sin(px.y * 0.11 + TIME * 0.4) * 2.5);
		float band = sin(px.y * 0.85 + TIME * 0.9 + px.x * 0.02);
		float glint = step(0.96, wave * band);
		col.rgb += glint * vec3(0.20, 0.22, 0.20);
		col.rgb *= 0.985 + 0.03 * sin(TIME * 0.7 + px.x * 0.013 + px.y * 0.021);
	}
	COLOR = col;
}
