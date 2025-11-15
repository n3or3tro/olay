package app
import "core:fmt"
import "core:reflect"
import "core:strconv"
import os "core:os/os2"
import "core:mem"
import "core:time"
import gl "vendor:OpenGL"
import sdl "vendor:sdl2"
import "core:encoding/json"


id :: fmt.tprintf
UI_State :: struct {
	box_cache:             map[string]^Box,
	// I.e. the node which will parent future children if children_open() has been called.
	parents_top:           ^Box,
	parents_stack:         [dynamic]^Box,
	settings_toggled:      bool,
	color_stack:           [dynamic]Color_RGBA,
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
	clicked_on_context_menu: bool,
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
	dark_theme: 			Token_To_Color_Map,
	light_theme: 			Token_To_Color_Map,
	draggable_window_offsets : map[string][2]f32,
}


init_ui_state :: proc() -> ^UI_State {
	ui_state.quad_vbuffer = new(u32)
	ui_state.quad_vabuffer = new(u32)

	ui_state.color_stack = make([dynamic]Color_RGBA)
	ui_state.box_cache = make(map[string]^Box)
	ui_state.next_frame_signals = make(map[string]Box_Signals)
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
	for _, box in ui_state.box_cache {
		box.keep = false
	}
	ui_state.changed_ui_screen = false
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

			for track, i in app.audio.tracks {
				audio_track(i, 250)
			}
		}
		if text_button(
			"+@add-track-button", 
			{
				position_floating =.Center_Right,
				padding = {10,10,10,10},
				border_thickness = 4,
				semantic_size = {{.Fit_Text, 1}, {.Fit_Text, 1}},
				color = {0.987, 0.41234, 0.41234, 1}
			}
		).clicked {
			track_add_new(app.audio)
		}
	} else {
		multi_button_set(
			"@test-radio-buttons", 
			{
				semantic_size = {{.Fit_Children, 1}, {.Fit_Children, 1}},
			}, 
			{
				direction =.Vertical,
				gap_horizontal = 20,
				gap_vertical = 10
			}, 
			false, 
			[]int{8,2,10,14,27, 4242, 23423, 123,4747}
		)
		cfg := Box_Config { 
			semantic_size = {{.Fixed, 300}, {.Fixed, 50}},
			border_thickness = 4,
			color = {0.5, 1, 1, 0.7}
		}
		edit_number_box("what@flaksjdf", cfg, 0, 100)
		edit_number_box("hey@lkjslkj", cfg, 5, 200)
		edit_number_box("fuck@asldlll", cfg, 20, 300)
		edit_number_box("lol@flaskjdf", cfg, 50, 400)
		// edit_text_box("@zxcvcxv", {cfg}, .Pitch)
		// edit_text_box("@zxcvcxv", {cfg}, .Pitch)
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
	// debug_dump_number_box_cache()
	flow_z_positions(root)
	compute_frame_signals(root)
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

	// --- Sweep phase of mark and sweep box memory management.

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


@(private="file")
Color_HSLA :: distinct [4]f32

Theme_Base_Colors  :: struct { 
	// Primary accent color, accent in comparison to surface color.
	primary,  	
	// Secondary accent color, accent in comparison to surface color.
	secondary, 
	// Third accent color, accent in comparison to surface color.
	tertiary, 
	// Neutral color that isn't the background nor an accent, yet fits the theme.
	neutral,
	// Used for backgrounds and large swaths of non-content area.
	surface,
	surface_variant,
	inactive,
	warning,
	error: Color_RGBA
}

Theme_Full_Palette :: struct { 
	primary,  	
	secondary, 
	tertiary, 
	neutral,
	surface,
	surface_variant,
	inactive,
	warning,
	error: [10] Color_RGBA
}

@(private="file")
// Note: A different color format like OKLCH may work better.
rgba_to_hsla :: proc(in_color: Color_RGBA) ->  Color_HSLA { 
	// This algo was written by chat GPT it may be shit or wrong, careful :).
	r, g, b, a := in_color[0], in_color[1], in_color[2], in_color[3]
	h, s, l: f32
   	maxc := max(r, max(g, b));
    minc := min(r, min(g, b));
    l     = (maxc + minc) * 0.5;

    if maxc == minc {
        // grayscale
        return {0, 0, l, a};
    }

    d := maxc - minc;

    if l > 0.5 {
        s = d / (2.0 - maxc - minc);
    } else {
        s = d / (maxc + minc);
    }

    if maxc == r {
        h = (g - b) / d + (g < b ? 6 : 0);
    } else if maxc == g {
        h = (b - r) / d + 2;
    } else {
        h = (r - g) / d + 4;
    }

    h /= 6.0;
    return {h,s,l, a};	
}

hsla_to_rgba :: proc(in_color: Color_HSLA) -> Color_RGBA {
	// This algo was written by chat GPT it may be shit or wrong, careful :).
	hue_to_rgb :: proc(p, q, t: f32) -> f32 { 
		t := t
		if t < 0 { t += 1; }
		if t > 1 { t -= 1; }

		if t < 1.0/6.0 {
			return p + (q - p) * 6 * t;
		}
		if t < 1.0/2.0 {
			return q;
		}
		if t < 2.0/3.0 {
			return p + (q - p) * (2.0/3.0 - t) * 6;
		}
		return p;
	}

	h, s, l, a := in_color[0], in_color[1], in_color[2], in_color[3]
    if s == 0 {
        // grayscale
        return {l, l, l, a};
    }

    q := (l < 0.5) ? (l * (1 + s)) : (l + s - l*s);
    p := 2*l - q;

    r := hue_to_rgb(p, q, h + 1.0/3.0);
    g := hue_to_rgb(p, q, h);
    b := hue_to_rgb(p, q, h - 1.0/3.0);

    return {r, g, b, a};
}

// Takes in 1 RGBA color and returns 10 shades of that color, each darker than the next.
// output[0] is lightest -> output[9] is darkest.
generate_tones_rgba :: proc(in_color: Color_RGBA) -> [10]Color_RGBA {
	hsla_input := rgba_to_hsla(in_color);
	h, s, l, a := hsla_input[0], hsla_input[1], hsla_input[2], hsla_input[3]

    intensities := [10]f32{
		0.05, 0.15, 0.25, 0.35, 0.45,
		0.55, 0.65, 0.75, 0.85, 0.95
    };

    tones: [10]Color_RGBA;

    for i in 0..<10 {
		hsla_variant := Color_HSLA{h, s, intensities[i], a}
        rgba_variant := hsla_to_rgba(hsla_variant);
        tones[i] = rgba_variant
    }

    return tones;
}

// These are color tokens generated by the material color util we have. They map onto things like 
// button color, button hover state, etc. 

Semantic_Color_Token :: enum {
	primary,
	on_primary,
	primary_container,
	on_primary_container,
	secondary,
	on_secondary,
	secondary_container,
	on_secondary_container,
	tertiary,
	on_tertiary,
	tertiary_container,
	on_tertiary_container,
	error,
	on_error,
	error_container,
	on_error_container,
	warning,
	on_warning,
	warning_container,
	on_warning_container,
	background,
	on_background,
	surface,
	on_surface,
	surface_variant,
	on_surface_variant,
	surface_dim,
	surface_bright,
	surface_container_lowest,
	surface_container_low,
	surface_container,
	surface_container_high,
	surface_container_highest,
	outline,
	outline_variant,
	inverse_surface,
	inverse_on_surface,
	inverse_primary,
	scrim,
	shadow,
	inactive,
	on_inactive,
}

Token_To_Color_Map :: map[Semantic_Color_Token]Color_RGBA

parse_json_token_color_mapping :: proc(path: string, allocator:=context.allocator) -> Token_To_Color_Map { 
	file_data, err := os.read_entire_file_from_path(path, context.temp_allocator)
	if err != nil { 
		panic(tprintf("Failed to open file at: {}", path))
	}

	json_data, json_err := json.parse(file_data, allocator=allocator)
	if json_err != .None { 
		panic(tprintf("Failed to parse file, got err: {}", json_err))
	}
	#partial switch json_token_map in json_data { 
		case json.Object:
			res: Token_To_Color_Map
			token_names := reflect.enum_field_names(Semantic_Color_Token)
			for color_token in Semantic_Color_Token {
				key := token_names[color_token]
				val := json_token_map[key]
				res[color_token] = convert_hash_color_to_rgba(val.(json.String))
			}
			return res
		case:
			panic("Parsing json color theme didn't return an object.")
	}
	panic("Failed to Token_To_Color_Map")
}

convert_hash_color_to_rgba :: proc(color: string) -> Color_RGBA { 
	if len(color) != 7 { 
		panic(tprintf("Color must be of the form #rrggbb, you sent: {}", color))
	}

	color := color[1:]

	_r, r_ok := strconv.parse_int(color[0:2], 16)
	_g, g_ok := strconv.parse_int(color[2:4], 16)
	_b, b_ok := strconv.parse_int(color[4:6], 16)
	assert(r_ok && g_ok && b_ok)

	r := f32(_r) / 255
	g := f32(_g) / 255
	b := f32(_b) / 255

	return Color_RGBA {r, g, b, 1}
}
