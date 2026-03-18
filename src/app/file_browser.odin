package app

import "core:sort"
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
import ma "vendor:miniaudio"
import "core:sync"
import sdl "vendor:sdl2"
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

browser_dir_free :: proc(dir: ^Browser_Directory) {
	for sub in dir.sub_directories {
		browser_dir_free(sub)
	}
	for file in dir.files {
		delete(file.name)
		free(file)
	}
	delete(dir.files)
	delete(dir.sub_directories)
	delete(dir.name)
	delete(dir.path)
	free(dir)
}

@(private="file")
add_dirs_to_browser :: proc(parent: ^Browser_Directory, dirs: []string) {
	arena, scratch := arena_allocator_new("file-browser-add-dirs")
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
	child_container({}, {direction = .Vertical})
	{
		file_browser_container := child_container(
			{
				size = {{.Fixed, 500}, {.Fixed, f32(app.wy) - TOPBAR_HEIGHT - 60}},
				color = .Primary_Container,
				padding = {bottom = 5},
				z_index = 100,
			},
			{direction = .Vertical},
			"file-browser-container",
			{.Draw, .Frosted},
		)
		top_menu: {
			child_container(
				{
					size = Size_Fit_Children_And_Grow, 
					padding = padding(10), 
					color = .Tertiary,
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
					border = border(1),
					color = .Tertiary
				},
				.Generic_One_Line,
				&ui_state.browser_search_term,
				extra_flags = {.Glow, .Frosted}
			)
			hori: {
				child_container(
					{size = Size_Fit_Children_And_Grow, color = .Red_600},
					{direction = .Horizontal},
				)
				btn_config := Box_Config {
					color         = .Primary,
					border        = border(3),
					padding       = {left = 15, right = 15, top = 20, bottom = 20},
					size = {{.Fit_Text_And_Grow, 1}, {.Fit_Text_And_Grow, 1}},
					max_size = {app.wx, 40},
					corner_radius = 0,
				}
				extra_flags := Box_Flags{.Frosted}
				add_folder := icon_button(Icon_Add_Folder, "Add folder", btn_config, extra_flags=extra_flags)
				sort_button: Box_Signals
				if ui_state.browser_sort_ascending { 
					sort_button =  icon_button(Icon_Sort_Alpha_Down, "Alphabetical descending", btn_config, extra_flags=extra_flags)
				} else {
					sort_button =  icon_button(Icon_Sort_Alpha_Up, "Alphabetical ascending", btn_config, extra_flags=extra_flags)
				}
				if sort_button.clicked { 
					ui_state.browser_sort_ascending = !ui_state.browser_sort_ascending
				}

				if add_folder.clicked {
					arena, scratch := arena_allocator_new("file-browser-add-folder")
					defer arena_allocator_destroy(arena, scratch)
					multiselect := true
					dirs, ok := folder_dialog_windows(scratch)
					if !ok {
						println(
							"File dialogue failure, either:\n- Failed to open dialogue.\n- Failed to return files from dialogue.",
						)
					}
					// Filter out directories that already exist as top-level entries.
					new_dirs := make([dynamic]string, scratch)
					for dir in dirs {
						already_exists := false
						for existing in app.browser_root_dir.sub_directories {
							if existing.path == dir {
								already_exists = true
								break
							}
						}
						if !already_exists {
							append(&new_dirs, dir)
						}
					}
					if len(new_dirs) > 0 {
						add_dirs_to_browser(app.browser_root_dir, new_dirs[:])
						file_browser_write_to_disk()
					}
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
							.Active_Animation, .Hot_Animation, .Draw_Text, .Scrollable
						},
						{
							border = border(1),
							color = app.browser_selected_dir != dir ? .Secondary_Container : .Warning,
							size = Size_Fit_Text_And_Grow,
							text_justify = {.Start, .Center},
							padding = padding(5),
						},
						dir.name,
						metadata = Metadata_Browser_Item{dir = dir},
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
						file_box := box_from_cache(
							{.Clickable, .Hot_Animation, .Drag_Drop_Source, .Draw_Text, .Scrollable},
							{
								size = Size_Fit_Text_And_Grow,
								padding = padding(5),
								margin = {left = 15 * (level + 1)},
								corner_radius = 4,
								text_justify = {.Start, .Center},
								text_color = .Slate_100,
								min_size = {0, 27}
							},
							file.name,
						)
						file_signals := box_signals(file_box)
						if file_signals.hovering && !app.mouse.left_pressed{ 
							file_box.config.font_size += 3
							file_box.config.color = .Slate_950
							file_box.flags += {.Draw}
						}

						if file_signals.box == ui_state.dragged_box {
							// Pretty inefficient if you have a long list
							if !slice.contains(ui_state.dropped_data[:], file^) {
								append(&ui_state.dropped_data, file^)
							}
						}
						play_demo: if file_signals.clicked { 
							full_path, err := filepath.join({file.parent.path, file.name}, context.temp_allocator)
							cpath := str.clone_to_cstring(full_path, context.temp_allocator)
							assert(err == .None)
							ma.sound_uninit(&app.audio.browser_preview_sound)
							res := ma.sound_init_from_file(app.audio.engine, cpath, {}, app.audio.audio_groups[0], nil, &app.audio.browser_preview_sound)
							if res != .SUCCESS {
								printfln("{}", res)
								break play_demo
							}
							// assert(res == .SUCCESS, tprintf("{}", res))
							sound_end_proc: ma.sound_end_proc = proc "c" (user_data: rawptr, sound: ^ma.sound) {
								sync.atomic_store(&app.audio.browser_preview_playing, false)
								// Ensure UI wakes up if it's gone to sleep, not sure if it's risky to do this from the
								// miniaudio thread.
								e: sdl.Event = {type = .USEREVENT}
								sdl.PushEvent(&e)
								// app.audio.browser_preview_sound = {}
							}
							ma.sound_set_end_callback(&app.audio.browser_preview_sound, sound_end_proc, nil)
							app.audio.browser_preview_sound_pcm_data, _ = sound_get_pcm_data(&app.audio.browser_preview_sound) // This will leak mem.
							ma.sound_seek_to_pcm_frame(&app.audio.browser_preview_sound, 0)
							ma.sound_start(&app.audio.browser_preview_sound)
							app.audio.browser_preview_playing = true
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
					max_size = {800, app.wy},
					color = .Warning,
				},
				{
					direction = .Vertical
				},
				"browser-main-container",
				{.Scrollable, .Scrollbar}
			)
			// Create each child of the root at the top level, this is because we don't actually
			// want to render / interact with the root.
			if len(app.browser_root_dir.sub_directories) == 0 {
				text(
					"No folders / files added, add a folder to add sounds to the project",
					{
						size = Size_Fit_Text_And_Grow,
						padding = padding(15),
						text_justify = {.Center, .Center},
						text_color = .Slate_100,
					},
				)
			} else {
				for &subdir in app.browser_root_dir.sub_directories{
					create_subdirs_files(subdir, 0, ui_state.browser_search_term)
				}
			}
		}
	}
	box_from_cache(
		{.Draw, .Frosted, .Glow, .Clickable, .Draw_Text},
		{
			size = {{.Fixed, 500}, {.Fixed, 60}},
			z_index = 800,
			color = .Red_600,
		},
		metadata = Metadata_Browser_Waveform{sound=&app.audio.browser_preview_sound},
	)
}

