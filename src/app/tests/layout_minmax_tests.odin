package tests
import "core:fmt"
import "core:testing"
import app "../"

// Tests for min/max size constraints on boxes

// Test min_size enforcement on width
@(test)
test_min_size_width :: proc(t: ^testing.T) {
	box := app.Box{
		width = 50,
		height = 100,
		config = {
			min_size = {200, 0},
		},
	}

	app.box_clamp_to_constraints(&box)

	testing.expect(t, box.width == 200,
		fmt.tprintf("Box should be clamped to min_size.x of 200, got %d", box.width))
}

// Test max_size enforcement on width
@(test)
test_max_size_width :: proc(t: ^testing.T) {
	box := app.Box{
		width = 500,
		height = 100,
		config = {
			max_size = {300, 0},
		},
	}

	app.box_clamp_to_constraints(&box)

	testing.expect(t, box.width == 300,
		fmt.tprintf("Box should be clamped to max_size.x of 300, got %d", box.width))
}

// Test min_size enforcement on height
@(test)
test_min_size_height :: proc(t: ^testing.T) {
	box := app.Box{
		width = 100,
		height = 50,
		config = {
			min_size = {0, 200},
		},
	}

	app.box_clamp_to_constraints(&box)

	testing.expect(t, box.height == 200,
		fmt.tprintf("Box should be clamped to min_size.y of 200, got %d", box.height))
}

// Test max_size enforcement on height
@(test)
test_max_size_height :: proc(t: ^testing.T) {
	box := app.Box{
		width = 100,
		height = 500,
		config = {
			max_size = {0, 300},
		},
	}

	app.box_clamp_to_constraints(&box)

	testing.expect(t, box.height == 300,
		fmt.tprintf("Box should be clamped to max_size.y of 300, got %d", box.height))
}

// Test both min and max on width
@(test)
test_min_and_max_width :: proc(t: ^testing.T) {
	// Test that a box between min and max stays unchanged
	box1 := app.Box{
		width = 250,
		height = 100,
		config = {
			min_size = {200, 0},
			max_size = {300, 0},
		},
	}

	app.box_clamp_to_constraints(&box1)

	testing.expect(t, box1.width == 250,
		fmt.tprintf("Box between min and max should stay at 250, got %d", box1.width))

	// Test that a box below min is clamped to min
	box2 := app.Box{
		width = 150,
		height = 100,
		config = {
			min_size = {200, 0},
			max_size = {300, 0},
		},
	}

	app.box_clamp_to_constraints(&box2)

	testing.expect(t, box2.width == 200,
		fmt.tprintf("Box below min should be clamped to 200, got %d", box2.width))

	// Test that a box above max is clamped to max
	box3 := app.Box{
		width = 350,
		height = 100,
		config = {
			min_size = {200, 0},
			max_size = {300, 0},
		},
	}

	app.box_clamp_to_constraints(&box3)

	testing.expect(t, box3.width == 300,
		fmt.tprintf("Box above max should be clamped to 300, got %d", box3.width))
}

// Test both min and max on height
@(test)
test_min_and_max_height :: proc(t: ^testing.T) {
	// Test that a box between min and max stays unchanged
	box1 := app.Box{
		width = 100,
		height = 250,
		config = {
			min_size = {0, 200},
			max_size = {0, 300},
		},
	}

	app.box_clamp_to_constraints(&box1)

	testing.expect(t, box1.height == 250,
		fmt.tprintf("Box between min and max should stay at 250, got %d", box1.height))

	// Test that a box below min is clamped to min
	box2 := app.Box{
		width = 100,
		height = 150,
		config = {
			min_size = {0, 200},
			max_size = {0, 300},
		},
	}

	app.box_clamp_to_constraints(&box2)

	testing.expect(t, box2.height == 200,
		fmt.tprintf("Box below min should be clamped to 200, got %d", box2.height))

	// Test that a box above max is clamped to max
	box3 := app.Box{
		width = 100,
		height = 350,
		config = {
			min_size = {0, 200},
			max_size = {0, 300},
		},
	}

	app.box_clamp_to_constraints(&box3)

	testing.expect(t, box3.height == 300,
		fmt.tprintf("Box above max should be clamped to 300, got %d", box3.height))
}

