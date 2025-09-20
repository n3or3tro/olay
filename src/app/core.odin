package app
import "core:flags"
import "core:fmt"
import "core:math/rand"
import "core:mem"
import str "core:strings"
import gl "vendor:OpenGL"
import sdl "vendor:sdl2"

WINDOW_HEIGHT :: 2000
WINDOW_WIDTH :: 1500
// Most children a box can have (created for alloc reasons, etc).
MAX_CHILDREN :: 1024

Vec2_i32 :: [2]i32
Vec3_i32 :: [3]i32
Vec4_i32 :: [4]i32

Vec2_f32 :: [2]f32
Vec3_f32 :: [3]f32
Vec4_f32 :: [4]f32

Vec2_int :: [2]int
Vec3_int :: [3]int
Vec4_int :: [4]int

Color :: [4]f32


// Style and layout info that has to be known upon Box creation.
Box_Config :: struct {
	background_color: Color,
	corner_radius:    int,
	border_thickness: int,
	border_color:     int,
	max_size:         int,
	min_size:         int,
	prefered_size:    int,
	// Internal padding that will surround child elements.
	padding:          struct {
		left:   int,
		top:    int,
		right:  int,
		bottom: int,
	},
	semantic_size:    [2]Box_Size,
	alignment:        [2]enum {
		Start,
		Middle,
		End,
	},
}

Box_Child_Layout :: struct {
	direction:      Layout_Direction,
	gap_horizontal: int,
	gap_vertical:   int,
}

Layout_Direction :: enum {
	Horizontal, // Left to right.
	Vertical, // Top to bottom.
}

Box_Size_Type :: enum {
	Fit,
	Grow,
	Fixed,
	Percent, // Percent of parent.
}

Box_Size :: struct {
	type:   Box_Size_Type,
	amount: f32,
}

Box_Flag :: enum {
	Clickable,
	Scrollable,
	View_Scroll,
	Draw,
	Draw_Text,
	Text_Center,
	Text_Left,
	Text_Right,
	Edit_Text,
	Draw_Border,
	Draw_Background,
	Draw_Drop_Shadow,
	Clipped,
	Hot_Animation,
	Active_Animation,
	Draggable,
	Fixed_Width,
	Floating_X,
	No_Offset, //
}

Box_Flags :: bit_set[Box_Flag]

Box :: struct {
	id_string:    string,
	// Feature flags.
	flags:        Box_Flags,
	// Style and layout config
	config:       Box_Config,
	children:     [dynamic]^Box,
	child_layout: Box_Child_Layout,
	parent:       ^Box,
	data:         Box_Data,
	position:     [2]int, // x, y co-ordinates.
	width:        int,
	height:       int,
	// Probably don't need both tl, br and x,y + width, height
	top_left:     Vec2_int,
	bottom_right: Vec2_int,
	next:         ^Box, // Sibling, aka, on the same level of the UI tree. Have the same parent.
}

Box_Signals :: struct {
	box:            ^Box,
	mouse:          Vec2_i32,
	clicked:        bool,
	double_clicked: bool,
	right_clicked:  bool,
	pressed:        bool,
	released:       bool,
	right_pressed:  bool,
	right_released: bool,
	dragging:       bool,
	dragged_over:   bool,
	hovering:       bool,
	scrolled:       bool,
	scrolled_up:    bool,
	scrolled_down:  bool,
}

Box_Data :: enum {
	string,
	int,
}

UI_State :: struct {
	box_cache:             map[string]^Box,
	// I.e. the node which will parent future children if children_open() has been called.
	parents_top:           ^Box,
	parents_stack:         [dynamic]^Box,
	// font_atlases:          Atlases,
	// font_size:             Font_Size,
	temp_boxes:            [dynamic]^Box,
	first_frame:           bool, // dont want to render on the first frame
	// rect_stack:            [dynamic]Rect,
	settings_toggled:      bool,
	color_stack:           [dynamic]Color,
	// font_size_stack:       [dynamic]Font_Size,
	// ui_scale:              f32, // between 0.0 and 1.0.
	// Used to tell the core layer to override some valu of a box that's in the cache.
	// Useful for parts of the code where the box isn't easilly accessible (like in audio related stuff).
	override_color:        bool,
	override_rect:         bool,
	quad_vbuffer:          ^u32,
	quad_vabuffer:         ^u32,
	quad_shader_program:   u32,
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
	// last_clicked_box_time: time.Time,
	// Added this to help with sorting out z-order event consumption.
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
	// Used to calculate clipping rects and nested clipping rects for overflowing content.
	// clipping_stack:        [dynamic]^Rect,
}

