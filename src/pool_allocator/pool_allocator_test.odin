package pool_allocator

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:testing"

// --- Helper Procedures ---

// A helper to count the number of nodes in the free list.
// This is useful for verifying the state of the allocator.
count_free_list_nodes :: proc(slab: ^Slab) -> int {
	count := 0
	curr := slab.free_list_head
	for curr != nil {
		count += 1
		curr = curr.next
	}
	return count
}

// --- Test Cases ---

@(test)
test_slab_initialization :: proc(t: ^testing.T) {
	slab: Slab
	item_count := 10
	item_size := size_of(f64)


	slab_init(&slab, item_size, item_count)
	defer slab_allocator_destroy(&slab)

	// Check that the slab's properties are set correctly.
	testing.expect_value(t, slab.items_allocated, 0)
	testing.expect_value(t, slab.items_capacity, item_count)
	testing.expect_value(t, slab.item_size, item_size)

	expected_buffer_size := item_count * item_size
	testing.expect(t, slab.backing_buffer != nil, "Backing buffer should not be nil")
	testing.expect_value(t, len(slab.backing_buffer), expected_buffer_size)

	// // After init, the free list should contain every single available chunk.
	free_node_count := count_free_list_nodes(&slab)
	testing.expect(t, free_node_count == item_count, "fuck")
}

@(test)
test_single_allocation_and_free :: proc(t: ^testing.T) {
	slab: Slab
	item_size := size_of(int)
	defer slab_allocator_destroy(&slab)
	slab_init(&slab, item_size, 1)

	// --- Allocation ---
	mem_slice, err := slab_allocator_alloc(&slab, item_size)

	testing.expect_value(t, err, mem.Allocator_Error.None)
	testing.expect(t, mem_slice != nil, "Allocated memory should not be nil")
	testing.expect_value(t, slab.items_allocated, 1)

	// The free list should now be empty.
	testing.expect(t, slab.free_list_head == nil, "Free list should be empty after allocating the only item")

	// --- Free ---
	item_ptr := raw_data(mem_slice)
	slab_allocator_free(&slab, item_ptr)

	testing.expect_value(t, slab.items_allocated, 0)
	// The freed item should now be the head of the free list.
	testing.expect_value(t, slab.free_list_head, transmute(^Free_Node)item_ptr)
}

@(test)
test_full_allocation_and_free_cycle :: proc(t: ^testing.T) {
	slab: Slab
	item_count := 100
	item_size := size_of(u64)
	defer slab_allocator_destroy(&slab)
	slab_init(&slab, item_size, item_count)

	// Store pointers to free them later.
	allocations := make([dynamic]rawptr)
	defer delete(allocations)

	// Allocate until full capacity.
	for i in 0 ..< item_count {
		mem_slice, err := slab_allocator_alloc(&slab, item_size)
		testing.expect_value(t, err, mem.Allocator_Error.None)
		append(&allocations, raw_data(mem_slice))
	}

	testing.expect_value(t, slab.items_allocated, item_count)
	testing.expect(t, slab.free_list_head == nil, "Free list must be empty when slab is full")

	// Free all items.
	for ptr in allocations {
		slab_allocator_free(&slab, ptr)
	}

	testing.expect_value(t, slab.items_allocated, 0)
	free_node_count := count_free_list_nodes(&slab)
	testing.expect_value(t, free_node_count, item_count)
}

@(test)
test_interleaved_alloc_and_free :: proc(t: ^testing.T) {
	slab: Slab
	item_count := 5
	item_size := 16
	defer slab_allocator_destroy(&slab)
	slab_init(&slab, item_size, item_count)

	p1, _ := slab_allocator_alloc(&slab, item_size)
	p2, _ := slab_allocator_alloc(&slab, item_size)
	p3, _ := slab_allocator_alloc(&slab, item_size)
	testing.expect_value(t, slab.items_allocated, 3)

	// Free an item from the middle of the allocation sequence.
	slab_allocator_free(&slab, raw_data(p2))
	testing.expect_value(t, slab.items_allocated, 2)

	// The allocator should reuse the slot from p2.
	p4, _ := slab_allocator_alloc(&slab, item_size)
	testing.expect_value(t, slab.items_allocated, 3)
	// The memory location of p4 should be the same as the freed p2.
	testing.expect_value(t, raw_data(p4), raw_data(p2))
}

@(test)
test_free_all_on_partially_filled_slab :: proc(t: ^testing.T) {
	slab: Slab
	item_count := 10
	item_size := size_of(int)
	defer slab_allocator_destroy(&slab)
	slab_init(&slab, item_size, item_count)

	// Allocate about half the capacity.
	for i in 0 ..< 5 {
		slab_allocator_alloc(&slab, item_size)
	}
	testing.expect_value(t, slab.items_allocated, 5)

	// Now, free everything.
	slab_allocator_free_all(&slab)

	// The slab should be completely reset.
	testing.expect_value(t, slab.items_allocated, 0)
	free_node_count := count_free_list_nodes(&slab)
	testing.expect_value(t, free_node_count, item_count)

	// A subsequent allocation should succeed.
	_, err := slab_allocator_alloc(&slab, item_size)
	testing.expect_value(t, err, mem.Allocator_Error.None)
	testing.expect_value(t, slab.items_allocated, 1)
}

