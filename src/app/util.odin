package app
import "base:intrinsics"
import "core:time"
import "core:strconv"
import str "core:strings"
import "core:path/filepath"
import vmem "core:mem/virtual"
import "core:mem"
import win "core:sys/windows"


// Could definitely break due to numeric type conversions and integer division and shit.
map_range :: proc(in_min, in_max, out_min, out_max, value: $T) -> T where intrinsics.type_is_numeric(T) {
	return ((value - in_min) * (out_max - out_min) / (in_max - in_min)) + out_min
}

get_drag_delta :: proc() -> [2]int {
	return {
		app.mouse_last_frame.pos.x - app.mouse.pos.x,
		app.mouse_last_frame.pos.y - app.mouse.pos.y,
	}
}

print_ui_tree :: proc(root: ^Box, level: int) {
	for _ in 0 ..< level {
		print("  ")
	}
	printfln("{} - {} x {} - [{},{}]", root.id, root.width, root.height, root.top_left, root.bottom_right)
	for child in root.children {
		print_ui_tree(child, level + 1)
	}
}

box_height :: proc(box: Box) -> u32 {
	height := box.bottom_right.y - box.top_left.y
	assert(height >= 0)
	return u32(height)
}

box_width :: proc(box: Box) -> u32 {
	width := box.bottom_right.x - box.top_left.x
	assert(width >= 0)
	return u32(width)
}

box_data_as_string :: proc(box_data: Box_Data, allocator := context.allocator) -> string { 
	data_as_string: string
	switch data in box_data {
	case string:
		// Wasteful to clone, but it helps to simplify the API, since other variants must malloc data.
		data_as_string = str.clone(data, allocator)
	case int:
		// Would not work properly for giant numbers.
		buf := make([]byte, 32, allocator)
		data_as_string = strconv.itoa(buf[:], data)
	case f64:
		// Would not work properly for giant numbers.
		buf := make([]byte, 32, allocator)
		data_as_string = strconv.write_float(buf[:], data, 'f', 2, 64)
	}
	return data_as_string
}

// Helper to get point to the last element at the end of a dynamic array / slice.
tail :: proc(list: []$T) -> ^T{ 
	if len(list) > 0 {
		return &list[len(list) - 1]
	} else {
		return nil
	}
}

box_center :: proc(box: Box) -> [2]f32 {
    return {
        (f32(box.top_left.x) + f32(box.bottom_right.x)) / 2,
        (f32(box.top_left.y) + f32(box.bottom_right.y)) / 2
	};
}

box_get_padding_x_tot :: proc(box: Box) -> int { 
	return box.config.padding.left + box.config.padding.right
}

box_get_padding_y_tot :: proc(box: Box) -> int { 
	return box.config.padding.top + box.config.padding.bottom
}

box_get_margin_x_tot :: proc(box: Box) -> int { 
	return box.config.margin.left + box.config.margin.right
}

box_get_margin_y_tot :: proc(box: Box) -> int { 
	return box.config.margin.top + box.config.margin.bottom
}


panicf :: proc(fmt_string: string, args: ..any, newline := false) -> ! {
	panic(tprintf(fmt_string, args, newline))
}

index_of :: proc(list: []$T, item: ^T) -> (index: int, found: bool) {
	for &el, i in list { 
		if &el == item {
			return i, true
		}
	}
	return -1, false
}

// Used in our tracker when we import a directory, we only want to actually register
// those files in the dir, that are one of the audio formats we support.
// This only checks the path, to actually be certain, we need an actual robust
// parsing based solution.
is_audio_file_via_path :: proc(path: string) -> bool {
	file_extension := filepath.ext(path)
	switch file_extension {
		case ".wav", ".mp3", ".flac":
			return true
		case:
			return false
	}
}

arena_allocator_new :: proc() -> (^vmem.Arena, mem.Allocator) { 
	arena := new(vmem.Arena)
	err := vmem.arena_init_growing(arena)
	if err != nil do panicf("{}", err)
	return arena, vmem.arena_allocator(arena)
}

arena_allocator_destroy :: proc(arena: ^vmem.Arena, allocator: mem.Allocator) {
	free_all(allocator)
	free(arena)
}

boxes_children_tot_height :: proc(box: Box) -> int {
	tot := 0
	switch box.child_layout.direction { 
	case .Vertical:
		for child in box.children {
			tot += child.height
		}
	case .Horizontal:
		for child in box.children {
			tot = max(tot, child.height)
		}
	}
	return tot
}

boxes_children_tot_width :: proc(box: Box) -> int {
	tot := 0
	switch box.child_layout.direction { 
	case .Horizontal:
		for child in box.children {
			tot += child.width
		}
	case .Vertical:
		for child in box.children {
			tot = max(tot, child.width)
		}
	}
	return tot
}

vec2_f32 :: proc(d: [2]$T) -> [2]f32 
where intrinsics.type_is_numeric(T) 
{
	return {f32(d[0]), f32(d[1])}
}

vec3_f32 :: proc(d: [3]$T) -> [3]f32 
where intrinsics.type_is_numeric(T) 
{
	return {f32(d[0]), f32(d[1]), f32(d[2])}
}

vec4_f32 :: proc(d: [4]$T) -> [4]f32 
where intrinsics.type_is_numeric(T) 
{
	return {f32(d[0]), f32(d[1]), f32(d[2]), f32(d[3])}
}

accurate_sleep :: proc(duration: time.Duration) {
	when ODIN_OS == .Windows {
		handle := win.CreateWaitableTimerExW(nil, nil, 2, win.TIMER_ALL_ACCESS)
		if handle == nil do return
		defer win.CloseHandle(handle)
		due := win.LARGE_INTEGER(-i64(duration) / 100)
		win.SetWaitableTimerEx(handle, &due, 0, nil, nil, nil, 0)
		win.WaitForSingleObject(handle, win.INFINITE)
	} 
	else when ODIN_OS == .Linux { 
		time.accurate_sleep(duration)
	}
	else when ODIN_OS == .Darwin {
		time.accurate_sleep(duration)
	} else {
		panicf("Don't know how to accurately sleep on {}", ODIN_OS)
	}
}