ui_vertex_shader_data :: #load("shaders/box_vertex_shader.glsl")
ui_pixel_shader_data :: #load("shaders/box_pixel_shader.glsl")

Mouse_State :: struct {
	pos:           [2]i32, // these are typed like this to follow the SDL api, else, they'd be u16
	last_pos:      [2]i32, // pos of the mouse in the last frame.
	drag_start:    [2]i32, // -1 if drag was already handled
	drag_end:      [2]i32, // -1 if drag was already handled
	dragging:      bool,
	drag_done:     bool,
	left_pressed:  bool,
	right_pressed: bool,
	wheel:         [2]i8, // -1 moved down, +1 move up
	clicked:       bool, // whether mouse was left clicked in this frame.
	right_clicked: bool, // whether mouse was right clicked in this frame.
}

box_from_cache :: proc(id_string: string, flags: Box_Flags, config: Box_Config) -> ^Box {
	box: ^Box
	is_new := false // Track if we created a new box

	if cached_box, ok := ui_state.box_cache[id_string]; ok {
		box = cached_box

		box.flags = flags
		box.config = config

		if box.config.semantic_size.x.type != .Fixed {box.width = 0}
		if box.config.semantic_size.y.type != .Fixed {box.height = 0}

		if box.config.semantic_size.x.type == .Fixed {box.width = int(box.config.semantic_size.x.amount)}
		if box.config.semantic_size.y.type == .Fixed {box.height = int(box.config.semantic_size.y.amount)}

		clear(&box.children)
	} else {
		is_new = true
		persistant_id_string, err := str.clone(id_string)
		new_box := box_make(id_string, flags, config)
		ui_state.box_cache[persistant_id_string] = new_box
		box = new_box
	}

	// This now runs for BOTH new and cached boxes.
	// We re-establish the parent-child link for the current frame.
	// This is the step that was missing and causing the layout to be "fixed".
	if id_string != "root@root" && ui_state.parents_top != nil {
		if is_new {
			// If the box is new, box_make already parented it.
			// (Assuming original box_make is restored)
		} else {
			// If the box is from the cache, we must re-parent it manually.
			box.parent = ui_state.parents_top
			append(&ui_state.parents_top.children, box)
		}
	}
	return box
}

box_make :: proc(id_string: string, flags: Box_Flags, config: Box_Config) -> ^Box {
	box := new(Box)
	if id_string == "spacer@spacer" {
		box = new(Box, context.temp_allocator)
	} else {
		box = new(Box)
	}
	box.flags = flags
	box.id_string = id_string
	box.config = config
	if id_string != "root@root" {
		box.parent = ui_state.parents_top
		append(&ui_state.parents_top.children, box)
	}
	if box.config.semantic_size.x.type == .Fixed {
		box.width = int(box.config.semantic_size.x.amount)
	}
	if box.config.semantic_size.y.type == .Fixed {
		box.height = int(box.config.semantic_size.y.amount)
	}
	return box
}

box_open_children :: proc(box: ^Box, child_layout: Box_Child_Layout) {
	box.child_layout = child_layout
	append(&ui_state.parents_stack, box)
	ui_state.parents_top = box
}

box_close_children :: proc(box: ^Box) {
	assert(len(ui_state.parents_stack) > 0)
	if box.config.semantic_size.x.type == .Fit {
		box.width = sizing_calc_fit_width(box^)
	}
	if box.config.semantic_size.y.type == .Fit {
		box.height = sizing_calc_fit_height(box^)
	}
	pop(&ui_state.parents_stack)
	curr_len := len(ui_state.parents_stack)
	if curr_len > 0 {
		ui_state.parents_top = ui_state.parents_stack[len(ui_state.parents_stack) - 1]
	} else {
		ui_state.parents_top = nil
	}
}

// Calculates a boxes width based on the widths of it's children.
sizing_calc_fit_width :: proc(box: Box) -> int {
	total := 0
	switch box.child_layout.direction {
	case .Horizontal:
		for child in box.children {
			total += child.width
		}
	case .Vertical:
		widest := 0
		for child in box.children {
			if child.width > widest {
				widest = child.width
			}
		}
		total = widest
	}
	total += box.child_layout.gap_horizontal * (len(box.children) - 1)
	total += box.config.padding.left + box.config.padding.right
	return total
}

