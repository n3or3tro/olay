package tests

import "core:fmt"
import "core:testing"
import app "../"

// Test mixing Fixed and Grow sizing
@(test)
test_mixed_fixed_and_grow :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 500,
		config = {
			padding = {left = 10, top = 0, right = 10, bottom = 0},
			semantic_size = {{type = .Fixed, amount = 500}, {type = .Fixed, amount = 100}},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 0,
		},
		children = make([dynamic]^app.Box),
	}

	child_fixed := app.Box{
		width = 100,
		config = {
			semantic_size = {{type = .Fixed, amount = 100}, {type = .Fixed, amount = 50}},
			floating_type = .Not_Floating,
		},
	}

	child_grow := app.Box{
		width = 50, // Initial small width
		config = {
			semantic_size = {{type = .Grow, amount = 0}, {type = .Fixed, amount = 50}},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child_fixed)
	append(&parent.children, &child_grow)

	app.sizing_grow_growable_width(&parent)

	// Parent available: 500 - 20 (padding) = 480
	// Fixed child takes: 100
	// Remaining for grow child: 480 - 100 - 50 (initial) = 330
	// Grow child final: 50 + 330 = 380
	expected_grow_width := 380

	testing.expect(t, child_grow.width == expected_grow_width,
		fmt.tprintf("Grow child should expand to 380, got %d", child_grow.width))
	testing.expect(t, child_fixed.width == 100,
		fmt.tprintf("Fixed child should remain 100, got %d", child_fixed.width))
}

// Test mixing Fit_Children and Grow
@(test)
test_mixed_fit_children_and_grow :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 600,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			semantic_size = {{type = .Fixed, amount = 600}, {type = .Fixed, amount = 100}},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 10,
		},
		children = make([dynamic]^app.Box),
	}

	container := app.Box{
		width = 150, // Fits its children
		config = {
			semantic_size = {{type = .Fit_Children, amount = 0}, {type = .Fixed, amount = 50}},
			floating_type = .Not_Floating,
		},
	}

	grow_child := app.Box{
		width = 100,
		config = {
			semantic_size = {{type = .Grow, amount = 0}, {type = .Fixed, amount = 50}},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &container)
	append(&parent.children, &grow_child)

	app.sizing_grow_growable_width(&parent)

	// Container: 150 (fixed by fit_children)
	// Gap: 10
	// Available for grow: 600 - 150 - 10 - 100 (initial) = 340
	// Grow child: 100 + 340 = 440
	expected_grow := 440

	testing.expect(t, grow_child.width == expected_grow,
		fmt.tprintf("Grow child should be 440, got %d", grow_child.width))
	testing.expect(t, container.width == 150,
		fmt.tprintf("Fit_Children container should remain 150, got %d", container.width))
}

