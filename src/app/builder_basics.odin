package app
import "base:intrinsics"
import "core:sort"

import "core:strconv"
import str "core:strings"
import "core:text/edit"
import "core:unicode"
import sdl "vendor:sdl2"
import md5 "core:crypto/legacy/md5"
import "core:bytes"
import "core:hash"

slider_value: f32 = 0

TOPBAR_HEIGHT :: 50

text :: proc(id_string: string, config: Box_Config) -> Box_Signals {
	b := box_from_cache(id_string, {.Draw, .Draw_Text, .Text_Center}, config)
	return box_signals(b)
}

text_button :: proc(id_string: string, config: Box_Config) -> Box_Signals {
	box := box_from_cache(id_string, {.Clickable, .Active_Animation, .Draw, .Text_Center, .Draw_Text}, config)
	return box_signals(box)
}

button :: proc(id_string: string, config: Box_Config) -> Box_Signals {
	box := box_from_cache(id_string, {.Clickable, .Active_Animation, .Draw}, config)
	return box_signals(box)
}

// A container that automatically opens for children and closes at the end of the scope it's called in.
@(deferred_out = box_close_children)
child_container :: proc(
	id_string: string,
	config: Box_Config,
	child_layout: Box_Child_Layout,
	extra_flags := Box_Flags{},
) -> Box_Signals {
	box := box_from_cache(id_string, {.Draw} + extra_flags, config)
	box_open_children(box, child_layout)
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

Edit_Text_State :: struct {
	selection:  [2]int,
	// The Odin package `text/edit` state.
	// edit_state: edit.State,
	// Could maybe store the string data here, but we'll store it in the box for now.
}

Text_Box_Type :: enum {
	Generic_One_Line,
	Pitch,
	Volume,
	Send1,
	Send2,
	Generic_Number,
	Multi_Line,
}

audio_track :: proc(track_num: int, track_width: f32) -> Track_Signals {
	track := &app.audio.tracks[track_num]
	n_steps := 32
	track_container := child_container(
		id("@track-{}-container", track_num),
		{semantic_size = {{.Fixed, track_width}, {.Percent, 1}}},
		{direction = .Vertical, gap_vertical = 3},
	)

	track_label: {
		child_container(
			id("@track-{}-label-container", track_num),
			{semantic_size = {{.Fixed, track_width}, {.Fit_Children, 1}}, padding = {left = 30}},
			{direction = .Horizontal, alignment_horizontal = .Center, alignment_vertical = .Center},
		)
		text(id("{} - @track-{}-num", track_num, track_num), {semantic_size = {{.Fit_Text, 1}, {.Fit_Text, 1}}})
		edit_text_box(
			id("@track-{}-name", track_num),
			{semantic_size = {{.Grow, 1}, {.Fixed, 50}}, background_color = {0.5, 0.2, 0.345, 0.2}},
			.Generic_One_Line,
		)
	}

	step_signals: Track_Steps_Signals
	steps: {
		child_container(
			id("@track-steps-container-{}", track_num),
			{semantic_size = {{.Fixed, track_width}, {.Percent, 0.7}}, background_color = {1, 0.5, 1, 1}},
			{direction = .Vertical, gap_vertical = 0},
		)

		substep_config: Box_Config = {
			semantic_size    = {{.Percent, 0.25}, {.Percent, 1}},
			background_color = {1, 0.5, 0, 1},
			border_thickness = 1,
			border_color     = {0, 0, 0.5, 1},
			type             = .Track_Step,
		}
		substep_extra_flags := Box_Flags{.Draw_Border, .Track_Step}

		for i in 0 ..< N_TRACK_STEPS {
			child_container(
				id("@track-{}-row-{}-steps-container", track_num, i),
				{semantic_size = {{.Fixed, track_width}, {.Percent, f32(1) / N_TRACK_STEPS}}},
				{direction = .Horizontal, gap_horizontal = 0},
			)

			pitch_box := edit_text_box(
				id("@track-{}-pitch-step-{}", track_num, i),
				substep_config,
				.Pitch,
				substep_extra_flags,
				metadata = Metadata_Track_Step {
					track = track_num,
					step  = i,
					type  = .Pitch,
				}
			)

			volume_box := edit_number_box(
				id("@track-{}-volume-step-{}", track_num, i),
				substep_config,
				0,
				100,
				Metadata_Track_Step {
					track = track_num,
					step  = i,
					type  = .Volume,
				},
				substep_extra_flags,
			)

			send1_box := edit_number_box(
				id("@track-{}-send1-step-{}", track_num, i),
				substep_config,
				0,
				100,
				Metadata_Track_Step {
					track = track_num,
					step  = i,
					type  = .Send1,
				},
				substep_extra_flags,
			)

			send2_box := edit_number_box(
				id("@track-{}-send2-step-{}", track_num, i),
				substep_config,
				0,
				100,
				Metadata_Track_Step {
					track = track_num,
					step  = i,
					type  = .Send2,
				},
				substep_extra_flags,
			)

			if pitch_box.double_clicked ||
			   volume_box.double_clicked ||
			   send1_box.double_clicked ||
			   send2_box.double_clicked {
				box_siblings_toggle_select(pitch_box.box^)
			}
		}
	}

	controls: {
		controls_container := child_container(
			id("@track-{}-controls-container", track_num),
			{semantic_size = {{.Fixed, track_width}, {.Percent, 0.3}}, background_color = {0.5, 0.7, 0.4, 1}},
			{direction = .Horizontal, alignment_horizontal = .Start, alignment_vertical = .End},
		)
		arm_button := text_button(
			id("arm@track-{}-arm-button", track_num),
			{semantic_size = {{.Percent, 0.333}, {.Fixed, 30}}, background_color = {1, 1, 0, 1}},
		)
		volume_slider := vertical_slider(
			id("hey@track-{}-volume-slider", track_num),
			{semantic_size = {{.Percent, 0.333}, {.Grow, 30}}},
			&track.volume,
			0,
			100,
		)
		load_sound_button := text_button(
			id("load@track-{}-load-sound-button", track_num),
			{semantic_size = {{.Percent, 0.333}, {.Fixed, 30}}, background_color = {1, 0, 0.5, 1}},
		)
	}
	return Track_Signals{step_signals, {}}
}

/*
Takes in any box and activates that box and all of it's siblings.
*/
box_siblings_toggle_select :: proc(box: Box) {
	for sibling in box.parent.children {
		sibling.selected = !sibling.selected
	}
}

box_siblings_set_select :: proc(box: Box, activate: bool) {
	for sibling in box.parent.children {
		sibling.selected = activate
	}
}

edit_number_box :: proc(
	id_string: string,
	config: Box_Config,
	min_val, max_val: int,
	metadata := Box_Metadata{},
	extra_flags := Box_Flags{},
) -> Box_Signals {
	handle_input :: proc(editor: ^edit.State, box: ^Box, min_val, max_val: int) -> string {
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
				app.curr_chars_stored = 0
				return strconv.itoa(res_buffer[:], new_val)
			case .DOWN:
				curr_str_val := str.to_string(editor.builder^)
				curr_val := strconv.atoi(curr_str_val)
				new_val := max(curr_val - 1, min_val)
				res_buffer := make([]byte, 10, context.temp_allocator)
				app.curr_chars_stored = 0
				return strconv.itoa(res_buffer[:], new_val)
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
						new_str_val := strconv.itoa(res_buffer[:], curr_val)
						edit.input_text(editor, new_str_val)
					}
				}
			}
		}
		app.curr_chars_stored = 0
		return str.to_string(editor.builder^)
	}

	increment_number :: proc() { 

	}

	decrement_number :: proc() { 

	}

	flags: Box_Flags
	if step_metadata, ok := metadata.(Metadata_Track_Step); ok {
		flags = {.Track_Step}
	}

	// box_signals := child_container(
	// 	id_string,
	// 	config,
	// 	{direction = .Horizontal},
	// 	{.Clickable, .Draw, .Draw_Text, .Edit_Text} + extra_flags + flags,
	// )
	box := box_from_cache(
		id_string,
		{.Clickable, .Draw, .Draw_Text, .Edit_Text} + extra_flags + flags,
		config,
	)
	box_signals := box_signals(box)
	box_open_children(box, {direction = .Horizontal})
	defer box_close_children(box_signals)
	box.metadata = metadata

	// If this widget is for an audio track step, and we're creating it for the first time (like after switching tabs),
	// pull it's value from the audio state.
	if box.first_frame { 
		if step_metadata, ok := metadata.(Metadata_Track_Step); ok { 
			track_num := step_metadata.track
			step_num := step_metadata.step
			switch step_metadata.type {
			case .Volume:
				box.data = app.audio.tracks[track_num].volumes[step_num]
			case .Send1:
				box.data = app.audio.tracks[track_num].send1[step_num]
			case .Send2:
				box.data = app.audio.tracks[track_num].send2[step_num]
			case .Pitch:
				panic("Set type = .Pitch in Box_Metadata when creating a number box.")
			}
		} else { 
			box.data = min_val
		}
	} else { // box.data should be populated if it's existed before
		if box.data == nil {
			panic(tprintf("It wasn't the first frame and box.data for {} was nil", box.id))
		}
		// NEW: Log the box.data value for cached boxes
		// if box.metadata.(Metadata_Track_Step).track == 0 { 
		// 	printf("Cached box %s has data=%v\n", box.id, box.data)
		// }
	}

	if box_signals.clicked do box.active = !box.active

	if ui_state.last_active_box != box do return box_signals

	if box_signals.scrolled { 
		println("scrolling on box")
	}

	// All text/edit state and the string buffers used when editing are temporary,
	// So we need to permanently allocate the resulting final string at some point so it can
	// be stored across frames. We also need to store each text editors state across frames.
	builder := str.builder_make(context.temp_allocator)
	editor: edit.State
	edit.init(&editor, context.temp_allocator, context.temp_allocator)
	edit.setup_once(&editor, &builder)
	edit.begin(&editor, 0, &builder)
	// Since we re-create the editor every frame, we need to re-populate it's initial data 
	// with the current value from box.data
	tmp_buf: [32]byte
	box_data_string := strconv.itoa(tmp_buf[:], box.data.(int))
	edit.input_text(&editor, box_data_string)

	// If this box hasn't been edited before, create a new edit state and store it
	// so we can remember things like, where the cursor is for this box.
	existing_edit_box := true
	if !(box.id in ui_state.text_editors_state) {
		ui_state.text_editors_state[box.id] = Edit_Text_State{}
		existing_edit_box = false
	}

	state := ui_state.text_editors_state[box.id]
	editor.selection = state.selection

	new_data_string := handle_input(&editor, box, min_val, max_val)

	ui_state.text_editors_state[box.id] = {selection=editor.selection}
	
	new_data := strconv.atoi(new_data_string)
	new_data = clamp(new_data, min_val, max_val)
	
	// Unlike pitches, we can basically always immediately update the audio state for 
	// a step whose value is a number because we clip the number to range on each
	// frame and the input handling function only allows numbers into the data.
	if step_metadata, ok := box.metadata.(Metadata_Track_Step); ok { 
		track := step_metadata.track
		step := step_metadata.step
		switch step_metadata.type { 
		case .Volume:
			app.audio.tracks[track].volumes[step] = new_data
		case .Send1:
			app.audio.tracks[track].send1[step] = new_data
		case .Send2:
			app.audio.tracks[track].send2[step] = new_data
		case .Pitch:
			panic("This shouldn't happen :)")
		}
	} else { 
	}
	box.data = new_data

	edit.end(&editor)
	return box_signals
}

