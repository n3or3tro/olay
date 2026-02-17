package tests

import "core:fmt"
import "core:testing"
import app "../"

// Test basic percent width sizing
@(test)
test_percent_width_basic :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 500,
		config = {
			padding = {left = 10, top = 0, right = 10, bottom = 0},
			size = {{type = .Fixed, amount = 500}, {type = .Fixed, amount = 100}},
		},
		children = make([dynamic]^app.Box),
	}

	child := app.Box{
		config = {
			size = {{type = .Percent, amount = 0.5}, {type = .Fixed, amount = 100}},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child)

	// Calculate percent sizing
	app.sizing_calc_percent_width(&parent)

	// Available width = 500 - 20 (padding) = 480
	// Child should be 50% of available = 240
	expected_width := 240

	testing.expect(t, child.width == expected_width,
		fmt.tprintf("Child percent width should be 240, got %d", child.width))
}

// Test percent height sizing
@(test)
test_percent_height_basic :: proc(t: ^testing.T) {
	parent := app.Box{
		height = 500,
		config = {
			padding = {left = 0, top = 10, right = 0, bottom = 10},
			size = {{type = .Fixed, amount = 100}, {type = .Fixed, amount = 500}},
		},
		children = make([dynamic]^app.Box),
	}

	child := app.Box{
		config = {
			size = {{type = .Fixed, amount = 100}, {type = .Percent, amount = 0.75}},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child)

	app.sizing_calc_percent_height(&parent)

	// Available height = 500 - 20 (padding) = 480
	// Child should be 75% of available = 360
	expected_height := 360

	testing.expect(t, child.height == expected_height,
		fmt.tprintf("Child percent height should be 360, got %d", child.height))
}

// Test multiple children with percent sizing
@(test)
test_percent_multiple_children :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 1000,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fixed, amount = 1000}, {type = .Fixed, amount = 100}},
		},
		children = make([dynamic]^app.Box),
	}

	child1 := app.Box{
		config = {
			size = {{type = .Percent, amount = 0.3}, {type = .Fixed, amount = 50}},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	child2 := app.Box{
		config = {
			size = {{type = .Percent, amount = 0.6}, {type = .Fixed, amount = 50}},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child1)
	append(&parent.children, &child2)

	app.sizing_calc_percent_width(&parent)

	// child1: 30% of 1000 = 300
	// child2: 60% of 1000 = 600
	testing.expect(t, child1.width == 300,
		fmt.tprintf("Child1 width should be 300, got %d", child1.width))
	testing.expect(t, child2.width == 600,
		fmt.tprintf("Child2 width should be 600, got %d", child2.width))
}

// Test percent sizing with padding
@(test)
test_percent_with_padding :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 500,
		config = {
			padding = {left = 50, top = 0, right = 50, bottom = 0},
			size = {{type = .Fixed, amount = 500}, {type = .Fixed, amount = 100}},
		},
		children = make([dynamic]^app.Box),
	}

	child := app.Box{
		config = {
			size = {{type = .Percent, amount = 1.0}, {type = .Fixed, amount = 100}},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child)

	app.sizing_calc_percent_width(&parent)

	// Available width = 500 - 100 (padding) = 400
	// Child is 100% = 400
	expected_width := 400

	testing.expect(t, child.width == expected_width,
		fmt.tprintf("Child with 100%% width should be 400, got %d", child.width))
}

// Test nested percent sizing
@(test)
test_percent_nested :: proc(t: ^testing.T) {
	grandparent := app.Box{
		width = 1000,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fixed, amount = 1000}, {type = .Fixed, amount = 200}},
		},
		children = make([dynamic]^app.Box),
	}

	parent := app.Box{
		config = {
			size = {{type = .Percent, amount = 0.5}, {type = .Fixed, amount = 100}},
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &grandparent,
		children = make([dynamic]^app.Box),
	}

	child := app.Box{
		config = {
			size = {{type = .Percent, amount = 0.8}, {type = .Fixed, amount = 50}},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&grandparent.children, &parent)
	append(&parent.children, &child)

	// Calculate from top down
	app.sizing_calc_percent_width(&grandparent)

	// parent: 50% of 1000 = 500
	testing.expect(t, parent.width == 500,
		fmt.tprintf("Parent width should be 500, got %d", parent.width))

	// child: 80% of parent's 500 = 400
	testing.expect(t, child.width == 400,
		fmt.tprintf("Child width should be 400, got %d", child.width))
}

// Test percent sizing ignores floating children
@(test)
test_percent_ignores_floating :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 500,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fixed, amount = 500}, {type = .Fixed, amount = 100}},
		},
		children = make([dynamic]^app.Box),
	}

	child_normal := app.Box{
		config = {
			size = {{type = .Percent, amount = 0.5}, {type = .Fixed, amount = 100}},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	child_floating := app.Box{
		width = 100,
		config = {
			size = {{type = .Percent, amount = 0.5}, {type = .Fixed, amount = 100}},
			floating_type = .Relative_Root,
		},
		parent = &parent,
	}

	append(&parent.children, &child_normal)
	append(&parent.children, &child_floating)

	// Store original floating child width
	original_floating_width := child_floating.width

	app.sizing_calc_percent_width(&parent)

	// Normal child should be calculated
	testing.expect(t, child_normal.width == 250,
		fmt.tprintf("Normal child width should be 250, got %d", child_normal.width))

	// Floating child should NOT be recalculated
	testing.expect(t, child_floating.width == original_floating_width,
		fmt.tprintf("Floating child width should remain %d, got %d", original_floating_width, child_floating.width))
}

// Test percent sizing edge case: 0% and 100%
@(test)
test_percent_edge_cases :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 500,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fixed, amount = 500}, {type = .Fixed, amount = 100}},
		},
		children = make([dynamic]^app.Box),
	}

	child_zero := app.Box{
		config = {
			size = {{type = .Percent, amount = 0.0}, {type = .Fixed, amount = 100}},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	child_full := app.Box{
		config = {
			size = {{type = .Percent, amount = 1.0}, {type = .Fixed, amount = 100}},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child_zero)
	append(&parent.children, &child_full)

	app.sizing_calc_percent_width(&parent)

	testing.expect(t, child_zero.width == 0,
		fmt.tprintf("0%% child width should be 0, got %d", child_zero.width))
	testing.expect(t, child_full.width == 500,
		fmt.tprintf("100%% child width should be 500, got %d", child_full.width))
}
