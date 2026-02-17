package tests
import "core:fmt"
import "core:testing"
import app "../"

// Tests to diagnose why Fit_Text_And_Grow doesn't fill cross-axis height in horizontal layout

// Test that Fit_Text_And_Grow should grow on BOTH axes
@(test)
test_fit_text_and_grow_both_axes :: proc(t: ^testing.T) {
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
			alignment_vertical = .Center,
		},
		children = make([dynamic]^app.Box),
	}

	// Single button with Fit_Text_And_Grow on both axes
	button := app.Box{
		width = 35,  // Initial fit-text width
		height = 20, // Initial fit-text height
		config = {
			size = {{type = .Fit_Text_And_Grow, amount = 1}, {type = .Fit_Text_And_Grow, amount = 1}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			padding = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &button)

	// Simulate the grow width pass (horizontal main axis)
	app.sizing_grow_growable_width(&parent)

	// After horizontal grow: button should fill parent width
	testing.expect(t, button.width == 200,
		fmt.tprintf("Button width should grow to fill parent (200), got %d", button.width))

	// Simulate the grow height pass (horizontal cross axis)
	app.sizing_grow_growable_height(&parent)

	// After vertical grow: button should fill parent height
	testing.expect(t, button.height == 60,
		fmt.tprintf("Button height should grow to fill parent (60), got %d", button.height))

	delete(parent.children)
}

// Test cross-axis growth in horizontal layout
@(test)
test_cross_axis_height_growth_horizontal_layout :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 200,
		height = 60,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fixed, amount = 200}, {type = .Fixed, amount = 60}},
		},
		child_layout = {
			direction = .Horizontal, // Main axis is X, cross axis is Y
			gap_horizontal = 0,
		},
		children = make([dynamic]^app.Box),
	}

	button := app.Box{
		width = 50,
		height = 20, // Starts at fit-text height
		config = {
			size = {{type = .Fit_Text_And_Grow, amount = 1}, {type = .Fit_Text_And_Grow, amount = 1}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			padding = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &button)

	initial_height := button.height

	// Call the height grow function
	app.sizing_grow_growable_height(&parent)

	// In horizontal layout, sizing_grow_growable_height should handle cross-axis (Y) growth
	// The button should grow from 20 to 60
	testing.expect(t, button.height > initial_height,
		fmt.tprintf("Button height should have grown from %d, but is still %d", initial_height, button.height))

	testing.expect(t, button.height == 60,
		fmt.tprintf("Button height should be 60 (parent height), got %d", button.height))

	delete(parent.children)
}

// Test that the grow algorithm correctly identifies cross-axis direction
@(test)
test_horizontal_layout_cross_axis_identification :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 200,
		height = 60,
		config = {
			padding = {left = 0, top = 0, right = 0, bottom = 0},
			size = {{type = .Fixed, amount = 200}, {type = .Fixed, amount = 60}},
		},
		child_layout = {
			direction = .Horizontal, // This means X is main axis, Y is cross axis
			gap_horizontal = 0,
		},
		children = make([dynamic]^app.Box),
	}

	// Verify the layout direction
	testing.expect(t, parent.child_layout.direction == .Horizontal,
		fmt.tprintf("Parent layout should be Horizontal"))

	// In horizontal layout:
	// - sizing_grow_growable_width handles MAIN axis (X) - grows width
	// - sizing_grow_growable_height handles CROSS axis (Y) - grows height

	// The cross-axis case in sizing_grow_growable_height is at line 1005-1017 in core.odin
	// It should check for case .Horizontal and grow the HEIGHT
}