edit_text_box :: proc(
	id_string: string,
	config: Box_Config,
	text_box_type: Text_Box_Type,
	extra_flags := Box_Flags{},
	metadata := Box_Metadata{},
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

	text_container_signals := child_container(
		id_string,
		config,
		{direction = .Horizontal},
		{.Clickable, .Draw, .Draw_Text, .Edit_Text} + extra_flags,
	)
	text_container := text_container_signals.box

	if text_box_type == .Pitch {
		if step_metadata, ok := metadata.(Metadata_Track_Step); ok { 
			text_container.metadata = metadata
		} else { 
			panic("When trying to create a edit_text_box, passed in the wrong metadata type.")
		}
		if text_container.first_frame {
			println("pulling text_container.data from audio state pitch")
			// Pull data from audio state, as it's the source of truth.
			track_num := text_container.metadata.(Metadata_Track_Step).track
			step_num := text_container.metadata.(Metadata_Track_Step).step
			text_container.data = str.clone(get_note_from_num(app.audio.tracks[track_num].pitches[step_num]))
		}
	} else {
		// Since we ALWAYS delete the previous box.data on a keystroke, a new text box needs an empty "" allocated.
		if text_container.first_frame { 
			text_container.data = str.clone("")
		}
	}

	if ui_state.last_active_box != text_container do return text_container_signals

	// All text/edit state and the string buffers used when editing are temporary,
	// So we need to permanently allocate the resulting final string at some point so it can
	// be stored across frames. We also need to store each text editors state across frames.
	builder := str.builder_make(context.temp_allocator)
	editor: edit.State
	edit.init(&editor, context.temp_allocator, context.temp_allocator)
	edit.setup_once(&editor, &builder)
	edit.begin(&editor, 0, &builder)
	edit.input_text(&editor, text_container.data.(string))
	
	existing_edit_box := true
	if !(text_container.id in ui_state.text_editors_state) {
		ui_state.text_editors_state[text_container.id] = Edit_Text_State{}
		existing_edit_box = false
	}
	state := &ui_state.text_editors_state[text_container.id]
	editor.selection = state.selection

	new_data: string
	#partial switch text_box_type {
	case .Generic_One_Line:
		new_data = handle_generic_single_line_input(state, &editor, text_container)
	case .Pitch:
		new_data = handle_pitch_input(state, &editor, text_container)
		// Only update audio state if the string the user entered, actually represents a valid pitch.
		// If not, the last valid pitch is still the current pitch, regardless if the textbox says
		// something like: Y#4
		if valid_pitch(new_data) {
			track_num := text_container.metadata.(Metadata_Track_Step).track
			step_num := text_container.metadata.(Metadata_Track_Step).step
			app.audio.tracks[track_num].pitches[step_num] = get_pitch_from_note(new_data)
		}
	}

	if existing_edit_box && len(text_container.data.(string)) > 0 {
		delete(text_container.data.(string))
	}

	text_container.data = str.clone(new_data)

	edit.end(&editor)
	edit.destroy(&editor)
	return text_container_signals
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
	child_container(
		id("{}-container", get_id_from_id_string(id_string)),
		config,
		{direction = .Vertical, alignment_horizontal = .Center},
	)
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
			position_floating = .Relative_Parent,
			position_floating_offset = {0.5, map_range(min_val, max_val, 0, 1, slider_value^)},
		},
	)
	grip_signals := box_signals(grip)

	if track_signals.scrolled || grip_signals.scrolled {
		// printfln("changing slider value: {}", app.mouse.wheel)
		printfln("slider value before scroll: {}", slider_value^)
		if track_signals.scrolled_up || grip_signals.scrolled_up {
			slider_value^ = clamp(slider_value^ - 1, min_val, max_val)
		} else if track_signals.scrolled_down || grip_signals.scrolled_down {
			slider_value^ = clamp(slider_value^ + 1, min_val, max_val)
		} else {
			printfln("neither scrolled up NOR down :(")
		}
		printfln("slider value after scroll: {}", slider_value^)
	}
	return Slider_Signals{track_signals, grip_signals}
}

