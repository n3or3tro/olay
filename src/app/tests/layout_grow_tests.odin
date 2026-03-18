package tests

import "core:fmt"
import "core:testing"
import app "../"

// Test grow sizing in horizontal layout with margins
@(test)
test_grow_horizontal_with_margins :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 500,
		config = {
			padding = {left = 10, top = 0, right = 10, bottom = 0},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 5,
		},
		children = make([dynamic]^app.Box),
	}

	// Fixed size child
	child1 := app.Box{
		width = 100,
		config = {
			margin = {left = 5, right = 5, top = 0, bottom = 0},
			floating_type = .Not_Floating,
			size = {{type = .Fixed, amount = 100}, {type = .Fixed, amount = 50}},
		},
	}

	// Growable child
	child2 := app.Box{
		width = 50,
		config = {
			margin = {left = 10, right = 10, top = 0, bottom = 0},
			floating_type = .Not_Floating,
			size = {{type = .Grow, amount = 0}, {type = .Fixed, amount = 50}},
		},
	}

	append(&parent.children, &child1)
	append(&parent.children, &child2)

	// Simulate the grow logic
	remaining_width := parent.width - app.box_get_padding_x_tot(parent)
	// Subtract child1: width + margins
	remaining_width -= child1.width + app.box_get_margin_x_tot(child1)
	// Subtract child2: width + margins
	remaining_width -= child2.width + app.box_get_margin_x_tot(child2)
	// Subtract gap
	remaining_width -= parent.child_layout.gap_horizontal

	// Expected remaining width:
	// 500 - 20 (padding) - 100 (child1) - 10 (child1 margins) - 50 (child2) - 20 (child2 margins) - 5 (gap) = 295
	expected_remaining := 295

	testing.expect(t, remaining_width == expected_remaining,
		fmt.tprintf("Remaining width after accounting for margins should be 295, got %d", remaining_width))

	// Now child2 should grow to fill remaining space
	// child2.width should increase by remaining_width
	expected_child2_final_width := 50 + remaining_width

	testing.expect(t, expected_child2_final_width == 345,
		fmt.tprintf("Child2 final width should be 345, got %d", expected_child2_final_width))
}

// Test grow sizing in vertical layout with margins
@(test)
test_grow_vertical_with_margins :: proc(t: ^testing.T) {
	parent := app.Box{
		height = 500,
		config = {
			padding = {left = 0, top = 10, right = 0, bottom = 10},
		},
		child_layout = {
			direction = .Vertical,
			gap_vertical = 5,
		},
		children = make([dynamic]^app.Box),
	}

	// Fixed size child
	child1 := app.Box{
		height = 100,
		config = {
			margin = {left = 0, top = 5, right = 0, bottom = 5},
			floating_type = .Not_Floating,
			size = {{type = .Fixed, amount = 50}, {type = .Fixed, amount = 100}},
		},
	}

	// Growable child
	child2 := app.Box{
		height = 50,
		config = {
			margin = {left = 0, top = 10, right = 0, bottom = 10},
			floating_type = .Not_Floating,
			size = {{type = .Fixed, amount = 50}, {type = .Grow, amount = 0}},
		},
	}

	append(&parent.children, &child1)
	append(&parent.children, &child2)

	remaining_height := parent.height - app.box_get_padding_y_tot(parent)
	remaining_height -= child1.height + app.box_get_margin_y_tot(child1)
	remaining_height -= child2.height + app.box_get_margin_y_tot(child2)
	remaining_height -= parent.child_layout.gap_vertical

	// Expected remaining height:
	// 500 - 20 (padding) - 100 (child1) - 10 (child1 margins) - 50 (child2) - 20 (child2 margins) - 5 (gap) = 295
	expected_remaining := 295

	testing.expect(t, remaining_height == expected_remaining,
		fmt.tprintf("Remaining height after accounting for margins should be 295, got %d", remaining_height))
}

