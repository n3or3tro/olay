package tests
import "core:fmt"
import "core:testing"
import app "../"

// Pathological and extreme edge case tests - pushing the UI system to its limits

// Test extremely deep nesting (10 levels)
@(test)
test_extreme_nesting_10_levels :: proc(t: ^testing.T) {
	// Build a 10-level deep hierarchy
	levels: [10]app.Box

	for i in 0..<10 {
		levels[i] = app.Box{
			config = {
				padding = {left = 1, top = 1, right = 1, bottom = 1},
				size = {{type = .Fit_Children, amount = 0}, {type = .Fit_Children, amount = 0}},
				floating_type = i == 0 ? .Not_Floating : .Not_Floating,
			},
			child_layout = {
				direction = i % 2 == 0 ? .Horizontal : .Vertical,
			},
			children = make([dynamic]^app.Box),
		}

		if i > 0 {
			levels[i].parent = &levels[i-1]
			append(&levels[i-1].children, &levels[i])
		}
	}

	// Leaf node at the bottom
	leaf := app.Box{
		width = 5,
		height = 5,
		config = {
			size = {{type = .Fixed, amount = 5}, {type = .Fixed, amount = 5}},
			floating_type = .Not_Floating,
		},
		parent = &levels[9],
	}
	append(&levels[9].children, &leaf)

	// Calculate sizes from bottom to top
	for i := 9; i >= 0; i -= 1 {
		levels[i].width = app.sizing_calc_fit_children_width(levels[i])
		levels[i].height = app.sizing_calc_fit_children_height(levels[i])
	}

	// Root should be: 5 + (2 * 10 levels of padding) = 5 + 20 = 25
	expected_size := 25
	testing.expect(t, levels[0].width == expected_size,
		fmt.tprintf("10-level deep root width should be %d, got %d", expected_size, levels[0].width))
	testing.expect(t, levels[0].height == expected_size,
		fmt.tprintf("10-level deep root height should be %d, got %d", expected_size, levels[0].height))

	// Cleanup
	for i in 0..<10 {
		delete(levels[i].children)
	}
}

// Test with hundreds of children
@(test)
test_many_children_100 :: proc(t: ^testing.T) {
	parent := app.Box{
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fit_Children, amount = 0}, {type = .Fit_Children, amount = 0}},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 1,
		},
		children = make([dynamic]^app.Box),
	}

	// Create 100 children, each 10 pixels wide
	children: [100]app.Box
	for i in 0..<100 {
		children[i] = app.Box{
			width = 10,
			height = 10,
			config = {
				size = {{type = .Fixed, amount = 10}, {type = .Fixed, amount = 10}},
				floating_type = .Not_Floating,
			},
			parent = &parent,
		}
		append(&parent.children, &children[i])
	}

	width := app.sizing_calc_fit_children_width(parent)

	// Width = 100 children * 10 pixels + 99 gaps * 1 pixel = 1000 + 99 = 1099
	expected_width := 1099
	testing.expect(t, width == expected_width,
		fmt.tprintf("100 children should produce width %d, got %d", expected_width, width))

	delete(parent.children)
}

