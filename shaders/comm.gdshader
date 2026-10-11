shader_type canvas_item;
// Retrato de comunicación: líneas de barrido, temblor ocasional y tinte de la especie.
uniform vec4 tint : source_color = vec4(0.4, 0.9, 1.0, 1.0);
uniform float strength = 0.22;

void fragment() {
	vec2 uv = UV;
	float row = floor(uv.y * 32.0);
	float glitch = step(0.995, fract(sin(floor(TIME * 7.0) * 91.3 + row * 17.7) * 43758.5)) * 0.006;
	uv.x += glitch;
	vec4 c = texture(TEXTURE, uv);
	float scan = 0.86 + 0.14 * sin(uv.y * 32.0 * 6.2831 * 0.5 + TIME * 3.0);
	c.rgb = mix(c.rgb, c.rgb * tint.rgb * 1.4, strength) * scan;
	COLOR = c;
}
