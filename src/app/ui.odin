package app
import "core:fmt"
import "core:mem"
import "core:time"
import gl "vendor:OpenGL"
import sdl "vendor:sdl2"
// import"core:mem"

id :: fmt.tprintf
UI_State :: struct {
	box_cache:             map[string]^Box,
	// I.e. the node which will parent future children if children_open() has been called.
	parents_top:           ^Box,
	parents_stack:         [dynamic]^Box,
	settings_toggled:      bool,
	color_stack:           [dynamic]Color,
	quad_vbuffer:          ^u32,
	quad_vabuffer:         ^u32,
	quad_shader_program:   u32,
	font_atlas_texture_id: u32,
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
	last_clicked_box:      ^Box,
	last_clicked_box_time: time.Time,
	next_frame_signals:    map[string]Box_Signals,
	// Used to help with the various bugs I was having related to input for box.value and mutating box.value.
	steps_value_arena:     mem.Arena,
	steps_value_allocator: mem.Allocator,
	// Helps to stop clicks registering when you start outside an element and release on top of it.
	mouse_down_on:         ^Box,
	context_menu:          struct {
		pos:                   Vec2_f32,
		active:                bool,
		show_fill_note_menu:   bool,
		show_remove_note_menu: bool,
		show_add_step_menu:    bool,
		show_remove_step_menu: bool,
	},
	font_state:            Font_State,
	tab_num:               int,
	// Indicates whether we triggered anything that would cause us to swap UI screens
	// and therefore we need to clear the box cache.
	changed_ui_screen:     bool,
	// Maps text_boxes id's to text editing state. Neccessary when we have multiple
	// text boxes on screen at one time.
	text_editors_state:    map[string]Edit_Text_State,
	sidebar_shown:         bool,
	dragged_window:	       ^Box,
	drag_offset:	       [2]int,
	// Stores offset_from_parent for every draggable window. The whole draggable window thing will
	// break if we have a draggable window whose inside some box that ISNT the root. I.e. draggable windows
	// only work if they're declared as a direct child of the root.
	draggable_window_offsets : map[string][2]f32
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

	// ui_state.steps_value_allocator = mem.arena_allocator(&ui_state.steps_value_arena)
	// mem.arena_init(&ui_state.steps_value_arena, steps_arena_buffer[:])

	font_init(&ui_state.font_state, 18)

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

// Since I don't have any support for z-index stuff yet, I'm relying on a sort of painter algorithm,
// where the things I want on top of other things (if they're floating) must be created after the things
// they want to sit on top of. I.e. z-depth is kind of determined by creation order.
create_ui :: proc() -> ^Box {
	// This is the first step of the mark and sweep, any boxes which are not re-created this frame, will
	// be removed from the cache at the end of the frame.
	ui_state.changed_ui_screen = false
	for _, box in ui_state.box_cache {
		box.keep = false
	}
	// root: ^Box
	root := child_container(
		"root@root", 
		{
			semantic_size = {{.Fixed, f32(app.wx)}, {.Fixed, f32(app.wy)}}
		},
		{direction=.Vertical}
	).box
	root.keep = true
	topbar()
	if ui_state.tab_num == 0 {
		audio_tracks: {
			child_container(
				"@all-tracks-container",
				{
					semantic_size = {{.Fit_Children, 1}, 
					// We hardcode the height of the topbar otherwise the layout gets annoying.
					{.Fixed, f32(app.wy - TOPBAR_HEIGHT)}}
				},
				{
					direction = .Horizontal,
					gap_horizontal = 3
				}
			)

			for i in 0 ..< 5 {
				audio_track(u32(i), 250)
			}
		}
	} else {
		checkbox_res := multi_button_set("@test-radio-buttons", 
		{
			semantic_size = {{.Fit_Children, 1}, {.Fit_Children, 1}},
		}, 
		{
			direction =.Vertical,
			gap_horizontal = 20,
			gap_vertical = 10
		}, 
		false, []int{8,2,10,14,27, 4242, 23423, 123,4747})
		if len(checkbox_res) > 0 { 
			printfln("selection was: {}", checkbox_res[:])
		}
	}

	if ui_state.context_menu.active { 
		context_menu()
	}

	if ui_state.sidebar_shown {
		draggable_window("File browser@file-browser-dragging-container", {
			direction = .Vertical,
		})
		file_browser_menu()
	}

	sizing_calc_percent_width(root)
	sizing_calc_percent_height(root)
	sizing_grow_growable_height(root)
	sizing_grow_growable_width(root)
	recalc_fit_children_sizing(root)
	position_boxes(root)
	// Handle dragging the open window(s)
	if ui_state.dragged_window != nil { 
		container := ui_state.dragged_window
		actual_id := container.id

		mouse_delta_x := f32(app.mouse.pos.x - app.mouse_last_frame.pos.x) 
		mouse_delta_y := f32(app.mouse.pos.y - app.mouse_last_frame.pos.y) 

		// This will break if the containers parent width and height arent fixed / arent
		// calculated before the child is. Which is often the case with our bottom up sizing passes.
		width_diff := f32(container.parent.width - container.width)
		height_diff := f32(container.parent.height - container.height)


		// Given as a f32 from 0 - 1 since that's how floating box positioning works.
		parent_offset_delta_x:= f32(mouse_delta_x) / width_diff
		parent_offset_delta_y:= f32(mouse_delta_y) / height_diff

		ui_state.draggable_window_offsets[actual_id] += {parent_offset_delta_x, parent_offset_delta_y}
	} 
	flow_z_positions(root)
	compute_frame_signals(root)
	return root
}
