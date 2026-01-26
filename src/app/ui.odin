package app
import sarr "core:container/small_array"
import "core:encoding/json"
import "core:fmt"
import "core:mem"
import os "core:os/os2"
import "core:reflect"
import "core:strconv"
import str "core:strings"
import "core:time"
import "core:unicode/utf8/utf8string"
import gl "vendor:OpenGL"
import sdl "vendor:sdl2"

id :: fmt.tprintf

// Short hand pre-defined semantic_size values that we commonly use.
Size_Fit_Children :: [2]Box_Size{{.Fit_Children, 1}, {.Fit_Children, 1}}
Size_Fit_Children_And_Grow :: [2]Box_Size{{.Fit_Children_And_Grow, 1}, {.Fit_Children_And_Grow, 1}}
Size_Grow :: [2]Box_Size{{.Grow, 1}, {.Grow, 1}}
Size_Fit_Text :: [2]Box_Size{{.Fit_Text, 1}, {.Fit_Text, 1}}
Size_Fit_Text_And_Grow :: [2]Box_Size{{.Fit_Text_And_Grow, 1}, {.Fit_Text_And_Grow, 1}}

UI_State :: struct {
	root:                     ^Box,
	box_cache:                map[string]^Box,
	// I.e. the node which will parent future children if children_open() has been called.
	parents_top:              ^Box,
	parents_stack:            [dynamic]^Box,
	settings_toggled:         bool,
	color_stack:              [dynamic]Color_RGBA,
	quad_vbuffer:             ^u32,
	quad_vabuffer:            ^u32,
	quad_shader_program:      u32,
	font_atlas_texture_id:    u32,
	frame_num:                u64,
	hot_box:                  ^Box,
	active_box:               ^Box,
	selected_box:             ^Box,
	last_hot_box:             ^Box,
	last_active_box:          ^Box,
	z_index:                  i16,
	right_clicked_on:         ^Box,
	// wav_rendering_data:    map[ma.sound][dynamic]Rect_Render_Data,
	// the visual space between border of text box and the text inside.
	last_clicked_box:         ^Box,
	clicked_on_context_menu:  bool,
	last_clicked_box_time:    time.Time,
	// These are collected at the start of the frame, based on the UI tree from the end of the previous
	// frame, they can be used in the current frame, therefore no 1 frame delay.
	frame_signals:            map[string]Box_Signals,
	// Used to help with the various bugs I was having related to input for box.value and mutating box.value.
	steps_value_arena:        mem.Arena,
	steps_value_allocator:    mem.Allocator,
	// Helps to stop clicks registering when you start outside an element and release on top of it.
	mouse_down_on:            ^Box,
	context_menu:             struct {
		pos:                   Vec2_f32,
		active:                bool,
		show_fill_note_menu:   bool,
		show_remove_note_menu: bool,
		show_add_step_menu:    bool,
		show_remove_step_menu: bool,
	},
	font_state:               Font_State,
	tab_num:                  int,
	// Indicates whether we triggered anything that would cause us to swap UI screens
	// and therefore we need to clear the box cache.
	changed_ui_screen:        bool,
	// Maps text_boxes id's to text editing state. Neccessary when we have multiple
	// text boxes on screen at one time.
	text_editors_state:       map[string]Edit_Text_State,
	sidebar_shown:            bool,
	// If this is nil, it's because no box is being dragged.
	dragged_box:              Maybe(^Box),
	drag_offset:              [2]int,
	dropped_data:             [dynamic]Drop_Data,
	// Stores offset_from_parent for every draggable window. The whole draggable window thing will
	// break if we have a draggable window whose inside some box that ISNT the root. I.e. draggable windows
	// only work if they're declared as a direct child of the root.
	dark_theme:               Token_To_Color_Map,
	light_theme:              Token_To_Color_Map,
	draggable_window_offsets: map[string][2]f32,
	// Necessary shared state for animations.
	// animation_items:        sarr.Small_Array(32, Animation_Item),
	undo_stack:               [dynamic]State_Change,
	redo_stack:               [dynamic]State_Change,
	// Whether or not a track's eq is showing.
	eqs:                      [dynamic]bool,
	// Maps scrollable containers id to the amount of offset to apply to their scrolled children in px.
	scroll_offsets: map[string]int
}

