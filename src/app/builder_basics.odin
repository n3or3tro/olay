package app
import "base:intrinsics"
import "core:math"
import "core:sort"

import "core:strconv"
import str "core:strings"
import "core:text/edit"
import "core:unicode"
import sdl "vendor:sdl2"


TOPBAR_HEIGHT :: 37

// For when you don't want to have to think of an ID for a box. Used for drawing lines for example.
// This has various obvious interactivity tradeoffs, i.e. harder to reference the box later.
// WARNING!!! Using anon_container leads to crashing when hot reloading, need to investigate.
// anon_container :: proc(config: Box_Config, flags: Box_Flags) -> Box_Signals {
//     id := tprintf("@anon-{}", ui_state.anon_box_counter)
//     ui_state.anon_box_counter += 1
// 	b := box_make(id, flags, config)
// 	return box_signals(b)
// }

text :: proc(label: string, config: Box_Config, id := "", extra_flags := Box_Flags{}) -> Box_Signals {
	b := box_from_cache({.Draw_Text, .Text_Center} + extra_flags, config, label, id)
	return box_signals(b)
}

icon :: proc(code_glyph: rune, hover_text: string, config: Box_Config, id := "", extra_flags := Box_Flags{}) -> Box_Signals {
	b := box_from_cache({.Draw_Icon, .Text_Center} + extra_flags, config, "", id, icon_rune=code_glyph)
	signals := box_signals(b)
	return signals
}

icon_button :: proc(code_glyph: rune, hover_text: string, config: Box_Config, id := "", extra_flags := Box_Flags{}) -> Box_Signals {
	signals := icon(code_glyph, hover_text, config, id, extra_flags + {.Clickable, .Hot_Animation, .Active_Animation})
	if signals.hovering {
		hover_help_text(hover_text, signals.box)
	}
	return signals
}


text_button :: proc(label: string, config: Box_Config, id := "", extra_flags := Box_Flags{}) -> Box_Signals {
	box := box_from_cache({.Clickable, .Hot_Animation, .Active_Animation, .Draw, .Text_Center, .Draw_Text} + extra_flags, config, label, id)
	return box_signals(box)
}

button :: proc(config: Box_Config, id := "", extra_flags := Box_Flags{}) -> Box_Signals {
	box := box_from_cache({.Clickable, .Hot_Animation, .Active_Animation, .Draw} + extra_flags, config, "", id)
	return box_signals(box)
}

// A container that automatically opens for children and closes at the end of the scope it's called in.
@(deferred_out = box_regular_close_children)
child_container :: proc(
	config: Box_Config,
	child_layout: Box_Child_Layout,
	id := "",
	box_flags := Box_Flags{},
	metadata := Box_Metadata{},
) -> Box_Signals 
{
	config := config
	if config.max_size == {0, 0} do config.max_size = {app.wx, app.wy}
	box := box_from_cache(box_flags, config, "", id, metadata)
	box_open_children(box, child_layout)
	return box_signals(box)
}

Track_Steps_Signals :: struct {
	volume, pitch, chop, send2: Box_Signals,
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
}

Text_Box_Type :: enum {
	Generic_One_Line,
	Pitch,
	Volume,
	// Chop,
	// Send2,
	// Generic_Number,
	Multi_Line,
}

