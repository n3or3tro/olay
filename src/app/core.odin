package app
import "core:flags"
import "core:fmt"
import str "core:strings"
import "core:time"
import gl "vendor:OpenGL"
import sdl "vendor:sdl2"
import sarr "core:container/small_array"

WINDOW_HEIGHT :: 1000
WINDOW_WIDTH :: 500
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

Color_RGBA :: [4]f32

// All size variants that require a value, have that value as a ratio 0-1 excpet for Absolute_Pixel which is in pixels.
// Top_* and Bottom_* are ways to easilly pin boxes to various places
Position_Floating_Type :: enum { 
	Not_Floating, 
	Relative_Root,
	Relative_Parent,
	// Relative to some other box that isn't the parent nor the root.
	Relative_Other, 
	Top_Center,
	Top_Left,
	Top_Right,
	Bottom_Center,
	Bottom_Left,
	Bottom_Right,
	Center_Center,
	Center_Left,
	Center_Right,
	Absolute_Pixel
}

Box_Padding :: struct { 
	left, top, right, bottom: int
}

Box_Border :: struct {
	left, top, right, bottom: int
}

// Style and layout info that has to be known upon Box creation.
Box_Config :: struct {
	// All other color info can be determined from the main color token, so this is all you
	// need to provide.
	color:  		 	Semantic_Color_Token,
	corner_radius:      int,
	edge_softness:      int,
	// border:   			Box_Border,
	border:   			int,
	// Internal padding that will surround child elements.
	padding: 			Box_Padding,  
	// External space that will put empty space around the outside of this box.
	margin: 			Box_Padding,  
	semantic_size:      [2]Box_Size,
	max_size:           [2]int,
	min_size:           [2]int,
	// Lets you break out of the layout flow and position 'absolutely', relative
	// to immediate parent.
	floating_type:  	Position_Floating_Type,
	// These are % value of how far to the right and how far down from the top left a child will
	// be placed if position_absolute, is set.
	floating_offset: 	[2]f32,
	// Sometimes you want to set some box to float relative a box that isn't
	// it's parent or the root, in that case, you set this pointer = to that box.
	floating_anchor_box: ^Box,
	text_justify:		[2]Text_Alignment,
	z_index:			int,
	line_start: 		Vec2_f32,
	line_end: 			Vec2_f32,
	line_thickness: 	int,
}

// This is a seperate enum so we can have a different default alignment for text. 
// i.e. text is centered by default.
Text_Alignment :: enum { 
	Center, 
	Start, 
	End,
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
	Fit_Children_And_Grow,
	// For things like text_buttons which won't have children
	Fit_Text, 
	// Like above, but also allows to grow along axis (useful lists of text where each 
	// string might be a different length.
	Fit_Text_And_Grow, 
	Grow,
	Fixed,
	Percent, // Percent of parent.
}

Box_Size :: struct {
	type:   Box_Size_Type,
	amount: f32,
}

Metadata_Track_Step :: struct { 
	track: 	int,
	step: 	int, 
	type: 	enum { 
		Pitch, Volume, Send1, Send2
	}
}

Metadata_Track :: struct { 
	track_num: int	
}

Metadata_Sampler :: struct { 
	track_num : int,
}

Metadata_Browser_Item :: struct { 
	is_dir:  bool,
	dir_id:  int,
	file_id: int,
}

Box_Metadata :: union {
	Metadata_Track_Step,
	Metadata_Track,
	Metadata_Sampler,
	Metadata_Browser_Item
}

Box_Flag :: enum {
	Clickable,
	Scrollable,
	View_Scroll,
	Draw,
	// Whether this box is a line.
	Line, 
	Draw_Text,
	Text_Center,
	Text_Left,
	Text_Right,
	Edit_Text,
	Track_Step,
	Draw_Border,
	Draw_Background,
	Draw_Drop_Shadow,
	Clipped,
	Hot_Animation,
	// disabled state propogates down the tree automatically,
	// some children should ALWAYS be enabled, hence the flag.
	Ignore_Parent_Disabled,
	Active_Animation,
	Draggable,
	Drag_Drop_Source,
	Drag_Drop_Sink, 
	Fixed_Width,
	Floating_X,
	No_Offset, //
}

Box_Flags :: bit_set[Box_Flag]

Box_Data :: union {
	string, 
	int,
	f64,
}

