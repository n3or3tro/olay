/*
TODO:
	- Figure out how to configure kb_text_shape to support ligatures and everything that is required for 
	fully proffesional text rendering. I think the only thing missing is ligature stuff.
	- Add propper memory management and cleanup.
	- Can probably pack glyphs more efficiently than just greedily storing them as we find them.
	- More granular caching of shaped strings. Basically if you shape "hello" and then later shape "world", when you go to 
	shape "hello \n world" it wont be recognized as cached, the check of the cache happens before you split into runs.
*/

package playground

import ft "../third-party/freetype"
import "core:fmt"
import "core:mem"
import "core:os"
import str "core:strings"
import "core:unicode/utf8"
import "vendor:fontstash"
import kb "vendor:kb_text_shape"
import image "vendor:stb/image"

// We create this struct since the library returns the x,y co-ord of the glyph instead of
// storing it inside the glyph.
Glyph :: struct {
	glyph: kb.glyph,
	pos:   [2]i32,
}

Glyph_Cache_Record :: struct {
	atlas_x, atlas_y:     int, // Where this glyph is in the atlas.
	width, height:        int, // How much space it takes up in the atlas.
	bearing_x, bearing_y: int, // x: how far away from 'pen' do we start drawing. y: how far away from the baseline.
	advance_x:            int, // How far to move 'pen' along after drawing this glyph.
}

Font_State :: struct {
	// Tells us whether we've rendered a string before
	shaped_string_cache:  map[string][dynamic]Glyph,
	// maps kb.glyph.uid to a record which we can use to locate the rendered data in the bitmap cache.
	rendered_glyph_cache: map[u16]Glyph_Cache_Record,
	atlas:                struct {
		// Serves as the bitmap and cache storage for rendered glyphs.
		bitmap:          ft.Bitmap,
		bitmap_dynarray: [dynamic]byte,
		// These locate the next position in bitmap.buffer we can store a rendered glyph.
		next_x:          int,
		next_y:          int,
	},
	freetype:             struct {
		lib:  ft.Library,
		face: ft.Face,
	},
	kb:                   struct {
		font: kb.font,
	},
}

font: kb.font
font_path := "C:\\Windows\\Fonts\\segoeui.ttf"
state: Font_State

font_init :: proc(state: ^Font_State, allocator := context.allocator) {
	font_file_data, ok := os.read_entire_file_from_filename(font_path, context.temp_allocator)
	assert(ok, fmt.tprintf("Failed to open and read .otf file at: {}", font_path))

	font, kb_err := kb.FontFromMemory(font_file_data, allocator)
	assert(
		kb_err == .None,
		fmt.tprintf("kb.FontFromMemory(font_file_data, context.allocator) failed with mem_err: {}", kb_err),
	)
	state.kb.font = font

	err := ft.init_free_type(&state.freetype.lib)
	assert(err == .Ok)

	err = ft.new_face(state.freetype.lib, str.clone_to_cstring(font_path), 0, &state.freetype.face)
	assert(err == .Ok)

	pixel_height := 30
	// Width is set to 0 to maintain the aspect ratio.
	err = ft.set_pixel_sizes(state.freetype.face, 0, 30)

	// Init the atlas which serves as the cache storage for rendered glyphs.
	state.atlas.bitmap.pixel_mode = 2 // This is the default value, need to investigate.
	state.atlas.bitmap.rows = 1024
	state.atlas.bitmap.width = 1024
	state.atlas.bitmap.pitch = 1024
	state.atlas.bitmap.num_grays = 256
	state.atlas.bitmap_dynarray = make([dynamic]byte, 1024 * 1024)
	state.atlas.bitmap.buffer = raw_data(state.atlas.bitmap_dynarray)

	assert(err == .Ok)
}