// These are all the types of data that can be dropped on items that are drag-and-drop
// enabled.
Drop_Data :: union {
	Browser_File,
	string,
	int,
	f32,
}

State_Change_Type :: enum {
	Track_Step,
	Track_Volume,
	Track_Arm_State,
	// Old / new values will be the file path or maybe an index into locally loaded sounds.
	Track_Sound,
}

Track_Step_Change :: struct {
	type:      enum {
		Pitch,
		Volume,
		Send1,
		Send2,
	},
	track:     int,
	step:      int,
	old_value: int,
	new_value: int,
}

Track_Volume_Change :: struct {
	track, step: int,
	old_volume:  int,
	new_value:   int,
}

Track_Arm_State_Change :: struct {
	track, step: int,
	old_value:   bool,
	new_value:   bool,
}

Track_Sound_Change :: struct {
	track, step: int,
	old_value:   string,
	new_value:   string,
}


State_Change :: union {
	Track_Step_Change,
	Track_Volume_Change,
	Track_Arm_State_Change,
	Track_Sound_Change,
}


undo_stack_push :: proc(change: State_Change) {
	append(&ui_state.undo_stack, change)
	// Writing new data invalidates the redo stack. A viewable tree would perhaps be better
	// But this is what happens in basic undo / redo systems
	clear(&ui_state.redo_stack)
}

undo :: proc() {
	undo_stack := &ui_state.undo_stack
	if len(undo_stack) == 0 {
		return
	}
	event := pop(undo_stack)
	// printfln("len of undo stack: {}", len(ui_state.undo_stack))
	// printfln("undoing event: {}", event)
	switch change in event {
	case Track_Step_Change:
		switch change.type {
		case .Pitch:
			app.audio.tracks[change.track].pitches[change.step] = change.old_value
		case .Volume:
			app.audio.tracks[change.track].volumes[change.step] = change.old_value
		case .Send1:
			app.audio.tracks[change.track].send1[change.step] = change.old_value
		case .Send2:
			app.audio.tracks[change.track].send2[change.step] = change.old_value
		}
	case Track_Arm_State_Change:
	case Track_Volume_Change:
	case Track_Sound_Change:
	}
	append(&ui_state.redo_stack, event)
}

redo :: proc() {
	redo_stack := &ui_state.redo_stack
	if len(redo_stack) == 0 {
		return
	}
	event := pop(redo_stack)
	// printfln("len of redo stack: {}", len(ui_state.undo_stack))
	// printfln("redoing event: {}", event)
	switch change in event {
	case Track_Step_Change:
		switch change.type {
		case .Pitch:
			app.audio.tracks[change.track].pitches[change.step] = change.new_value
		case .Volume:
			app.audio.tracks[change.track].volumes[change.step] = change.new_value
		case .Send1:
			app.audio.tracks[change.track].send1[change.step] = change.new_value
		case .Send2:
			app.audio.tracks[change.track].send2[change.step] = change.new_value
		}
	case Track_Arm_State_Change:
	case Track_Volume_Change:
	case Track_Sound_Change:
	}
	append(&ui_state.undo_stack, event)
}

