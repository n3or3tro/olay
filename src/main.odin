package main
import "core:fmt"
import gl "vendor:OpenGL"
import sdl "vendor:sdl2"

App_State :: struct {
	curr_parent:       ^Box,
	parent_birthing:   bool,
	ui_state:          ^UI_State,
	mouse:             Mouse_State,
	mouse_last_frame:  Mouse_State,
	char_queue:        [32]sdl.Keycode,
	curr_chars_stored: u32,
	keys_held:         [sdl.NUM_SCANCODES]bool,
	window:            ^sdl.Window,
	wx:                int,
	wy:                int,
}

main :: proc() {
	// ui_state.parents_stack = make([dynamic]^Box)
	init_app()
	root: ^Box
	for {
		root, fine := update_app()
		if !fine {
			break
		}
		rect_render_data := make([dynamic]Rect_Render_Data, context.temp_allocator)
		collect_render_data_from_ui_tree(root, &rect_render_data)
		if !ui_state.first_frame {
			render_ui(rect_render_data)
		}
		reset_ui_state()
	}
}


init_app :: proc() -> ^App_State {
	app = new(App_State)
	init_window()
	app.ui_state = new(UI_State)
	ui_state = app.ui_state
	ui_state.parents_stack = make([dynamic]^Box)
	init_ui_state()
	// ui_state.box_cache = make(map[string]^Box)
	return app
}

init_window :: proc() -> (^sdl.Window, sdl.GLContext) {
	// sdl.Init({.AUDIO, .EVENTS, .TIMER})
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

	gl.load_up_to(4, 1, sdl.gl_set_proc_address)

	// Enable OpenGL settings
	gl.Hint(gl.LINE_SMOOTH_HINT, gl.NICEST)
	gl.Hint(gl.POLYGON_SMOOTH_HINT, gl.NICEST)
	gl.Enable(gl.LINE_SMOOTH)
	gl.Enable(gl.POLYGON_SMOOTH)
	gl.Enable(gl.MULTISAMPLE)
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
	return app.window, gl_context
}

update_app :: proc() -> (root: ^Box, exit: bool) {
	// root_rect := app.ui_state.root_rect
	if register_resize() {
		printfln("changing screen res to : {} x {}", app.wx, app.wy)
		set_shader_vec2(ui_state.quad_shader_program, "screen_res", {f32(app.wx), f32(app.wy)})
	}
	event: sdl.Event
	reset_mouse_state()
	show_context_menu: bool
	for sdl.PollEvent(&event) {
		exit, show_context_menu = handle_input(event)
		if exit {
			return nil, false
		}
	}

	root = create_ui()
	if show_context_menu {
		ui_state.context_menu.active = true
	}
	reset_renderer_data()
	sdl.GL_SwapWindow(app.window)

	free_all(context.temp_allocator)
	app.ui_state.frame_num += 1
	app.curr_chars_stored = {}
	return root, true
}

handle_input :: proc(event: sdl.Event) -> (exit, show_context_menu: bool) {
	etype := event.type
	app.mouse_last_frame = app.mouse
	if etype == .QUIT {
		exit = true
	}
	if etype == .MOUSEMOTION {
		app.mouse.last_pos = app.mouse.pos
		sdl.GetMouseState(&app.mouse.pos.x, &app.mouse.pos.y)
	}
	// We cannot just rely on querying the current 'keys held down' for typing in input fields,
	// since order matters and querying some matrix of keys down does NOT preserve input order.
	// It would work for querying if we're in the state to trigger some keyboard shortcut however.
	if etype == .KEYDOWN {
		app.char_queue[app.curr_chars_stored] = event.key.keysym.sym
		app.curr_chars_stored += 1
		app.keys_held[event.key.keysym.scancode] = true
	}
	if etype == .KEYUP {
		app.keys_held[event.key.keysym.scancode] = false
	}
	if etype == .MOUSEWHEEL {
		app.mouse.wheel.x = cast(i8)event.wheel.x
		app.mouse.wheel.y = cast(i8)event.wheel.y
	}
	if etype == .MOUSEBUTTONDOWN {
		ui_state.keyboard_mode = false
		switch event.button.button {
		case sdl.BUTTON_LEFT:
			if !app.mouse.left_pressed { 	// i.e. if left button wasn't pressed last frame
				app.mouse.drag_start = app.mouse.pos
				app.mouse.dragging = true
				app.mouse.drag_done = false
			}
			app.mouse.left_pressed = true
		case sdl.BUTTON_RIGHT:
			app.mouse.right_pressed = true
		}
	}
	if etype == .MOUSEBUTTONUP {
		switch event.button.button {
		case sdl.BUTTON_LEFT:
			if app.mouse.left_pressed {
				app.mouse.clicked = true

			}
			app.mouse.left_pressed = false
			app.mouse.drag_end = app.mouse.pos
			app.mouse.dragging = false
			app.mouse.drag_done = true
		// app.dragging_window = false
		case sdl.BUTTON_RIGHT:
			if app.mouse.right_pressed { 	// i.e. A right click was performed.
				app.mouse.right_clicked = true
				show_context_menu = true
				// ui_state.context_menu.pos = Vec2{f32(app.mouse.pos.x), f32(app.mouse.pos.y)}
			}
			app.mouse.right_pressed = false
		}
	}
	// if etype == .DROPFILE {
	// 	which, on_track := dropped_on_track()
	// 	if on_track {
	// 		printfln("file was dropped on track {}", which)
	// 	}
	// 	assert(on_track)
	// 	if on_track {
	// 		set_track_sound(event.drop.file, which)
	// 	}
	// }
	return exit, show_context_menu
}

register_resize :: proc() -> bool {
	old_width, old_height := app.wx, app.wy
	new_width, new_height: i32
	sdl.GetWindowSize(app.window, &new_width, &new_height)
	app.wx = int(new_width)
	app.wy = int(new_height)
	if old_width != app.wx || old_height != app.wy {
		gl.Viewport(0, 0, i32(app.wx), i32(app.wy))
		set_shader_vec2(ui_state.quad_shader_program, "screen_res", {f32(app.wx), f32(app.wy)})
		return true
	}
	// printfln("new window dimensions are: {} x {}", app.wx^, app.wy^)
	return false
}

reset_mouse_state :: proc() {
	app.mouse.wheel = {0, 0}
	app.mouse.last_pos = app.mouse.pos
	if app.mouse.clicked {
		// do this here because events are captured before ui is created,
		// meaning context-menu.button1.signals.click will never be set.
		printfln("last active box clicked on was: {}", ui_state.last_active_box.id_string)
		// _, clicked_on_context_menu := ui_state.last_active_box.metadata.(Context_Menu_Metadata)
		// if !clicked_on_context_menu {
		// 	ui_state.context_menu.active = false
		// }
	}
	app.mouse.clicked = false
	app.mouse.right_clicked = false
}
