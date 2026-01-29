package app
import "base:intrinsics"
import "core:math"
import alg "core:math/linalg"
import "core:sort"
import str "core:strings"
import "core:time"
import "core:unicode/utf8"
import gl "vendor:OpenGL"
import ma "vendor:miniaudio"

PI :: math.PI

Font_Size :: enum {
	xs = 0,
	s  = 1,
	m  = 2,
	l  = 3,
	xl = 4,
}

UI_Element_Type :: enum {
	Regular,
	Text,
	Waveform_Data,
	Circle,
	Fader_Knob,
	Audio_Spectrum,
	Background = 15,
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
	ui_element_type:      UI_Element_Type,
	font_size:            Font_Size,
	clip_tl:              Vec2_f32,
	clip_br:              Vec2_f32,
	rotation_radians:     f32,
}

// Kind of the default data when turning an abstract box into an opengl rect.
get_default_rendering_data :: proc(box: Box) -> Rect_Render_Data {
	color := ui_state.dark_theme[box.config.color]
	data: Rect_Render_Data = {
		top_left         = {f32(box.top_left.x), f32(box.bottom_right.y)},
		bottom_right     = {f32(box.bottom_right.x), f32(box.bottom_right.y)},
		// idrk the winding order for colors, this works tho.
		tl_color         = color,
		tr_color         = color,
		bl_color         = color,
		br_color         = color,
		corner_radius    = 0,
		edge_softness    = 0,
		border_thickness = 1000000,
		// clip_tl          = box.clipping_container.top_left,
		// clip_br          = box.clipping_container.bottom_right,
	}
	return data
}

@(private = "file")
box_coord_to_vec2f32 :: proc(coord: [2]int) -> Vec2_f32 {
	return Vec2_f32{f32(coord.x), f32(coord.y)}
}


Boxes_Rendering_Data :: struct {
	additional_data: [dynamic]Rect_Render_Data,
	box:             Maybe(Rect_Render_Data),
	overlay:         Maybe(Rect_Render_Data),
	outer_shadow:    Maybe(Rect_Render_Data),
	inner_shadow:    Maybe(Rect_Render_Data),
	text_cursor:     Maybe(Rect_Render_Data),
}


@(private = "file")
distance :: proc(a, b: [2]$T) -> f32 where intrinsics.type_is_numeric(T) {
	// distance = sqrt((x2 - x1)² + (y2 - y1)²)
	return math.sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y))
}