// Test extreme grow amounts
@(test)
test_extreme_grow_amounts :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 10000,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fixed, amount = 10000}, {type = .Fixed, amount = 100}},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 0,
		},
		children = make([dynamic]^app.Box),
	}

	// One child with grow amount 1.0
	child1 := app.Box{
		width = 10,
		config = {
			size = {{type = .Grow, amount = 1.0}, {type = .Fixed, amount = 100}},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	// One child with grow amount 100.0 (extreme)
	child2 := app.Box{
		width = 10,
		config = {
			size = {{type = .Grow, amount = 100.0}, {type = .Fixed, amount = 100}},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child1, &child2)

	// Total grow = 101
	// Available = 10000 - 20 = 9980
	// Child1 grows by: 9980 * (1/101) ≈ 98.8
	// Child2 grows by: 9980 * (100/101) ≈ 9881.2

	available := parent.width - (child1.width + child2.width)
	total_grow := child1.config.size.x.amount + child2.config.size.x.amount
	child2_grow := int(f32(available) * (child2.config.size.x.amount / total_grow))

	// Child2 should get approximately 100x more than child1
	testing.expect(t, child2_grow > 9800,
		fmt.tprintf("Child with grow 100.0 should get >9800 pixels, calculated %d", child2_grow))

	delete(parent.children)
}

// Test very small grow amount (0.01)
@(test)
test_very_small_grow_amount :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 1000,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fixed, amount = 1000}, {type = .Fixed, amount = 100}},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 0,
		},
		children = make([dynamic]^app.Box),
	}

	child_tiny_grow := app.Box{
		width = 100,
		config = {
			size = {{type = .Grow, amount = 0.01}, {type = .Fixed, amount = 100}},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	child_normal_grow := app.Box{
		width = 100,
		config = {
			size = {{type = .Grow, amount = 1.0}, {type = .Fixed, amount = 100}},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child_tiny_grow, &child_normal_grow)

	// Available = 1000 - 200 = 800
	// Total grow = 0.01 + 1.0 = 1.01
	// Tiny grows by: 800 * (0.01/1.01) ≈ 7.9
	// Normal grows by: 800 * (1.0/1.01) ≈ 792.1

	available := parent.width - (child_tiny_grow.width + child_normal_grow.width)
	total_grow := child_tiny_grow.config.size.x.amount + child_normal_grow.config.size.x.amount
	tiny_grow := int(f32(available) * (child_tiny_grow.config.size.x.amount / total_grow))

	// Tiny grow should be very small
	testing.expect(t, tiny_grow >= 7 && tiny_grow <= 9,
		fmt.tprintf("Tiny grow (0.01) should get ~8 pixels, calculated %d", tiny_grow))

	delete(parent.children)
}

// Test percent values at extremes
@(test)
test_extreme_percent_values :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 1000,
		height = 500,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fixed, amount = 1000}, {type = .Fixed, amount = 500}},
		},
		children = make([dynamic]^app.Box),
	}

	// Child with 0.001% (very small)
	child_tiny := app.Box{
		config = {
			size = {{type = .Percent, amount = 0.00001}, {type = .Fixed, amount = 100}},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	// Child with 150% (exceeds parent)
	child_exceed := app.Box{
		config = {
			size = {{type = .Percent, amount = 1.5}, {type = .Fixed, amount = 100}},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child_tiny, &child_exceed)

	app.sizing_calc_percent_width(&parent)

	// Tiny should be ~0.01 pixels (rounds to 0)
	testing.expect(t, child_tiny.width >= 0 && child_tiny.width <= 1,
		fmt.tprintf("Tiny percent child should be 0-1 pixels, got %d", child_tiny.width))

	// Exceed should be 1500 (150% of 1000)
	testing.expect(t, child_exceed.width == 1500,
		fmt.tprintf("150%% child should be 1500, got %d", child_exceed.width))

	delete(parent.children)
}

// Test padding larger than content
@(test)
test_padding_larger_than_content :: proc(t: ^testing.T) {
	parent := app.Box{
		config = {
			padding = {left = 100, top = 100, right = 100, bottom = 100},
			size = {{type = .Fit_Children, amount = 0}, {type = .Fit_Children, amount = 0}},
		},
		children = make([dynamic]^app.Box),
	}

	// Tiny child (1x1)
	child := app.Box{
		width = 1,
		height = 1,
		config = {
			size = {{type = .Fixed, amount = 1}, {type = .Fixed, amount = 1}},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child)

	width := app.sizing_calc_fit_children_width(parent)
	height := app.sizing_calc_fit_children_height(parent)

	// Width = 1 + 100 + 100 = 201
	// Height = 1 + 100 + 100 = 201
	testing.expect(t, width == 201,
		fmt.tprintf("Padding larger than content width should be 201, got %d", width))
	testing.expect(t, height == 201,
		fmt.tprintf("Padding larger than content height should be 201, got %d", height))

	delete(parent.children)
}

// Test margins larger than content
@(test)
test_margins_larger_than_content :: proc(t: ^testing.T) {
	parent := app.Box{
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fit_Children, amount = 0}, {type = .Fit_Children, amount = 0}},
		},
		child_layout = {
			direction = .Horizontal,
		},
		children = make([dynamic]^app.Box),
	}

	// Tiny child with huge margins
	child := app.Box{
		width = 2,
		height = 2,
		config = {
			size = {{type = .Fixed, amount = 2}, {type = .Fixed, amount = 2}},
			margin = {left = 200, top = 200, right = 200, bottom = 200},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child)

	width := app.sizing_calc_fit_children_width(parent)
	height := app.sizing_calc_fit_children_height(parent)

	// Width = 2 + 200 + 200 = 402
	// Height = 2 + 200 + 200 = 402
	testing.expect(t, width == 402,
		fmt.tprintf("Margins larger than content width should be 402, got %d", width))
	testing.expect(t, height == 402,
		fmt.tprintf("Margins larger than content height should be 402, got %d", height))

	delete(parent.children)
}

// Test gap larger than all children combined
@(test)
test_gap_larger_than_children :: proc(t: ^testing.T) {
	parent := app.Box{
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fit_Children, amount = 0}, {type = .Fit_Children, amount = 0}},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 500, // Huge gap
		},
		children = make([dynamic]^app.Box),
	}

	child1 := app.Box{
		width = 10,
		height = 10,
		config = {
			size = {{type = .Fixed, amount = 10}, {type = .Fixed, amount = 10}},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	child2 := app.Box{
		width = 10,
		height = 10,
		config = {
			size = {{type = .Fixed, amount = 10}, {type = .Fixed, amount = 10}},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child1, &child2)

	width := app.sizing_calc_fit_children_width(parent)

	// Width = 10 + 500 (gap) + 10 = 520
	expected_width := 520
	testing.expect(t, width == expected_width,
		fmt.tprintf("Gap larger than children should produce width %d, got %d", expected_width, width))

	delete(parent.children)
}

// Test single pixel sizes throughout
@(test)
test_single_pixel_everything :: proc(t: ^testing.T) {
	parent := app.Box{
		config = {
			padding = {left = 1, top = 1, right = 1, bottom = 1},
			size = {{type = .Fit_Children, amount = 0}, {type = .Fit_Children, amount = 0}},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 1,
		},
		children = make([dynamic]^app.Box),
	}

	child1 := app.Box{
		width = 1,
		height = 1,
		config = {
			size = {{type = .Fixed, amount = 1}, {type = .Fixed, amount = 1}},
			margin = {left = 1, top = 1, right = 1, bottom = 1},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	child2 := app.Box{
		width = 1,
		height = 1,
		config = {
			size = {{type = .Fixed, amount = 1}, {type = .Fixed, amount = 1}},
			margin = {left = 1, top = 1, right = 1, bottom = 1},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child1, &child2)

	width := app.sizing_calc_fit_children_width(parent)
	height := app.sizing_calc_fit_children_height(parent)

	// Width = (1+1+1) + 1 (gap) + (1+1+1) + 1+1 (padding) = 3 + 1 + 3 + 2 = 9
	// Height = max((1+1+1), (1+1+1)) + 1+1 (padding) = 3 + 2 = 5
	testing.expect(t, width == 9,
		fmt.tprintf("Single pixel width should be 9, got %d", width))
	testing.expect(t, height == 5,
		fmt.tprintf("Single pixel height should be 5, got %d", height))

	delete(parent.children)
}

// Test extreme aspect ratio (very wide)
@(test)
test_extreme_aspect_ratio_wide :: proc(t: ^testing.T) {
	parent := app.Box{
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fit_Children, amount = 0}, {type = .Fit_Children, amount = 0}},
		},
		children = make([dynamic]^app.Box),
	}

	// 10000x1 child (extreme aspect ratio)
	child := app.Box{
		width = 10000,
		height = 1,
		config = {
			size = {{type = .Fixed, amount = 10000}, {type = .Fixed, amount = 1}},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child)

	width := app.sizing_calc_fit_children_width(parent)
	height := app.sizing_calc_fit_children_height(parent)

	testing.expect(t, width == 10000,
		fmt.tprintf("Extreme wide aspect should be 10000 wide, got %d", width))
	testing.expect(t, height == 1,
		fmt.tprintf("Extreme wide aspect should be 1 tall, got %d", height))

	delete(parent.children)
}

// Test extreme aspect ratio (very tall)
@(test)
test_extreme_aspect_ratio_tall :: proc(t: ^testing.T) {
	parent := app.Box{
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fit_Children, amount = 0}, {type = .Fit_Children, amount = 0}},
		},
		child_layout = {
			direction = .Vertical,
		},
		children = make([dynamic]^app.Box),
	}

	// 1x10000 child (extreme aspect ratio)
	child := app.Box{
		width = 1,
		height = 10000,
		config = {
			size = {{type = .Fixed, amount = 1}, {type = .Fixed, amount = 10000}},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child)

	width := app.sizing_calc_fit_children_width(parent)
	height := app.sizing_calc_fit_children_height(parent)

	testing.expect(t, width == 1,
		fmt.tprintf("Extreme tall aspect should be 1 wide, got %d", width))
	testing.expect(t, height == 10000,
		fmt.tprintf("Extreme tall aspect should be 10000 tall, got %d", height))

	delete(parent.children)
}

// Test alternating huge and tiny children
@(test)
test_alternating_huge_tiny_children :: proc(t: ^testing.T) {
	parent := app.Box{
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fit_Children, amount = 0}, {type = .Fit_Children, amount = 0}},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 0,
		},
		children = make([dynamic]^app.Box),
	}

	children: [10]app.Box
	for i in 0..<10 {
		size := i % 2 == 0 ? 1000 : 1 // Alternate between huge and tiny
		children[i] = app.Box{
			width = size,
			height = size,
			config = {
				size = {{type = .Fixed, amount = f32(size)}, {type = .Fixed, amount = f32(size)}},
				floating_type = .Not_Floating,
			},
			parent = &parent,
		}
		append(&parent.children, &children[i])
	}

	width := app.sizing_calc_fit_children_width(parent)
	height := app.sizing_calc_fit_children_height(parent)

	// Width = 5 * 1000 + 5 * 1 = 5005
	// Height = max(1000, 1) = 1000
	expected_width := 5005
	expected_height := 1000

	testing.expect(t, width == expected_width,
		fmt.tprintf("Alternating huge/tiny width should be %d, got %d", expected_width, width))
	testing.expect(t, height == expected_height,
		fmt.tprintf("Alternating huge/tiny height should be %d, got %d", expected_height, height))

	delete(parent.children)
}