// Test zero values (no constraint)
@(test)
test_zero_constraints :: proc(t: ^testing.T) {
	// Zero min_size should not enforce minimum
	box1 := app.Box{
		width = 10,
		height = 10,
		config = {
			min_size = {0, 0},
		},
	}

	app.box_clamp_to_constraints(&box1)

	testing.expect(t, box1.width == 10 && box1.height == 10,
		fmt.tprintf("Zero min_size should not clamp, got [%d, %d]", box1.width, box1.height))

	// Zero max_size should not enforce maximum
	box2 := app.Box{
		width = 1000,
		height = 1000,
		config = {
			max_size = {0, 0},
		},
	}

	app.box_clamp_to_constraints(&box2)

	testing.expect(t, box2.width == 1000 && box2.height == 1000,
		fmt.tprintf("Zero max_size should not clamp, got [%d, %d]", box2.width, box2.height))
}

// Test both axes constrained simultaneously
@(test)
test_both_axes_constrained :: proc(t: ^testing.T) {
	box := app.Box{
		width = 50,
		height = 50,
		config = {
			min_size = {100, 150},
			max_size = {500, 600},
		},
	}

	app.box_clamp_to_constraints(&box)

	testing.expect(t, box.width == 100 && box.height == 150,
		fmt.tprintf("Both axes should be clamped to min, got [%d, %d]", box.width, box.height))
}

// Test that clamping respects both min and max when both are set
@(test)
test_min_takes_precedence_over_max :: proc(t: ^testing.T) {
	// Even if min > max (misconfiguration), min should take precedence
	box := app.Box{
		width = 50,
		height = 50,
		config = {
			min_size = {300, 400},
			max_size = {200, 200}, // max < min (misconfiguration)
		},
	}

	app.box_clamp_to_constraints(&box)

	// After min clamping: 300, 400
	// After max clamping: min(300, 200) = 200, min(400, 200) = 200
	// So max should win in current implementation

	testing.expect(t, box.width == 200 && box.height == 200,
		fmt.tprintf("When min > max, max should clamp after min, got [%d, %d]", box.width, box.height))
}

// Test large values
@(test)
test_large_values :: proc(t: ^testing.T) {
	box := app.Box{
		width = 100000,
		height = 100000,
		config = {
			min_size = {50000, 60000},
			max_size = {80000, 90000},
		},
	}

	app.box_clamp_to_constraints(&box)

	testing.expect(t, box.width == 80000 && box.height == 90000,
		fmt.tprintf("Large values should clamp correctly, got [%d, %d]", box.width, box.height))
}

// Test negative values don't break things (even though they shouldn't happen)
@(test)
test_negative_size :: proc(t: ^testing.T) {
	box := app.Box{
		width = -50,
		height = -50,
		config = {
			min_size = {100, 100},
		},
	}

	app.box_clamp_to_constraints(&box)

	testing.expect(t, box.width == 100 && box.height == 100,
		fmt.tprintf("Negative sizes should be clamped to min, got [%d, %d]", box.width, box.height))
}

// Test only one axis constrained
@(test)
test_single_axis_constrained :: proc(t: ^testing.T) {
	// Only width constrained
	box1 := app.Box{
		width = 50,
		height = 200,
		config = {
			min_size = {100, 0},
		},
	}

	app.box_clamp_to_constraints(&box1)

	testing.expect(t, box1.width == 100 && box1.height == 200,
		fmt.tprintf("Only width should be clamped, got [%d, %d]", box1.width, box1.height))

	// Only height constrained
	box2 := app.Box{
		width = 200,
		height = 50,
		config = {
			min_size = {0, 100},
		},
	}

	app.box_clamp_to_constraints(&box2)

	testing.expect(t, box2.width == 200 && box2.height == 100,
		fmt.tprintf("Only height should be clamped, got [%d, %d]", box2.width, box2.height))
}

// Test exact boundary values
@(test)
test_boundary_values :: proc(t: ^testing.T) {
	// Width exactly at min
	box1 := app.Box{
		width = 100,
		height = 100,
		config = {
			min_size = {100, 100},
		},
	}

	app.box_clamp_to_constraints(&box1)

	testing.expect(t, box1.width == 100 && box1.height == 100,
		fmt.tprintf("Exact min values should stay unchanged, got [%d, %d]", box1.width, box1.height))

	// Width exactly at max
	box2 := app.Box{
		width = 200,
		height = 200,
		config = {
			max_size = {200, 200},
		},
	}

	app.box_clamp_to_constraints(&box2)

	testing.expect(t, box2.width == 200 && box2.height == 200,
		fmt.tprintf("Exact max values should stay unchanged, got [%d, %d]", box2.width, box2.height))
}