Box :: struct {
	fresh:  bool,
	id:           string,
	label:        string,
	// Current thing being hovered over this frame, only 1 can exist at the end of each frame.
	hot:          bool,
	// Current thing being clicked on this frame, only 1 can exist at the end of each frame.
	active:       bool,
	// Many UI elements require this idea of being 'selected'. Radio boxes, tracker steps, etc, etc
	// Many boxes can be selected in any given frame.
	selected: 	  bool,
	// Various boxes have this idea of being disabled
	disabled: 	  bool,
	signals:      Box_Signals,
	// Feature flags.
	flags:        Box_Flags,
	// Style and layout config
	config:       Box_Config,
	children:     [dynamic]^Box,
	child_layout: Box_Child_Layout,
	parent:       ^Box,
	// For boxes that need data associated with them, e.g: edit_text_boxes.
	data:         Box_Data,
	// Temporary field I'm using while debugging tracker step mem corruption issue. 
	// It will act as the backing buffer of the box.data string.
	data_buffer:  [64]byte, // Delete after, don't use this in production.
	width:        int,
	height:       int,
	// We need to keep track of these for calculations we perform when building the tree,
	// for example calculating drag deltas (dragging volume handle up a track, track height)
	// needs to be known.
	last_height:  int,
	last_width:   int,
	top_left:     Vec2_int,
	bottom_right: Vec2_int,
	// Store where tl and br were last frame. Sometimes we need to know these co-ords for the box during UI creation and they don't 
	// exist until the end of the frame. In most of these cases we can use the position from the last frame, this might be fucky with animations
	// and such, but using prev_width / height has been okay so far.
	// last_top_left:     Vec2_int,
	// last_bottom_right: Vec2_int,
	z_index:      int,
	// next:         ^Box, // Sibling, aka, on the same level of the UI tree. Have the same parent.
	keep:         bool, // Indicates whether we keep this box across frame boundaries.
	metadata: 	  Box_Metadata,
}

Box_Signals :: struct {
	clicked:        bool,
	shift_clicked:  bool,
	double_clicked: bool,
	right_clicked:  bool,
	pressed:        bool,
	released:       bool,
	right_pressed:  bool,
	right_released: bool,
	dragged_over:   bool,
	dropped_on: 	bool,
	hovering:       bool,
	scrolled:       bool,
	scrolled_up:    bool,
	scrolled_down:  bool,
	box:            ^Box,
}

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

ui_vertex_shader_data :: #load("shaders/box_vertex_shader.glsl")
ui_pixel_shader_data :: #load("shaders/box_pixel_shader.glsl")

/* ======================= Start Core Box Code ========================= */

@(private="file")
box_make :: proc(id_string: string, flags: Box_Flags, config: Box_Config, allocator := context.allocator) -> ^Box {
	box := new(Box, context.allocator)

	persistant_id, err := str.clone(get_id_from_id_string(id_string))
	label := get_label_from_id_string(id_string)
	box.id = persistant_id
	box.label = label

	box.flags = flags
	box.config = config

	if id_string != "root@root" {
		box.parent = ui_state.parents_top
		append(&ui_state.parents_top.children, box)
		box.z_index = box.parent.z_index + 1
	}

	x_size_type := box.config.semantic_size.x.type 
	y_size_type := box.config.semantic_size.y.type 

	if x_size_type == .Fixed {
		box.width = int(box.config.semantic_size.x.amount)
	}
	if y_size_type == .Fixed {
		box.height = int(box.config.semantic_size.y.amount)
	}

	if x_size_type == .Fit_Text || x_size_type == .Fit_Text_And_Grow  {
		if .Edit_Text in box.flags {
			data_as_string := box_data_as_string(box.data, context.temp_allocator)
			box.width = int(font_get_strings_rendered_len(data_as_string))
		} else {
			box.width = int(font_get_strings_rendered_len(box.label))
		}
	}
	if y_size_type == .Fit_Text || y_size_type == .Fit_Text_And_Grow {
		if .Edit_Text in box.flags {
			data_as_string := box_data_as_string(box.data, context.temp_allocator)
			box.height = int(font_get_strings_rendered_height(data_as_string))
		} else {
			box.height = int(font_get_strings_rendered_height(box.label))
		}
	}
	box.keep = true
	box.z_index = config.z_index
	box.fresh = true
	if box.parent != nil {
		if !(.Ignore_Parent_Disabled in box.flags) {
			box.disabled = box.parent.disabled
		}
	}
	box_clamp_to_constraints(box)
	return box
}

