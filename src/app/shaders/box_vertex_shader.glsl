#version 410 core

layout(location = 0)  in vec2 quad_top_left;      	// Top-left corner of rectangle (per-instance)
layout(location = 1)  in vec2 quad_bottom_right;     // Bottom-right corner of rectangle (per-instance)

layout(location = 2)  in vec4 tl_color;
layout(location = 3)  in vec4 tr_color;
layout(location = 4)  in vec4 bl_color;
layout(location = 5)  in vec4 br_color;

layout(location = 6)  in float corner_radius;
layout(location = 7)  in float edge_softness;  		// Used for shadows and shit I think. 
layout(location = 8)  in float border_thickness; 	// Used for shadows and shit I think. 

layout(location = 9)  in vec2 texture_top_left;
layout(location = 10) in vec2 texture_bottom_right;
layout(location = 11) in float ui_element_type; 	// 0 = normal quad, 1 = text, 2 = to be decided    
layout(location = 12) in float font_size; 
layout(location = 13) in vec2 clip_tl; 		
layout(location = 14) in vec2 clip_br; 		
// For drawing primitves on an angle.
layout(location = 15) in float rotation_radians; 		


layout(location = 0)  out vec4  v_color;
layout(location = 1)  out vec2  out_dst_pos;
layout(location = 2)  out vec2  out_dst_center;
layout(location = 3)  out vec2  out_dst_half_size;
layout(location = 4)  out float out_corner_radius;
layout(location = 5)  out float out_edge_softness;
layout(location = 6)  out float out_border_thickness;
layout(location = 7)  out vec2  out_texture_uv;
layout(location = 8)  out float out_ui_element_type; // 0 = normal quad, 1 = text, 2 = to be decided    
layout(location = 9)  out float out_font_size; 
layout(location = 10) out vec2  out_clip_tl; 
layout(location = 11) out vec2  out_clip_br; 
layout(location = 12) out float out_rotation_radians;

// uniform vec2 screen_res = vec2(3000, 2000);
uniform vec2 screen_res; 

#define UI_Type_Regular 		0
#define UI_Type_Font 			1
#define UI_Type_Waveform_Data 	2
#define UI_Type_Circle 			3
#define UI_Type_Fader_Knob 		4
#define UI_Type_Audio_Spectrum	5
#define UI_Type_Background  	15

void main() {
	vec4[4] colors;
	colors[0] = br_color;
	colors[1] = tr_color;
	colors[2] = bl_color;
	colors[3] = tl_color;

    // Static vertex array mapped to gl_VertexID
	vec2 vertices[4] = vec2[](vec2(-1.0, -1.0), vec2(-1.0, 1.0), vec2(1.0, -1.0), vec2(1.0, 1.0));

	// Old working position calculation code
	vec2 dst_half_size = (quad_bottom_right - quad_top_left) / 2.0;
	vec2 dst_center = (quad_bottom_right + quad_top_left) / 2.0;
	// vec2 dst_pos = (vertices[gl_VertexID] * dst_half_size) + dst_center;

	// New position code to account for angled primitives.
	float s = sin(rotation_radians);
	float c = cos(rotation_radians);
	vec2 local_pos = vertices[gl_VertexID] * dst_half_size;
	vec2 rotated_pos = vec2(local_pos.x * c - local_pos.y * s, local_pos.x * s + local_pos.y * c);
	vec2 dst_pos = rotated_pos + dst_center;

	// Texture stuff :)
	vec2 tex_half_size = (texture_bottom_right - texture_top_left) / 2;
	vec2 tex_center = (texture_bottom_right + texture_top_left) / 2;
	vec2 tex_pos = (vertices[gl_VertexID] * tex_half_size + tex_center);

	if (ui_element_type == 1) { 
		out_texture_uv = tex_pos;
	}
	else if (ui_element_type == UI_Type_Audio_Spectrum) {
		// we pass in the track number of the eq's spectrum we're sampling.
		out_texture_uv = texture_top_left;
	}
	else { // rest of textures you just paste the whole texture ontop of the quad.
		out_texture_uv = (vertices[gl_VertexID] + 1.0) * 0.5;
		out_texture_uv.y = 1.0 - out_texture_uv.y; 
	}

    // Map to screen coordinates (-1 to 1 NDC)
	// vec2 ndc_pos = 2.0 * dst_pos / screen_res - vec2(1.0);

    // Output data for pixel shader
	v_color = colors[gl_VertexID];
	out_dst_pos = dst_pos;
	out_dst_center = dst_center;
	out_dst_half_size = dst_half_size;
	out_corner_radius = corner_radius;
	out_edge_softness = edge_softness;
	out_border_thickness = border_thickness;
	out_ui_element_type = ui_element_type;
	out_font_size = font_size;
	out_clip_tl = clip_tl;
	out_clip_br = clip_br;
	out_rotation_radians = rotation_radians;
	gl_Position = vec4(2 * dst_pos.x / screen_res.x - 1, -1 * (2 * dst_pos.y / screen_res.y - 1), 0.0, 1.0);
}
