package pool_allocator
import "core:fmt"
import "core:mem"
import vm "core:mem/virtual"
import "core:strconv"

My_Data :: struct {
	val:  int,
	name: string,
}
Other_Data :: struct {
	lol: u8,
}

main :: proc() {
	slab: Slab
	slab_init(&slab, size_of(My_Data), 10)
	slab_allocator := slab_allocator(&slab)

	// for i in 0 ..< 20 {
	for i in 0 ..< 50 {
		data, err := new(My_Data, allocator = slab_allocator)
		data.val = i
		data.name = fmt.tprintf("{}", i)
		fmt.printfln("{} {}", data, err)
		free(data, slab_allocator)
	}
	lol := new(Other_Data, slab_allocator)
}
