// Functions to clean up the handling of OpenGL buffers and associated data.
package app
import "core:fmt"
import "core:math/rand"
import gl "vendor:OpenGL"

gl_clear_error :: proc() {
	for gl.GetError() != gl.NO_ERROR {
	}
}

gl_check_error :: proc() {
	for err := gl.GetError(); err != gl.NO_ERROR; err = gl.GetError() {
		println("OpenGL Error: ", err)
	}
}

create_vbuffer :: proc(buffer: ^u32, vertex_positions: [^]f32, size: int) {
	gl.GenBuffers(1, buffer)
	gl.BindBuffer(gl.ARRAY_BUFFER, buffer^)
	// for some reason this isn't working unless I provide a literal size
	gl.BufferData(gl.ARRAY_BUFFER, size, nil, gl.DYNAMIC_DRAW)
}

populate_vbuffer :: proc(buffer: ^u32, offset: u32, data: [^]f32, size: u32) {
	gl.BufferSubData(gl.ARRAY_BUFFER, cast(int)offset, cast(int)size, data)
}

populate_vbuffer_with_rects :: proc(buffer: ^u32, offset: u32, data: [^]Rect_Render_Data, size: u32) {
	gl.BufferSubData(gl.ARRAY_BUFFER, cast(int)offset, cast(int)size, data)
}

bind_vbuffer :: proc(buffer: u32) {
	gl.BindBuffer(gl.ARRAY_BUFFER, buffer)
}

delete_vbuffer :: proc(buffer: ^u32) {
	gl.DeleteBuffers(1, buffer)
}

enable_layout :: proc(which: u32 = 0) {
	gl.EnableVertexAttribArray(which)
}
disable_layout :: proc(which: u32 = 0) {
	gl.DisableVertexAttribArray(which)
}

// vertex_element_type is kinda weird, should probs fix.
layout_vbuffer :: proc(
	index: u32 = 0,
	elements_per_vertex: i32,
	vertex_element_type: u32,
	normalize: bool,
	bytes_to_next_value: i32,
	offset_pointer: uintptr,
) {
	gl.VertexAttribPointer(
		index,
		elements_per_vertex,
		vertex_element_type,
		normalize,
		bytes_to_next_value,
		offset_pointer,
	)
}

unbind_vbuffer :: proc() {
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
}

// pretty sure gl.GenBuffers must be called before you create an index buffer.
create_ibuffer :: proc(buffer: ^u32, indices: rawptr, n_indices: u32) {
	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, buffer^)
	gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, cast(int)(n_indices * size_of(u32)), nil, gl.STATIC_DRAW)
}

populate_ibuffer :: proc(buffer: ^u32, indices: [^]u32, n_indices: u32) {
	// gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, buffer^)
	current_buffer: i32
	gl.GetIntegerv(gl.ELEMENT_ARRAY_BUFFER_BINDING, &current_buffer)
	assert(current_buffer == i32(buffer^), "Buffer is not bound!")
	gl.BufferSubData(gl.ELEMENT_ARRAY_BUFFER, 0, cast(int)(n_indices * size_of(u32)), indices)
}

bind_ibuffer :: proc(buffer: u32) {
	gl.BindBuffer(gl.ELEMENT_ARRAY_BARRIER_BIT, buffer)
}

unbind_ibuffer :: proc() {
	gl.BindBuffer(gl.ELEMENT_ARRAY_BARRIER_BIT, 0)
}

delete_ibuffer :: proc(buffer: ^u32) {
	gl.DeleteBuffers(1, buffer)
}

// vertices_of_box :: proc(box: Box) -> [4]Vertex {
// 	r := rect_from_points(box.rect.top_left, box.rect.bottom_right)
// 	rect := MyRect {
// 		w = cast(f32)r.w,
// 		h = cast(f32)r.h,
// 		x = cast(f32)r.x,
// 		y = cast(f32)r.y,
// 	}
// 	top_left: Vec2 = {rect.x, rect.y}
// 	bottom_left: Vec2 = {rect.x, rect.y + rect.h}
// 	bottom_right: Vec2 = {rect.x + rect.w, rect.y + rect.h}
// 	top_right: Vec2 = {rect.x + rect.w, rect.y}

// 	v1 := Vertex{top_left, bottom_right, box.color}
// 	v2 := Vertex {
// 		pos   = bottom_left,
// 		color = {box.color.r / 8, box.color.g / 8, box.color.b / 8, box.color.a},
// 	}
// 	v3 := Vertex {
// 		pos   = bottom_right,
// 		color = {box.color.r / 8, box.color.g / 8, box.color.b / 8, box.color.a},
// 	}
// 	v4 := Vertex {
// 		pos   = top_right,
// 		color = box.color,
// 	}
// 	return [4]Vertex{v1, v2, v3, v4}
// }

// raw_vertex_data :: proc(vertices: [4]Vertex) -> [size_of(Vertex)]f32 {
// 	return {}
// }

// this probably doesn't need to be dynamic? but I guess we can't predict the size
// so maybe it does.
// generate_indices :: proc(n_quads: u32) -> [dynamic]u32 {
// 	indices: [dynamic]u32
// 	for i: u32 = 0; i < n_quads; i += 1 {
// 		start := i * 4
// 		append(&indices, start, start + 1, start + 2, start + 2, start + 3, start + 0)
// 	}
// 	return indices
// }

print_vertices :: proc(vertices: [6 * 4]f32) {
	i := 0
	for (i < 24) {
		j := 0
		for (j < 6) {
			fmt.print(vertices[i + j])
			fmt.print(" ")
			j += 1
		}
		println("\n")
		i += 6
	}
}