box_from_cache :: proc(id_string: string, flags: Box_Flags, config: Box_Config, metadata := Box_Metadata{}) -> ^Box {
	box: ^Box
	is_new: bool
	key := get_id_from_id_string(id_string)

	if key in ui_state.box_cache {
		box = ui_state.box_cache[key]
		box.fresh = false
		box.keep = true
		box.flags = flags
		box.config = config
		box.z_index = config.z_index
		// Label is recreated each frame, so it's temp allocated.
		box.label = get_label_from_id_string(id_string)

		// Boxes with fixed sizing have their size set upon creation, so if we're retrieving a box from the cache
		// we need to manually re-set it's sizing info for later layout calculations.
		x_size_type := box.config.semantic_size.x.type 
		y_size_type := box.config.semantic_size.y.type 
		// Not sure if you even need to skip .Fixed sized boxes here... Need to double check.
		if x_size_type != .Fixed {
			box.last_width = box.width
			box.width = 0
		}
		if y_size_type != .Fixed {
			box.last_height = box.height
			box.height = 0
		}

		if x_size_type == .Fixed do box.width  = int(box.config.semantic_size.x.amount)
		if y_size_type == .Fixed do box.height = int(box.config.semantic_size.y.amount)

		if x_size_type == .Fit_Text || x_size_type == .Fit_Text_And_Grow {
			if .Edit_Text in box.flags {
				data_as_string := box_data_as_string(box.data, context.temp_allocator)
				box.width =
					font_get_strings_rendered_len(data_as_string) + box.config.padding.left + box.config.padding.right
			} else {
				box.width =
					font_get_strings_rendered_len(box.label) + box.config.padding.left + box.config.padding.right
			}
		}
		if y_size_type == .Fit_Text || y_size_type == .Fit_Text_And_Grow {
			if .Edit_Text in box.flags {
				data_as_string := box_data_as_string(box.data, context.temp_allocator)
				box.height =
					font_get_strings_rendered_height(data_as_string) + box.config.padding.top + box.config.padding.bottom
			} else {
				box.height =
					font_get_strings_rendered_height(box.label) + box.config.padding.top + box.config.padding.bottom
			}
		}
		clear(&box.children)
		box_clamp_to_constraints(box)
	} else {
		is_new = true
		new_box := box_make(id_string, flags, config)
		ui_state.box_cache[new_box.id] = new_box
		box = new_box
	}

	// Re-establish parent-child link for boxes from the cache. If we didn't do this and we for example removed
	// a box from the UI that was a child of some parent, that parent would still think it had that child.
	if ui_state.parents_top != nil && key != "root" {
		if is_new {
			// The box is new, box_make already parented it.
		} else {
			// If the box is from the cache, we must re-parent it manually.
			box.parent = ui_state.parents_top
			append(&ui_state.parents_top.children, box)
			// box.z_index = box.parent.z_index + 1
		}
	}
	if box.parent != nil { 
		if .Ignore_Parent_Disabled not_in box.flags { 
			box.disabled = box.parent.disabled
		}
	}
	box.metadata = metadata
	return box
}

box_open_children :: proc(box: ^Box, child_layout: Box_Child_Layout) -> ^Box {
	box.child_layout = child_layout
	append(&ui_state.parents_stack, box)
	ui_state.parents_top = box
	return box
}


box_close_children :: proc {
	box_floating_close_children,
	box_regular_close_children
}


box_floating_close_children :: proc(signals: Box_Signals, closed: bool) {
	box_regular_close_children(signals)
}

// Takes in signals since this is automatically called at the end of creation various 'container' boxes.
// And all box creation functions return the signals for the box.
box_regular_close_children :: proc(signals: Box_Signals) {
	box := signals.box
	size := box.config.semantic_size
	assert(len(ui_state.parents_stack) > 0)
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
		ui_state.parents_top = ui_state.parents_stack[len(ui_state.parents_stack) - 1]
	} else {
		ui_state.parents_top = nil
	}
}
/* ======================= End Core Box Code ========================= */



/* ============================ Signal Handling =========================== */
handle_input :: proc(event: sdl.Event) -> (exit, show_context_menu: bool) {
	show_context_menu = ui_state.context_menu.active
	etype := event.type

	if etype == .QUIT {
		exit = true
	}

	if etype == .MOUSEMOTION {
		mouse_x, mouse_y:i32
		sdl.GetMouseState(&mouse_x, &mouse_y)
		x := int(event.motion.x)
		y := int(event.motion.y)
		// printfln("event.motion values: [{}, {}]", x, y)
		app.mouse.pos.x = int(mouse_x)
		app.mouse.pos.y = int(mouse_y)
		// printfln("GetMouseState values: [{}, {}]\n", app.mouse.pos.x, app.mouse.pos.y)
		if ([2]int{x,y} != app.mouse.pos.xy) { 
			println("fuaaaaaark ^^^^^^")
		}
	}

	// We cannot just rely on querying the current 'keys held down' for typing in input fields,
	// since order matters and querying some matrix of keys down does NOT preserve input order.
	// It would work for querying if we're in the state to trigger some keyboard shortcut however.
	if etype == .KEYDOWN {
		#partial switch event.key.keysym.sym {
			case .ESCAPE:
				ui_state.dragged_box = nil
			case:
				app.char_queue[app.curr_chars_stored] = event.key.keysym.sym
				app.curr_chars_stored += 1
				app.keys_held[event.key.keysym.scancode] = true
		}
	}

	if etype == .KEYUP {
		app.keys_held[event.key.keysym.scancode] = false
	}

	if etype == .MOUSEWHEEL {
		app.mouse.wheel.x = cast(i8)event.wheel.x
		app.mouse.wheel.y = cast(i8)event.wheel.y
	}

	if etype == .MOUSEBUTTONDOWN {
		switch event.button.button {
		case sdl.BUTTON_LEFT:
			if !app.mouse.left_pressed { 	// i.e. if left button wasn't pressed last frame
				app.mouse.drag_start = app.mouse.pos
				app.mouse.dragging = true
				app.mouse.drag_done = false
				// show_context_menu = false
			}
			app.mouse.left_pressed = true
		case sdl.BUTTON_RIGHT:
			app.mouse.right_pressed = true
		}
	}

	if etype == .MOUSEBUTTONUP {
		switch event.button.button {
		case sdl.BUTTON_LEFT:
			if app.mouse.left_pressed {
				app.mouse.clicked = true
			}
			app.mouse.left_pressed = false
			app.mouse.drag_end = app.mouse.pos
			app.mouse.dragging = false
			app.mouse.drag_done = true

		case sdl.BUTTON_RIGHT:
			if app.mouse.right_pressed { 	// i.e. A right click was performed.
				app.mouse.right_clicked = true
				show_context_menu = true
				ui_state.context_menu.pos = Vec2_f32{f32(app.mouse.pos.x), f32(app.mouse.pos.y)}
			}
			app.mouse.right_pressed = false
		}
	}

	// if etype == .DROPFILE {
	// 	which, on_track := dropped_on_track()
	// 	if on_track {
	// 		printfln("file was dropped on track {}", which)
	// 	}
	// 	assert(on_track)
	// 	if on_track {
	// 		set_track_sound(event.drop.file, which)
	// 	}
	// }

	return exit, show_context_menu
}

