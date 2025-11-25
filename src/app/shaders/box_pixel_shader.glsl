#version 410 core

layout(location = 0)  in vec4 v_color;
layout(location = 1)  in vec2 dst_pos;
layout(location = 2)  in vec2 dst_center;
layout(location = 3)  in vec2 dst_half_size;
layout(location = 4)  in float corner_radius;
layout(location = 5)  in float edge_softness;
layout(location = 6)  in float border_thickness;
layout(location = 7)  in vec2 texture_uv;
layout(location = 8)  in float ui_element_type; // 0 = normal quad, 1 = text, 2 = waveform data, 3 = circle.
layout(location = 9)  in float font_size; 
layout(location = 10) in vec2 clip_tl; 
layout(location = 11) in vec2 clip_br; 
layout(location = 12) in float rotation_radians; 

#define font_size_xs  0
#define font_size_s   1
#define font_size_m   2
#define font_size_l   3
#define font_size_xl  4


#define UI_Type_Regular 		0
#define UI_Type_Font 			1
#define UI_Type_Waveform_Data 	2
#define UI_Type_Circle 			3
#define UI_Type_Fader_Knob 		4
#define UI_Type_Background  	15


// At the moment, a fragment == a pixel.
out vec4 color;

// This indicates which texture unit holds the relevant texture data.
// uniform sampler2D font_texture_xs;
// uniform sampler2D font_texture_s;
// uniform sampler2D font_texture_m;
// uniform sampler2D font_texture_l;
// uniform sampler2D font_texture_xl;

uniform sampler2D font_atlas;

// uniform sampler2D circle_knob_texture;
// uniform sampler2D fader_knob_texture;
// uniform sampler2D background_texture;

uniform vec2 screen_res;

float RoundedRectSDF(vec2 sample_pos, vec2 rect_center, vec2 rect_half_size, float r) {
	vec2 d2 = (abs(rect_center - sample_pos) -
		rect_half_size +
		vec2(r, r));
	return min(max(d2.x, d2.y), 0.0) + length(max(d2, 0.0)) - r;
}

float calculate_border_factor(vec2 softness_padding) {
	float border_factor = 1.0;
	if(border_thickness == 0) {
		return border_factor;
	} else {
		vec2 interior_half_size = dst_half_size - vec2(border_thickness, border_thickness);
		// reduction factor for the internal corner radius. not 100% sure the best way to go
		// about this, but this is the best thing I've found so far!

		// this is necessary because otherwise it looks weird
		float interior_radius_reduce_f = min(interior_half_size.x / dst_half_size.x, interior_half_size.y / dst_half_size.y);
		float interior_corner_radius = (corner_radius * interior_radius_reduce_f * interior_radius_reduce_f);

		// calculate sample distance from "interior"
		float inside_d = RoundedRectSDF(dst_pos, dst_center, interior_half_size -
			softness_padding, interior_corner_radius);

		// map distance => factor
		float inside_f = smoothstep(0, 2 * edge_softness, inside_d);
		return inside_f;
	}
}

float CircleSDF(vec2 sample_pos, vec2 center, float radius) {
	return length(sample_pos - center) - radius;
}

void main() {
	// Don't draw any pixels that fall outside clipping rect set during UI creation.
	// float screen_space_y = screen_res.y - gl_FragCoord.y;
	// if (gl_FragCoord.x < clip_tl.x || gl_FragCoord.x > clip_br.x || screen_space_y < clip_tl.y 
	// 	|| screen_space_y > clip_br.y) {
	// 	discard;
	// }

	// we need to shrink the rectangle's half-size that is used for distance calculations with
	// the edge softness - otherwise the underlying primitive will cut off the falloff too early.
	vec2 softness = vec2(edge_softness, edge_softness);
	vec2 softness_padding = max(max(softness * 2.0 - 1.0, 0.0), max(softness * 2.0 - 1.0, 0.0));

	// sample distance
	float dist;

	// ============ Added by Claude ===========================
	// Inverse-rotate sample position for rotated primitives
	vec2 sample_pos = dst_pos;
	if (rotation_radians != 0.0) {
		vec2 local_pos = dst_pos - dst_center;
		float s = sin(rotation_radians);
		float c = cos(rotation_radians);
		vec2 unrotated_local = vec2(
			local_pos.x * c + local_pos.y * s,
			-local_pos.x * s + local_pos.y * c
		);
		sample_pos = unrotated_local + dst_center;
	}

	if(ui_element_type == UI_Type_Circle) { 
    dist = CircleSDF(sample_pos, dst_center, dst_half_size.x - softness_padding.x);
	} else {
		dist = RoundedRectSDF(sample_pos, dst_center, dst_half_size - softness_padding, corner_radius);
	}

	// if(ui_element_type == UI_Type_Circle) { 
	// 	dist = CircleSDF(dst_pos, dst_center, dst_half_size.x - softness_padding.x);
	// } else {
	// 	dist = RoundedRectSDF(dst_pos, dst_center, dst_half_size - softness_padding, corner_radius);
	// }
	// ============ Added by Claude ===========================

	// if(ui_element_type == UI_Type_Circle) { 
	// 	dist = CircleSDF(dst_pos, dst_center, dst_half_size.x - softness_padding.x);
	// } else {
	// 	dist = RoundedRectSDF(dst_pos, dst_center, dst_half_size - softness_padding, corner_radius);
	// }

	// map distance => a blend factor
	// float sdf_factor = 1.0 - smoothstep(0.0, 2.0 * edge_softness, dist);

	// replaced the above line with these 2 lines from sdf for apparently better edges when using SDF 
	// for anti aliasing non squared off edges. Supposedly doesn't effect the other use of the SDF function(s)
	// I.e amount of rounded corners, borders etc.
	float aa = max(edge_softness, fwidth(dist));   // dynamic, high-quality
	float sdf_factor = smoothstep(aa, -aa, dist);  // symmetric falloff

	// use sdf_factor in final color calculation
	if(ui_element_type == UI_Type_Regular) 
	{ 
		color = v_color * sdf_factor * calculate_border_factor(softness_padding);
	} 
	// else if(ui_element_type == UI_Type_Waveform_Data) 
	// {
	// 	color = v_color;
	// } 
	// else if (ui_element_type == UI_Type_Circle) 
	// { 
	// 	vec4 texture_sample = texture(circle_knob_texture, texture_uv);
	// 	color = texture_sample;
	// } 
	// else if (ui_element_type == UI_Type_Fader_Knob) 
	// { 
	// 	vec4 texture_sample = texture(fader_knob_texture, texture_uv);
	// 	color = texture_sample;
	// } 
	else 
	{ 
		// Sample red channel due to how texture is uploaded.
		float texture_sample = texture(font_atlas, texture_uv).r;
		color = v_color * texture_sample;
	}
}
