package app
import os "core:os/os2"

import "core:encoding/base32"
import "core:strconv"
import str "core:strings"
import "core:text/edit"
import "core:unicode"
import sdl "vendor:sdl2"

slider_value: f32 = 0

TOPBAR_HEIGHT :: 50
button_text :: proc(id_string: string, config: Box_Config) -> Box_Signals {
	box := box_from_cache(id_string, {.Clickable, .Active_Animation, .Draw, .Text_Center, .Draw_Text}, config)
	return box_signals(box)
}

// @(deferred_out=box_close_children)
container :: proc(id_string: string, config: Box_Config) -> Box_Signals {
	box := box_from_cache(id_string, {.Draw}, config)
	return box_signals(box)
}

Track_Steps_Signals :: struct {
	volume, pitch, send1, send2: Box_Signals,
}
Track_Controller_Signals :: struct {
	track, slider, play_button, load_button: Box_Signals,
}
Track_Signals :: struct {
	steps:      Track_Steps_Signals,
	controller: Track_Controller_Signals,
}

audio_track :: proc(track_num: u32, track_width: f32) -> Track_Signals {
	n_steps: f32 = 32
	track_container := container(
		tprintf("@track-{}-container", track_num),
		{semantic_size = {{.Fixed, track_width}, {.Percent, 1}}},
	)
	box_open_children(track_container.box, {direction = .Vertical, gap_vertical = 3})
	defer box_close_children(track_container.box)

	step_signals: Track_Steps_Signals
	steps: {
		steps_container := container(
			tprintf("@track-steps-container-{}", track_num),
			{semantic_size = {{.Fixed, track_width}, {.Percent, 0.7}}, background_color = {1, 0.5, 1, 1}},
		)
		box_open_children(steps_container.box, {direction = .Vertical, gap_vertical = 0})
		defer box_close_children(steps_container.box)

		substep_config: Box_Config = {
			semantic_size    = {{.Percent, 0.25}, {.Percent, 1}},
			background_color = {1, 0.5, 0, 1},
			border_thickness = 1,
			border_color     = Color{0, 0, 0.5, 1},
		}
		substep_extra_flags := Box_Flags{.Draw_Border}
		for i in 0 ..< 30 {
			row_container := container(
				tprintf("@track-{}-row-{}-steps-container", track_num, i),
				{semantic_size = {{.Fixed, track_width}, {.Percent, f32(1) / 32.0}}},
			)
			box_open_children(row_container.box, {direction = .Horizontal, gap_horizontal = 0})
			edit_text_box(
				id("@track-{}-pitch-step-{}", track_num, i),
				substep_config,
				.Pitch_Input,
				substep_extra_flags,
			)
			edit_number_box(id("@track-{}-volume-step-{}", track_num, i), substep_config, 0, 100, substep_extra_flags)
			edit_number_box(id("@track-{}-send1-step-{}", track_num, i), substep_config, 0, 100, substep_extra_flags)
			edit_number_box(id("@track-{}-send2-step-{}", track_num, i), substep_config, 0, 100, substep_extra_flags)
			box_close_children(row_container.box)
		}
	}

	controls: {
		controls_container := container(
			tprintf("@track-{}-controls-container", track_num),
			{semantic_size = {{.Fixed, track_width}, {.Percent, 0.3}}, background_color = {0.5, 0.7, 0.4, 1}},
		)
		box_open_children(
			controls_container.box,
			{direction = .Horizontal, alignment_horizontal = .Start, alignment_vertical = .End},
		)
		defer box_close_children(controls_container.box)

		arm_button := button_text(
			id("arm@track-{}-arm-button", track_num),
			{semantic_size = {{.Percent, 0.333}, {.Fixed, 30}}, background_color = {1, 1, 0, 1}},
		)
		volume_slider := vertical_slider(
			id("hey@track-{}-volume-slider", track_num), // volume_slider := button_text(
			{
				semantic_size = {{.Percent, 0.333}, {.Grow, 30}}, /*background_color = {1, 0, 0, 1}*/
			},
			&slider_value,
			0,
			100,
		)
		load_sound_button := button_text(
			id("load@track-{}-load-sound-button", track_num),
			{semantic_size = {{.Percent, 0.333}, {.Fixed, 30}}, background_color = {1, 0, 0.5, 1}},
		)
		// if volume_slider.grip.scrolled || volume_slider.track.scrolled {
		// }
	}
	return Track_Signals{step_signals, {}}
}

