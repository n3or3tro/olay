package app
import "core:flags"
import "core:fmt"
import "core:math/rand"
import "core:mem"
import str "core:strings"
import "core:time"
import "core:unicode/utf8"
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

Vec2_f64 :: [2]f32
Vec3_f64 :: [3]f32
Vec4_f64 :: [4]f32

Vec2_int :: [2]int
Vec3_int :: [3]int
Vec4_int :: [4]int

Color :: [4]f32

// All size variants that require a value, have that value as a ratio 0-1 excpet for Absolute_Pixel which is in pixels.
// Top_* and Bottom_* are ways to easilly pin boxes to various places
Position_Floating_Type :: enum { 
	Not_Floating, 
	Relative_Root,
	Relative_Parent,
	Top_Center,
	Top_Left,
	Top_Right,
	Bottom_Center,
	Bottom_Left,
	Bottom_Right,
	Absolute_Pixel
}

// Style and layout info that has to be known upon Box creation.
Box_Config :: struct {
	background_color:   Color,
	corner_radius:      int,
	border_thickness:   int,
	border_color:       Color,
	max_size:           int,
	min_size:           int,
	prefered_size:      int,
	// Internal padding that will surround child elements.
	padding:            struct {
		left:   int,
		top:    int,
		right:  int,
		bottom: int,
	},
	semantic_size:      [2]Box_Size,
	// Lets you break out of the layout flow and position 'absolutely', relative
	// to immediate parent.
	position_floating:  Position_Floating_Type,
	// These are % value of how far to the right and how far down from the top left a child will
	// be placed if position_absolute, is set.
	position_floating_offset: [2]f32,
	type: 				Box_Type,
	z_index:			int,
}

Alignment :: enum {
	Start,
	Center,
	End,
	Space_Around,
	Space_Between,
}

Box_Child_Layout :: struct {
	direction:            Layout_Direction,
	gap_horizontal:       int,
	gap_vertical:         int,
	alignment_horizontal: Alignment,
	alignment_vertical:   Alignment,
}

Layout_Direction :: enum {
	Horizontal, // Left to right.
	Vertical, // Top to bottom.
}