register_resize :: proc() -> bool {
	old_width, old_height := app.wx, app.wy
	new_width, new_height: i32
	sdl.GetWindowSize(app.window, &new_width, &new_height)
	app.wx = int(new_width)
	app.wy = int(new_height)
	if old_width != app.wx || old_height != app.wy {
		gl.Viewport(0, 0, i32(app.wx), i32(app.wy))
		set_shader_vec2(ui_state.quad_shader_program, "screen_res", {f32(app.wx), f32(app.wy)})
		return true
	}

	// Recalc where floating windows should go.

	return false
}

reset_mouse_state :: proc() {
	app.mouse.wheel = {0, 0}
	app.mouse_last_frame = app.mouse
	if app.mouse.clicked {
		// do this here because events are captured before ui is created,
		// meaning context-menu.button1.signals.click will never be set.
		// printfln("last active box clicked on was: {}", ui_state.last_active_box.id)
		// _, clicked_on_context_menu := ui_state.last_active_box.metadata.(Context_Menu_Metadata)
		// if !clicked_on_context_menu {
		// 	ui_state.context_menu.active = false
		// }
	}
	app.mouse.clicked = false
	app.mouse.right_clicked = false
}

mouse_inside_box :: proc(box: ^Box, mouse: [2]int) -> bool {
	mousex := int(mouse.x)
	mousey := int(mouse.y)
	top_left := box.top_left
	bottom_right := box.bottom_right
	return mousex >= top_left.x 	&& 
		   mousex <= bottom_right.x && 
		   mousey >= top_left.y 	&& 
		   mousey <= bottom_right.y
}

