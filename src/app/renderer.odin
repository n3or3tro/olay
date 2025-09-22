package app
import "core:fmt"
import "core:math"
import alg "core:math/linalg"
import "core:math/rand"
import "core:mem"
import "core:mem/tlsf"
import "core:strconv"
import s "core:strings"
import gl "vendor:OpenGL"
import ma "vendor:miniaudio"
import sdl "vendor:sdl2"

PI :: math.PI

Font_Size :: enum {
	xs = 0,
	s  = 1,
	m  = 2,
	l  = 3,
	xl = 4,
}

Rect_Render_Data :: struct {
	top_left:             Vec2_f32,
	bottom_right:         Vec2_f32,
	texture_top_left:     Vec2_f32,
	texture_bottom_right: Vec2_f32,
	tl_color:             Vec4_f32,
	tr_color:             Vec4_f32,
	bl_color:             Vec4_f32,
	br_color:             Vec4_f32,
	corner_radius:        f32,
	edge_softness:        f32,
	border_thickness:     f32,
	ui_element_type:      u32,
	font_size:            Font_Size,
	clip_tl:              Vec2_f32,
	clip_br:              Vec2_f32,
}

// Kind of the default data when turning an abstract box into an opengl rect.
get_default_rendering_data :: proc(box: Box) -> Rect_Render_Data {
	data: Rect_Render_Data = {
		top_left         = {f32(box.top_left.x), f32(box.bottom_right.y)},
		bottom_right     = {f32(box.bottom_right.x), f32(box.bottom_right.y)},
		// idrk the winding order for colors, this works tho.
		tl_color         = box.config.background_color,
		tr_color         = box.config.background_color,
		bl_color         = box.config.background_color,
		br_color         = box.config.background_color,
		corner_radius    = 0,
		edge_softness    = 0,
		border_thickness = 1000000,
		// clip_tl          = box.clipping_container.top_left,
		// clip_br          = box.clipping_container.bottom_right,
	}
	return data
}