Box_Size_Type :: enum {
	Fit_Children,
	Fit_Text, // For things like text_buttons which won't have children
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

Box_Metadata :: enum {

}

// Used in places like context menu handling where we need to know what type of UI 
// element we've clicked on.
Box_Type :: enum { 
	None,
	Track_Step,
}

Box_Flags :: bit_set[Box_Flag]

Box :: struct {
	first_frame:  bool,
	id:           string,
	label:        string,
	// Current thing being hovered over this frame, only 1 can exist at the end of each frame.
	hot:          bool,
	// Current thing being clicked on this frame, only 1 can exist at the end of each frame.
	active:       bool,
	// Many UI elements require this idea of being 'selected'. Radio boxes, tracker steps, etc, etc
	// Many boxes can be selected in any given frame.
	selected: 	  bool,
	signals:      Box_Signals,
	// Feature flags.
	flags:        Box_Flags,
	// Style and layout config
	config:       Box_Config,
	children:     [dynamic]^Box,
	child_layout: Box_Child_Layout,
	parent:       ^Box,
	// For boxes that need data associated with them, e.g: edit_text_boxes.
	data:         string,
	width:        int,
	height:       int,
	top_left:     Vec2_int,
	bottom_right: Vec2_int,
	z_index:      int,
	// next:         ^Box, // Sibling, aka, on the same level of the UI tree. Have the same parent.
	keep:         bool, // Indicates whether we keep this box across frame boundaries.
}

Box_Signals :: struct {
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
	box:            ^Box,
	mouse:          Vec2_i32,
}

ui_vertex_shader_data :: #load("shaders/box_vertex_shader.glsl")
ui_pixel_shader_data :: #load("shaders/box_pixel_shader.glsl")

Mouse_State :: struct {
	pos:           [2]int, // these are typed like this to follow the SDL api, else, they'd be u16
	drag_start:    [2]int, // -1 if drag was already handled
	drag_end:      [2]int, // -1 if drag was already handled
	dragging:      bool,
	drag_done:     bool,
	left_pressed:  bool,
	right_pressed: bool,
	wheel:         [2]i8, // -1 moved down, +1 move up
	clicked:       bool, // whether mouse was left clicked in this frame.
	right_clicked: bool, // whether mouse was right clicked in this frame.
}

box_make :: proc(id_string: string, flags: Box_Flags, config: Box_Config) -> ^Box {
	box: ^Box

	if id_string == "spacer@spacer" {
		box = new(Box, context.temp_allocator)
	} else {
		box = new(Box)
	}
	box.flags = flags
	persistant_id, err := str.clone(get_id_from_id_string(id_string))
	label := get_label_from_id_string(id_string)
	box.id = persistant_id
	box.label = label
	box.config = config
	if id_string != "root@root" {
		box.parent = ui_state.parents_top
		append(&ui_state.parents_top.children, box)
		box.z_index = box.parent.z_index + 1
	}
	if box.config.semantic_size.x.type == .Fixed {
		box.width = int(box.config.semantic_size.x.amount)
	}
	if box.config.semantic_size.y.type == .Fixed {
		box.height = int(box.config.semantic_size.y.amount)
	}
	if box.config.semantic_size.x.type == .Fit_Text {
		if .Edit_Text in box.flags {
			box.width = int(font_get_strings_rendered_len(box.data))
		} else {
			box.width = int(font_get_strings_rendered_len(box.label))
		}
	}
	if box.config.semantic_size.y.type == .Fit_Text {
		if .Edit_Text in box.flags {
			box.height = int(font_get_strings_rendered_height(box.data))
		} else {
			box.height = int(font_get_strings_rendered_height(box.label))
		}
	}
	box.keep = true
	box.z_index = config.z_index
	box.first_frame = true
	return box
}

box_from_cache :: proc(id_string: string, flags: Box_Flags, config: Box_Config) -> ^Box {
	box: ^Box
	is_new: bool

	key := get_id_from_id_string(id_string)
	if key in ui_state.box_cache {
		box = ui_state.box_cache[key]
		box.first_frame = false
		box.flags = flags
		box.config = config
		box.label = get_label_from_id_string(id_string)

		// Boxes with fixed sizing have their size set upon creation, so if we're retrieving a box from the cache
		// we need to manually re-set it's sizing info for later layout calculations.
		if box.config.semantic_size.x.type != .Fixed {box.width = 0}
		if box.config.semantic_size.y.type != .Fixed {box.height = 0}
		if box.config.semantic_size.x.type == .Fixed {box.width = int(box.config.semantic_size.x.amount)}
		if box.config.semantic_size.y.type == .Fixed {box.height = int(box.config.semantic_size.y.amount)}
		if box.config.semantic_size.x.type == .Fit_Text {
			if .Edit_Text in box.flags {
				box.width =
					font_get_strings_rendered_len(box.data) + box.config.padding.left + box.config.padding.right
			} else {
				box.width =
					font_get_strings_rendered_len(box.label) + box.config.padding.left + box.config.padding.right
			}
		}
		if box.config.semantic_size.y.type == .Fit_Text {
			if .Edit_Text in box.flags {
				box.height =
					font_get_strings_rendered_height(box.data) + box.config.padding.top + box.config.padding.bottom
			} else {
				box.height =
					font_get_strings_rendered_height(box.label) + box.config.padding.top + box.config.padding.bottom
			}
		}
		clear(&box.children)
	} else {
		is_new = true
		new_box := box_make(id_string, flags, config)
		ui_state.box_cache[new_box.id] = new_box
		box = new_box
	}

	// Re-establish parent-child link for boxes from the cache. If we didn't do this and we for example removed
	// a box from the UI that was a child of some parent, that parent would still think it had that child.
	if key != "root" && ui_state.parents_top != nil {
		if is_new {
			// The box is new, box_make already parented it.
		} else {
			// If the box is from the cache, we must re-parent it manually.
			box.parent = ui_state.parents_top
			append(&ui_state.parents_top.children, box)
			// box.z_index = box.parent.z_index + 1
		}
	}
	box.keep = true
	box.z_index = config.z_index
	return box
}

box_open_children :: proc(box: ^Box, child_layout: Box_Child_Layout) -> ^Box {
	box.child_layout = child_layout
	append(&ui_state.parents_stack, box)
	ui_state.parents_top = box
	return box
}

// Takes in signals since this is automatically called at the end of creation various 'container' boxes.
// And all box creation functions return the signals for the box.
box_close_children :: proc(signals: Box_Signals) {
	box := signals.box
	assert(len(ui_state.parents_stack) > 0)
	if box.config.semantic_size.x.type == .Fit_Children {
		box.width = sizing_calc_fit_children_width(box^)
	}
	if box.config.semantic_size.y.type == .Fit_Children {
		box.height = sizing_calc_fit_children_height(box^)
	}
	pop(&ui_state.parents_stack)
	curr_len := len(ui_state.parents_stack)
	if curr_len > 0 {
		ui_state.parents_top = ui_state.parents_stack[len(ui_state.parents_stack) - 1]
	} else {
		ui_state.parents_top = nil
	}
}

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
		// delete(box.children) <-- was causing weird crashes, thought I'd leak memory without this, but don't seem to be.
		delete_key(&ui_state.box_cache, key)
		free(box)
		delete(key)
	}

	clear(&ui_state.parents_stack)
	ui_state.parents_top = nil
}