/*
This does 2 things:
1. Segments text into runs. For my use case which is an English UI I think this does basically nothing.
   I think it should result in multiple calls to add_shaped_text if there a '\n' in my string, but it
   doesn't appear to do so. 
2. Calls into add_shaped_text, providing the buffer which the shaped glyphs will be placed into
*/
font_segment_and_shape :: proc(font: ^kb.font, text: []rune) -> [dynamic]Glyph {
	key := utf8.runes_to_string(text, context.temp_allocator)
	if key in state.shaped_string_cache {
		fmt.printfln("string {} was found in shaped cache", key)
		return state.shaped_string_cache[key]
	}
	glyph_buffer := make([dynamic]Glyph)
	cursor: kb.cursor
	direction := kb.direction.NONE
	script := kb.script.DONT_KNOW
	run_start: u32 = 0
	break_state: kb.break_state
	kb.BeginBreak(&break_state, .NONE, .NORMAL)
	for codepoint, i in text {
		kb.BreakAddCodepoint(&break_state, codepoint, 1, i == len(text) - 1)
		kb_break: kb.break_type
		for kb.Break(&break_state, &kb_break) {
			flags := kb_break.Flags
			if (kb_break.Position > run_start) && (flags & {.DIRECTION, .LINE_HARD, .LINE_SOFT, .SCRIPT} != nil) {
				run_length := kb_break.Position - run_start
				font_add_shaped_run(
					font,
					&glyph_buffer,
					&cursor,
					text[run_start:run_start + run_length],
					break_state.MainDirection,
					break_state.LastDirection,
					script,
				)
				run_start = kb_break.Position
			}
			if .DIRECTION in flags {
				direction = kb_break.Direction
				if cursor.Direction == .NONE {
					cursor = kb.Cursor(break_state.MainDirection)
				}
			}
			if .SCRIPT in flags {
				script = kb_break.Script
			}
		}
	}
	if run_start < u32(len(text)) {
		font_add_shaped_run(
			font,
			&glyph_buffer,
			&cursor,
			text[run_start:len(text)], // Shape the rest of the text
			break_state.MainDirection,
			break_state.LastDirection,
			script,
		)
	}
	// Because the segmenting code is not breaking up the input string if it finds a new line,
	// we just cache the whole string instead of runs, words, lines etc, which would probably be
	// better.
	fmt.printfln("{} was not in shaped cache, it's now been shaped and stored in the cache", text)
	state.shaped_string_cache[key] = glyph_buffer
	return glyph_buffer
}

/*
	This is called during the segment_text proc, it takes a buffer, shapes the text and places the shaped text,
	inside the buffer which will ultimately be handled by the font renderer.
	The returned buffer is temporary allocated, so you need to permanently store it's contents if you want them to persist.
*/
font_add_shaped_run :: proc(
	font: ^kb.font,
	glyph_buffer: ^[dynamic]Glyph,
	cursor: ^kb.cursor,
	text: []rune,
	main_direction: kb.direction,
	last_direction: kb.direction,
	script: kb.script,
) {
	key := utf8.runes_to_string(text, context.temp_allocator)
	// if key in state.shaped_string_cache {
	// 	return state.shaped_string_cache[key]
	// }
	fmt.printfln("adding shaped text for {}\n\n", text)
	temp_glyph_buffer := make([dynamic]kb.glyph, len(text))
	for codepoint, i in text {
		temp_glyph_buffer[i] = kb.CodepointToGlyph(font, codepoint)
	}
	state, err := kb.CreateShapeState(font, context.temp_allocator)
	assert(err == .None)

	shape_config := kb.ShapeConfig(font, script, .DONT_KNOW)
	glyph_count := u32(len(text))
	glyph_capacity := glyph_count
	for kb.Shape(
		    state,
		    &shape_config,
		    main_direction,
		    last_direction,
		    raw_data(temp_glyph_buffer),
		    &glyph_count,
		    glyph_capacity,
	    ) {
		err := resize_dynamic_array(&temp_glyph_buffer, state.RequiredGlyphCapacity)
		assert(err == .None, "resizing dynamic array of temp_glyph_buffer failed.")
		glyph_capacity = state.RequiredGlyphCapacity
	}
	// return_glyph_buffer := make([dynamic]Glyph, len(temp_glyph_buffer), context.temp_allocator)
	for &glyph, i in temp_glyph_buffer {
		x, y := kb.PositionGlyph(cursor, &glyph)
		my_glyph := new(Glyph)
		my_glyph^ = {
			glyph = glyph,
			pos   = {x, y},
		}
		append(glyph_buffer, my_glyph^)
	}
}