// Test rounding errors with many percent children
@(test)
test_rounding_errors_many_percent :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 1000,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fixed, amount = 1000}, {type = .Fixed, amount = 100}},
		},
		children = make([dynamic]^app.Box),
	}

	// 7 children each with 1/7 = 14.285714%
	children: [7]app.Box
	for i in 0..<7 {
		children[i] = app.Box{
			config = {
				size = {{type = .Percent, amount = 1.0/7.0}, {type = .Fixed, amount = 100}},
				floating_type = .Not_Floating,
			},
			parent = &parent,
		}
		append(&parent.children, &children[i])
	}

	app.sizing_calc_percent_width(&parent)

	// Each should be ~142.857 pixels, rounds to 142
	// Check that all are sized (even if not perfectly equal due to rounding)
	total_width := 0
	for i in 0..<7 {
		total_width += children[i].width
		testing.expect(t, children[i].width >= 142 && children[i].width <= 143,
			fmt.tprintf("Child %d should be 142-143 pixels, got %d", i, children[i].width))
	}

	delete(parent.children)
}

// Test grow with extremely limited space
@(test)
test_grow_with_limited_space :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 105, // Just barely enough for initial children
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fixed, amount = 105}, {type = .Fixed, amount = 100}},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 5,
		},
		children = make([dynamic]^app.Box),
	}

	child1 := app.Box{
		width = 50,
		config = {
			size = {{type = .Grow, amount = 1.0}, {type = .Fixed, amount = 100}},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	child2 := app.Box{
		width = 50,
		config = {
			size = {{type = .Grow, amount = 1.0}, {type = .Fixed, amount = 100}},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child1, &child2)

	// Available = 105 - 50 - 5 - 50 = 0
	// No space to grow
	available := parent.width - child1.width - parent.child_layout.gap_horizontal - child2.width

	testing.expect(t, available == 0,
		fmt.tprintf("Should have 0 available space for grow, got %d", available))

	delete(parent.children)
}

// Test nested with all different sizing modes at once
@(test)
test_nested_all_sizing_modes_chaos :: proc(t: ^testing.T) {
	root := app.Box{
		width = 2000,
		height = 1000,
		config = {
			padding = {left = 10, top = 10, right = 10, bottom = 10},
			size = {{type = .Fixed, amount = 2000}, {type = .Fixed, amount = 1000}},
		},
		child_layout = {
			direction = .Horizontal,
		},
		children = make([dynamic]^app.Box),
	}

	// Child 1: Percent
	child_percent := app.Box{
		config = {
			size = {{type = .Percent, amount = 0.3}, {type = .Fixed, amount = 100}},
			padding = {left = 5, top = 5, right = 5, bottom = 5},
			floating_type = .Not_Floating,
		},
		child_layout = {
			direction = .Vertical,
		},
		parent = &root,
		children = make([dynamic]^app.Box),
	}

	// Child 2: Fit_Children
	child_fit := app.Box{
		config = {
			size = {{type = .Fit_Children, amount = 0}, {type = .Fixed, amount = 100}},
			padding = {left = 3, top = 3, right = 3, bottom = 3},
			floating_type = .Not_Floating,
		},
		child_layout = {
			direction = .Horizontal,
		},
		parent = &root,
		children = make([dynamic]^app.Box),
	}

	// Child 3: Grow
	child_grow := app.Box{
		width = 100,
		config = {
			size = {{type = .Grow, amount = 1.0}, {type = .Fixed, amount = 100}},
			floating_type = .Not_Floating,
		},
		parent = &root,
	}

	// Grandchild in fit container
	grandchild_fixed := app.Box{
		width = 75,
		height = 50,
		config = {
			size = {{type = .Fixed, amount = 75}, {type = .Fixed, amount = 50}},
			margin = {left = 2, top = 2, right = 2, bottom = 2},
			floating_type = .Not_Floating,
		},
		parent = &child_fit,
	}

	append(&child_fit.children, &grandchild_fixed)
	append(&root.children, &child_percent, &child_fit, &child_grow)

	// Calculate percent first
	app.sizing_calc_percent_width(&root)

	// Percent child should be 30% of (2000 - 20 padding) = 594
	testing.expect(t, child_percent.width == 594,
		fmt.tprintf("Percent child should be 594, got %d", child_percent.width))

	// Fit child width
	child_fit.width = app.sizing_calc_fit_children_width(child_fit)
	// Should be 75 + 2 + 2 (margins) + 3 + 3 (padding) = 85
	testing.expect(t, child_fit.width == 85,
		fmt.tprintf("Fit child should be 85, got %d", child_fit.width))

	// Grow child gets remaining space
	// Available = 1980 (content) - 594 - 85 - 100 (initial) = 1201
	content_width := root.width - root.config.padding.left - root.config.padding.right
	available := content_width - child_percent.width - child_fit.width - child_grow.width
	expected_grow_final := child_grow.width + available

	testing.expect(t, expected_grow_final == 1301,
		fmt.tprintf("Grow child should grow to 1301, calculated %d", expected_grow_final))

	delete(root.children)
	delete(child_percent.children)
	delete(child_fit.children)
}

// Test overflow scenario - children larger than parent
@(test)
test_children_larger_than_parent_space :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 100, // Small parent
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fixed, amount = 100}, {type = .Fixed, amount = 100}},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 0,
		},
		children = make([dynamic]^app.Box),
	}

	// Three children, 50 pixels each = 150 total (exceeds parent)
	children: [3]app.Box
	for i in 0..<3 {
		children[i] = app.Box{
			width = 50,
			config = {
				size = {{type = .Fixed, amount = 50}, {type = .Fixed, amount = 50}},
				floating_type = .Not_Floating,
			},
			parent = &parent,
		}
		append(&parent.children, &children[i])
	}

	// Parent as fit_children would be 150, but it's fixed at 100
	// This creates an overflow situation
	fit_width := app.sizing_calc_fit_children_width(parent)

	testing.expect(t, fit_width == 150,
		fmt.tprintf("Fit calculation should be 150 (overflow), got %d", fit_width))
	testing.expect(t, parent.width == 100,
		fmt.tprintf("Fixed parent should remain 100, got %d", parent.width))

	delete(parent.children)
}