/* ============================ Signal Handling =========================== */

mouse_inside_box :: proc(box: ^Box, mouse: [2]int) -> bool {
	mousex := int(mouse.x)
	mousey := int(mouse.y)
	top_left := box.top_left
	bottom_right := box.bottom_right
	return mousex >= top_left.x && mousex <= bottom_right.x && mousey >= top_left.y && mousey <= bottom_right.y
}

box_signals :: proc(box: ^Box) -> Box_Signals {
	// Return signals computed in previous frame if they exist
	if stored_signals, ok := ui_state.next_frame_signals[box.id]; ok {
		// Update box visual state
		box.hot = stored_signals.hovering
		box.active = stored_signals.pressed || stored_signals.clicked
		box.signals = stored_signals
		return stored_signals
	} else {
		this_frame_signals: Box_Signals
		this_frame_signals.box = box
		// Can always immediately set hover state.
		if mouse_inside_box(box, app.mouse.pos) {
			this_frame_signals.hovering = true
		}
		box.signals = this_frame_signals
		return this_frame_signals
	}
}

// Parses UI tree of boxes and gives you back a flat list.
box_tree_to_list :: proc(root: ^Box, allocator := context.allocator) -> [dynamic]^Box {
	recurse_and_add :: proc(box: ^Box, list: ^[dynamic]^Box) {
		append_elem(list, box)
		for child in box.children {
			recurse_and_add(child, list)
		}
	}
	list := make([dynamic]^Box, allocator)
	recurse_and_add(root, &list)
	return list
}

