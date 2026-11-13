shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float strength : hint_range(0.0, 2.0) = 1.7;
uniform float pixel_size : hint_range(1.0, 4.0, 1.0) = 2.0;
uniform float dither_scale = 2.0;
uniform float dither_amplitude = 0.65;
uniform float color_levels = 32.0;
uniform float saturation = 0.75;
uniform vec4 tint : source_color = vec4(0.92, 1.0, 0.94, 1.0);
uniform float grain = 0.006;
uniform float grain_tick = 0.0;
uniform float disturbance = 0.0;

float noise(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233)) + grain_tick) * 43758.5453);
}

void fragment() {
	// Choose a central texel explicitly to avoid nearest-filter ties in even blocks.
	vec2 sample_pixel = floor(SCREEN_UV / SCREEN_PIXEL_SIZE / pixel_size) * pixel_size + floor(pixel_size * 0.5) + 0.5;
	vec2 sample_uv = clamp(sample_pixel * SCREEN_PIXEL_SIZE, SCREEN_PIXEL_SIZE * 0.5, vec2(1.0) - SCREEN_PIXEL_SIZE * 0.5);
	vec3 original = texture(screen_texture, sample_uv).rgb;
	float luminance = dot(original, vec3(0.2126, 0.7152, 0.0722));
	vec3 graded = mix(vec3(luminance), original, saturation) * tint.rgb;
	vec2 pixel = floor(FRAGCOORD.xy / max(dither_scale, 1.0));
	// Recursive Bayer threshold: stable texture without crawling edges.
	vec2 low = mod(pixel, 2.0);
	vec2 high = mod(floor(pixel / 2.0), 2.0);
	float bayer = (2.0 * low.x + 3.0 * low.y - 4.0 * low.x * low.y) * 4.0;
	bayer += 2.0 * high.x + 3.0 * high.y - 4.0 * high.x * high.y;
	float levels = max(color_levels - 1.0, 1.0);
	graded = floor(clamp(graded + ((bayer + 0.5) / 16.0 - 0.5) * dither_amplitude / levels, 0.0, 1.0) * levels + 0.5) / levels;
	graded += (noise(floor(FRAGCOORD.xy)) - 0.5) * grain;
	graded *= 1.0 - disturbance;
	COLOR = vec4(clamp(mix(original, clamp(graded, 0.0, 1.0), strength), 0.0, 1.0), 1.0);
}