/* 
	Takes in glyph_buffer which is segemented and shaped text info from kb_text_shape, 
	and creates a glyph atlas. 
*/
font_get_render_info :: proc(glpyh_buffer: [dynamic]Glyph, allocator := context.allocator) -> ft.Bitmap {
	lib := state.freetype.lib
	face := state.freetype.face
	total_width: u32 = 0
	max_ascender: u32 = 0 // aka: above the baseline.
	max_descender: u32 = 0 // aka: below the baseline.
	/*
	The freetype lib only 'renders' 1 glyph at a time, so we need to create our own 'final'
	bitmap by first iterating through our glyphs and collecting metrics, this lets us create
	an appropriately sized buffer to store our visual data. Then the second time we collect the visual
	data and store it in our atlas buffer.
	We could probably gain some efficiency doing this in one pass, but for simplicity, we'll 
	just do 2 passes for now.
	*/
	// Collect metrics.
	// load_flags := ft.Load_Flags{.Bitmap_Metrics_Only}
	// for glyph in glpyh_buffer {
	// 	// We call load_glyph instead of load_char since kb_text_shape has already worked out all the correct glyphs.
	// 	err := ft.load_glyph(face, u32(glyph.glyph.Id), load_flags)
	// 	assert(err == .Ok, fmt.tprintf("Failed to glyph metrics of: {}", glyph))

	// 	total_width += u32(face.glyph.advance.x >> 6)
	// 	// curr_height := u32(face.glyph.bitmap.rows)
	// 	curr_ascent := u32(face.glyph.bitmap_top)
	// 	curr_descent := u32(face.glyph.bitmap.rows) - u32(face.glyph.bitmap_top)
	// 	if curr_ascent > max_ascender {
	// 		max_ascender = curr_ascent
	// 	}
	// 	if curr_descent > max_descender {
	// 		max_descender = curr_descent
	// 	}
	// }
	// total_height := max_ascender + max_descender
	// atlas_bitmap: ft.Bitmap
	// atlas_bitmap.width = u32(total_width)
	// atlas_bitmap.rows = u32(total_height)
	// atlas_bitmap.pitch = i32(total_width)
	// atlas_bitmap.pixel_mode = 2 // magic number :)
	// atlas_bitmap.num_grays = 256
	// atlas_buffer := make([]u8, total_width * total_height, allocator)
	// atlas_bitmap.buffer = raw_data(atlas_buffer)

	// Write pixel data to our buffer.
	load_flags := ft.Load_Flags{.Render}
	curr_pos := 0
	pen_x := 0
	for glyph in glpyh_buffer {
		err := ft.load_glyph(face, u32(glyph.glyph.Id), load_flags)
		assert(err == .Ok, fmt.tprintf("Failed to render glyph: {}", glyph))
		this_glyphs_bitmap := face.glyph.bitmap
		pen_y := max_ascender - u32(face.glyph.bitmap_top)
		/*
		Due to freetype fuckery, you must copy the src bitmap row by row instead of just
		memcopy'ing curr_glyph.bitmap.buffer into atlas_buffer in one fell swoop. 
		Something about pitch != width due to padding and maybe other reasons... idk, but this works :).
		*/
		for y in 0 ..< this_glyphs_bitmap.rows {
			dst_offset := (pen_y + y) * total_width + u32(pen_x + int(face.glyph.bitmap_left))
			dst := mem.ptr_offset(raw_data(atlas_buffer), dst_offset)
			src_offset := int(y) * int(this_glyphs_bitmap.pitch)
			src := mem.ptr_offset(this_glyphs_bitmap.buffer, src_offset)
			mem.copy(dst, src, int(this_glyphs_bitmap.width))
		}
		pen_x += int(face.glyph.advance.x >> 6)
	}
	return atlas_bitmap
}

font_render_text :: proc(text: string) {
	shaped_glyphs := font_segment_and_shape(&state.kb.font, utf8.string_to_runes(text))
	glyphs_render_info := font_get_render_info()
}

main :: proc() {
	font_init(&state, context.allocator)
	// runes := utf8.string_to_runes("I really am that nigga. I really do render font\n\f Like a motherfucker")
	// glyphs := font_segment_and_shape(&state.kb.font, runes)
	font_render_text("hello there")
	font_render_text("hello there")
	font_render_text("hello\nthere")
	font_render_text("hello")
	font_render_text("hello\nthere")
	// bitmap := font_create_atlas(glyphs)
	// fmt.println(bitmap)
	// image.write_png("./font_output.png", i32(bitmap.width), i32(bitmap.rows), 1, bitmap.buffer, bitmap.pitch)
}

destroy_font :: proc(state: ^Font_State) {
	ft.done_free_type(state.freetype.lib)
	ft.done_face(state.freetype.face)
}

/*
Things I considered but didn't do:
- Basically a 1d atlas that is as high as the tallest glyph
	- Essentialy the GPU ecosystem is highly geared to working with more squared
	shaped bitmaps, for example it pulls in neighbour pixels when sampling some texture,
	so it's probably wiser to have a more square texture.
*/