// sets circumstantial (hovering, clicked, etc) rendering data like radius, borders, etc
/* Returns:
1st: The render data for the passed in box.
2nd: A list of related things like borders, shadows, etc.
3rd: An overlay (for example to grey out a disabled track)
*/
get_boxes_rendering_data :: proc(box: Box, allocator := context.allocator) -> Boxes_Rendering_Data {
	additional_render_data := make([dynamic]Rect_Render_Data, context.temp_allocator)
	result := Boxes_Rendering_Data {
		additional_data = additional_render_data,
	}

	color := ui_state.dark_theme[box.config.color]

	if .Line in box.flags {
		// A bit of trig to work shit out for the line. Since top_left and bottom_right,
		// form a rectangle, we can cut it in half to get 2 equal triangles and use
		// basic trig to work out the rotation angle to pass to the GPU.
		start := box.config.line_start
		end := box.config.line_end
		center := (start + end) * 0.5
		// Classic pythagoras.
		length := distance(start, end)
		angle := math.atan2(end.y - start.y, end.x - start.x)
		thickness := f32(box.config.line_thickness)

		// In the rest of our UI: box.tl < box.br is always true. This doesn't hold for
		// lines where start < end isn't always true. Thus we must construct a valid quad
		// for our line from scratch based on the other things we know about the line.
		half_size := Vec2_f32{length / 2, thickness / 2}
		top_left := center - half_size
		bottom_right := center + half_size

		line_render_data: Rect_Render_Data = {
			top_left         = top_left,
			bottom_right     = bottom_right,
			tl_color         = color,
			tr_color         = color,
			bl_color         = color,
			br_color         = color,
			corner_radius    = f32(box.config.corner_radius),
			edge_softness    = f32(box.config.edge_softness),
			border_thickness = 100000,
			rotation_radians = angle,
			// clip_tl          = box.clipping_container.top_left,
			// clip_br          = box.clipping_container.bottom_right,
		}
		result.box = line_render_data
		return result
	}

	box_render_data: Rect_Render_Data = {
		top_left         = box_coord_to_vec2f32(box.top_left),
		bottom_right     = box_coord_to_vec2f32(box.bottom_right),
		// idrk the winding order for colors, this works tho.
		tl_color         = color,
		tr_color         = color,
		bl_color         = color,
		br_color         = color,
		corner_radius    = f32(box.config.corner_radius),
		edge_softness    = f32(box.config.edge_softness),
		border_thickness = 100000,
		clip_tl 		 = vec2_f32(box.clip_tl),
		clip_br			 = vec2_f32(box.clip_br)
	}

	if box.parent != nil && box.parent.config.overflow_y != .Visible {
		box_render_data.clip_tl = vec2_f32(box.parent.top_left)
		box_render_data.clip_br = vec2_f32(box.parent.bottom_right)
	}

	// Cheap and dirty way to anti alias non squared off edges. Not as good as real anti-aliasing of course.
	if box_render_data.corner_radius > 0 && box_render_data.edge_softness == 0 {
		box_render_data.edge_softness = 0.7
	}

	if box.disabled {
		// Color selection here is iffy, we can't always use some complement of the base color,
		// because different siblings can have different colors, but you want the 'disabled' look to
		// be uniform. For now we'll just pick a random color.
		color := Color_RGBA{0, 0, 0, -0.17} + ui_state.dark_theme[Semantic_Color_Token.Inactive]
		data := Rect_Render_Data {
			tl_color     = color,
			tr_color     = color,
			bl_color     = color,
			br_color     = color,
			top_left     = vec2_f32(box.top_left),
			bottom_right = vec2_f32(box.bottom_right),
		}
		result.overlay = data
	}

	if box.signals.hovering && .Clickable in box.flags {
		// Create frosted glass overlay.
		if .Hot_Animation in box.flags && !box.signals.pressed {
			glass_overlay := Rect_Render_Data {
				top_left         = box_coord_to_vec2f32(box.top_left),
				bottom_right     = box_coord_to_vec2f32(box.bottom_right),
				// Graident from semi-transparent white to transparent at bottom
				tl_color         = {1, 1, 1, 0.05},
				tr_color         = {1, 1, 1, 0.05},
				bl_color         = {1, 1, 1, 0.4},
				br_color         = {1, 1, 1, 0.4},
				corner_radius    = f32(box.config.corner_radius),
				edge_softness    = 1.5, // subtle glow
				border_thickness = 10000,
			}

			// Create drop shadow for depth
			shadow := Rect_Render_Data {
				top_left         = box_coord_to_vec2f32(box.top_left) + {4, 4}, // Offset for shadow
				bottom_right     = box_coord_to_vec2f32(box.bottom_right) + {4, 4},
				tl_color         = {0, 0, 0, 0.3},
				tr_color         = {0, 0, 0, 0.3},
				bl_color         = {0, 0, 0, 0.6},
				br_color         = {0, 0, 0, 0.6},
				corner_radius    = box_render_data.corner_radius,
				edge_softness    = 3.0, // Soft shadow
				border_thickness = 10000,
			}
			result.outer_shadow = shadow
			result.overlay = glass_overlay
		} else if .Active_Animation in box.flags && box.signals.pressed {
			glass_overlay := Rect_Render_Data {
				top_left         = box_coord_to_vec2f32(box.top_left),
				bottom_right     = box_coord_to_vec2f32(box.bottom_right),
				// Graident from semi-transparent white to transparent at bottom
				tl_color         = {1, 1, 1, 0.2},
				tr_color         = {1, 1, 1, 0.2},
				bl_color         = {1, 1, 1, 0.05},
				br_color         = {1, 1, 1, 0.05},
				corner_radius    = f32(box.config.corner_radius),
				edge_softness    = 1.5, // subtle glow
				border_thickness = 10000,
			}
			result.overlay = glass_overlay

			// Inner shadow (render AFTER the main element)
			inner_shadow := Rect_Render_Data {
				top_left         = box_coord_to_vec2f32(box.top_left),
				bottom_right     = box_coord_to_vec2f32(box.bottom_right),
				tl_color         = {0, 0, 0, 0.3},
				tr_color         = {0, 0, 0, 0.2},
				bl_color         = {0, 0, 0, 0.2},
				br_color         = {0, 0, 0, 0.15},
				corner_radius    = box_render_data.corner_radius,
				edge_softness    = 3.0,
				border_thickness = 10000,
			}
			result.inner_shadow = inner_shadow
			// Darken the main element
			// box_render_data.tl_color *= 0.9
			// box_render_data.tr_color *= 0.9
			// box_render_data.bl_color *= 0.9
			// box_render_data.br_color *= 0.9
		}
	}
	// ------ These come after adding the main rect data since they have a higher 'z-order'.

	text_cursor_render: {
		// Uses some heuristic time based property to determine if text cursor
		// should be showing or not. Ultimately achieving blinking.
		should_render_text_cursor :: proc() -> bool {
			time_in_ms := time.now()._nsec / 1_000_000
			// On for 0.5 second, off for a 0.5 a second
			return (time_in_ms % (800)) < 500
		}
		// Tells you where the cursor should render. This function will need to be updated
		// when we include various types of text positioning, right now all text is centered by default.
		calc_cursor_pos :: proc(box: Box, text: string) -> int {
			editor_state := ui_state.text_editors_state[box.id]
			cursor_pos := editor_state.selection[0]
			substr_len := font_get_strings_rendered_len(text[0:cursor_pos])
			// Calculate offset gap between left edge of box and start of rendered text.
			half_gap := (box.width - font_get_strings_rendered_len(text)) / 2
			return box.top_left.x + half_gap + substr_len
		}
		// Add cursor inside text box. Blinking is kinda jank right now.
		if .Edit_Text in box.flags &&
		   should_render_text_cursor() &&
		   ui_state.last_active_box != nil &&
		   ui_state.last_active_box.id == box.id {
			box_data_string := box_data_as_string(box.data, context.temp_allocator)
			color := Color_RGBA{0, 0.5, 1, 1}
			cursor_x_pos := f32(calc_cursor_pos(box, box_data_string))
			cursor_data := Rect_Render_Data {
				top_left         = {cursor_x_pos, f32(box.top_left.y)},
				bottom_right     = {cursor_x_pos + 2.4, f32(box.bottom_right.y)},
				bl_color         = color,
				tl_color         = color,
				br_color         = color,
				tr_color         = color,
				border_thickness = 300,
				corner_radius    = 0,
			}
			result.text_cursor = cursor_data
		}
	}

	// Need to figure out how to make my SDL hollow stuff work with independantly sized sides of a border.
	// Previously you could just have borders on or off
	if box.config.border > 0 {
		top_color := ui_state.dark_theme[.Outline]
		// printfln("box {} has a border of thickness: {}", box.id, box.config.border)
		border_rect := box_render_data
		border_rect.border_thickness = f32(box.config.border)
		border_rect.border_thickness = 1
		border_rect.tl_color = top_color
		border_rect.tr_color = top_color
		border_rect.bl_color = top_color
		border_rect.br_color = top_color
		if box.signals.hovering {
			hover_color := ui_state.dark_theme[.Warning_Container]
			border_rect.tl_color = hover_color
			border_rect.tr_color = hover_color
			border_rect.bl_color = hover_color
			border_rect.br_color = hover_color
			border_rect.border_thickness = 2
		}
		append(&result.additional_data, border_rect)
	}

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

	if metadata, ok := box.metadata.(Metadata_Audio_Spectrum); ok{ 
		box_render_data.ui_element_type = .Audio_Spectrum
		// re-purpose this vertex attribute to indicate which row the pixel shader should sample from.
		box_render_data.texture_top_left = ({f32(metadata.track_num), f32(metadata.track_num)})
		// Update GPU texture so it can render whatever new audio data we have.
		data := app.audio.tracks[metadata.track_num].eq.frequency_spectrum_bins
		gl.ActiveTexture(gl.TEXTURE1)
		gl.BindTexture(gl.TEXTURE_2D, ui_state.frequency_spectrum_texture_id)
		gl.TexSubImage2D(
			gl.TEXTURE_2D,
			0, 			// mip level
			0, i32(metadata.track_num), // x, y offset
			512,
			1,
			gl.RED,
			gl.FLOAT,
			raw_data(data[:])
		)
	}

	if .Draw in box.flags {
		result.box = box_render_data
	}

	return result
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

// Assumes pcm_frames is from a mono version of the .wav file, BOLD assumption.
// Might need to cache calls to this function since it's pretty costly.
add_waveform_rendering_data :: proc(
	box: Box,
	track: Track,
	pcm_frames: [dynamic]f32,
	rendering_data: ^[dynamic]Rect_Render_Data,
) {
	sound := track.sound
	if sound == nil {
		return
	}
	printfln("inside waveform rendering function, sampler.zoom_point is: {}", track.sampler.zoom_point)
	// render_width := rect_width(rect)
	render_width := f32(box.last_width)
	// render_height := rect_height(rect)
	render_height := f32(box.last_height)
	frames_read := u64(len(pcm_frames))
	wav_rendering_data := make([dynamic]Rect_Render_Data, u32(render_width), allocator = context.temp_allocator)
	sampler := track.sampler
	// might break with very large samples.
	visible_width := f64(frames_read) * f64(1 - sampler.zoom_amount)


	// New CLAUDE fix for correct zooming.
	start_sample := u64(f64(sampler.zoom_point) * f64(frames_read))
	end_sample := start_sample + u64(visible_width)

	// Clamp to valid range
	start_sample = max(u64(0), start_sample)
	end_sample = min(u64(frames_read), end_sample)

	// Figure out how much of the sound has played.
	pos_in_track: u64
	if ma.sound_get_cursor_in_pcm_frames(sound, &pos_in_track) != .SUCCESS {
		panic("failed to get cursor position of sound")
	}

	played_color := ui_state.dark_theme[Semantic_Color_Token.Secondary]
	unplayed_color := ui_state.dark_theme[Semantic_Color_Token.Secondary]
	for x in 0 ..< render_width {
		ratio_of_waveform := f64(x) / f64(render_width)
		start := start_sample + u64((f64(x) / f64(render_width)) * (f64(end_sample - start_sample)))
		end := start_sample + u64((f64(x + 1) / f64(render_width)) * (f64(end_sample - start_sample)))
		if end >= frames_read {end = frames_read}
		min: f32 = 1
		max: f32 = -1
		for i in start ..< end {
			if pcm_frames[i] < min {min = pcm_frames[i]}
			if pcm_frames[i] > max {max = pcm_frames[i]}
		}
		norm_x: f32 = f32(x) / f32(render_width)
		x_pos := f32(box.top_left.x) + norm_x * render_width
		y_top := f32(box.top_left.y) + (0.5 - max * 0.5) * render_height
		y_bot := f32(box.top_left.y) + (0.5 - min * 0.5) * render_height
		new_data := Rect_Render_Data {
			border_thickness = 300,
			corner_radius    = 0,
			edge_softness    = 0,
			top_left         = Vec2_f32{x_pos - 0.5, y_top},
			bottom_right     = Vec2_f32{x_pos + 0.5, y_bot},
			// ui_element_type  = 2.0,
		}
		if end <= pos_in_track {
			new_data.tl_color = played_color
			new_data.tr_color = played_color
			new_data.bl_color = played_color
			new_data.br_color = played_color
		} else {
			new_data.tl_color = unplayed_color
			new_data.tr_color = unplayed_color
			new_data.bl_color = unplayed_color
			new_data.br_color = unplayed_color
		}
		new_data.clip_tl = {0, 0}
		new_data.clip_br = {f32(app.wx), f32(app.wy)}
		append(rendering_data, new_data)
	}
}

collect_render_data_from_ui_tree :: proc(render_data: ^[dynamic]Rect_Render_Data) {
	box_list := box_tree_to_list_complex(ui_state.root, context.temp_allocator)
	sort.merge_sort_proc(box_list[:], proc(a, b: ^Box) -> int {
		if a.z_index < b.z_index {
			return -1
		} else if a.z_index > b.z_index {
			return 1
		} else {
			return 0
		}
	})

	for box in box_list {
		boxes_render_data := get_boxes_rendering_data(box^, context.temp_allocator)

		if shadow, ok := boxes_render_data.outer_shadow.(Rect_Render_Data); ok {
			append(render_data, shadow)
		}

		// Some boxes may not need to be rendered themselves, but their related data to that box may need to be rendered.
		// Hence the conditional.
		if box_data, ok := boxes_render_data.box.(Rect_Render_Data); ok {
			append(render_data, box_data)
			
		}

		for data in boxes_render_data.additional_data {
			append(render_data, data)
		}


		if inner_shadow, ok := boxes_render_data.inner_shadow.(Rect_Render_Data); ok {
			append(render_data, inner_shadow)
		}

		draw_text: if .Draw_Text in box.flags {
			// gl.ActiveTexture(gl.TEXTURE0)
			// gl.BindTexture(gl.TEXTURE_2D, ui_state.font_atlas_texture_id)
			text_to_render: string
			if .Edit_Text in box.flags {
				text_to_render = box_data_as_string(box.data, context.temp_allocator)
			} else {
				text_to_render = box.label
			}
			if .Track_Step in box.flags {
				if !box.selected {
					break draw_text
				}
			}
			text := utf8.string_to_runes(text_to_render, context.temp_allocator)
			shaped_glyphs := font_segment_and_shape_text(&ui_state.font_state.kb.font, text)
			glyph_render_info := font_get_render_info(shaped_glyphs, context.temp_allocator)
			glyph_rects := get_text_quads(box^, glyph_render_info[:], context.temp_allocator)
			for rect in glyph_rects {
				append_elem(render_data, rect)
			}
		}

		if text_cursor, ok := boxes_render_data.text_cursor.(Rect_Render_Data); ok {
			append(render_data, text_cursor)
		}

		if metadata, ok := box.metadata.(Metadata_Sampler); ok {
			track := app.audio.tracks[metadata.track_num]
			add_waveform_rendering_data(box^, track, track.pcm_data.left_channel, render_data)
		}
		if overlay, ok := boxes_render_data.overlay.(Rect_Render_Data); ok {
			append(render_data, overlay)
		}

	}
}

/*
Returns the quads which we will sample the font pixels into. 
This is probably where I'd implement subpixel positioning and stuff, but for now
we just naively wrap to the nearest int.
*/

// NOTE! character quads aren't positioned correctly, refer to claude chat as to how
// we can fix it.
get_text_quads :: proc(
	box: Box,
	glyph_buffer: []Glyph_Render_Info,
	allocator := context.allocator,
) -> [dynamic]Rect_Render_Data {
	// Calculate baseline: (for now we just center text on both axis inside the box)
	tallest_char := font_get_glyphs_tallest_glyph(glyph_buffer)
	rendered_len := font_get_glyphs_rendered_len(glyph_buffer)
	vertical_diff_half := (box.height - int(tallest_char)) / 2
	horizontal_diff_half := (box.width - int(rendered_len)) / 2
	// Really only the first point in baseline, which is all we need.
	baseline_x, baseline_y: int
	switch box.config.text_justify.x {
	case .Center:
		baseline_x = box.top_left.x + int(horizontal_diff_half)
	case .Start:
		baseline_x = box.top_left.x + box.config.padding.left
	case .End:
		baseline_x = box.bottom_right.x - (box.config.padding.right + rendered_len)
	}
	switch box.config.text_justify.y {
	case .Center:
		// baseline_y = box.top_left.y + int(vertical_diff_half)
		baseline_y = box.bottom_right.y - int(vertical_diff_half)
	case .Start:
		baseline_y = box.top_left.y + box.config.padding.top
	case .End:
		baseline_y = box.bottom_right.y - (box.config.padding.bottom + tallest_char)
	}
	pen_x := baseline_x
	// Doesn't need to be dynamically sized but static allocated size may confuse user.
	glyph_rects := make([dynamic]Rect_Render_Data, len(glyph_buffer), allocator)
	atlas_width := ui_state.font_state.atlas.row_width
	atlas_height := ui_state.font_state.atlas.num_rows
	for glyph, i in glyph_buffer {
		cache_record := glyph.cache_record
		final_x := f32(baseline_x) + glyph.pos.x
		final_y := f32(baseline_y) + glyph.pos.y
		descent := cache_record.height - cache_record.bearing_y // Descent below baseline.
		tex_tl_x := f32(cache_record.atlas_x) / f32(atlas_width)
		tex_tl_y := f32(cache_record.atlas_y) / f32(atlas_height)
		tex_br_x := f32(cache_record.atlas_x + cache_record.width) / f32(atlas_width)
		tex_br_y := f32(cache_record.atlas_y + cache_record.height) / f32(atlas_height)
		text_color := get_text_color_from_base(box.config.color)
		data := Rect_Render_Data {
			top_left             = {final_x + f32(cache_record.bearing_x), final_y - f32(cache_record.bearing_y)},
			bottom_right         = {
				final_x + f32(cache_record.bearing_x + cache_record.width),
				final_y + f32(descent),
			},
			texture_top_left     = Vec2_f32{tex_tl_x, tex_tl_y},
			texture_bottom_right = Vec2_f32{tex_br_x, tex_br_y},
			border_thickness     = 500,
			tl_color             = text_color,
			tr_color             = text_color,
			bl_color             = text_color,
			br_color             = text_color,
			ui_element_type      = .Text,
			clip_tl				 = vec2_f32(box.clip_tl),
			clip_br				 = vec2_f32(box.clip_br),
		}
		// Set clipping rect for text.
		// if box.parent != nil && box.parent.config.overflow_y != .Visible {
		// 	data.clip_tl = vec2_f32(box.parent.top_left)
		// 	data.clip_br = vec2_f32(box.parent.bottom_right)
		// }
		glyph_rects[i] = data
	}

	


	return glyph_rects
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

draw :: proc(n_vertices: i32, indices: [^]u32) {
	gl.DrawElements(gl.TRIANGLES, n_vertices, gl.UNSIGNED_INT, indices)
}

setup_for_quads :: proc(shader_program: ^u32) {
	//odinfmt:disable
	gl.BindVertexArray(ui_state.quad_vabuffer^)
	// bind_shader(shader_program^)

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

	gl.VertexAttribPointer(15, 1, gl.FLOAT, false, size_of(Rect_Render_Data), offset_of(Rect_Render_Data, rotation_radians))
	enable_layout(15)
	gl.VertexAttribDivisor(15, 1)

	//odinfmt:enable
}

clear_screen :: proc() {
	color := ui_state.dark_theme[.Inverse_On_Surface]
	gl.ClearColor(color.r, color.g, color.b, color.a)
	gl.Clear(gl.COLOR_BUFFER_BIT)
}

@(private = "file")
// The material color palette generates text colors that go ontop of the base colors,
// so this function just pulls that out
get_text_color_from_base :: proc(color_token: Semantic_Color_Token) -> Color_RGBA {
	#partial switch color_token {
	case .Primary:
		return ui_state.dark_theme[.On_Primary]
	case .Secondary:
		return ui_state.dark_theme[.On_Secondary]
	case .Tertiary:
		return ui_state.dark_theme[.On_Tertiary]
	case .Background:
		return ui_state.dark_theme[.On_Background]
	case .Inactive:
		return ui_state.dark_theme[.On_Inactive]
	case .Error:
		return ui_state.dark_theme[.On_Error]
	case .Primary_Container:
		return ui_state.dark_theme[.On_Primary_Container]
	case .Secondary_Container:
		return ui_state.dark_theme[.On_Secondary_Container]
	case .Tertiary_Container:
		return ui_state.dark_theme[.On_Tertiary_Container]
	case .Error_Container:
		return ui_state.dark_theme[.On_Error_Container]
	case .Surface:
		return ui_state.dark_theme[.On_Surface]
	case .Surface_Variant:
		return ui_state.dark_theme[.On_Surface_Variant]
	case .Warning:
		return ui_state.dark_theme[.On_Warning]
	case .Warning_Container:
		return ui_state.dark_theme[.On_Warning_Container]
	}
	panic(tprintf("We haven't defined a mapping for a text color that sits on top of base color {}", color_token))
}
