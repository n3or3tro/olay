package app
import "base:intrinsics"
import s "core:strings"

// Could definitely break due to numeric type conversions and integer division and shit.
map_range :: proc(in_min, in_max, out_min, out_max, value: $T) -> T where intrinsics.type_is_numeric(T) {
	return ((value - in_min) * (out_max - out_min) / (in_max - in_min)) + out_min
}

get_label_from_id_string :: proc(id_string: string) -> string {
	to := s.index(id_string, "@")
	if to == -1 {
		return ""
	}
	return id_string[:to]
}

get_id_from_id_string :: proc(id_string: string) -> string {
	from := s.index(id_string, "@")
	return id_string[from + 1:]
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
