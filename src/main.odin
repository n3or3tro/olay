package main
import "./playground"
import "app"
import "base:runtime"
import "core:dynlib"
import "core:fmt"
import "core:io"
import "core:mem"
import os "core:os/os2"
import "core:prof/spall"
import "core:sync"
import "core:time"
import "pool_allocator"

PROFILING :: #config(profile, false)
MODE_RELEASE :: #config(release, false)
MODE_HOT_RELOAD :: #config(hot_reload, true)

print :: fmt.print
println :: fmt.println
printf :: fmt.printf
printfln :: fmt.printfln
aprintf :: fmt.aprintf
tprintf :: fmt.tprintf
tprintfln :: fmt.aprintfln

DLL_PATH :: "build/app." + dynlib.LIBRARY_FILE_EXTENSION


App_API :: struct {
	create:            proc() -> ^app.App,
	init:              proc(),
	init_window:       proc(),
	create_gl_context: proc(),
	load_gl_procs:     proc(),
	unload_miniaudio:  proc(),
	update:            proc() -> bool,
	memory:            proc() -> rawptr,
	memory_size:       proc() -> int,
	should_run:        proc() -> bool,
	wants_reload:      proc() -> bool,
	wants_restart:     proc() -> bool,
	hot_reload:        proc(mem: rawptr) -> bool,
	shutdown:          proc(),
	last_edit:         time.Time,
	version:           int,
	lib:               dynlib.Library,
}


when PROFILING {
	spall_ctx: spall.Context
	@(thread_local)
	spall_buffer: spall.Buffer

	//------------------ Automatic profiling of every procedure:-----------------
	@(instrumentation_enter)
	spall_enter :: proc "contextless" (
		proc_address, call_site_return_address: rawptr,
		loc: runtime.Source_Code_Location,
	) {
		spall._buffer_begin(&spall_ctx, &spall_buffer, "", "", loc)
	}

	@(instrumentation_exit)
	spall_exit :: proc "contextless" (
		proc_address, call_site_return_address: rawptr,
		loc: runtime.Source_Code_Location,
	) {
		spall._buffer_end(&spall_ctx, &spall_buffer)
	}
}

api: App_API

main :: proc() {
	when MODE_HOT_RELOAD {
		run_hot_reload_mode()
	}

	// Can't figure out how to profile in hot-reload debug mode so we only profile in release mode.
	when MODE_RELEASE {
		run_release_mode()
	}
}

run_release_mode :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				for _, entry in track.allocation_map {
					fmt.eprintf("%v leaked %v bytes\n", entry.location, entry.size)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	when PROFILING {
		spall_ctx = spall.context_create("trace_test.spall")
		defer spall.context_destroy(&spall_ctx)

		backing_buffer := make([]u8, spall.BUFFER_DEFAULT_SIZE)
		defer delete(backing_buffer)

		spall_buffer = spall.buffer_create(backing_buffer, u32(sync.current_thread_id()))
		defer spall.buffer_destroy(&spall_ctx, &spall_buffer)

		spall.SCOPED_EVENT(&spall_ctx, &spall_buffer, #procedure)
	}

	app.app_create()
	app.app_init_window()
	app.app_create_gl_context()
	app.app_load_gl_procs()
	app.app_init()
	for {
		if !app.app_update() {
			break
		}
	}
	app.app_shutdown()
}

run_hot_reload_mode :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				for _, entry in track.allocation_map {
					fmt.eprintf("%v leaked %v bytes\n", entry.location, entry.size)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	load_dll()
	api.create()
	api.init_window()
	api.create_gl_context()
	api.load_gl_procs()
	api.init()
	for {
		if should_reload() {
			println("unloading miniaudio")
			api.unload_miniaudio()
			// time.sleep(time.Millisecond * 2000)
			println("done unloading miniaudio")
			old_mem := api.memory()
			load_dll()
			api.hot_reload(old_mem)
			api.load_gl_procs()
		}
		all_good := api.update()
		if !all_good {
			break
		}
		if api.wants_reload() {
		}
		if api.wants_restart() {
			app_mem := api.create()
			api.init()
			api.hot_reload(app_mem)
		}
	}
	println("running shutdown code")
	api.shutdown()
	println("shutdown code run")
}

// Calling dynlib.initiazlize_symbols, unloads the old dll, so you don't have to manually unload.
load_dll :: proc() {
	new_dll_path := tprintf("build/app_{}.dll", api.version)
	// Try multiple times since `odin build` doesn't release it's lock on the file straight away.
	for i in 0 ..< 20 {
		copy_err := os.copy_file(new_dll_path, DLL_PATH)
		if copy_err != io.Error.None {
			printfln("Failed copying {} to {}.", DLL_PATH, new_dll_path)
			time.sleep(time.Millisecond * 200)
		} else {
			printfln("Success! In copying {} to {}.", DLL_PATH, new_dll_path)
			break
		}
		if i == 19 {
			panic("Tried 19 times and still couldn't copy.")
		}
	}

	for i in 0 ..< 20 {
		count, ok := dynlib.initialize_symbols(&api, new_dll_path, "app_", "lib")
		if !ok {
			printfln("Failed copying fetchng symbols {}\n{}", new_dll_path, dynlib.last_error())
			time.sleep(time.Millisecond * 200)
		} else {
			printfln("Success fetching symbols")
			break
		}
		if i == 19 {
			panic("Tried 19 times and still couldn't copy.")
		}
	}

	edit_time, check_time_err := os.last_write_time_by_name(new_dll_path)
	if check_time_err != io.Error.None {
		panic(tprintfln("{}", check_time_err))
	}
	api.last_edit = edit_time
	api.version += 1
	printfln("Loaded DLL from {}", new_dll_path)
}

should_reload :: proc() -> bool {
	time, err := os.last_write_time_by_name(DLL_PATH)
	if err != io.Error.None {
		panic(tprintfln("{}", err))
	}
	return time._nsec > api.last_edit._nsec
}
