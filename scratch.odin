package main
import "core:encoding/json"
import "core:fmt"
import os "core:os/os2"
import "core:sort"

path :: "./util/dark-theme.json"
// main :: proc() {
// 	parse_json_token_color_mapping :: proc(path: string) {
// 		json_data, err := os.read_entire_file_from_path(path, context.temp_allocator)
// 		if err != nil {
// 			panic(fmt.tprintf("Failed to open file at: {}", path))
// 		}

// 		res, json_err := json.parse(json_data)
// 		if json_err != .None {
// 			panic(fmt.tprintf("Failed to parse file, got err: {}", json_err))
// 		}
// 		fmt.printfln("Parsing json data returned: {}", res)
// 	}
// 	parse_json_token_color_mapping(path)
// }

Box :: struct { 
	z_index: int,
	data: 	 int,
}
print_box_list :: proc(list: []Box) { 
	for box in list { 
		fmt.printfln("data: {}   z_index: {}", box.data, box.z_index)
	}
}

main :: proc() { 
	b1 := Box{
		z_index = 4234, 
		data = 1
	}
	b2 := Box{
		z_index = 4839, 
		data = 69
	}
	b3 := Box{
		z_index = 0, 
		data = 47
	}
	b4 := Box{
		z_index = -4234, 
		data = 2304
	}
	b5 := Box{
		z_index = -234, 
		data = 42 
	}
	box_list := [5]Box{b1, b2, b3, b4, b5}
	print_box_list(box_list[:])
	sort.quick_sort_proc(box_list[:], proc(a, b: Box) -> int {
		if a.z_index < b.z_index {
			return -1
		} else if a.z_index > b.z_index {
			return 1
		} else {
			return 0
		}
	})
	fmt.println("")
	print_box_list(box_list[:])
}