// sets circumstantial (hovering, clicked, etc) rendering data like radius, borders, etc
get_boxes_rendering_data :: proc(box: Box) -> ^[dynamic]Rect_Render_Data {
	render_data := new([dynamic]Rect_Render_Data, context.temp_allocator)
	tl_color: Vec4_f32 = box.config.background_color
	bl_color: Vec4_f32 = box.config.background_color
	tr_color: Vec4_f32 = box.config.background_color
	br_color: Vec4_f32 = box.config.background_color

	is_button := s.contains(box.id_string, "button")

	if is_button {
		bl_color -= {0.6, 0.6, 0.6, 0}
		br_color -= {0.6, 0.6, 0.6, 0}
	}

	// // super jank and not-sensible color animations for clickable stuff.
	// if box.signals.hovering && .Active_Animation in box.flags {
	// 	bl_color += {0.3, 0.3, 0.3, 0}
	// 	br_color += {0.3, 0.3, 0.3, 0}
	// } else if box.signals.hovering && .Hot_Animation in box.flags {
	// 	bl_color.a = 0.1
	// 	br_color.a = 0.1
	// }

	// data := get_standard_rendering_data(box)
	data: Rect_Render_Data = {
		top_left         = {f32(box.top_left.x), f32(box.top_left.y)},
		bottom_right     = {f32(box.bottom_right.x), f32(box.bottom_right.y)},
		// idrk the winding order for colors, this works tho.
		tl_color         = bl_color,
		tr_color         = br_color,
		bl_color         = box.config.background_color,
		br_color         = box.config.background_color,
		corner_radius    = 0,
		edge_softness    = 0,
		border_thickness = 100000,
		// clip_tl          = box.clipping_container.top_left,
		// clip_br          = box.clipping_container.bottom_right,
	}

	if is_button {
		data.corner_radius = 10
	}

	// Add red outline to indicate the current step of the sequence.
	// if val, is_step := box.metadata.(Step_Metadata); is_step {
	// 	data.border_thickness = 100
	// 	if is_active_step(box) {
	// 		data.corner_radius = 0
	// 		outlining_rect := data
	// 		outlining_rect.border_thickness = 0.7
	// 		normal_color: Color = {1, 0, 0, 1}
	// 		outline_color: Color = {0.5, 0.5, 0.5, 1}
	// 		outlining_rect.tl_color = normal_color
	// 		outlining_rect.tr_color = normal_color
	// 		outlining_rect.bl_color = normal_color
	// 		outlining_rect.br_color = normal_color
	// 		append(render_data, data, outlining_rect)
	// 		return render_data
	// 	}
	// }

	append(render_data, data)

	/* These come after adding the main rect data since they have a higher 'z-order'. */

	// Add cursor inside text box. Blinking is kinda jank right now.
	// if .Edit_Text in box.flags &&
	//    should_render_text_cursor() &&
	//    ui_state.last_active_box != nil &&
	//    ui_state.last_active_box.id_string == box.id_string {
	// 	color := Color{0, 0.5, 1, 1}
	// 	cursor_x_coord :=
	// 		box.rect.top_left.x +
	// 		f32(ui_state.text_box_padding) +
	// 		f32(word_rendered_length(box.value.(Step_Value_Type).(string)[:box.cursor_pos], box.font_size))
	// 	cursor_data := Rect_Render_Data {
	// 		top_left         = {cursor_x_coord, box.rect.top_left.y + 3},
	// 		bottom_right     = {cursor_x_coord + 5, box.rect.bottom_right.y - 3},
	// 		bl_color         = color,
	// 		tl_color         = color,
	// 		br_color         = color,
	// 		tr_color         = color,
	// 		border_thickness = 300,
	// 		corner_radius    = 0,
	// 		edge_softness    = 2,
	// 	}
	// 	append(render_data, cursor_data)
	// }

	// if .Draw_Border in box.flags {
	// 	border_rect := data
	// 	border_rect.border_thickness = 0.6
	// 	border_rect.bl_color = {0, 0, 0, 1}
	// 	border_rect.tl_color = {0, 0, 0, 1}
	// 	border_rect.tr_color = {0, 0, 0, 1}
	// 	border_rect.br_color = {0, 0, 0, 1}
	// 	append(render_data, border_rect)
	// }

	// Add 2 rects to serve as outline indicators for the current step that's been edited.
	// if val, is_step := box.metadata.(Step_Metadata); is_step {
	// 	if box.hot || box.selected || box.active {
	// 		left_selection_border := data
	// 		left_selection_border.border_thickness = 3
	// 		left_selection_border.bottom_right.x -= (rect_width(box.rect) / 1.7)
	// 		left_selection_border.tl_color = {box.color.r, box.color.g, box.color.b, 0}
	// 		left_selection_border.bl_color = {box.color.r, box.color.g, box.color.b, 0}

	// 		right_selection_border := data
	// 		right_selection_border.border_thickness = 3
	// 		right_selection_border.top_left.x += (rect_width(box.rect) / 1.7)
	// 		right_selection_border.tr_color = {box.color.r, box.color.g, box.color.b, 0}
	// 		right_selection_border.br_color = {box.color.r, box.color.g, box.color.b, 0}
	// 		if box.hot {
	// 			left_selection_border.tr_color = palette.secondary.s_800
	// 			left_selection_border.br_color = palette.secondary.s_800
	// 			right_selection_border.tl_color = palette.secondary.s_800
	// 			right_selection_border.bl_color = palette.secondary.s_800
	// 		}
	// 		if box.selected {
	// 			left_selection_border.border_thickness = 5
	// 			right_selection_border.border_thickness = 5
	// 			hot_pink_color := Color{1.0, 0.41, 0.71, 1.0}
	// 			left_selection_border.tr_color = hot_pink_color
	// 			left_selection_border.br_color = hot_pink_color
	// 			right_selection_border.tl_color = hot_pink_color
	// 			right_selection_border.bl_color = hot_pink_color
	// 		}
	// 		if box.active {
	// 			left_selection_border.tr_color = palette.secondary.s_500
	// 			left_selection_border.br_color = palette.secondary.s_500
	// 			right_selection_border.tl_color = palette.secondary.s_500
	// 			right_selection_border.bl_color = palette.secondary.s_500
	// 		}
	// 		append(render_data, left_selection_border)
	// 		append(render_data, right_selection_border)
	// 	}
	// }
	return render_data
}

