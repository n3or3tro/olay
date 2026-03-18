package app
// import sarr "core:container/small_array"
import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:reflect"
import "core:strconv"
import str "core:strings"
import "core:time"
import gl "vendor:OpenGL"
import sdl "vendor:sdl2"
import vmem "core:mem/virtual"

DARK_THEME_FILE_DATA :: #load("../../dark-theme.json")
EXPECTED_FRAME_TIME_SECONDS :: 0.00833333
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
	blur_shader_program:      u32,
	tex_id_font_atlas:    	  u32,
	fbo_id_offscreen_ui: 	  u32,
	tex_id_offscreen_ui: 	  u32,
	fbo_id_blurred_ui: 	  	  u32,
	tex_id_blurred_ui: 	  	  u32,
	tex_id_freq_spectrum:	  u32,
	tex_id_freq_response: 	  u32,
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
	icon_state: 			  Font_State,
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
	draggable_window_offsets: map[string]Draggable_Window_Metadata,
	// Necessary shared state for animations. Could definitely live on a pool based allocator.
	animations:               [N_MAX_ANIMATIONS]Animation_Item,
	animations_stored:		  int,
	undo_stack:               [dynamic]State_Change,
	redo_stack:               [dynamic]State_Change,
	// Whether or not a track's eq is showing.
	eqs:                      [dynamic]bool,
	// Maps scrollable containers id to the amount of offset to apply to their scrolled children in px.
	scroll_offsets: map[string]int,
	file_browser_allocator: mem.Allocator,
	browser_files: [dynamic]Browser_File,
	browser_dirs:  [dynamic]Browser_Directory,
	browser_search_term: 	string,
	browser_sort_ascending: bool,
	frames_since_sleep: 	i8,
	event_wait_timeout: 	f64,
	prev_frame_start_ms: 	f64,
	show_mixer: bool,
	show_track_waveforms: bool,
}