compute_frame_signals :: proc(root: ^Box) {
	candidates_at_mouse := make([dynamic]^Box, allocator = context.temp_allocator)
	mouse_pos := Vec2_f32{f32(app.mouse.pos.x), f32(app.mouse.pos.y)}
	box_list := box_tree_to_list(root, context.temp_allocator)
	// Find all boxes under mouse
	for box in box_list {
		if mouse_inside_box(box, app.mouse.pos) && .Clickable in box.flags {
			append(&candidates_at_mouse, box)
		}
	}

	// Find highest z-index
	hot_box: ^Box
	if len(candidates_at_mouse) > 0 {
		hot_box = candidates_at_mouse[0]
		for box in candidates_at_mouse[1:] {
			if box.z_index >= hot_box.z_index {
				hot_box = box
			}
		}
		ui_state.hot_box = hot_box
	}

	// Record where mouse down started, otherwise starting outside a box and releasing on a box
	// will register as if we clicked on that box.
	if app.mouse.left_pressed && !app.mouse_last_frame.left_pressed {
		ui_state.mouse_down_on = hot_box
	}

	// Process all boxes
	for box in box_list {
		next_signals: Box_Signals
		next_signals.box = box

		// Get previous frame's signals
		prev_signals: Box_Signals
		if stored, ok := ui_state.next_frame_signals[box.id]; ok {
			prev_signals = stored
		}

		// These events should only trigger on the top most box.
		if box == hot_box {
			if app.mouse.left_pressed {
				next_signals.pressed = true
				if !prev_signals.pressed {
					ui_state.active_box = box
				}
			} else if prev_signals.pressed && ui_state.mouse_down_on == box {
				next_signals.clicked = true
				// Double-click detection
				if ui_state.last_clicked_box == box {
					time_diff_ms := (time.now()._nsec - ui_state.last_clicked_box_time._nsec) / 1000 / 1000
					if time_diff_ms <= 400 {
						next_signals.double_clicked = true
					}
				}
				ui_state.last_clicked_box = box
				ui_state.last_clicked_box_time = time.now()
			}

			if app.mouse.right_pressed {
				next_signals.right_pressed = true
			} else if prev_signals.right_pressed {
				next_signals.right_clicked = true
				ui_state.right_clicked_on = box
			}


			// These are events that can just trigger regardless of z-index.
			if mouse_inside_box(box, app.mouse.pos) {
				next_signals.hovering = true
				// Dragging
				if next_signals.pressed && prev_signals.pressed {
					next_signals.dragging = true
				} else { 
					// next_signals.dragging = false
				}
				next_signals.dragged_over = next_signals.pressed

				// Scrolling
				if app.mouse.wheel.y != 0 {
					next_signals.scrolled = true
					printfln("scrolling on {}", box.id)
					if app.mouse.wheel.y > 0 {
						next_signals.scrolled_up = true
					} else if app.mouse.wheel.y < 0 {
						next_signals.scrolled_down = true
					}
				}
			}

		}
		// Maintain active state even if not hot
		if ui_state.active_box == box {
			box.active = true
		}
		ui_state.next_frame_signals[box.id] = next_signals
	}

}

// z-position is set to 0 as default, any box which still has 0 after creation, will inherit the z-index of it's parent.
flow_z_positions::proc(root: ^Box) {
	for child in root.children { 
		if child.z_index == 0 {  
			child.z_index = root.z_index
		}
	}

	for child in root.children { 
		flow_z_positions(child)
	}
}
/* ============================ End Signal Handling ======================= */


/* ============================ Layout  ============================== */
// Calculates a boxes width based on the widths of it's children.
sizing_calc_fit_children_width :: proc(box: Box) -> int {
	total := 0
	switch box.child_layout.direction {

	case .Horizontal:
		for child in box.children {
			if child.config.position_floating == .Not_Floating{
				total += child.width
			}
		}
		total += box.child_layout.gap_horizontal * (num_of_non_floating_children(box) - 1)

	case .Vertical:
		widest := 0
		for child in box.children {
			if child.config.position_floating == .Not_Floating && child.width > widest {
				widest = child.width
			}
		}
		total = widest
	}

	total += box.config.padding.left + box.config.padding.right

	return total
}

// Calculates a boxes height based on the widths of it's children.
sizing_calc_fit_children_height :: proc(box: Box) -> int {
	height := 0
	switch box.child_layout.direction {
	case .Vertical:
		for child in box.children {
			if child.config.position_floating == .Not_Floating {
				height += child.height
			}
		}
	case .Horizontal:
		tallest := 0
		for child in box.children {
			if child.config.position_floating == .Not_Floating && child.height > tallest {
				tallest = child.height
			}
		}
		height = tallest
	}
	height += box.child_layout.gap_vertical * (num_of_non_floating_children(box) - 1)
	height += box.config.padding.top + box.config.padding.bottom
	return height
}