// Test with padding to see if that's affecting cross-axis growth
@(test)
test_cross_axis_growth_with_padding :: proc(t: ^testing.T) {
	parent := app.Box{
		width = 200,
		height = 60,
		config = {
			padding = {left = 10, top = 5, right = 10, bottom = 5}, // 10px Y padding total
			size = {{type = .Fixed, amount = 200}, {type = .Fixed, amount = 60}},
		},
		child_layout = {
			direction = .Horizontal,
			gap_horizontal = 0,
		},
		children = make([dynamic]^app.Box),
	}

	button := app.Box{
		width = 50,
		height = 20,
		config = {
			size = {{type = .Fit_Text_And_Grow, amount = 1}, {type = .Fit_Text_And_Grow, amount = 1}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			padding = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &button)

	app.sizing_grow_growable_height(&parent)

	// Available height = 60 - 10 (padding) = 50
	// Button should grow to 50
	expected_height := parent.height - (parent.config.padding.top + parent.config.padding.bottom)

	testing.expect(t, button.height == expected_height,
		fmt.tprintf("Button height should be %d (accounting for parent padding), got %d", expected_height, button.height))

	delete(parent.children)
}

// Test with button padding to see if that affects calculation
@(test)
test_cross_axis_growth_button_with_padding :: proc(t: ^testing.T) {
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
		},
		children = make([dynamic]^app.Box),
	}

	button := app.Box{
		width = 50,
		height = 20, // This is the HEIGHT OF THE BOX, not including padding
		config = {
			size = {{type = .Fit_Text_And_Grow, amount = 1}, {type = .Fit_Text_And_Grow, amount = 1}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			padding = {left = 10, right = 10, top = 5, bottom = 5}, // Button has internal padding
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &button)

	app.sizing_grow_growable_height(&parent)

	// The button's HEIGHT should grow to 60 (box height, not including button's padding)
	// The total space the button takes = height + margin (not padding)
	testing.expect(t, button.height == 60,
		fmt.tprintf("Button box height should be 60, got %d (padding is internal to the box)", button.height))

	delete(parent.children)
}

// Test the exact scenario from the user's code
@(test)
test_exact_user_scenario :: proc(t: ^testing.T) {
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

	button := app.Box{
		width = 35,
		height = 20,
		config = {
			size = {{type = .Fit_Text_And_Grow, amount = 1}, {type = .Fit_Text_And_Grow, amount = 1}},
			margin = {left = 0, right = 0, top = 0, bottom = 0},
			padding = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &container,
	}

	append(&container.children, &button)

	// Run the layout passes in order (like ui.odin does)
	app.sizing_calc_percent_width(&container)
	app.sizing_calc_percent_height(&container)
	app.sizing_grow_growable_height(&container)  // Height first
	app.sizing_grow_growable_width(&container)   // Then width

	// After layout, button should fill container
	testing.expect(t, button.width == 200,
		fmt.tprintf("Button width should be 200, got %d", button.width))

	testing.expect(t, button.height == 60,
		fmt.tprintf("Button height should be 60, got %d", button.height))

	delete(container.children)
}

// Test with margins to see if they affect cross-axis growth
@(test)
test_cross_axis_growth_with_margins :: proc(t: ^testing.T) {
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
		},
		children = make([dynamic]^app.Box),
	}

	button := app.Box{
		width = 50,
		height = 20,
		config = {
			size = {{type = .Fit_Text_And_Grow, amount = 1}, {type = .Fit_Text_And_Grow, amount = 1}},
			margin = {left = 0, right = 0, top = 5, bottom = 5}, // 10px total Y margin
			padding = {left = 0, right = 0, top = 0, bottom = 0},
			floating_type = .Not_Floating,
		},
		parent = &parent,
	}

	append(&parent.children, &button)

	app.sizing_grow_growable_height(&parent)

	// Available height = 60
	// Button total space with margin = height + 10
	// So button.height should be 60 - 10 = 50
	expected_height := parent.height - (button.config.margin.top + button.config.margin.bottom)

	testing.expect(t, button.height == expected_height,
		fmt.tprintf("Button height should account for margins (%d), got %d", expected_height, button.height))

	delete(parent.children)
}
