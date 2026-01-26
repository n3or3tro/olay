package app

import "core:math/rand"
import "core:slice"
import str "core:strings"
import "core:os"
import vmem "core:mem/virtual"
import "core:path/filepath"

Browser_File :: struct {
	// Pseudo GID for sorting and ID shit.
	id:     int,
	name:   string,
	parent: ^Browser_Directory,
}

Browser_Directory :: struct {
	// Pseudo GID for sorting and ID shit.
	id:              int,
	name:            string,
	// This is the full path on the disk, we use it when loading files from
	// a directory.
	path: 			 string,
	parent:          ^Browser_Directory,
	sub_directories: [dynamic]Browser_Directory,
	files:           [dynamic]Browser_File,
	selected_files:  [2]int, // [start ..= end]
	collapsed:       bool,
}

Trie :: struct { 
}
@(private="file")
add_dirs_to_browser :: proc(parent: ^Browser_Directory, dirs: []string) { 
	arena, scratch := arena_allocator_new()
	defer arena_allocator_destroy(arena, scratch)
	for dir in dirs {
		handle, o_err := os.open(dir)
		if o_err != nil do panicf("{}", o_err)
		defer os.close(handle)
		dir_name := filepath.base(dir)
		new_dir  := Browser_Directory {
			name   = str.clone(dir_name),
			parent = parent, 
			id     = int(rand.int63()),
			path   = str.clone(dir)
		}

		append(&parent.sub_directories, new_dir)
		new_dir_ptr := slice.last_ptr(parent.sub_directories[:])

		files, d_err := os.read_dir(handle, 100, scratch)
		if d_err != nil do panicf("{}", d_err)

		audio_files := make([dynamic]Browser_File, scratch)
		subdirs := make([dynamic]string, scratch)

		for f in files {
			if f.is_dir {
				// add_dirs_to_browser(new_dir_ptr, {f.fullpath})
				append(&subdirs, f.fullpath)
			}
			if !is_audio_file_via_path(f.name) do continue

			new_file := Browser_File {
				id = int(rand.int63()),
				name = str.clone(f.name),
				parent = new_dir_ptr,
			}
			append(&audio_files, new_file)
		}

		if len(audio_files) > 0 {
			// This will certainly break, we need something like persistent reliable handles, not pointers
			// into a dyn array which will certainly resize and be moved in mem.
			for &file in audio_files { 
				file.parent = new_dir_ptr
				append(&new_dir_ptr.files, file)
			}
			add_dirs_to_browser(new_dir_ptr, subdirs[:])
		} else if len(subdirs) > 0 {
			add_dirs_to_browser(new_dir_ptr, subdirs[:])
		} else {
			// Kinda jank to append then delete like this.
			delete(new_dir.name)
			pop(&parent.sub_directories)
		}
	}
}