/*
	Has to be placed in the root container to display properly.
*/
topbar :: proc() {
	child_container(
		"@topbar",
		{
			semantic_size    = {{.Fixed, f32(app.wx)}, {.Fixed, TOPBAR_HEIGHT}},
			background_color = {1, 1, 1, 0.8},
			// padding = {top = 10, bottom = 5},
		},
		{direction = .Horizontal, alignment_horizontal = .End, alignment_vertical = .Center, gap_horizontal = 5},
	)
	btn_config := Box_Config {
		semantic_size = {{.Fit_Text, 1}, {.Fit_Text, 1}},
		background_color = {0.5, 0.7, 0.7, 1},
		corner_radius = 5,
		padding = {top = 7, bottom = 7, left = 2, right = 2},
	}
	if text_button("Default layout@top-bar-default", btn_config).clicked {
		ui_state.tab_num = 0
		ui_state.changed_ui_screen = true
	}
	if text_button("Test layout@top-bar-test", btn_config).clicked {
		ui_state.tab_num = 1
		ui_state.changed_ui_screen = true
	}
	side_bar_btn_id :=
		ui_state.sidebar_shown ? "Close sidebar@top-bar-sidebar-close" : "Open sidebar@top-bar-sidebar-open"
	if text_button(side_bar_btn_id, btn_config).clicked {
		ui_state.sidebar_shown = !ui_state.sidebar_shown
	}

}