sizing_calc_fit_height :: proc(box: Box) -> int {
	height := 0
	switch box.child_layout.direction {
	case .Vertical:
		for child in box.children {
			height += child.height
		}
	case .Horizontal:
		tallest := 0
		for child in box.children {
			if child.height > tallest {
				tallest = child.height
			}
		}
		height = tallest
	}
	height += box.child_layout.gap_vertical * (len(box.children) - 1)
	height += box.config.padding.top + box.config.padding.bottom
	return height
}

// Assumes boxes size is already calculated and we expand it's children to fill the space.
sizing_grow_growable_width :: proc(box: ^Box) {
	// printfln("growing children of: {}", box.id_string)
	switch box.child_layout.direction {
	case .Horizontal:
		remaining_width := box.width - (box.config.padding.left + box.config.padding.right)
		growable_children := make([dynamic]^Box, allocator = context.temp_allocator)
		defer delete(growable_children)
		for child in box.children {
			remaining_width -= child.width
			if child.config.semantic_size.x.type == .Grow {
				append(&growable_children, child)
			}
		}
		remaining_width -= (len(box.children) - 1) * box.child_layout.gap_horizontal

		if len(growable_children) == 0 {
			return
		}
		for remaining_width > 0 {
			smallest := 2 << 30
			second_smallest := 2 << 30
			width_increase := remaining_width
			for child in growable_children {
				if child.width < smallest {
					second_smallest = smallest
					smallest = child.width
				}
				if child.width > smallest {
					second_smallest = min(second_smallest, child.width)
					width_increase = second_smallest - smallest
				}
			}
			width_increase = min(width_increase, remaining_width / len(growable_children))
			if width_increase == 0 {
				// println("breaking out of loop because width increase == 0 but remaining width > 0.")
				// printfln("Actual values: height_width: {} remaining_width: {}", width_increase, remaining_width)
				return
			}
			for child in growable_children {
				if child.width == smallest {
					child.width += width_increase
					remaining_width -= width_increase
				}
			}
		}
	case .Vertical:
		growable_amount :=
			box.width -
			(box.config.padding.left + box.config.padding.right) -
			((box.child_layout.gap_horizontal) * len(box.children) - 1)
		for child in box.children {
			if child.config.semantic_size.x.type == .Grow {
				child.width += growable_amount - child.width
			}
		}
	}
	for &child in box.children {
		sizing_grow_growable_width(child)
	}
}

// Odds are you can create layouts that won't actually work, can do some cool checking / error'ing if this happens.
// or implement some constraints mechanism.
sizing_calc_percent_width :: proc(box: ^Box) {
	no_layout_conflict :: proc(box: ^Box) -> bool {
		if box.parent.config.semantic_size.x.type == .Fit {
			panic(
				tprintf(
					"A box with size type of .Fit cannot contain a child with size type of .Percent\nIn this case the parent box: {} has sizing type .Fit on it's x-axis and it has a child: {} with sizing type .Percent",
					box.parent.id_string,
					box.id_string,
				),
			)
		}
		return true
	}

	// Might want to account for child gap.
	available_width := box.width - (box.config.padding.left + box.config.padding.right)

	for child in box.children {
		if child.config.semantic_size.x.type == .Percent && no_layout_conflict(child) {
			child.width = int(child.config.semantic_size.x.amount * f32(available_width))
		}
	}
	for child in box.children {
		sizing_calc_percent_width(child)
	}
}

sizing_calc_percent_height :: proc(box: ^Box) {
	no_layout_conflict :: proc(box: ^Box) -> bool {
		if box.parent.config.semantic_size.y.type == .Fit {
			panic(
				tprintf(
					"A box with size type of .Fit cannot contain a child with size type of .Percent\nIn this case the parent box: {} has sizing type .Fit on it's y-axis and it has a child: {} with sizing type .Percent",
					box.parent.id_string,
					box.id_string,
				),
			)
		}
		return true
	}

	// Need to account for child gap too.
	available_height := box.height - (box.config.padding.top + box.config.padding.bottom)

	for child in box.children {
		if child.config.semantic_size.y.type == .Percent && no_layout_conflict(child) {
			child.height = int(child.config.semantic_size.y.amount * f32(available_height))
		}
	}
	for child in box.children {
		sizing_calc_percent_height(child)
	}
}

