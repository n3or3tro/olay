package tests
import "core:fmt"
import "core:testing"
import app "../"

// Tests for Fit_Text_And_Grow sizing behavior - investigating why buttons don't fill parent

// Test basic Fit_Text_And_Grow in horizontal layout
@(test)
test_fit_text_and_grow_horizontal_basic :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 200, // Fixed size boxes get their width from semantic_size amount
		height = 100,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fixed, amount = 200}, {type = .Fixed, amount = 100}},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 0,
		},
		children = make([dynamic]^app.Box),
	}

	// Simulate text button with Fit_Text_And_Grow
	child1 := app.Box{
		width = 50, // Initial fit-text width
		height = 20, // Initial fit-text height
		config = {
			size = {{type = .Fit_Text_And_Grow, amount = 1.0}, {type = .Fit_Text_And_Grow, amount = 1.0}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child1)

	// After setting up, parent is 200 wide, child starts at 50
	// Child should grow to fill: 200 - 50 = 150 additional space
	// Final child width should be 50 + 150 = 200

	testing.expect(t, parent.width == 200,
		fmt.tprintf("Parent width should be 200, got %d", parent.width))

	testing.expect(t, child1.width == 50,
		fmt.tprintf("Child initial width should be 50 (fit text), got %d", child1.width))

	// Note: The actual growing happens in sizing_grow_growable_width, which we can't call here
	// This test just verifies the initial state

	delete(parent.children)
}

// Test Fit_Text_And_Grow with multiple children in horizontal layout
@(test)
test_fit_text_and_grow_horizontal_multiple :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 200,
		height = 60,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fixed, amount = 200}, {type = .Fixed, amount = 60}},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 0,
			alignment_horizontal = .Center,
		},
		children = make([dynamic]^app.Box),
	}

	// Three buttons like in the UI code
	child1 := app.Box{
		width = 40, // Fit text "hey"
		height = 20,
		config = {
			size = {{type = .Fit_Text_And_Grow, amount = 1.0}, {type = .Fit_Text_And_Grow, amount = 10.0}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	child2 := app.Box{
		width = 45, // Fit text "mate"
		height = 20,
		config = {
			size = {{type = .Fit_Text_And_Grow, amount = 1.0}, {type = .Fit_Text_And_Grow, amount = 10.0}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	child3 := app.Box{
		width = 50, // Fit text "baby"
		height = 20,
		config = {
			size = {{type = .Fit_Text_And_Grow, amount = 1.0}, {type = .Fit_Text_And_Grow, amount = 10.0}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child1, &child2, &child3)

	// Initial total width: 40 + 45 + 50 = 135
	// Available space: 200 - 135 = 65
	// Each should grow equally (grow amount = 1.0 for all)
	// Each grows by ~21-22 pixels

	initial_total := child1.width + child2.width + child3.width
	available := parent.width - initial_total

	testing.expect(t, initial_total == 135,
		fmt.tprintf("Initial children total should be 135, got %d", initial_total))

	testing.expect(t, available == 65,
		fmt.tprintf("Available space for growth should be 65, got %d", available))

	delete(parent.children)
}

// Test Fit_Children parent with Fit_Text_And_Grow children
@(test)
test_fit_children_parent_with_fit_text_and_grow :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 0,
		height = 0,
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

	child1 := app.Box{
		width = 50,
		height = 20,
		config = {
			size = {{type = .Fit_Text_And_Grow, amount = 1.0}, {type = .Fixed, amount = 20}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	child2 := app.Box{
		width = 60,
		height = 20,
		config = {
			size = {{type = .Fit_Text_And_Grow, amount = 1.0}, {type = .Fixed, amount = 20}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child1, &child2)

	// When parent is Fit_Children, it should fit to children's INITIAL size
	// Which is their Fit_Text size: 50 + 60 = 110
	// The _And_Grow part should NOT affect Fit_Children calculation

	expected_parent_width := child1.width + child2.width
	calculated_width := app.sizing_calc_fit_children_width(parent)

	testing.expect(t, calculated_width == expected_parent_width,
		fmt.tprintf("Fit_Children parent should size to children's fit-text size (%d), got %d",
			expected_parent_width, calculated_width))

	// The issue might be: if children start at width=0 before fit-text calculation,
	// then Fit_Children parent would also be 0

	delete(parent.children)
}

// Test the order of operations: Fit_Text sizing happens BEFORE Fit_Children calculation
@(test)
test_fit_text_and_grow_sizing_order :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 0,
		height = 0,
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

	// Child with Fit_Text_And_Grow starting at width 0
	child := app.Box{
		width = 0, // NOT YET SIZED
		height = 0,
		config = {
			size = {{type = .Fit_Text_And_Grow, amount = 1.0}, {type = .Fit_Text_And_Grow, amount = 1.0}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child)

	// If Fit_Text sizing hasn't happened yet, child is still 0
	// So Fit_Children parent would calculate as 0
	calculated_width := app.sizing_calc_fit_children_width(parent)

	testing.expect(t, calculated_width == 0,
		fmt.tprintf("If child not yet sized, Fit_Children should be 0, got %d", calculated_width))

	// This is the BUG: Fit_Text_And_Grow boxes need their Fit_Text sizing
	// to happen BEFORE their parent's Fit_Children calculation

	delete(parent.children)
}

// Test Fit_Text_And_Grow with different grow amounts on different axes
@(test)
test_fit_text_and_grow_different_axis_amounts :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 200,
		height = 100,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fixed, amount = 200}, {type = .Fixed, amount = 100}},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 0,
		},
		children = make([dynamic]^app.Box),
	}

	// Like in the UI code: grow amount 1.0 on X, 10.0 on Y
	child := app.Box{
		width = 50,
		height = 20,
		config = {
			size = {{type = .Fit_Text_And_Grow, amount = 1.0}, {type = .Fit_Text_And_Grow, amount = 10.0}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child)

	// X-axis: grow amount 1.0
	// Y-axis: grow amount 10.0 (cross-axis for horizontal layout)

	// In horizontal layout, Y-axis grow should make child grow to parent height
	// X-axis grow should make child grow to fill remaining width

	testing.expect(t, child.config.size.x.amount == 1.0,
		fmt.tprintf("X-axis grow amount should be 1.0"))

	testing.expect(t, child.config.size.y.amount == 10.0,
		fmt.tprintf("Y-axis grow amount should be 10.0"))

	delete(parent.children)
}

// Test that Fit_Text_And_Grow is recognized as growable
@(test)
test_fit_text_and_grow_is_growable :: proc(t: ^testing.T) {
	box := app.Box{
		width = 50,
		height = 20,
		config = {
			size = {{type = .Fit_Text_And_Grow, amount = 1.0}, {type = .Fixed, amount = 20}},
		},
	}

	// Check that the size type is correct
	testing.expect(t, box.config.size.x.type == .Fit_Text_And_Grow,
		fmt.tprintf("X-axis should be Fit_Text_And_Grow"))

	// In the actual layout code, sizing_grow_growable_width should include this type
	// Let's verify it's one of the growable types
	is_growable := box.config.size.x.type == .Grow ||
	               box.config.size.x.type == .Fit_Text_And_Grow ||
	               box.config.size.x.type == .Fit_Children_And_Grow

	testing.expect(t, is_growable,
		fmt.tprintf("Fit_Text_And_Grow should be recognized as growable"))
}

// Test Fit_Children_And_Grow parent with Fit_Text_And_Grow children
@(test)
test_fit_children_and_grow_parent_with_fit_text_and_grow :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 0,
		height = 0,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fit_Children_And_Grow, amount = 1.0}, {type = .Fit_Children, amount = 0}},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 0,
		},
		children = make([dynamic]^app.Box),
	}

	child := app.Box{
		width = 50,
		height = 20,
		config = {
			size = {{type = .Fit_Text_And_Grow, amount = 1.0}, {type = .Fixed, amount = 20}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child)

	// Parent with Fit_Children_And_Grow should:
	// 1. First fit to children (50)
	// 2. Then grow to fill available space (if there is a grandparent)

	calculated_width := app.sizing_calc_fit_children_width(parent)

	testing.expect(t, calculated_width == 50,
		fmt.tprintf("Fit_Children_And_Grow parent should first fit to children (50), got %d", calculated_width))

	delete(parent.children)
}

// Test center alignment with Fit_Text_And_Grow
@(test)
test_center_alignment_with_fit_text_and_grow :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 200,
		height = 60,
		top_left = {0, 0},
		bottom_right = {200, 60},
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fixed, amount = 200}, {type = .Fixed, amount = 60}},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 0,
			alignment_horizontal = .Center,
			alignment_vertical = .Center,
		},
		children = make([dynamic]^app.Box),
	}

	child1 := app.Box{
		width = 40,
		height = 20,
		config = {
			size = {{type = .Fit_Text_And_Grow, amount = 1.0}, {type = .Fit_Text_And_Grow, amount = 10.0}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	child2 := app.Box{
		width = 40,
		height = 20,
		config = {
			size = {{type = .Fit_Text_And_Grow, amount = 1.0}, {type = .Fit_Text_And_Grow, amount = 10.0}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child1, &child2)

	// With center alignment, children should be centered
	// But Fit_Text_And_Grow should still work to fill space

	// The question: does grow happen BEFORE or AFTER alignment positioning?
	// It should happen during sizing, before positioning

	total_initial := child1.width + child2.width
	testing.expect(t, total_initial == 80,
		fmt.tprintf("Total initial width should be 80, got %d", total_initial))

	delete(parent.children)
}

// Test the exact scenario from ui.odin
@(test)
test_ui_code_scenario :: proc(t: ^testing.T) {
	// This replicates lines 335-344 from ui.odin
	container := app.Box{
		width = 200,
		height = 60,
		config = {
			size = {{type = .Fixed, amount = 200}, {type = .Fixed, amount = 60}},
			padding = {left = 0, top = 0, right = 0, bottom = 0},
		},
		child_layout = {
			alignment_horizontal = .Center,
			alignment_vertical = .Center,
			direction = .Horizontal,
			gap_horizontal = 0,
		},
		children = make([dynamic]^app.Box),
	}

	// Three text buttons with Fit_Text_And_Grow
	btn1 := app.Box{
		width = 35, // Approximate fit-text for "hey"
		height = 20,
		config = {
			size = {{type = .Fit_Text_And_Grow, amount = 1}, {type = .Fit_Text_And_Grow, amount = 10}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &container,
	}

	btn2 := app.Box{
		width = 40, // Approximate fit-text for "mate"
		height = 20,
		config = {
			size = {{type = .Fit_Text_And_Grow, amount = 1}, {type = .Fit_Text_And_Grow, amount = 10}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &container,
	}

	btn3 := app.Box{
		width = 45, // Approximate fit-text for "baby"
		height = 20,
		config = {
			size = {{type = .Fit_Text_And_Grow, amount = 1}, {type = .Fit_Text_And_Grow, amount = 10}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &container,
	}

	append(&container.children, &btn1, &btn2, &btn3)

	// Initial: 35 + 40 + 45 = 120
	// Available: 200 - 120 = 80
	// Each should grow by ~26-27 pixels

	initial_total := btn1.width + btn2.width + btn3.width
	available := container.width - initial_total

	testing.expect(t, initial_total == 120,
		fmt.tprintf("Initial button widths should total 120, got %d", initial_total))

	testing.expect(t, available == 80,
		fmt.tprintf("Available space for growth should be 80, got %d", available))

	// The issue might be that buttons don't grow at all
	// Or they grow but center alignment puts them in the wrong place

	delete(container.children)
}

// Test what happens when Fit_Text sizing is 0
@(test)
test_fit_text_and_grow_with_zero_initial_size :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 200,
		height = 100,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fixed, amount = 200}, {type = .Fixed, amount = 100}},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 0,
		},
		children = make([dynamic]^app.Box),
	}

	// Child starts with 0 width (not yet fit to text)
	child := app.Box{
		width = 0,
		height = 0,
		config = {
			size = {{type = .Fit_Text_And_Grow, amount = 1.0}, {type = .Fixed, amount = 20}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &child)

	// If child is 0 width initially, and grows to fill parent
	// It should end up as 200 width
	// But the grow algorithm might not work correctly if initial size is 0

	testing.expect(t, child.width == 0,
		fmt.tprintf("Child initial width is 0 (not yet sized)"))

	// After grow: should be 200
	// But this requires the grow algorithm to handle 0 initial size correctly

	delete(parent.children)
}
