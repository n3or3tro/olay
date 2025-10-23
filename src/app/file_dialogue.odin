package app
import "core:c"
import "core:fmt"
import s "core:strings"
import "core:sys/posix"
import "core:sys/windows"
import "core:unicode/utf16"
import "core:unicode/utf8"
import sdl "vendor:sdl2"

file_dialog :: proc(multiselect: bool) -> ([dynamic]cstring, bool) {
	when ODIN_OS == .Windows {
		return file_dialog_windows(multiselect)
	} else {
		return file_dialog_linux(multiselect)
	}
}

when ODIN_OS == .Linux {
	file_dialog_linux :: proc(multiselect: bool = false) -> ([dynamic]cstring, bool) {
		paths := make([dynamic]cstring)
		fp := posix.popen("zenity --file-selection --multiple", "r\x00")
		if fp == nil {
			panic("Could not run zenity!")
		}
		in_line: [128]u8
		stdout_runes := make([dynamic]rune)
		defer delete(stdout_runes)
		for {
			stdout_data := posix.fgets(raw_data(in_line[:]), size_of(in_line), fp)
			if stdout_data == nil {
				break
			}
			for i in 0 ..< len(in_line) {
				ch := stdout_data[i]
				if ch == 0 {
					break
				}
				append(&stdout_runes, rune(ch))
			}
		}
		stdout := utf8.runes_to_string(stdout_runes[:])
		for file_name in s.split_iterator(&stdout, "|") {
			append(&paths, s.clone_to_cstring(s.trim_space(file_name)))
		}
		println(paths)
		// delete(stdout) <--- this causes a segfault, not sure why..
		// it definitely needs to be free tho, lest we leak memory every
		// time we open the file dialog
		return paths, true
	}
}

when ODIN_OS == .Windows {
	file_dialog_windows :: proc(
		multiselect: bool = false,
		allocator := context.allocator,
	) -> (
		[dynamic]cstring,
		bool,
	) {
		MAX_LEN :: 50_000 // max length of all file paths combined.
		MAX_FILES :: 1_000 // max number of files that can be returned
		config: windows.OPENFILENAMEW

		config.nMaxFile = MAX_FILES
		config.lStructSize = size_of(config)

		sdl_window_info: sdl.SysWMinfo
		sdl.GetWindowWMInfo(app.window, &sdl_window_info)
		config.hwndOwner = windows.HWND(sdl_window_info.info.win.window)


		selection_data: [MAX_LEN]u16
		title_str := "Select audio files\x00"
		title: [size_of(title_str) * 2]u16
		utf16.encode_string(title[:], title_str)

		config.lpstrFile = cstring16(raw_data(selection_data[:]))
		config.lpstrTitle = cstring16(raw_data(title[:]))

		config.Flags = windows.OFN_EXPLORER | windows.OFN_FILEMUSTEXIST | windows.OFN_NOCHANGEDIR
		if multiselect {
			config.Flags |= windows.OFN_ALLOWMULTISELECT
		}

		open_ok := windows.GetOpenFileNameW(&config)
		if !open_ok {
			println("If you selected a file and pressed 'OK', then we have a !! SERIOUS BUG !!")
			return {}, false
		}
		lol := cast([^]u16)(config.lpstrFile)
		return parse_result(lol[:], MAX_LEN, multiselect, allocator), true
	}
	@(private = "file")
	parse_result :: proc(
		data: [^]u16,
		max_length: u32,
		multiselect: bool,
		allocator := context.allocator,
	) -> [dynamic]cstring {
		if multiselect {
			return parse_multi_result(data, max_length)
		} else {
			results := make([dynamic]cstring, allocator)
			append(&results, parse_single_result(data, max_length, allocator))
			return results
		}
	}

	// assumes caller has passed in valid data, i.e. opening multi files worked
	@(private = "file")
	parse_multi_result :: proc(data: [^]u16, max_length: u32, allocator := context.allocator) -> [dynamic]cstring {
		parent_dir_runes := make([dynamic]rune)
		defer delete(parent_dir_runes)
		start_of_files: int
		for ch, i in data[0:max_length] {
			start_of_files = i
			if ch == 0 {
				break
			}
			append(&parent_dir_runes, rune(ch))
		}
		parent_dir := utf8.runes_to_string(parent_dir_runes[:])
		defer delete(parent_dir)

		results := make([dynamic]cstring, allocator)
		child_file := make([dynamic]rune)
		defer delete(child_file)

		n_nulls := 0
		for ch in data[start_of_files:2000] {
			if ch == 0 {
				n_nulls += 1
				if n_nulls == 2 { 	// 2 nulls == end of files.
					break
				}
				file_suffix := utf8.runes_to_string(child_file[:])
				file_path := tprintf("{}\\{}", parent_dir, file_suffix)
				cstring_path := s.clone_to_cstring(file_path)
				delete(file_suffix)
				// delete(file_path)
				append(&results, cstring_path)
				clear_dynamic_array(&child_file)
			} else {
				n_nulls = 0
				append(&child_file, rune(ch))
			}
		}
		return results
	}

	@(private = "file")
	parse_single_result :: proc(data: [^]u16, max_length: u32, allocator := context.allocator) -> cstring {
		filename_runes := make([dynamic]rune)
		defer delete(filename_runes)

		for ch in data[:max_length] {
			if ch == 0 {
				break
			} else {
				append(&filename_runes, rune(ch))
			}
		}
		path := utf8.runes_to_string(filename_runes[:])
		defer delete(path)
		return s.clone_to_cstring(path, allocator)
	}
}
