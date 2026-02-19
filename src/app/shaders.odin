// Basic abstraction to make working with OpenGL shaders easier.
package app
import "core:fmt"
import "core:io"
import alg "core:math/linalg"
import "core:os"
import "core:strings"
import gl "vendor:OpenGL"

shader_as_cstring :: proc(path: string) -> string {
	data, err := os.read_entire_file_from_path(path, context.temp_allocator)
	assert(err == io.Error.None, "Failed to read file: ")
	return strings.clone_from_bytes(data)
}

create_shader :: proc(vshader_path: string, fshader_path: string) -> u32 {

	vertex_shader := shader_as_cstring(vshader_path)
	fragment_shader := shader_as_cstring(fshader_path)
	// // simpler way
	// pid, ok := gl.load_shaders_source(vertex_shader, fragment_shader)
	// if !ok {
	// 	fmt.eprintln("Failed to create GLSL program")
	// 	panic("Failed to create GLSL program")
	// }
	// shader_program := pid
	shader_program := gl.CreateProgram()

	vs, verr := gl.compile_shader_from_source(vertex_shader, .VERTEX_SHADER)
	fs, ferr := gl.compile_shader_from_source(fragment_shader, .FRAGMENT_SHADER)
	if !verr || !ferr {
		panic("Failed to compile vertex or fragment shader. Probably break up this check to give more information.")
	}
	check_shader_compiled(vs)
	check_shader_compiled(fs)
	// this makes it impossible to debug, pretty sure it deletes the shader code from the gpu, but the
	// ?binary? is still there. (not really sure)
	// defer gl.DeleteShader(vs)
	// defer gl.DeleteShader(fs)

	gl.AttachShader(shader_program, vs)
	gl.AttachShader(shader_program, fs)
	gl.LinkProgram(shader_program)

	// check_shader_program_linked(shader_program)
	return shader_program
}
check_shader_program_linked :: proc(shader_program: u32) -> bool {
	gl.ValidateProgram(shader_program)
	success: i32 = 3
	gl.GetProgramiv(shader_program, gl.VALIDATE_STATUS, &success)
	println("gl.false", gl.FALSE, "gl.true", gl.TRUE, "success variable:", bool(success))
	if bool(success) == gl.FALSE {
		log_size: i32 = 0
		gl.GetShaderiv(shader_program, gl.INFO_LOG_LENGTH, &log_size)
		println("log size is:", log_size)
		error_msg: string = string(make([]u8, log_size))
		panic(fmt.aprintf("shader %u didn't link correctly ", shader_program))
		// return false
	}
	println("shader linked fine")
	return true
}

check_shader_compiled :: proc(shader: u32) -> bool {
	success: i32
	gl.GetShaderiv(shader, gl.COMPILE_STATUS, &success)
	if success == 0 {
		log_size: i32 = 0
		gl.GetShaderiv(shader, gl.INFO_LOG_LENGTH, &log_size)
		println("log size is:", log_size)
		error_msg: string = string(make([]u8, log_size))
		panic(fmt.tprintf("shader %u didn't compile correctly ", shader))
		// return false
	}
	// println("shader compiled fine")
	return true
}

bind_shader :: proc(shader_program: u32) {
	gl.UseProgram(shader_program)
}

create_and_bind_shader :: proc(vshader_path: string, fshader_path: string) -> u32 {
	program := create_shader(vshader_path, fshader_path)
	bind_shader(program)
	return program
}

set_shader_bool :: proc(shader: u32, name: cstring, value: bool) {
	val: i32 = 1 if value else 0
	gl.Uniform1i(gl.GetUniformLocation(shader, name), val)
}

set_shader_u32 :: proc(shader: u32, name: cstring, value: u32) {
	gl.Uniform1ui(gl.GetUniformLocation(shader, name), value)
}

set_shader_i32 :: proc(shader: u32, name: cstring, value: i32) {
	gl.Uniform1i(gl.GetUniformLocation(shader, name), value)
}

set_shader_f32 :: proc(shader: u32, name: cstring, value: f32) {
	gl.Uniform1f(gl.GetUniformLocation(shader, name), value)
}
set_shader_matrix2 :: proc(shader: u32, name: cstring, value: ^alg.Matrix2x2f32) {
	gl.UniformMatrix2fv(gl.GetUniformLocation(shader, name), 1, gl.FALSE, raw_data(value))
}
set_shader_matrix3 :: proc(shader: u32, name: cstring, value: ^alg.Matrix3x3f32) {
	gl.UniformMatrix3fv(gl.GetUniformLocation(shader, name), 1, gl.FALSE, raw_data(value))

}
set_shader_matrix4 :: proc(shader: u32, name: cstring, value: ^alg.Matrix4x4f32) {
	gl.UniformMatrix4fv(gl.GetUniformLocation(shader, name), 1, gl.FALSE, raw_data(value))

}
set_shader_vec3 :: proc(shader: u32, name: cstring, value: Vec3_f32) {
	gl.Uniform3f(gl.GetUniformLocation(shader, name), value.x, value.y, value.z)
}
set_shader_vec2 :: proc(shader: u32, name: cstring, value: Vec2_f32) {
	gl.Uniform2f(gl.GetUniformLocation(shader, name), value.x, value.y)
}

set_shader_texture_2d :: proc(shader: u32, name: cstring, texture: [dynamic][dynamic]i32) {
	// gl.Uniform(gl.GetUniformLocation(shader, name), value.x, value.y)
}

delete_shader :: proc(shader_program: u32) {
	gl.DeleteProgram(shader_program)
}


// // how to check a uniform exists in shader
// rot := alg.matrix2_rotate_f32(1.0 * math.PI)
// uniforms := gl.get_uniforms_from_program(program)
// uniform_location := gl.GetUniformLocation(program, "rot_matrix")
// assert(uniform_location != -1)
