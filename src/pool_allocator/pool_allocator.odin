/*
An implementation of a statically sized slab allocator. 

It's designed to take in a fixed size backing buffer and a type T; and then allow for 
O(1) creation / deletion of objects of type T.

Designed to panic if you write more bytes than can be allowed by the buffer you passed in.

Designed to take in another allocator which will be used to create the backing store of the slab. 
*/

package pool_allocator
import "core:fmt"
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
	if n_items < 1 {
		panic("You tried to create a slab allocator that holds < 1 item !!!")
	}
	slab.backing_buffer = make([dynamic]byte, item_size * n_items, allocator = backing_allocator)

	// Init the free list.
	first_node := transmute(^Free_Node)&slab.backing_buffer[0]
	slab.free_list_head = first_node
	for i in 0 ..< n_items {
		start := i * item_size
		end := (i + 1) * item_size
		node := transmute(^Free_Node)&slab.backing_buffer[start]
		node.next = slab.free_list_head
		slab.free_list_head = node
	}

	slab.items_capacity = n_items
	slab.items_allocated = 0
	slab.item_size = item_size
	slab.alignment = alignment
}


slab_allocator_free :: proc(slab: ^Slab, item: rawptr) -> ([]byte, mem.Allocator_Error) {
	start := raw_data(slab.backing_buffer)
	end := rawptr(&slab.backing_buffer[slab.items_capacity * slab.item_size - 1])
	if item > end || item < start {
		panic("tried to free an item whose address does not lie in the bounds of this allocators backing buffer.")
	}
	if item == nil {
		panic("tried to free nil pointer")
	}
	node := transmute(^Free_Node)item
	if slab.free_list_head == nil {
		if slab.items_allocated != 0 {
			panic(
				"When trying to free, found that items_allocated != 0 BUT free_list_head == nil. Should never happen!",
			)
		} else {
			slab.free_list_head = node
		}
	} else {
		node.next = slab.free_list_head
		slab.free_list_head = node
	}
	slab.items_allocated -= 1
	return nil, .None
}

// I fear calling free all when there's already things in the list will cause the same chunk to appear in the
// free list twice.
slab_allocator_free_all :: proc(slab: ^Slab) -> ([]byte, mem.Allocator_Error) {
	for i in 0 ..< slab.items_capacity {
		offset := i * slab.item_size
		node := transmute(^Free_Node)&slab.backing_buffer[offset]
		if i == 0 && slab.items_allocated == slab.items_capacity {
			slab.free_list_head = node
		} else {
			node.next = slab.free_list_head
			slab.free_list_head.next = node
		}
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

slab_allocator_alloc :: proc(slab: ^Slab, size: int, loc := #caller_location) -> ([]byte, mem.Allocator_Error) {
	if slab.items_allocated == slab.items_capacity {
		panic("Tried to allocate from full slab allocator.")
	}
	if size != slab.item_size {
		panic(
			fmt.tprintf(
				"Tried to allocate {} byte. This slab allocator was configured to allocate chunks of size {} bytes",
				size,
				slab.item_size,
			),
		)
	}
	next_free: ^Free_Node
	if slab.free_list_head.next == nil { 	// i.e. there's only 1 free chunk left.
		next_free = slab.free_list_head
		slab.free_list_head = nil
	} else {
		new_head := slab.free_list_head.next
		next_free = slab.free_list_head
		slab.free_list_head = new_head
	}
	result := ([^]byte)(next_free)[:size]
	slab.items_allocated += 1
	return result, .None
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
	panic("slab_allocator_proc did not receive a valid .Mode")
}
