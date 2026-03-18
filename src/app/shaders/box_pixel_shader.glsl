#version 410 core

layout(location = 0)       in vec4  v_color;
layout(location = 1)       in vec2  dst_pos;
layout(location = 2)       in vec2  dst_center;
layout(location = 3)       in vec2  dst_half_size;
layout(location = 4)       in float corner_radius;
layout(location = 5)       in float edge_softness;
layout(location = 6)       in float border_thickness;
layout(location = 7)       in vec2  texture_uv;
layout(location = 8)  flat in uint  ui_flags; 
layout(location = 9)       in float font_size; 
layout(location = 10)      in vec2  clip_tl; 
layout(location = 11)      in vec2  clip_br; 
layout(location = 12)      in float rotation_radians; 

// inst = instance, i.e. the quad instance from the vertex shader.
flat in vec4 inst_tl_color;
flat in vec4 inst_tr_color;
flat in vec4 inst_bl_color;
flat in vec4 inst_br_color;

#define font_size_xs  0
#define font_size_s   1
#define font_size_m   2
#define font_size_l   3
#define font_size_xl  4

#define UI_Flag_Regular 		(1u << 0u)
#define UI_Flag_Font 			(1u << 1u)
#define UI_Flag_Waveform_Data 	(1u << 2u)
#define UI_Flag_Circle 			(1u << 3u)
#define UI_Flag_Fader_Knob 		(1u << 4u)
#define UI_Flag_Audio_Spectrum	(1u << 5u)
#define UI_Flag_Frosted_Glass	(1u << 6u)
#define UI_Flag_Glow			(1u << 7u)
#define UI_Flag_Knob_Indicator	(1u << 8u)
#define UI_Flag_Frequency_Response (1u << 9u)
#define UI_Flag_Background  	(1u << 15u)

#define frequency_spectrum_row_len 512
#define eq_response_row_len 512

// At the moment, a fragment == a pixel.
out vec4 color;

uniform vec2 screen_res;

// This indicates which texture unit holds the relevant texture data.
// uniform sampler2D font_texture_xs;
// uniform sampler2D font_texture_s;
// uniform sampler2D font_texture_m;
// uniform sampler2D font_texture_l;
// uniform sampler2D font_texture_xl;

uniform sampler2D font_atlas;
// Actual frequency data from 20hz - 20khz
uniform sampler2D audio_frequency_spectrum;    // One row per EQ
// The points we need for drawing the response curve
uniform sampler2D audio_frequency_eq_response; // One row per EQ
uniform sampler2D blurred_ui;

// uniform sampler2D circle_knob_texture;
// uniform sampler2D fader_knob_texture;
// uniform sampler2D background_texture;


bool flag_set(uint bit_field, uint flag) {
	return ((bit_field & flag) != 0);
}

float rounded_rect_sdf(vec2 sample_pos, vec2 rect_center, vec2 rect_half_size, float r) {
	vec2 d2 = (abs(rect_center - sample_pos) -
		rect_half_size +
		vec2(r, r));
	return min(max(d2.x, d2.y), 0.0) + length(max(d2, 0.0)) - r;
}

float circle_sdf(vec2 sample_pos, vec2 center, float radius) {
	return length(sample_pos - center) - radius;
}

float arc_sdf(vec2 p, float radius, float thickness, float sweep_range) {
    float start_a = 2.26892802;
    float r       = length(p);
    float radial  = abs(r - radius) - thickness * 0.5;

    float angle = mod(atan(p.y, p.x) - start_a, 6.28318530);

    if (angle < sweep_range) {
        return radial;
    } else {
        vec2 sta_dir = vec2(cos(start_a),              sin(start_a));
        vec2 end_dir = vec2(cos(start_a + sweep_range), sin(start_a + sweep_range));
        float d0 = length(p - radius * sta_dir) - thickness * 0.5;
        float d1 = length(p - radius * end_dir) - thickness * 0.5;
        return min(d0, d1);
    }
}