Edit_Text_State :: struct {
	selection:  [2]int,
	// The Odin package `text/edit` state.
	edit_state: edit.State,
	// Could maybe store the string data here, but we'll store it in the box for now.
}
Text_Box_Type :: enum {
	Generic_One_Line,
	Pitch_Input,
	Number_Input,
	Multi_Line,
}
edit_number_box :: proc(
	id_string: string,
	config: Box_Config,
	min_val, max_val: int,
	extra_flags := Box_Flags{},
) -> Box_Signals {
	handle_input :: proc(state: ^Edit_Text_State, editor: ^edit.State, box: ^Box, min_val, max_val: int) -> string {
		for i := u32(0); i < app.curr_chars_stored; i += 1 {
			keycode := app.char_queue[i]
			#partial switch keycode {
			case .LEFT:
				edit.move_to(editor, .Left)
			case .RIGHT:
				edit.move_to(editor, .Right)
			case .BACKSPACE:
				edit.delete_to(editor, .Left)
			case .DELETE:
				edit.delete_to(editor, .Right)
			// case .ESCAPE, .CAPSLOCK:
			// ui_state.last_active_box = nil
			// ui_state.active_box = nil
			// app.curr_chars_stored = 1
			case .UP:
				curr_str_val := str.to_string(editor.builder^)
				curr_val := strconv.atoi(curr_str_val)
				new_val := min(curr_val + 1, max_val)
				res_buffer := make([]byte, 50, context.temp_allocator)
				return strconv.itoa(res_buffer, new_val)
			case .DOWN:
				curr_str_val := str.to_string(editor.builder^)
				curr_val := strconv.atoi(curr_str_val)
				new_val := max(curr_val - 1, min_val)
				res_buffer := make([]byte, 10, context.temp_allocator)
				return strconv.itoa(res_buffer, new_val)
			case:
				char := rune(keycode)
				if unicode.is_number(char) {
					edit.input_rune(editor, char)
					curr_str_val := str.to_string(editor.builder^)
					curr_val := strconv.atoi(curr_str_val)
					clamped_val := clamp(min_val, max_val, curr_val)
					if clamped_val != curr_val {
						// Not sure if this is the right way to programatically edit
						// the input state.
						edit.move_to(editor, .Start)
						edit.delete_to(editor, .End)
						res_buffer := make([]byte, 10, context.temp_allocator)
						new_str_val := strconv.itoa(res_buffer, curr_val)
						edit.input_text(editor, new_str_val)
					}
				}
			}
		}
		app.curr_chars_stored = 0
		state.selection = editor.selection
		return str.to_string(editor.builder^)
	}

	text_container := box_from_cache(id_string, {.Clickable, .Draw, .Draw_Text, .Edit_Text} + extra_flags, config)
	box_open_children(text_container, {direction = .Horizontal})
	defer box_close_children(text_container)
	container_signals := box_signals(text_container)

	if ui_state.last_active_box != text_container do return container_signals

	// All text/edit state and the string buffers used when editing are temporary,
	// So we need to permanently allocate the resulting final string at some point so it can
	// be stored across frames. We also need to store each text editors state across frames.
	editor: edit.State
	edit.init(&editor, context.temp_allocator, context.temp_allocator)
	builder := str.builder_make(context.temp_allocator)
	str.write_string(&builder, text_container.data)
	edit.setup_once(&editor, &builder)
	edit.begin(&editor, 0, &builder)

	existing_edit_box := true
	if !(id_string in ui_state.text_editors_state) {
		ui_state.text_editors_state[id_string] = Edit_Text_State{}
		text_container.data = "0"
		existing_edit_box = false
	}
	state := &ui_state.text_editors_state[id_string]
	editor.selection = state.selection

	new_data: string
	new_data = handle_input(state, &editor, text_container, min_val, max_val)
	if existing_edit_box && len(text_container.data) > 0 {
		delete(text_container.data)
	}
	text_container.data = str.clone(new_data)
	edit.end(&editor)
	edit.destroy(&editor)
	return container_signals
}

