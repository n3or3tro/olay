package app
import "core:fmt"
import "core:mem"
import "core:time"
import gl "vendor:OpenGL"
import sdl "vendor:sdl2"

id :: fmt.tprintf
UI_State :: struct {
	box_cache:             map[string]^Box,
	// I.e. the node which will parent future children if children_open() has been called.
	parents_top:           ^Box,
	parents_stack:         [dynamic]^Box,
	settings_toggled:      bool,
	color_stack:           [dynamic]Color,
	// ui_scale:              f32, // between 0.0 and 1.0.
	// Used to tell the core layer to override some valu of a box that's in the cache.
	// Useful for parts of the code where the box isn't easilly accessible (like in audio related stuff).
	override_color:        bool,
	override_rect:         bool,
	quad_vbuffer:          ^u32,
	quad_vabuffer:         ^u32,
	quad_shader_program:   u32,
	font_atlas_texture_id: u32,
	// root_rect:             ^Rect,
	frame_num:             u64,
	hot_box:               ^Box,
	active_box:            ^Box,
	selected_box:          ^Box,
	last_hot_box:          ^Box,
	last_active_box:       ^Box,
	z_index:               i16,
	right_clicked_on:      ^Box,
	// wav_rendering_data:    map[ma.sound][dynamic]Rect_Render_Data,
	// the visual space between border of text box and the text inside.
	text_box_padding:      u16,
	keyboard_mode:         bool,
	last_clicked_box:      ^Box,
	last_clicked_box_time: time.Time,
	next_frame_signals:    map[string]Box_Signals,
	// Used to help with the various bugs I was having related to input for box.value and mutating box.value.
	steps_value_arena:     mem.Arena,
	steps_value_allocator: mem.Allocator,
	// Helps to stop clicks registering when you start outside an element and release on top of it.
	mouse_down_on:         ^Box,
	context_menu:          struct {
		// pos:                   Vec2,
		active:                bool,
		show_fill_note_menu:   bool,
		show_remove_note_menu: bool,
		show_add_step_menu:    bool,
		show_remove_step_menu: bool,
	},
	steps_vertical_offset: u32,
	font_state:            Font_State,
	// Used to calculate clipping rects and nested clipping rects for overflowing content.
	// clipping_stack:        [dynamic]^Rect,
}

init_ui_state :: proc() -> ^UI_State {
	ui_state.quad_vbuffer = new(u32)
	ui_state.quad_vabuffer = new(u32)

	ui_state.color_stack = make([dynamic]Color)
	ui_state.box_cache = make(map[string]^Box)
	ui_state.next_frame_signals = make(map[string]Box_Signals)
	// ui_state.clipping_stack = make([dynamic]^Rect)

	wx: i32 = 0
	wy: i32 = 0
	sdl.GetWindowSize(app.window, &wx, &wy)
	app.wx, app.wy = int(wx), int(wy)

	ui_state.frame_num = 0
	ui_state.text_box_padding = 10

	// ui_state.steps_value_allocator = mem.arena_allocator(&ui_state.steps_value_arena)
	// mem.arena_init(&ui_state.steps_value_arena, steps_arena_buffer[:])

	font_init(&ui_state.font_state, 32)

	gl.GenVertexArrays(1, ui_state.quad_vabuffer)
	create_vbuffer(ui_state.quad_vbuffer, nil, 700_000)

	shader_program_id, quad_shader_ok := gl.load_shaders_source(
		string(ui_vertex_shader_data),
		string(ui_pixel_shader_data),
	)
	assert(quad_shader_ok)
	ui_state.quad_shader_program = shader_program_id

	// Setup shader.
	bind_shader(ui_state.quad_shader_program)
	// Did it this way because was getting bugs with layout being wrong when using tiling WM on windows.
	actual_w, actual_h: i32
	sdl.GetWindowSize(app.window, &actual_w, &actual_h)
	set_shader_vec2(ui_state.quad_shader_program, "screen_res", {f32(actual_w), f32(actual_h)})
	setup_for_quads(&ui_state.quad_shader_program)

	// Setup font texture atlas.
	atlas_texture_id: u32
	gl.GenTextures(1, &atlas_texture_id)
	gl.BindTexture(gl.TEXTURE_2D, atlas_texture_id)

	gl.TexImage2D(
		gl.TEXTURE_2D, // target
		0, // level (mipmap)
		gl.R8, // internal format (8 bit red channel is most efficient apparently)
		1024, // width
		1024, // height
		0, // border
		gl.RED, // format of pixel data, i.e. where it looks to find the pixel info.
		gl.UNSIGNED_BYTE, // type of pixel data.
		nil, // data -> nil as it's empty until we start rendering text.
	)

	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)

	ui_state.font_atlas_texture_id = atlas_texture_id
	return ui_state
}

