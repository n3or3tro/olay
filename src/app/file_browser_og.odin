package app

// import "core:math/rand"
// import "core:slice"
// import str "core:strings"
// import "core:prof/spall"

// Browser_File :: struct { 
// 	// Pseudo GID for sorting and ID shit.
// 	id:   int, 
// 	name: string,
// 	parent: int,
// }

// Browser_Directory :: struct {
// 	// Pseudo GID for sorting and ID shit.
// 	id:   int, 
// 	name:            string,
// 	parent: 		 int,
// 	sub_directories: [dynamic]Browser_Directory,
// 	files:           [dynamic]Browser_File,
// 	selected_files:  [2]int, // [start ..= end]
// 	collapsed: 		 bool,
// }

// file_browser_menu :: proc() {
// 	child_container(
// 		"@file-browser-container",
// 		{
// 			semantic_size 	= {{.Fit_Children, 1}, {.Fit_Children, 1}},
// 			color 			= .Primary_Container,
// 			padding 		= {bottom = 5},
// 			z_index 		= 10,
// 			min_size	 	= {350, 70},
// 			max_size		= {800, 2>>64}
// 		},
// 		{direction = .Vertical},
// 		{.Draw}
// 	)

// 	top_menu: {
// 		child_container(
// 			"@file-browser-options-container",
// 			{
// 				semantic_size 	= Size_Fit_Children_And_Grow,
// 				padding 		= padding(10),
// 				color 			= .Tertiary,
// 			},
// 			{direction = .Horizontal, alignment_horizontal = .Center, alignment_vertical = .Center},
// 		)
// 		btn_config := Box_Config {
// 			color 			 = .Secondary,
// 			border			 = 3,
// 			padding          = {10, 10, 10, 10},
// 			semantic_size    = {{.Fit_Text, 1}, {.Fit_Text_And_Grow, 1}},
// 			corner_radius    = 0,
// 		}
// 		load := text_button("Add Files@browser-options-folder-button", btn_config)
// 		sort_files := text_button("Sort@browser-options-sort-button", btn_config)
// 		flip := text_button("Flip@browser-options-flip-button", btn_config)
// 		box_from_cache("@filler-hehe-mwahaha", {},  {size = Size_Grow})
// 		add_folder := text_button("Add Folder@browser-options-add-folder", btn_config)

// 		if load.clicked {
// 			res, ok := file_dialog_windows(true, context.temp_allocator)
// 			if !ok {
// 				// panic(
// 				println(
// 					"File dialogue failure, either:\n- Failed to open dialogue.\n- Failed to return files from dialogue.",
// 				)
// 			}
// 			for path in res {
// 				// path_string := str.clone_from_cstring(path, context.temp_allocator)
// 				path_string := str.clone_from_cstring(path)
// 				tokens, err := str.split(path_string, "\\")
// 				if err != nil do panic(tprintf("{}", err))
// 				file_name := slice.last(tokens[:])
// 				file := Browser_File { 
// 					name   = file_name, 
// 					parent = app.browser_selected_dir.id,
// 					id 	   = int(rand.int63())
// 				}
// 				append(&app.browser_selected_dir.files, file)
// 			}
// 		}

// 		if add_folder.clicked {
// 			name := str.clone(tprintf("new_dir_{}", rand.int31()))
// 			new_folder := Browser_Directory {
// 				// Not sure why, but if I don't clone this string, shit breaks and it doesn't dispaly properly.
// 				name = name,
// 				id = int(rand.int63())
// 			}
// 			new_folder.parent = app.browser_selected_dir.id
// 			append(&app.browser_selected_dir.sub_directories, new_folder)
// 			printfln("added {} to {}", new_folder.name, app.browser_selected_dir.name)
// 		}

// 		if sort_files.clicked {
// 		}
// 	}