edit_text_box :: proc(
	id_string: string,
	config: Box_Config,
	text_box_type: Text_Box_Type,
	extra_flags := Box_Flags{},
) -> Box_Signals {
	// Handles input and returns the new string from the editor.
	handle_generic_single_line_input :: proc(state: ^Edit_Text_State, editor: ^edit.State, box: ^Box) -> string {
		for i := u32(0); i < app.curr_chars_stored; i += 1 {
			keycode := app.char_queue[i]
			#partial switch keycode {
			case .LEFT:
				edit.move_to(editor, .Left)
			case .RIGHT:
				edit.move_to(editor, .Right)
			case .BACKSPACE:
				edit.delete_to(editor, .Left)
				printfln("backspace pressed")
			case .DELETE:
				edit.delete_to(editor, .Right)
				printfln("delete pressed")
				// case .ESCAPE, .CAPSLOCK:
				// ui_state.last_active_box = nil
				// ui_state.active_box = nil
				// app.curr_chars_stored = 1
				break
			case .DOWN, .UP, .LCTRL, .RCTRL:
			// For single line editor this does nothing.
			case:
				char := rune(keycode)
				if unicode.is_alpha(char) ||
				   unicode.is_digit(char) ||
				   unicode.is_space(char) ||
				   unicode.is_punct(char) {
					if app.keys_held[sdl.Scancode.LSHIFT] || app.keys_held[sdl.Scancode.RSHIFT] {
						char = unicode.to_upper(char)
					}
					edit.input_rune(editor, char)
				}
			}
		}
		app.curr_chars_stored = 0
		state.selection = editor.selection
		return str.to_string(editor.builder^)
	}

	handle_pitch_input :: proc(state: ^Edit_Text_State, editor: ^edit.State, box: ^Box) -> string {
		for i := u32(0); i < app.curr_chars_stored; i += 1 {
			keycode := app.char_queue[i]
			#partial switch keycode {
			case .LEFT:
				edit.move_to(editor, .Left)
			case .RIGHT:
				edit.move_to(editor, .Right)
			case .BACKSPACE:
				edit.delete_to(editor, .Left)
			case .DELETE:
				edit.delete_to(editor, .Right)
				// case .ESCAPE, .CAPSLOCK:
				// ui_state.last_active_box = nil
				// ui_state.active_box = nil
				// app.curr_chars_stored = 1
				break
			case .UP:
				edit.move_to(editor, .End)
				return up_one_semitone(str.to_string(editor.builder^))
			case .DOWN:
				edit.move_to(editor, .End)
				return down_one_semitone(str.to_string(editor.builder^))
			case:
				// Pitch can be at most 3 chars.
				if str.builder_len(editor.builder^) < 3 {
					char := rune(keycode)
					if unicode.is_alpha(char) {
						edit.input_rune(editor, unicode.to_upper(char))
					} else if unicode.is_digit(char) || char == '#' {
						edit.input_rune(editor, char)
					}
				}
			}
		}
		app.curr_chars_stored = 0
		state.selection = editor.selection
		return str.to_string(editor.builder^)
	}

	text_container := box_from_cache(id_string, {.Clickable, .Draw, .Draw_Text, .Edit_Text} + extra_flags, config)
	box_open_children(text_container, {direction = .Horizontal})
	defer box_close_children(text_container)
	container_signals := box_signals(text_container)

	if ui_state.last_active_box != text_container do return container_signals

	// All text/edit state and the string buffers used when editing are temporary,
	// So we need to permanently allocate the resulting final string at some point so it can
	// be stored across frames. We also need to store each text editors state across frames.
	editor: edit.State
	edit.init(&editor, context.temp_allocator, context.temp_allocator)
	builder := str.builder_make(context.temp_allocator)
	str.write_string(&builder, text_container.data)
	edit.setup_once(&editor, &builder)
	edit.begin(&editor, 0, &builder)


	existing_edit_box := true
	if !(id_string in ui_state.text_editors_state) {
		ui_state.text_editors_state[id_string] = Edit_Text_State{}
		existing_edit_box = false
	}
	state := &ui_state.text_editors_state[id_string]
	editor.selection = state.selection

	new_data: string
	#partial switch text_box_type {
	case .Generic_One_Line:
		new_data = handle_generic_single_line_input(state, &editor, text_container)
	case .Pitch_Input:
		new_data = handle_pitch_input(state, &editor, text_container)
	}

	if existing_edit_box && len(text_container.data) > 0 {
		delete(text_container.data)
	}

	text_container.data = str.clone(new_data)
	edit.end(&editor)
	edit.destroy(&editor)
	return container_signals
}