@(test)
test_free_list_lifo_behavior :: proc(t: ^testing.T) {
	slab: Slab
	item_count := 3
	item_size := 32
	slab_init(&slab, item_size, item_count)
	defer slab_allocator_destroy(&slab)

	p1, _ := slab_allocator_alloc(&slab, item_size)
	p2, _ := slab_allocator_alloc(&slab, item_size)
	p3, _ := slab_allocator_alloc(&slab, item_size)

	ptr1 := raw_data(p1)
	ptr2 := raw_data(p2)
	ptr3 := raw_data(p3)

	// Free in a specific, non-sequential order: 2, then 1.
	slab_allocator_free(&slab, ptr2)
	slab_allocator_free(&slab, ptr1)

	// Due to LIFO, the next allocation should reuse ptr1's memory,
	// and the one after that should reuse ptr2's memory.
	p4, _ := slab_allocator_alloc(&slab, item_size)
	ptr4 := raw_data(p4)
	testing.expect_value(t, ptr4, ptr1)

	p5, _ := slab_allocator_alloc(&slab, item_size)
	ptr5 := raw_data(p5)
	testing.expect_value(t, ptr5, ptr2)
}

@(test)
test_data_integrity_with_structs :: proc(t: ^testing.T) {
	Test_Struct :: struct {
		id:   u32,
		name: string,
	}

	slab: Slab
	item_count := 5
	item_size := size_of(Test_Struct)
	slab_init(&slab, item_size, item_count)
	defer slab_allocator_destroy(&slab)

	test_struct := new(Test_Struct, slab_allocator(&slab))
	test_struct.id = 99
	test_struct.name = "test_data"

	// Verify the data by reading it back.
	testing.expect_value(t, test_struct.id, 99)
	testing.expect_value(t, test_struct.name, "test_data")
}

@(test)
test_usage_through_allocator_interface :: proc(t: ^testing.T) {
	slab: Slab
	item_count := 10
	item_size := size_of(f64)
	slab_init(&slab, item_size, item_count, backing_allocator = context.temp_allocator)

	custom_allocator := slab_allocator(&slab)
	// Allocate and free using the standard `mem` procedures.
	data, err := mem.alloc(item_size, allocator = custom_allocator)
	testing.expect_value(t, err, mem.Allocator_Error.None)
	testing.expect_value(t, slab.items_allocated, 1)

	mem.free(data, custom_allocator)
	testing.expect_value(t, slab.items_allocated, 0)

	// Test making a slice
	slice, slice_err := mem.make_slice([]f64, 1, custom_allocator)
	testing.expect_value(t, slice_err, mem.Allocator_Error.None)
	testing.expect_value(t, slab.items_allocated, 1)

	mem.delete_slice(slice, custom_allocator)
	testing.expect_value(t, slab.items_allocated, 0)
}

// // --- Death Tests ---
// // These tests verify that the code panics under specific failure conditions.
// @(test)
// test_panic_on_alloc_when_full :: proc(t: ^testing.T) {
// 	slab: Slab
// 	slab_init(&slab, size_of(int), 1)
// 	// defer slab_allocator_destroy(&slab)

// 	slab_allocator_alloc(&slab, size_of(int)) // Slab is now full.
// 	testing.expect_assert_message(t, "Tried to allocate from full slab allocator.")
// 	slab_allocator_alloc(&slab, size_of(int)) // This second call must panic.
// }

// @(test)
// test_panic_on_double_free :: proc(t: ^testing.T) {
// 	slab: Slab
// 	defer slab_allocator_destroy(&slab)
// 	slab_init(&slab, size_of(int), 1)

// 	mem_slice, _ := slab_allocator_alloc(&slab, size_of(int))
// 	item_ptr := raw_data(mem_slice)

// 	slab_allocator_free(&slab, item_ptr) // First free is OK.
// 	testing.expect_assert_message(t, "Double free detected in slab allocator.")
// 	slab_allocator_free(&slab, item_ptr) // Second free must panic.
// }

// @(test)
// test_panic_on_freeing_nil :: proc(t: ^testing.T) {
// 	slab: Slab
// 	defer slab_allocator_destroy(&slab)
// 	slab_init(&slab, size_of(int), 1)

// 	testing.expect_assert_message(
// 		t,
// 		"Pointer which was passed in to free, is outside the bounds of the backing buffer.",
// 	)
// 	slab_allocator_free(&slab, nil) // Must panic.
// }

// @(test)
// test_panic_on_freeing_invalid_pointer :: proc(t: ^testing.T) {
// 	slab: Slab
// 	defer slab_allocator_destroy(&slab)
// 	slab_init(&slab, size_of(int), 1)

// 	// Create a pointer to something on the stack, not in the slab.
// 	x: int
// 	invalid_ptr := &x
// 	testing.expect_assert_message(t, "Passed in nil pointer to slab_allocator_free.")
// 	slab_allocator_free(&slab, invalid_ptr) // Must panic.
// }

// @(test)
// test_panic_on_wrong_alloc_size :: proc(t: ^testing.T) {
// 	slab: Slab
// 	defer slab_allocator_destroy(&slab)
// 	slab_init(&slab, 16, 5)

// 	testing.expect_assert_message(
// 		t,
// 		"Tried to allocate a size of memory which was different from the size this allocator was configured to support.",
// 	)
// 	slab_allocator_alloc(&slab, 8) // Requesting 8 bytes when slab is configured for 16 must panic.
// }

// @(test)
// test_panic_on_init_with_zero_items :: proc(t: ^testing.T) {
// 	slab: Slab
// 	defer slab_allocator_destroy(&slab)
// 	testing.expect_assert_message(t, "You cannot create a slab allocator that holds < 1 item.")
// 	slab_init(&slab, size_of(int), 0) // Must panic as n_items < 1.

// }
