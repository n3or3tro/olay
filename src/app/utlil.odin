package app
import s "core:strings"

get_name_from_id_string :: proc(id_string: string) -> string {
	to := s.index(id_string, "@")
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
	printfln("{} - {} x {} - [{},{}]", root.id_string, root.width, root.height, root.top_left, root.bottom_right)
	for child in root.children {
		print_ui_tree(child, level + 1)
	}
}