box_signals :: proc(box: ^Box) -> Box_Signals {
	// Return signals computed in previous frame if they exist
	if stored_signals, ok := ui_state.frame_signals[box.id]; ok {
		// Update box visual state these 
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

collect_frame_signals :: proc(root: ^Box) {
	candidates_at_mouse := make([dynamic]^Box, allocator = context.temp_allocator)
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

		// Skip signal gathering if box is disabled.
		if box.disabled { 
			// One second thoughts, this is probably overkill since we might want to, for example
			// right click and activate a track, if it's disabled, we can't do that.
			continue
		}

		// Get frame signals from previous frame.
		prev_siganls: Box_Signals
		if stored, ok := ui_state.frame_signals[box.id]; ok {
			prev_siganls = stored
		}

		// These events should only trigger on the top most box.
		if box == hot_box {
			if app.mouse.left_pressed {
				next_signals.pressed = true
				if !prev_siganls.pressed {
					ui_state.active_box = box
				}
			} else if prev_siganls.pressed && ui_state.mouse_down_on == box {
				next_signals.clicked = true
				// Double-click detection
				if ui_state.last_clicked_box == box {
					time_diff_ms := (time.now()._nsec - ui_state.last_clicked_box_time._nsec) / 1000 / 1000
					if time_diff_ms <= 400 {
						next_signals.double_clicked = true
					}
				}
				if app.keys_held[sdl.Scancode.LSHIFT] || app.keys_held[sdl.Scancode.RSHIFT] {
					next_signals.shift_clicked = true
				}
				ui_state.last_clicked_box = box
				ui_state.last_clicked_box_time = time.now()
			}

			if !app.mouse.left_pressed && prev_siganls.pressed {
				if .Drag_Drop_Sink in box.flags && (ui_state.dragged_box != nil && .Drag_Drop_Source in ui_state.dragged_box.(^Box).flags) {
					next_signals.dropped_on = true
				}
			}

			if app.mouse.right_pressed {
				next_signals.right_pressed = true
			} else if prev_siganls.right_pressed {
				next_signals.right_clicked = true
				ui_state.right_clicked_on = box
			}


			// These are events that can just trigger regardless of z-index.
			if mouse_inside_box(box, app.mouse.pos) {
				next_signals.hovering = true
				// Only set a new dragged box if we've previously let go of the mouse, which is indicated
				// by ui_state.dragged_box, since this is only set to nil, when the mouse button goes up.
				if next_signals.pressed && prev_siganls.pressed {
					// This check avoids changing the dragged box when the mouse escapes
					// the previous drag target.
					if ui_state.dragged_box == nil {
						ui_state.dragged_box = box
					}
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

		// Maintain active state even if not hot.
		if ui_state.active_box == box {
			box.active = true
		}
		ui_state.frame_signals[box.id] = next_signals
	}

}

// Automatically handles dragging for floating positioned boxes that are draggable. i.e floating windows.
handle_automatic_dragging :: proc() {
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
			if child.config.floating_type == .Not_Floating{
				total += child.width + box_get_margin_x_tot(child^)
			}
		}
		num_children := num_of_non_floating_children(box)
		if num_children > 1 {
			total += box.child_layout.gap_horizontal * (num_children - 1)
		}

	case .Vertical:
		widest := 0
		for child in box.children {
			if child.config.floating_type == .Not_Floating {
				child_total_width := child.width + box_get_margin_x_tot(child^)
				if child_total_width > widest {
					widest = child_total_width
				}
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
			if child.config.floating_type == .Not_Floating {
				height += child.height + box_get_margin_y_tot(child^)
			}
		}
	case .Horizontal:
		tallest := 0
		for child in box.children {
			if child.config.floating_type == .Not_Floating {
				child_total_height := child.height + box_get_margin_y_tot(child^)
				if child_total_height > tallest {
					tallest = child_total_height
				}
			}
		}
		height = tallest
	}
	num_children := num_of_non_floating_children(box)
	if num_children > 1 {
		height += box.child_layout.gap_vertical * (num_children - 1)
	}
	height += box.config.padding.top + box.config.padding.bottom
	return height
}

// Re-calculates .Fit_Children sizing after grow/percent passes have updated children
recalc_fit_children_sizing :: proc(box: ^Box) {
    // Recurse to children
    for child in box.children {
        recalc_fit_children_sizing(child)
    }

	x_size_type := box.config.semantic_size.x.type
    if x_size_type == .Fit_Children || x_size_type == .Fit_Children_And_Grow {
        box.width = sizing_calc_fit_children_width(box^)
    }

	y_size_type := box.config.semantic_size.y.type
    if y_size_type == .Fit_Children || y_size_type == .Fit_Children_And_Grow {
        box.height = sizing_calc_fit_children_height(box^)
    }

	box_clamp_to_constraints(box)
}

@(private = "file")
num_of_non_floating_children :: proc(box: Box) -> int {
	tot := 0
	for child in box.children {
		if child.config.floating_type  == .Not_Floating{
			tot += 1
		}
	}
	return tot
}

// Clamps box dimensions to respect min_size and max_size constraints
box_clamp_to_constraints :: proc(box: ^Box) {
	// Clamp width
	if box.config.min_size.x > 0 {
		box.width = max(box.width, box.config.min_size.x)
	}
	if box.config.max_size.x > 0 {
		box.width = min(box.width, box.config.max_size.x)
	}

	// Clamp height
	if box.config.min_size.y > 0 {
		box.height = max(box.height, box.config.min_size.y)
	}
	if box.config.max_size.y > 0 {
		box.height = min(box.height, box.config.max_size.y)
	}
}

// Assumes boxes size is already calculated and we expand it's children to fill the space.
sizing_grow_growable_width :: proc(box: ^Box) {
	switch box.child_layout.direction {
	case .Horizontal:
		remaining_width := box.width - box_get_padding_x_tot(box^) 
		growable_children := make([dynamic]^Box, allocator = context.temp_allocator)
		for child in box.children {
			if child.config.floating_type != .Not_Floating {
				continue
			}
			remaining_width -= child.width + box_get_margin_x_tot(child^)
			size_type := child.config.semantic_size.x.type
			if size_type == .Grow || size_type == .Fit_Text_And_Grow || size_type == .Fit_Children_And_Grow {
				append(&growable_children, child)
			}
		}
		remaining_width -= (num_of_non_floating_children(box^) - 1) * box.child_layout.gap_horizontal
		for remaining_width > 0 {
			smallest := 2 << 30
			second_smallest := 2 << 30
			width_increase := remaining_width
			for child in growable_children {
				child_tot_width := child.width + box_get_margin_x_tot(child^)
				if child_tot_width < smallest {
					second_smallest = smallest
					smallest = child_tot_width
				}
				if child_tot_width > smallest {
					second_smallest = min(second_smallest, child_tot_width)
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
				child_tot_width := child.width + box_get_margin_x_tot(child^)
				if  child_tot_width == smallest {
					child.width += width_increase
					box_clamp_to_constraints(child)
					remaining_width -= width_increase
					sizing_calc_percent_width(child)
				}
			}
		}
	case .Vertical:
		growable_amount := box.width - box_get_padding_x_tot(box^)
		for child in box.children {
			if child.config.floating_type != .Not_Floating {
				continue
			}
			size_type := child.config.semantic_size.x.type
			if size_type == .Grow || size_type == .Fit_Text_And_Grow  || size_type == .Fit_Children_And_Grow {
				child.width += growable_amount - (child.width + box_get_margin_x_tot(child^))
				box_clamp_to_constraints(child)
				sizing_calc_percent_width(child)
			}
		}
	}
	for &child in box.children {
		sizing_grow_growable_width(child)
	}
}

// Assumes boxes size is already calculated and we expand it's children to fill the space.
sizing_grow_growable_height :: proc(box: ^Box) {
	switch box.child_layout.direction {
	case .Vertical:
		remaining_height := box.height - box_get_padding_y_tot(box^)
		growable_children := make([dynamic]^Box, allocator = context.temp_allocator)
		for child in box.children {
			if child.config.floating_type != .Not_Floating{
				continue
			}
			remaining_height -= child.height + box_get_margin_y_tot(child^)
			size_type := child.config.semantic_size.y.type
			if size_type == .Grow  || size_type == .Fit_Text_And_Grow || size_type == .Fit_Children_And_Grow {
				append(&growable_children, child)
			}
		}
		remaining_height -= (num_of_non_floating_children(box^) - 1) * box.child_layout.gap_vertical
		for remaining_height > 0 {
			smallest := 2 << 30
			second_smallest := 2 << 30
			height_increase := remaining_height
			for child in growable_children {
				child_tot_height := child.height + box_get_margin_y_tot(child^)
				if child_tot_height < smallest {
					second_smallest = smallest
					smallest = child_tot_height
				}
				if child_tot_height > smallest {
					second_smallest = min(second_smallest, child_tot_height)
					height_increase = second_smallest - smallest
				}
			}
			// Have to check the logic here is correct.
			if len(growable_children) == 0 {
				// return <--- this was causing the recursion at the bottom of this function to not run
							// that recursion HAS to run. 
				return
				// break
			}
			height_increase = min(height_increase, remaining_height / len(growable_children))
			if height_increase == 0 {
				// return <--- this was causing the recursion at the bottom of this function to not run
							// that recursion HAS to run. 
				return
				// break
			}
			for child in growable_children {
				child_tot_height := child.height + box_get_margin_y_tot(child^)
				if child_tot_height == smallest {
					child.height += height_increase
					box_clamp_to_constraints(child)
					remaining_height -= height_increase
					// Since sizing_calc_percent_height in ui.odin runs before
					// we calculate grow sizing, any box with size .grow and whose child is
					// .percent(of_parent)
					sizing_calc_percent_height(child)
				}
			}
		}
	case .Horizontal:
		growable_amount := box.height - box_get_padding_y_tot(box^)
		for child in box.children {
			if child.config.floating_type != .Not_Floating {
				continue
			}
			size_type := child.config.semantic_size.y.type
			if size_type == .Grow || size_type == .Fit_Text_And_Grow || size_type == .Fit_Children_And_Grow {
				child.height += growable_amount - (child.height + box_get_margin_y_tot(child^))
				box_clamp_to_constraints(child)
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
		// if child.config.floating_type == .Not_Floating && child.config.semantic_size.x.type == .Percent && no_layout_conflict(child) {
		if child.config.semantic_size.x.type == .Percent && no_layout_conflict(child) {
			child.width = int(child.config.semantic_size.x.amount * f32(available_width))
			box_clamp_to_constraints(child)
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
		// if child.config.floating_type == .Not_Floating && child.config.semantic_size.y.type == .Percent && no_layout_conflict(child) {
		if child.config.semantic_size.y.type == .Percent && no_layout_conflict(child) {
			child.height = int(child.config.semantic_size.y.amount * f32(available_height))
			box_clamp_to_constraints(child)
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
		if child.config.floating_type  == .Not_Floating{
			append(&res, child)
		}
	}
	return res
}

/*
Sizing on the x-axis and y-axis happens on 2 different passes.
I.e. we place the x co-ords of some root's children and then we place their y co-ord in 2 seperate procs.
We continue like this from the root down to all leaves.
*/
position_boxes :: proc(root: ^Box) {

	// 100% offset means the far edge of the box is inline with the far edge of the inside
	// of the parents space. 
	// All relative values are [0..=1], 0 = 0%, 0.5 = 50%, 1 = 100%.
	position_absolute :: proc(parent: ^Box, child: ^Box) {
		switch child.config.floating_type {
		
		// Kind of ugly but here the 'floating_offset' is in absolute pixel amounts, unlike the other
		// relative sizing types where it's a percentage of the parents width / height.
		case .Absolute_Pixel:
			child.top_left = {int(child.config.floating_offset.x), int(child.config.floating_offset.y)}
			child.bottom_right = child.top_left + {child.width, child.height}

		case .Relative_Root:
			width_diff := f32(parent.width - child.width)
			height_diff := f32(parent.height - child.height)

			offset_x := int(width_diff * child.config.floating_offset.x)
			offset_y := int(height_diff * child.config.floating_offset.y)


			child.top_left = {parent.top_left.x + offset_x, parent.top_left.y + offset_y}
			child.bottom_right = {child.top_left.x + child.width, child.top_left.y + child.height}
		case .Relative_Other:
			assert(child.config.floating_anchor_box != nil)
			other_box := child.config.floating_anchor_box
			width_diff := f32(other_box.width - child.width)
			height_diff := f32(other_box.height - child.height)

			offset_x := int(width_diff * child.config.floating_offset.x)
			offset_y := int(height_diff * child.config.floating_offset.y)


			child.top_left = {other_box.top_left.x + offset_x, other_box.top_left.y + offset_y}
			child.bottom_right = {child.top_left.x + child.width, child.top_left.y + child.height}
		case .Relative_Parent:
			width_diff := f32(child.parent.width - child.width)
			height_diff := f32(child.parent.height - child.height)

			offset_x := int(width_diff * child.config.floating_offset.x)
			offset_y := int(height_diff * child.config.floating_offset.y)


			child.top_left = {child.parent.top_left.x + offset_x, child.parent.top_left.y + offset_y}
			child.bottom_right = {child.top_left.x + child.width, child.top_left.y + child.height}

		case .Center_Right:
			child.top_left = {app.wx - child.width, (app.wy / 2) - (child.height/2)}
			child.bottom_right = child.top_left + {child.width, child.height}
		
		case .Bottom_Center, .Bottom_Left,.Bottom_Right, .Top_Center, .Top_Left, .Top_Right, .Not_Floating, .Center_Center, .Center_Left:
			panic(tprintf("Have not implemented position child with floating type: {}", child.config.floating_type))
		}
	}

	/* ========== START Position horizontally when horizontal is the main axis ============= */
	// Helper function for positioning children horizontally at start, center or end.
	place_siblings_horizontally :: proc(root: Box, siblings: []^Box, start_x: int, gap: int) {
		prev_sibling: ^Box
		for child in siblings {
			if prev_sibling == nil {
				child.top_left.x = start_x + child.config.margin.left
			} else {
				child.top_left.x = prev_sibling.bottom_right.x + prev_sibling.config.margin.right + gap + child.config.margin.left
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
			total_child_width += child.width + box_get_margin_x_tot(child^)
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
			total_child_raw_width += child.width + box_get_margin_x_tot(child^)
		}
		total_child_width := total_child_raw_width + (gap * (len(valid_children) - 1) + padding)
		start_x := root.bottom_right.x - total_child_width
		place_siblings_horizontally(root^, valid_children[:], start_x, gap)
	}

	// Space between all children should equal space between start edge
	// and first child and end edge and last child.
	position_horizontally_space_around :: proc(root: ^Box) {
		total_child_width := 0
		valid_children := non_floating_children(root)
		for child in valid_children {
			total_child_width += child.width + box_get_margin_x_tot(child^)
		}
		remaining_space := root.width - total_child_width
		n_gaps := len(root.children) + 1
		gap := int(f32(remaining_space) / f32(n_gaps))
		start_x := root.top_left.x + gap
		place_siblings_horizontally(root^, valid_children[:], start_x, gap)
	}

	// Distribute space evenly between children.
	// Only left and right padding matter here.
	position_horizontally_space_between :: proc(root: ^Box) {
		// Gap will be ignored since items won't really be next to each other.
		padding := root.config.padding.left + root.config.padding.right
		total_child_raw_width := 0
		valid_children := non_floating_children(root)
		for child in valid_children {
			total_child_raw_width += child.width + box_get_margin_x_tot(child^)
		}
		total_child_width := total_child_raw_width + padding
		remaining_space := root.width - total_child_width
		n_gaps := len(root.children) - 1
		gap := int(f32(remaining_space) / f32(n_gaps))
		start_x := root.top_left.x + root.config.padding.left
		place_siblings_horizontally(root^, valid_children[:], start_x, gap)
	}
	/* ========== END Position horizontally when horizontal is the main axis ============= */


	/* ========== START Position horizontally when horizontal is the cross axis ============= */
	position_horizontally_across_start :: proc(root: ^Box) {
		valid_children := non_floating_children(root)
		for child in valid_children {
			child.top_left.x = root.top_left.x + root.config.padding.left + child.config.margin.left
			child.bottom_right.x = child.top_left.x + child.width
		}
	}

	position_horizontally_across_center :: proc(root: ^Box) {
		valid_children := non_floating_children(root)
		available_width := root.width - (root.config.padding.left + root.config.padding.right)
		for child in valid_children {
			child_total_width := child.width + box_get_margin_x_tot(child^)
			half_width_diff := (available_width - child_total_width) / 2
			child.top_left.x = root.top_left.x + half_width_diff + root.config.padding.left + child.config.margin.left
			child.bottom_right.x = child.top_left.x + child.width
		}
	}

	position_horizontally_across_end :: proc(root: ^Box) {
		valid_children := non_floating_children(root)
		for child in valid_children {
			child.bottom_right.x = root.bottom_right.x - root.config.padding.right - child.config.margin.right
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
				child.top_left.y = start_y + child.config.margin.top
			} else {
				child.top_left.y = prev_sibling.bottom_right.y + prev_sibling.config.margin.bottom + gap + child.config.margin.top
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
			total_children_height += child.height + box_get_margin_y_tot(child^)
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
			total_children_height += child.height + box_get_margin_y_tot(child^)
		}
		start_y := root.bottom_right.y - total_children_height
		place_siblings_vertically(root^, siblings[:], start_y, gap)
	}

	position_vertically_space_between :: proc(root: ^Box)  {
		siblings := non_floating_children(root)
		total_children_height := 0
		for child in siblings {
			total_children_height += child.height + box_get_margin_y_tot(child^)
		}
		// total_children_height += (len(siblings) - 1) * gap
		remaining_height := root.height - total_children_height
		gap := remaining_height / len(siblings)
		start_y := root.top_left.y + root.config.padding.top
		place_siblings_vertically(root^, siblings[:], start_y, gap)
	}

	position_vertically_space_around :: proc(root: ^Box)  {
		siblings := non_floating_children(root)
		total_children_height := 0
		for child in siblings {
			total_children_height += child.height + box_get_margin_y_tot(child^)
		}
		remaining_height := root.height - total_children_height
		// Space between the start edge and first child, between each child and last
		// child and end edge should all be equal.
		n_gaps := len(siblings) + 1
		gap := remaining_height / n_gaps
		start_y := root.top_left.y + gap
		place_siblings_vertically(root^, siblings[:], start_y, gap)
	}
	/* ========== END Position vertically when vertical is the main axis ============= */

	/* ========== Position vertically when vertical is the cross axis ============= */
	position_vertically_across_start :: proc(root: ^Box) {
		valid_children := non_floating_children(root)
		for child in valid_children {
			child.top_left.y = root.top_left.y + root.config.padding.top + child.config.margin.top
			child.bottom_right.y = child.top_left.y + child.height
		}
	}

	position_vertically_across_center :: proc(root: ^Box) {
		valid_children := non_floating_children(root)
		available_height := root.height - (root.config.padding.top + root.config.padding.bottom)
		for child in valid_children {
			child_total_height := child.height + box_get_margin_y_tot(child^)
			half_height_diff := (available_height - child_total_height) / 2
			child.top_left.y = root.top_left.y + root.config.padding.top + half_height_diff + child.config.margin.top
			child.bottom_right.y = child.top_left.y + child.height
		}
	}

	position_vertically_across_end :: proc(root: ^Box) {
		valid_children := non_floating_children(root)
		for child in valid_children {
			child.bottom_right.y = root.bottom_right.y - root.config.padding.bottom - child.config.margin.bottom
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
			if child.config.floating_type != .Not_Floating{
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
				position_horizontally_space_between(root)
				// panic("space between not implemented yet")
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
				position_vertically_space_around(root)
			case .Space_Between:
				position_vertically_space_between(root)
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

box_get_siblings :: proc(box: Box, allocator:=context.allocator) -> [dynamic]^Box { 
	res := make([dynamic]^Box, allocator)
	for child in box.parent.children { 
		append(&res, child)
	}
	return res
}

/* ============================ START ANIMATION CODE ============================== */
// ** Decided to not implement animations yet, since not sure how needed they even are in my code base. 
ANIMATION_MAX_ITEMS :: 64

Animation_Item :: struct { 
	id: 		string,
	progress:	f32, 
	time:		f32, 
	initial:	f32, 
	// The last returned value from when animation_get was called.
	prev:		f32,
}

// animation_update_all :: proc(dt: f32) { 
// 	items := ui_state.animation_items
// 	#reverse for &item, i in sarr.slice(&items) { 
// 		item.progress += dt / item.time
// 		if item.progress >= 1 { 
// 			// remove this item from the array.
// 		}
// 	}
// }

animation_start :: proc(id: string, initial, time: f32) { 
}
/* ============================ END ANIMATION CODE ============================== */




/* ============================ START PLATFORM LAYER CODE ============================== */

/* ============================ END PLATFORM LAYER CODE ============================== */