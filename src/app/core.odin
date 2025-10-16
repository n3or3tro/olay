package app
import "core:flags"
import "core:fmt"
import "core:math/rand"
import "core:mem"
import str "core:strings"
import "core:time"
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
	background_color:   Color,
	corner_radius:      int,
	border_thickness:   int,
	border_color:       int,
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
	position_absolute:  bool,
	// These are % value of how far to the right and how far down from the top left a child will
	// be placed if position_absolute, is set.
	offset_from_parent: [2]f32,
}

Alignment :: enum {
	Center,
	Start,
	End,
	Space_Around,
	Space_Between,
}

Box_Child_Layout :: struct {
	direction:        Layout_Direction,
	gap_horizontal:   int,
	gap_vertical:     int,
	align_horizontal: Alignment,
	align_vertical:   Alignment,
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
	hot:          bool,
	active:       bool,
	signals:      Box_Signals,
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
	z_index:      int,
	next:         ^Box, // Sibling, aka, on the same level of the UI tree. Have the same parent.
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

Box_Data :: enum {
	string,
	int,
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

box_make :: proc(id_string: string, flags: Box_Flags, config: Box_Config) -> ^Box {
	box: ^Box
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
		box.z_index = box.parent.z_index + 1
	}
	if box.config.semantic_size.x.type == .Fixed {
		box.width = int(box.config.semantic_size.x.amount)
	}
	if box.config.semantic_size.y.type == .Fixed {
		box.height = int(box.config.semantic_size.y.amount)
	}
	box.keep = true
	return box
}

box_from_cache :: proc(id_string: string, flags: Box_Flags, config: Box_Config) -> ^Box {
	box: ^Box
	is_new: bool

	if id_string in ui_state.box_cache {
		box = ui_state.box_cache[id_string]
		box.flags = flags
		box.config = config

		// Boxes with fixed sizing have their size set upon creation, so if we're retrieving a box from the cache
		// we need to manually re-set it's sizing info for later layout calculations.
		if box.config.semantic_size.x.type != .Fixed {box.width = 0}
		if box.config.semantic_size.y.type != .Fixed {box.height = 0}
		if box.config.semantic_size.x.type == .Fixed {box.width = int(box.config.semantic_size.x.amount)}
		if box.config.semantic_size.y.type == .Fixed {box.height = int(box.config.semantic_size.y.amount)}
		clear(&box.children)
	} else {
		is_new = true
		persistant_id_string, err := str.clone(id_string)
		new_box := box_make(persistant_id_string, flags, config)
		ui_state.box_cache[persistant_id_string] = new_box
		box = new_box
	}

	// Re-establish parent-child link for boxes from the cache. If we didn't do this and we for example removed
	// a box from the UI that was a child of some parent, that parent would still think it had that child.
	if id_string != "root@root" && ui_state.parents_top != nil {
		if is_new {
			// The box is new, box_make already parented it.
		} else {
			// If the box is from the cache, we must re-parent it manually.
			box.parent = ui_state.parents_top
			append(&ui_state.parents_top.children, box)
			box.z_index = box.parent.z_index + 1
		}
	}
	box.keep = true
	return box
}


box_open_children :: proc(box: ^Box, child_layout: Box_Child_Layout) -> ^Box {
	box.child_layout = child_layout
	append(&ui_state.parents_stack, box)
	ui_state.parents_top = box
	return box
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
	for key, box in ui_state.box_cache {
		if !box.keep {
			printfln("deleting box with id: {}", key)
			delete(box.children)
			delete_key(&ui_state.box_cache, key)
			free(box)
			delete(key)
		}
	}
	// clear(&ui_state.box_cache)
}

/* ============================ Signal Handling =========================== */

mouse_inside_box :: proc(box: ^Box, mouse: [2]i32) -> bool {
	mousex := int(mouse.x)
	mousey := int(mouse.y)
	top_left := box.top_left
	bottom_right := box.bottom_right
	return mousex >= top_left.x && mousex <= bottom_right.x && mousey >= top_left.y && mousey <= bottom_right.y
}

box_signals :: proc(box: ^Box) -> Box_Signals {
	// Return signals computed in previous frame if they exist
	if stored_signals, ok := ui_state.next_frame_signals[box.id_string]; ok {
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
			if box.z_index > hot_box.z_index {
				hot_box = box
			}
		}
		ui_state.hot_box = hot_box
		// printfln("hot box is: {}", ui_state.hot_box.id_string)
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
		if stored, ok := ui_state.next_frame_signals[box.id_string]; ok {
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
				}
				next_signals.dragged_over = next_signals.pressed

				// Scrolling
				if app.mouse.wheel.y != 0 {
					next_signals.scrolled = true
					printfln("scrolling on {}", box.id_string)
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
		ui_state.next_frame_signals[box.id_string] = next_signals
	}

}
/* ============================ End Signal Handling ======================= */

/* ============================ Layout  ============================== */
// Calculates a boxes width based on the widths of it's children.
sizing_calc_fit_width :: proc(box: Box) -> int {
	total := 0
	switch box.child_layout.direction {
	case .Horizontal:
		for child in box.children {
			if !child.config.position_absolute {
				total += child.width
			}
		}
	case .Vertical:
		widest := 0
		for child in box.children {
			if !child.config.position_absolute && child.width > widest {
				widest = child.width
			}
		}
		total = widest
	}
	total += box.child_layout.gap_horizontal * (len(box.children) - 1)
	total += box.config.padding.left + box.config.padding.right
	return total
}

// Calculates a boxes height based on the widths of it's children.
sizing_calc_fit_height :: proc(box: Box) -> int {
	height := 0
	switch box.child_layout.direction {
	case .Vertical:
		for child in box.children {
			if !child.config.position_absolute {
				height += child.height
			}
		}
	case .Horizontal:
		tallest := 0
		for child in box.children {
			if !child.config.position_absolute && child.height > tallest {
				tallest = child.height
			}
		}
		height = tallest
	}
	height += box.child_layout.gap_vertical * (len(box.children) - 1)
	height += box.config.padding.top + box.config.padding.bottom
	return height
}

@(private = "file")
num_of_non_floating_children :: proc(box: Box) -> int {
	tot := 0
	for child in box.children {
		if !child.config.position_absolute {
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
			if child.config.position_absolute {
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
			if child.config.position_absolute {
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
			if child.config.position_absolute {
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
			if !child.config.position_absolute && child.config.semantic_size.y.type == .Grow {
				child.height = available_height
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
		if box.parent.config.semantic_size.x.type == .Fit {
			panic(
				tprintf(
					"A box with size type of .Fit cannot contain a child with size type of .Percent\nIn this case the parent box: {} has sizing type .Fit on it's x-axis and it has a child: {} with sizing type .Percent.",
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
					"A box with size type of .Fit cannot contain a child with size type of .Percent\nIn this case the parent box: {} has sizing type .Fit on it's y-axis and it has a child: {} with sizing type .Percent.",
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

calc_sizing_shrink_width :: proc(box: Box) {
}

calc_text_wrap :: proc(root: Box) {
}

position_boxes :: proc(root: ^Box) {
	position_children :: proc(root: ^Box) {
		// printfln("setting position for {}'s children", root.id_string)
		if root.id_string == "root@root" {
			root.top_left = {0, 0}
			root.bottom_right = {app.wx, app.wy}
		}
		// Need to explicitly track prev sibling since absolutely positioned children are NOT to be
		// included in the layout calculations, if we relied on index of box.children, they would be.
		prev_layout_sibling: ^Box = nil
		for child, i in root.children {
			// Absolutely positioned children won't have padding added when positioning.
			if child.config.position_absolute {
				offset_x := int(f32(root.width) * child.config.offset_from_parent.x)
				offset_y := int(f32(root.height) * child.config.offset_from_parent.y)
				child.top_left = {root.top_left.x + offset_x, root.top_left.y + offset_y}
				child.bottom_right = {child.top_left.x + child.width, child.top_left.y + child.height}
			} else {
				switch root.child_layout.direction {
				case .Horizontal:
					if prev_layout_sibling == nil {
						child.top_left = {
							root.top_left.x + root.config.padding.left,
							root.top_left.y + root.config.padding.top,
						}
						child.bottom_right = {child.top_left.x + child.width, child.top_left.y + child.height}
					} else {
						child.top_left = {
							prev_layout_sibling.bottom_right.x + root.child_layout.gap_horizontal,
							root.top_left.y + root.config.padding.top,
						}
						child.bottom_right = {child.top_left.x + child.width, child.top_left.y + child.height}
					}
				case .Vertical:
					if prev_layout_sibling == nil {
						child.top_left = {
							root.top_left.x + root.config.padding.left,
							root.top_left.y + root.config.padding.top,
						}
						child.bottom_right = {child.top_left.x + child.width, child.top_left.y + child.height}
					} else {
						child.top_left = {
							root.top_left.x + root.config.padding.left,
							prev_layout_sibling.bottom_right.y + root.child_layout.gap_vertical,
						}
						child.bottom_right = {child.top_left.x + child.width, child.top_left.y + child.height}
					}
				}
				prev_layout_sibling = child
			}
			position_children(child)
		}
	}
	position_children(root)
}
/* ============================ END LAYOUT CODE ============================== */