init_ui_state :: proc() -> ^UI_State {
	ui_state.quad_vbuffer = new(u32)
	ui_state.quad_vabuffer = new(u32)

	ui_state.color_stack = make([dynamic]Color_RGBA)
	ui_state.box_cache = make(map[string]^Box)
	ui_state.frame_signals = make(map[string]Box_Signals)
	// ui_state.clipping_stack = make([dynamic]^Rect)

	wx: i32 = 0
	wy: i32 = 0
	sdl.GetWindowSize(app.window, &wx, &wy)
	app.wx, app.wy = int(wx), int(wy)

	ui_state.frame_num = 0

	// Generate and store color theme:
	ui_state.dark_theme = parse_json_token_color_mapping("util/dark-theme.json")

	font_init(&ui_state.font_state, 18)

	gl.GenVertexArrays(1, ui_state.quad_vabuffer)
	create_vbuffer(ui_state.quad_vbuffer, nil, 3_000_000)

	shader_program_id, quad_shader_ok := gl.load_shaders_source(
		string(ui_vertex_shader_data),
		string(ui_pixel_shader_data),
	)
	if !quad_shader_ok {
		msg, type := gl.get_last_error_message()
		println(msg, type)
		panic("")
	}
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
	// Collect frame signals for this frame based on what the tree just looked like.
	if ui_state.frame_num > 1 {
		// Not sure if this is neccessary... turns out we crash if we do this, so disable it for now.
		// clear(&ui_state.frame_signals)
		collect_frame_signals(ui_state.root)
	}

	// This is the first step of the mark and sweep, any boxes which are not re-created this frame,
	// will be removed from the cache at the end of the frame.
	ui_start_time := time.now()._nsec
	for _, box in ui_state.box_cache {
		box.keep = false
	}

	ui_state.changed_ui_screen = false

	root := child_container(
		{
			semantic_size = {{.Fixed, f32(app.wx)}, {.Fixed, f32(app.wy)}},
			// color = .Inactive,
		},
		{direction = .Vertical},
		id = "root",
		box_flags = {.Draw},
	).box

	ui_state.root = root

	topbar()
	if ui_state.tab_num == 0 {
		audio_tracks: {
			num_column: {

			}
			
			child_container(
				{
					semantic_size = {
						{.Fit_Children, 1},
						// We hardcode the height of the topbar otherwise the layout gets annoying.
						{.Fixed, f32(app.wy - TOPBAR_HEIGHT)},
					},
				},
				{
					direction      = .Horizontal,
					gap_horizontal = 3,
				},
			)
			
			for track, i in app.audio.tracks {
				audio_track(i, 190)
			}
		}
		if text_button(
			"+",
			{
				floating_type = .Center_Right,
				padding       = {10, 10, 10, 10},
				border        = 2,
				semantic_size = {{.Fit_Text, 1}, {.Fit_Text, 1}},
				color         = .Warning,
			},
  		).clicked
		{
			track_add_new(app.audio)
		}

	}
	else {
		multi_button_set(
			{semantic_size = {{.Fit_Children, 1}, {.Fit_Children, 1}}},
			{direction = .Vertical, gap_horizontal = 20, gap_vertical = 10},
			false,
			[]int{8, 2, 10, 14, 27, 4242, 23423, 123, 4747},
			"test-radio-buttons",
			{},
			context.allocator,
		)

		child_container(
			{
				semantic_size = {{.Fixed, 500}, {.Fixed, 200}},
				overflow_x = .Scroll,
				overflow_y = .Scroll
			},
			{
				gap_horizontal = 10,
				direction = .Vertical,
			},
			box_flags = {.Draw, .Scrollable}
		)
		text_button("heya",  {semantic_size = {{.Fixed, 300}, {.Fixed, 250}}})
		text_button("there", {semantic_size = {{.Fixed, 300}, {.Fixed, 250}}})
		text_button("mate",  {semantic_size = {{.Fixed, 300}, {.Fixed, 250}}})
	}

	if ui_state.context_menu.active {
		context_menu()
	}

	if ui_state.sidebar_shown {
		_, closed := draggable_window("File browser", {direction = .Vertical}, "file-browser-dragging-container")
		if closed do ui_state.sidebar_shown = false
		file_browser_menu()
	}

	// Render current dragging item under the mouse if applicable.
	if ui_state.dragged_box != nil {
		dragged_box := ui_state.dragged_box.(^Box)
		if .Drag_Drop_Source in dragged_box.flags {
			// printfln("dragging: {}", dragged_box.id)
			// printfln("droppable data is: {}", ui_state.dropped_data[:])
			cfg := dragged_box.config
			cfg.floating_type = .Absolute_Pixel
			cfg.floating_offset = {f32(app.mouse.pos.x), f32(app.mouse.pos.y)}
			cfg.z_index = 100
			drag_ghost := box_from_cache({.Draw}, cfg, "the ghost", tprintf("{}-drag-ghost", dragged_box.id))
		}
	}

	// Draw helper text in the bottom right corner
	{
		child_container(
			{
				semantic_size       = Size_Fit_Children,
				color               = .Surface_Variant,
				floating_type       = .Relative_Parent,
				floating_anchor_box = ui_state.root,
				floating_offset     = {1, 1},
			},
			{
				direction            = .Vertical,
				alignment_horizontal = .Start,
				gap_vertical         = 5,
			},
			"helper-text-bottom-right",
		)

		text(
			"F5 -> Hot reload DLL, keep data",
			{
				color         = .Warning_Container,
				text_justify  = {.Start, .Center},
				semantic_size = Size_Fit_Text,
			},
			"helper-text-1",
		)

		text(
			"F3 -> Hot reload DLL, clear data",
			{
				color         = .Warning_Container,
				text_justify  = {.Start, .Center},
				semantic_size = Size_Fit_Text,
			},
		)

		text(
			"F1 -> Restart, keep DLL, clear data",
			{
				color         = .Warning_Container,
				text_justify  = {.Start, .Center},
				margin = {bottom = 5},
				semantic_size = Size_Fit_Text,
			},
			"helper-text-3",
		)
	}

	// animation_update_all()
	start := time.now()._nsec
	sizing_calc_percent_width(root)
	sizing_calc_percent_height(root)
	sizing_grow_growable_height(root)
	sizing_grow_growable_width(root)
	recalc_fit_children_sizing(root)
	position_boxes(root)

	end := time.now()._nsec
	total_layout_time := (end - start) / 1000

	flow_z_positions(root)

	ui_end_time := time.now()._nsec
	total_ui_creation_time := (ui_end_time - ui_start_time) / 1000
	// printfln("this frame took {} microseconds to create, layout and draw", total_ui_creation_time)
	return root
}