/*
	Used for radio buttons and checkbox groups only allows for strings or number arguments for now.
*/
multi_button_set :: proc(
	id_string: string,
	config: Box_Config,
	child_layout: Box_Child_Layout,
	exclusive: bool = true,
	values: []$T,
	allocator := context.allocator,
) -> [dynamic]T where intrinsics.type_is_string(T) ||
	intrinsics.type_is_numeric(T) {
	set_id := get_id_from_id_string(id_string)
	child_container(id("@{}-container", set_id), config, child_layout)

	Res_Type :: struct {
		signals: Box_Signals,
		value:   T,
	}
	buttons := make([]Res_Type, len(values), context.temp_allocator)

	// --- Draw buttons and store them in a buffer so we can query their signals.
	for value, i in values {
		child_container(id("@{}-item-{}", set_id, i), {}, {direction = .Horizontal, gap_horizontal = 5})
		b := button(
			tprintf("@{}-button-{}", value, set_id, i),
			{
				semantic_size = {{.Fit_Text, 1}, {.Fit_Text, 1}},
				padding = {10, 10, 10, 10},
				background_color = {.5, .7, .8, 1},
			},
		)
		val_str_buf := make([]u8, 50, context.temp_allocator)
		val_as_str: string
		if intrinsics.type_is_numeric(T) {
			if intrinsics.type_is_float(T) {
				// format strings are inefficient.
				val_as_str = tprintf("{}", value)
			} else if intrinsics.type_is_integer(T) {
				val_as_str = strconv.itoa(val_str_buf, value)
			}
		}
		text(id("{}@{}-text-{}", val_as_str, set_id, i), {semantic_size = {{.Fit_Text, 1}, {.Fit_Text, 1}}})
		buttons[i] = {b, value}
	}

	/*
		If this is NOT the first frame this button set has existed, there's a chance some of the buttons have been 
		selected, in which case, we visually indicate this..
	*/
	for button in buttons {
		if button.signals.box.selected {
			button.signals.box.config.background_color = {1, 0.5, 1, 1}
		}
	}

	results := make([dynamic]T, allocator)
	for button in buttons {
		if button.signals.clicked {
			button.signals.box.selected = !button.signals.box.selected
			if button.signals.box.selected {
				append(&results, button.value)
				if exclusive {
					// --- 'Switch off' sibling radio buttons.
					for other_button in buttons {
						if button != other_button {
							other_button.signals.box.selected = false
						}
					}
					return results
				}
			}
		}
	}
	return results
}