Slider_Signals :: struct {
	track: Box_Signals,
	grip:  Box_Signals,
}

vertical_slider :: proc(
	id_string: string,
	config: Box_Config,
	slider_value: ^f32,
	min_val: f32,
	max_val: f32,
) -> Slider_Signals {
	slider_container := container(id("{}-container", get_id_from_id_string(id_string)), config)
	box_open_children(slider_container.box, {direction = .Vertical, alignment_horizontal = .Center})
	defer box_close_children(slider_container.box)

	track := box_from_cache(
		id("{}-track", get_id_from_id_string(id_string)),
		{.Clickable, .Draw, .Scrollable},
		{semantic_size = {{.Percent, 0.5}, {.Percent, 1}}, background_color = {1, 1, 1, 1}},
	)
	track_signals := box_signals(track)

	grip := box_from_cache(
		id("{}-grip", get_id_from_id_string(id_string)),
		{.Clickable, .Draggable, .Draw},
		{
			semantic_size = {{.Percent, 0.7}, {.Percent, 0.1}},
			background_color = {0, 0.1, 0.7, 1},
			position_absolute = true,
			offset_from_parent = {0.5, map_range(min_val, max_val, 0, 1, slider_value^)},
		},
	)
	grip_signals := box_signals(grip)

	if track_signals.scrolled || grip_signals.scrolled {
		printfln("changing slider value: {}", app.mouse.wheel)
		if track_signals.scrolled_up || grip_signals.scrolled_up {
			slider_value^ = max(slider_value^ - 1, 0)
		} else if track_signals.scrolled_down || grip_signals.scrolled_down {
			slider_value^ = min(slider_value^ + 1, max_val)
		}
	}
	return Slider_Signals{track_signals, grip_signals}
}

/*
Has to be placed in the root container to display properly.
*/
topbar :: proc() {
	topbar_container := container(
	"@topbar",
	{
		semantic_size    = {{.Fixed, f32(app.wx)}, {.Fixed, TOPBAR_HEIGHT}},
		background_color = {1, 1, 1, 0.8},
		// padding = {top = 10, bottom = 5},
	},
	)
	box_open_children(
		topbar_container.box,
		{direction = .Horizontal, alignment_horizontal = .End, alignment_vertical = .Center, gap_horizontal = 5},
	)
	defer box_close_children(topbar_container.box)
	btn_config := Box_Config {
		semantic_size = {{.Fit_Text, 1}, {.Fit_Text, 1}},
		background_color = {0.5, 0.7, 0.7, 1},
		corner_radius = 5,
		padding = {top = 7, bottom = 7, left = 2, right = 2},
	}
	if button_text("Default layout@top-bar-default", btn_config).clicked {
		ui_state.tab_num = 0
		ui_state.changed_ui_screen = true
	}
	if button_text("Test layout@top-bar-test", btn_config).clicked {
		ui_state.tab_num = 1
		ui_state.changed_ui_screen = true
	}

	side_bar_btn_id :=
		ui_state.sidebar_shown ? "Close sidebar@top-bar-sidebar-close" : "Open sidebar@top-bar-sidebar-open"
	if button_text(side_bar_btn_id, btn_config).clicked {
		ui_state.sidebar_shown = !ui_state.sidebar_shown
	}

}

// Can use mouse pos when summoned
test_context_menu :: proc() {
	context_menu_container := container(
		"@context-menu",
		{
			semantic_size = {{.Fit_Children, 1}, {.Fit_Children, 1}},
			padding = {2, 2, 2, 2},
			background_color = {0.5, 0.2, 1, 0.5},
			position_absolute = true,
			offset_from_parent = {f32(app.mouse.pos.x) / f32(app.wx), f32(app.mouse.pos.y) / f32(app.wy)},
		},
	)
	btn_height: f32 = 30
	box_open_children(
		context_menu_container.box,
		{direction = .Vertical, alignment_horizontal = .Center, gap_vertical = 3},
	)
	defer box_close_children(context_menu_container.box)

	b1 := button_text(
	"button1@conext-menu-1",
	{semantic_size = {{.Fit_Text, 1}, {.Fit_Text, btn_height}}, background_color = {1, 0.5, 1, 1}},
	// {semantic_size = {{.Fixed, 50}, {.Fixed, btn_height}}, background_color = {1, 0.5, 1, 1}},
	)
	b2 := button_text(
	"button2@conext-menu-2",
	{semantic_size = {{.Fit_Text, 1}, {.Fit_Text, btn_height}}, background_color = {1, 0.5, 0.7, 1}},
	// {semantic_size = {{.Fixed, 50}, {.Fixed, btn_height}}, background_color = {1, 0.5, 0.7, 1}},
	)
}

