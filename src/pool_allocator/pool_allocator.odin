/*
An implementation of a statically sized slab allocator. 

It's designed to take in a fixed size backing buffer and a type T; and then allow for 
O(1) creation / deletion of objects of type T.

Designed to panic if you write more bytes than can be allowed by the buffer you passed in.

Designed to take in another allocator which will be used to create the backing store of the slab. 
*/

package pool_allocator
import "core:fmt"
import "core:log"
import "core:mem"
import "core:slice"

// Could be done with just next and taking from the front, but the weird casting / transmuting below
// requires this struct to be 16 bytes I think anyway.
Free_Node :: struct {
	next: ^Free_Node,
}

Slab :: struct {
	item_size:       int, // Size in bytes of the type you want to store chunks of. i.e. sizeof(My_Struct)
	backing_buffer:  [dynamic]byte,
	free_list_head:  ^Free_Node,
	items_allocated: int, // How many T's are currently alloc'd (doesn't include things in free list).
	items_capacity:  int, // How many T's you *can* alloc in total.
	alignment:       int,
}

slab_init :: proc(
	slab: ^Slab,
	item_size: int,
	n_items: int,
	backing_allocator := context.allocator,
	alignment := mem.DEFAULT_ALIGNMENT,
) {
	assert(n_items > 0, "You cannot create a slab allocator that holds < 1 item.")
	assert(
		item_size >= size_of(Free_Node),
		fmt.tprintf(
			"item_size is too small to hold a Free_Node pointer. item_size: {}, size_of(Free_Node): {}",
			item_size,
			size_of(Free_Node),
		),
	)
	slab.backing_buffer = make([dynamic]byte, item_size * n_items)

	// Init the free list.
	for i in 0 ..< n_items {
		start := i * item_size
		node := transmute(^Free_Node)&slab.backing_buffer[start]
		node.next = slab.free_list_head
		slab.free_list_head = node
	}

	slab.items_capacity = n_items
	slab.items_allocated = 0
	slab.item_size = item_size
	slab.alignment = alignment
}


slab_allocator_alloc :: proc(slab: ^Slab, size: int, loc := #caller_location) -> ([]byte, mem.Allocator_Error) {
	assert(slab.items_capacity != slab.items_allocated, "Tried to allocate from full slab allocator.")
	assert(
		size == slab.item_size,
		"Tried to allocate a size of memory which was different from the size this allocator was configured to support",
	)
	next_free := slab.free_list_head
	slab.free_list_head = next_free.next // Works even if next_free.next is nil

	result := ([^]byte)(next_free)[:size]
	slab.items_allocated += 1
	return result, .None
}

slab_allocator_free :: proc(slab: ^Slab, item: rawptr) -> ([]byte, mem.Allocator_Error) {
	start := raw_data(slab.backing_buffer)
	end := rawptr(&slab.backing_buffer[slab.items_capacity * slab.item_size - 1])
	assert(
		item <= end && item >= start,
		"Pointer which was passed in to free, is outside the bounds of the backing buffer.",
	)
	assert(item != nil, "Passed in nil pointer to slab_allocator_free.")

	// In debug mode we will walk the free list to try and catch if we've free'd this pointer already.
	// if ODIN_DEBUG {
	// 	curr := slab.free_list_head
	// 	for curr != nil {
	// 		fmt.printfln("curr: {}", curr)
	// 		assert(curr != item, "Double free detected in slab allocator.")
	// 		curr = curr.next
	// 	}
	// }

	node := transmute(^Free_Node)item

	// This works whether the list is empty or not.
	node.next = slab.free_list_head
	slab.free_list_head = node

	slab.items_allocated -= 1
	return nil, .None
}

// I fear calling free all when there's already things in the list will cause the same chunk to appear in the
// free list twice.
slab_allocator_free_all :: proc(slab: ^Slab) -> ([]byte, mem.Allocator_Error) {

	// Rebuild the free list from scratch.
	slab.free_list_head = nil
	for i in 0 ..< slab.items_capacity {
		offset := i * slab.item_size
		node := transmute(^Free_Node)&slab.backing_buffer[offset]
		node.next = slab.free_list_head
		slab.free_list_head = node
	}
	slab.items_allocated = 0
	return nil, .None
}

slab_allocator_destroy :: proc(slab: ^Slab) -> ([]byte, mem.Allocator_Error) {
	delete(slab.backing_buffer)
	slab^ = Slab{}
	return nil, .None
}

slab_allocator :: proc(pool: ^Slab) -> mem.Allocator {
	return mem.Allocator{procedure = slab_allocator_proc, data = pool}
}


slab_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: mem.Allocator_Mode,
	size: int,
	alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (
	[]byte,
	mem.Allocator_Error,
) {
	slab := (^Slab)(allocator_data)
	switch mode {
	case .Alloc:
		return slab_allocator_alloc(slab, size)
	case .Alloc_Non_Zeroed:
	case .Free:
		return slab_allocator_free(slab, old_memory)
	case .Free_All:
	case .Query_Features:
		return nil, .Mode_Not_Implemented
	case .Query_Info:
		return nil, .Mode_Not_Implemented
	case .Resize:
		return nil, .Mode_Not_Implemented
	case .Resize_Non_Zeroed:
		return nil, .Mode_Not_Implemented
	}
	assert(1 == 2, "slab_allocator_proc did not receive a valid .Mode")
	return nil, .Mode_Not_Implemented
}
