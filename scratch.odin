package main
import "core:encoding/json"
import "core:fmt"
import os "core:os/os2"

path :: "./util/dark-theme.json"
main :: proc() {
	parse_json_token_color_mapping :: proc(path: string) {
		json_data, err := os.read_entire_file_from_path(path, context.temp_allocator)
		if err != nil {
			panic(fmt.tprintf("Failed to open file at: {}", path))
		}

		res, json_err := json.parse(json_data)
		if json_err != .None {
			panic(fmt.tprintf("Failed to parse file, got err: {}", json_err))
		}
		fmt.printfln("Parsing json data returned: {}", res)
	}
	parse_json_token_color_mapping(path)
}