// float arc_sdf(vec2 p, float radius, float thickness, float sweep_range) {
// 	float start_a = 2.26892802; // 130 * PI / 180
//     float r      = length(p);
//     float radial = abs(r - radius) - thickness * 0.5;

//     // Normalize angle to [0, sweep_range] relative to start_a
//     float angle  = mod(atan(p.y, p.x) - start_a, 6.28318530);
//     float past   = angle - sweep_range;

//     // If inside the swept range, angular distance is negative (inside)
//     float angular;
//     if (angle < sweep_range) {
//         // Inside arc: smooth distance to both caps
//         float d0 = r * sin(angle);           // dist to start cap tangent
//         float d1 = r * sin(sweep_range - angle);   // dist to end cap tangent
//         angular = -min(d0, d1);
//     } else {
//         // Outside arc: distance to nearer endpoint
//         vec2 end_dir = vec2(cos(start_a + sweep_range), sin(start_a + sweep_range));
//         vec2 sta_dir = vec2(cos(start_a), sin(start_a));
//         float d0 = length(p - radius * sta_dir);
//         float d1 = length(p - radius * end_dir);
//         angular = min(d0, d1) - thickness * 0.5;
//     }
//     return max(radial, angular);
// }

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
		float inside_d = rounded_rect_sdf(dst_pos, dst_center, interior_half_size -
			softness_padding, interior_corner_radius);

		// map distance => factor
		float inside_f = smoothstep(0, 2 * edge_softness, inside_d);
		return inside_f;
	}
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

float sample_eq_response(float x, float eq_row) {
    float fx = x * float(eq_response_row_len - 1);
    int   i0 = int(floor(fx));
    int   i1 = min(i0 + 1, eq_response_row_len - 1);
    float t  = fract(fx);
    float row_v = (eq_row + 0.5) / 256.0;
    float y0 = texture(audio_frequency_eq_response, vec2(float(i0) / 511.0, row_v)).r;
    float y1 = texture(audio_frequency_eq_response, vec2(float(i1) / 511.0, row_v)).r;
    return mix(y0, y1, t);
}

