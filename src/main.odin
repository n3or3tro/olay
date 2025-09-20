package main
import "app"
import "core:dynlib"
import "core:fmt"
import "core:io"
import os "core:os/os2"
import "core:time"

print :: fmt.print
println :: fmt.println
printf :: fmt.printf
printfln :: fmt.printfln
aprintf :: fmt.aprintf
tprintf :: fmt.tprintf
tprintfln :: fmt.aprintfln

DLL_PATH :: "build/app." + dynlib.LIBRARY_FILE_EXTENSION


App_API :: struct {
	create:            proc() -> ^app.App_State,
	init:              proc(),
	init_window:       proc(),
	create_gl_context: proc(),
	load_gl_procs:     proc(),
	update:            proc() -> bool,
	memory:            proc() -> rawptr,
	memory_size:       proc() -> int,
	should_run:        proc() -> bool,
	wants_reload:      proc() -> bool,
	wants_restart:     proc() -> bool,
	hot_reload:        proc(mem: rawptr) -> bool,
	last_edit:         time.Time,
	version:           int,
	lib:               dynlib.Library,
}

api: App_API

main :: proc() {
	load_dll()
	api.create()
	api.init_window()
	api.create_gl_context()
	api.load_gl_procs()
	api.init()
	for {
		if should_reload() {
			println("need to reload")
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
}


load_dll :: proc() {
	// os.setwd("C:\\Users\\n3or3tro\\MySoftware\\my-projects\\olay")
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

unload_lib :: proc() {
	assert(api.lib != nil)
	ok := dynlib.unload_library(api.lib)
	if !ok {
		panic(tprintf("Could not unload lib: {}\nVersion: {}", api.lib, api.version))
	}
}
