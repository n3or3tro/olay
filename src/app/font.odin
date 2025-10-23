package app
/*
TODO / Improvments.:
	- Figure out how to configure kb_text_shape to support ligatures and everything that is required for 
	fully proffesional text rendering. I think the only thing missing is ligature stuff.
	- Add propper memory management and cleanup.
	- Can probably pack glyphs more efficiently than just greedily storing them as we find them.
	- Check if there's any significant inefficiencies with storing 
*/

import ft "../third-party/freetype"
import "core:fmt"
import "core:mem"
import "core:os"
import str "core:strings"
import "core:unicode/utf8"
import gl "vendor:OpenGL"
import kb "vendor:kb_text_shape"

// We create this struct since the library returns the x,y co-ord of the glyph instead of
// storing it inside the glyph.
Glyph :: struct {
	glyph: kb.glyph,
	pos:   [2]f32,
}

Glyph_Cache_Record :: struct {
	atlas_x, atlas_y:     int, // Where this glyph is in the atlas.
	width, height:        int, // How much space it takes up in the atlas.
	bearing_x, bearing_y: int, // x: how far away (right usually) from 'pen' do we start drawing. y: how far up from the baseline.
	advance_x:            int, // How far to move 'pen' along after drawing this glyph.
}


Glyph_Render_Info :: struct {
	cache_record: Glyph_Cache_Record,
	pos:          Vec2_f32,
}

Font_State :: struct {
	font_size:            u32,
	// Cache for strings which have already run through the kb_text_shape machinery.
	shaped_string_cache:  map[string][dynamic]Glyph,
	// maps kb.glyph.id to a record which we can use to locate the rendered data in the bitmap cache.
	rendered_glyph_cache: map[u16]Glyph_Cache_Record,
	atlas:                struct {
		// Serves as the bitmap and cache storage for rendered glyphs.
		bitmap_buffer:          [dynamic]byte,
		// These locate the next position in bitmap.buffer we can store a rendered glyph.
		row_offset:             int, // How far along the current row.
		row_num:                int, // Which row.
		tallest_glyph_this_row: int, // Need to track this across function calls.
		row_width, num_rows:    int, // Basically the width & height of the atlas.
		pitch:                  int, // How many bytes from one row to the next.
		num_grays:              int, // freetype shit.
		pixel_mode:             int, // freetype shit.
	},
	freetype:             struct {
		lib:  ft.Library,
		face: ft.Face,
	},
	kb:                   struct {
		font: kb.font,
	},
}

when ODIN_OS == .Windows {
	font_path :: "C:\\Windows\\Fonts\\segoeui.ttf"
} else {
	font_path :: "panic"
}
// font_state: Font_State

font_init :: proc(state: ^Font_State, font_size: u32, allocator := context.allocator) {
	if font_path == "panic" {
		panic("Need to set font path for non Windows systems.")
	}
	font_file_data, ok := os.read_entire_file_from_filename(font_path, context.temp_allocator)
	assert(ok, fmt.tprintf("Failed to open and read .otf file at: {}", font_path))

	font, kb_err := kb.FontFromMemory(font_file_data, allocator)
	assert(
		kb_err == .None,
		fmt.tprintf("kb.FontFromMemory(font_file_data, context.allocator) failed with err: {}", kb_err),
	)
	state.kb.font = font

	err := ft.init_free_type(&state.freetype.lib)
	assert(err == .Ok)

	err = ft.new_face(state.freetype.lib, str.clone_to_cstring(font_path), 0, &state.freetype.face)
	assert(err == .Ok)

	// Width is set to 0 to maintain the aspect ratio.
	err = ft.set_pixel_sizes(state.freetype.face, 0, font_size)
	ui_state.font_state.font_size = font_size

	// Init the atlas which serves as the cache storage for rendered glyphs.
	state.atlas.pixel_mode = 2 // This is the default value, need to investigate.
	state.atlas.num_rows = 1024
	state.atlas.row_width = 1024
	state.atlas.pitch = 1024
	state.atlas.num_grays = 256
	state.atlas.bitmap_buffer = make([dynamic]byte, 1024 * 1024)

	assert(err == .Ok)
}