create_ui :: proc() -> ^Box {
	// This is the first step of the mark and sweep, any boxes which are not re-created this frame, will
	// be removed from the cache at the end of the frame.
	for key, box in ui_state.box_cache {
		box.keep = false
	}
	root := box_from_cache("root@root", {}, {semantic_size = {{.Fixed, f32(app.wx)}, {.Fixed, f32(app.wy)}}})
	box_open_children(root, {direction = .Horizontal})


	// box_open_children(audio_track_containers.box, {gap_horizontal = 10, direction = .Horizontal})
	for i in 0 ..< 5 {
		audio_track(u32(i), 250)
	}
	// box_close_children(audio_track_containers.box)

	// second_part: {
	// 	container_2 := container("ha@container2", {semantic_size = {{.Grow, 1}, {.Grow, 1}}})
	// 	box_open_children(container_2.box, Box_Child_Layout{direction = .Horizontal, gap_vertical = 10})
	// 	defer box_close_children(container_2.box)

	// 	button_text(
	// 		tprintf("hey there {}@bitch", "nigga"),
	// 		{background_color = {0.3, 1, 0.5, 1}, corner_radius = 1, semantic_size = {{.Grow, 1}, {.Grow, 1}}},
	// 	)
	// 	button_text(
	// 		"button4@button4",
	// 		{background_color = {1, 1, 0, 0.5}, corner_radius = 2, semantic_size = {{.Grow, 1}, {.Grow, 1}}},
	// 	)
	// 	button_text(
	// 		"button4@button5",
	// 		{background_color = {1, 1, 0, 0.5}, corner_radius = 20, semantic_size = {{.Grow, 1}, {.Grow, 1}}},
	// 	)
	// 	{
	// 		other_container := container(
	// 			"a@other_container",
	// 			{background_color = {1, 1, 0, 0.5}, corner_radius = 2, semantic_size = {{.Grow, 1}, {.Grow, 1}}},
	// 		)
	// 		box_open_children(other_container.box, {direction = .Horizontal, gap_horizontal = 1})
	// 		defer box_close_children(other_container.box)
	// 		button_text(
	// 			"somehing@alskdjfafd",
	// 			{
	// 				semantic_size = {{type = .Fixed, amount = 100}, {type = .Fixed, amount = 30}},
	// 				background_color = {1, 1, 0.2, 1},
	// 			},
	// 		)
	// 	}
	// }

	// third_part: {
	// 	container_3 := container("ha@container3", {semantic_size = {{.Fixed, 100}, {.Fixed, 30}}})
	// 	box_open_children(container_3.box, Box_Child_Layout{direction = .Vertical, gap_vertical = 10})
	// 	defer box_close_children(container_3.box)

	// 	button_text(
	// 		"what@heyabutton5",
	// 		{background_color = {1, 0, 0, 1}, corner_radius = 2, semantic_size = {{.Grow, 1}, {.Grow, 1}}},
	// 	)
	// 	button_text(
	// 		"button4@button6",
	// 		{background_color = {1, 0, 0, 1}, corner_radius = 2, semantic_size = {{.Grow, 1}, {.Grow, 1}}},
	// 	)
	// }
	box_close_children(root)
	sizing_calc_percent_width(root)
	sizing_calc_percent_height(root)
	sizing_grow_growable_height(root)
	sizing_grow_growable_width(root)
	// sizing_calc_percent_width(root)
	// sizing_calc_percent_height(root)

	// resolve_layout(root)
	position_boxes(root)
	compute_frame_signals(root)
	return root
}
