package app
import "core:fmt"
import "core:math"
import "core:sync"
import "vendor:kb_text_shape"
import "core:thread"
import "core:time"
import gl "vendor:OpenGL"
import sdl "vendor:sdl2"
import str "core:strings"
import "core:sys/windows"

PROFILING :: #config(profile, false)

print 	  :: fmt.print
println   :: fmt.println
printf 	  :: fmt.printf
printfln  :: fmt.printfln
aprintf	  :: fmt.aprintf
tprintf	  :: fmt.tprintf
tprintfln :: fmt.aprintfln

App :: struct {
	char_queue:        		  [128]sdl.Keycode,
	keys_held:         		  [sdl.NUM_SCANCODES]bool,
	mouse:             		  Mouse_State,
	mouse_last_frame:  		  Mouse_State,
	ui_state:          		  ^UI_State,
	window:            		  ^sdl.Window,
	curr_chars_stored: 		  u32,
	wx:                		  int,
	wy:                		  int,
	audio:             		  ^Audio_State,
	browser_root_dir:  		  ^Browser_Directory,
	browser_selected_dir:     ^Browser_Directory,
	running:           		  bool,
	windows_com_handle:		  windows.HRESULT,
	ui_refresh_thread: 		  ^thread.Thread,
	audio_update_thread: 	  ^thread.Thread
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
	if ui_state.frames_since_sleep >= 5 do ui_state.frames_since_sleep = 0
	ui_state.event_wait_timeout = 1_000_000_000
	dt_ms := (f64(time.now()._nsec) / 1_000_000) - ui_state.prev_frame_start_ms
	dt_ms = min(dt_ms, 100)
	ui_state.prev_frame_start_ms = f64(time.now()._nsec) / 1_000_000
	animation_update_all(dt_ms / 1_000)
	start := time.now()._nsec
	if register_resize() {
		printfln("changing screen res to : {} x {}", app.wx, app.wy)
		set_shader_vec2(ui_state.quad_shader_program, "screen_res", {f32(app.wx), f32(app.wy)})
	}
	event: sdl.Event
	reset_mouse_state()
	show_context_menu, exit := ui_state.context_menu.active, false
	// Sleep until an event arrives and unblocks us.
	if (ui_state.frames_since_sleep == 0 && sdl.WaitEventTimeout(&event, i32(ui_state.event_wait_timeout * 1_000))) || 
	ui_state.frame_num < 5 
	{
		exit, show_context_menu = handle_input(event)
		if exit {
			return false
		}
	}

	// Poll for any other events that arrived with the unblocking event.
	for sdl.PollEvent(&event) {
		exit, show_context_menu = handle_input(event)
		if exit {
			return false
		}
	}

	// Handle keybaord shortcuts
	handle_keyboard_shortcuts()
	root := create_ui()

	if show_context_menu {
		ui_state.context_menu.active = true
	} 
	else {
		ui_state.context_menu.active = false
	}

	render_start := time.now()._nsec
	rect_render_data := make([dynamic]Rect_Render_Data, context.temp_allocator)
	collect_render_data_from_ui_tree(&rect_render_data)
	if ui_state.frame_num > 0 {
		render_ui(rect_render_data)
	}
	render_end := time.now()._nsec
	// printfln("rendering the UI took: {}", f64(render_end - render_start) / 1_000_000)

	sdl.GL_SwapWindow(app.window)

	// We do this here instead of inside 'handle_input' because handle_input runs at the start of the frame,
	// and this data must live till the end of the frame.
	if !app.mouse.left_pressed {
		ui_state.dragged_box = nil
		// Might want to shrink it if we're dragging around huge data one time,
		// and then never again...
		clear(&ui_state.dropped_data)
	}
	
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
		ui_state.dragged_box = nil
		ui_state.mouse_down_on = nil
		// This doesn't reclaim the memory the map used to store the values. 
		// Just resets the map's metadata so that memory can be overwritten.
		clear(&ui_state.frame_signals)
	}

	// Calculate how long this frame took and sleep until it's time for the next frame.
	// max_frame_time_ns: f64 = 1_000_000 * 200 
	max_frame_time_ns: f64 = 1_000_000 * 8.3333 
	// max_frame_time_ns: f64 = 1_000_000 * 16.6666
	frame_time := f64(time.now()._nsec - start)
	time_to_wait := time.Duration(max_frame_time_ns - frame_time)

	// end := time.now()._nsec
	// total_frame_time_ns := f64(end - start)
	// printfln("app_update() took {} ms", total_frame_time_ns / 1_000_000)

	if time_to_wait > 0 {
		time.accurate_sleep(time_to_wait)
	}
	ui_state.frames_since_sleep += 1
	return true
}