/*
This does 2 things:
1. Segments text into runs. For my use case which is an English UI I think this does basically nothing.
   I think it should result in multiple calls to add_shaped_text if there a '\n' in my string, but it
   doesn't appear to do so. 
2. Calls into add_shaped_text, providing the buffer which the shaped glyphs will be placed into
*/
font_segment_and_shape_text :: proc(font: ^kb.font, text: []rune, allocator := context.allocator) -> [dynamic]Glyph {
	state := &ui_state.font_state
	key := utf8.runes_to_string(text, context.temp_allocator)
	if key in state.shaped_string_cache {
		return state.shaped_string_cache[key]
	}
	glyph_buffer := make([dynamic]Glyph, allocator)
	cursor := kb.Cursor(.LTR)
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
			if (kb_break.Position > run_start) && (flags & {.DIRECTION, .LINE_HARD, .SCRIPT} != nil) {
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
	state.shaped_string_cache[key] = glyph_buffer
	return glyph_buffer
}

/*
	This is called during the segment_text proc, it takes a buffer, shapes the text and places the shaped text,
	inside the buffer which will ultimately be handled by the font renderer.
	The returned buffer is temporary allocated, so you need to permanently store it's contents if you want them to persist.
*/
@(private = "file")
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

	/* Font have this idea of 26.6 sizing, where the greater 26 bits are the pixel position
	and the less 6 bits are for subpixel positioning. For now, we'll just take the pixel 
	position and worry about sub pixel rendering later. */
	x_scale := i64(ui_state.font_state.freetype.face.size.metrics.x_scale)
	y_scale := i64(ui_state.font_state.freetype.face.size.metrics.y_scale)
	for &glyph, i in temp_glyph_buffer {
		// The weird integer up sizing is because we were previously overflowing
		// an i32.
		x_i32, y_i32 := kb.PositionGlyph(cursor, &glyph)
		x := i64(x_i32)
		y := i64(y_i32)
		pixel_space_x: i64 = (x * x_scale) >> 16
		final_pos := f32(pixel_space_x / 64)
		my_glyph := Glyph {
			glyph = glyph,
			// pos   = {f32((x * x_scale) >> 16) / 64, f32((y * y_scale) >> 16) / 64},
			pos   = {final_pos, f32((y * y_scale) >> 16) / 64},
		}
		append(glyph_buffer, my_glyph)
	}
}