handle_file_browser_interactions :: proc() {
}

file_browser_menu :: proc() {
	menu := container(
		"@file-browser-container",
		{
			position_absolute = true,
			offset_from_parent = {0, 0},
			semantic_size = {{.Fit_Children, 1}, {.Fit_Children, 1}},
			background_color = {1, 0, 0.7, 1},
			padding = {bottom = 5},
		},
	)
	box_open_children(menu.box, {direction = .Vertical})
	defer box_close_children(menu.box)
	top_menu: {
		options_container := container(
			"@file-browser-options-container",
			{
				semantic_size = {{.Fit_Children, 1}, {.Fit_Children, 1.}},
				padding = {10, 10, 10, 10},
				background_color = {.5, .4, .423, 1},
			},
		)
		box_open_children(
			options_container.box,
			{direction = .Horizontal, alignment_horizontal = .Center, alignment_vertical = .Center},
		)
		defer box_close_children(options_container.box)
		btn_config := Box_Config {
			background_color = {0.9, 0.8, 0.9, 1},
			border_thickness = 3,
			padding          = {10, 10, 10, 10},
			semantic_size    = {{.Fit_Text, 1}, {.Fit_Text, 1}},
			corner_radius    = 0,
		}
		option_load := button_text("Add@browser-options-folder-button", btn_config)
		option_sort := button_text("Sort@browser-options-sort-button", btn_config)
		option_flip := button_text("Flip@browser-options-flip-button", btn_config)
		if option_load.clicked {
			res, ok := file_dialog_windows(true, context.temp_allocator)
			if !ok {
				panic(
					"File dialogue failure, either:\n- Failed to open dialogue.\n- Failed to return files from dialogue.",
				)
			}
			for path in res {
				path_string := str.clone_from_cstring(path)
				append(&app.browser_files, path_string)
			}
		}
	}
	files_and_folders: {
		hehe := container(
			"@browser-files-container",
			{
				semantic_size = {{.Fit_Children, 1}, {.Fit_Children, 1}}, 
				background_color = {.5, .4, .2, 1}},
		)
		box_open_children(hehe.box, {direction = .Vertical})
		defer box_close_children(hehe.box)
		// Can see having issues with the index being in the id here.
		for file, i in app.browser_files {
			lol := Box_Config {
				semantic_size    = {{.Fit_Text, 1}, {.Fit_Text, 1}},
				background_color = {1, 2, 3, 1},
			}
			text(
				id("{}@browser-file-{}", file, i),
				{
					semantic_size = {{.Fit_Text, 1}, {.Fit_Text, 1}},
					padding = {left = 5, right = 5, top = 3, bottom = 3},
					corner_radius = 4,
				},
			)
		}
	}
}

text :: proc(id_string: string, config: Box_Config) -> Box_Signals {
	b := box_from_cache(id_string, {.Draw, .Draw_Text}, config)
	return box_signals(b)
}


draggable_window :: proc(id_string: string, config: Box_Config) {
	// Probably want to store window positions even when they're closed.
	cnt := container(id_string, {
		position_absolute = true,
		offset_from_parent = {.5, .5}
	})
	box_open_children(cnt.box, {
		direction = .Vertical
	})
	defer box_close_children(cnt.box)

	title_bar := box_from_cache(
		id("title bar@{}-title-bar", cnt.box.id),
		{.Draggable, .Clickable},
		{
			semantic_size = {{.Percent, 1}, {.Fit_Text, 1}}, 
			padding = {top = 5, bottom = 5}
		},
	)
	title_bar_signals := box_signals(title_bar)
}
