#version 410 core

layout(location = 0)  in vec4  v_color;
layout(location = 1)  in vec2  dst_pos;
layout(location = 2)  in vec2  dst_center;
layout(location = 3)  in vec2  dst_half_size;
layout(location = 4)  in float corner_radius;
layout(location = 5)  in float edge_softness;
layout(location = 6)  in float border_thickness;
layout(location = 7)  in vec2  texture_uv;
layout(location = 8)  in float ui_element_type; // 0 = normal quad, 1 = text, 2 = waveform data, 3 = circle.
layout(location = 9)  in float font_size; 
layout(location = 10) in vec2  clip_tl; 
layout(location = 11) in vec2  clip_br; 
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
#define UI_Type_Audio_Spectrum	5
#define UI_Type_Background  	15

#define frequency_spectrum_row_len 512

// At the moment, a fragment == a pixel.
out vec4 color;

// This indicates which texture unit holds the relevant texture data.
// uniform sampler2D font_texture_xs;
// uniform sampler2D font_texture_s;
// uniform sampler2D font_texture_m;
// uniform sampler2D font_texture_l;
// uniform sampler2D font_texture_xl;

uniform sampler2D font_atlas;
uniform sampler2D audio_frequency_spectrum;

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

// For drawing a smooth top curve on the frequency spectrum data in the EQ.
float sample_spectrum_smooth(vec2 uv, float spectrum_row) {
    float x = uv.x * float(frequency_spectrum_row_len - 1);
    int i0 = max(int(floor(x)) - 1, 0);
    int i1 = i0 + 1;
    int i2 = i0 + 2;
    int i3 = min(i0 + 3, frequency_spectrum_row_len - 1);
    
    float t = fract(x);
    
    float y0 = texture(audio_frequency_spectrum, vec2(float(i0)/511.0, (spectrum_row+0.5)/256.0)).r;
    float y1 = texture(audio_frequency_spectrum, vec2(float(i1)/511.0, (spectrum_row+0.5)/256.0)).r;
    float y2 = texture(audio_frequency_spectrum, vec2(float(i2)/511.0, (spectrum_row+0.5)/256.0)).r;
    float y3 = texture(audio_frequency_spectrum, vec2(float(i3)/511.0, (spectrum_row+0.5)/256.0)).r;
    
    // Catmull-Rom spline
    float t2 = t * t;
    float t3 = t2 * t;
    return 0.5 * ((2.0*y1) + (-y0+y2)*t + (2.0*y0-5.0*y1+4.0*y2-y3)*t2 + (-y0+3.0*y1-3.0*y2+y3)*t3);
}

void main() {
	if (clip_br.x > 0.0 || clip_br.y > 0.0) {
        // Convert UI coords to GL coords (bottom-left origin)
        float clip_left   = clip_tl.x;
        float clip_right  = clip_br.x;
        float clip_bottom = screen_res.y - clip_br.y;  // UI bottom -> GL y
        float clip_top    = screen_res.y - clip_tl.y;  // UI top -> GL y
        
        vec2 frag = gl_FragCoord.xy;
        
        if (frag.x < clip_left || frag.x > clip_right ||
            frag.y < clip_bottom || frag.y > clip_top) {
            discard;
        }
    }

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

	// Apparently better edges when using SDF for anti aliasing non squared off edges. 
	// Supposedly doesn't effect the other use of the SDF function(s), 
	// i.e amount of rounded corners, borders etc.
	float aa = max(edge_softness, fwidth(dist));   // dynamic, high-quality
	float sdf_factor = smoothstep(aa, -aa, dist);  // symmetric falloff

	// use sdf_factor in final color calculation
	if(ui_element_type == UI_Type_Regular) 
	{ 
		color = v_color * sdf_factor * calculate_border_factor(softness_padding);
	} 

	else if(ui_element_type == UI_Type_Audio_Spectrum)
	{
		float spectrum_row = texture_uv.x;
		// Normalize positio within the quad (0 <-> 1)	
		vec2 local_pos = (dst_pos - (dst_center - dst_half_size)) / (dst_half_size * 2.0);
		float bin_f = local_pos.x * float(frequency_spectrum_row_len - 1);
		int bin_low = int(floor(bin_f));
		int bin_high = int(floor(bin_f));
		float t = fract(bin_f);

		// Linear interpolation between adjacent bins
		// float amplitude = mix(spectrum_data[bin_low], spectrum_data[bin_high], t);
		// vec2 uv = vec2(local_pos.x, (spectrum_row + 0.5) / 256);
		// float amplitude = texture(audio_frequency_spectrum, uv).r;

		float amplitude = sample_spectrum_smooth(local_pos, spectrum_row);

		// Y=0 is top, Y=1 in .parent_relative co-ord sysetm.
		// amplitude is 0-1 where 1 = full height.
		// We want to fill from bottom up.
		float fill_threshold = 1.0 - amplitude;

		if (local_pos.y < fill_threshold) {
			discard;
		}

		// Fade color based on height for gradient effect.
		float height_factor = (local_pos.y - fill_threshold) / amplitude;
		vec4 base_color = v_color;
		base_color.a *= mix(0.3, 1.0, height_factor); // Fade toward top
		
		// color = base_color * sdf_factor;	
		color = v_color * sdf_factor;	
	}

	else 
	{ 
		// Sample red channel due to how texture is uploaded.
		float texture_sample = texture(font_atlas, texture_uv).r;
		color = v_color * texture_sample;
	}
}
