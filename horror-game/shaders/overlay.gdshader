shader_type canvas_item;
// Full-screen horror post effect: film grain, heavy vignette, fear pulse,
// chromatic aberration + scanline glitch, red flash and fade.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float fear : hint_range(0.0, 1.0) = 0.0;
uniform float glitch : hint_range(0.0, 1.0) = 0.0;
uniform float red_flash : hint_range(0.0, 1.0) = 0.0;
uniform float fade : hint_range(0.0, 1.0) = 0.0;
uniform float grain : hint_range(0.0, 1.0) = 0.09;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME;
	// glitch: horizontal tearing bands
	float band = step(1.0 - glitch * 0.35, hash(vec2(floor(uv.y * 40.0), floor(t * 18.0))));
	uv.x += band * (hash(vec2(t, uv.y)) - 0.5) * 0.12 * glitch;
	// fear warps the edges like a heartbeat
	vec2 c = uv - 0.5;
	float beat = pow(abs(sin(t * (2.0 + fear * 3.0))), 8.0) * fear;
	uv -= c * beat * 0.025;
	float ab = 0.002 + glitch * 0.02 + beat * 0.006;
	vec3 col;
	col.r = texture(screen_tex, uv + vec2(ab, 0.0)).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - vec2(ab, 0.0)).b;
	// desaturate slightly + cold-green tint
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(l) * vec3(0.92, 1.0, 0.95), 0.35);
	// grain
	float n = hash(uv * vec2(1024.0, 1024.0) + fract(t * 7.0) * 100.0);
	col += (n - 0.5) * (grain + glitch * 0.3);
	// scanlines during glitch
	col *= 1.0 - glitch * 0.25 * step(0.5, fract(SCREEN_UV.y * 320.0));
	// vignette (portrait screen: stronger at top/bottom)
	vec2 vc = (SCREEN_UV - 0.5) * vec2(1.0, 0.75);
	float vig = smoothstep(0.75, 0.22 - fear * 0.08, length(vc) * (1.15 + fear * 0.35));
	col *= vig;
	// red tint with fear + red flash
	col = mix(col, col * vec3(1.4, 0.55, 0.5), fear * 0.35 + beat * 0.3);
	col = mix(col, vec3(0.6, 0.0, 0.0), red_flash * 0.75);
	col = mix(col, vec3(0.0), fade);
	COLOR = vec4(col, 1.0);
}
