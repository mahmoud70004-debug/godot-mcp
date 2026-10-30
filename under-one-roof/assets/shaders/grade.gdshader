shader_type canvas_item;
// Final look of the world (under the HUD): warm highlights, cool shadows, a touch more
// contrast and colour, a soft glow around bright light (lanterns, fire, sunlit sand)
// and a gentle vignette.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 1.0;
uniform float glow = 0.55;

vec3 grade(vec3 c) {
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, 1.12);                                   // saturation
	c = (c - 0.5) * 1.08 + 0.5;                                  // contrast
	vec3 shadows = vec3(0.92, 0.96, 1.06);                       // cool shade
	vec3 lights = vec3(1.06, 1.01, 0.92);                        // warm sun
	c *= mix(shadows, lights, smoothstep(0.15, 0.8, l));
	return c;
}

void fragment() {
	vec4 base = textureLod(screen, SCREEN_UV, 0.0);
	vec3 c = grade(base.rgb);
	// cheap bloom from a blurred mip of the screen, only where it is bright
	vec3 blur = textureLod(screen, SCREEN_UV, 2.5).rgb * 0.5 + textureLod(screen, SCREEN_UV, 4.0).rgb * 0.5;
	float bl = dot(blur, vec3(0.299, 0.587, 0.114));
	c += blur * smoothstep(0.62, 0.95, bl) * glow;
	vec2 d = (SCREEN_UV - vec2(0.5)) * vec2(1.25, 1.0);
	float v = smoothstep(0.38, 0.85, length(d));
	c = mix(c, c * vec3(0.55, 0.58, 0.68), v * 0.55);
	COLOR = vec4(mix(base.rgb, c, strength), 1.0);
}