// 	files_and_folders: {
// 		child_container(
// 			"@browser-subdirs-container",
// 			{
// 				size = Size_Fit_Children, 
// 				color = .Surface,
// 				padding = {5,5,5,0}
// 			},
// 			{
// 				direction = .Vertical,
// 				gap_vertical = 0,
// 			},
// 		)

// 		create_subdirs_files :: proc(dir: ^Browser_Directory, level: int) {
// 			// Create folder part.
// 			// Will have ID collision if 2 folders are named the same thing.
// 			{
// 				child_container(
// 					id("@{}-dispaly-container", dir.name),
// 					{
// 						size = Size_Fit_Children_And_Grow,
// 						padding = {left = 5 * level}
// 					},
// 					{
// 						gap_horizontal = 1
// 					},
// 					metadata = Metadata_Browser_Item{
// 						is_dir = true,
// 						dir_id = dir.id,
// 					}
// 				)
// 				arrow_name := dir.collapsed ? ">" : "v"
// 				arrow_box := text_button(
// 					id("{}@{}-arrow_box", arrow_name, dir.name),
// 					{ 
// 						size = {{.Fit_Text, 1}, {.Fit_Text_And_Grow, 1}},
// 						color = app.browser_selected_dir != dir ? .Secondary_Container : .Warning,
// 						text_justify = {.Start, .Center},
// 						padding = padding(5),
// 					},
// 				)
// 				if arrow_box.clicked { 
// 					dir.collapsed = !dir.collapsed
// 				}
// 				dir_box := box_from_cache(
// 					id("{}@browser-folder-{}", dir.name, dir.name), 
// 					{.Clickable, .Drag_Drop_Sink, .Drag_Drop_Source, .Draw, .Active_Animation, .Hot_Animation, .Draw_Text},
// 					{
// 						border = 1,
// 						color = app.browser_selected_dir != dir ? .Secondary_Container : .Warning,
// 						size = Size_Fit_Text_And_Grow,
// 						text_justify = {.Start, .Center},
// 						padding = padding(5),
// 					},
// 					metadata = Metadata_Browser_Item {
// 						is_dir = true,
// 						dir_id = dir.id
// 					}
// 				)	
// 				dir_box_signals := box_signals(dir_box)

// 				if ui_state.dragged_box == dir_box && dir_box.parent != nil { 
// 					append(&ui_state.dropped_data, dir_box.metadata.(Metadata_Browser_Item))
// 				}

// 				if dir_box_signals.clicked {
// 					dir_box.selected = !dir_box.selected
// 					app.browser_selected_dir = dir
// 				}

// 				handle_drop: if dir_box_signals.dropped_on {
// 					if len(ui_state.dropped_data) > 0 { 
// 						data := pop(&ui_state.dropped_data)
// 						// Linear searching will become inefficient when a folder has ALOT of child files.
// 						if dropped, ok := data.(Metadata_Browser_Item); ok {
// 							if dropped.is_dir {
// 								// Can't drop dir onto itself.
// 								if dropped.dir_id == dir.id do break handle_drop
// 								if dropped_dir, found_dir := find_directory_by_id(app.browser_root_dir, dropped.dir_id); found_dir { 
// 									dropped_dir_parent, found_parent := find_directory_by_id(app.browser_root_dir, dropped_dir.parent)
// 									idx, _ := index_of(dropped_dir_parent.sub_directories[:], dropped_dir)
// 									ordered_remove(&dropped_dir_parent.sub_directories, idx)
// 									append(&dir.sub_directories, dropped_dir^)
// 								}
// 							} else {
// 								// // Can't drop file into same dir it's from.
// 								// for file, idx in dir.files { if file.id == dropped.file_id do break handle_drop }
// 								// dropped_file, ok := find_file_by_id(app.browser_root_dir, dropped.file_id)
// 								// for file, idx in dropped_file.parent.files {
// 								// 	if file.id == dropped_file.id {
// 								// 		ordered_remove(&dropped_file.parent.files, idx)
// 								// 		break
// 								// 	}
// 								// }
// 								// dropped_file.parent = dir
// 								// append(&dir.files, dropped_file^)
// 							}
// 						} else {
// 							printfln("Tried to drop {} into folder, which can't happen", data)
// 						}
// 					}
// 				}
// 			}