sizing_grow_growable_height :: proc(box: ^Box) {
	switch box.child_layout.direction {
	case .Vertical:
		growable_children := make([dynamic]^Box, allocator = context.temp_allocator)
		defer delete(growable_children)
		remaining_height := box.height
		for child in box.children {
			remaining_height -= child.height
			if child.config.semantic_size.y.type == .Grow {
				append(&growable_children, child)
			}
		}
		remaining_height -= (box.config.padding.top + box.config.padding.bottom)
		remaining_height -= (len(box.children) - 1) * box.child_layout.gap_vertical
		if len(growable_children) == 0 {
			return
		}
		for remaining_height > 0 {
			smallest := 2 << 30
			second_smallest := 2 << 30
			height_increase := remaining_height
			for child in growable_children {
				if child.height < smallest {
					second_smallest = smallest
					smallest = child.height
				}
				if child.height > smallest {
					second_smallest = min(second_smallest, child.height)
					height_increase = second_smallest - smallest
				}
			}
			// Have to check the logic here is correct.
			if len(growable_children) == 0 {
				return
			}
			height_increase = min(height_increase, remaining_height / len(growable_children))
			if height_increase == 0 {
				// println("breaking out of loop because height increase == 0 but remaining height > 0.")
				// printfln("Actual values: height_increase: {} remaining_height: {}", height_increase, remaining_height)
				return
			}
			for child in growable_children {
				if child.height == smallest {
					child.height += height_increase
					remaining_height -= height_increase
				}
			}
		}
	case .Horizontal:
		tallest := 0
		growable_amount :=
			box.height -
			(box.config.padding.top + box.config.padding.bottom) -
			((box.child_layout.gap_vertical) * len(box.children) - 1)
		for child in box.children {
			if child.config.semantic_size.y.type == .Grow {
				child.height += growable_amount - child.height
			}
		}
	}
	for &child in box.children {
		sizing_grow_growable_height(child)
	}
}

calc_sizing_shrink_width :: proc(box: Box) {
}

calc_text_wrap :: proc(root: Box) {
}

calc_positions :: proc(root: Box) {
}

position_boxes :: proc(root: ^Box) {
	position_children :: proc(root: ^Box) {
		// printfln("setting position for {}'s children", root.id_string)
		if root.id_string == "root@root" {
			root.top_left = {0, 0}
			root.bottom_right = {app.wx, app.wy}
		}
		for child, i in root.children {
			switch root.child_layout.direction {
			case .Horizontal:
				if i == 0 {
					child.top_left = {
						root.top_left.x + root.config.padding.left,
						root.top_left.y + root.config.padding.top,
					}
					child.bottom_right = {child.top_left.x + child.width, child.top_left.y + child.height}
				} else {
					prev_sibling := root.children[i - 1]
					child.top_left = {
						prev_sibling.bottom_right.x + root.child_layout.gap_horizontal,
						root.top_left.y + root.config.padding.top,
					}
					child.bottom_right = {child.top_left.x + child.width, child.top_left.y + child.height}
				}
			case .Vertical:
				if i == 0 {
					child.top_left = {
						root.top_left.x + root.config.padding.left,
						root.top_left.y + root.config.padding.top,
					}
					child.bottom_right = {child.top_left.x + child.width, child.top_left.y + child.height}
				} else {
					prev_sibling := root.children[i - 1]
					child.top_left = {
						root.top_left.x + root.config.padding.left,
						prev_sibling.bottom_right.y + root.config.padding.top,
					}
					child.bottom_right = {child.top_left.x + child.width, child.top_left.y + child.height}
				}
			}
			position_children(child)
		}
	}
	position_children(root)
}

collect_render_data_from_ui_tree :: proc(root: ^Box, render_data: ^[dynamic]Rect_Render_Data) {
	// Box may need multiple 'rects' to be rendered to achieve desired affect.
	boxes_rendering_data := get_boxes_rendering_data(root^)
	for data in boxes_rendering_data {
		append_elem(render_data, data)
	}
	for child in root.children {
		collect_render_data_from_ui_tree(child, render_data)
	}
}