// get_background_rendering_data :: proc() -> Rect_Render_Data {
// 	background_box := Box {
// 		rect = Rect{top_left = {0.0, 0.0}, bottom_right = {f32(app.wx^), f32(app.wy^)}},
// 		id_string = "background@background",
// 		visible = true,
// 	}
// 	rendering_data := Rect_Render_Data {
// 		// ui_element_type      = 15.0,
// 		// texture_top_left     = {0, 0},
// 		// texture_bottom_right = {1, 1},
// 		top_left     = {0, 0},
// 		bottom_right = {f32(app.wx^), f32(app.wy^)},
// 		bl_color     = {0, 0, 0, 1},
// 		br_color     = {0, 0, 0, 1},
// 		tl_color     = {0.3, 0.3, 0.3, 1},
// 		tr_color     = {0.3, 0.3, 0.3, 1},
// 	}
// 	return rendering_data
// }

get_all_rendering_data :: proc() -> ^[dynamic]Rect_Render_Data {
	// Deffs not efficient to keep realloc'ing and deleting this list, will fix in future.
	rendering_data := new([dynamic]Rect_Render_Data, allocator = context.temp_allocator)
	// append(rendering_data, get_background_rendering_data())
	for box in ui_state.temp_boxes {
		if box.id_string == "" || box == nil {
			panic("This box as it has no id_string OR box == nil")
		}
		boxes_to_render := get_boxes_rendering_data(box^)
		defer delete(boxes_to_render^)
		if .Draw in box.flags {
			for data in boxes_to_render {
				append(rendering_data, data)
			}
		}
		// if metadata, is_knob := box.metadata.(Sampler_Metadata); is_knob {
		// 	if metadata.sampler_part == .ADSR_Knob {
		// 		add_knob_rendering_data(box^, rendering_data)
		// 	}
		// } else if metadata, is_grip := box.metadata.(Track_Control_Metadata); is_grip {
		// 	if metadata.control_type == .Volume_Slider {
		// 		add_fader_knob_rendering_data(box^, rendering_data)
		// 	}
		// } else if .Draw in box.flags {
		// 	for data in boxes_to_render {
		// 		append(rendering_data, data)
		// 	}
		// }

		// if .Draw_Text in box.flags {
		// 	add_word_rendering_data(box^, boxes_to_render, rendering_data)
		// }
		// if s.contains(get_id_from_id_string(box.id_string), "waveform-container") {
		// 	// Render left_channel and right_channel serperately. Maybe we can gain some efficiency by doing this together ?
		// 	// unclear, but it previously setup to only render one channel, so we can do this without any changes.
		// 	active_track := get_active_track()
		// 	left_channel, right_channel := get_track_pcm_data(active_track)
		// 	rects := cut_rect_into_n_vertically(box.rect, 2)
		// 	top_rect, bottom_rect := rects[0], rects[1]
		// 	add_waveform_rendering_data(
		// 		top_rect,
		// 		app.audio_state.tracks[active_track].sound,
		// 		left_channel,
		// 		rendering_data,
		// 	)
		// 	add_waveform_rendering_data(
		// 		bottom_rect,
		// 		app.audio_state.tracks[active_track].sound,
		// 		right_channel,
		// 		rendering_data,
		// 	)
		// }
	}
	return rendering_data
}

