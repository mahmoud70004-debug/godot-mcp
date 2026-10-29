shader_type canvas_item;
// Gentle horizontal ripple on the title-screen bay; pixel steps keep it crisp.
uniform float sea_y = 0.73;

void fragment() {
	vec2 px = floor(UV / TEXTURE_PIXEL_SIZE);
	float depth = clamp((UV.y - sea_y) / (1.0 - sea_y), 0.0, 1.0);
	float shift = floor(sin(px.y * 0.9 + TIME * 1.4) * (0.6 + depth * 1.6) + 0.5);
	vec2 uv = (px + vec2(shift, 0.0) + 0.5) * TEXTURE_PIXEL_SIZE;
	vec4 col = texture(TEXTURE, uv);
	col.rgb *= 0.96 + 0.06 * sin(TIME * 0.8 + px.x * 0.05 + px.y * 0.3);
	COLOR = col;
}
