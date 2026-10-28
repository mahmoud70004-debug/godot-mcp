// Hollowmere curse flesh (U8): vertex-coloured wet flesh that slowly breathes.
// Built for merged batches (HollowmereProps.Batch): no instance uniforms.
//   COLOR.rgb = albedo (sRGB), COLOR.a = how far the vertex swells with the pulse (0 = rigid,
//   so blood pools and teeth in the same batch stay still).
// The beat phase comes from the world position, so neighbouring growths throb out of step.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

uniform sampler2D grain : source_color, filter_nearest_mipmap, repeat_enable;
uniform float grain_scale = 1.6;
uniform float pulse_amount = 0.05;
uniform float pulse_speed = 1.15;
uniform float wetness : hint_range(0.0, 1.0) = 0.6;

varying vec3 albedo_lin;
varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = dot(wp, vec3(0.31, 0.17, 0.43));
	float beat = pow(max(sin(TIME * pulse_speed + phase), 0.0), 3.0) * 0.8
		+ sin(TIME * pulse_speed * 0.45 + phase * 1.3) * 0.2;
	VERTEX += NORMAL * beat * pulse_amount * COLOR.a;
	vec3 c = COLOR.rgb;
	albedo_lin = mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 w = abs(world_normal);
	vec2 uv = w.y > max(w.x, w.z) ? world_pos.xz : (w.x > w.z ? world_pos.zy : world_pos.xy);
	ALBEDO = albedo_lin * texture(grain, uv * grain_scale).rgb;
	ROUGHNESS = mix(0.9, 0.28, wetness);
	SPECULAR = 0.55;
}