// add_knob_rendering_data :: proc(box: Box, rendering_data: ^[dynamic]Rect_Render_Data) {
// 	data := get_default_rendering_data(box)
// 	data.corner_radius = 0
// 	data.ui_element_type = 3.0
// 	data.texture_top_left = {0.0, 0.0}
// 	data.texture_bottom_right = {1.0, 1.0}
// 	append(rendering_data, data)
// }

// add_fader_knob_rendering_data :: proc(box: Box, rendering_data: ^[dynamic]Rect_Render_Data) {
// 	data := get_default_rendering_data(box)
// 	data.corner_radius = 0
// 	data.ui_element_type = 4.0
// 	data.texture_top_left = {0.0, 0.0}
// 	data.texture_bottom_right = {1.0, 1.0}
// 	append(rendering_data, data)
// }

// add_word_rendering_data :: proc(
// 	box: Box,
// 	boxes_to_render: ^[dynamic]Rect_Render_Data,
// 	rendering_data: ^[dynamic]Rect_Render_Data,
// ) {
// 	add_single_word_rendering_data :: proc(
// 		word: string,
// 		baseline: Vec2_f32,
// 		font_size: Font_Size,
// 		rendering_data: ^[dynamic]Rect_Render_Data,
// 	) {
// 		len_so_far: f32 = 0
// 		baseline_x, baseline_y := baseline.x, baseline.y
// 		for i in 0 ..< len(word) {
// 			ch := rune(word[i])
// 			char_metadata := ui_state.font_atlases[font_size].chars[ch]
// 			new_rect := Rect_Render_Data {
// 				bl_color             = {1, 1, 1, 1},
// 				br_color             = {1, 1, 1, 1},
// 				tl_color             = {1, 1, 1, 1},
// 				tr_color             = {1, 1, 1, 1},
// 				border_thickness     = 300,
// 				corner_radius        = 0,
// 				edge_softness        = 0,
// 				ui_element_type      = 1.0,
// 				top_left             = {
// 					baseline_x + len_so_far + char_metadata.glyph_x0, // Use glyph x0
// 					baseline_y + char_metadata.glyph_y0, // Use glyph y0
// 				},
// 				bottom_right         = {
// 					baseline_x + len_so_far + char_metadata.glyph_x1, // Use glyph_x1 for actual glyph width
// 					baseline_y + char_metadata.glyph_y1,
// 				},
// 				texture_top_left     = {char_metadata.u0, char_metadata.v0},
// 				texture_bottom_right = {char_metadata.u1, char_metadata.v1},
// 				font_size            = font_size,
// 				clip_tl              = {0, 0},
// 				clip_br              = {f32(app.wx^), f32(app.wy^)},
// 			}
// 			len_so_far += char_metadata.advance_x
// 			append(rendering_data, new_rect)
// 		}
// 	}
// 	// Only render text data of a tracker step if it's 'selected'.
// 	if _, is_step := box.metadata.(Step_Metadata); is_step {
// 		step_num := step_num_from_step(box.id_string)
// 		track_num := track_num_from_step(box.id_string)
// 		if !app.audio_state.tracks[track_num].selected_steps[step_num] {
// 			return
// 		}
// 	}

// 	// Figure out whether to render box.name or box.value
// 	box_value, has_value := box.value.?
// 	conversion_data: [8]byte
// 	string_to_render: string
// 	if has_value {
// 		switch _ in box_value {
// 		case string:
// 			string_to_render = box_value.(string)
// 		case u32:
// 			string_to_render = strconv.itoa(conversion_data[:], int(box_value.(u32)))
// 		}
// 	} else {
// 		// Basically if box.value wasn't set, but this field is supposed to
// 		// take an input, then we render no text.
// 		if s.contains(box.id_string, "input") {
// 			string_to_render = ""
// 		} else {
// 			string_to_render = box.name
// 		}
// 	}