/* 
	Returns list of structs which tell the caller how to locate the passed in glyphs in the bitmap.
	If any glyph has been seen before, it's retrieved from the cache, if not, it's put into the cache.
*/
font_get_render_info :: proc(
	glyph_buffer: [dynamic]Glyph,
	allocator := context.allocator,
) -> [dynamic]Glyph_Render_Info {
	state := &ui_state.font_state
	lib := state.freetype.lib
	face := state.freetype.face

	load_flags := ft.Load_Flags{.Render}
	result := make([dynamic]Glyph_Render_Info, len(glyph_buffer), allocator)
	for glyph, i in glyph_buffer {
		if existing_record, ok := state.rendered_glyph_cache[glyph.glyph.Id]; ok {
			glyph_render_info := Glyph_Render_Info {
				cache_record = existing_record,
				pos          = glyph.pos,
			}
			result[i] = glyph_render_info
			continue
		}
		err := ft.load_glyph(face, u32(glyph.glyph.Id), load_flags)
		assert(err == .Ok, fmt.tprintf("Failed to render glyph: {}", glyph))

		this_glyphs_bitmap := face.glyph.bitmap
		// Check if new glyph will fit on this row of the atlas
		if state.atlas.row_offset + int(this_glyphs_bitmap.width) > state.atlas.row_width {
			state.atlas.row_num += state.atlas.tallest_glyph_this_row
			state.atlas.row_offset = 0
			state.atlas.tallest_glyph_this_row = 0
		}
		new_glyph_cache_record: Glyph_Cache_Record
		atlas_row_offset_at_start := state.atlas.row_offset
		atlas_row_num_at_start := state.atlas.row_num
		// Copy glyph into atlas, row by row of the glyph.
		for curr_glyph_row in 0 ..< this_glyphs_bitmap.rows {
			dst_row_offset := (atlas_row_num_at_start + int(curr_glyph_row)) * state.atlas.pitch
			dst_offset := dst_row_offset + atlas_row_offset_at_start
			dst := mem.ptr_offset(raw_data(state.atlas.bitmap_buffer), dst_offset)

			src_offset := int(curr_glyph_row) * int(this_glyphs_bitmap.pitch)
			src := mem.ptr_offset(this_glyphs_bitmap.buffer, src_offset)

			mem.copy(dst, src, int(this_glyphs_bitmap.width))
		}


		// Metrics from FreeType.
		// We >> 6 here because FreeType uses the least-sig 6 bits as metadata
		// for subpixel rendering stuff, which we aren't implementing *yet*.
		new_glyph_cache_record.advance_x = int(face.glyph.advance.x >> 6)
		new_glyph_cache_record.bearing_x = int(face.glyph.bitmap_left)
		new_glyph_cache_record.bearing_y = int(face.glyph.bitmap_top)


		// Position and size in the atlas.
		new_glyph_cache_record.height = int(face.glyph.bitmap.rows)
		new_glyph_cache_record.width = int(face.glyph.bitmap.width)
		new_glyph_cache_record.atlas_x = atlas_row_offset_at_start
		new_glyph_cache_record.atlas_y = atlas_row_num_at_start

		if new_glyph_cache_record.height > state.atlas.tallest_glyph_this_row {
			state.atlas.tallest_glyph_this_row = new_glyph_cache_record.height
		}

		// Update metadata that determines where next to 'draw' in the atlas buffer.
		state.atlas.row_offset += int(new_glyph_cache_record.width) + 1
		if state.atlas.row_num > state.atlas.num_rows {
			// In reallity we would grow the bitmap or create another one.
			panic("we've run out of space in the glyph atlas bitmap buffer !!!")
		}

		new_glyph_render_info := Glyph_Render_Info {
			cache_record = new_glyph_cache_record,
			pos          = glyph.pos,
		}

		result[i] = new_glyph_render_info
		state.rendered_glyph_cache[glyph.glyph.Id] = new_glyph_cache_record

		// Upload new rendered glyph to bitmap atlas.
		gl.BindTexture(gl.TEXTURE_2D, ui_state.font_atlas_texture_id)
		gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
		gl.PixelStorei(gl.UNPACK_ROW_LENGTH, i32(this_glyphs_bitmap.pitch))

		// Upload new glyph's pixel data to subregion of atlas.
		gl.TexSubImage2D(
			gl.TEXTURE_2D, // target
			0, // level (mipmap)
			i32(new_glyph_cache_record.atlas_x), // xoffset
			i32(new_glyph_cache_record.atlas_y), // yoffset
			i32(this_glyphs_bitmap.width), // width of the new data
			i32(this_glyphs_bitmap.rows), // height of the new data
			gl.RED, // format
			gl.UNSIGNED_BYTE, // type
			this_glyphs_bitmap.buffer, // pointer to the pixel data
		)

		// Reset pixel store state to default (4).
		gl.PixelStorei(gl.UNPACK_ROW_LENGTH, 4)
	}
	return result
}


/* 
Takes a string, performs all the transforms neccessary to get a glyph_render_info buffer and then
calculates the length of that string if those glyphs were rendered.
*/
font_get_strings_rendered_len :: proc(text: string) -> int {

	runes := utf8.string_to_runes(text, context.temp_allocator)
	shaped_runes := font_segment_and_shape_text(&ui_state.font_state.kb.font, runes)
	rendered_glyps := font_get_render_info(shaped_runes, context.temp_allocator)
	length := font_get_glyphs_rendered_len(rendered_glyps[:])
	return length
}
font_get_glyphs_rendered_len :: proc(text: []Glyph_Render_Info) -> int {
	tot := 0
	for record in text {
		tot += record.cache_record.advance_x
	}
	return tot
}

/* 
Tells you the actual height of the tallest glyph, measured in pixels from the bottom of the glyph to the top
of the glyph.
*/
font_get_strings_rendered_height :: proc(text: string) -> int {
	runes := utf8.string_to_runes(text, context.temp_allocator)
	shaped_runes := font_segment_and_shape_text(&ui_state.font_state.kb.font, runes)
	rendered_glyphs := font_get_render_info(shaped_runes, context.temp_allocator)
	return font_get_glyphs_tallest_glyph(rendered_glyphs[:])
}
font_get_glyphs_tallest_glyph :: proc(glyph_buffer: []Glyph_Render_Info) -> int {
	highest_ascender := 0
	deepest_descender := 0
	for glyph in glyph_buffer {
		if glyph.cache_record.bearing_y > highest_ascender {
			highest_ascender = glyph.cache_record.bearing_y
		}
		curr_descent := glyph.cache_record.height - glyph.cache_record.bearing_y // Descent below baseline.
		if curr_descent > deepest_descender {
			deepest_descender = curr_descent
		}
	}
	height := highest_ascender + deepest_descender
	return height

}

font_destroy :: proc(state: ^Font_State) {
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