@(export)
app_init :: proc(first_run := true) -> ^App {
	app.ui_state = new(UI_State)
	ui_state = app.ui_state
	ui_state.parents_stack = make([dynamic]^Box)
	init_ui_state()
	root_dir := new(Browser_Directory)
	root_dir.name = str.clone("Root dir")
	app.browser_selected_dir = root_dir
	app.browser_root_dir     = root_dir

	font_init(&ui_state.font_state, ui_state.font_state.font_size)

	file_browser_read_from_disk()
	app.audio = audio_init()
	audio_init_miniaudio(app.audio)
	app.running = true

	app.ui_refresh_thread   = thread.create_and_start(ui_refresh_thread_proc, priority = .High)
	app.audio_update_thread = thread.create_and_start(audio_thread_timing_proc, priority = .High)

	// This a per thread thing that will persist across hot reloads, so we set it up once only
	when ODIN_OS == .Windows {
		if first_run {
			hr := windows.CoInitializeEx(nil, windows.COINIT.APARTMENTTHREADED)
			if !windows.SUCCEEDED(hr) {
				panic("failed 1")
			}
			app.windows_com_handle = hr
		}
	}
	return app
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
// Trigger a build of the DLL and hot reload it in, keeping existing state.
app_wants_reload :: proc() -> bool {
	return app.keys_held[sdl.SCANCODE_F5]
}

@(export)
// I.e. fully reset state as if you just launched the app.
// Won't trigger a rebuild of the DLL.
app_wants_restart :: proc() -> bool {
	return app.keys_held[sdl.SCANCODE_F1]
}


@(export)
app_hot_reload :: proc(mem: rawptr) {
	app = (^App)(mem)
	ui_state = app.ui_state
	font_init(&ui_state.font_state, ui_state.font_state.font_size)
	audio_init_miniaudio(app.audio)
	sync.atomic_store(&app.audio.exit_timing_thread, false)
	app.ui_refresh_thread   = thread.create_and_start(ui_refresh_thread_proc, priority = .High)
	app.audio_update_thread = thread.create_and_start(audio_thread_timing_proc, priority = .High)
}

@(export)
app_reload_colors :: proc(mem: rawptr, color_file_path: string) { 
	app = (^App)(mem)
	delete(app.ui_state.dark_theme)
	app.ui_state.dark_theme = parse_json_token_color_mapping(color_file_path)
}

// This needs to run before we unload the DLL due to miniaudio spawning background threads that will
// continue to run after we've unloaded the DLL and crash the program.
@(export)
app_unload_miniaudio :: proc() {
	sync.atomic_store(&app.audio.exit_timing_thread, true)
	sync.cond_broadcast(&app.audio.playing_cond)
	// Wait for audio timing thread to pickup that it should terminate.
	thread.join_multiple(app.ui_refresh_thread, app.audio_update_thread)
	audio_uninit_miniaudio()
}

@(export)
app_delete :: proc() {

}

@(export)
app_reset_state :: proc() {
	app.char_queue 		  = {}
	app.curr_chars_stored = 0
	app.keys_held  		  = {}
	app.mouse 	   		  = {}
	app.mouse_last_frame  = {}

	free(app.ui_state.quad_vbuffer)
	free(app.ui_state.quad_vabuffer)
	delete_dynamic_array(app.ui_state.color_stack)
	for key, val in app.ui_state.box_cache {
		delete(key)
		if str, ok := val.data.(string); ok { 
			delete(str)
		}
		delete(val.children)
		free(val)
	}
	delete_map(app.ui_state.box_cache)

	delete(app.ui_state.font_state.rendered_glyph_cache)
	delete(app.ui_state.font_state.shaped_string_cache)
	delete(app.ui_state.font_state.atlas.bitmap_buffer)
	kb_text_shape.FreeFont(&app.ui_state.font_state.kb.font, context.allocator)
	for parent in app.ui_state.parents_stack {
		free(parent)
	}
	delete(app.ui_state.parents_stack)
	delete(app.ui_state.dark_theme)
	free(app.ui_state)

	// Audio state maybe needs to be cleared..
	app.browser_root_dir = nil
	app.browser_selected_dir = nil
}

@(export)
app_shutdown :: proc() {
	when ODIN_OS == .Windows {
		windows.CoUninitialize()
	}
	free(app.ui_state.quad_vbuffer)
	free(app.ui_state.quad_vabuffer)
	delete_dynamic_array(app.ui_state.color_stack)
	for key, val in app.ui_state.box_cache {
		delete(key)
		if str, ok := val.data.(string); ok { 
			delete(str)
		}
		delete(val.children)
		free(val)
	}
	delete_map(app.ui_state.box_cache)

	delete(ui_state.font_state.rendered_glyph_cache)
	delete(ui_state.font_state.shaped_string_cache)
	delete(ui_state.font_state.atlas.bitmap_buffer)
	kb_text_shape.FreeFont(&ui_state.font_state.kb.font, context.allocator)
	for parent in ui_state.parents_stack {
		free(parent)
	}
	delete(ui_state.parents_stack)
	delete(ui_state.dark_theme)
	free(app.ui_state)
	free(app)
	// free_all(context.allocator)
	free_all(context.temp_allocator)
}

// This must be called after we create teh UI and give widgets the chance to consume key events.
handle_keyboard_shortcuts :: proc() {
	n_handled :u32= 0
	for i in 0 ..< app.curr_chars_stored {
		curr_ch := app.char_queue[i]
		#partial switch curr_ch {
		case .SPACE:
			if app.audio.playing {
				audio_transport_pause()
			} else {
				audio_transport_play()
			}
			n_handled += 1
		case .ESCAPE:
			ui_state.context_menu.active = false
		case .R:
			audio_transport_reset()
		case .M:
			ui_state.show_mixer = !ui_state.show_mixer
		}
	}
	app.curr_chars_stored -= n_handled
}