Draggable_Window_Metadata :: struct { 
	opened: bool,
	maximised: bool,
	// 0-1 range of how far from root's top_left.
	offset: [2]f32,
	dragging: bool,
	grab_offset: [2]f32,
	// offset_at_drag_start: [2]f32
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
		Chop,
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

init_ui_state :: proc() -> ^UI_State {
	ui_state.quad_vbuffer = new(u32)
	ui_state.quad_vabuffer = new(u32)

	ui_state.color_stack = make([dynamic]Color_RGBA)
	ui_state.box_cache = make(map[string]^Box)
	ui_state.frame_signals = make(map[string]Box_Signals)
	ui_state.show_mixer = true
	// ui_state.sidebar_shown = true
	// ui_state.clipping_stack = make([dynamic]^Rect)

	// Fine to leave this dangling since it has the same lifetime as the whole program.
	_, ui_state.file_browser_allocator =  arena_allocator_new("file-browser-arena")

	wx: i32 = 0
	wy: i32 = 0
	sdl.GetWindowSize(app.window, &wx, &wy)
	app.wx, app.wy = int(wx), int(wy)

	ui_state.frame_num = 0

	// Generate and store color theme:
	// ui_state.dark_theme = parse_json_token_color_mapping("util/dark-theme.json")
	ui_state.dark_theme = parse_json_token_color_mapping(DARK_THEME_FILE_DATA)

	font_init(&ui_state.font_state)
	icons_init(&ui_state.icon_state)

	gl.GenVertexArrays(1, ui_state.quad_vabuffer)
	create_vbuffer(ui_state.quad_vbuffer, nil, 30_000_000)

	shader_program_id, quad_shader_ok := gl.load_shaders_source(
		string(QUAD_VERTEX_SHADER_AS_BYTES),
		string(QUAD_PIXEL_SHADER_AS_BYTES),
	)

	if !quad_shader_ok {
		msg, type := gl.get_last_error_message()
		panicf("{} {}", msg, type)
	}
	ui_state.quad_shader_program = shader_program_id

	blur_shader_program_id, blur_shader_ok := gl.load_shaders_source(
		string(BLUR_VERTEX_SHADER_AS_BYTES),
		string(BLUR_PIXEL_SHADER_AS_BYTES),
	)
	if !blur_shader_ok {
		msg, type := gl.get_last_error_message()
		println(msg, type)
		panic("")
	}
	ui_state.blur_shader_program = blur_shader_program_id



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
	gl.ActiveTexture(gl.TEXTURE0)
	gl.BindTexture(gl.TEXTURE_2D, atlas_texture_id)

	gl.TexImage2D(
		gl.TEXTURE_2D,  	// target
		0, 					// level (mipmap)
		gl.R8,  			// internal format (8 bit red channel is most efficient apparently)
		1024,   			// width
		1024,   			// height
		0, 	    			// border
		gl.RED, 			// format of pixel data, i.e. where it looks to find the pixel info.
		gl.UNSIGNED_BYTE,   // type of pixel data.
		nil, 				// data -> nil as it's empty until we start rendering text.
	)
	ui_state.tex_id_font_atlas = atlas_texture_id

	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)

	// Create texture to store spectrum analyzed audio data.
	frequency_spectrum_tex_id: u32
	gl.GenTextures(1, &frequency_spectrum_tex_id)
	gl.ActiveTexture(gl.TEXTURE1)
	gl.BindTexture(gl.TEXTURE_2D, frequency_spectrum_tex_id)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.R32F, 512, 256, 0, gl.RED, gl.FLOAT, nil)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	ui_state.tex_id_freq_spectrum = frequency_spectrum_tex_id

	// Create texture to store spectrum analyzed audio data.
	frequency_response_tex_id: u32
	gl.GenTextures(1, &frequency_response_tex_id)
	gl.ActiveTexture(gl.TEXTURE3)
	gl.BindTexture(gl.TEXTURE_2D, frequency_response_tex_id)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.R32F, 512, 256, 0, gl.RED, gl.FLOAT, nil)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	ui_state.tex_id_freq_response = frequency_response_tex_id

	// Let open gl know which texture we've uploaded corresponds to which of the variables
	// that are defined in the shader code.
	gl.Uniform1i(gl.GetUniformLocation(shader_program_id, "font_atlas"), 0)
	gl.Uniform1i(gl.GetUniformLocation(shader_program_id, "audio_frequency_spectrum"), 1)
	gl.Uniform1i(gl.GetUniformLocation(shader_program_id, "blurred_ui"), 2)
	gl.Uniform1i(gl.GetUniformLocation(shader_program_id, "audio_frequency_eq_response"), 3)

	// -- Frosted Glass FBO + Texture setup ------------
	// Setup FBO to draw UI to an offscreen texture.
	offscreen_ui_fbo_id: u32
	gl.GenFramebuffers(1, &offscreen_ui_fbo_id)
	gl.BindFramebuffer(gl.FRAMEBUFFER, offscreen_ui_fbo_id)

	offscreen_ui_tex_id: u32
	gl.GenTextures(1, &offscreen_ui_tex_id)
	gl.ActiveTexture(gl.TEXTURE4)
	gl.BindTexture(gl.TEXTURE_2D, offscreen_ui_tex_id)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, i32(app.wx), i32(app.wy), 0, gl.RGBA, gl.UNSIGNED_BYTE, nil)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S,     gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T,     gl.CLAMP_TO_EDGE)
	gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, offscreen_ui_tex_id, 0)
	gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
	ui_state.fbo_id_offscreen_ui = offscreen_ui_fbo_id
	ui_state.tex_id_offscreen_ui = offscreen_ui_tex_id

	// Setup FBO to blurred UI to an offscreen texture.
	blurred_ui_fbo_id: u32
	gl.GenFramebuffers(1, &blurred_ui_fbo_id)
	gl.BindFramebuffer(gl.FRAMEBUFFER, blurred_ui_fbo_id)

	blurred_ui_tex_id: u32
	gl.GenTextures(1, &blurred_ui_tex_id)
	gl.ActiveTexture(gl.TEXTURE5)
	gl.BindTexture(gl.TEXTURE_2D, blurred_ui_tex_id)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, i32(app.wx), i32(app.wy), 0, gl.RGBA, gl.UNSIGNED_BYTE, nil)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S,     gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T,     gl.CLAMP_TO_EDGE)
	gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, blurred_ui_tex_id, 0)
	gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
	ui_state.fbo_id_blurred_ui = blurred_ui_fbo_id
	ui_state.tex_id_blurred_ui = blurred_ui_tex_id

	return ui_state
}