edit_number_box :: proc(
	config: Box_Config,
	value: ^int,
	min_val, max_val: int,
	id := "",
	metadata := Box_Metadata{},
	extra_flags := Box_Flags{},
) -> Box_Signals 
{
	handle_input :: proc(editor: ^edit.State, box: ^Box, min_val, max_val: int) -> string {
		write_idx: u32 = 0
		for i := u32(0); i < app.curr_chars_stored; i += 1 {
			keycode := app.char_queue[i]
			handled := true
			#partial switch keycode {
			case .LEFT:
				edit.move_to(editor, .Left)
			case .RIGHT:
				edit.move_to(editor, .Right)
			case .BACKSPACE:
				edit.delete_to(editor, .Left)
			case .DELETE:
				edit.delete_to(editor, .Right)
			case .UP:
				curr_str_val := str.to_string(editor.builder^)
				app.curr_chars_stored = write_idx
				return increment_number_string(curr_str_val, max_val)
			case .DOWN:
				curr_str_val := str.to_string(editor.builder^)
				app.curr_chars_stored = write_idx
				return decrement_number_string(curr_str_val, min_val)
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
				} else {
					handled = false
				}
			}
			if !handled {
				app.char_queue[write_idx] = keycode
				write_idx += 1
			}
		}
		app.curr_chars_stored = write_idx
		return str.to_string(editor.builder^)
	}

	increment_number_string :: proc(curr_str_val: string, max_val: int) -> string {
		curr_val := strconv.atoi(curr_str_val)
		new_val := min(curr_val + 1, max_val)
		res_buffer := make([]byte, 50, context.temp_allocator)
		return strconv.itoa(res_buffer[:], new_val)
	}

	decrement_number_string :: proc(curr_str_val: string, min_val: int) -> string {
		curr_val := strconv.atoi(curr_str_val)
		new_val := max(curr_val - 1.0, min_val)
		res_buffer := make([]byte, 50, context.temp_allocator)
		return strconv.itoa(res_buffer[:], new_val)
	}

	tmp_buf := make([]byte, 32, context.temp_allocator)
	num_as_string := strconv.itoa(tmp_buf[:], value^)

	box := box_from_cache(
		{.Clickable, .Draw, .Draw_Text, .Edit_Text, .Hot_Animation, .Active_Animation, .Scrollable} + extra_flags,
		config,
		num_as_string,
		id,
		metadata,
	)
	box_signals := box_signals(box)

	if box_signals.clicked do box.active = !box.active

	if ui_state.last_active_box != box do return box_signals

	// All text/edit state and the string buffers used when editing are temporary,
	// So we need to permanently allocate the resulting final string at some point so it can
	// be stored across frames. We also need to store each text editors state across frames.
	builder := str.builder_make(context.temp_allocator)
	editor: edit.State
	edit.init(&editor, context.temp_allocator, context.temp_allocator)
	edit.setup_once(&editor, &builder)
	edit.begin(&editor, 0, &builder)
	edit.input_text(&editor, num_as_string)

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

	if box_signals.shift_scrolled_up {
		new_data_string = increment_number_string(str.to_string(editor.builder^), max_val)
	} else if box_signals.shift_scrolled_down { 
		new_data_string = decrement_number_string(str.to_string(editor.builder^), min_val)
	}
	ui_state.text_editors_state[box.id] = {selection=editor.selection}
	new_value := strconv.atoi(new_data_string)
	new_value = clamp(new_value, min_val, max_val)


	// Only update audio state if we actually changed the value this frame
	// Unlike pitches, we can basically always immediately update the audio state for 
	// a step whose value is a number because we clip the number to range on each
	// frame and the input handling function only allows numbers into the data.
	update_audio_state: if step_metadata, ok := box.metadata.(Metadata_Track_Step); ok { 
		track := step_metadata.track
		step := step_metadata.step
		change: State_Change
		switch step_metadata.type { 
		case .Volume:
			old_data := app.audio.tracks[track].volumes[step]
			if old_data == new_value do break update_audio_state
			app.audio.tracks[track].volumes[step] = new_value
		case .Chop:
			old_data := app.audio.tracks[track].chops[step]
			if old_data == new_value do break update_audio_state
			app.audio.tracks[track].chops[step] = new_value
		case .Send2:
			old_data := app.audio.tracks[track].send2[step]
			if old_data == new_value do break update_audio_state
			app.audio.tracks[track].send2[step] = new_value
		case .Pitch:
			panic("This shouldn't happen :)")
		}
	}
	value^ = new_value
	edit.end(&editor)
	return box_signals
}

