package app
import "base:intrinsics"
import "core:strconv"
import str "core:strings"

// Could definitely break due to numeric type conversions and integer division and shit.
map_range :: proc(in_min, in_max, out_min, out_max, value: $T) -> T where intrinsics.type_is_numeric(T) {
	return ((value - in_min) * (out_max - out_min) / (in_max - in_min)) + out_min
}

// get_label_from_id_string :: proc(id_string: string) -> string {
// 	to := str.index(id_string, "@")
// 	if to == -1 {
// 		return ""
// 	}
// 	return id_string[:to]
// }

// get_id_from_id_string :: proc(id_string: string) -> string {
// 	from := str.index(id_string, "@")
// 	return id_string[from + 1:]
// }

get_drag_delta :: proc() -> [2]int {
	return {
		app.mouse_last_frame.pos.x - app.mouse.pos.x,
		app.mouse_last_frame.pos.y - app.mouse.pos.y,
	}
}

print_ui_tree :: proc(root: ^Box, level: int) {
	for _ in 0 ..< level {
		print("  ")
	}
	printfln("{} - {} x {} - [{},{}]", root.id, root.width, root.height, root.top_left, root.bottom_right)
	for child in root.children {
		print_ui_tree(child, level + 1)
	}
}

box_height :: proc(box: Box) -> u32 {
	height := box.bottom_right.y - box.top_left.y
	assert(height >= 0)
	return u32(height)
}

box_width :: proc(box: Box) -> u32 {
	width := box.bottom_right.x - box.top_left.x
	assert(width >= 0)
	return u32(width)
}

box_data_as_string :: proc(box_data: Box_Data, allocator := context.allocator) -> string { 
	data_as_string: string
	switch data in box_data {
	case string:
		// Wasteful to clone, but it helps to simplify the API, since other variants must malloc data.
		data_as_string = str.clone(data, allocator)
	case int:
		// Would not work properly for giant numbers.
		buf := make([]byte, 32, allocator)
		data_as_string = strconv.itoa(buf[:], data)
	case f64:
		// Would not work properly for giant numbers.
		buf := make([]byte, 32, allocator)
		data_as_string = strconv.write_float(buf[:], data, 'f', 2, 64)
	}
	return data_as_string
}

// Helper to get point to the last element at the end of a dynamic array / slice.
tail :: proc(list: []$T) -> ^T{ 
	if len(list) > 0 {
		return &list[len(list) - 1]
	} else {
		return nil
	}
}

box_center :: proc(box: Box) -> [2]f32 {
    return {
        (f32(box.top_left.x) + f32(box.bottom_right.x)) / 2,
        (f32(box.top_left.y) + f32(box.bottom_right.y)) / 2
	};
}

box_get_padding_x_tot :: proc(box: Box) -> int { 
	return box.config.padding.left + box.config.padding.right
}

box_get_padding_y_tot :: proc(box: Box) -> int { 
	return box.config.padding.top + box.config.padding.bottom
}

box_get_margin_x_tot :: proc(box: Box) -> int { 
	return box.config.margin.left + box.config.margin.right
}

box_get_margin_y_tot :: proc(box: Box) -> int { 
	return box.config.margin.top + box.config.margin.bottom
}


panicf :: proc(fmt_string: string, args: ..any, newline := false) -> string {
	panic(tprintf(fmt_string, args, newline))
}

index_of :: proc(list: []$T, item: ^T) -> (index: int, found: bool) {
	for &el, i in list { 
		if &el == item {
			return i, true
		}
	}
	return -1, false
}