// Test all sizing modes together
@(test)
test_all_sizing_modes_together :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 1000,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			semantic_size = {{type = .Fixed, amount = 1000}, {type = .Fixed, amount = 100}},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 0,
		},
		children = make([dynamic]^app.Box),
	}

	// After percent sizing, this will be set
	child_percent := app.Box{
		config = {
			semantic_size = {{type = .Percent, amount = 0.2}, {type = .Fixed, amount = 50}},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	child_fixed := app.Box{
		width = 150,
		config = {
			semantic_size = {{type = .Fixed, amount = 150}, {type = .Fixed, amount = 50}},
			floating_type = .Not_Floating,
		},
	}

	child_grow1 := app.Box{
		width = 100,
		config = {
			semantic_size = {{type = .Grow, amount = 0}, {type = .Fixed, amount = 50}},
			floating_type = .Not_Floating,
		},
	}

	child_grow2 := app.Box{
		width = 100,
		config = {
			semantic_size = {{type = .Grow, amount = 0}, {type = .Fixed, amount = 50}},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child_percent)
	append(&parent.children, &child_fixed)
	append(&parent.children, &child_grow1)
	append(&parent.children, &child_grow2)

	// Sizing order: percent first, then grow
	app.sizing_calc_percent_width(&parent)
	app.sizing_grow_growable_width(&parent)

	// Percent child: 20% of 1000 = 200
	testing.expect(t, child_percent.width == 200,
		fmt.tprintf("Percent child should be 200, got %d", child_percent.width))

	// Fixed child: remains 150
	testing.expect(t, child_fixed.width == 150,
		fmt.tprintf("Fixed child should be 150, got %d", child_fixed.width))

	// Remaining for grow children: 1000 - 200 - 150 - 100 - 100 = 450
	// Split evenly: each gets 225 more, total 325
	expected_grow := 325

	testing.expect(t, child_grow1.width == expected_grow,
		fmt.tprintf("Grow child 1 should be 325, got %d", child_grow1.width))
	testing.expect(t, child_grow2.width == expected_grow,
		fmt.tprintf("Grow child 2 should be 325, got %d", child_grow2.width))
}

// Test Fit_Text sizing with grow
@(test)
test_fit_text_with_other_modes :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 500,
		config = {
			padding = {left = 10, top = 0, right = 10, bottom = 0},
			semantic_size = {{type = .Fixed, amount = 500}, {type = .Fixed, amount = 50}},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 5,
		},
		children = make([dynamic]^app.Box),
	}

	// Fit_Text starts with text width
	text_child := app.Box{
		width = 80, // Set by text measurement
		config = {
			semantic_size = {{type = .Fit_Text, amount = 0}, {type = .Fixed, amount = 30}},
			floating_type = .Not_Floating,
		},
	}

	grow_child := app.Box{
		width = 50,
		config = {
			semantic_size = {{type = .Grow, amount = 0}, {type = .Fixed, amount = 30}},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &text_child)
	append(&parent.children, &grow_child)

	app.sizing_grow_growable_width(&parent)

	// Fit_Text child: stays at 80
	testing.expect(t, text_child.width == 80,
		fmt.tprintf("Fit_Text child should remain 80, got %d", text_child.width))

	// Available: 500 - 20 (padding) - 80 (text) - 5 (gap) - 50 (initial grow) = 345
	// Grow child: 50 + 345 = 395
	expected_grow := 395

	testing.expect(t, grow_child.width == expected_grow,
		fmt.tprintf("Grow child should be 395, got %d", grow_child.width))
}

// Test empty container with Fit_Children
@(test)
test_empty_fit_children_container :: proc(t: ^testing.T) {
	parent := app.Box{
		config = {
			padding = {left = 10, top = 5, right = 15, bottom = 8},
			semantic_size = {{type = .Fit_Children, amount = 0}, {type = .Fit_Children, amount = 0}},
		},
		child_layout = {
			direction = .Horizontal,
		},
		children = make([dynamic]^app.Box),
	}

	width := app.sizing_calc_fit_children_width(parent)
	height := app.sizing_calc_fit_children_height(parent)

	// With no children, should just be padding
	expected_width := 10 + 15  // left + right padding
	expected_height := 5 + 8   // top + bottom padding

	testing.expect(t, width == expected_width,
		fmt.tprintf("Empty container width should be %d, got %d", expected_width, width))
	testing.expect(t, height == expected_height,
		fmt.tprintf("Empty container height should be %d, got %d", expected_height, height))
}

// Test single child with Fit_Children
@(test)
test_single_child_fit_children :: proc(t: ^testing.T) {
	parent := app.Box{
		config = {
			padding = {left = 10, top = 10, right = 10, bottom = 10},
			semantic_size = {{type = .Fit_Children, amount = 0}, {type = .Fit_Children, amount = 0}},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 20, // Should be ignored with single child
		},
		children = make([dynamic]^app.Box),
	}

	child := app.Box{
		width = 100,
		height = 80,
		config = {
			margin = {left = 5, top = 3, right = 7, bottom = 4},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child)

	width := app.sizing_calc_fit_children_width(parent)
	height := app.sizing_calc_fit_children_height(parent)

	// Width: 100 (child) + 12 (child margins) + 20 (padding) = 132
	// Height: 80 (child) + 7 (child margins) + 20 (padding) = 107
	// Gap should NOT be counted (only one child)

	expected_width := 132
	expected_height := 107

	testing.expect(t, width == expected_width,
		fmt.tprintf("Single child container width should be %d, got %d", expected_width, width))
	testing.expect(t, height == expected_height,
		fmt.tprintf("Single child container height should be %d, got %d", expected_height, height))
}

// Test grow with different initial sizes
@(test)
test_grow_unequal_initial_sizes :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 500,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			semantic_size = {{type = .Fixed, amount = 500}, {type = .Fixed, amount = 100}},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 0,
		},
		children = make([dynamic]^app.Box),
	}

	// Child with smaller initial width should grow first
	child1 := app.Box{
		width = 50,
		config = {
			semantic_size = {{type = .Grow, amount = 0}, {type = .Fixed, amount = 50}},
			floating_type = .Not_Floating,
		},
	}

	child2 := app.Box{
		width = 100,
		config = {
			semantic_size = {{type = .Grow, amount = 0}, {type = .Fixed, amount = 50}},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child1)
	append(&parent.children, &child2)

	app.sizing_grow_growable_width(&parent)

	// Both should end up equal after grow
	// Remaining: 500 - 50 - 100 = 350
	// Child1 needs 50 to match child2, leaving 300
	// Split 300 evenly: 150 each
	// Final: child1 = 50 + 50 + 150 = 250, child2 = 100 + 150 = 250

	testing.expect(t, child1.width == 250,
		fmt.tprintf("Child1 should grow to 250, got %d", child1.width))
	testing.expect(t, child2.width == 250,
		fmt.tprintf("Child2 should grow to 250, got %d", child2.width))
}

// Test vertical layout with mixed sizing
@(test)
test_vertical_mixed_sizing :: proc(t: ^testing.T) {
	parent := app.Box{
		height = 600,
		config = {
			padding = {left = 0, top = 10, right = 0, bottom = 10},
			semantic_size = {{type = .Fixed, amount = 200}, {type = .Fixed, amount = 600}},
		},
		child_layout = {
			direction = .Vertical,
			gap_vertical = 5,
		},
		children = make([dynamic]^app.Box),
	}

	child_fixed := app.Box{
		height = 100,
		config = {
			semantic_size = {{type = .Fixed, amount = 100}, {type = .Fixed, amount = 100}},
			floating_type = .Not_Floating,
		},
	}

	child_grow := app.Box{
		height = 50,
		config = {
			semantic_size = {{type = .Fixed, amount = 100}, {type = .Grow, amount = 0}},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child_fixed)
	append(&parent.children, &child_grow)

	app.sizing_grow_growable_height(&parent)

	// Available: 600 - 20 (padding) = 580
	// Fixed: 100
	// Gap: 5
	// Remaining: 580 - 100 - 5 - 50 = 425
	// Grow: 50 + 425 = 475

	expected_grow_height := 475

	testing.expect(t, child_grow.height == expected_grow_height,
		fmt.tprintf("Grow child height should be 475, got %d", child_grow.height))
}
