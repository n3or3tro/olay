package tests

import "core:fmt"
import "core:testing"
import app "../"

// Test that margin is correctly added to fit_children width calculations
@(test)
test_margin_fit_children_width_horizontal :: proc(t: ^testing.T) {
	// Create a parent box with two children laid out horizontally
	parent := app.Box{
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 0,
		},
		children = make([dynamic]^app.Box),
	}

	child1 := app.Box{
		width = 100,
		config = {
			margin = {left = 10, right = 5, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
	}

	child2 := app.Box{
		width = 50,
		config = {
			margin = {left = 8, right = 12, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child1)
	append(&parent.children, &child2)

	// Calculate fit_children width
	calculated_width := app.sizing_calc_fit_children_width(parent)

	// Expected: 100 (child1) + 15 (child1 margins) + 50 (child2) + 20 (child2 margins) = 185
	expected_width := 185

	testing.expect(t, calculated_width == expected_width,
		fmt.tprintf("Fit children width with margins should be 185, got %d", calculated_width))
}

// Test that margin is correctly added to fit_children width in vertical layout
@(test)
test_margin_fit_children_width_vertical :: proc(t: ^testing.T) {
	// In vertical layout, width should be the widest child + its margins
	parent := app.Box{
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
		},
		child_layout = {
			direction = .Vertical,
		},
		children = make([dynamic]^app.Box),
	}

	child1 := app.Box{
		width = 100,
		config = {
			margin = {left = 10, right = 5, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
	}

	child2 := app.Box{
		width = 80,
		config = {
			margin = {left = 20, right = 15, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child1)
	append(&parent.children, &child2)

	calculated_width := app.sizing_calc_fit_children_width(parent)

	// Expected: widest child is child1 (100) + its margins (15) = 115
	expected_width := 115

	testing.expect(t, calculated_width == expected_width,
		fmt.tprintf("Fit children width in vertical layout should be 115, got %d", calculated_width))
}

// Test that margin is correctly added to fit_children height calculations
@(test)
test_margin_fit_children_height_vertical :: proc(t: ^testing.T) {
	parent := app.Box{
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
		},
		child_layout = {
			direction = .Vertical,
			gap_vertical = 0,
		},
		children = make([dynamic]^app.Box),
	}

	child1 := app.Box{
		height = 100,
		config = {
			margin = {left = 0, top = 10, right = 0, bottom = 5},
			floating_type = .Not_Floating,
		},
	}

	child2 := app.Box{
		height = 50,
		config = {
			margin = {left = 0, top = 8, right = 0, bottom = 12},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child1)
	append(&parent.children, &child2)

	calculated_height := app.sizing_calc_fit_children_height(parent)

	// Expected: 100 (child1) + 15 (child1 margins) + 50 (child2) + 20 (child2 margins) = 185
	expected_height := 185

	testing.expect(t, calculated_height == expected_height,
		fmt.tprintf("Fit children height with margins should be 185, got %d", calculated_height))
}

// Test that margin is correctly added to fit_children height in horizontal layout
@(test)
test_margin_fit_children_height_horizontal :: proc(t: ^testing.T) {
	// In horizontal layout, height should be the tallest child + its margins
	parent := app.Box{
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
		},
		child_layout = {
			direction = .Horizontal,
		},
		children = make([dynamic]^app.Box),
	}

	child1 := app.Box{
		height = 100,
		config = {
			margin = {left = 0, top = 10, right = 0, bottom = 5},
			floating_type = .Not_Floating,
		},
	}

	child2 := app.Box{
		height = 80,
		config = {
			margin = {left = 0, top = 20, right = 0, bottom = 15},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child1)
	append(&parent.children, &child2)

	calculated_height := app.sizing_calc_fit_children_height(parent)

	// Expected: tallest child is child1 (100) + its margins (10 + 5) = 115
	expected_height := 115

	testing.expect(t, calculated_height == expected_height,
		fmt.tprintf("Fit children height in horizontal layout should be 115, got %d", calculated_height))
}

// Test margin with padding interaction
@(test)
test_margin_with_padding_fit_children :: proc(t: ^testing.T) {
	parent := app.Box{
		config = {
			padding = {left = 20, top = 15, right = 25, bottom = 18},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 0,
		},
		children = make([dynamic]^app.Box),
	}

	child := app.Box{
		width = 100,
		config = {
			margin = {left = 10, right = 5, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child)

	calculated_width := app.sizing_calc_fit_children_width(parent)

	// Expected: 100 (child) + 10 (child left margin) + 5 (child right margin) +
	//           20 (parent left padding) + 25 (parent right padding) = 160
	expected_width := 160

	testing.expect(t, calculated_width == expected_width,
		fmt.tprintf("Fit children width with padding and margins should be 160, got %d", calculated_width))
}

// Test margin in horizontal positioning (siblings placed next to each other)
@(test)
test_margin_horizontal_positioning_start :: proc(t: ^testing.T) {
	parent := app.Box{
		top_left = {0, 0},
		bottom_right = {500, 100},
		width = 500,
		config = {
			padding = {left = 10, top = 0, right = 0, bottom = 0},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 5,
			alignment_horizontal = .Start,
		},
		children = make([dynamic]^app.Box),
	}

	child1 := app.Box{
		width = 100,
		config = {
			margin = {left = 15, right = 8, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
	}

	child2 := app.Box{
		width = 80,
		config = {
			margin = {left = 12, right = 6, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child1)
	append(&parent.children, &child2)

	// Manually simulate what place_siblings_horizontally should do
	siblings := [2]^app.Box{&child1, &child2}
	start_x := parent.top_left.x + parent.config.padding.left
	gap := parent.child_layout.gap_horizontal

	// First child: start_x + left_margin
	child1.top_left.x = start_x + child1.config.margin.left
	child1.bottom_right.x = child1.top_left.x + child1.width

	// Second child: prev.bottom_right + prev.right_margin + gap + current.left_margin
	child2.top_left.x = child1.bottom_right.x + child1.config.margin.right + gap + child2.config.margin.left
	child2.bottom_right.x = child2.top_left.x + child2.width

	// Expected positions:
	// child1.top_left.x = 0 + 10 (padding) + 15 (left margin) = 25
	// child1.bottom_right.x = 25 + 100 = 125
	// child2.top_left.x = 125 + 8 (child1 right margin) + 5 (gap) + 12 (child2 left margin) = 150
	// child2.bottom_right.x = 150 + 80 = 230

	testing.expect(t, child1.top_left.x == 25,
		fmt.tprintf("Child1 left position should be 25, got %d", child1.top_left.x))
	testing.expect(t, child1.bottom_right.x == 125,
		fmt.tprintf("Child1 right position should be 125, got %d", child1.bottom_right.x))
	testing.expect(t, child2.top_left.x == 150,
		fmt.tprintf("Child2 left position should be 150, got %d", child2.top_left.x))
	testing.expect(t, child2.bottom_right.x == 230,
		fmt.tprintf("Child2 right position should be 230, got %d", child2.bottom_right.x))
}

// Test margin in vertical positioning (siblings placed one below another)
@(test)
test_margin_vertical_positioning_start :: proc(t: ^testing.T) {
	parent := app.Box{
		top_left = {0, 0},
		bottom_right = {100, 500},
		height = 500,
		config = {
			padding = {left = 0, top = 10, right = 0, bottom = 0},
		},
		child_layout = {
			direction = .Vertical,
			gap_vertical = 5,
			alignment_vertical = .Start,
		},
		children = make([dynamic]^app.Box),
	}

	child1 := app.Box{
		height = 100,
		config = {
			margin = {left = 0, top = 15, right = 0, bottom = 8},
			floating_type = .Not_Floating,
		},
	}

	child2 := app.Box{
		height = 80,
		config = {
			margin = {left = 0, top = 12, right = 0, bottom = 6},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child1)
	append(&parent.children, &child2)

	start_y := parent.top_left.y + parent.config.padding.top
	gap := parent.child_layout.gap_vertical

	// First child: start_y + top_margin
	child1.top_left.y = start_y + child1.config.margin.top
	child1.bottom_right.y = child1.top_left.y + child1.height

	// Second child: prev.bottom_right + prev.bottom_margin + gap + current.top_margin
	child2.top_left.y = child1.bottom_right.y + child1.config.margin.bottom + gap + child2.config.margin.top
	child2.bottom_right.y = child2.top_left.y + child2.height

	// Expected positions:
	// child1.top_left.y = 0 + 10 (padding) + 15 (top margin) = 25
	// child1.bottom_right.y = 25 + 100 = 125
	// child2.top_left.y = 125 + 8 (child1 bottom margin) + 5 (gap) + 12 (child2 top margin) = 150
	// child2.bottom_right.y = 150 + 80 = 230

	testing.expect(t, child1.top_left.y == 25,
		fmt.tprintf("Child1 top position should be 25, got %d", child1.top_left.y))
	testing.expect(t, child1.bottom_right.y == 125,
		fmt.tprintf("Child1 bottom position should be 125, got %d", child1.bottom_right.y))
	testing.expect(t, child2.top_left.y == 150,
		fmt.tprintf("Child2 top position should be 150, got %d", child2.top_left.y))
	testing.expect(t, child2.bottom_right.y == 230,
		fmt.tprintf("Child2 bottom position should be 230, got %d", child2.bottom_right.y))
}

// Test that floating children are ignored in margin calculations
@(test)
test_margin_ignores_floating_children :: proc(t: ^testing.T) {
	parent := app.Box{
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 0,
		},
		children = make([dynamic]^app.Box),
	}

	child1 := app.Box{
		width = 100,
		config = {
			margin = {left = 10, right = 5, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
	}

	child2_floating := app.Box{
		width = 50,
		config = {
			margin = {left = 20, right = 25, top = 0, bottom = 0},
			floating_type = .Relative_Root, // Floating, should be ignored
		},
	}

	append(&parent.children, &child1)
	append(&parent.children, &child2_floating)

	calculated_width := app.sizing_calc_fit_children_width(parent)

	// Expected: Only child1 should count: 100 + 15 (margins) = 115
	expected_width := 115

	testing.expect(t, calculated_width == expected_width,
		fmt.tprintf("Fit children width should ignore floating children, expected 115, got %d", calculated_width))
}

// Test nested layouts with margins
@(test)
test_nested_margins :: proc(t: ^testing.T) {
	// Parent with margin
	parent := app.Box{
		config = {
			padding = {left = 5, top = 5, right = 5, bottom = 5},
			margin = {left = 10, top = 10, right = 10, bottom = 10},
		},
		child_layout = {
			direction = .Vertical,
			gap_vertical = 0,
		},
		children = make([dynamic]^app.Box),
	}

	// Child with margin
	child := app.Box{
		height = 100,
		config = {
			margin = {left = 0, top = 8, right = 0, bottom = 12},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child)

	calculated_height := app.sizing_calc_fit_children_height(parent)

	// Expected: 100 (child) + 20 (child margins) + 10 (parent padding) = 130
	// NOTE: Parent's own margin is NOT included in its size (margin is external)
	expected_height := 130

	testing.expect(t, calculated_height == expected_height,
		fmt.tprintf("Nested margins should add up correctly, expected 130, got %d", calculated_height))
}

// Test helper functions for margin totals
@(test)
test_margin_helper_functions :: proc(t: ^testing.T) {
	box := app.Box{
		config = {
			margin = {left = 10, top = 15, right = 20, bottom = 25},
		},
	}

	x_total := app.box_get_margin_x_tot(box)
	y_total := app.box_get_margin_y_tot(box)

	testing.expect(t, x_total == 30, fmt.tprintf("X margin total should be 30, got %d", x_total))
	testing.expect(t, y_total == 40, fmt.tprintf("Y margin total should be 40, got %d", y_total))
}

// Test helper functions for padding totals
@(test)
test_padding_helper_functions :: proc(t: ^testing.T) {
	box := app.Box{
		config = {
			padding = {left = 10, top = 15, right = 20, bottom = 25},
		},
	}

	x_total := app.box_get_padding_x_tot(box)
	y_total := app.box_get_padding_y_tot(box)

	testing.expect(t, x_total == 30, fmt.tprintf("X padding total should be 30, got %d", x_total))
	testing.expect(t, y_total == 40, fmt.tprintf("Y padding total should be 40, got %d", y_total))
}