// 	potential_length := word_rendered_length(string_to_render, box.font_size)
// 	if potential_length >= int(rect_width(box.rect)) {
// 		words := s.split(string_to_render, " ", context.temp_allocator)
// 		n_words := u32(len(words))
// 		word_rects := cut_rect_into_n_vertically(box.rect, n_words, context.temp_allocator)
// 		word_lengths := make([dynamic]u32, allocator = context.temp_allocator)
// 		word_baselines := make([dynamic]Vec2_f32, allocator = context.temp_allocator)
// 		for word, i in words {
// 			append(&word_lengths, u32(word_rendered_length(word, box.font_size)))
// 			x, y := get_font_baseline(word, box.font_size, word_rects[i], box.flags)
// 			append(&word_baselines, Vec2_f32{x, y})
// 		}
// 		printfln("string_to_render is: {}", string_to_render)
// 		for j in 0 ..< len(words) {
// 			word := words[j]
// 			printfln("this token is: {}", word)
// 			baseline := word_baselines[j]
// 			add_single_word_rendering_data(word, baseline, box.font_size, rendering_data)
// 		}
// 	} else {
// 		baseline_x, baseline_y := get_font_baseline(string_to_render, box.font_size, box.rect, box.flags)
// 		baseline := Vec2_f32{baseline_x, baseline_y}
// 		add_single_word_rendering_data(string_to_render, baseline, box.font_size, rendering_data)
// 	}
// 	// render font baseline for debuggin purposes
// 	// font_baseline_rect := Rect_Render_Data {
// 	// 	bl_color         = {1, 0.2, 0.5, 1},
// 	// 	tl_color         = {1, 0.2, 0.5, 1},
// 	// 	br_color         = {1, 0.2, 0.5, 1},
// 	// 	tr_color         = {1, 0.2, 0.5, 1},
// 	// 	border_thickness = 100,
// 	// 	top_left         = {baseline_x, baseline_y},
// 	// 	bottom_right     = {baseline_x + f32(word_rendered_length(string_to_render)), baseline_y + 3},
// 	// 	corner_radius    = 0,
// 	// 	edge_softness    = 0,
// 	// }
// 	// append(rendering_data, font_baseline_rect)
// }

// // Assumes pcm_frames is from a mono version of the .wav file, BOLD assumption.
// // Might need to cache calls to this function since it's pretty costly.
// add_waveform_rendering_data :: proc(
// 	rect: Rect,
// 	sound: ^ma.sound,
// 	pcm_frames: [dynamic]f32,
// 	rendering_data: ^[dynamic]Rect_Render_Data,
// ) {
// 	render_width := rect_width(rect)
// 	render_height := rect_height(rect)
// 	frames_read := u64(len(pcm_frames))
// 	wav_rendering_data := make([dynamic]Rect_Render_Data, u32(render_width), allocator = context.temp_allocator)
// 	sampler := app.samplers[get_active_track()]
// 	// might break with very large samples.
// 	visible_width := f64(frames_read) * f64(1 - sampler.zoom_amount)


// 	// New CLAUDE fix for correct zooming.
// 	start_sample := u64(f64(sampler.zoom_point) * f64(frames_read))
// 	end_sample := start_sample + u64(visible_width)

// 	// Clamp to valid range
// 	start_sample = max(u64(0), start_sample)
// 	end_sample = min(u64(frames_read), end_sample)

// 	// Figure out how much of the sound has played.
// 	pos_in_track: u64
// 	if ma.sound_get_cursor_in_pcm_frames(sound, &pos_in_track) != .SUCCESS {
// 		panic("failed to get cursor position of sound")
// 	}

