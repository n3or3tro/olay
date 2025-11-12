package app
import "core:fmt"
import gl "vendor:OpenGL"
import sdl "vendor:sdl2"

PROFILING :: #config(profile, false)

print :: fmt.print
println :: fmt.println
printf :: fmt.printf
printfln :: fmt.printfln
aprintf :: fmt.aprintf
tprintf :: fmt.tprintf
tprintfln :: fmt.aprintfln

Browser_File :: string

Browser_Directory :: struct {
	name:           string,
	subdirectories: [dynamic]Browser_Directory,
	files:          [dynamic]Browser_File,
}

App :: struct {
	curr_parent:       ^Box,
	parent_birthing:   bool,
	ui_state:          ^UI_State,
	mouse:             Mouse_State,
	mouse_last_frame:  Mouse_State,
	char_queue:        [128]sdl.Keycode,
	curr_chars_stored: u32,
	keys_held:         [sdl.NUM_SCANCODES]bool,
	window:            ^sdl.Window,
	wx:                int,
	wy:                int,
	running:           bool,
	audio:             ^Audio_State,
	// For testing purposes we just store the path to the file, but in the future
	browser_files:     [dynamic]string,
}

Window :: sdl.Window


ui_state: ^UI_State
app: ^App


@(export)
app_create :: proc() -> ^App {
	app = new(App)
	return app
}

@(export)
app_update :: proc() -> (all_good: bool) {
	if register_resize() {
		printfln("changing screen res to : {} x {}", app.wx, app.wy)
		set_shader_vec2(ui_state.quad_shader_program, "screen_res", {f32(app.wx), f32(app.wy)})
	}
	event: sdl.Event
	reset_mouse_state()
	show_context_menu, exit := ui_state.context_menu.active, false
	for sdl.PollEvent(&event) {
		exit, show_context_menu = handle_input(event)
		if exit {
			return false
		}
	}

	root := create_ui()
	if show_context_menu {
		ui_state.context_menu.active = true
	} 
	else {
		ui_state.context_menu.active = false
	}

	rect_render_data := make([dynamic]Rect_Render_Data, context.temp_allocator)
	collect_render_data_from_ui_tree(root, &rect_render_data)
	if ui_state.frame_num > 0 {
		render_ui(rect_render_data)
	}
	delete(rect_render_data)

	sdl.GL_SwapWindow(app.window)

	reset_ui_state()
	free_all(context.temp_allocator)
	app.ui_state.frame_num += 1
	app.curr_chars_stored = {}
	// Probably need to add more stuff to clear here.
	if ui_state.changed_ui_screen {
		ui_state.last_hot_box = nil
		ui_state.last_active_box = nil
		ui_state.last_clicked_box = nil
		ui_state.right_clicked_on = nil
		ui_state.dragged_window = nil
		ui_state.mouse_down_on = nil
		// This doesn't reclaim the memory the map used to store the values. Just resets metadata
		// so that memory can be overwritten.
		clear(&ui_state.next_frame_signals)
	}
	return true
}

@(export)
app_init :: proc() -> ^App {
	app.ui_state = new(UI_State)
	ui_state = app.ui_state
	ui_state.parents_stack = make([dynamic]^Box)
	init_ui_state()
	app.audio = audio_init()
	app.running = true
	app_hot_reload(app)
	return app
}

@(export)
app_init_gl :: proc() {
}

@(export)
app_init_window :: proc() {
	sdl.Init({.EVENTS})
	window_flags := sdl.WINDOW_OPENGL | sdl.WINDOW_RESIZABLE | sdl.WINDOW_ALLOW_HIGHDPI | sdl.WINDOW_UTILITY
	app.window = sdl.CreateWindow(
		"n3or3tro-tracker",
		sdl.WINDOWPOS_UNDEFINED,
		sdl.WINDOWPOS_UNDEFINED,
		i32(WINDOW_WIDTH),
		i32(WINDOW_HEIGHT),
		window_flags,
	)
	if app.window == nil {
		panic("Failed to create window")
	}
}

@(export)
app_create_gl_context :: proc() {
	// Set OpenGL attributes after SDL initialization
	sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 4)
	sdl.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 1)
	sdl.GL_SetAttribute(.CONTEXT_PROFILE_MASK, gl.CONTEXT_CORE_PROFILE_BIT)
	sdl.GL_SetAttribute(.MULTISAMPLEBUFFERS, 1)
	sdl.GL_SetAttribute(.MULTISAMPLESAMPLES, 8)
	sdl.GL_SetAttribute(.ACCELERATED_VISUAL, 1)

	gl_context := sdl.GL_CreateContext(app.window)
	if gl_context == nil {
		panic("Failed to create OpenGL context")
	}
	sdl.GL_MakeCurrent(app.window, gl_context)

}

@(export)
app_load_gl_procs :: proc() {
	gl.load_up_to(4, 1, sdl.gl_set_proc_address)

	// Enable OpenGL settings
	gl.Hint(gl.LINE_SMOOTH_HINT, gl.NICEST)
	gl.Hint(gl.POLYGON_SMOOTH_HINT, gl.NICEST)
	gl.Enable(gl.LINE_SMOOTH)
	gl.Enable(gl.POLYGON_SMOOTH)
	gl.Enable(gl.MULTISAMPLE)
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
}

@(export)
app_memory :: proc() -> rawptr {
	return app
}

@(export)
app_memory_size :: proc() -> int {
	return size_of(App)
}

@(export)
app_should_run :: proc() -> bool {
	return app.running
}

@(export)
app_wants_reload :: proc() -> bool {
	return app.keys_held[sdl.SCANCODE_F5]
}

@(export)
app_wants_restart :: proc() -> bool {
	return app.keys_held[sdl.SCANCODE_F6]
}

@(export)
app_hot_reload :: proc(mem: rawptr) {
	app = (^App)(mem)
	ui_state = app.ui_state
	font_init(&ui_state.font_state, ui_state.font_state.font_size)
	audio_init_miniaudio(app.audio)
}

// This needs to run before we unload the DLL due to miniaudio spawning background threads that will
// continue to run after we've unloaded the DLL and crash the program.
@(export)
app_unload_miniaudio :: proc() {
	audio_uninit_miniaudio()
}

@(export)
app_shutdown :: proc() {
	free(app.ui_state.quad_vbuffer)
	free(app.ui_state.quad_vabuffer)
	// delete_dynamic_array(app.ui_state.rect_stack)
	delete_dynamic_array(app.ui_state.color_stack)
	for key, val in app.ui_state.box_cache {
		delete(key)
		free(val)
	}
	// for entry in app.ui_state.temp_boxes {
	// 	free(entry)
	// }
	delete_map(app.ui_state.box_cache)
	// delete(app.ui_state.temp_boxes)
	sdl.DestroyWindow(app.window)

	delete(ui_state.font_state.rendered_glyph_cache)
	delete(ui_state.font_state.shaped_string_cache)
	delete(ui_state.font_state.atlas.bitmap_buffer)
	// font_destroy(&ui_state.font_state)
	// delete(app.audio_state.tracks)
	// free(app.audio_state.engine)
	// for group in app.audio_state.audio_groups {
	// free(group)
	// }
	for something in ui_state.parents_stack {
		free(something)
	}
	delete(ui_state.parents_stack)
	free(app.ui_state)
	free(app)
	free_all(context.allocator)
	free_all(context.temp_allocator)
}