// edit box never owns the string it's editing, it can access via box.data.(^string), and it's ALWAYS a reference.
edit_text_box :: proc(
	config: Box_Config,
	text_box_type: Text_Box_Type,
	text: ^string,
	id := "",
	extra_flags := Box_Flags{},
	metadata := Box_Metadata{},
) -> Box_Signals {

	// Handles input and returns the new string from the editor.
	handle_generic_single_line_input :: proc(state: ^Edit_Text_State, editor: ^edit.State, box: ^Box) -> string {
		write_idx: u32 = 0
		for i := u32(0); i < app.curr_chars_stored; i += 1 {
			keycode := app.char_queue[i]
			handled := true
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
				} else {
					handled = false
				}
			}
			if handled {
				box.signals.changed = true
			} else {
				app.char_queue[write_idx] = keycode
				write_idx += 1
			}
		}
		app.curr_chars_stored = write_idx
		state.selection = editor.selection
		return str.to_string(editor.builder^)
	}

	edit_box := box_from_cache(
		{.Clickable, .Draw, .Draw_Text, .Edit_Text, .Hot_Animation, .Active_Animation} + extra_flags,
		config,
		text^,
		id,
		metadata,
	)

	// No need to run editing code if the box isn't active.
	if ui_state.last_active_box != edit_box do return box_signals(edit_box)

	// All text/edit state and the string buffers used when editing are temporary,
	// So we need to permanently allocate the resulting final result at some point so it can
	// be stored across frames. We also need to store each text editors state across frames.
	builder := str.builder_make(context.temp_allocator)
	editor: edit.State
	edit.init(&editor, context.temp_allocator, context.temp_allocator)
	edit.setup_once(&editor, &builder)
	edit.begin(&editor, 0, &builder)
	edit.input_text(&editor, edit_box.text)
	
	existing_edit_box := true
	if edit_box.id not_in ui_state.text_editors_state {
		ui_state.text_editors_state[edit_box.id] = Edit_Text_State{}
		existing_edit_box = false
	}
	state := &ui_state.text_editors_state[edit_box.id]
	editor.selection = state.selection

	if text != nil do delete(text^)
	text^ = str.clone(handle_generic_single_line_input(state, &editor, edit_box))
	edit_box.text = text^
	edit.end(&editor)
	edit.destroy(&editor)
	return box_signals(edit_box)
}

