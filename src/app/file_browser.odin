package app

import "core:math/rand"
import "core:prof/spall"
import "core:slice"
import str "core:strings"
import "core:os"
import "core:c"

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
	parent:          ^Browser_Directory,
	sub_directories: [dynamic]Browser_Directory,
	files:           [dynamic]Browser_File,
	selected_files:  [2]int, // [start ..= end]
	collapsed:       bool,
}

Trie :: struct { 
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

	top_menu: {
		child_container(
			{semantic_size = Size_Fit_Children_And_Grow, padding = padding(10), color = .Tertiary},
			{direction = .Vertical, alignment_horizontal = .Center, alignment_vertical = .Center},
			"file-browser-options-container",
		)
		edit_text_box(
			{semantic_size = {{.Grow, 1}, {.Fixed, 30}}, border = 1, padding = {left = 4, right = 4}},
			.Generic_One_Line,
			"browser-search-bar",
		)
		hori: {
			child_container(
				{semantic_size = Size_Fit_Children},
				{direction = .Horizontal},
				"fuckmeneedanonboxeslolol",
			)
			btn_config := Box_Config {
				color         = .Secondary,
				border        = 3,
				padding       = {10, 10, 10, 10},
				semantic_size = {{.Fit_Text, 1}, {.Fit_Text_And_Grow, 1}},
				corner_radius = 0,
			}
			add_folder := text_button("Add Folder", btn_config, "browser-options-add-folder")
			sort_files := text_button("Sort", btn_config, "browser-options-sort-button")
			flip := text_button("Flip", btn_config, "browser-options-flip-button")

			if add_folder.clicked {
				multiselect := true
				dirs, ok := folder_dialog_windows(context.temp_allocator)
				if !ok {
					println(
						"File dialogue failure, either:\n- Failed to open dialogue.\n- Failed to return files from dialogue.",
					)
				}
				for dir in dirs {
					name := slice.last(str.split(dir, "\\"))
					new_dir := Browser_Directory {
						name   = str.clone(name),
						parent = app.browser_root_dir, 
						id     = int(rand.int63()),
					}
					append(&app.browser_root_dir.sub_directories, new_dir)

					handle, o_err := os.open(dir)
					if o_err != nil do panicf("{}", o_err)
					// defer os.close(handle)
					files, d_err := os.read_dir(handle, 100, context.temp_allocator)
					if d_err != nil  do panicf("{}", d_err)

					for f in files {
						// This will certainly break, we need something like persistent reliable handles, not pointers
						// into a dyn array which will certainly resize and be moved in mem.
						d := slice.last_ptr(app.browser_root_dir.sub_directories[:])
						new_file := Browser_File {
							id = int(rand.int63()),
							name = str.clone(tprintf("aa {}", f.name)),
							parent = d
						}
						printfln("added file {} to dir {}", f.name, d.name)
						append(&d.files, new_file)
						// print(f)
					}
				}

			}
			if sort_files.clicked {
			}
		}
	}

	files_and_folders: {
		child_container(
			{semantic_size = Size_Fit_Children, color = .Surface, padding = {5, 5, 5, 0}},
			{direction = .Vertical, gap_vertical = 0},
			"browser-subdirs-container",
		)

		create_subdirs_files :: proc(dir: ^Browser_Directory, level: int) {
			// Create folder part.
			// Will have ID collision if 2 folders are named the same thing.
			{
				child_container(
					{semantic_size = Size_Fit_Children_And_Grow, padding = {left = 5 * level}},
					{gap_horizontal = 1},
					id("{}-dispaly-container", dir.name),
					{},
					Metadata_Browser_Item{is_dir = true, dir_id = dir.id},
				)
				arrow_name := dir.collapsed ? ">" : "v"
				arrow_box := text_button(
					arrow_name,
					{
						semantic_size = {{.Fit_Text, 1}, {.Fit_Text_And_Grow, 1}},
						color = app.browser_selected_dir != dir ? .Secondary_Container : .Warning,
						text_justify = {.Start, .Center},
						padding = padding(5),
					},
					id("{}-arrow_box", dir.name),
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
					id("browser-folder-{}", dir.name),
					Metadata_Browser_Item{is_dir = true, dir_id = dir.id},
				)
				dir_box_signals := box_signals(dir_box)

				if ui_state.dragged_box == dir_box && dir_box.parent != nil {
					append(&ui_state.dropped_data, dir_box.metadata.(Metadata_Browser_Item))
				}

				if dir_box_signals.clicked {
					dir_box.selected = !dir_box.selected
					app.browser_selected_dir = dir
				}

				handle_drop: if dir_box_signals.dropped_on {
					if len(ui_state.dropped_data) > 0 {
						data := pop(&ui_state.dropped_data)
						// Linear searching will become inefficient when a folder has ALOT of child files.
						if dropped, ok := data.(Metadata_Browser_Item); ok {
							if dropped.is_dir {
								// Can't drop dir onto itself.
								if dropped.dir_id == dir.id do break handle_drop
								if dropped_dir, found := find_directory_by_id(app.browser_root_dir, dropped.dir_id);
								   found {
									idx, _ := index_of(dropped_dir.parent.sub_directories[:], dropped_dir)
									ordered_remove(&dropped_dir.parent.sub_directories, idx)
									dropped_dir.parent = dir
									append(&dir.sub_directories, dropped_dir^)
								}
							} else {
								// Can't drop file into same dir it's from.
								for file, idx in dir.files {if file.id == dropped.file_id do break handle_drop}
								dropped_file, ok := find_file_by_id(app.browser_root_dir, dropped.file_id)
								for file, idx in dropped_file.parent.files {
									if file.id == dropped_file.id {
										ordered_remove(&dropped_file.parent.files, idx)
										break
									}
								}
								dropped_file.parent = dir
								append(&dir.files, dropped_file^)
							}
						} else {
							printfln("Tried to drop {} into folder, which can't happen", data)
						}
					}
				}
			}

			if !dir.collapsed {
				// Can see having issues with the index being in the id here.
				for file, i in dir.files {
					file_metadata := Metadata_Browser_Item {
						file_id = file.id,
					}
					f := box_from_cache(
						{.Clickable, .Draw, .Hot_Animation, .Drag_Drop_Source, .Draw_Text},
						{
							semantic_size = Size_Fit_Text_And_Grow,
							padding = padding(5),
							margin = {left = 10 * (level + 1)},
							corner_radius = 4,
							text_justify = {.Start, .Center},
							color = .Surface,
						},
						file.name,
						id("browser-file-{}-{}", i, file.name),
						file_metadata,
					)
					file_signals := box_signals(f)

					if file_signals.box == ui_state.dragged_box {
						// Pretty inefficient if you have a long list
						if !slice.contains(ui_state.dropped_data[:], file_metadata) {
							append(&ui_state.dropped_data, file_metadata)
						}
					}

					if file_signals.clicked {
						file_signals.box.selected = !file_signals.box.selected
					}

					if file_signals.shift_clicked {
						siblings := box_get_siblings(file_signals.box^, context.temp_allocator)
						println(siblings)
					}

					if file_signals.box.selected {
						file_signals.box.config.color = .Primary
					}
				}
				for &subdir in dir.sub_directories {
					create_subdirs_files(&subdir, level + 1)
				}
			}
		}

		create_subdirs_files(app.browser_root_dir, 0)
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
