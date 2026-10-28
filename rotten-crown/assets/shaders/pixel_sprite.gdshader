shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_disabled;
// Palette-indexed pixel sprite (SpriteSheetData v2). Index 0 = transparent.
// Y-axis billboard identical to BILLBOARD_FIXED_Y (keeps node scale); full_billboard = BILLBOARD_ENABLED.
// Works in the Mobile and the Compatibility renderer.

uniform sampler2D index_tex : filter_nearest, repeat_disable;
uniform sampler2D palette_tex : source_color, filter_nearest, repeat_disable;
uniform int variant = 0;
uniform int variants = 1;
uniform bool full_billboard = false;

void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	mat4 bb;
	if (full_billboard) {
		bb = mat4(MAIN_CAM_INV_VIEW_MATRIX[0], MAIN_CAM_INV_VIEW_MATRIX[1], MAIN_CAM_INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	} else {
		vec3 up = normalize(MODEL_MATRIX[1].xyz);
		vec3 right = normalize(MAIN_CAM_INV_VIEW_MATRIX[0].xyz);
		vec3 fwd = normalize(cross(right, up));
		bb = mat4(vec4(right, 0.0), vec4(up, 0.0), vec4(fwd, 0.0), MODEL_MATRIX[3]);
	}
	bb = bb * mat4(vec4(sc.x, 0.0, 0.0, 0.0), vec4(0.0, sc.y, 0.0, 0.0), vec4(0.0, 0.0, sc.z, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
	MODELVIEW_NORMAL_MATRIX = mat3(VIEW_MATRIX) * mat3(bb[0].xyz / sc.x, bb[1].xyz / sc.y, bb[2].xyz / sc.z);
}

void fragment() {
	int idx = int(round(texture(index_tex, UV).r * 255.0));
	if (idx == 0) {
		discard;
	}
	vec4 c = texelFetch(palette_tex, ivec2(idx, clamp(variant, 0, variants - 1)), 0);
	ALBEDO = c.rgb * COLOR.rgb;
	ROUGHNESS = 1.0;
}
