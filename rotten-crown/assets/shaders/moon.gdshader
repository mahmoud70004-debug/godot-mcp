// Pixelated billboard moon that ignores fog, bright enough to bloom.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, shadows_disabled;

uniform vec4 moon_color : source_color = vec4(0.86, 0.88, 0.7, 1.0);
uniform float brightness = 2.0;
uniform float pixel_size = 28.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743);
}

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 cell = floor(UV * pixel_size);
	vec2 uv = (cell + 0.5) / pixel_size - 0.5;
	float d = length(uv) * 2.0;
	if (d > 1.0) {
		discard;
	}
	float crater = step(0.82, hash(floor(cell / 3.0))) * 0.3;
	float rim = smoothstep(0.7, 1.0, d) * 0.25;
	ALBEDO = moon_color.rgb * brightness * (1.0 - crater - rim);
}
