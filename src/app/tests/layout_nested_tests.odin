package tests
import "core:fmt"
import "core:testing"
import app "../"

// Tests for complex nested layout scenarios

// Test nested horizontal in vertical
@(test)
test_nested_horizontal_in_vertical :: proc(t: ^testing.T) {
	grandparent := app.Box{
		width = 500,
		height = 600,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fixed, amount = 500}, {type = .Fixed, amount = 600}},
		},
		child_layout = {
			direction = .Vertical,
			gap_vertical = 10,
		},
		children = make([dynamic]^app.Box),
	}

	// Horizontal container inside vertical parent
	parent := app.Box{
		config = {
			padding = {left = 10, top = 0, right = 10, bottom = 0},
			size = {{type = .Fit_Children, amount = 0}, {type = .Fit_Children, amount = 0}},
			floating_type = .Not_Floating,
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 5,
		},
		parent = &grandparent,
		children = make([dynamic]^app.Box),
	}

	child1 := app.Box{
		width = 100,
		height = 50,
		config = {
			size = {{type = .Fixed, amount = 100}, {type = .Fixed, amount = 50}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	child2 := app.Box{
		width = 150,
		height = 50,
		config = {
			size = {{type = .Fixed, amount = 150}, {type = .Fixed, amount = 50}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child1, &child2)
	append(&grandparent.children, &parent)

	// Parent should fit its children horizontally
	// Width = child1 (100) + gap (5) + child2 (150) + padding (20) = 275
	parent.width = app.sizing_calc_fit_children_width(parent)
	expected_width := 275
	testing.expect(t, parent.width == expected_width,
		fmt.tprintf("Nested horizontal parent width should be %d, got %d", expected_width, parent.width))

	// Height should fit the tallest child
	// Height = 50 + padding (0) = 50
	parent.height = app.sizing_calc_fit_children_height(parent)
	expected_height := 50
	testing.expect(t, parent.height == expected_height,
		fmt.tprintf("Nested horizontal parent height should be %d, got %d", expected_height, parent.height))

	delete(parent.children)
	delete(grandparent.children)
}

// Test deeply nested fit_children (3 levels)
@(test)
test_three_level_nested_fit_children :: proc(t: ^testing.T) {
	root := app.Box{
		config = {
			padding = {left = 5, top = 5, right = 5, bottom = 5},
			size = {{type = .Fit_Children, amount = 0}, {type = .Fit_Children, amount = 0}},
		},
		child_layout = {
			direction = .Vertical,
			gap_vertical = 0,
		},
		children = make([dynamic]^app.Box),
	}

	level1 := app.Box{
		config = {
			padding = {left = 10, top = 10, right = 10, bottom = 10},
			size = {{type = .Fit_Children, amount = 0}, {type = .Fit_Children, amount = 0}},
			floating_type = .Not_Floating,
		},
		child_layout = {
			direction = .Vertical,
			gap_vertical = 0,
		},
		parent = &root,
		children = make([dynamic]^app.Box),
	}

	level2 := app.Box{
		config = {
			padding = {left = 15, top = 15, right = 15, bottom = 15},
			size = {{type = .Fit_Children, amount = 0}, {type = .Fit_Children, amount = 0}},
			floating_type = .Not_Floating,
		},
		child_layout = {
			direction = .Vertical,
			gap_vertical = 0,
		},
		parent = &level1,
		children = make([dynamic]^app.Box),
	}

	leaf := app.Box{
		width = 100,
		height = 80,
		config = {
			size = {{type = .Fixed, amount = 100}, {type = .Fixed, amount = 80}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &level2,
	}

	append(&level2.children, &leaf)
	append(&level1.children, &level2)
	append(&root.children, &level1)

	// Calculate sizes from innermost to outermost
	level2.width = app.sizing_calc_fit_children_width(level2)
	level2.height = app.sizing_calc_fit_children_height(level2)

	// Level2: 100 + 15 + 15 = 130 width, 80 + 15 + 15 = 110 height
	testing.expect(t, level2.width == 130,
		fmt.tprintf("Level2 width should be 130, got %d", level2.width))
	testing.expect(t, level2.height == 110,
		fmt.tprintf("Level2 height should be 110, got %d", level2.height))

	level1.width = app.sizing_calc_fit_children_width(level1)
	level1.height = app.sizing_calc_fit_children_height(level1)

	// Level1: 130 + 10 + 10 = 150 width, 110 + 10 + 10 = 130 height
	testing.expect(t, level1.width == 150,
		fmt.tprintf("Level1 width should be 150, got %d", level1.width))
	testing.expect(t, level1.height == 130,
		fmt.tprintf("Level1 height should be 130, got %d", level1.height))

	root.width = app.sizing_calc_fit_children_width(root)
	root.height = app.sizing_calc_fit_children_height(root)

	// Root: 150 + 5 + 5 = 160 width, 130 + 5 + 5 = 140 height
	testing.expect(t, root.width == 160,
		fmt.tprintf("Root width should be 160, got %d", root.width))
	testing.expect(t, root.height == 140,
		fmt.tprintf("Root height should be 140, got %d", root.height))

	delete(leaf.children)
	delete(level2.children)
	delete(level1.children)
	delete(root.children)
}

// Test nested with margins propagating
@(test)
test_nested_margins_propagation :: proc(t: ^testing.T) {
	parent := app.Box{
		config = {
			padding = {left = 10, top = 10, right = 10, bottom = 10},
			size = {{type = .Fit_Children, amount = 0}, {type = .Fit_Children, amount = 0}},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 0,
		},
		children = make([dynamic]^app.Box),
	}

	child_container := app.Box{
		config = {
			padding = {left = 5, top = 5, right = 5, bottom = 5},
			margin = {left = 8, right = 12, top = 0, bottom = 0},
			size = {{type = .Fit_Children, amount = 0}, {type = .Fit_Children, amount = 0}},
			floating_type = .Not_Floating,
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 0,
		},
		parent = &parent,
		children = make([dynamic]^app.Box),
	}

	grandchild := app.Box{
		width = 50,
		height = 30,
		config = {
			size = {{type = .Fixed, amount = 50}, {type = .Fixed, amount = 30}},
			margin = {left = 3, right = 7, top = 2, bottom = 4},
			floating_type = .Not_Floating,
		},
		parent = &child_container,
	}

	append(&child_container.children, &grandchild)
	append(&parent.children, &child_container)

	// Calculate child_container size
	child_container.width = app.sizing_calc_fit_children_width(child_container)
	child_container.height = app.sizing_calc_fit_children_height(child_container)

	// child_container width = grandchild width (50) + grandchild margins (3 + 7) + container padding (5 + 5) = 70
	expected_container_width := 70
	testing.expect(t, child_container.width == expected_container_width,
		fmt.tprintf("Container width should be %d, got %d", expected_container_width, child_container.width))

	// child_container height = grandchild height (30) + grandchild margins (2 + 4) + container padding (5 + 5) = 46
	expected_container_height := 46
	testing.expect(t, child_container.height == expected_container_height,
		fmt.tprintf("Container height should be %d, got %d", expected_container_height, child_container.height))

	// Calculate parent size (includes child_container's margins but not its own)
	parent.width = app.sizing_calc_fit_children_width(parent)
	parent.height = app.sizing_calc_fit_children_height(parent)

	// parent width = child_container width (70) + child_container margins (8 + 12) + parent padding (10 + 10) = 110
	expected_parent_width := 110
	testing.expect(t, parent.width == expected_parent_width,
		fmt.tprintf("Parent width should be %d, got %d", expected_parent_width, parent.width))

	delete(child_container.children)
	delete(parent.children)
}

// Test nested percent sizing
@(test)
test_nested_percent :: proc(t: ^testing.T) {
	grandparent := app.Box{
		width = 1000,
		height = 500,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fixed, amount = 1000}, {type = .Fixed, amount = 500}},
		},
		children = make([dynamic]^app.Box),
	}

	// Parent is 50% of grandparent
	parent := app.Box{
		config = {
			size = {{type = .Percent, amount = 0.5}, {type = .Percent, amount = 0.5}},
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &grandparent,
		children = make([dynamic]^app.Box),
	}

	// Child is 50% of parent
	child := app.Box{
		config = {
			size = {{type = .Percent, amount = 0.5}, {type = .Percent, amount = 0.5}},
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child)
	append(&grandparent.children, &parent)

	// Calculate percent sizes
	app.sizing_calc_percent_width(&grandparent)
	app.sizing_calc_percent_height(&grandparent)

	// Parent should be 50% of 1000 = 500
	testing.expect(t, parent.width == 500,
		fmt.tprintf("Parent width should be 500, got %d", parent.width))
	testing.expect(t, parent.height == 250,
		fmt.tprintf("Parent height should be 250, got %d", parent.height))

	// Child should be 50% of parent = 50% of 500 = 250
	testing.expect(t, child.width == 250,
		fmt.tprintf("Child width should be 250, got %d", child.width))
	testing.expect(t, child.height == 125,
		fmt.tprintf("Child height should be 125, got %d", child.height))

	delete(parent.children)
	delete(grandparent.children)
}

// Test mixed nested sizing (grow inside fit_children)
@(test)
test_nested_grow_in_fit_children :: proc(t: ^testing.T) {
	// This tests that a fit_children parent correctly sizes to accommodate
	// its grow children AFTER they have grown

	grandparent := app.Box{
		width = 800,
		height = 200,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fixed, amount = 800}, {type = .Fixed, amount = 200}},
		},
		child_layout = {
			direction = .Vertical,
		},
		children = make([dynamic]^app.Box),
	}

	// Parent that fits children
	parent := app.Box{
		width = 800, // Will be set by grandparent
		config = {
			size = {{type = .Percent, amount = 1.0}, {type = .Fit_Children, amount = 0}},
			padding = {left = 10, top = 10, right = 10, bottom = 10},
			floating_type = .Not_Floating,
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 10,
		},
		parent = &grandparent,
		children = make([dynamic]^app.Box),
	}

	child_fixed := app.Box{
		width = 200,
		height = 100,
		config = {
			size = {{type = .Fixed, amount = 200}, {type = .Fixed, amount = 100}},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	child_grow := app.Box{
		width = 100, // Initial
		height = 100,
		config = {
			size = {{type = .Grow, amount = 1.0}, {type = .Fixed, amount = 100}},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child_fixed, &child_grow)
	append(&grandparent.children, &parent)

	// First set parent width from percent
	app.sizing_calc_percent_width(&grandparent)
	testing.expect(t, parent.width == 800,
		fmt.tprintf("Parent width should be 800, got %d", parent.width))

	// The grow child should grow to fill available space in parent
	// Content width = 800 - 20 (padding) = 780
	// Fixed child = 200
	// Gap = 10
	// Available for grow = 780 - 200 - 10 - 100 (initial grow size) = 470
	// Grow child final = 100 + 470 = 570

	content_width := parent.width - parent.config.padding.left - parent.config.padding.right
	gap := parent.child_layout.gap_horizontal
	available := content_width - child_fixed.width - gap - child_grow.width
	expected_grow_final := child_grow.width + available

	testing.expect(t, expected_grow_final == 570,
		fmt.tprintf("Grow child should grow to 570, calculated %d", expected_grow_final))

	// Parent height should fit the children
	// Height = 100 (child height) + 10 + 10 (padding) = 120
	parent.height = app.sizing_calc_fit_children_height(parent)
	testing.expect(t, parent.height == 120,
		fmt.tprintf("Parent height should be 120, got %d", parent.height))

	delete(parent.children)
	delete(grandparent.children)
}

// Test alternating directions (H->V->H)
@(test)
test_alternating_directions :: proc(t: ^testing.T) {
	root := app.Box{
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fit_Children, amount = 0}, {type = .Fit_Children, amount = 0}},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 5,
		},
		children = make([dynamic]^app.Box),
	}

	vertical_container := app.Box{
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fit_Children, amount = 0}, {type = .Fit_Children, amount = 0}},
			floating_type = .Not_Floating,
		},
		child_layout = {
			direction = .Vertical,
			gap_vertical = 3,
		},
		parent = &root,
		children = make([dynamic]^app.Box),
	}

	horizontal_container := app.Box{
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fit_Children, amount = 0}, {type = .Fit_Children, amount = 0}},
			floating_type = .Not_Floating,
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 2,
		},
		parent = &vertical_container,
		children = make([dynamic]^app.Box),
	}

	leaf1 := app.Box{
		width = 30,
		height = 20,
		config = {
			size = {{type = .Fixed, amount = 30}, {type = .Fixed, amount = 20}},
			floating_type = .Not_Floating,
		},
		parent = &horizontal_container,
	}

	leaf2 := app.Box{
		width = 40,
		height = 20,
		config = {
			size = {{type = .Fixed, amount = 40}, {type = .Fixed, amount = 20}},
			floating_type = .Not_Floating,
		},
		parent = &horizontal_container,
	}

	append(&horizontal_container.children, &leaf1, &leaf2)
	append(&vertical_container.children, &horizontal_container)
	append(&root.children, &vertical_container)

	// Calculate from innermost to outermost
	horizontal_container.width = app.sizing_calc_fit_children_width(horizontal_container)
	horizontal_container.height = app.sizing_calc_fit_children_height(horizontal_container)

	// Horizontal container: 30 + 2 + 40 = 72 width, 20 height
	testing.expect(t, horizontal_container.width == 72,
		fmt.tprintf("Horizontal container width should be 72, got %d", horizontal_container.width))
	testing.expect(t, horizontal_container.height == 20,
		fmt.tprintf("Horizontal container height should be 20, got %d", horizontal_container.height))

	vertical_container.width = app.sizing_calc_fit_children_width(vertical_container)
	vertical_container.height = app.sizing_calc_fit_children_height(vertical_container)

	// Vertical container: 72 width (widest child), 20 height (only child)
	testing.expect(t, vertical_container.width == 72,
		fmt.tprintf("Vertical container width should be 72, got %d", vertical_container.width))
	testing.expect(t, vertical_container.height == 20,
		fmt.tprintf("Vertical container height should be 20, got %d", vertical_container.height))

	root.width = app.sizing_calc_fit_children_width(root)
	root.height = app.sizing_calc_fit_children_height(root)

	// Root: 72 width, 20 height (only child in horizontal layout)
	testing.expect(t, root.width == 72,
		fmt.tprintf("Root width should be 72, got %d", root.width))
	testing.expect(t, root.height == 20,
		fmt.tprintf("Root height should be 20, got %d", root.height))

	delete(horizontal_container.children)
	delete(vertical_container.children)
	delete(root.children)
}
