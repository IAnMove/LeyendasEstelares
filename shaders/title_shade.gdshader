shader_type canvas_item;
// Legibility layer for the cover, independent of illustration versions.
void fragment() {
	float shade = mix(0.91, 0.05, smoothstep(0.32, 0.77, UV.x));
	shade += 0.2 * smoothstep(0.86, 1.0, UV.y);
	COLOR = vec4(vec3(0.025, 0.08, 0.10), clamp(shade, 0.0, 1.0));
}