void main() {
	// Clip rects that won't be inside the viewport. Probably more efficient to discard 
	// them before they even reach this point if that's possible. i.e. in the vertex shader / CPU code.
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
	// ========================================================

	if(flag_set(ui_flags, UI_Flag_Circle)) { 
		dist = circle_sdf(sample_pos, dst_center, dst_half_size.x - softness_padding.x);
	} else {
		dist = rounded_rect_sdf(sample_pos, dst_center, dst_half_size - softness_padding, corner_radius);
	}

	// Apparently better edges when using SDF for anti aliasing non squared off edges. 
	// Supposedly doesn't effect the other use of the SDF function(s), 
	// i.e amount of rounded corners, borders etc.
	float aa = max(edge_softness, fwidth(dist));   // dynamic, high-quality
	float sdf_factor = smoothstep(aa, -aa, dist);  // symmetric falloff

	// use sdf_factor in final color calculation
	 
	// Step 1: Frosted base — computed before the type chain so any type can use it.
	vec4 base_color;
	if (flag_set(ui_flags, UI_Flag_Frosted_Glass)) {
		vec2  screen_uv = gl_FragCoord.xy / screen_res;
		float texel_y   = 1.0 / screen_res.y;

		const float weights[7] = float[](0.1370, 0.1296, 0.1097, 0.0831, 0.0563, 0.0342, 0.0185);
		vec4 blurred = texture(blurred_ui, screen_uv) * weights[0];
		float blur_multiplier = 1.5;
		for (int i = 1; i < 7; i++) {
			float offset = float(i) * texel_y * blur_multiplier;
			blurred += texture(blurred_ui, screen_uv + vec2(0.0,  offset)) * weights[i];
			blurred += texture(blurred_ui, screen_uv - vec2(0.0,  offset)) * weights[i];
		}

		vec4 tint = vec4(0.04, 0.06, 0.09, 0.6);
		base_color = vec4(mix(blurred.rgb, tint.rgb, tint.a), 1.0);
	} else {
		base_color = v_color;
	}

	// Step 2: Type-specific rendering. Each branch uses base_color so frosted tints it correctly.
	if (flag_set(ui_flags, UI_Flag_Font))
	{
		// float texture_sample = texture(font_atlas, texture_uv).r;
		// color = base_color * texture_sample;
		float texture_sample = texture(font_atlas, texture_uv).r;
		color = vec4(base_color.rgb, base_color.a * texture_sample);

	}
	else if(flag_set(ui_flags, UI_Flag_Audio_Spectrum))
	{
		float spectrum_row = texture_uv.x;
		vec2 local_pos = (dst_pos - (dst_center - dst_half_size)) / (dst_half_size * 2.0);
		float amplitude = sample_spectrum_smooth(local_pos, spectrum_row);
		float fill_threshold = 1.0 - amplitude;
		if (local_pos.y < fill_threshold) {
			discard;
		}
		color = base_color * sdf_factor;
	}
	else if (flag_set(ui_flags, UI_Flag_Knob_Indicator)) {
		float sweep_range = 4.88692;
		float ring_radius = dst_half_size.x - border_thickness;
		float d = arc_sdf(sample_pos - dst_center, ring_radius, border_thickness, texture_uv.x * sweep_range);
		float arc_aa = max(edge_softness, fwidth(d));
		color = base_color * smoothstep(arc_aa, -arc_aa, d);
	}
	else if (flag_set(ui_flags, UI_Flag_Frequency_Response)) {
		float eq_row = texture_uv.x;
		vec2 local = (dst_pos - (dst_center - dst_half_size)) / (dst_half_size * 2);

		float curve_y  = sample_eq_response(local.x, eq_row);
		// float curve_y = 0.5;

		float box_h_px = dst_half_size.y * 2;
		// float dist_px  = abs(local.y - curve_y) * box_h_px;
		float dist_px = abs((1.0 - local.y) - curve_y) * box_h_px;


		float line_px = 1.5;
		float aa_px   = 1.0;
		float line_alpha = smoothstep(line_px + aa_px, line_px - aa_px, dist_px);

		if (line_alpha <= 0.0) discard;
		color = vec4(base_color.rgb, base_color.a * line_alpha) * sdf_factor;
	}
	else {
		color = base_color * sdf_factor * calculate_border_factor(softness_padding);
	}

	// Step 3: Glow is additive on top of whatever type was rendered.
	if (flag_set(ui_flags, UI_Flag_Glow)) {
		vec2 box_size  = dst_half_size * 2.0;
		vec2 uv        = (sample_pos - (dst_center - dst_half_size)) / box_size;
		float aspect   = box_size.x / box_size.y;
		vec2 uv_aspect = vec2(uv.x * aspect, uv.y);

		vec3 col_tl = vec3(0.0, 0.85, 0.95);
		vec3 col_tr = vec3(0.1, 0.4,  0.9);
		vec3 col_bl = vec3(0.8, 0.1,  0.5);
		vec3 col_br = vec3(0.4, 0.2,  0.8);

		vec2 pos_tl = vec2(0.0 * aspect, 0.0);
		vec2 pos_tr = vec2(1.0 * aspect, 0.0);
		vec2 pos_bl = vec2(0.0 * aspect, 1.0);
		vec2 pos_br = vec2(1.0 * aspect, 1.0);

		float int_tl = exp(-distance(uv_aspect, pos_tl) * 4.0) * 0.7;
		float int_tr = exp(-distance(uv_aspect, pos_tr) * 4.0) * 0.6;
		float int_bl = exp(-distance(uv_aspect, pos_bl) * 4.0) * 0.7;
		float int_br = exp(-distance(uv_aspect, pos_br) * 4.0) * 0.6;

		vec3 light_sum = col_tl*int_tl + col_tr*int_tr + col_bl*int_bl + col_br*int_br;

		float border_intensity = exp(-abs(dist) * 0.8) * 1.8;
		vec3 glowing_border    = (light_sum + vec3(0.05)) * border_intensity;

		color.rgb += light_sum + glowing_border;
	}
}