file_browser_write_to_disk :: proc() {
	arena, scratch := arena_allocator_new("file-browser-write-to-disk")
	defer arena_allocator_destroy(arena, scratch)

	f, err := os.open(BROWSER_SAVE_FILE, {.Write, .Create, .Trunc}, {.Read_User, .Write_User})
	assert(err == io.Error.None , tprintf("Failed to open {} for writing\nGot err: {}", BROWSER_SAVE_FILE, err))
	defer os.close(f)

	for child, i in app.browser_root_dir.sub_directories {
		os.write_string(f, child.path)
		if i < len(app.browser_root_dir.sub_directories) - 1 {
			os.write_string(f, "\n")
		}
	}
}

// Assumed to run only at program startup.
file_browser_read_from_disk :: proc() {
	arena, scratch := arena_allocator_new("file-browser-read-from-disk")
	defer arena_allocator_destroy(arena, scratch)

	data, err := os.read_entire_file_from_path(BROWSER_SAVE_FILE, allocator = scratch)
	if err != io.Error.None {
		printf("Failed to open {} for reading\nGot err: {}", BROWSER_SAVE_FILE, err)
		return
	} 

	data_as_str, err2 := str.clone_from_bytes(data, scratch)
	assert(err2 == .None)

	if len(data_as_str) == 0 do return

	lines := str.split_lines(data_as_str, scratch)

	add_dirs_to_browser(app.browser_root_dir, lines)
}