/* 
Reset state that was set in the current frame.
This is called at the end of every frame after all logical UI stuff has happened.
*/
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

	// if app.mouse_last_frame.clicked && !ui_state.clicked_on_context_menu {
	if app.mouse_last_frame.clicked {
		ui_state.context_menu.active = false
	}
	ui_state.clicked_on_context_menu = false

	// --- Sweep phase of mark and sweep box memory management ---

	// Collect keys to delete, can't iterate the map and delete in one loop I think....
	keys_to_delete := make([dynamic]string, context.temp_allocator)
	for key, box in ui_state.box_cache {
		if !box.keep {
			append(&keys_to_delete, key)
		}
	}

	for key in keys_to_delete {
		box := ui_state.box_cache[key]

		// Delete editor state related to box if it exists
		// if .Edit_Text in box.flags {
		// 	delete_key(&ui_state.text_editors_state, box.id)
		// }

		// delete(box.children) <-- was causing weird crashes, thought I'd leak memory without this, but seems to be fine.
		delete_key(&ui_state.box_cache, key)
		// delete(key)
		free(box)
	}

	clear(&ui_state.parents_stack)
	ui_state.parents_top = nil
}

// These are color tokens generated by the material color util we have. They map onto things like
// button color, button hover state, etc.
Semantic_Color_Token :: enum {
	Primary,
	On_Primary,
	Primary_Container,
	On_Primary_Container,
	Secondary,
	On_Secondary,
	Secondary_Container,
	On_Secondary_Container,
	Tertiary,
	On_Tertiary,
	Tertiary_Container,
	On_Tertiary_Container,
	Error,
	On_Error,
	Error_Container,
	On_Error_Container,
	Warning,
	On_Warning,
	Warning_Container,
	On_Warning_Container,
	Background,
	On_Background,
	Surface,
	On_Surface,
	Surface_Variant,
	On_Surface_Variant,
	Surface_Dim,
	Surface_Bright,
	Surface_Container_Lowest,
	Surface_Container_Low,
	Surface_Container,
	Surface_Container_High,
	Surface_Container_Highest,
	Outline,
	Outline_Variant,
	Inverse_Surface,
	Inverse_On_Surface,
	Inverse_Primary,
	Scrim,
	Shadow,
	Inactive,
	On_Inactive,
}