// Test multiple growable children with margins
@(test)
test_multiple_grow_children_with_margins :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 500,
		config = {
			padding = {left = 10, top = 0, right = 10, bottom = 0},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 5,
		},
		children = make([dynamic]^app.Box),
	}

	// First growable child
	child1 := app.Box{
		width = 50,
		config = {
			margin = {left = 5, right = 5, top = 0, bottom = 0},
			floating_type = .Not_Floating,
			size = {{type = .Grow, amount = 0}, {type = .Fixed, amount = 50}},
		},
	}

	// Second growable child
	child2 := app.Box{
		width = 50,
		config = {
			margin = {left = 10, right = 10, top = 0, bottom = 0},
			floating_type = .Not_Floating,
			size = {{type = .Grow, amount = 0}, {type = .Fixed, amount = 50}},
		},
	}

	append(&parent.children, &child1)
	append(&parent.children, &child2)

	remaining_width := parent.width - app.box_get_padding_x_tot(parent)
	remaining_width -= child1.width + app.box_get_margin_x_tot(child1)
	remaining_width -= child2.width + app.box_get_margin_x_tot(child2)
	remaining_width -= parent.child_layout.gap_horizontal

	// Expected remaining width:
	// 500 - 20 (padding) - 50 (child1) - 10 (child1 margins) - 50 (child2) - 20 (child2 margins) - 5 (gap) = 345

	expected_remaining := 345

	testing.expect(t, remaining_width == expected_remaining,
		fmt.tprintf("Remaining width with two growable children should be 345, got %d", remaining_width))

	// In the grow algorithm, the smallest child grows first
	// Both children start at width 50
	// child1 total width with margin: 50 + 10 = 60
	// child2 total width with margin: 50 + 20 = 70
	// child1 is smallest, so it should grow first
}

// Test cross-axis grow (vertical layout, horizontal grow)
@(test)
test_cross_axis_grow_horizontal :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 500,
		config = {
			padding = {left = 10, top = 0, right = 10, bottom = 0},
		},
		child_layout = {
			direction = .Vertical,
		},
		children = make([dynamic]^app.Box),
	}

	// In vertical layout, children can grow horizontally to fill parent width
	child := app.Box{
		width = 100,
		config = {
			margin = {left = 20, right = 30, top = 0, bottom = 0},
			floating_type = .Not_Floating,
			size = {{type = .Grow, amount = 0}, {type = .Fixed, amount = 50}},
		},
	}

	append(&parent.children, &child)

	growable_amount := parent.width - app.box_get_padding_x_tot(parent)
	// Expected: 500 - 20 = 480

	// The child should grow to fill this space minus its margins
	// child.width should become: growable_amount - (child.width + margins)
	// But actually the implementation is:
	// child.width += growable_amount - (child.width + box_get_margin_x_tot(child^))

	expected_growable := 480
	expected_increase := growable_amount - (child.width + app.box_get_margin_x_tot(child))
	expected_final_width := child.width + expected_increase

	// growable_amount = 480
	// child margin total = 50
	// expected_increase = 480 - (100 + 50) = 330
	// expected_final_width = 100 + 330 = 430

	testing.expect(t, expected_growable == 480,
		fmt.tprintf("Growable amount should be 480, got %d", expected_growable))
	testing.expect(t, expected_increase == 330,
		fmt.tprintf("Expected width increase should be 330, got %d", expected_increase))
	testing.expect(t, expected_final_width == 430,
		fmt.tprintf("Final child width should be 430, got %d", expected_final_width))
}

// Test cross-axis grow (horizontal layout, vertical grow)
@(test)
test_cross_axis_grow_vertical :: proc(t: ^testing.T) {
	parent := app.Box{
		height = 500,
		config = {
			padding = {left = 0, top = 10, right = 0, bottom = 10},
		},
		child_layout = {
			direction = .Horizontal,
		},
		children = make([dynamic]^app.Box),
	}

	child := app.Box{
		height = 100,
		config = {
			margin = {left = 0, top = 20, right = 0, bottom = 30},
			floating_type = .Not_Floating,
			size = {{type = .Fixed, amount = 50}, {type = .Grow, amount = 0}},
		},
	}

	append(&parent.children, &child)

	growable_amount := parent.height - app.box_get_padding_y_tot(parent)
	expected_growable := 480

	expected_increase := growable_amount - (child.height + app.box_get_margin_y_tot(child))
	expected_final_height := child.height + expected_increase

	// growable_amount = 480
	// child margin total = 50
	// expected_increase = 480 - (100 + 50) = 330
	// expected_final_height = 100 + 330 = 430

	testing.expect(t, expected_growable == 480,
		fmt.tprintf("Growable amount should be 480, got %d", expected_growable))
	testing.expect(t, expected_increase == 330,
		fmt.tprintf("Expected height increase should be 330, got %d", expected_increase))
	testing.expect(t, expected_final_height == 430,
		fmt.tprintf("Final child height should be 430, got %d", expected_final_height))
}

