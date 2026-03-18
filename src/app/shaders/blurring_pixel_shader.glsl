#version 410 core

in  vec2 uv;
out vec4 frag_color;

uniform sampler2D scene_texture;
uniform vec2      texel_size;    // vec2(1.0 / screen_width, 1.0 / screen_height)

// 13-tap separable Gaussian weights (sigma = 3).
// weights[0] is the center tap, weights[1..6] are the symmetric offsets.
const float weights[7] = float[](0.1370, 0.1296, 0.1097, 0.0831, 0.0563, 0.0342, 0.0185);

void main() {
	vec4 result = texture(scene_texture, uv) * weights[0];
	// The higher the nubmer, the more blurry, but can introduce artifacts, if you want more blur without 
	// artifacts, you need a different approach.
	float blur_multiplier = 1.5; 
	for (int i = 1; i < 7; i++) {
		float offset = float(i) * texel_size.x * blur_multiplier;
		result += texture(scene_texture, uv + vec2(offset, 0.0)) * weights[i];
		result += texture(scene_texture, uv - vec2(offset, 0.0)) * weights[i];
	}

	frag_color = result;
}
