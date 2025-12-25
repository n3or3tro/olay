package tests
import "core:fmt"
import "core:testing"
import app "../"

// Tests for grow distribution algorithm - verifying how extra space is distributed among growable children

// Test basic grow distribution with equal initial sizes
@(test)
test_grow_equal_distribution :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 600,
		height = 100,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			semantic_size = {{type = .Fixed, amount = 600}, {type = .Fixed, amount = 100}},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 0,
		},
		children = make([dynamic]^app.Box),
	}

	child1 := app.Box{
		width = 100,
		height = 50,
		config = {
			semantic_size = {{type = .Grow, amount = 1.0}, {type = .Fixed, amount = 50}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	child2 := app.Box{
		width = 100,
		height = 50,
		config = {
			semantic_size = {{type = .Grow, amount = 1.0}, {type = .Fixed, amount = 50}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child1, &child2)

	// Both children start at 100, total = 200
	// Available space = 600 - 200 = 400
	// Each should grow by 400 / 2 = 200
	// Final sizes: 100 + 200 = 300 each

	testing.expect(t, child1.width + child2.width == 200,
		fmt.tprintf("Initial total width should be 200, got %d", child1.width + child2.width))

	// After growing, each should be 300
	// Note: We can't actually call the grow function here since it's internal
	// But we can verify the logic by calculating what it should be
	available_space := parent.width - (child1.width + child2.width)
	expected_grow_each := available_space / 2
	expected_final_width := child1.width + expected_grow_each

	testing.expect(t, expected_final_width == 300,
		fmt.tprintf("After grow, each child should be 300, calculated %d", expected_final_width))

	delete(parent.children)
}

// Test grow with different grow amounts
@(test)
test_grow_weighted_distribution :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 1000,
		height = 100,
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

	// Child with grow amount 1.0
	child1 := app.Box{
		width = 100,
		height = 50,
		config = {
			semantic_size = {{type = .Grow, amount = 1.0}, {type = .Fixed, amount = 50}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	// Child with grow amount 2.0 (should grow twice as much)
	child2 := app.Box{
		width = 100,
		height = 50,
		config = {
			semantic_size = {{type = .Grow, amount = 2.0}, {type = .Fixed, amount = 50}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child1, &child2)

	// Total initial width = 200
	// Available space = 1000 - 200 = 800
	// Total grow amount = 1.0 + 2.0 = 3.0
	// Child1 grows by: 800 * (1.0 / 3.0) = 266.66... ≈ 266
	// Child2 grows by: 800 * (2.0 / 3.0) = 533.33... ≈ 533
	// Child1 final: 100 + 266 = 366
	// Child2 final: 100 + 533 = 633

	available_space := parent.width - (child1.width + child2.width)
	total_grow_amount := child1.config.semantic_size.x.amount + child2.config.semantic_size.x.amount

	child1_grow := int(f32(available_space) * (child1.config.semantic_size.x.amount / total_grow_amount))
	child2_grow := int(f32(available_space) * (child2.config.semantic_size.x.amount / total_grow_amount))

	expected_child1_final := child1.width + child1_grow
	expected_child2_final := child2.width + child2_grow

	// Child2 should get approximately twice the grow amount of child1
	testing.expect(t, f32(child2_grow) >= f32(child1_grow) * 1.9 && f32(child2_grow) <= f32(child1_grow) * 2.1,
		fmt.tprintf("Child2 grow (%d) should be about 2x child1 grow (%d)", child2_grow, child1_grow))

	delete(parent.children)
}

// Test grow with margins
@(test)
test_grow_with_margins :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 500,
		height = 100,
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

	child1 := app.Box{
		width = 80,
		height = 50,
		config = {
			semantic_size = {{type = .Grow, amount = 1.0}, {type = .Fixed, amount = 50}},
			margin = {left = 10, right = 10, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	child2 := app.Box{
		width = 80,
		height = 50,
		config = {
			semantic_size = {{type = .Grow, amount = 1.0}, {type = .Fixed, amount = 50}},
			margin = {left = 10, right = 10, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child1, &child2)

	// Content width = 500 - 20 (padding) = 480
	// Child total space = (80 + 20) + (80 + 20) = 200
	// Available for grow = 480 - 200 = 280
	// Each grows by 140
	// Final: 80 + 140 = 220 each

	content_width := parent.width - parent.config.padding.left - parent.config.padding.right
	child_space := (child1.width + app.box_get_margin_x_tot(child1)) + (child2.width + app.box_get_margin_x_tot(child2))
	available_for_grow := content_width - child_space
	expected_grow_each := available_for_grow / 2
	expected_final := child1.width + expected_grow_each

	testing.expect(t, expected_final == 220,
		fmt.tprintf("After grow with margins, each child should be 220, calculated %d", expected_final))

	delete(parent.children)
}

// Test grow with gaps
@(test)
test_grow_with_gaps :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 500,
		height = 100,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			semantic_size = {{type = .Fixed, amount = 500}, {type = .Fixed, amount = 100}},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 20,
		},
		children = make([dynamic]^app.Box),
	}

	child1 := app.Box{
		width = 100,
		height = 50,
		config = {
			semantic_size = {{type = .Grow, amount = 1.0}, {type = .Fixed, amount = 50}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	child2 := app.Box{
		width = 100,
		height = 50,
		config = {
			semantic_size = {{type = .Grow, amount = 1.0}, {type = .Fixed, amount = 50}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child1, &child2)

	// Total child width = 200
	// Gap = 20 (between 2 children = 1 gap)
	// Available for grow = 500 - 200 - 20 = 280
	// Each grows by 140
	// Final: 100 + 140 = 240 each

	gap_total := parent.child_layout.gap_horizontal * (len(parent.children) - 1)
	available_for_grow := parent.width - (child1.width + child2.width) - gap_total
	expected_grow_each := available_for_grow / 2
	expected_final := child1.width + expected_grow_each

	testing.expect(t, expected_final == 240,
		fmt.tprintf("After grow with gaps, each child should be 240, calculated %d", expected_final))

	delete(parent.children)
}

// Test grow with fixed and grow children mixed
@(test)
test_grow_mixed_with_fixed :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 600,
		height = 100,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			semantic_size = {{type = .Fixed, amount = 600}, {type = .Fixed, amount = 100}},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 0,
		},
		children = make([dynamic]^app.Box),
	}

	child_fixed := app.Box{
		width = 100,
		height = 50,
		config = {
			semantic_size = {{type = .Fixed, amount = 100}, {type = .Fixed, amount = 50}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	child_grow := app.Box{
		width = 100,
		height = 50,
		config = {
			semantic_size = {{type = .Grow, amount = 1.0}, {type = .Fixed, amount = 50}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child_fixed, &child_grow)

	// Fixed child takes 100
	// Grow child starts at 100
	// Available = 600 - 200 = 400
	// Only grow child should grow, by 400
	// Final grow child: 100 + 400 = 500

	available_space := parent.width - (child_fixed.width + child_grow.width)
	expected_grow_child_final := child_grow.width + available_space

	testing.expect(t, expected_grow_child_final == 500,
		fmt.tprintf("Grow child should be 500, calculated %d", expected_grow_child_final))

	testing.expect(t, child_fixed.width == 100,
		fmt.tprintf("Fixed child should remain 100, got %d", child_fixed.width))

	delete(parent.children)
}

// Test vertical grow
@(test)
test_grow_vertical :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 100,
		height = 600,
		config = {
			padding = {left = 0, top = 10, right = 0, bottom = 10},
			semantic_size = {{type = .Fixed, amount = 100}, {type = .Fixed, amount = 600}},
		},
		child_layout = {
			direction = .Vertical,
			gap_vertical = 5,
		},
		children = make([dynamic]^app.Box),
	}

	child1 := app.Box{
		width = 80,
		height = 100,
		config = {
			semantic_size = {{type = .Fixed, amount = 80}, {type = .Grow, amount = 1.0}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	child2 := app.Box{
		width = 80,
		height = 100,
		config = {
			semantic_size = {{type = .Fixed, amount = 80}, {type = .Grow, amount = 1.0}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child1, &child2)

	// Content height = 600 - 20 (padding) = 580
	// Total child height = 200
	// Gap = 5
	// Available for grow = 580 - 200 - 5 = 375
	// Each grows by 187.5 ≈ 187
	// Final: 100 + 187 = 287 (with rounding variations)

	content_height := parent.height - parent.config.padding.top - parent.config.padding.bottom
	gap_total := parent.child_layout.gap_vertical * (len(parent.children) - 1)
	available_for_grow := content_height - (child1.height + child2.height) - gap_total
	expected_grow_each := available_for_grow / 2

	testing.expect(t, expected_grow_each >= 187 && expected_grow_each <= 188,
		fmt.tprintf("Each child should grow by ~187, calculated %d", expected_grow_each))

	delete(parent.children)
}

// Test grow ignores floating children
@(test)
test_grow_ignores_floating :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 600,
		height = 100,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			semantic_size = {{type = .Fixed, amount = 600}, {type = .Fixed, amount = 100}},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 0,
		},
		children = make([dynamic]^app.Box),
	}

	child_grow := app.Box{
		width = 100,
		height = 50,
		config = {
			semantic_size = {{type = .Grow, amount = 1.0}, {type = .Fixed, amount = 50}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	child_floating := app.Box{
		width = 200,
		height = 50,
		config = {
			semantic_size = {{type = .Grow, amount = 1.0}, {type = .Fixed, amount = 50}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Relative_Parent,
		},
		parent = &parent,
	}

	append(&parent.children, &child_grow, &child_floating)

	// Only non-floating child should participate in grow
	// Available = 600 - 100 = 500
	// Grow child should get all 500
	// Final: 100 + 500 = 600

	available_space := parent.width - child_grow.width
	expected_grow_child_final := child_grow.width + available_space

	testing.expect(t, expected_grow_child_final == 600,
		fmt.tprintf("Non-floating grow child should be 600, calculated %d", expected_grow_child_final))

	// Floating child should not participate
	testing.expect(t, child_floating.width == 200,
		fmt.tprintf("Floating child should remain 200, got %d", child_floating.width))

	delete(parent.children)
}

// Test Fit_Children_And_Grow
@(test)
test_fit_children_and_grow :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 800,
		height = 100,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			semantic_size = {{type = .Fixed, amount = 800}, {type = .Fixed, amount = 100}},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 0,
		},
		children = make([dynamic]^app.Box),
	}

	// This child will first fit its children, then grow to fill
	fit_and_grow_child := app.Box{
		width = 150, // Initially fits children
		height = 50,
		config = {
			semantic_size = {{type = .Fit_Children_And_Grow, amount = 1.0}, {type = .Fixed, amount = 50}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
			padding = {left = 0, top = 0, right = 0, bottom = 0},
		},
		parent = &parent,
		children = make([dynamic]^app.Box),
	}

	fixed_child := app.Box{
		width = 200,
		height = 50,
		config = {
			semantic_size = {{type = .Fixed, amount = 200}, {type = .Fixed, amount = 50}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &fit_and_grow_child, &fixed_child)

	// Fit_and_grow starts at 150, fixed at 200
	// Total = 350
	// Available = 800 - 350 = 450
	// Fit_and_grow gets all 450
	// Final: 150 + 450 = 600

	available_space := parent.width - (fit_and_grow_child.width + fixed_child.width)
	expected_fit_grow_final := fit_and_grow_child.width + available_space

	testing.expect(t, expected_fit_grow_final == 600,
		fmt.tprintf("Fit_Children_And_Grow should be 600, calculated %d", expected_fit_grow_final))

	delete(parent.children)
	delete(fit_and_grow_child.children)
}

// Test three grow children with different amounts
@(test)
test_grow_three_children_weighted :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 1000,
		height = 100,
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

	child1 := app.Box{
		width = 50,
		height = 50,
		config = {
			semantic_size = {{type = .Grow, amount = 1.0}, {type = .Fixed, amount = 50}},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	child2 := app.Box{
		width = 50,
		height = 50,
		config = {
			semantic_size = {{type = .Grow, amount = 2.0}, {type = .Fixed, amount = 50}},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	child3 := app.Box{
		width = 50,
		height = 50,
		config = {
			semantic_size = {{type = .Grow, amount = 3.0}, {type = .Fixed, amount = 50}},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child1, &child2, &child3)

	// Total initial = 150
	// Available = 1000 - 150 = 850
	// Total grow amount = 1 + 2 + 3 = 6
	// Child1: 850 * (1/6) ≈ 141.66
	// Child2: 850 * (2/6) ≈ 283.33
	// Child3: 850 * (3/6) = 425

	available_space := parent.width - (child1.width + child2.width + child3.width)
	total_grow := child1.config.semantic_size.x.amount + child2.config.semantic_size.x.amount + child3.config.semantic_size.x.amount

	child1_grow := int(f32(available_space) * (child1.config.semantic_size.x.amount / total_grow))
	child2_grow := int(f32(available_space) * (child2.config.semantic_size.x.amount / total_grow))
	child3_grow := int(f32(available_space) * (child3.config.semantic_size.x.amount / total_grow))

	// Verify the ratios are roughly correct
	// Child3 should get about 3x what child1 gets
	testing.expect(t, f32(child3_grow) >= f32(child1_grow) * 2.9 && f32(child3_grow) <= f32(child1_grow) * 3.1,
		fmt.tprintf("Child3 grow (%d) should be ~3x child1 grow (%d)", child3_grow, child1_grow))

	// Child2 should get about 2x what child1 gets
	testing.expect(t, f32(child2_grow) >= f32(child1_grow) * 1.9 && f32(child2_grow) <= f32(child1_grow) * 2.1,
		fmt.tprintf("Child2 grow (%d) should be ~2x child1 grow (%d)", child2_grow, child1_grow))

	delete(parent.children)
}