// Re-calculates .Fit_Children sizing after grow/percent passes have updated children
recalc_fit_children_sizing :: proc(box: ^Box) {
    // Recurse to children
    for child in box.children {
        recalc_fit_children_sizing(child)
    }

    if box.config.semantic_size.x.type == .Fit_Children {
        box.width = sizing_calc_fit_children_width(box^)
    }
    if box.config.semantic_size.y.type == .Fit_Children {
        box.height = sizing_calc_fit_children_height(box^)
    }
}

@(private = "file")
num_of_non_floating_children :: proc(box: Box) -> int {
	tot := 0
	for child in box.children {
		if child.config.position_floating  == .Not_Floating{
			tot += 1
		}
	}
	return tot
}

// Assumes boxes size is already calculated and we expand it's children to fill the space.
sizing_grow_growable_width :: proc(box: ^Box) {
	switch box.child_layout.direction {
	case .Horizontal:
		remaining_width := box.width - (box.config.padding.left + box.config.padding.right)
		growable_children := make([dynamic]^Box, allocator = context.temp_allocator)
		defer delete(growable_children)
		for child in box.children {
			if child.config.position_floating != .Not_Floating {
				continue
			}
			remaining_width -= child.width
			if child.config.semantic_size.x.type == .Grow {
				append(&growable_children, child)
			}
		}
		remaining_width -= (num_of_non_floating_children(box^) - 1) * box.child_layout.gap_horizontal
		// if len(growable_children) == 0 {
		// 	return
		// }
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
			if len(growable_children) == 0 {
				return
			}
			width_increase = min(width_increase, remaining_width / len(growable_children))
			if width_increase == 0 {
				return
			}
			for child in growable_children {
				if child.width == smallest {
					child.width += width_increase
					remaining_width -= width_increase
					sizing_calc_percent_width(child)
				}
			}
		}
	case .Vertical:
		growable_amount :=
			box.width -
			(box.config.padding.left + box.config.padding.right) -
			(box.child_layout.gap_horizontal * (num_of_non_floating_children(box^) - 1))
		for child in box.children {
			if child.config.position_floating != .Not_Floating {
				continue
			}
			if child.config.semantic_size.x.type == .Grow {
				child.width += growable_amount - child.width
				sizing_calc_percent_width(child)
			}
		}
	}
	for &child in box.children {
		sizing_grow_growable_width(child)
	}
}

sizing_grow_growable_height :: proc(box: ^Box) {
	switch box.child_layout.direction {
	case .Vertical:
		growable_children := make([dynamic]^Box, allocator = context.temp_allocator)
		defer delete(growable_children)
		remaining_height := box.height
		for child in box.children {
			if child.config.position_floating != .Not_Floating{
				continue
			}
			remaining_height -= child.height
			if child.config.semantic_size.y.type == .Grow {
				append(&growable_children, child)
			}
		}
		remaining_height -= (box.config.padding.top + box.config.padding.bottom)
		remaining_height -= (num_of_non_floating_children(box^) - 1) * box.child_layout.gap_vertical
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
				return
			}
			for child in growable_children {
				if child.height == smallest {
					child.height += height_increase
					remaining_height -= height_increase
					// Since sizing_calc_percent_height in ui.odin runs before
					// we calculate grow sizing, any box with size .grow and whose child is
					// .percent(of_parent)
					sizing_calc_percent_height(child)
				}
			}
		}
	case .Horizontal:
		tallest := 0

		// New and hopefully working / improved code:
		available_height := box.height - (box.config.padding.top + box.config.padding.bottom)
		for child in box.children {
			if child.config.position_floating == .Not_Floating && child.config.semantic_size.y.type == .Grow {
				child.height = available_height
				sizing_calc_percent_height(child)
			}
		}
	}
	for &child in box.children {
		sizing_grow_growable_height(child)
	}
}

