shader_type canvas_item;
// 2D twin of pixel_sprite.gdshader: draws a palette-indexed SpriteSheetData (v2) frame.
// Use on a Sprite2D with region_enabled and texture_filter = nearest. Index 0 = transparent.

uniform sampler2D palette_tex : source_color, filter_nearest, repeat_disable;
uniform int variant = 0;
uniform int variants = 1;
// Multiplies the palette colour (moonlight grade for the title backdrop).
uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	int idx = int(round(texture(TEXTURE, UV).r * 255.0));
	vec4 c = texelFetch(palette_tex, ivec2(idx, clamp(variant, 0, variants - 1)), 0);
	COLOR = idx == 0 ? vec4(0.0) : vec4(c.rgb * tint.rgb, c.a * tint.a);
}
