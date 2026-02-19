package app

import "core:bytes"
import "core:io"
import "core:mem"
import "core:math/rand"
import "core:slice"
import str "core:strings"
import "core:os"
import vmem "core:mem/virtual"
import "core:path/filepath"
import "core:encoding/json"
// import q "core:container/queue"
BROWSER_SAVE_FILE :: "./file-browser.txt"

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
	// Not the most performant in terms of cache access patterns to store pointers,
	// but other approaches are a headache for not much gain.
	sub_directories: [dynamic]^Browser_Directory,
	files:           [dynamic]^Browser_File,
	selected_files:  [2]int, // [start ..= end]
	collapsed:       bool,
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
		new_dir  := new(Browser_Directory)
		new_dir^  =   Browser_Directory{
			name   = str.clone(dir_name),
			parent = parent, 
			id     = int(rand.int63()),
			path   = str.clone(dir)
		}


		append(&parent.sub_directories, new_dir)

		files, d_err := os.read_dir(handle, 100, scratch)
		if d_err != nil do panicf("{}", d_err)

		audio_files := make([dynamic]^Browser_File, scratch)
		subdirs := make([dynamic]string, scratch)

		for f in files {
			if f.type == .Directory {
				append(&subdirs, f.fullpath)
			}
			if !is_audio_file_via_path(f.name) do continue

			new_file := new(Browser_File)
			new_file^ =  Browser_File {
				id = int(rand.int63()),
				name = str.clone(f.name),
				parent = new_dir,
			}
			append(&audio_files, new_file)
		}

		if len(audio_files) > 0 {
			// This will certainly break, we need something like persistent reliable handles, not pointers
			// into a dyn array which will certainly resize and be moved in mem.
			for &file in audio_files { 
				file.parent = new_dir
				append(&new_dir.files, file)
			}
			add_dirs_to_browser(new_dir, subdirs[:])
		} else if len(subdirs) > 0 {
			add_dirs_to_browser(new_dir, subdirs[:])
		} else {
			// Kinda jank to append then delete like this.
			delete(new_dir.name)
			pop(&parent.sub_directories)
		}
	}
}

file_browser_menu :: proc(allocator: mem.Allocator) {
	child_container(
		{
			size = {{.Fit_Children, 1}, {.Fit_Children, 1}},
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
				size = Size_Fit_Children_And_Grow, 
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
				size = {{.Grow, 1}, {.Fixed, 30}}, 
				padding = {left = 4, right = 4},
				border = 1
			},
			.Generic_One_Line,
		)
		// Quick hack coz I fucked up setting search_bar.box.data somewhere
		// along the line. This really shoudl just be a one liner where we are
		// certain that box.data always holds a valid string.
		if search_bar.box.data == nil {
			search_term = ""
		} else {
			if val, ok := search_bar.box.data.(string); ok {
				search_term = val
			} else {
				search_term = ""	
			}
		}
		hori: {
			child_container(
				{size = Size_Fit_Children},
				{direction = .Horizontal},
			)
			btn_config := Box_Config {
				color         = .Secondary,
				border        = 3,
				padding       = {10, 10, 10, 10},
				size = {{.Fit_Text, 1}, {.Fit_Text_And_Grow, 1}},
				corner_radius = 0,
			}
			add_folder := text_button("Add Folder", btn_config)
			sort_files := text_button("Sort", btn_config)
			flip 	   := text_button("Flip", btn_config)
			save 	   := text_button("Save", btn_config)
			open_file  := text_button("Open", btn_config)

			if save.clicked { 
				file_browser_write_to_disk()
			}

			if open_file.clicked {
				file_browser_read_from_disk()
			}

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
					{size = Size_Fit_Children_And_Grow, padding = {left = 15 * level}},
					{gap_horizontal = 1},
				)
				arrow_box := text_button(
					dir.collapsed ? ">" : "v",
					{
						size = {{.Fit_Text, 1}, {.Fit_Text_And_Grow, 1}},
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
						size = Size_Fit_Text_And_Grow,
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
							size = Size_Fit_Text_And_Grow,
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
						if !slice.contains(ui_state.dropped_data[:], file^) {
							append(&ui_state.dropped_data, file^)
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
					create_subdirs_files(subdir, level + 1, search_term)
				}
			}
		}

		child_container(
			{
				overflow_y = .Scroll,
				overflow_x = .Scroll,
				// size = {{.Percent, 1}, {.Percent, 1}},
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
			create_subdirs_files(subdir, 0, search_term)
		}
	}
}

file_browser_write_to_disk :: proc() {
	arena, scratch := arena_allocator_new()
	defer arena_allocator_destroy(arena, scratch)

	f, err := os.open(BROWSER_SAVE_FILE, {.Write, .Create, .Read}, {.Read_User, .Write_User})
	assert(err == io.Error.None , tprintf("Failed to open {} for writing\nGot err: {}", BROWSER_SAVE_FILE, err))
	defer os.close(f)

	for child in app.browser_root_dir.sub_directories {
		os.write_string(f, child.path)
	}
}

// Assumed to run only at program startup.
file_browser_read_from_disk :: proc() {
	arena, scratch := arena_allocator_new()
	defer arena_allocator_destroy(arena, scratch)

	data, err := os.read_entire_file_from_path(BROWSER_SAVE_FILE, allocator = scratch)
	assert(err == io.Error.None , tprintf("Failed to open {} for reading\nGot err: {}", BROWSER_SAVE_FILE, err))

	data_as_str, err2 := str.clone_from_bytes(data, scratch)
	assert(err2 == .None)

	lines := str.split_lines(data_as_str, scratch)

	add_dirs_to_browser(app.browser_root_dir, lines)
}