// Odds are you can create layouts that won't actually work, can do some cool checking / error'ing if this happens.
// or implement some constraints mechanism.
sizing_calc_percent_width :: proc(box: ^Box) {
	no_layout_conflict :: proc(box: ^Box) -> bool {
		if box.parent.config.semantic_size.x.type == .Fit_Children {
			panic(
				tprintf(
					"A box with size type of .Fit cannot contain a child with size type of .Percent\nIn this case the parent box: {} has sizing type .Fit on it's x-axis and it has a child: {} with sizing type .Percent.",
					box.parent.id,
					box.id,
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
		if box.parent.config.semantic_size.y.type == .Fit_Children {
			panic(
				tprintf(
					"A box with size type of .Fit cannot contain a child with size type of .Percent\nIn this case the parent box: {} has sizing type .Fit on it's y-axis and it has a child: {} with sizing type .Percent.",
					box.parent.id,
					box.id,
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

calc_sizing_shrink_width :: proc(box: Box) {
}

calc_text_wrap :: proc(root: Box) {
}

@(private = "file")
non_floating_children :: proc(box: ^Box, allocator := context.temp_allocator) -> [dynamic]^Box {
	res := make([dynamic]^Box, allocator)
	for child in box.children {
		if child.config.position_floating  == .Not_Floating{
			append(&res, child)
		}
	}
	return res
}

/*
Sizing on the x-axis and y-axis happens on 2 different passes.
I.e. we place the x co-ords of some root's children and then we place their y co-ord in 2 seperate procs.
*/
position_boxes :: proc(root: ^Box) {

	// 100% offset means the far edge of the box is inline with the far edge of the inside
	// of the parents space.
	position_absolute :: proc(parent: ^Box, child: ^Box) {
		switch child.config.position_floating {

		case .Absolute_Pixel:
			child.top_left = {int(child.config.position_floating_offset.x), int(child.config.position_floating_offset.y)}
			child.bottom_right += child.top_left + {child.width, child.height}

		case .Relative_Root:
			width_diff := f32(parent.width - child.width)
			height_diff := f32(parent.height - child.height)

			offset_x := int(width_diff * child.config.position_floating_offset.x)
			offset_y := int(height_diff * child.config.position_floating_offset.y)


			child.top_left = {parent.top_left.x + offset_x, parent.top_left.y + offset_y}
			child.bottom_right = {child.top_left.x + child.width, child.top_left.y + child.height}

		case .Relative_Parent:
			width_diff := f32(child.parent.width - child.width)
			height_diff := f32(child.parent.height - child.height)

			offset_x := int(width_diff * child.config.position_floating_offset.x)
			offset_y := int(height_diff * child.config.position_floating_offset.y)


			child.top_left = {child.parent.top_left.x + offset_x, child.parent.top_left.y + offset_y}
			child.bottom_right = {child.top_left.x + child.width, child.top_left.y + child.height}

		case .Bottom_Center, .Bottom_Left,.Bottom_Right, .Top_Center, .Top_Left, .Top_Right, .Not_Floating:
			panic(tprintf("Have not implemented position child with floating type: {}", child.config.position_floating))
		}
	}

	/* ========== START Position horizontally when horizontal is the main axis ============= */
	// Helper function for positioning children horizontally at start, center or end.
	place_siblings_horizontally :: proc(root: Box, siblings: []^Box, start_x: int, gap: int) {
		prev_sibling: ^Box
		for child in siblings {
			if prev_sibling == nil {
				child.top_left.x = start_x
			} else {
				child.top_left.x = prev_sibling.bottom_right.x + gap
			}
			child.bottom_right.x = child.top_left.x + child.width
			prev_sibling = child
		}
	}

	position_horizontally_start :: proc(root: ^Box) {
		start_x := root.top_left.x + root.config.padding.left
		gap := root.child_layout.gap_horizontal
		valid_children := non_floating_children(root)
		place_siblings_horizontally(root^, valid_children[:], start_x, gap)
	}

	position_horizontally_center :: proc(root: ^Box) {
		total_child_width := 0
		gap := root.child_layout.gap_horizontal
		valid_children := non_floating_children(root)
		for child in valid_children {
			total_child_width += child.width
		}
		available_width :=
			root.width -
			((total_child_width + root.child_layout.gap_horizontal * (len(valid_children) - 1)) +
					root.config.padding.left +
					root.config.padding.right)

		half_width := available_width / 2
		start_x := root.top_left.x + half_width + root.config.padding.left
		place_siblings_horizontally(root^, valid_children[:], start_x, gap)
	}

	// Could probably just iterate backwards from the root.bottom_right.x.
	position_horizontally_end :: proc(root: ^Box) {
		gap := root.child_layout.gap_horizontal
		padding := root.config.padding.left + root.config.padding.right
		total_child_raw_width := 0
		valid_children := non_floating_children(root)
		for child in valid_children {
			total_child_raw_width += child.width
		}
		total_child_width := total_child_raw_width + (gap * (len(valid_children) - 1) + padding)
		start_x := root.bottom_right.x - total_child_width
		place_siblings_horizontally(root^, valid_children[:], start_x, gap)
	}

	// Basically put them in the middle with the remaining space distributed evenly on either end
	position_horizontally_space_around :: proc(root: ^Box) {
	}

	// Distribute space evenly between children.
	// Will ignore root.padding and just consider it 'empty' space to be distributed between.
	position_horizontally_space_between :: proc(root: ^Box) {
	}
	/* ========== END Position horizontally when horizontal is the main axis ============= */


	/* ========== START Position horizontally when horizontal is the cross axis ============= */
	position_horizontally_across_start :: proc(root: ^Box) {
		valid_children := non_floating_children(root)
		for child in valid_children {
			child.top_left.x = root.top_left.x + root.config.padding.left
			child.bottom_right.x = child.top_left.x + child.width
		}
	}

	position_horizontally_across_center :: proc(root: ^Box) {
		valid_children := non_floating_children(root)
		available_width := root.width - (root.config.padding.left + root.config.padding.right)
		for child in valid_children {
			half_width_diff := (available_width - child.width) / 2
			child.top_left.x = root.top_left.x + half_width_diff
			child.bottom_right.x = child.top_left.x + child.width
		}
	}

	position_horizontally_across_end :: proc(root: ^Box) {
		valid_children := non_floating_children(root)
		for child in valid_children {
			child.bottom_right.x = root.bottom_right.x - root.config.padding.right
			child.top_left.x = child.bottom_right.x - child.width
		}
	}
	/* ========== END Position horizontally when horizontal is the cross axis ============= */


	/* ========== START Position vertically when vertical is the main axis ============= */
	// Helper function for position vertically at start, center, or end.
	place_siblings_vertically :: proc(root: Box, siblings: []^Box, start_y: int, gap: int) {
		prev_sibling: ^Box
		for child in siblings {
			if prev_sibling == nil {
				child.top_left.y = start_y
			} else {
				child.top_left.y = prev_sibling.bottom_right.y + gap
			}
			child.bottom_right.y = child.top_left.y + child.height
			prev_sibling = child
		}
	}

	position_vertically_start :: proc(root: ^Box) {
		start_y := root.top_left.y + root.config.padding.top
		gap := root.child_layout.gap_vertical
		siblings := non_floating_children(root)
		place_siblings_vertically(root^, siblings[:], start_y, gap)
	}

	// Probably don't account for padding here. Not sure yet, but for now we don't.
	position_vertically_center :: proc(root: ^Box) {
		gap := root.child_layout.gap_vertical
		siblings := non_floating_children(root)
		total_children_height := 0
		for child in siblings {
			total_children_height += child.height
		}
		available_height :=
			root.height -
			((len(siblings) - 1) * gap + total_children_height + root.config.padding.top + root.config.padding.bottom)
		half_height := available_height / 2
		start_y := root.top_left.y + half_height + root.config.padding.top
		place_siblings_vertically(root^, siblings[:], start_y, gap)
	}

	position_vertically_end :: proc(root: ^Box) {
		gap := root.child_layout.gap_vertical
		siblings := non_floating_children(root)
		padding := root.config.padding.top + root.config.padding.bottom
		total_children_height := 0
		for child in siblings {
			total_children_height += child.height
		}
		total_children_height += (len(siblings) - 1) * gap
		start_y := root.bottom_right.y - total_children_height
		place_siblings_vertically(root^, siblings[:], start_y, gap)
	}
	/* ========== END Position vertically when vertical is the main axis ============= */

	/* ========== Position vertically when vertical is the cross axis ============= */
	position_vertically_across_start :: proc(root: ^Box) {
		valid_children := non_floating_children(root)
		for child in valid_children {
			child.top_left.y = root.top_left.y + root.config.padding.top
			child.bottom_right.y = child.top_left.y + child.height
		}
	}

	position_vertically_across_center :: proc(root: ^Box) {
		valid_children := non_floating_children(root)
		available_height := root.height - (root.config.padding.top + root.config.padding.bottom)
		for child in valid_children {
			half_height_diff := (available_height - child.height) / 2
			child.top_left.y = root.top_left.y + root.config.padding.top + half_height_diff
			child.bottom_right.y = child.top_left.y + child.height
		}
	}

	position_vertically_across_end :: proc(root: ^Box) {
		valid_children := non_floating_children(root)
		for child in valid_children {
			child.bottom_right.y = root.bottom_right.y - root.config.padding.bottom
			child.top_left.y = child.bottom_right.y - child.height
		}
	}
	/* ========== END Position vertically when vertical is the cross axis ============= */

	// Some of the more complicated positioning aren't implemented fully, but start, center and end are.
	position_children :: proc(root: ^Box) {
		// printfln("setting position for {}'s children", root.id_string)
		if root.id == "root@root" {
			root.top_left = {0, 0}
			root.bottom_right = {app.wx, app.wy}
		}
		for child, i in root.children {
			// Absolutely positioned children won't have padding added when positioning.
			if child.config.position_floating != .Not_Floating{
				position_absolute(root, child)
			}
		}
		switch root.child_layout.direction {
		case .Horizontal:
			// Main axis case:
			switch root.child_layout.alignment_horizontal {
			case .Start:
				position_horizontally_start(root)
			case .Center:
				position_horizontally_center(root)
			case .End:
				position_horizontally_end(root)
			case .Space_Around:
				panic("space around not implemented yet")
			case .Space_Between:
				panic("space between not implemented yet")
			}
			// Across axis case:
			switch root.child_layout.alignment_vertical {
			case .Start:
				position_vertically_across_start(root)
			case .Center:
				position_vertically_across_center(root)
			case .End:
				position_vertically_across_end(root)
			case .Space_Around:
				panic("space around not implemented yet")
			case .Space_Between:
				panic("space between not implemented yet")
			}
		case .Vertical:
			// Along axis case:
			switch root.child_layout.alignment_vertical {
			case .Start:
				position_vertically_start(root)
			case .Center:
				position_vertically_center(root)
			case .End:
				position_vertically_end(root)
			case .Space_Around:
				panic("space around not implemented yet")
			case .Space_Between:
				panic("space between not implemented yet")
			}
			// Across axis case:
			switch root.child_layout.alignment_horizontal {
			case .Start:
				position_horizontally_across_start(root)
			case .Center:
				position_horizontally_across_center(root)
			case .End:
				position_horizontally_across_end(root)
			case .Space_Around:
				panic("space around not implemented yet")
			case .Space_Between:
				panic("space between not implemented yet")
			}
		}
		for child in root.children {
			position_children(child)
		}
	}
	position_children(root)
}
/* ============================ END LAYOUT CODE ============================== */