// 			if !dir.collapsed {
// 				// Can see having issues with the index being in the id here.
// 				for file, i in dir.files {
// 					file_metadata := Metadata_Browser_Item {file_id = file.id}
// 					f := box_from_cache(
// 						id("{}@browser-file-{}-{}", file.name, i, file.name),
// 						{.Clickable, .Draw, .Hot_Animation,.Drag_Drop_Source, .Draw_Text},
// 						{
// 							size = Size_Fit_Text_And_Grow,
// 							padding = padding(5),
// 							margin = {left = 5 * (level + 1)},
// 							corner_radius = 4,
// 							text_justify = {.Start, .Center},
// 							color = .Surface
// 						},
// 						metadata = file_metadata, 					
// 					)
// 					file_signals := box_signals(f)

// 					if file_signals.box == ui_state.dragged_box {
// 						// Pretty inefficient if you have more a long list
// 						if !slice.contains(ui_state.dropped_data[:], file_metadata) {
// 							append(&ui_state.dropped_data, file_metadata)
// 						}
// 					}

// 					if file_signals.clicked {
// 						file_signals.box.selected = !file_signals.box.selected
// 					}

// 					if file_signals.shift_clicked {
// 						siblings := box_get_siblings(file_signals.box^, context.temp_allocator)
// 						println(siblings)
// 					}

// 					if file_signals.box.selected {
// 						file_signals.box.config.color = .Primary
// 					}
// 				}
//                 for &subdir in dir.sub_directories {
//                     create_subdirs_files(&subdir, level + 1)
//                 }
// 			}
// 		}

// 		create_subdirs_files(app.browser_root_dir, 0)
// 	}
// }

// // file_browser_delete_file :: proc(file: ^Browser_File) {
// // 	idx, found := index_of(file.parent.files[:], file)
// // 	if !found {
// // 		panicf("could not find file: {} with name: {} in it's parent", file.id, file.name)
// // 	}
// // 	ordered_remove(&file.parent.files, idx)
// // }

// // file_browser_delete_dir :: proc(dir: ^Browser_Directory) {
// // 	// We don't need to 
// // 	if dir.parent == nil {
// // 		printfln("Cannot delete the root dir: {}", dir.name)
// // 		return
// // 	}
// // 	delete(dir.files)
// // 	for &subdir in dir.sub_directories {
// // 		file_browser_delete_dir(&subdir)
// // 	}
// // 	idx, found := index_of(dir.parent.sub_directories[:], dir)
// // 	if !found {
// // 		panicf("could not find dir: {} in it's parent", dir.name)
// // 	}
// // 	ordered_remove(&dir.parent.sub_directories, idx)
// // }

// @(private="file")
// find_directory_by_id :: proc(node: ^Browser_Directory, id: int) -> (dir: ^Browser_Directory, found_it: bool) {
//     if node.id == id do return node, true
//     for &subdir in node.sub_directories {
//         if dir, found := find_directory_by_id(&subdir, id); found {
//             return dir, true
//         }
//     }
//     return nil, false
// }

// @(private="file")
// find_file_by_id :: proc(root: ^Browser_Directory, id: int) -> (file: ^Browser_File, found_it: bool) {
// 	search_dir :: proc(root: ^Browser_Directory, id: int) -> (^Browser_File, bool) { 
// 		for &file in root.files {
// 			if file.id == id {
// 				return &file, true
// 			}
// 		}
// 		return nil, false
// 	}

// 	if file, found := search_dir(root, id); found { 
// 		return file, true
// 	}

// 	for &subdir in root.sub_directories {
// 		if file, found := search_dir(&subdir, id); found { 
// 			return file, true
// 		}
// 	}

//     return nil, false
// }