// Test Fit_Text_And_Grow with margins
@(test)
test_fit_text_and_grow_with_margins :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 500,
		config = {
			padding = {left = 10, top = 0, right = 10, bottom = 0},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 0,
		},
		children = make([dynamic]^app.Box),
	}

	// Fixed child
	child1 := app.Box{
		width = 100,
		config = {
			margin = {left = 5, right = 5, top = 0, bottom = 0},
			floating_type = .Not_Floating,
			size = {{type = .Fixed, amount = 100}, {type = .Fixed, amount = 50}},
		},
	}

	// Fit_Text_And_Grow child starts with text width but can grow
	child2 := app.Box{
		width = 80, // Initial text width
		config = {
			margin = {left = 10, right = 15, top = 0, bottom = 0},
			floating_type = .Not_Floating,
			size = {{type = .Fit_Text_And_Grow, amount = 0}, {type = .Fixed, amount = 50}},
		},
	}

	append(&parent.children, &child1)
	append(&parent.children, &child2)

	remaining_width := parent.width - app.box_get_padding_x_tot(parent)
	remaining_width -= child1.width + app.box_get_margin_x_tot(child1)
	remaining_width -= child2.width + app.box_get_margin_x_tot(child2)

	// Expected remaining:
	// 500 - 20 (padding) - 100 (child1) - 10 (child1 margins) - 80 (child2) - 25 (child2 margins) = 265
	expected_remaining := 265

	testing.expect(t, remaining_width == expected_remaining,
		fmt.tprintf("Remaining width for Fit_Text_And_Grow should be 265, got %d", remaining_width))
}

// Test Fit_Children_And_Grow with margins
@(test)
test_fit_children_and_grow_with_margins :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 600,
		config = {
			padding = {left = 10, top = 0, right = 10, bottom = 0},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 0,
		},
		children = make([dynamic]^app.Box),
	}

	// Container that fits its children but can also grow
	container := app.Box{
		width = 150, // Initial size based on children
		config = {
			margin = {left = 10, right = 10, top = 0, bottom = 0},
			floating_type = .Not_Floating,
			size = {{type = .Fit_Children_And_Grow, amount = 0}, {type = .Fixed, amount = 50}},
		},
	}

	append(&parent.children, &container)

	remaining_width := parent.width - app.box_get_padding_x_tot(parent)
	remaining_width -= container.width + app.box_get_margin_x_tot(container)

	// Expected:
	// 600 - 20 (padding) - 150 (container) - 20 (container margins) = 410
	expected_remaining := 410

	testing.expect(t, remaining_width == expected_remaining,
		fmt.tprintf("Remaining width for Fit_Children_And_Grow should be 410, got %d", remaining_width))
}

// Test that margins don't interfere with gap calculations
@(test)
test_margins_and_gaps :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 500,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 10,
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
		width = 100,
		config = {
			margin = {left = 5, right = 5, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
	}

	append(&parent.children, &child1)
	append(&parent.children, &child2)

	// In positioning, the gap goes between the boxes, separate from margins
	// child1: 0 + margin.left(5) = 5 to 105, right edge + margin.right(5) = 110
	// gap: 10
	// child2: 110 + 10 + margin.left(5) = 125 to 225

	child1.top_left.x = 0 + child1.config.margin.left
	child1.bottom_right.x = child1.top_left.x + child1.width

	child2.top_left.x = child1.bottom_right.x + child1.config.margin.right + parent.child_layout.gap_horizontal + child2.config.margin.left
	child2.bottom_right.x = child2.top_left.x + child2.width

	testing.expect(t, child1.top_left.x == 5,
		fmt.tprintf("Child1 left should be 5, got %d", child1.top_left.x))
	testing.expect(t, child2.top_left.x == 125,
		fmt.tprintf("Child2 left should be 125, got %d", child2.top_left.x))
}