file_browser_menu :: proc() {
	child_container(
		{
			semantic_size = {{.Fit_Children, 1}, {.Fit_Children, 1}},
			color = .Primary_Container,
			padding = {bottom = 5},
			z_index = 10,
			min_size = {350, 70},
			max_size = {800, app.wy - 100},
		},
		{direction = .Vertical},
		"file-browser-container",
		{.Draw},
	)

	search_term := ""

	top_menu: {
		child_container(
			{
				semantic_size = Size_Fit_Children_And_Grow, 
				padding = padding(10), 
				color = .Tertiary
			},
			{
				direction = .Vertical, 
				alignment_horizontal = .Center,
				alignment_vertical = .Center
			},
		)
		search_bar := edit_text_box(
			{
				semantic_size = {{.Grow, 1}, {.Fixed, 30}}, 
				padding = {left = 4, right = 4},
				border = 1
			},
			.Generic_One_Line,
		)
		search_term = search_bar.box.data.(string)
		hori: {
			child_container(
				{semantic_size = Size_Fit_Children},
				{direction = .Horizontal},
			)
			btn_config := Box_Config {
				color         = .Secondary,
				border        = 3,
				padding       = {10, 10, 10, 10},
				semantic_size = {{.Fit_Text, 1}, {.Fit_Text_And_Grow, 1}},
				corner_radius = 0,
			}
			add_folder := text_button("Add Folder", btn_config)
			sort_files := text_button("Sort", btn_config)
			flip 	   := text_button("Flip", btn_config)

			if add_folder.clicked {
				arena, scratch := arena_allocator_new()
				defer arena_allocator_destroy(arena, scratch)
				multiselect := true
				dirs, ok := folder_dialog_windows(scratch)
				if !ok {
					println(
						"File dialogue failure, either:\n- Failed to open dialogue.\n- Failed to return files from dialogue.",
					)
				}
				add_dirs_to_browser(app.browser_root_dir, dirs[:])
			}
		}
	}
	files_and_folders: {
		create_subdirs_files :: proc(dir: ^Browser_Directory, level: int, search_term: string) {
			{
				child_container(
					{semantic_size = Size_Fit_Children_And_Grow, padding = {left = 15 * level}},
					{gap_horizontal = 1},
				)
				arrow_box := text_button(
					dir.collapsed ? ">" : "v",
					{
						semantic_size = {{.Fit_Text, 1}, {.Fit_Text_And_Grow, 1}},
						color = app.browser_selected_dir != dir ? .Secondary_Container : .Warning,
						text_justify = {.Start, .Center},
						padding = padding(5),
					},
				)
				if arrow_box.clicked {
					dir.collapsed = !dir.collapsed
				}
				dir_box := box_from_cache(
					{
						.Clickable, .Drag_Drop_Sink, .Drag_Drop_Source, .Draw,
						.Active_Animation, .Hot_Animation, .Draw_Text,
					},
					{
						border = 1,
						color = app.browser_selected_dir != dir ? .Secondary_Container : .Warning,
						semantic_size = Size_Fit_Text_And_Grow,
						text_justify = {.Start, .Center},
						padding = padding(5),
					},
					dir.name,
				)
				dir_box_signals := box_signals(dir_box)

				if dir_box_signals.clicked {
					dir_box.selected = !dir_box.selected
					app.browser_selected_dir = dir
				}
			}

			if !dir.collapsed {
				// Can see having issues with the index being in the id here.
				for file, i in dir.files {
					if !str.contains(file.name, search_term) do continue
					f := box_from_cache(
						{.Clickable, .Draw, .Hot_Animation, .Drag_Drop_Source, .Draw_Text},
						{
							semantic_size = Size_Fit_Text_And_Grow,
							padding = padding(5),
							margin = {left = 15 * (level + 1)},
							corner_radius = 4,
							text_justify = {.Start, .Center},
							color = .Surface,
						},
						file.name,
					)
					file_signals := box_signals(f)

					if file_signals.box == ui_state.dragged_box {
						// Pretty inefficient if you have a long list
						if !slice.contains(ui_state.dropped_data[:], file) {
							append(&ui_state.dropped_data, file)
						}
					}

					if file_signals.clicked {
						file_signals.box.selected = !file_signals.box.selected
					}

					if file_signals.box.selected {
						file_signals.box.config.color = .Primary
					}
				}
				for &subdir in dir.sub_directories {
					create_subdirs_files(&subdir, level + 1, search_term)
				}
			}
		}

		child_container(
			{
				overflow_y = .Scroll,
				overflow_x = .Scroll,
				// semantic_size = {{.Percent, 1}, {.Percent, 1}},
				max_size = {800, app.wy - 250},
				color = .Warning,
			},
			{
				direction = .Vertical
			},
			"browser-main-container",
			{.Scrollable, .Draw, .Scrollbar}
		)
		// Create each child of the root at the top level, this is because we don't actually
		// want to render / interact with the root.
		for &subdir in app.browser_root_dir.sub_directories{
			create_subdirs_files(&subdir, 0, search_term)
		}
	}
}

file_browser_delete_file :: proc(file: ^Browser_File) {
	idx, found := index_of(file.parent.files[:], file)
	if !found {
		panicf("could not find file: {} with name: {} in it's parent", file.id, file.name)
	}
	ordered_remove(&file.parent.files, idx)
}

file_browser_delete_dir :: proc(dir: ^Browser_Directory) {
	// We don't need to
	if dir.parent == nil {
		printfln("Cannot delete the root dir: {}", dir.name)
		return
	}
	delete(dir.files)
	for &subdir in dir.sub_directories {
		file_browser_delete_dir(&subdir)
	}
	idx, found := index_of(dir.parent.sub_directories[:], dir)
	if !found {
		panicf("could not find dir: {} in it's parent", dir.name)
	}
	ordered_remove(&dir.parent.sub_directories, idx)
}

@(private = "file")
find_directory_by_id :: proc(node: ^Browser_Directory, id: int) -> (dir: ^Browser_Directory, found_it: bool) {
	if node.id == id do return node, true
	for &subdir in node.sub_directories {
		if dir, found := find_directory_by_id(&subdir, id); found {
			return dir, true
		}
	}
	return nil, false
}

@(private = "file")
find_file_by_id :: proc(root: ^Browser_Directory, id: int) -> (file: ^Browser_File, found_it: bool) {
	search_dir :: proc(root: ^Browser_Directory, id: int) -> (^Browser_File, bool) {
		for &file in root.files {
			if file.id == id {
				return &file, true
			}
		}
		return nil, false
	}

	if file, found := search_dir(root, id); found {
		return file, true
	}

	for &subdir in root.sub_directories {
		if file, found := search_dir(&subdir, id); found {
			return file, true
		}
	}

	return nil, false
}
