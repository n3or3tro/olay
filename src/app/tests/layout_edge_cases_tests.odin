package tests

import "core:fmt"
import "core:testing"
import app "../"

// Test gap calculation with no children
@(test)
test_gap_with_no_children :: proc(t: ^testing.T) {
	parent := app.Box{
		config = {
			padding = {left = 10, top = 10, right = 10, bottom = 10},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 50,
			gap_vertical = 30,
		},
		children = make([dynamic]^app.Box),
	}

	width := app.sizing_calc_fit_children_width(parent)
	height := app.sizing_calc_fit_children_height(parent)

	// Gaps should not contribute when there are no children
	// Should only be padding
	expected_width := 20
	expected_height := 20

	testing.expect(t, width == expected_width,
		fmt.tprintf("Width with no children should be %d, got %d", expected_width, width))
	testing.expect(t, height == expected_height,
		fmt.tprintf("Height with no children should be %d, got %d", expected_height, height))
}

// Test gap calculation with single child
@(test)
test_gap_with_single_child :: proc(t: ^testing.T) {
	parent := app.Box{
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 100, // Large gap
		},
		children = make([dynamic]^app.Box),
	}

	child := app.Box{
		width = 50,
		height = 50,
		config = {
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child)

	width := app.sizing_calc_fit_children_width(parent)

	// With single child, gap should NOT be counted
	// (num_children - 1) * gap = (1 - 1) * 100 = 0
	expected_width := 50

	testing.expect(t, width == expected_width,
		fmt.tprintf("Width with single child should ignore gap, expected %d, got %d", expected_width, width))
}

// Test large gap with multiple children
@(test)
test_large_gap_multiple_children :: proc(t: ^testing.T) {
	parent := app.Box{
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 100,
		},
		children = make([dynamic]^app.Box),
	}

	child1 := app.Box{
		width = 50,
		config = {
			floating_type = .Not_Floating,
		},
	}

	child2 := app.Box{
		width = 50,
		config = {
			floating_type = .Not_Floating,
		},
	}

	child3 := app.Box{
		width = 50,
		config = {
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child1)
	append(&parent.children, &child2)
	append(&parent.children, &child3)

	width := app.sizing_calc_fit_children_width(parent)

	// 3 children: 50 + 50 + 50 = 150
	// 2 gaps: 2 * 100 = 200
	// Total: 350
	expected_width := 350

	testing.expect(t, width == expected_width,
		fmt.tprintf("Width with gaps should be %d, got %d", expected_width, width))
}

// Test only floating children (all should be ignored)
@(test)
test_all_floating_children :: proc(t: ^testing.T) {
	parent := app.Box{
		config = {
			padding = {left = 5, top = 5, right = 5, bottom = 5},
		},
		child_layout = {
			direction = .Horizontal,
		},
		children = make([dynamic]^app.Box),
	}

	floating1 := app.Box{
		width = 100,
		height = 100,
		config = {
			floating_type = .Relative_Root,
		},
	}

	floating2 := app.Box{
		width = 200,
		height = 200,
		config = {
			floating_type = .Relative_Parent,
		},
	}

	append(&parent.children, &floating1)
	append(&parent.children, &floating2)

	width := app.sizing_calc_fit_children_width(parent)
	height := app.sizing_calc_fit_children_height(parent)

	// All floating children should be ignored
	// Should only count padding
	expected_width := 10
	expected_height := 10

	testing.expect(t, width == expected_width,
		fmt.tprintf("Width with only floating children should be %d, got %d", expected_width, width))
	testing.expect(t, height == expected_height,
		fmt.tprintf("Height with only floating children should be %d, got %d", expected_height, height))
}