// 	played_color: Color = {1, 0.5, 1, 1}
// 	unplayed_color: Color = {0.5, 0.5, 0.5, 1}
// 	for x in 0 ..< render_width {
// 		ratio_of_waveform := f64(x) / f64(render_width)
// 		start := start_sample + u64((f64(x) / f64(render_width)) * (f64(end_sample - start_sample)))
// 		end := start_sample + u64((f64(x + 1) / f64(render_width)) * (f64(end_sample - start_sample)))
// 		if end >= frames_read {end = frames_read}
// 		min: f32 = 1
// 		max: f32 = -1
// 		for i in start ..< end {
// 			if pcm_frames[i] < min {min = pcm_frames[i]}
// 			if pcm_frames[i] > max {max = pcm_frames[i]}
// 		}
// 		norm_x: f32 = f32(x) / render_width
// 		x_pos := rect.top_left.x + norm_x * render_width
// 		y_top := rect.top_left.y + (0.5 - max * 0.5) * render_height
// 		y_bot := rect.top_left.y + (0.5 - min * 0.5) * render_height
// 		new_data := Rect_Render_Data {
// 			border_thickness = 300,
// 			corner_radius    = 0,
// 			edge_softness    = 0,
// 			top_left         = Vec2_f32{x_pos - 0.5, y_top},
// 			bottom_right     = Vec2_f32{x_pos + 0.5, y_bot},
// 			ui_element_type  = 2.0,
// 		}
// 		if end <= pos_in_track {
// 			new_data.tl_color = played_color
// 			new_data.tr_color = played_color
// 			new_data.bl_color = played_color
// 			new_data.br_color = played_color
// 		} else {
// 			new_data.tl_color = unplayed_color
// 			new_data.tr_color = unplayed_color
// 			new_data.bl_color = unplayed_color
// 			new_data.br_color = unplayed_color
// 		}
// 		new_data.clip_tl = {0, 0}
// 		new_data.clip_br = {f32(app.wx^), f32(app.wy^)}
// 		append(rendering_data, new_data)
// 	}
// }


// // A jank way to 'animate' the text cursor blinking based on frame number.
// should_render_text_cursor :: proc() -> bool {
// 	frame_rate: u64 = 120 // Shouldn't be hardcoded in prod.
// 	curr_frame := app.ui_state.frame_num^ % frame_rate
// 	return curr_frame < frame_rate
// }

// is_active_step :: proc(box: Box) -> bool {
// 	track_num := track_num_from_step(box.id_string)
// 	step_num := step_num_from_step(box.id_string)
// 	return step_num == app.audio_state.tracks[track_num].curr_step
// }