Token_To_Color_Map :: map[Semantic_Color_Token]Color_RGBA

parse_json_token_color_mapping :: proc(path: string, allocator := context.allocator) -> Token_To_Color_Map {
	file_data, err := os.read_entire_file_from_path(path, context.temp_allocator)
	if err != nil {
		panic(tprintf("Failed to open file at: {}", path))
	}

	json_data, json_err := json.parse(file_data, allocator = context.temp_allocator)
	if json_err != .None {
		panic(tprintf("Failed to parse file, got err: {}", json_err))
	}
	#partial switch json_token_map in json_data {
	case json.Object:
		res := new(Token_To_Color_Map, allocator)
		token_names := reflect.enum_field_names(Semantic_Color_Token)
		for color_token in Semantic_Color_Token {
			// Added the snake case things, so just check that carefully if anything is broken now.
			key := str.to_snake_case(token_names[color_token], context.temp_allocator)
			val := json_token_map[key]
			res[color_token] = convert_hash_color_to_rgba(val.(json.String))
		}
		return res^
	case:
		panic("Parsing json color theme didn't return an object.")
	}
	panic("Failed to Token_To_Color_Map")
}

convert_hash_color_to_rgba :: proc(in_color: string) -> Color_RGBA {
	if len(in_color) != 7 && len(in_color) != 9 {
		panic(tprintf("Color must be of the form #rrggbb, you sent: {}", in_color))
	}
	color: string
	// Check for this incase they pass in an alpha value, like #fa8422ff instead of #fa8422
	if len(color) == 9 {
		color = in_color[1:7]
	} else {
		color = in_color[1:]
	}


	_r, r_ok := strconv.parse_int(color[0:2], 16)
	_g, g_ok := strconv.parse_int(color[2:4], 16)
	_b, b_ok := strconv.parse_int(color[4:6], 16)
	assert(r_ok && g_ok && b_ok)

	r := f32(_r) / 255
	g := f32(_g) / 255
	b := f32(_b) / 255

	return Color_RGBA{r, g, b, 1}
}

// Short hand helper functions for various padding scenarios
padding_x :: proc(amount: int) -> Box_Padding {
	return Box_Padding{left = amount, right = amount}
}
padding_y :: proc(amount: int) -> Box_Padding {
	return Box_Padding{top = amount, bottom = amount}
}
padding :: proc(amount: int) -> Box_Padding {
	return Box_Padding{left = amount, top = amount, right = amount, bottom = amount}
}

// Short hand helper functions for borders
// border_x :: proc(amount: int) -> Box_Border{
// 	return Box_Border {
// 		left = amount,
// 		right = amount
// 	}
// }
// borer_y :: proc(amount: int) -> Box_Border{
// 	return Box_Border {
// 		top = amount,
// 		bottom = amount
// 	}
// }
// border :: proc(amount: int) -> Box_Border{
// 	return Box_Border {
// 		left   = amount,
// 		top    = amount,
// 		right  = amount,
// 		bottom = amount,
// 	}
// }
