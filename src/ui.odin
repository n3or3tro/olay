package main
import gl "vendor:OpenGL"
import sdl "vendor:sdl2"
import "core:mem"

init_ui_state :: proc() -> ^UI_State {
	// app.wx = new(i32)
	// app.wy = new(i32)

	ui_state.quad_vbuffer = new(u32)
	ui_state.quad_vabuffer = new(u32)

	// ui_state.rect_stack = make([dynamic]^Rect)
	ui_state.color_stack = make([dynamic]Color)
	// append(&ui_state.rect_stack, ui_state.root_rect)
	ui_state.box_cache = make(map[string]^Box)
	ui_state.temp_boxes = make([dynamic]^Box)
	ui_state.next_frame_signals = make(map[string]Box_Signals)
	// ui_state.clipping_stack = make([dynamic]^Rect)
	ui_state.first_frame = true
	ui_state.text_box_padding = 10
	ui_state.steps_value_allocator = mem.arena_allocator(&ui_state.steps_value_arena)
	// mem.arena_init(&ui_state.steps_value_arena, steps_arena_buffer[:])

	gl.GenVertexArrays(1, ui_state.quad_vabuffer)
	create_vbuffer(ui_state.quad_vbuffer, nil, 700_000)

	program1, quad_shader_ok := gl.load_shaders_source(string(ui_vertex_shader_data), string(ui_pixel_shader_data))
	assert(quad_shader_ok)
	ui_state.quad_shader_program = program1

	bind_shader(ui_state.quad_shader_program)
	// Did it this way because was getting bugs with layout being wrong when using tiling WM on windows.
	actual_w, actual_h: i32
	sdl.GetWindowSize(app.window, &actual_w, &actual_h)

	// Use the ACTUAL size to set the shader uniform for the first time.
	set_shader_vec2(ui_state.quad_shader_program, "screen_res", {f32(actual_w), f32(actual_h)})
	// set_shader_vec2(ui_state.quad_shader_program, "screen_res", {f32(WINDOW_WIDTH), f32(WINDOW_HEIGHT)})
	setup_for_quads(&ui_state.quad_shader_program)

	wx: i32 = 0
	wy: i32 = 0
	sdl.GetWindowSize(app.window, &wx, &wy)
	app.wx, app.wy = int(wx), int(wy)
	ui_state.frame_num = 0
	return ui_state
}

create_ui :: proc() -> ^Box {
	// root := box_from_cache("root@root", {}, {semantic_size = {{.Fixed, f32(app.wx)}, {.Fixed, f32(app.wy)}}})
	root := box_from_cache("root@root", {}, {semantic_size = {{.Fixed, f32(app.wx)}, {.Fixed, f32(app.wy)}}})
	box_open_children(root, {direction = .Horizontal, gap_horizontal = 10})

	first_part: {
		container := container("ha@container1", {semantic_size = {{.Grow, 1}, {.Grow, 1}}})
		box_open_children(container.box, {direction = .Horizontal, gap_horizontal = 10})
		defer box_close_children(container.box)

		button_text(
			"button1@button1",
			{background_color = {0, 0, 1, 1}, corner_radius = 2, semantic_size = {{.Grow, 1}, {.Grow, 1}}},
		)
		button_text(
			"button2@button2",
			{background_color = {0, 0, 1, 1}, corner_radius = 2, semantic_size = {{.Grow, 1}, {.Grow, 1}}},
		)
	}

	second_part: {
		container_2 := container("ha@container2", {semantic_size = {{.Grow, 1}, {.Grow, 1}}})
		box_open_children(container_2.box, Box_Child_Layout{direction = .Vertical, gap_vertical = 10})
		defer box_close_children(container_2.box)

		button_text(
			"button3@button3",
			{background_color = {0, 1, 0, 1}, corner_radius = 2, semantic_size = {{.Grow, 1}, {.Grow, 1}}},
		)
		button_text(
			"button4@button4",
			{background_color = {0, 1, 0, 1}, corner_radius = 2, semantic_size = {{.Grow, 1}, {.Grow, 1}}},
		)
	}
	third_part: {
		container_3 := container("ha@container3", {semantic_size = {{.Fixed, 100}, {.Fixed, 30}}})
		box_open_children(container_3.box, Box_Child_Layout{direction = .Vertical, gap_vertical = 10})
		defer box_close_children(container_3.box)

		button_text(
			"button3@button5",
			{background_color = {1, 0, 0, 1}, corner_radius = 2, semantic_size = {{.Grow, 1}, {.Grow, 1}}},
		)
		button_text(
			"button4@button6",
			{background_color = {1, 0, 0, 1}, corner_radius = 2, semantic_size = {{.Grow, 1}, {.Grow, 1}}},
		)
	}

	box_close_children(root)
	sizing_grow_growable_height(root)
	sizing_grow_growable_width(root)
	position_boxes(root)
	return root
}