// Test mix of floating and non-floating children
@(test)
test_mixed_floating_and_normal :: proc(t: ^testing.T) {
	parent := app.Box{
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 10,
		},
		children = make([dynamic]^app.Box),
	}

	normal1 := app.Box{
		width = 50,
		config = {
			floating_type = .Not_Floating,
		},
	}

	floating := app.Box{
		width = 999, // Should be ignored
		config = {
			floating_type = .Relative_Root,
		},
	}

	normal2 := app.Box{
		width = 70,
		config = {
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &normal1)
	append(&parent.children, &floating)
	append(&parent.children, &normal2)

	width := app.sizing_calc_fit_children_width(parent)

	// Only count normal children: 50 + 70 = 120
	// Only 1 gap between the two normal children: 10
	// Total: 130
	expected_width := 130

	testing.expect(t, width == expected_width,
		fmt.tprintf("Width should only count non-floating children, expected %d, got %d", expected_width, width))
}

// Test very small child sizes (potential integer underflow)
@(test)
test_very_small_sizes :: proc(t: ^testing.T) {
	parent := app.Box{
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
		},
		child_layout = {
			direction = .Horizontal,
		},
		children = make([dynamic]^app.Box),
	}

	tiny_child := app.Box{
		width = 1,
		height = 1,
		config = {
			margin = {left = 0, top = 0, right = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &tiny_child)

	width := app.sizing_calc_fit_children_width(parent)
	height := app.sizing_calc_fit_children_height(parent)

	testing.expect(t, width == 1,
		fmt.tprintf("Width with 1px child should be 1, got %d", width))
	testing.expect(t, height == 1,
		fmt.tprintf("Height with 1px child should be 1, got %d", height))
}

// Test zero-sized children
@(test)
test_zero_sized_children :: proc(t: ^testing.T) {
	parent := app.Box{
		config = {
			padding = {left = 5, top = 5, right = 5, bottom = 5},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 10,
		},
		children = make([dynamic]^app.Box),
	}

	zero_child1 := app.Box{
		width = 0,
		height = 0,
		config = {
			floating_type = .Not_Floating,
		},
	}

	zero_child2 := app.Box{
		width = 0,
		height = 0,
		config = {
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &zero_child1)
	append(&parent.children, &zero_child2)

	width := app.sizing_calc_fit_children_width(parent)

	// Two zero-width children + 1 gap + padding
	// 0 + 0 + 10 (gap) + 10 (padding) = 20
	expected_width := 20

	testing.expect(t, width == expected_width,
		fmt.tprintf("Width with zero-sized children should be %d, got %d", expected_width, width))
}

// Test asymmetric padding
@(test)
test_asymmetric_padding :: proc(t: ^testing.T) {
	parent := app.Box{
		config = {
			padding = {left = 5, top = 10, right = 15, bottom = 20},
		},
		children = make([dynamic]^app.Box),
	}

	child := app.Box{
		width = 100,
		height = 80,
		config = {
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child)

	width := app.sizing_calc_fit_children_width(parent)
	height := app.sizing_calc_fit_children_height(parent)

	// Width: 100 + 5 (left) + 15 (right) = 120
	// Height: 80 + 10 (top) + 20 (bottom) = 110

	testing.expect(t, width == 120,
		fmt.tprintf("Width with asymmetric padding should be 120, got %d", width))
	testing.expect(t, height == 110,
		fmt.tprintf("Height with asymmetric padding should be 110, got %d", height))
}

// Test asymmetric margins
@(test)
test_asymmetric_margins :: proc(t: ^testing.T) {
	parent := app.Box{
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
		},
		children = make([dynamic]^app.Box),
	}

	child := app.Box{
		width = 100,
		height = 80,
		config = {
			margin = {left = 3, top = 7, right = 11, bottom = 13},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child)

	width := app.sizing_calc_fit_children_width(parent)
	height := app.sizing_calc_fit_children_height(parent)

	// Width: 100 + 3 + 11 = 114
	// Height: 80 + 7 + 13 = 100

	testing.expect(t, width == 114,
		fmt.tprintf("Width with asymmetric margins should be 114, got %d", width))
	testing.expect(t, height == 100,
		fmt.tprintf("Height with asymmetric margins should be 100, got %d", height))
}

// Test vertical layout widest child selection
@(test)
test_vertical_widest_child :: proc(t: ^testing.T) {
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
			margin = {left = 5, right = 5, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
	}

	child2 := app.Box{
		width = 150, // Widest
		config = {
			margin = {left = 10, right = 10, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
	}

	child3 := app.Box{
		width = 120,
		config = {
			margin = {left = 3, right = 3, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child1)
	append(&parent.children, &child2)
	append(&parent.children, &child3)

	width := app.sizing_calc_fit_children_width(parent)

	// Widest child including margins: 150 + 10 + 10 = 170
	expected_width := 170

	testing.expect(t, width == expected_width,
		fmt.tprintf("Vertical layout should pick widest child (170), got %d", width))
}

// Test horizontal layout tallest child selection
@(test)
test_horizontal_tallest_child :: proc(t: ^testing.T) {
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
			margin = {left = 0, right = 0, top = 5, bottom = 5},
			floating_type = .Not_Floating,
		},
	}

	child2 := app.Box{
		height = 80,
		config = {
			margin = {left = 0, right = 0, top = 10, bottom = 10},
			floating_type = .Not_Floating,
		},
	}

	child3 := app.Box{
		height = 150, // Tallest
		config = {
			margin = {left = 0, right = 0, top = 3, bottom = 7},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child1)
	append(&parent.children, &child2)
	append(&parent.children, &child3)

	height := app.sizing_calc_fit_children_height(parent)

	// Tallest child including margins: 150 + 3 + 7 = 160
	expected_height := 160

	testing.expect(t, height == expected_height,
		fmt.tprintf("Horizontal layout should pick tallest child (160), got %d", height))
}

// Test that helper functions work correctly
@(test)
test_helper_functions_with_zeros :: proc(t: ^testing.T) {
	box := app.Box{
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			margin = {left = 0, top = 0, right = 0, bottom = 0},
		},
	}

	x_padding := app.box_get_padding_x_tot(box)
	y_padding := app.box_get_padding_y_tot(box)
	x_margin := app.box_get_margin_x_tot(box)
	y_margin := app.box_get_margin_y_tot(box)

	testing.expect(t, x_padding == 0, fmt.tprintf("X padding should be 0, got %d", x_padding))
	testing.expect(t, y_padding == 0, fmt.tprintf("Y padding should be 0, got %d", y_padding))
	testing.expect(t, x_margin == 0, fmt.tprintf("X margin should be 0, got %d", x_margin))
	testing.expect(t, y_margin == 0, fmt.tprintf("Y margin should be 0, got %d", y_margin))
}

// Test deeply nested layouts
@(test)
test_deeply_nested_fit_children :: proc(t: ^testing.T) {
	// Level 3 (innermost)
	child := app.Box{
		width = 50,
		height = 50,
		config = {
			floating_type = .Not_Floating,
		},
	}

	// Level 2
	middle := app.Box{
		config = {
			padding = {left = 5, top = 5, right = 5, bottom = 5},
		},
		children = make([dynamic]^app.Box),
	}
	append(&middle.children, &child)

	// Level 1 (outermost)
	outer := app.Box{
		config = {
			padding = {left = 10, top = 10, right = 10, bottom = 10},
		},
		children = make([dynamic]^app.Box),
	}
	append(&outer.children, &middle)

	// Calculate middle first
	middle_width := app.sizing_calc_fit_children_width(middle)
	middle_height := app.sizing_calc_fit_children_height(middle)

	// Middle should be: 50 + 10 (padding) = 60
	testing.expect(t, middle_width == 60,
		fmt.tprintf("Middle width should be 60, got %d", middle_width))

	// Set middle's dimensions for outer calculation
	middle.width = middle_width
	middle.height = middle_height

	outer_width := app.sizing_calc_fit_children_width(outer)

	// Outer should be: 60 (middle) + 20 (outer padding) = 80
	expected_outer_width := 80

	testing.expect(t, outer_width == expected_outer_width,
		fmt.tprintf("Outer width should be %d, got %d", expected_outer_width, outer_width))
}
