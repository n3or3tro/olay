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

// text :: proc(id_string: string, config: Box_Config, extra_flags := Box_Flags{}) -> Box_Signals {
// 	b := box_from_cache(id_string, {.Draw_Text, .Text_Center} + extra_flags, config)
// 	return box_signals(b)
// }

text :: proc(label: string, config: Box_Config, id := "", extra_flags := Box_Flags{}) -> Box_Signals {
	b := box_from_cache({.Draw_Text, .Text_Center} + extra_flags, config, label, id)
	return box_signals(b)
}

text_button :: proc(label: string, config: Box_Config, id := "", extra_flags := Box_Flags{}) -> Box_Signals {
	box := box_from_cache({.Clickable, .Hot_Animation, .Active_Animation, .Draw, .Text_Center, .Draw_Text} + extra_flags, config, label, id)
	return box_signals(box)
}

button :: proc(config: Box_Config, id := "", extra_flags := Box_Flags{}) -> Box_Signals {
	box := box_from_cache({.Clickable, .Hot_Animation, .Active_Animation, .Draw}, config, "", id)
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
) -> Box_Signals {
	box := box_from_cache(box_flags, config, "", id, metadata)
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

edit_number_box :: proc(
	config: Box_Config,
	min_val, max_val: int,
	id := "",
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

	box_signals := child_container(
		config,
		{direction = .Horizontal},
		id,
		{.Clickable, .Draw, .Draw_Text, .Edit_Text, .Hot_Animation, .Active_Animation} + extra_flags + flags,
		metadata,
	)
	box := box_signals.box
	box.metadata = metadata

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
			change = Track_Step_Change {
				track = track,
				step = step,
				old_value = old_data,
				new_value = new_data,
				type = .Volume
			}
			if old_data == new_data do break update_audio_state
			app.audio.tracks[track].volumes[step] = new_data
		case .Send1:
			old_data := app.audio.tracks[track].send1[step]
			change = Track_Step_Change {
				track = track,
				step = step,
				old_value = app.audio.tracks[track].send1[step],
				new_value = new_data,
				type = .Send1
			}
			if old_data == new_data do break update_audio_state
			app.audio.tracks[track].send1[step] = new_data
		case .Send2:
			old_data := app.audio.tracks[track].send2[step]
			change = Track_Step_Change {
				track = track,
				step = step,
				old_value = app.audio.tracks[track].send2[step],
				new_value = new_data,
				type = .Send2
			}
			if old_data == new_data do break update_audio_state
			app.audio.tracks[track].send2[step] = new_data
		case .Pitch:
			panic("This shouldn't happen :)")
		}
		undo_stack_push(change)
	} else { 
	}
	box.data = new_data

	edit.end(&editor)
	return box_signals
}

