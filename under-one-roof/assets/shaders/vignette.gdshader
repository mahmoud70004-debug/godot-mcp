shader_type canvas_item;
// Soft vignette: darkens and cools the corners a little so the scene has depth.

void fragment() {
	vec2 d = (SCREEN_UV - vec2(0.5)) * vec2(1.25, 1.0);
	float v = smoothstep(0.38, 0.85, length(d));
	COLOR = vec4(0.03, 0.04, 0.08, v * 0.42);
}