create_ui :: proc() -> ^Box {
	// Collect frame signals for this frame based on what the tree just looked like at the end of the prev frame.
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
			size = {{.Fixed, f32(app.wx)}, {.Fixed, f32(app.wy)}},
			color = .Inverse_On_Surface,
		},
		{direction = .Vertical},
		// This is basically the only mandatory ID in the entire UI. DON'T REMOVE IT!!
		id = "root",
		box_flags = {.Draw, .Glow, .Clickable},
	).box

	ui_state.root = root

	topbar()
	if ui_state.tab_num == 0 {
		add_track_btn :=  text_button(
			"+",
			{
				floating_type = .Center_Right,
				padding       = {10, 10, 10, 10},
				border        = border(1),
				size 		  = {{.Fit_Text, 1}, {.Fit_Text, 1}},
				color         = .Lime_200,
			},
  		)
		if add_track_btn.hovering do hover_help_text("Add new track", add_track_btn.box)
		if add_track_btn.clicked  do track_add_new(app.audio)
		track_width :: 190
		audio_tracks: {
			track_vlist := virtual_list(
				{
					size = {
						{.Fit_Children, 1},
						// We hardcode the height of the topbar otherwise the layout gets annoying.
						{.Fixed, f32(app.wy - TOPBAR_HEIGHT)},
					},
					max_size = {app.wx, app.wy}
				},
				{
					direction      = .Horizontal,
					gap_horizontal = 3,
				},
				len(app.audio.tracks),
				track_width,
				box_flags = {.Scrollable}
			)

			// Draw vertical column of step numbers
			step_num_col_box: ^Box 
			number_col: {
				if ui_state.frame_num == 0 do break number_col
				steps_container_height := ui_state.box_cache["track-0-steps-container"].height
				step_num_col_box = child_container(
					{
						size = {{.Fit_Children, 1}, {.Fixed, f32(steps_container_height)}},
						margin = {top = 38, left=5, right=5},
						overflow_y = .Scroll
					},
					{direction = .Vertical},
					box_flags = {}
				).box
				// Janky solution to get pixel perfect step number column sizing. We hardcode one of the 
				// audio tracks steps container and use that as a reference for figruing out the height of the
				// step numbers
				// This must match the ratio calculation in audio_track().
				step_height_ratio := f32(ui_state.show_mixer ? 1.0 / (54.0 * 0.7) : 1.0 / (80.0 * 0.7))
				step_height_px := f32(steps_container_height) * step_height_ratio
				for i in 0 ..< N_TRACK_STEPS {
					sig := text(
						tprintf("{}", i),
						{
							text_justify = {.End, .Center},
							size={{.Fit_Text_And_Grow, 1}, {.Fixed, step_height_px}}
						},
						extra_flags = {.Clickable},
					)
					if sig.clicked do audio_seek_to_step(i)
				}
			}

			// Ugliness required to scroll container in sync.
			arena, scratch := arena_allocator_new("container-scroll-sync")	
			defer arena_allocator_destroy(arena, scratch)
			step_containers := make([]^Box, len(app.audio.tracks), scratch)

			for i in track_vlist.first_visible ..= track_vlist.last_visible {
				audio_track(i, track_width, &step_containers)
			}

			scrolled_container : ^Box
			for box in step_containers {
				if box == nil do continue
				if box.signals.scrolled_up || box.signals.scrolled_down {
					scrolled_container = box
					break
				}
			}

			if scrolled_container != nil {
				for box in step_containers { 
					if box == nil do continue
					box.signals.scrolled_up = scrolled_container.signals.scrolled_up
					box.signals.scrolled_down = scrolled_container.signals.scrolled_down
				}
				step_num_col_box.signals.scrolled_up = scrolled_container.signals.scrolled_up
				step_num_col_box.signals.scrolled_down = scrolled_container.signals.scrolled_down
			}
		}
	}
	else {
		offset_x := f32(animation_get("ani_x", 200))
		offset_y := f32(animation_get("ani_y", 60))
		if text_button(
			"animate me :)",
			{
				floating_type = .Absolute_Pixel,
				floating_offset = {offset_x, offset_y},
				size = {{.Fixed, offset_x}, {.Fixed, offset_y}},
				color = .Warning
			}
		).clicked {
			animation_start("ani_x", 20, 1)
			animation_start("ani_y", 6, 1)
		}
	}

	if ui_state.context_menu.active {
		context_menu()
	}

	if ui_state.sidebar_shown || animation_is_running("browser-offset-x"){
		x_offset := animation_get("browser-offset-x", ui_state.sidebar_shown ? 1.0 : 2.0)
		child_container(
			{
				floating_type   = .Relative_Root,
				floating_offset = {f32(x_offset), 0},
				padding 		= {top = TOPBAR_HEIGHT}
			},
			{}
		)
		file_browser_menu(ui_state.file_browser_allocator)
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
	// {
	// 	child_container(
	// 		{
	// 			size       = Size_Fit_Children,
	// 			color               = .Surface_Variant,
	// 			floating_type       = .Relative_Parent,
	// 			floating_anchor_box = ui_state.root,
	// 			floating_offset     = {1, 1},
	// 		},
	// 		{
	// 			direction            = .Vertical,
	// 			alignment_horizontal = .Start,
	// 			gap_vertical         = 5,
	// 		},
	// 		"helper-text-bottom-right",
	// 	)

	// 	text(
	// 		"F5 -> Hot reload DLL, keep data",
	// 		{
	// 			color         = .Warning_Container,
	// 			text_justify  = {.Start, .Center},
	// 			size = Size_Fit_Text,
	// 		},
	// 		"helper-text-1",
	// 	)

	// 	text(
	// 		"F3 -> Hot reload DLL, clear data",
	// 		{
	// 			color         = .Warning_Container,
	// 			text_justify  = {.Start, .Center},
	// 			size = Size_Fit_Text,
	// 		},
	// 	)

	// 	text(
	// 		"F1 -> Restart, keep DLL, clear data",
	// 		{
	// 			color         = .Warning_Container,
	// 			text_justify  = {.Start, .Center},
	// 			margin = {bottom = 5},
	// 			size = Size_Fit_Text,
	// 		},
	// 		"helper-text-3",
	// 	)
	// }

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
		if .Edit_Text in box.flags {
			delete_key(&ui_state.text_editors_state, box.id)
		}

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
	// Material Theme Palette
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

	// Tailwind colors
	Slate_50, Slate_100, Slate_200, Slate_300, Slate_400, Slate_500, Slate_600, Slate_700, Slate_800, Slate_900, Slate_950,
	Gray_50, Gray_100, Gray_200, Gray_300, Gray_400, Gray_500, Gray_600, Gray_700, Gray_800, Gray_900, Gray_950,
	Zinc_50, Zinc_100, Zinc_200, Zinc_300, Zinc_400, Zinc_500, Zinc_600, Zinc_700, Zinc_800, Zinc_900, Zinc_950,
	Neutral_50, Neutral_100, Neutral_200, Neutral_300, Neutral_400, Neutral_500, Neutral_600, Neutral_700, Neutral_800, Neutral_900, Neutral_950,
	Stone_50, Stone_100, Stone_200, Stone_300, Stone_400, Stone_500, Stone_600, Stone_700, Stone_800, Stone_900, Stone_950,
	Red_50, Red_100, Red_200, Red_300, Red_400, Red_500, Red_600, Red_700, Red_800, Red_900, Red_950,
	Orange_50, Orange_100, Orange_200, Orange_300, Orange_400, Orange_500, Orange_600, Orange_700, Orange_800, Orange_900, Orange_950,
	Amber_50, Amber_100, Amber_200, Amber_300, Amber_400, Amber_500, Amber_600, Amber_700, Amber_800, Amber_900, Amber_950,
	Yellow_50, Yellow_100, Yellow_200, Yellow_300, Yellow_400, Yellow_500, Yellow_600, Yellow_700, Yellow_800, Yellow_900, Yellow_950,
	Lime_50, Lime_100, Lime_200, Lime_300, Lime_400, Lime_500, Lime_600, Lime_700, Lime_800, Lime_900, Lime_950,
	Green_50, Green_100, Green_200, Green_300, Green_400, Green_500, Green_600, Green_700, Green_800, Green_900, Green_950,
	Emerald_50, Emerald_100, Emerald_200, Emerald_300, Emerald_400, Emerald_500, Emerald_600, Emerald_700, Emerald_800, Emerald_900, Emerald_950,
	Teal_50, Teal_100, Teal_200, Teal_300, Teal_400, Teal_500, Teal_600, Teal_700, Teal_800, Teal_900, Teal_950,
	Cyan_50, Cyan_100, Cyan_200, Cyan_300, Cyan_400, Cyan_500, Cyan_600, Cyan_700, Cyan_800, Cyan_900, Cyan_950,
	Sky_50, Sky_100, Sky_200, Sky_300, Sky_400, Sky_500, Sky_600, Sky_700, Sky_800, Sky_900, Sky_950,
	Blue_50, Blue_100, Blue_200, Blue_300, Blue_400, Blue_500, Blue_600, Blue_700, Blue_800, Blue_900, Blue_950,
	Indigo_50, Indigo_100, Indigo_200, Indigo_300, Indigo_400, Indigo_500, Indigo_600, Indigo_700, Indigo_800, Indigo_900, Indigo_950,
	Violet_50, Violet_100, Violet_200, Violet_300, Violet_400, Violet_500, Violet_600, Violet_700, Violet_800, Violet_900, Violet_950,
	Purple_50, Purple_100, Purple_200, Purple_300, Purple_400, Purple_500, Purple_600, Purple_700, Purple_800, Purple_900, Purple_950,
	Fuchsia_50, Fuchsia_100, Fuchsia_200, Fuchsia_300, Fuchsia_400, Fuchsia_500, Fuchsia_600, Fuchsia_700, Fuchsia_800, Fuchsia_900, Fuchsia_950,
	Pink_50, Pink_100, Pink_200, Pink_300, Pink_400, Pink_500, Pink_600, Pink_700, Pink_800, Pink_900, Pink_950,
	Rose_50, Rose_100, Rose_200, Rose_300, Rose_400, Rose_500, Rose_600, Rose_700, Rose_800, Rose_900, Rose_950,
}

Token_To_Color_Map :: map[Semantic_Color_Token]Color_RGBA

parse_json_token_color_mapping :: proc(file_data: []byte, allocator := context.allocator) -> Token_To_Color_Map {
	// file_data, err := os.read_entire_file_from_path(path, context.temp_allocator)
	// if err != nil {
	// 	panic(tprintf("Failed to open file at: {}", path))
	// }

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
border_x :: proc(amount: int) -> Box_Border{
	return Box_Border {
		left = amount,
		right = amount
	}
}
borer_y :: proc(amount: int) -> Box_Border{
	return Box_Border {
		top = amount,
		bottom = amount
	}
}
border :: proc(amount: int) -> Box_Border{
	return Box_Border {
		left   = amount,
		top    = amount,
		right  = amount,
		bottom = amount,
	}
}