setup_for_quads :: proc(shader_program: ^u32) {
	//odinfmt:disable
	gl.BindVertexArray(ui_state.quad_vabuffer^)
	bind_shader(shader_program^)

	gl.VertexAttribPointer(0, 2, gl.FLOAT, false, size_of(Rect_Render_Data), offset_of(Rect_Render_Data, top_left))
	gl.VertexAttribDivisor(0, 1)
	enable_layout(0)

	gl.VertexAttribPointer(1, 2, gl.FLOAT, false, size_of(Rect_Render_Data), offset_of(Rect_Render_Data, bottom_right))
	enable_layout(1)
	gl.VertexAttribDivisor(1, 1)

	// Trying to pass in a [4]vec4 for colors was fucky, so did this. Should clean up later.
	gl.VertexAttribPointer(2, 4, gl.FLOAT, false, size_of(Rect_Render_Data), offset_of(Rect_Render_Data, tl_color))
	enable_layout(2)
	gl.VertexAttribDivisor(2, 1)

	gl.VertexAttribPointer(3, 4, gl.FLOAT, false, size_of(Rect_Render_Data), offset_of(Rect_Render_Data, tr_color))
	enable_layout(3)
	gl.VertexAttribDivisor(3, 1)

	gl.VertexAttribPointer(4, 4, gl.FLOAT, false, size_of(Rect_Render_Data), offset_of(Rect_Render_Data, bl_color))
	enable_layout(4)
	gl.VertexAttribDivisor(4, 1)

	gl.VertexAttribPointer(5, 4, gl.FLOAT, false, size_of(Rect_Render_Data), offset_of(Rect_Render_Data, br_color))
	enable_layout(5)
	gl.VertexAttribDivisor(5, 1)

	gl.VertexAttribPointer(6, 1, gl.FLOAT, false, size_of(Rect_Render_Data), offset_of(Rect_Render_Data, corner_radius))
	enable_layout(6)
	gl.VertexAttribDivisor(6, 1)

	gl.VertexAttribPointer(7, 1, gl.FLOAT, false, size_of(Rect_Render_Data), offset_of(Rect_Render_Data, edge_softness))
	enable_layout(7)
	gl.VertexAttribDivisor(7, 1)

	gl.VertexAttribPointer(8, 1, gl.FLOAT, false, size_of(Rect_Render_Data), offset_of(Rect_Render_Data, border_thickness))
	enable_layout(8)
	gl.VertexAttribDivisor(8, 1)

	gl.VertexAttribPointer(9, 2, gl.FLOAT, false, size_of(Rect_Render_Data), offset_of(Rect_Render_Data, texture_top_left))
	enable_layout(9)
	gl.VertexAttribDivisor(9, 1)

	gl.VertexAttribPointer(10, 2, gl.FLOAT, false, size_of(Rect_Render_Data), offset_of(Rect_Render_Data, texture_bottom_right))
	enable_layout(10)
	gl.VertexAttribDivisor(10, 1)

	gl.VertexAttribPointer(11, 1, gl.INT, false, size_of(Rect_Render_Data), offset_of(Rect_Render_Data, ui_element_type))
	enable_layout(11)
	gl.VertexAttribDivisor(11, 1)

	gl.VertexAttribPointer(12, 1, gl.INT, false, size_of(Rect_Render_Data), offset_of(Rect_Render_Data, font_size))
	enable_layout(12)
	gl.VertexAttribDivisor(12, 1)

	gl.VertexAttribPointer(13, 2, gl.FLOAT, false, size_of(Rect_Render_Data), offset_of(Rect_Render_Data, clip_tl))
	enable_layout(13)
	gl.VertexAttribDivisor(13, 1)

	gl.VertexAttribPointer(14, 2, gl.FLOAT, false, size_of(Rect_Render_Data), offset_of(Rect_Render_Data, clip_br))
	enable_layout(14)
	gl.VertexAttribDivisor(14, 1)

	//odinfmt:enable
}

clear_screen :: proc() {
	gl.ClearColor(0, 0.5, 1, 0.5)
	gl.Clear(gl.COLOR_BUFFER_BIT)
}

render_ui :: proc(rect_rendering_data: [dynamic]Rect_Render_Data) {
	clear_screen()
	if ui_state.frame_num == 0 {
		return
	}
	n_rects := u32(len(rect_rendering_data))
	populate_vbuffer_with_rects(
		ui_state.quad_vbuffer, // ui_state.quad_vabuffer,
		0,
		raw_data(rect_rendering_data),
		n_rects * size_of(Rect_Render_Data),
	)
	gl.DrawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, i32(n_rects))
}

reset_ui_state :: proc() {
	/* 
		I think maybe I don't want to actually reset this each frame, for exmaple,
		if a user selected some input field on one frame, then it should still be active
		on the next fram
	*/
	if ui_state.active_box != nil {
		ui_state.last_active_box = ui_state.active_box
	}
	if ui_state.hot_box != nil {
		ui_state.last_hot_box = ui_state.hot_box
	}
	ui_state.active_box = nil
	ui_state.hot_box = nil
	clear(&ui_state.box_cache)
}


draw :: proc(n_vertices: i32, indices: [^]u32) {
	gl.DrawElements(gl.TRIANGLES, n_vertices, gl.UNSIGNED_INT, indices)
}