edit_text_box :: proc(
	config: Box_Config,
	text_box_type: Text_Box_Type,
	id := "",
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
		config,
		{direction = .Horizontal},
		id,
		{.Clickable, .Draw, .Draw_Text, .Edit_Text, .Hot_Animation, .Active_Animation} + extra_flags,
		metadata,
	)
	text_container := text_container_signals.box

	if text_box_type == .Pitch {
		if step_metadata, ok := metadata.(Metadata_Track_Step); ok { 
			text_container.metadata = metadata
		} else { 
			panic("When trying to create a edit_text_box, passed in the wrong metadata type.")
		}

		track_num := text_container.metadata.(Metadata_Track_Step).track
		step_num := text_container.metadata.(Metadata_Track_Step).step
		// This constant allocation and deallocation may be problematic.
		if !text_container.fresh && len(text_container.data.(string)) > 0{ 
			delete(text_container.data.(string))
		}
		text_container.data = str.clone(get_note_from_num(app.audio.tracks[track_num].pitches[step_num]))
	} else {
		// Since we ALWAYS delete the previous box.data on a keystroke, a new text box needs an empty "" allocated.
		if text_container.fresh { 
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
	if text_container.id not_in ui_state.text_editors_state {
		ui_state.text_editors_state[text_container.id] = Edit_Text_State{}
		existing_edit_box = false
	}
	state := &ui_state.text_editors_state[text_container.id]
	editor.selection = state.selection

	new_data: string
	update_audio_data:{
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
				old_pitch := app.audio.tracks[track_num].pitches[step_num]
				new_pitch := pitch_get_from_note(new_data)
				if new_pitch == old_pitch {
					break update_audio_data
				}
				change := Track_Step_Change {
					track = track_num,
					step = step_num,
					old_value = old_pitch,
					new_value = new_pitch,
					type = .Pitch
				}
				app.audio.tracks[track_num].pitches[step_num] = new_pitch
				undo_stack_push(change)
			}
		}
	}

	// There should be a way to not have to delete text_container.data every frame that it's selected,
	// but guarding this code with a conditional on new_data != old_data, doesn't work correctly.
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
		{.Clickable, .Draw, .Scrollable},
		{
			semantic_size = {{.Percent, 0.5}, {.Percent, 1}},
			color = .Secondary
		},
		"",
		track_id,
	)
	track_signals := box_signals(track)
	if track_signals.pressed { 
		delta_from_top := f32(app.mouse.pos.y - track.top_left.y)
		ratio_of_click := delta_from_top / f32(track.last_height)
		slider_value^  =  ratio_of_click * max_val
	}

	grip_id := id != "" ? tprintf("{}-grip", id) : ""
	grip := box_from_cache(
		{.Clickable, .Draggable, .Draw, .Hot_Animation},
		{
			semantic_size   = {{.Percent, 0.8}, {.Percent, 0.1}},
			// min_size = {20, 20},
			// max_size = {50, 50},
			// semantic_size   = {{.Fixed, 50}, {.Fixed, 50}},
			color           = .Tertiary,
			floating_type   = .Relative_Parent,
			floating_offset = {0.5, map_range(min_val, max_val, 0, 1, slider_value^)},
			corner_radius   = 2,
			edge_softness   = 2,
		},
		"",
		grip_id,
	)
	// println("created grip :) ")
	grip_signals := box_signals(grip)
	if grip_signals.box == ui_state.dragged_box { 
		mouse_y := f32(app.mouse.pos.y)
        track_top := f32(track.top_left.y)  // This is also from last frame
        track_height := f32(track.last_height)  // Use last_height instead of height
        normalized_pos := clamp((mouse_y - track_top) / track_height, 0, 1)
        slider_value^ = map_range(f32(0), f32(1), min_val, max_val, normalized_pos)
	}

	if track_signals.scrolled || grip_signals.scrolled {
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
				semantic_size = Size_Fit_Children,
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
				semantic_size = Size_Fit_Text,
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
				semantic_size = Size_Fit_Text_And_Grow,
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
(signals: Box_Signals, closed:bool) {
	container := box_from_cache(
		{},
		{
			floating_type   = .Absolute_Pixel,
			floating_offset = box_center(ui_state.root^),
			semantic_size   = Size_Fit_Children,
			z_index         = 20,
		},
		"",
		id,
	)
	container_signals := box_signals(container)
	box_open_children(container, child_layout)

	offset_from_root: ^Vec2_f32
	if container.id not_in ui_state.draggable_window_offsets {
		// Put floating container in the center of the screen the first time it's created.
		ui_state.draggable_window_offsets[container.id] = {f32(app.wx) / 2 , f32(app.wy) / 2}
	}
	offset_from_root = &ui_state.draggable_window_offsets[container.id]
	container.config.floating_offset = offset_from_root^

	topbar_id := id != "" ? tprintf("{}-topbar", id) : ""
	child_container(
		{
			semantic_size = {{.Grow, 100}, {.Fit_Children, 1}}
		},
		{
			direction = .Horizontal,
		},
		topbar_id,
	)
	title_bar_id := id != "" ? tprintf("{}-title-bar", id) : ""
	title_bar := box_from_cache(
		{.Clickable, .Draw_Text, .Draw, .Hot_Animation, .Active_Animation},
		{
			semantic_size = {{.Percent, .95}, {.Fit_Text, 1}},
			padding = {top = 5, bottom = 5},
			color = .Tertiary,
			z_index = container.z_index,
		},
		title,
		title_bar_id,
	)
	close_button_id := id != "" ? tprintf("{}-close-button", id) : ""
	close_button := text_button(
		"x",
		{
			color = .Error_Container,
			semantic_size = Size_Fit_Text_And_Grow,
		},
		close_button_id,
	)

	title_bar_signals := box_signals(title_bar)
	if ui_state.dragged_box == title_bar {
		delta_x := f32(app.mouse.pos.x - app.mouse_last_frame.pos.x)
		delta_y := f32(app.mouse.pos.y - app.mouse_last_frame.pos.y)
		offset_from_root.x = clamp(offset_from_root.x + delta_x, 0, f32(app.wx - container.last_width))
		offset_from_root.y = clamp(offset_from_root.y + delta_y, 0, f32(app.wy - container.last_height))
	}
	return box_signals(container), close_button.clicked
}

circular_knob :: proc(
    label: string,
    config: Box_Config,
    value: ^f32,
    min_val: f32,
    max_val: f32,
    id := "",
    knob_size: f32 = 60,  // diameter in pixels
    extra_flags := Box_Flags{},
) {
    // Container
	container_id := id != "" ? tprintf("{}-container", id) : ""
    child_container(
        config,
        {direction = .Vertical, alignment_horizontal = .Center, gap_vertical = 5},
		container_id,
    )

    // Track (circular background)
	track_id := id != "" ? tprintf("{}-track", id) : ""
    track := box_from_cache(
        {.Clickable, .Draw, .Scrollable},
        {
            semantic_size = {{.Fixed, knob_size}, {.Fixed, knob_size}},
            color = config.color,
            corner_radius = int(knob_size / 2),  // Makes it circular
        },
		"",
		track_id,
    )
	track_signals := box_signals(track)

	label_id := id != "" ? tprintf("{}-label", id) : ""
 	text(
		label,
		{color = .Secondary, semantic_size = Size_Fit_Text},
		label_id,
	)


	if track_signals.scrolled { 
		printfln("inside knob widget and detect scrolling on the track")
		
		if track_signals.scrolled_up {
			println("increasing")
			value^ += max_val / 100
		} else if track_signals.scrolled_down  { 
			println("decreasing")
			value^ -= max_val / 100
		}
	}
	value^ = clamp(value^, min_val, max_val)
   

    // Calculate grip position
    center_x := f32(track.top_left.x + track.width / 2)
    center_y := f32(track.top_left.y + track.height / 2)
 	// This code is parameterized to facilitate ease of tweaking deadzone and scrolling animation,
	// but in the future once I've settled on some values we can hardcode values.

	deadzone_center_deg: f32 = 90.0 
	deadzone_size_deg:   f32 = 80.0 

	// deadzone_center_rad: f32 = 90.0 * math.PI / 180
	// deadzone_size_rad:   f32 = 50.0 

	start_angle_deg: f32 = deadzone_center_deg + (deadzone_size_deg / 2)
	sweep_range_deg: f32 = 360.0 - deadzone_size_deg

	// Convert to radians for use in code.
	start_angle := start_angle_deg * math.PI / 180.0
	sweep_range := sweep_range_deg * math.PI / 180.0

	angle := start_angle + map_range(min_val, max_val, 0, sweep_range, value^)
    
    // Position on circumference
    radius := knob_size / 2 * 0.7
    grip_offset_x := 0.5 + math.cos(angle) * 0.7
    grip_offset_y := 0.5 + math.sin(angle) * 0.7
    
    // Grip
	grip_id := id != "" ? tprintf("{}-grip", id) : ""
    grip := box_from_cache(
        {.Clickable, .Draggable, .Draw, .Hot_Animation},
        {
            semantic_size = {{.Fixed, 10}, {.Fixed, 10}},
            color = .Error_Container,
            floating_type = .Relative_Other,
            floating_offset = {grip_offset_x, grip_offset_y},
			floating_anchor_box = track,
            corner_radius = 5,
        },
		"",
		grip_id,
    )

    // Handle input...
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