edit_pitch_box :: proc(
	config: Box_Config,
	id := "",
	extra_flags := Box_Flags{},
	metadata := Box_Metadata{},
) -> Box_Signals 
{ 
	handle_pitch_input :: proc(state: ^Edit_Text_State, editor: ^edit.State, box: ^Box) -> string {
		write_idx: u32 = 0
		for i := u32(0); i < app.curr_chars_stored; i += 1 {
			keycode := app.char_queue[i]
			handled := true
			#partial switch keycode {
			case .LEFT:
				edit.move_to(editor, .Left)
			case .RIGHT:
				edit.move_to(editor, .Right)
			case .BACKSPACE:
				edit.delete_to(editor, .Left)
			case .DELETE:
				edit.delete_to(editor, .Right)
			case .UP:
				edit.move_to(editor, .End)
				app.curr_chars_stored = write_idx
				return pitch_up_one_semitone(str.to_string(editor.builder^))
			case .DOWN:
				edit.move_to(editor, .End)
				app.curr_chars_stored = write_idx
				return pitch_down_one_semitone(str.to_string(editor.builder^))
			case:
				// Pitch can be at most 3 chars.
				if str.builder_len(editor.builder^) < 3 {
					char := rune(keycode)
					if unicode.is_alpha(char) {
						edit.input_rune(editor, unicode.to_upper(char))
					} else if unicode.is_digit(char) || char == '#' {
						edit.input_rune(editor, char)
					} else {
						handled = false
					}
				} else {
					handled = false
				}
			}
			if !handled {
				app.char_queue[write_idx] = keycode
				write_idx += 1
			}
		}
		app.curr_chars_stored = write_idx
		state.selection = editor.selection
		return str.to_string(editor.builder^)
	}

	step_data := metadata.(Metadata_Track_Step)
	pitch := app.audio.tracks[step_data.track].pitches[step_data.step]
	// Since we re-grab the pitch every frame, we can just temp allocate the display string.
	buf := make([]byte, 32, context.temp_allocator)
	pitch_as_string := get_note_from_num(pitch)
	pitch_box := box_from_cache(
		{.Draw, .Draw_Text, .Clickable, .Edit_Text} + extra_flags,
		config, 
		pitch_as_string,
		id,
		metadata
	)

	// No need to run editing code if the box isn't active.
	if ui_state.last_active_box != pitch_box do return box_signals(pitch_box)

	// All text/edit state and the string buffers used when editing are temporary,
	// So we need to permanently allocate the resulting final result at some point so it can
	// be stored across frames. We also need to store each text editors state across frames.
	builder := str.builder_make(context.temp_allocator)
	editor: edit.State
	edit.init(&editor, context.temp_allocator, context.temp_allocator)
	edit.setup_once(&editor, &builder)
	edit.begin(&editor, 0, &builder)
	edit.input_text(&editor, pitch_as_string)
	
	existing_pitch_box := true
	if pitch_box.id not_in ui_state.text_editors_state {
		ui_state.text_editors_state[pitch_box.id] = Edit_Text_State{}
		existing_pitch_box = false
	}

	state := &ui_state.text_editors_state[pitch_box.id]
	editor.selection = state.selection
	new_pitch := handle_pitch_input(state, &editor, pitch_box)
	if pitch_valid(new_pitch)  && new_pitch != pitch_as_string {
		track := metadata.(Metadata_Track_Step).track 
		step := metadata.(Metadata_Track_Step).step 
		pitch_set_from_note(track, step, new_pitch)
	}
	return box_signals(pitch_box)
}

Slider_Signals :: struct {
	track: Box_Signals,
	grip:  Box_Signals,
}

vertical_slider :: proc(
	config: Box_Config,
	slider_value: ^f32,
	min_val: f32,
	max_val: f32,
	id := "",
 	extra_flags := Box_Flags{},
) -> Slider_Signals {
	container_id := id != "" ? tprintf("{}-container", id) : ""
	track_id := id != "" ? tprintf("{}-track", id) : ""

	child_container(
		config,
		{direction = .Vertical, alignment_horizontal = .Center},
		container_id,
	)
	track := box_from_cache(
		{.Clickable, .Draw, .Scrollable, .Glow, .Frosted},
		{
			size = {{.Percent, 0.5}, {.Percent, 1}},
			color = .Secondary
		},
	)
	track_signals := box_signals(track)
	if track_signals.pressed { 
		delta_from_top := f32(app.mouse.pos.y - track.top_left.y)
		ratio_of_click := delta_from_top / f32(track.prev_height)
		slider_value^  =  (1 - ratio_of_click) * max_val
	}

	grip := box_from_cache(
		{.Clickable, .Draggable, .Draw, .Hot_Animation, .Glow},
		{
			size   = {{.Percent, 0.8}, {.Percent, 0.1}},
			color           = .Primary,
			floating_type   = .Relative_Parent,
			floating_offset = {0.5, map_range(min_val, max_val, 1, 0, slider_value^)},
			corner_radius   = 2,
			edge_softness   = 2,
		},
	)
	grip_signals := box_signals(grip)
	if grip_signals.box == ui_state.dragged_box { 
		undo_push(slider_value)
		mouse_y := f32(app.mouse.pos.y)
        track_top := f32(track.top_left.y)  // This is also from last frame
        track_height := f32(track.prev_height)  // Use last_height instead of height
        normalized_pos := clamp((mouse_y - track_top) / track_height, 0, 1)
        slider_value^ = map_range(f32(0), f32(1), max_val, min_val, normalized_pos)
	}

	if track_signals.scrolled_up || grip_signals.scrolled_up {
		slider_value^ = clamp(slider_value^ + 1, min_val, max_val)
	} else if track_signals.scrolled_down || grip_signals.scrolled_down {
		slider_value^ = clamp(slider_value^ - 1, min_val, max_val)
	}
	return Slider_Signals{track_signals, grip_signals}
}


