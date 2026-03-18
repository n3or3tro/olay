package tests

import "core:fmt"
import "core:testing"
import app "../"

// Test horizontal center alignment with margins
@(test)
test_horizontal_center_alignment_with_margins :: proc(t: ^testing.T) {
	parent := app.Box{
		top_left = {0, 0},
		bottom_right = {500, 100},
		width = 500,
		config = {
			padding = {left = 10, top = 0, right = 10, bottom = 0},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 5,
			alignment_horizontal = .Center,
		},
		children = make([dynamic]^app.Box),
	}

	child1 := app.Box{
		width = 100,
		config = {
			margin = {left = 10, right = 10, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
	}

	child2 := app.Box{
		width = 80,
		config = {
			margin = {left = 5, right = 5, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child1)
	append(&parent.children, &child2)

	// Calculate center positioning
	total_child_width := 100 + app.box_get_margin_x_tot(child1) + 80 + app.box_get_margin_x_tot(child2)
	// total_child_width = 100 + 20 + 80 + 10 = 210
	gap_total := parent.child_layout.gap_horizontal
	// gap_total = 5

	available_width := parent.width - (total_child_width + gap_total + app.box_get_padding_x_tot(parent))
	// available_width = 500 - (210 + 5 + 20) = 265

	half_width := available_width / 2
	// half_width = 132

	start_x := parent.top_left.x + half_width + parent.config.padding.left
	// start_x = 0 + 132 + 10 = 142

	testing.expect(t, total_child_width == 210,
		fmt.tprintf("Total child width should be 210, got %d", total_child_width))
	testing.expect(t, available_width == 265,
		fmt.tprintf("Available width should be 265, got %d", available_width))
	testing.expect(t, start_x == 142,
		fmt.tprintf("Start x for centered children should be 142, got %d", start_x))
}

// Test horizontal end alignment with margins
@(test)
test_horizontal_end_alignment_with_margins :: proc(t: ^testing.T) {
	parent := app.Box{
		top_left = {0, 0},
		bottom_right = {500, 100},
		width = 500,
		config = {
			padding = {left = 10, top = 0, right = 10, bottom = 0},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 5,
			alignment_horizontal = .End,
		},
		children = make([dynamic]^app.Box),
	}

	child1 := app.Box{
		width = 100,
		config = {
			margin = {left = 10, right = 10, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
	}

	child2 := app.Box{
		width = 80,
		config = {
			margin = {left = 5, right = 5, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child1)
	append(&parent.children, &child2)

	total_child_raw_width := 100 + app.box_get_margin_x_tot(child1) + 80 + app.box_get_margin_x_tot(child2)
	// = 210
	gap := parent.child_layout.gap_horizontal
	padding := app.box_get_padding_x_tot(parent)
	total_child_width := total_child_raw_width + gap + padding
	// = 210 + 5 + 20 = 235

	start_x := parent.bottom_right.x - total_child_width
	// = 500 - 235 = 265

	testing.expect(t, start_x == 265,
		fmt.tprintf("Start x for end-aligned children should be 265, got %d", start_x))
}

// Test vertical center alignment with margins
@(test)
test_vertical_center_alignment_with_margins :: proc(t: ^testing.T) {
	parent := app.Box{
		top_left = {0, 0},
		bottom_right = {100, 500},
		height = 500,
		config = {
			padding = {left = 0, top = 10, right = 0, bottom = 10},
		},
		child_layout = {
			direction = .Vertical,
			gap_vertical = 5,
			alignment_vertical = .Center,
		},
		children = make([dynamic]^app.Box),
	}

	child1 := app.Box{
		height = 100,
		config = {
			margin = {left = 0, top = 10, right = 0, bottom = 10},
			floating_type = .Not_Floating,
		},
	}

	child2 := app.Box{
		height = 80,
		config = {
			margin = {left = 0, top = 5, right = 0, bottom = 5},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child1)
	append(&parent.children, &child2)

	total_children_height := 100 + app.box_get_margin_y_tot(child1) + 80 + app.box_get_margin_y_tot(child2)
	// = 100 + 20 + 80 + 10 = 210
	gap := parent.child_layout.gap_vertical
	// = 5

	available_height := parent.height - (gap + total_children_height + app.box_get_padding_y_tot(parent))
	// = 500 - (5 + 210 + 20) = 265

	half_height := available_height / 2
	// = 132

	start_y := parent.top_left.y + half_height + parent.config.padding.top
	// = 0 + 132 + 10 = 142

	testing.expect(t, total_children_height == 210,
		fmt.tprintf("Total children height should be 210, got %d", total_children_height))
	testing.expect(t, available_height == 265,
		fmt.tprintf("Available height should be 265, got %d", available_height))
	testing.expect(t, start_y == 142,
		fmt.tprintf("Start y for centered children should be 142, got %d", start_y))
}

// Test space_around alignment with margins
@(test)
test_horizontal_space_around_with_margins :: proc(t: ^testing.T) {
	parent := app.Box{
		top_left = {0, 0},
		bottom_right = {500, 100},
		width = 500,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
		},
		child_layout = {
			direction = .Horizontal,
			alignment_horizontal = .Space_Around,
		},
		children = make([dynamic]^app.Box),
	}

	child1 := app.Box{
		width = 100,
		config = {
			margin = {left = 10, right = 10, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
	}

	child2 := app.Box{
		width = 80,
		config = {
			margin = {left = 5, right = 5, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child1)
	append(&parent.children, &child2)

	total_child_width := 100 + app.box_get_margin_x_tot(child1) + 80 + app.box_get_margin_x_tot(child2)
	// = 210

	remaining_space := parent.width - total_child_width
	// = 500 - 210 = 290

	// Space around distributes space evenly with gaps on edges too
	n_gaps := len(parent.children) + 1  // = 3
	gap := remaining_space / n_gaps
	// = 290 / 3 = 96 (integer division)

	start_x := parent.top_left.x + gap
	// = 0 + 96 = 96

	testing.expect(t, remaining_space == 290,
		fmt.tprintf("Remaining space should be 290, got %d", remaining_space))
	testing.expect(t, gap == 96,
		fmt.tprintf("Gap for space_around should be 96, got %d", gap))
	testing.expect(t, start_x == 96,
		fmt.tprintf("Start x should be 96, got %d", start_x))
}

// Test space_between alignment with margins
@(test)
test_horizontal_space_between_with_margins :: proc(t: ^testing.T) {
	parent := app.Box{
		top_left = {0, 0},
		bottom_right = {500, 100},
		width = 500,
		config = {
			padding = {left = 10, top = 0, right = 10, bottom = 0},
		},
		child_layout = {
			direction = .Horizontal,
			alignment_horizontal = .Space_Between,
		},
		children = make([dynamic]^app.Box),
	}

	child1 := app.Box{
		width = 100,
		config = {
			margin = {left = 10, right = 10, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
	}

	child2 := app.Box{
		width = 80,
		config = {
			margin = {left = 5, right = 5, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child1)
	append(&parent.children, &child2)

	padding := app.box_get_padding_x_tot(parent)
	total_child_raw_width := 100 + app.box_get_margin_x_tot(child1) + 80 + app.box_get_margin_x_tot(child2)
	// = 210
	total_child_width := total_child_raw_width + padding
	// = 210 + 20 = 230

	remaining_space := parent.width - total_child_width
	// = 500 - 230 = 270

	n_gaps := len(parent.children) - 1  // = 1
	gap := remaining_space / n_gaps
	// = 270 / 1 = 270

	start_x := parent.top_left.x + parent.config.padding.left
	// = 0 + 10 = 10

	testing.expect(t, remaining_space == 270,
		fmt.tprintf("Remaining space should be 270, got %d", remaining_space))
	testing.expect(t, gap == 270,
		fmt.tprintf("Gap for space_between should be 270, got %d", gap))
	testing.expect(t, start_x == 10,
		fmt.tprintf("Start x should be 10, got %d", start_x))
}

// Test cross-axis center alignment (vertical layout, horizontal center)
@(test)
test_cross_axis_horizontal_center_with_margins :: proc(t: ^testing.T) {
	parent := app.Box{
		top_left = {0, 0},
		bottom_right = {500, 300},
		width = 500,
		config = {
			padding = {left = 20, top = 0, right = 20, bottom = 0},
		},
		child_layout = {
			direction = .Vertical,
			alignment_horizontal = .Center,
		},
		children = make([dynamic]^app.Box),
	}

	child := app.Box{
		width = 100,
		config = {
			margin = {left = 15, right = 25, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child)

	available_width := parent.width - app.box_get_padding_x_tot(parent)
	// = 500 - 40 = 460

	child_total_width := child.width + app.box_get_margin_x_tot(child)
	// = 100 + 40 = 140

	half_width_diff := (available_width - child_total_width) / 2
	// = (460 - 140) / 2 = 160

	child_left_x := parent.top_left.x + half_width_diff + parent.config.padding.left + child.config.margin.left
	// = 0 + 160 + 20 + 15 = 195

	testing.expect(t, available_width == 460,
		fmt.tprintf("Available width should be 460, got %d", available_width))
	testing.expect(t, child_total_width == 140,
		fmt.tprintf("Child total width should be 140, got %d", child_total_width))
	testing.expect(t, half_width_diff == 160,
		fmt.tprintf("Half width diff should be 160, got %d", half_width_diff))
	testing.expect(t, child_left_x == 195,
		fmt.tprintf("Child left x should be 195, got %d", child_left_x))
}

// Test cross-axis end alignment (vertical layout, horizontal end)
@(test)
test_cross_axis_horizontal_end_with_margins :: proc(t: ^testing.T) {
	parent := app.Box{
		top_left = {0, 0},
		bottom_right = {500, 300},
		width = 500,
		config = {
			padding = {left = 10, top = 0, right = 15, bottom = 0},
		},
		child_layout = {
			direction = .Vertical,
			alignment_horizontal = .End,
		},
		children = make([dynamic]^app.Box),
	}

	child := app.Box{
		width = 100,
		config = {
			margin = {left = 5, right = 8, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child)

	child_right_x := parent.bottom_right.x - parent.config.padding.right - child.config.margin.right
	// = 500 - 15 - 8 = 477

	child_left_x := child_right_x - child.width
	// = 477 - 100 = 377

	testing.expect(t, child_right_x == 477,
		fmt.tprintf("Child right x should be 477, got %d", child_right_x))
	testing.expect(t, child_left_x == 377,
		fmt.tprintf("Child left x should be 377, got %d", child_left_x))
}

// Test cross-axis start alignment (horizontal layout, vertical start)
@(test)
test_cross_axis_vertical_start_with_margins :: proc(t: ^testing.T) {
	parent := app.Box{
		top_left = {0, 0},
		bottom_right = {300, 500},
		height = 500,
		config = {
			padding = {left = 0, top = 12, right = 0, bottom = 18},
		},
		child_layout = {
			direction = .Horizontal,
			alignment_vertical = .Start,
		},
		children = make([dynamic]^app.Box),
	}

	child := app.Box{
		height = 100,
		config = {
			margin = {left = 0, top = 10, right = 0, bottom = 15},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child)

	child_top_y := parent.top_left.y + parent.config.padding.top + child.config.margin.top
	// = 0 + 12 + 10 = 22

	child_bottom_y := child_top_y + child.height
	// = 22 + 100 = 122

	testing.expect(t, child_top_y == 22,
		fmt.tprintf("Child top y should be 22, got %d", child_top_y))
	testing.expect(t, child_bottom_y == 122,
		fmt.tprintf("Child bottom y should be 122, got %d", child_bottom_y))
}

// Test cross-axis center alignment (horizontal layout, vertical center)
@(test)
test_cross_axis_vertical_center_with_margins :: proc(t: ^testing.T) {
	parent := app.Box{
		top_left = {0, 0},
		bottom_right = {300, 500},
		height = 500,
		config = {
			padding = {left = 0, top = 20, right = 0, bottom = 20},
		},
		child_layout = {
			direction = .Horizontal,
			alignment_vertical = .Center,
		},
		children = make([dynamic]^app.Box),
	}

	child := app.Box{
		height = 100,
		config = {
			margin = {left = 0, top = 15, right = 0, bottom = 25},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child)

	available_height := parent.height - app.box_get_padding_y_tot(parent)
	// = 500 - 40 = 460

	child_total_height := child.height + app.box_get_margin_y_tot(child)
	// = 100 + 40 = 140

	half_height_diff := (available_height - child_total_height) / 2
	// = (460 - 140) / 2 = 160

	child_top_y := parent.top_left.y + parent.config.padding.top + half_height_diff + child.config.margin.top
	// = 0 + 20 + 160 + 15 = 195

	testing.expect(t, available_height == 460,
		fmt.tprintf("Available height should be 460, got %d", available_height))
	testing.expect(t, child_total_height == 140,
		fmt.tprintf("Child total height should be 140, got %d", child_total_height))
	testing.expect(t, half_height_diff == 160,
		fmt.tprintf("Half height diff should be 160, got %d", half_height_diff))
	testing.expect(t, child_top_y == 195,
		fmt.tprintf("Child top y should be 195, got %d", child_top_y))
}

// Test cross-axis end alignment (horizontal layout, vertical end)
@(test)
test_cross_axis_vertical_end_with_margins :: proc(t: ^testing.T) {
	parent := app.Box{
		top_left = {0, 0},
		bottom_right = {300, 500},
		height = 500,
		config = {
			padding = {left = 0, top = 10, right = 0, bottom = 15},
		},
		child_layout = {
			direction = .Horizontal,
			alignment_vertical = .End,
		},
		children = make([dynamic]^app.Box),
	}

	child := app.Box{
		height = 100,
		config = {
			margin = {left = 0, top = 5, right = 0, bottom = 8},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child)

	child_bottom_y := parent.bottom_right.y - parent.config.padding.bottom - child.config.margin.bottom
	// = 500 - 15 - 8 = 477

	child_top_y := child_bottom_y - child.height
	// = 477 - 100 = 377

	testing.expect(t, child_bottom_y == 477,
		fmt.tprintf("Child bottom y should be 477, got %d", child_bottom_y))
	testing.expect(t, child_top_y == 377,
		fmt.tprintf("Child top y should be 377, got %d", child_top_y))
}

// Test vertical space_around with margins
@(test)
test_vertical_space_around_with_margins :: proc(t: ^testing.T) {
	parent := app.Box{
		top_left = {0, 0},
		bottom_right = {100, 500},
		height = 500,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
		},
		child_layout = {
			direction = .Vertical,
			alignment_vertical = .Space_Around,
		},
		children = make([dynamic]^app.Box),
	}

	child1 := app.Box{
		height = 100,
		config = {
			margin = {left = 0, top = 10, right = 0, bottom = 10},
			floating_type = .Not_Floating,
		},
	}

	child2 := app.Box{
		height = 80,
		config = {
			margin = {left = 0, top = 5, right = 0, bottom = 5},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child1)
	append(&parent.children, &child2)

	total_children_height := 100 + app.box_get_margin_y_tot(child1) + 80 + app.box_get_margin_y_tot(child2)
	// = 100 + 20 + 80 + 10 = 210

	remaining_height := parent.height - total_children_height
	// = 500 - 210 = 290

	n_gaps := len(parent.children) + 1  // = 3
	gap := remaining_height / n_gaps
	// = 290 / 3 = 96

	start_y := parent.top_left.y + gap
	// = 0 + 96 = 96

	testing.expect(t, remaining_height == 290,
		fmt.tprintf("Remaining height should be 290, got %d", remaining_height))
	testing.expect(t, gap == 96,
		fmt.tprintf("Gap should be 96, got %d", gap))
	testing.expect(t, start_y == 96,
		fmt.tprintf("Start y should be 96, got %d", start_y))
}

// Test vertical space_between with margins
@(test)
test_vertical_space_between_with_margins :: proc(t: ^testing.T) {
	parent := app.Box{
		top_left = {0, 0},
		bottom_right = {100, 500},
		height = 500,
		config = {
			padding = {left = 0, top = 10, right = 0, bottom = 10},
		},
		child_layout = {
			direction = .Vertical,
			alignment_vertical = .Space_Between,
		},
		children = make([dynamic]^app.Box),
	}

	child1 := app.Box{
		height = 100,
		config = {
			margin = {left = 0, top = 10, right = 0, bottom = 10},
			floating_type = .Not_Floating,
		},
	}

	child2 := app.Box{
		height = 80,
		config = {
			margin = {left = 0, top = 5, right = 0, bottom = 5},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child1)
	append(&parent.children, &child2)

	total_children_height := 100 + app.box_get_margin_y_tot(child1) + 80 + app.box_get_margin_y_tot(child2)
	// = 210

	remaining_height := parent.height - total_children_height
	// = 500 - 210 = 290

	gap := remaining_height / len(parent.children)
	// = 290 / 2 = 145

	start_y := parent.top_left.y + parent.config.padding.top
	// = 0 + 10 = 10

	testing.expect(t, remaining_height == 290,
		fmt.tprintf("Remaining height should be 290, got %d", remaining_height))
	testing.expect(t, gap == 145,
		fmt.tprintf("Gap should be 145, got %d", gap))
	testing.expect(t, start_y == 10,
		fmt.tprintf("Start y should be 10, got %d", start_y))
}