set_nth_child_select :: proc(track_num, nth: int, selected: bool) {
	// Is inefficient to traverse all boxes in the UI but should be okay for now.
	root, ok := ui_state.box_cache["root"]
	if !ok {
		panic("Failed to get box with id 'root'")
	}
	boxes := box_tree_to_list(root, context.temp_allocator)
	for box in boxes {
		switch metadata in box.metadata {
		case Metadata_Track_Step:
			if metadata.track != track_num do continue
			if metadata.step % nth == 0 do box.selected = selected
		}
	}
}

context_menu :: proc() {
	track_steps_context_menu :: proc(box: ^Box) {
		btn_height: f32 = 30
		add_button := text_button(
			"add@conext-menu-1",
			{
				semantic_size = {{.Grow, 1}, {.Fit_Text, btn_height}},
				background_color = {1, 0.5, 0.7, 1},
				padding = {10, 10, 10, 10},
			},
		)

		remove_button := text_button(
			"remove@conext-menu-2",
			{
				semantic_size = {{.Fit_Text, 1}, {.Fit_Text, btn_height}},
				background_color = {1, 0.7, 0.3, 1},
				padding = {10, 10, 10, 10},
			},
		)
		add_submenu_id := "@add-step-hover-container"
		add_submenu_hovered := false
		if submenu_box, ok := ui_state.box_cache[add_submenu_id[1:]]; ok {
			add_submenu_hovered = mouse_inside_box(submenu_box, app.mouse.pos)
		}
		if add_button.hovering || add_submenu_hovered {
			hover_container := child_container(
				add_submenu_id,
				{
					position_floating = .Absolute_Pixel,
					position_floating_offset = {f32(add_button.box.bottom_right.x), f32(add_button.box.top_left.y)},
					semantic_size = {{.Fit_Children, 1}, {.Fit_Children, 1}},
					z_index = 20,
				},
				{direction = .Vertical, gap_vertical = 2},
				{.Clickable},
			)
			btn_config := Box_Config {
				semantic_size    = {{.Fit_Text, 1}, {.Fit_Text, 1}},
				background_color = {0.734, 0.9235, 0.984, 1},
				padding          = {10, 10, 10, 10},
			}
			if text_button("All steps@context-add-all", btn_config).clicked {
				track_num := box.metadata.(Metadata_Track_Step).track
				set_nth_child_select(track_num, 1, true)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 2nd@context-add-2nd", btn_config).clicked {
				track_num := box.metadata.(Metadata_Track_Step).track
				set_nth_child_select(track_num, 2, true)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 3rd@context-add-3rd", btn_config).clicked {
				track_num := box.metadata.(Metadata_Track_Step).track
				set_nth_child_select(track_num, 3, true)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 4th@context-add-4th", btn_config).clicked {
				track_num := box.metadata.(Metadata_Track_Step).track
				set_nth_child_select(track_num, 4, true)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 6th@context-add-6th", btn_config).clicked {
				track_num := box.metadata.(Metadata_Track_Step).track
				set_nth_child_select(track_num, 6, true)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 8th@context-add-8th", btn_config).clicked {
				track_num := box.metadata.(Metadata_Track_Step).track
				set_nth_child_select(track_num, 8, true)
				ui_state.clicked_on_context_menu = true
			}
		}

		remove_submenu_id := "@remove-step-hover-container"
		remove_submenu_hovered := false
		if submenu_box, ok := ui_state.box_cache[remove_submenu_id[1:]]; ok {
			remove_submenu_hovered = mouse_inside_box(submenu_box, app.mouse.pos)
		}
		if remove_button.hovering || remove_submenu_hovered {
			hover_container := child_container(
				remove_submenu_id,
				{
					position_floating = .Absolute_Pixel,
					position_floating_offset = {
						f32(remove_button.box.bottom_right.x),
						f32(remove_button.box.top_left.y),
					},
					semantic_size = {{.Fit_Children, 1}, {.Fit_Children, 1}},
					z_index = 20,
				},
				{direction = .Vertical, gap_vertical = 2},
				{.Clickable},
			)
			btn_config := Box_Config {
				semantic_size    = {{.Fit_Text, 1}, {.Fit_Text, 1}},
				background_color = {0.934, 0.135, 0.484, 1},
				padding          = {10, 10, 10, 10},
			}
			if text_button("All steps@context-remove-all", btn_config).clicked {
				track_num := box.metadata.(Metadata_Track_Step).track
				set_nth_child_select(track_num, 1, false)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 2nd@context-remove-2nd", btn_config).clicked {
				track_num := box.metadata.(Metadata_Track_Step).track
				set_nth_child_select(track_num, 2, false)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 3rd@context-remove-3rd", btn_config).clicked {
				track_num := box.metadata.(Metadata_Track_Step).track
				set_nth_child_select(track_num, 3, false)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 4th@context-remove-4th", btn_config).clicked {
				track_num := box.metadata.(Metadata_Track_Step).track
				set_nth_child_select(track_num, 4, false)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 6th@context-remove-6th", btn_config).clicked {
				track_num := box.metadata.(Metadata_Track_Step).track
				set_nth_child_select(track_num, 6, false)
				ui_state.clicked_on_context_menu = true

			}
			if text_button("Every 8th@context-remove-8th", btn_config).clicked {
				track_num := box.metadata.(Metadata_Track_Step).track
				set_nth_child_select(track_num, 8, false)
				ui_state.clicked_on_context_menu = true

			}
		}

		delete_track_button := text_button(
			"delete@conext-menu-3",
			{
				semantic_size = {{.Grow, 1}, {.Fit_Text, btn_height}},
				background_color = {0.3, 0.7, 0.3, 1},
				padding = {10, 10, 10, 10},
			},
		)
		if delete_track_button.clicked {
			track_delete(box.metadata.(Metadata_Track_Step).track)
			printfln("deletring track that contains {}", ui_state.right_clicked_on.id)
		}
	}
	context_menu_container := child_container(
		"@context-menu",
		{
			semantic_size = {{.Fit_Children, 1}, {.Fit_Children, 1}},
			padding = {2, 2, 2, 2},
			background_color = {0.5, 0.2, 1, 0.5},
			position_floating = .Absolute_Pixel,
			position_floating_offset = {f32(ui_state.context_menu.pos.x), f32(ui_state.context_menu.pos.y)},
			z_index = 100,
		},
		{direction = .Vertical, alignment_horizontal = .Center, gap_vertical = 3},
	)

	switch metadata in ui_state.right_clicked_on.metadata {
	case Metadata_Track_Step:
		println("right clicked on a track step")
		track_steps_context_menu(ui_state.right_clicked_on)
	case:
		text(
			"Context menu not implemented for this box type @ alskdjfalskdjfladf",
			{semantic_size = {{.Fit_Text, 1}, {.Fit_Text, 1}}},
		)
	}
}