// Used for radio buttons and checkbox groups only allows for strings or number arguments for now.
multi_button_set :: proc(
	config: Box_Config,
	child_layout: Box_Child_Layout,
	exclusive: bool = true,
	values: []$T,
	id := "",
	extra_flags := Box_Flags{},
	allocator := context.allocator,
) -> [dynamic]T where intrinsics.type_is_string(T) || intrinsics.type_is_numeric(T)
{
	container_id := id != "" ? tprintf("{}-container", id) : ""
	child_container(config, child_layout, container_id)

	Res_Type :: struct {
		signals: Box_Signals,
		value:   T,
	}
	buttons := make([]Res_Type, len(values), context.temp_allocator)

	// --- Draw buttons and store them in a buffer so we can query their signals.
	for value, i in values {
		item_id := id != "" ? tprintf("{}-item-{}", id, i) : ""
		child_container(
			{
				size = Size_Fit_Children,
			},
			{
				direction = .Horizontal,
				gap_horizontal = 7,
			},
			item_id,
		)
		button_id := id != "" ? tprintf("{}-button-{}", id, i) : ""
		b := button(
			{
				size = Size_Fit_Text,
				padding = {10, 10, 10, 10},
				color = .Secondary,
			},
			button_id,
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

		text_id := id != "" ? tprintf("{}-text-{}", id, i) : ""
		text(
			tprintf("{} heya", val_as_str),
			{
				color 		  =  .Background,
				size = Size_Fit_Text_And_Grow,
				text_justify  = {.End, .Center}
			},
			text_id,
		)
		buttons[i] = {b, value}
	}

	/*
		If this is NOT the first frame this button set has existed, there's a chance some of the buttons have been 
		selected, in which case, we visually indicate this..
	*/
	for button in buttons {
		if button.signals.box.selected {
			button.signals.box.config.color = .Warning 
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

// Offset_from_parent is the normal [2]f32 = {x, y} where x,y is between 0 and 1.
// {0,0} means top left, {0.5, 0.5} means center, {1, 1} means bottom right.
// At the moment we assume all dragging windows should be draggable anywhere in the root container,
// we could most likely restrict this to have nested floating windows. i.e. you can't drag some floating
// window outside of it's parent's bounds.
@(deferred_out = box_floating_close_children)
draggable_window :: proc(title: string, child_layout: Box_Child_Layout, id := "", extra_flags := Box_Flags{}) ->
(container_signals: Box_Signals, close_btn_signals: Box_Signals, maximise_button_signals: Box_Signals, maximised: bool) 
{
	container := box_from_cache(
		{.Drop_Shadow},
		{
			floating_type   = .Absolute_Pixel,
			floating_offset = box_center(ui_state.root^),
			size   		    = Size_Fit_Children,
			z_index         = 20,
		},
		"",
		id,
	)
	container_signals = box_signals(container)
	box_open_children(container, child_layout)

	offset_from_root: ^Vec2_f32
	if container.id not_in ui_state.draggable_window_offsets {
		data := Draggable_Window_Metadata {
			// This probably won't work since boxes aren't sized until the end of the frame.
			opened = true,
			// Put floating container in the center of the screen the first time it's created.
			offset = {f32(app.wx) / 2 , f32(app.wy) / 2}
		}
		ui_state.draggable_window_offsets[container.id] = data
	}
	window_metadata := &ui_state.draggable_window_offsets[container.id] 
	offset_from_root = &window_metadata.offset
	container.config.floating_offset = offset_from_root^

	child_container(
		{
			size = {{.Grow, 100}, {.Fit_Children, 1}}
		},
		{direction = .Horizontal},
	)

	maximise_button := text_button(
		"o",
		{
			color = .Green_500,
			size = Size_Fit_Text_And_Grow,
			max_size = {50, 50}
		}
	)
	if maximise_button.clicked { 
		window_metadata.maximised = !window_metadata.maximised
	}

	title_bar := box_from_cache(
		{.Clickable, .Draw_Text, .Draw, .Hot_Animation, .Active_Animation, .Frosted},
		{
			size = {{.Percent, .90}, {.Fit_Text, 1}},
			padding = {top = 5, bottom = 5},
			color = .Tertiary,
			z_index = container.z_index,
		},
		title,
	)
	close_button := text_button(
		"x",
		{
			color = .Error_Container,
			size = Size_Fit_Text_And_Grow,
			max_size = {50, 50}
		},
	)
	if close_button.clicked { 
		window_metadata.opened = false
	}

	title_bar_signals := box_signals(title_bar)
	if ui_state.dragged_box == title_bar {
		if !window_metadata.dragging {
			window_metadata.dragging = true
			// Remember where within the window the user grabbed
			window_metadata.grab_offset = {
				f32(app.mouse.pos.x) - offset_from_root.x,
				f32(app.mouse.pos.y) - offset_from_root.y,
			}
		}
		offset_from_root.x = clamp(f32(app.mouse.pos.x) - window_metadata.grab_offset.x, 0, f32(app.wx - container.prev_width))
		offset_from_root.y = clamp(f32(app.mouse.pos.y) - window_metadata.grab_offset.y, 0, f32(app.wy - container.prev_height))
		container.config.floating_offset = offset_from_root^
	} else {
		window_metadata.dragging = false
	}
	return box_signals(container), close_button, maximise_button, window_metadata.maximised
}

Knob_Type :: enum { 
	Generic, 
	Frequency,
	Q, 
	Gain, 
	Panning,
}

circular_knob :: proc(
    label: string,
    config: Box_Config,
    value: ^f64,
    min_val: f64,
    max_val: f64,
	logarithmic := false,
    id := "",
    knob_size: f32 = 60,  // diameter in pixels
    extra_flags := Box_Flags{},
	type := Knob_Type{}
) {
    // Container
	container_id := id != "" ? tprintf("{}-container", id) : ""
    child_container(
        config,
        {direction = .Vertical, alignment_horizontal = .Center, gap_vertical = 5},
		container_id,
    )

	body_string: string
	switch type {
		case .Q:
			body_string = tprintf("%.3f", value^)
		case .Gain:
			body_string = tprintf("%.2f db", value^)
		case .Frequency:
			body_string = tprintf("%d hz", int(value^))
		case .Generic, .Panning:
			body_string = tprintf("%.2f", value^)
	}
	// Track (circular background)
	knob_body := box_from_cache(
		{.Clickable, .Draw, .Scrollable, .Glow, .Knob_Ring, .Draw_Text},
		{
			size = {{.Fixed, knob_size}, {.Fixed, knob_size}},
			// color = config.color,
			color = .Secondary,
			corner_radius = int(knob_size / 2),  // Makes it circular
			text_color = .Slate_900,
			font_size = 12,
		},
		metadata = Metadata_Knob{f32(min_val), f32(max_val), f32(value^), logarithmic},
		label = body_string
	)
	if type == .Panning do knob_body.flags -= {.Draw_Text, .Knob_Ring}

	knob_body_signals := box_signals(knob_body)

	label_id := id != "" ? tprintf("{}-label", id) : ""
	text(
		label,
		{color = .Red_500, size = Size_Fit_Text},
		label_id,
	)

	scroll_speed := app.keys_held[sdl.Scancode.LSHIFT] ? 200.0 : 40.0
	if knob_body_signals.scrolled_up {
		undo_push(value)
		if logarithmic {
			value^ *= math.pow(max_val / min_val, 1.0 / scroll_speed)
		} else { 
			value^ += (max_val - min_val) / scroll_speed 
		}
	} else if knob_body_signals.scrolled_down  { 
		undo_push(value)
		if logarithmic {
			value^ /= math.pow(max_val / min_val, 1.0 / scroll_speed)
		} else {
			value^ -= (max_val - min_val) / scroll_speed 
		}
	}
	value^ = clamp(value^, min_val, max_val)
   
	knob_indicator: {
		// Calculate grip position
		center_x := f64(knob_body.top_left.x + knob_body.width / 2)
		center_y := f64(knob_body.top_left.y + knob_body.height / 2)
		// This code is parameterized to facilitate ease of tweaking deadzone and scrolling animation,
		// but in the future once I've settled on some values we can hardcode values.

		deadzone_center_deg := 90.0 
		deadzone_size_deg   := 80.0 

		start_angle_deg := deadzone_center_deg + (deadzone_size_deg / 2)
		sweep_range_deg := 360.0 - deadzone_size_deg

		// Convert to radians for use in code.
		start_angle := start_angle_deg * math.PI / 180.0
		sweep_range := sweep_range_deg * math.PI / 180.0

		t := logarithmic \
			? math.ln(value^ / min_val) / math.ln(max_val / min_val) \
			: (value^ - min_val) / (max_val - min_val)
		angle := start_angle + t * sweep_range
		// angle := start_angle + map_range(min_val, max_val, 0, sweep_range, value^)
		
		// Position on circumference
		radius := knob_size / 2 * 0.7
		grip_offset_x := 0.5 + math.cos(angle) * 0.7
		grip_offset_y := 0.5 + math.sin(angle) * 0.7
		
		inner_r := f64(knob_size) / 2 * 0.55
		outer_r := f64(knob_size) / 2 
		line(
			{
				color          = .Primary,
				line_start     = {f32(center_x + math.cos(angle) * inner_r), f32(center_y + math.sin(angle) * inner_r)},
				line_end       = {f32(center_x + math.cos(angle) * outer_r), f32(center_y + math.sin(angle) * outer_r)},
				line_thickness = 5,
				corner_radius  = 1,
				edge_softness  = 1,
			},
		)
	}

	if ui_state.dragged_box == knob_body {
		undo_push(value)
		scale_factor := app.keys_held[sdl.Scancode.LSHIFT] ? 0.8 : 3.8
		delta_y := app.mouse_last_frame.pos.y - app.mouse.pos.y
		normalized := f64(delta_y) / f64(app.wy) // fraction of screen height per pixel drag
		if logarithmic {
			t := math.ln(value^ / min_val) / math.ln(max_val / min_val)
			t  = clamp(t + normalized * scale_factor, 0, 1)
			value^ = min_val * math.pow(max_val / min_val, t)
		} else {
			value^ += normalized * (max_val - min_val) * scale_factor
		}
		value^ = clamp(value^, min_val, max_val)
	} 
}

// Most of the existing layout code and sizing stuff won't really apply to lines.
// We just pass in the start, end and thickness and the renderer works out the rest.
line :: proc(
	config: Box_Config,
	id := "",
	extra_flags := Box_Flags{},
) -> Box_Signals {
	l := box_from_cache(
		{.Draw, .Line} + extra_flags,
		config,
		"",
		id,
	)
	return box_signals(l)
}

Virtual_List_State :: struct {
	first_visible: 		   int,
	last_visible:  		   int,
	total_items:   		   int,
	item_size:   		   int,
	direction:             Layout_Direction,
	container_signals:     Box_Signals,
}

virtual_list_end :: proc(state: Virtual_List_State) {
	items_after := state.total_items - state.last_visible - 1
	if items_after > 0 && state.item_size > 0 {
		end_spacer_size: [2]Box_Size
		switch state.direction {
		case .Vertical:
			end_spacer_size = {{.Grow, 1}, {.Fixed, f32(items_after * state.item_size)}}
		case .Horizontal:
			end_spacer_size = {{.Fixed, f32(items_after * state.item_size)}, {.Grow, 1}}
		}
		box_from_cache(
			{},
			{size = end_spacer_size},
			id = tprintf("{}-vl-end-spacer", state.container_signals.box.id),
		)
	}

	// Close the container (same logic as box_regular_close_children).
	box := state.container_signals.box
	size := box.config.size
	if size.x.type == .Fit_Children || size.x.type == .Fit_Children_And_Grow {
		box.width = sizing_calc_fit_children_width(box^)
	}
	if size.y.type == .Fit_Children || size.y.type == .Fit_Children_And_Grow {
		box.height = sizing_calc_fit_children_height(box^)
	}
	box_clamp_to_constraints(box)

	pop(&ui_state.parents_stack)
	curr_len := len(ui_state.parents_stack)
	if curr_len > 0 {
		ui_state.parents_top = ui_state.parents_stack[curr_len - 1]
	} else {
		ui_state.parents_top = nil
	}
}

VList_Item_Size :: union {
	int,
	f32,
}

@(deferred_out = virtual_list_end)
virtual_list :: proc(
	config: Box_Config,
	child_layout: Box_Child_Layout,
	total_items: int,
	item_size: VList_Item_Size,
	id := "",
	box_flags := Box_Flags{},
	metadata := Box_Metadata{},
) -> Virtual_List_State
{
	config := config
	if config.max_size == {0, 0} do config.max_size = {app.wx, app.wy}

	direction := child_layout.direction
	switch direction {
	case .Vertical:
		config.overflow_y = .Auto
	case .Horizontal:
		// config.overflow_x = .Auto
	}

	box := box_from_cache(box_flags + {.Scrollable}, config, "", id)
	box_open_children(box, child_layout)

	// TODO: X-axis virtualization disabled for now due to clipping issues with floating containers.
	// Re-enable once we have a No_Clip flag or similar solution.
	if direction == .Horizontal {
		return {
			first_visible 		  = 0,
			last_visible  		  = total_items - 1,
			total_items   		  = total_items,
			item_size   		  = 0,
			direction             = direction,
			container_signals     = box_signals(box),
		}
	}

	container_extent: int
	switch direction {
	case .Vertical:
		container_extent = box.config.size.y.type == .Fixed ? int(config.size.y.amount) : box.prev_height
	case .Horizontal:
		// container_extent = box.config.size.x.type == .Fixed ? int(config.size.x.amount) : box.prev_width
	}

	actual_item_size := 0
	switch v in item_size {
		case f32:
			actual_item_size = int(f32(container_extent) * v)
		case int:
			actual_item_size = v
	}

	if actual_item_size <= 0 {
		return {
			first_visible 		  = 0,
			last_visible  		  = total_items - 1,
			total_items   		  = total_items,
			item_size   		  = 0,
			direction             = direction,
			container_signals     = box_signals(box),
		}
	}

	scroll_offset := 0
	if box.id in ui_state.scroll_offsets {
		scroll_offset = ui_state.scroll_offsets[box.id]
	}

	SCROLL_CHANGE_PER_TICK :: 40
	scroll_buffer := (SCROLL_CHANGE_PER_TICK / actual_item_size) + 2
	first := max(scroll_offset / actual_item_size - scroll_buffer, 0)
	visible_count := (container_extent / actual_item_size) + scroll_buffer * 2
	last := min(first + visible_count - 1, total_items - 1)

	// Start spacer: pushes visible items to correct scroll position.
	if first > 0 {
		start_spacer_size: [2]Box_Size
		switch direction {
		case .Vertical:
			start_spacer_size = {{.Grow, 1}, {.Fixed, f32(first * actual_item_size)}}
		case .Horizontal:
			start_spacer_size = {{.Fixed, f32(first * actual_item_size)}, {.Grow, 1}}
		}
		box_from_cache(
			{},
			{size = start_spacer_size},
			id = tprintf("{}-vl-start-spacer", box.id),
		)
	}

	return {
		first_visible 		  = first,
		last_visible  		  = last,
		total_items   		  = total_items,
		item_size   		  = actual_item_size,
		direction             = direction,
		container_signals     = box_signals(box),
	}
}