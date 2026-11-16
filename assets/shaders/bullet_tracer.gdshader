shader_type spatial;
render_mode unshaded, shadows_disabled;

uniform float start_distance = 20.0;
uniform float segment_length = 1.0;
uniform float fade = 1.0;
uniform float hitscan_distance = 20.0;
uniform float fade_distance = 5.0;
varying float distance_traveled;

void vertex() {
	distance_traveled = start_distance + segment_length * 0.5 - VERTEX.z;
}

void fragment() {
	ALBEDO = vec3(1.0, 0.7, 0.35);
	EMISSION = ALBEDO * 2.0;
	ALPHA = clamp((distance_traveled - hitscan_distance) / fade_distance, 0.0, 1.0) * 0.7 * fade;
}