file_browser_menu :: proc() {
	child_container(
		"@file-browser-container",
		{
			semantic_size = {{.Fit_Children, 1}, {.Fit_Children, 1}},
			background_color = {1, 0, 0.7, 1},
			padding = {bottom = 5},
			z_index = 10,
		},
		{direction = .Vertical},
	)
	top_menu: {
		child_container(
			"@file-browser-options-container",
			{
				semantic_size = {{.Fit_Children, 1}, {.Fit_Children, 1.}},
				padding = {10, 10, 10, 10},
				background_color = {.5, .4, .423, 1},
			},
			{direction = .Horizontal, alignment_horizontal = .Center, alignment_vertical = .Center},
		)
		btn_config := Box_Config {
			background_color = {0.9, 0.8, 0.9, 1},
			border_thickness = 3,
			padding          = {10, 10, 10, 10},
			semantic_size    = {{.Fit_Text, 1}, {.Fit_Text, 1}},
			corner_radius    = 0,
		}
		option_load := text_button("Add@browser-options-folder-button", btn_config)
		option_sort := text_button("Sort@browser-options-sort-button", btn_config)
		option_flip := text_button("Flip@browser-options-flip-button", btn_config)
		if option_load.clicked {
			res, ok := file_dialog_windows(true, context.temp_allocator)
			if !ok {
				// panic(
				println(
					"File dialogue failure, either:\n- Failed to open dialogue.\n- Failed to return files from dialogue.",
				)
			}
			for path in res {
				path_string := str.clone_from_cstring(path)
				append(&app.browser_files, path_string)
			}
		}
		// --- Don't think this sorting actually changes anything.
		sort.quick_sort(app.browser_files[:])
	}
	files_and_folders: {
		child_container(
			"@browser-files-container",
			{semantic_size = {{.Fit_Children, 1}, {.Fit_Children, 1}}, background_color = {.5, .4, .2, 1}},
			{direction = .Vertical},
		)

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

@(deferred_out = box_close_children)
draggable_window :: proc(id_string: string, child_layout: Box_Child_Layout) -> Box_Signals {
	// Probably want to store window positions even when they're closed.
	actual_id := get_id_from_id_string(id_string)
	offset_from_parent := Vec2_f32{.5, .5}
	if actual_id in ui_state.draggable_window_offsets {
		offset_from_parent = ui_state.draggable_window_offsets[actual_id]
	} else {
		ui_state.draggable_window_offsets[actual_id] = offset_from_parent
	}
	container := box_from_cache(
		id_string,
		{},
		{
			position_floating = .Relative_Parent,
			position_floating_offset = offset_from_parent,
			semantic_size = {{.Fit_Children, 1}, {.Fit_Children, 1}},
			z_index = 20,
		},
	)
	container_signals := box_signals(container)
	box_open_children(container, child_layout)

	title_bar := box_from_cache(
		id("Title bar@{}-title-bar", get_id_from_id_string(id_string)),
		{.Draggable, .Clickable, .Draw_Text, .Draw},
		{
			semantic_size = {{.Grow, 100}, {.Fit_Text, 1}},
			padding = {top = 5, bottom = 5},
			background_color = {.5, .2, .3, 1},
			z_index = container.z_index,
		},
	)

	bar_signals := box_signals(title_bar)

	if bar_signals.dragging {
		// printfln("dragging {}", container.id)
		ui_state.dragged_window = container
	} else {
		// printfln("NOT dragging {}", container.id)
		ui_state.dragged_window = nil
	}

	return box_signals(container)
}