// Test zero percent (edge case)
@(test)
test_zero_percent :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 1000,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fixed, amount = 1000}, {type = .Fixed, amount = 100}},
		},
		children = make([dynamic]^app.Box),
	}

	child := app.Box{
		config = {
			size = {{type = .Percent, amount = 0.0}, {type = .Fixed, amount = 100}},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child)
	app.sizing_calc_percent_width(&parent)

	// 0% should be 0 pixels
	testing.expect(t, child.width == 0,
		fmt.tprintf("0%% should be 0 pixels, got %d", child.width))

	delete(parent.children)
}

// Test massive gap array (gap * 999 children)
// @(test)
// test_massive_gap_contribution :: proc(t: ^testing.T) {
// 	parent := app.Box{
// 		config = {
// 			padding = {left = 0, top = 0, right = 0, bottom = 0},
// 			size = {{type = .Fit_Children, amount = 0}, {type = .Fit_Children, amount = 0}},
// 		},
// 		child_layout = {
// 			direction = .Horizontal,
// 			gap_horizontal = 10,
// 		},
// 		children = make([dynamic]^app.Box),
// 	}

// 	// 50 children with 1 pixel each, gaps dominate the size
// 	children: [50]app.Box
// 	for i in 0..<50 {
// 		children[i] = app.Box{
// 			width = 1,
// 			height = 1,
// 			config = {
// 				size = {{type = .Fixed, amount = 1}, {type = .Fixed, amount = 1}},
// 				floating_type = .Not_Floating,
// 			},
// 			parent = &parent,
// 		}
// 		append(&parent.children, &children[i])
// 	}

// 	width := app.sizing_calc_fit_children_width(parent)

// 	// Width = 50 * 1 (children) + 49 * 10 (gaps) = 50 + 490 = 540
// 	expected_width := 540
// 	testing.expect(t, width == expected_width,
// 		fmt.tprintf("Gap-dominated width should be %d, got %d", expected_width, width))

// 	delete(parent.children)
// }
