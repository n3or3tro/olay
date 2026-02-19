package tests

import app "../"
import "core:math"
import "core:mem"
import "core:testing"

// ============================================================================
// Test Struct Definitions
//
// These mirror the real audio engine structs (EQ_Band_State, EQ_State,
// Sampler_Slice, Sampler_State, Track, Audio_State) but are self-contained
// so tests don't depend on miniaudio or SDL types.
// ============================================================================

Test_Effect_Type :: enum {
	Reverb,
	Delay,
	Chorus,
	Flanger,
	Distortion,
}

// Mirrors EQ_Band_State: scalar fields + enum.
Test_Band :: struct {
	freq:   f64 `s_id:1`,
	gain:   f64 `s_id:2`,
	q:      f64 `s_id:3`,
	active: bool `s_id:4`,
	type:   Test_Effect_Type `s_id:5`,
}

// Mirrors EQ_State: dynamic array of structs + scalars.
Test_Effect_Chain :: struct {
	bands:      [dynamic]Test_Band `s_id:1`,
	enabled:    bool `s_id:2`,
	active_idx: int `s_id:3`,
}

// Mirrors Sampler_Slice.
Test_Marker :: struct {
	position: f32 `s_id:1`,
	index:    u32 `s_id:2`,
}

// Mirrors Sampler_State: fixed array of structs + scalars.
Test_Sampler :: struct {
	n_markers: u32 `s_id:1`,
	markers:   [16]Test_Marker `s_id:2`,
	zoom:      f32 `s_id:3`,
	visible:   bool `s_id:4`,
}

// Mirrors Track: strings, scalars, fixed arrays, nested structs.
Test_Track :: struct {
	path:     string `s_id:1`,
	name:     string `s_id:2`,
	volume:   f32 `s_id:3`,
	track_id: int `s_id:4`,
	n_steps:  u32 `s_id:5`,
	pitches:  [32]int `s_id:6`,
	volumes:  [32]int `s_id:7`,
	selected: [32]bool `s_id:8`,
	effects:  Test_Effect_Chain `s_id:9`,
	sampler:  Test_Sampler `s_id:10`,
	loop_at:  int `s_id:11`,
}

// Mirrors Audio_State: top-level with dynamic array of complex structs.
Test_Project :: struct {
	bpm:      u16 `s_id:1`,
	tracks:   [dynamic]Test_Track `s_id:2`,
	position: int `s_id:3`,
}

// --- Version compatibility structs ---

Test_Config_V1 :: struct {
	name:  string `s_id:1`,
	value: int `s_id:2`,
}

Test_Config_V2 :: struct {
	name:     string `s_id:1`,
	value:    int `s_id:2`,
	enabled:  bool `s_id:3`,
	priority: f32 `s_id:4`,
}

// Same s_ids as V1 but fields in reversed declaration order.
Test_Config_Reordered :: struct {
	value: int `s_id:2`,
	name:  string `s_id:1`,
}

// Mix of tagged and untagged fields.
Test_Mixed_Tags :: struct {
	serialized_a:   int `s_id:1`,
	not_serialized: f64,
	serialized_b:   string `s_id:2`,
	also_skipped:   bool,
	serialized_c:   f32 `s_id:3`,
}

// --- Scalar wrapper structs for isolated type tests ---

Test_Int_Wrapper :: struct {
	val: int `s_id:1`,
}

Test_F32_Wrapper :: struct {
	val: f32 `s_id:1`,
}

Test_F64_Wrapper :: struct {
	val: f64 `s_id:1`,
}

Test_Bool_Wrapper :: struct {
	val: bool `s_id:1`,
}

Test_U16_Wrapper :: struct {
	val: u16 `s_id:1`,
}

Test_U32_Wrapper :: struct {
	val: u32 `s_id:1`,
}

Test_String_Wrapper :: struct {
	val: string `s_id:1`,
}

Test_Enum_Wrapper :: struct {
	val: Test_Effect_Type `s_id:1`,
}

Test_Fixed_Int_Array_Wrapper :: struct {
	val: [8]int `s_id:1`,
}

Test_Fixed_Bool_Array_Wrapper :: struct {
	val: [8]bool `s_id:1`,
}

Test_Fixed_F32_Array_Wrapper :: struct {
	val: [8]f32 `s_id:1`,
}

Test_Fixed_Struct_Array_Wrapper :: struct {
	val: [4]Test_Marker `s_id:1`,
}

Test_Dynamic_Struct_Array_Wrapper :: struct {
	val: [dynamic]Test_Band `s_id:1`,
}

Test_Dynamic_Int_Array_Wrapper :: struct {
	val: [dynamic]int `s_id:1`,
}

Test_Dynamic_F32_Array_Wrapper :: struct {
	val: [dynamic]f32 `s_id:1`,
}

// Holds f32/f64 IEEE 754 special values in a single struct.
Test_Float_Extremes :: struct {
	f32_pos_inf:  f32 `s_id:1`,
	f32_neg_inf:  f32 `s_id:2`,
	f32_neg_zero: f32 `s_id:3`,
	f32_max:      f32 `s_id:4`,
	f64_pos_inf:  f64 `s_id:5`,
	f64_neg_inf:  f64 `s_id:6`,
	f64_neg_zero: f64 `s_id:7`,
	f64_max:      f64 `s_id:8`,
}

// Fields with non-contiguous s_ids (1, 1000, 99999) to stress id dispatch.
Test_Sparse_S_Ids :: struct {
	first:  int `s_id:1`,
	second: string `s_id:1000`,
	third:  f32 `s_id:99999`,
}

// Larger fixed array of the same element type as Test_Fixed_Struct_Array_Wrapper
// ([4]Test_Marker) so we can serialize 8 elements and deserialize into a 4-slot target.
Test_Fixed_Large_Struct_Array_Wrapper :: struct {
	val: [8]Test_Marker `s_id:1`,
}

// ============================================================================
// Helpers
// ============================================================================

serialize_to_buf :: proc(data: any) -> [dynamic]byte {
	buf := make([dynamic]byte)
	app.serialize(data, &buf)
	return buf
}

deserialize_from_buf :: proc(data: any, buf: []byte) {
	cursor := 0
	app.deserialize(data, buf, &cursor)
}

// ============================================================================
// Tests: Individual Scalar Types
// ============================================================================

@(test)
test_roundtrip_int :: proc(t: ^testing.T) {
	input := Test_Int_Wrapper {
		val = 42,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Int_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, 42)
}

@(test)
test_roundtrip_int_negative :: proc(t: ^testing.T) {
	input := Test_Int_Wrapper {
		val = -999_999,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Int_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, -999_999)
}

@(test)
test_roundtrip_int_zero :: proc(t: ^testing.T) {
	input := Test_Int_Wrapper {
		val = 0,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Int_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, 0)
}

@(test)
test_roundtrip_int_max :: proc(t: ^testing.T) {
	input := Test_Int_Wrapper {
		val = max(int),
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Int_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, max(int))
}

@(test)
test_roundtrip_int_min :: proc(t: ^testing.T) {
	input := Test_Int_Wrapper {
		val = min(int),
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Int_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, min(int))
}

@(test)
test_roundtrip_f32 :: proc(t: ^testing.T) {
	input := Test_F32_Wrapper {
		val = 3.14,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_F32_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, f32(3.14))
}

@(test)
test_roundtrip_f32_negative :: proc(t: ^testing.T) {
	input := Test_F32_Wrapper {
		val = -24.0,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_F32_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, f32(-24.0))
}

@(test)
test_roundtrip_f64 :: proc(t: ^testing.T) {
	input := Test_F64_Wrapper {
		val = 2.718281828459045,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_F64_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, 2.718281828459045)
}

@(test)
test_roundtrip_f64_negative :: proc(t: ^testing.T) {
	input := Test_F64_Wrapper {
		val = -0.001,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_F64_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, -0.001)
}

@(test)
test_roundtrip_bool_true :: proc(t: ^testing.T) {
	input := Test_Bool_Wrapper {
		val = true,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Bool_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, true)
}

@(test)
test_roundtrip_bool_false :: proc(t: ^testing.T) {
	input := Test_Bool_Wrapper {
		val = false,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Bool_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, false)
}

@(test)
test_roundtrip_u16 :: proc(t: ^testing.T) {
	input := Test_U16_Wrapper {
		val = 120,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_U16_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, u16(120))
}

@(test)
test_roundtrip_u32 :: proc(t: ^testing.T) {
	input := Test_U32_Wrapper {
		val = 4_294_967_295,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_U32_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, u32(4_294_967_295))
}

// ============================================================================
// Tests: Strings
// ============================================================================

@(test)
test_roundtrip_string_ascii :: proc(t: ^testing.T) {
	input := Test_String_Wrapper {
		val = "hello world",
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_String_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, "hello world")
}

@(test)
test_roundtrip_string_empty :: proc(t: ^testing.T) {
	input := Test_String_Wrapper {
		val = "",
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_String_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, "")
}

@(test)
test_roundtrip_string_file_path :: proc(t: ^testing.T) {
	input := Test_String_Wrapper {
		val = "C:/Users/music/samples/kick_808.wav",
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_String_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, "C:/Users/music/samples/kick_808.wav")
}

@(test)
test_roundtrip_string_with_spaces :: proc(t: ^testing.T) {
	input := Test_String_Wrapper {
		val = "My Track Name 01",
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_String_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, "My Track Name 01")
}

@(test)
test_roundtrip_string_single_char :: proc(t: ^testing.T) {
	input := Test_String_Wrapper {
		val = "A",
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_String_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, "A")
}

// ============================================================================
// Tests: Enums
// ============================================================================

@(test)
test_roundtrip_enum_first_variant :: proc(t: ^testing.T) {
	input := Test_Enum_Wrapper {
		val = .Reverb,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Enum_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, Test_Effect_Type.Reverb)
}

@(test)
test_roundtrip_enum_last_variant :: proc(t: ^testing.T) {
	input := Test_Enum_Wrapper {
		val = .Distortion,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Enum_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, Test_Effect_Type.Distortion)
}

@(test)
test_roundtrip_enum_middle_variant :: proc(t: ^testing.T) {
	input := Test_Enum_Wrapper {
		val = .Chorus,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Enum_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, Test_Effect_Type.Chorus)
}

// ============================================================================
// Tests: Fixed Arrays of Scalars
// ============================================================================

@(test)
test_roundtrip_fixed_int_array :: proc(t: ^testing.T) {
	input := Test_Fixed_Int_Array_Wrapper {
		val = {10, -20, 30, 0, 500, -1, 42, 99},
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Fixed_Int_Array_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, input.val)
}

@(test)
test_roundtrip_fixed_int_array_all_zeros :: proc(t: ^testing.T) {
	input: Test_Fixed_Int_Array_Wrapper
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Fixed_Int_Array_Wrapper
	deserialize_from_buf(result, buf[:])
	for i in 0 ..< 8 {
		testing.expect_value(t, result.val[i], 0)
	}
}

@(test)
test_roundtrip_fixed_bool_array :: proc(t: ^testing.T) {
	input := Test_Fixed_Bool_Array_Wrapper {
		val = {true, false, true, true, false, false, true, false},
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Fixed_Bool_Array_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, input.val)
}

@(test)
test_roundtrip_fixed_f32_array :: proc(t: ^testing.T) {
	input := Test_Fixed_F32_Array_Wrapper {
		val = {0.0, 1.0, -1.0, 0.5, 100.0, -0.001, 3.14, 24.0},
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Fixed_F32_Array_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, input.val)
}

// ============================================================================
// Tests: Fixed Arrays of Structs
// ============================================================================

@(test)
test_roundtrip_fixed_struct_array :: proc(t: ^testing.T) {
	input := Test_Fixed_Struct_Array_Wrapper {
		val = {
			Test_Marker{position = 0.0, index = 0},
			Test_Marker{position = 0.25, index = 1},
			Test_Marker{position = 0.5, index = 2},
			Test_Marker{position = 0.75, index = 3},
		},
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Fixed_Struct_Array_Wrapper
	deserialize_from_buf(result, buf[:])
	for i in 0 ..< 4 {
		testing.expect_value(t, result.val[i].position, input.val[i].position)
		testing.expect_value(t, result.val[i].index, input.val[i].index)
	}
}

@(test)
test_roundtrip_fixed_struct_array_partial_fill :: proc(t: ^testing.T) {
	// Only fill 2 of 4 slots, rest stay zero.
	input: Test_Fixed_Struct_Array_Wrapper
	input.val[0] = Test_Marker {
		position = 0.1,
		index    = 5,
	}
	input.val[1] = Test_Marker {
		position = 0.9,
		index    = 10,
	}

	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Fixed_Struct_Array_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val[0].position, f32(0.1))
	testing.expect_value(t, result.val[0].index, u32(5))
	testing.expect_value(t, result.val[1].position, f32(0.9))
	testing.expect_value(t, result.val[1].index, u32(10))
	// Unfilled slots remain zero.
	testing.expect_value(t, result.val[2].position, f32(0.0))
	testing.expect_value(t, result.val[2].index, u32(0))
	testing.expect_value(t, result.val[3].position, f32(0.0))
	testing.expect_value(t, result.val[3].index, u32(0))
}

// ============================================================================
// Tests: Dynamic Arrays of Structs
// ============================================================================

@(test)
test_roundtrip_dynamic_struct_array :: proc(t: ^testing.T) {
	bands := make([dynamic]Test_Band)
	append(&bands, Test_Band{freq = 440.0, gain = -3.0, q = 0.7, active = true, type = .Reverb})
	append(&bands, Test_Band{freq = 1000.0, gain = 6.0, q = 1.4, active = false, type = .Delay})
	append(&bands, Test_Band{freq = 8000.0, gain = 0.0, q = 0.5, active = true, type = .Distortion})

	input := Test_Dynamic_Struct_Array_Wrapper {
		val = bands,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Dynamic_Struct_Array_Wrapper
	deserialize_from_buf(result, buf[:])

	testing.expect_value(t, len(result.val), 3)

	testing.expect_value(t, result.val[0].freq, 440.0)
	testing.expect_value(t, result.val[0].gain, -3.0)
	testing.expect_value(t, result.val[0].q, 0.7)
	testing.expect_value(t, result.val[0].active, true)
	testing.expect_value(t, result.val[0].type, Test_Effect_Type.Reverb)

	testing.expect_value(t, result.val[1].freq, 1000.0)
	testing.expect_value(t, result.val[1].gain, 6.0)
	testing.expect_value(t, result.val[1].q, 1.4)
	testing.expect_value(t, result.val[1].active, false)
	testing.expect_value(t, result.val[1].type, Test_Effect_Type.Delay)

	testing.expect_value(t, result.val[2].freq, 8000.0)
	testing.expect_value(t, result.val[2].gain, 0.0)
	testing.expect_value(t, result.val[2].q, 0.5)
	testing.expect_value(t, result.val[2].active, true)
	testing.expect_value(t, result.val[2].type, Test_Effect_Type.Distortion)
}

@(test)
test_roundtrip_dynamic_struct_array_empty :: proc(t: ^testing.T) {
	bands := make([dynamic]Test_Band)
	input := Test_Dynamic_Struct_Array_Wrapper {
		val = bands,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Dynamic_Struct_Array_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, len(result.val), 0)
}

@(test)
test_roundtrip_dynamic_struct_array_single :: proc(t: ^testing.T) {
	bands := make([dynamic]Test_Band)
	append(&bands, Test_Band{freq = 100.0, gain = 12.0, q = 2.0, active = true, type = .Chorus})

	input := Test_Dynamic_Struct_Array_Wrapper {
		val = bands,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Dynamic_Struct_Array_Wrapper
	deserialize_from_buf(result, buf[:])

	testing.expect_value(t, len(result.val), 1)
	testing.expect_value(t, result.val[0].freq, 100.0)
	testing.expect_value(t, result.val[0].gain, 12.0)
	testing.expect_value(t, result.val[0].q, 2.0)
	testing.expect_value(t, result.val[0].active, true)
	testing.expect_value(t, result.val[0].type, Test_Effect_Type.Chorus)
}

// ============================================================================
// Tests: Dynamic Arrays of Scalars
// ============================================================================

@(test)
test_roundtrip_dynamic_int_array :: proc(t: ^testing.T) {
	arr := make([dynamic]int)
	append(&arr, 10)
	append(&arr, -20)
	append(&arr, 30)
	append(&arr, 0)
	append(&arr, 500)

	input := Test_Dynamic_Int_Array_Wrapper {
		val = arr,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Dynamic_Int_Array_Wrapper
	deserialize_from_buf(result, buf[:])

	testing.expect_value(t, len(result.val), 5)
	testing.expect_value(t, result.val[0], 10)
	testing.expect_value(t, result.val[1], -20)
	testing.expect_value(t, result.val[2], 30)
	testing.expect_value(t, result.val[3], 0)
	testing.expect_value(t, result.val[4], 500)
}

@(test)
test_roundtrip_dynamic_int_array_empty :: proc(t: ^testing.T) {
	arr := make([dynamic]int)
	input := Test_Dynamic_Int_Array_Wrapper {
		val = arr,
	}
	buf := serialize_to_buf(input)
	// defer delete(buf)

	result: Test_Dynamic_Int_Array_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, len(result.val), 0)
}

@(test)
test_roundtrip_dynamic_f32_array :: proc(t: ^testing.T) {
	arr := make([dynamic]f32)
	append(&arr, f32(0.0))
	append(&arr, f32(1.0))
	append(&arr, f32(-0.5))
	append(&arr, f32(100.0))

	input := Test_Dynamic_F32_Array_Wrapper {
		val = arr,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Dynamic_F32_Array_Wrapper
	deserialize_from_buf(result, buf[:])

	testing.expect_value(t, len(result.val), 4)
	testing.expect_value(t, result.val[0], f32(0.0))
	testing.expect_value(t, result.val[1], f32(1.0))
	testing.expect_value(t, result.val[2], f32(-0.5))
	testing.expect_value(t, result.val[3], f32(100.0))
}

// ============================================================================
// Tests: Simple Structs (multiple fields)
// ============================================================================

@(test)
test_roundtrip_flat_struct :: proc(t: ^testing.T) {
	input := Test_Band {
		freq   = 440.0,
		gain   = -6.0,
		q      = 1.0,
		active = true,
		type   = .Delay,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Band
	deserialize_from_buf(result, buf[:])

	testing.expect_value(t, result.freq, 440.0)
	testing.expect_value(t, result.gain, -6.0)
	testing.expect_value(t, result.q, 1.0)
	testing.expect_value(t, result.active, true)
	testing.expect_value(t, result.type, Test_Effect_Type.Delay)
}

@(test)
test_roundtrip_marker_struct :: proc(t: ^testing.T) {
	input := Test_Marker {
		position = 0.333,
		index    = 7,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Marker
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.position, f32(0.333))
	testing.expect_value(t, result.index, u32(7))
}

@(test)
test_roundtrip_all_zero_struct :: proc(t: ^testing.T) {
	input: Test_Band
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Band
	deserialize_from_buf(result, buf[:])

	testing.expect_value(t, result.freq, 0.0)
	testing.expect_value(t, result.gain, 0.0)
	testing.expect_value(t, result.q, 0.0)
	testing.expect_value(t, result.active, false)
	testing.expect_value(t, result.type, Test_Effect_Type.Reverb) // zero value = first variant
}

// ============================================================================
// Tests: Nested Structs
// ============================================================================

@(test)
test_roundtrip_nested_effect_chain :: proc(t: ^testing.T) {
	bands := make([dynamic]Test_Band)
	append(&bands, Test_Band{freq = 200.0, gain = 3.0, q = 0.5, active = true, type = .Reverb})
	append(&bands, Test_Band{freq = 5000.0, gain = -12.0, q = 2.0, active = false, type = .Flanger})

	input := Test_Effect_Chain {
		bands      = bands,
		enabled    = true,
		active_idx = 1,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Effect_Chain
	deserialize_from_buf(result, buf[:])

	testing.expect_value(t, result.enabled, true)
	testing.expect_value(t, result.active_idx, 1)
	testing.expect_value(t, len(result.bands), 2)
	testing.expect_value(t, result.bands[0].freq, 200.0)
	testing.expect_value(t, result.bands[0].gain, 3.0)
	testing.expect_value(t, result.bands[0].q, 0.5)
	testing.expect_value(t, result.bands[0].active, true)
	testing.expect_value(t, result.bands[0].type, Test_Effect_Type.Reverb)
	testing.expect_value(t, result.bands[1].freq, 5000.0)
	testing.expect_value(t, result.bands[1].gain, -12.0)
	testing.expect_value(t, result.bands[1].q, 2.0)
	testing.expect_value(t, result.bands[1].active, false)
	testing.expect_value(t, result.bands[1].type, Test_Effect_Type.Flanger)
}

@(test)
test_roundtrip_sampler_with_markers :: proc(t: ^testing.T) {
	input := Test_Sampler {
		n_markers = 3,
		zoom      = 2.5,
		visible   = true,
	}
	input.markers[0] = Test_Marker {
		position = 0.0,
		index    = 0,
	}
	input.markers[1] = Test_Marker {
		position = 0.33,
		index    = 1,
	}
	input.markers[2] = Test_Marker {
		position = 0.66,
		index    = 2,
	}

	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Sampler
	deserialize_from_buf(result, buf[:])

	testing.expect_value(t, result.n_markers, u32(3))
	testing.expect_value(t, result.zoom, f32(2.5))
	testing.expect_value(t, result.visible, true)
	testing.expect_value(t, result.markers[0].position, f32(0.0))
	testing.expect_value(t, result.markers[0].index, u32(0))
	testing.expect_value(t, result.markers[1].position, f32(0.33))
	testing.expect_value(t, result.markers[1].index, u32(1))
	testing.expect_value(t, result.markers[2].position, f32(0.66))
	testing.expect_value(t, result.markers[2].index, u32(2))
	// Remaining markers should be zero.
	testing.expect_value(t, result.markers[3].position, f32(0.0))
	testing.expect_value(t, result.markers[3].index, u32(0))
}

@(test)
test_roundtrip_empty_effect_chain :: proc(t: ^testing.T) {
	bands := make([dynamic]Test_Band)
	input := Test_Effect_Chain {
		bands      = bands,
		enabled    = false,
		active_idx = 0,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Effect_Chain
	deserialize_from_buf(result, buf[:])

	testing.expect_value(t, result.enabled, false)
	testing.expect_value(t, result.active_idx, 0)
	testing.expect_value(t, len(result.bands), 0)
}

// ============================================================================
// Tests: Complex Track (strings + scalars + fixed arrays + nested structs)
// ============================================================================

@(test)
test_roundtrip_track :: proc(t: ^testing.T) {
	bands := make([dynamic]Test_Band)
	append(&bands, Test_Band{freq = 80.0, gain = -3.0, q = 0.7, active = true, type = .Reverb})

	input: Test_Track
	input.path = "C:/samples/kick.wav"
	input.name = "Kick"
	input.volume = 0.8
	input.track_id = 0
	input.n_steps = 16
	input.loop_at = 16
	for i in 0 ..< 16 {
		input.pitches[i] = i - 8
		input.volumes[i] = 100 - i
	}
	input.selected[0] = true
	input.selected[4] = true
	input.selected[8] = true
	input.effects = Test_Effect_Chain {
		bands      = bands,
		enabled    = true,
		active_idx = 0,
	}
	input.sampler = Test_Sampler {
		n_markers = 1,
		zoom      = 1.0,
		visible   = false,
	}
	input.sampler.markers[0] = Test_Marker {
		position = 0.5,
		index    = 0,
	}

	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Track
	deserialize_from_buf(result, buf[:])

	testing.expect_value(t, result.path, "C:/samples/kick.wav")
	testing.expect_value(t, result.name, "Kick")
	testing.expect_value(t, result.volume, f32(0.8))
	testing.expect_value(t, result.track_id, 0)
	testing.expect_value(t, result.n_steps, u32(16))
	testing.expect_value(t, result.loop_at, 16)

	for i in 0 ..< 16 {
		testing.expect_value(t, result.pitches[i], i - 8)
		testing.expect_value(t, result.volumes[i], 100 - i)
	}

	testing.expect_value(t, result.selected[0], true)
	testing.expect_value(t, result.selected[1], false)
	testing.expect_value(t, result.selected[4], true)
	testing.expect_value(t, result.selected[8], true)

	testing.expect_value(t, result.effects.enabled, true)
	testing.expect_value(t, result.effects.active_idx, 0)
	testing.expect_value(t, len(result.effects.bands), 1)
	testing.expect_value(t, result.effects.bands[0].freq, 80.0)

	testing.expect_value(t, result.sampler.n_markers, u32(1))
	testing.expect_value(t, result.sampler.zoom, f32(1.0))
	testing.expect_value(t, result.sampler.visible, false)
	testing.expect_value(t, result.sampler.markers[0].position, f32(0.5))
}

@(test)
test_roundtrip_track_empty_strings :: proc(t: ^testing.T) {
	bands := make([dynamic]Test_Band)
	input: Test_Track
	input.path = ""
	input.name = ""
	input.volume = 1.0
	input.effects = Test_Effect_Chain {
		bands      = bands,
		enabled    = false,
		active_idx = 0,
	}

	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Track
	deserialize_from_buf(result, buf[:])

	testing.expect_value(t, result.path, "")
	testing.expect_value(t, result.name, "")
	testing.expect_value(t, result.volume, f32(1.0))
}

// ============================================================================
// Tests: Full Project (top-level with dynamic array of tracks)
// ============================================================================

@(test)
test_roundtrip_full_project :: proc(t: ^testing.T) {
	// Track 1: full content.
	bands1 := make([dynamic]Test_Band)
	append(&bands1, Test_Band{freq = 80.0, gain = -3.0, q = 0.7, active = true, type = .Reverb})
	append(&bands1, Test_Band{freq = 10000.0, gain = -6.0, q = 1.0, active = true, type = .Delay})

	track1: Test_Track
	track1.path = "C:/samples/kick.wav"
	track1.name = "Kick"
	track1.volume = 0.75
	track1.track_id = 0
	track1.n_steps = 8
	track1.loop_at = 8
	track1.pitches[0] = 0
	track1.pitches[1] = 2
	track1.volumes[0] = 127
	track1.volumes[1] = 100
	track1.selected[0] = true
	track1.effects = Test_Effect_Chain {
		bands      = bands1,
		enabled    = true,
		active_idx = 0,
	}
	track1.sampler = Test_Sampler {
		n_markers = 2,
		zoom      = 1.5,
		visible   = true,
	}
	track1.sampler.markers[0] = Test_Marker {
		position = 0.0,
		index    = 0,
	}
	track1.sampler.markers[1] = Test_Marker {
		position = 1.0,
		index    = 1,
	}

	// Track 2: minimal, no effects.
	bands2 := make([dynamic]Test_Band)
	track2: Test_Track
	track2.path = "C:/samples/snare.wav"
	track2.name = "Snare"
	track2.volume = 0.9
	track2.track_id = 1
	track2.n_steps = 16
	track2.loop_at = 16
	track2.effects = Test_Effect_Chain {
		bands      = bands2,
		enabled    = false,
		active_idx = 0,
	}

	tracks := make([dynamic]Test_Track)
	append(&tracks, track1)
	append(&tracks, track2)

	input := Test_Project {
		bpm      = 128,
		tracks   = tracks,
		position = 4,
	}

	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Project
	deserialize_from_buf(result, buf[:])

	testing.expect_value(t, result.bpm, u16(128))
	testing.expect_value(t, result.position, 4)
	testing.expect_value(t, len(result.tracks), 2)

	// Track 1 checks.
	t1 := result.tracks[0]
	testing.expect_value(t, t1.path, "C:/samples/kick.wav")
	testing.expect_value(t, t1.name, "Kick")
	testing.expect_value(t, t1.volume, f32(0.75))
	testing.expect_value(t, t1.track_id, 0)
	testing.expect_value(t, t1.n_steps, u32(8))
	testing.expect_value(t, t1.loop_at, 8)
	testing.expect_value(t, t1.pitches[0], 0)
	testing.expect_value(t, t1.pitches[1], 2)
	testing.expect_value(t, t1.volumes[0], 127)
	testing.expect_value(t, t1.selected[0], true)
	testing.expect_value(t, t1.effects.enabled, true)
	testing.expect_value(t, len(t1.effects.bands), 2)
	testing.expect_value(t, t1.effects.bands[0].freq, 80.0)
	testing.expect_value(t, t1.effects.bands[1].freq, 10000.0)
	testing.expect_value(t, t1.sampler.n_markers, u32(2))
	testing.expect_value(t, t1.sampler.markers[0].position, f32(0.0))
	testing.expect_value(t, t1.sampler.markers[1].position, f32(1.0))

	// Track 2 checks.
	t2 := result.tracks[1]
	testing.expect_value(t, t2.path, "C:/samples/snare.wav")
	testing.expect_value(t, t2.name, "Snare")
	testing.expect_value(t, t2.volume, f32(0.9))
	testing.expect_value(t, t2.track_id, 1)
	testing.expect_value(t, t2.effects.enabled, false)
	testing.expect_value(t, len(t2.effects.bands), 0)
}

@(test)
test_roundtrip_project_no_tracks :: proc(t: ^testing.T) {
	tracks := make([dynamic]Test_Track)
	input := Test_Project {
		bpm      = 90,
		tracks   = tracks,
		position = 0,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Project
	deserialize_from_buf(result, buf[:])

	testing.expect_value(t, result.bpm, u16(90))
	testing.expect_value(t, result.position, 0)
	testing.expect_value(t, len(result.tracks), 0)
}

// ============================================================================
// Tests: Deeply Nested (Project -> Track -> Effect_Chain -> Band)
// ============================================================================

@(test)
test_deeply_nested_three_levels :: proc(t: ^testing.T) {
	bands := make([dynamic]Test_Band)
	append(&bands, Test_Band{freq = 250.0, gain = 6.0, q = 1.2, active = true, type = .Chorus})

	track: Test_Track
	track.path = "deep_test.wav"
	track.name = "Deep"
	track.volume = 0.5
	track.effects = Test_Effect_Chain {
		bands      = bands,
		enabled    = true,
		active_idx = 0,
	}

	tracks := make([dynamic]Test_Track)
	append(&tracks, track)

	input := Test_Project {
		bpm      = 90,
		tracks   = tracks,
		position = 0,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Project
	deserialize_from_buf(result, buf[:])

	testing.expect_value(t, result.bpm, u16(90))
	testing.expect_value(t, len(result.tracks), 1)
	testing.expect_value(t, result.tracks[0].name, "Deep")
	testing.expect_value(t, result.tracks[0].effects.enabled, true)
	testing.expect_value(t, len(result.tracks[0].effects.bands), 1)
	testing.expect_value(t, result.tracks[0].effects.bands[0].freq, 250.0)
	testing.expect_value(t, result.tracks[0].effects.bands[0].type, Test_Effect_Type.Chorus)
}

// ============================================================================
// Tests: Multiple Tracks with Varied Content
// ============================================================================

@(test)
test_many_tracks_varied_content :: proc(t: ^testing.T) {
	tracks := make([dynamic]Test_Track)

	// Track 0: heavy effects, full sampler.
	{
		bands := make([dynamic]Test_Band)
		append(&bands, Test_Band{freq = 60.0, gain = 0.0, q = 0.7, active = true, type = .Reverb})
		append(&bands, Test_Band{freq = 300.0, gain = -2.0, q = 1.0, active = true, type = .Delay})
		append(&bands, Test_Band{freq = 8000.0, gain = -12.0, q = 0.5, active = false, type = .Distortion})

		track: Test_Track
		track.path = "kick.wav"
		track.name = "Kick"
		track.volume = 0.85
		track.track_id = 0
		track.n_steps = 32
		track.loop_at = 32
		for i in 0 ..< 32 {
			track.pitches[i] = (i % 12) - 6
		}
		track.effects = Test_Effect_Chain {
			bands      = bands,
			enabled    = true,
			active_idx = 2,
		}
		track.sampler.n_markers = 4
		track.sampler.zoom = 3.0
		track.sampler.visible = true
		for i in 0 ..< 4 {
			track.sampler.markers[i] = Test_Marker {
				position = f32(i) * 0.25,
				index    = u32(i),
			}
		}
		append(&tracks, track)
	}

	// Track 1: empty effects.
	{
		bands := make([dynamic]Test_Band)
		track: Test_Track
		track.path = "hihat.wav"
		track.name = "HiHat"
		track.volume = 0.6
		track.track_id = 1
		track.n_steps = 16
		track.effects = Test_Effect_Chain {
			bands      = bands,
			enabled    = false,
			active_idx = 0,
		}
		append(&tracks, track)
	}

	// Track 2: empty path, no arrays populated.
	{
		bands := make([dynamic]Test_Band)
		track: Test_Track
		track.path = ""
		track.name = "Empty Track"
		track.volume = 1.0
		track.track_id = 2
		track.effects = Test_Effect_Chain {
			bands      = bands,
			enabled    = false,
			active_idx = 0,
		}
		append(&tracks, track)
	}

	input := Test_Project {
		bpm      = 140,
		tracks   = tracks,
		position = 7,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Project
	deserialize_from_buf(result, buf[:])

	testing.expect_value(t, result.bpm, u16(140))
	testing.expect_value(t, result.position, 7)
	testing.expect_value(t, len(result.tracks), 3)

	// Track 0.
	testing.expect_value(t, result.tracks[0].name, "Kick")
	testing.expect_value(t, result.tracks[0].n_steps, u32(32))
	testing.expect_value(t, len(result.tracks[0].effects.bands), 3)
	testing.expect_value(t, result.tracks[0].effects.active_idx, 2)
	testing.expect_value(t, result.tracks[0].sampler.n_markers, u32(4))
	testing.expect_value(t, result.tracks[0].sampler.markers[2].position, f32(0.5))
	testing.expect_value(t, result.tracks[0].pitches[0], -6)
	testing.expect_value(t, result.tracks[0].pitches[6], 0)
	testing.expect_value(t, result.tracks[0].pitches[11], 5)

	// Track 1.
	testing.expect_value(t, result.tracks[1].name, "HiHat")
	testing.expect_value(t, len(result.tracks[1].effects.bands), 0)
	testing.expect_value(t, result.tracks[1].effects.enabled, false)

	// Track 2.
	testing.expect_value(t, result.tracks[2].path, "")
	testing.expect_value(t, result.tracks[2].name, "Empty Track")
}

// ============================================================================
// Tests: Untagged Fields Are Ignored
// ============================================================================

@(test)
test_untagged_fields_stay_zero :: proc(t: ^testing.T) {
	input := Test_Mixed_Tags {
		serialized_a   = 42,
		not_serialized = 99.99,
		serialized_b   = "hello",
		also_skipped   = true,
		serialized_c   = 1.5,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Mixed_Tags
	deserialize_from_buf(result, buf[:])

	// Tagged fields survive the roundtrip.
	testing.expect_value(t, result.serialized_a, 42)
	testing.expect_value(t, result.serialized_b, "hello")
	testing.expect_value(t, result.serialized_c, f32(1.5))

	// Untagged fields are zero after deserialization.
	testing.expect_value(t, result.not_serialized, 0.0)
	testing.expect_value(t, result.also_skipped, false)
}

// ============================================================================
// Tests: Forward Compatibility (extra s_ids in stream get skipped)
// ============================================================================

@(test)
test_forward_compat_extra_fields_skipped :: proc(t: ^testing.T) {
	// Serialize V2 which has s_id:3 and s_id:4 that V1 does not know about.
	input := Test_Config_V2 {
		name     = "test",
		value    = 100,
		enabled  = true,
		priority = 5.0,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	// Deserialize into V1 — unknown s_ids 3 and 4 are silently skipped.
	result: Test_Config_V1
	deserialize_from_buf(result, buf[:])

	testing.expect_value(t, result.name, "test")
	testing.expect_value(t, result.value, 100)
}

// ============================================================================
// Tests: Backward Compatibility (missing s_ids stay zero)
// ============================================================================

@(test)
test_backward_compat_missing_fields_zero :: proc(t: ^testing.T) {
	// Serialize V1 which only has s_id:1 and s_id:2.
	input := Test_Config_V1 {
		name  = "old_config",
		value = 50,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	// Deserialize into V2 — s_id:3 and s_id:4 were never serialized.
	result: Test_Config_V2
	deserialize_from_buf(result, buf[:])

	testing.expect_value(t, result.name, "old_config")
	testing.expect_value(t, result.value, 50)
	testing.expect_value(t, result.enabled, false)
	testing.expect_value(t, result.priority, f32(0.0))
}

// ============================================================================
// Tests: Field Order Independence (matching by s_id, not struct position)
// ============================================================================

@(test)
test_field_order_independence :: proc(t: ^testing.T) {
	// Serialize V1: name is s_id:1 (first field), value is s_id:2 (second).
	input := Test_Config_V1 {
		name  = "order_test",
		value = 77,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	// Deserialize into Reordered: value (s_id:2) declared first, name (s_id:1) second.
	result: Test_Config_Reordered
	deserialize_from_buf(result, buf[:])

	testing.expect_value(t, result.name, "order_test")
	testing.expect_value(t, result.value, 77)
}

// ============================================================================
// Tests: Serializing the Same Data Twice Produces Identical Output
// ============================================================================

@(test)
test_serialize_deterministic :: proc(t: ^testing.T) {
	input := Test_Band {
		freq   = 440.0,
		gain   = -6.0,
		q      = 1.0,
		active = true,
		type   = .Delay,
	}
	buf1 := serialize_to_buf(input)
	defer delete(buf1)
	buf2 := serialize_to_buf(input)
	defer delete(buf2)

	testing.expect_value(t, len(buf1), len(buf2))
	for i in 0 ..< len(buf1) {
		testing.expect_value(t, buf1[i], buf2[i])
	}
}

// ============================================================================
// Tests: Edge Cases
// ============================================================================

@(test)
test_roundtrip_struct_with_multiple_strings :: proc(t: ^testing.T) {
	input := Test_Config_V1 {
		name  = "first string with spaces",
		value = 42,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Config_V1
	deserialize_from_buf(result, buf[:])

	testing.expect_value(t, result.name, "first string with spaces")
	testing.expect_value(t, result.value, 42)
}

@(test)
test_roundtrip_track_with_all_steps_set :: proc(t: ^testing.T) {
	bands := make([dynamic]Test_Band)
	input: Test_Track
	input.path = "test.wav"
	input.name = "Full"
	input.volume = 0.5
	input.n_steps = 32
	input.effects = Test_Effect_Chain {
		bands      = bands,
		enabled    = false,
		active_idx = 0,
	}

	// Fill every step.
	for i in 0 ..< 32 {
		input.pitches[i] = i * 2 - 31
		input.volumes[i] = 127 - i * 4
		input.selected[i] = (i % 3) == 0
	}

	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Track
	deserialize_from_buf(result, buf[:])

	for i in 0 ..< 32 {
		testing.expect_value(t, result.pitches[i], i * 2 - 31)
		testing.expect_value(t, result.volumes[i], 127 - i * 4)
		testing.expect_value(t, result.selected[i], (i % 3) == 0)
	}
}

@(test)
test_roundtrip_many_bands :: proc(t: ^testing.T) {
	bands := make([dynamic]Test_Band)
	for i in 0 ..< 20 {
		append(
			&bands,
			Test_Band {
				freq = f64(100 * (i + 1)),
				gain = f64(i) - 10.0,
				q = f64(i) * 0.1 + 0.1,
				active = (i % 2) == 0,
				type = Test_Effect_Type(i % 5),
			},
		)
	}

	input := Test_Effect_Chain {
		bands      = bands,
		enabled    = true,
		active_idx = 10,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Effect_Chain
	deserialize_from_buf(result, buf[:])

	testing.expect_value(t, len(result.bands), 20)
	testing.expect_value(t, result.active_idx, 10)
	for i in 0 ..< 20 {
		testing.expect_value(t, result.bands[i].freq, f64(100 * (i + 1)))
		testing.expect_value(t, result.bands[i].gain, f64(i) - 10.0)
		testing.expect_value(t, result.bands[i].active, (i % 2) == 0)
		testing.expect_value(t, result.bands[i].type, Test_Effect_Type(i % 5))
	}
}

@(test)
test_roundtrip_project_many_tracks :: proc(t: ^testing.T) {
	tracks := make([dynamic]Test_Track)
	for i in 0 ..< 8 {
		bands := make([dynamic]Test_Band)
		append(&bands, Test_Band{freq = f64(100 + i * 50), gain = 0.0, q = 0.7, active = true, type = .Reverb})

		track: Test_Track
		track.name = "Track"
		track.track_id = i
		track.volume = f32(i + 1) * 0.1
		track.n_steps = u32(8 + i * 4)
		track.effects = Test_Effect_Chain {
			bands      = bands,
			enabled    = true,
			active_idx = 0,
		}
		append(&tracks, track)
	}

	input := Test_Project {
		bpm      = 120,
		tracks   = tracks,
		position = 3,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Project
	deserialize_from_buf(result, buf[:])

	testing.expect_value(t, len(result.tracks), 8)
	for i in 0 ..< 8 {
		testing.expect_value(t, result.tracks[i].track_id, i)
		testing.expect_value(t, result.tracks[i].volume, f32(i + 1) * 0.1)
		testing.expect_value(t, result.tracks[i].n_steps, u32(8 + i * 4))
		testing.expect_value(t, len(result.tracks[i].effects.bands), 1)
		testing.expect_value(t, result.tracks[i].effects.bands[0].freq, f64(100 + i * 50))
	}
}

// ============================================================================
// PATHOLOGICAL TESTS
// ============================================================================

// ============================================================================
// IEEE 754 Float Special Values
// ============================================================================

@(test)
test_roundtrip_f32_nan :: proc(t: ^testing.T) {
	input := Test_F32_Wrapper {
		val = math.nan_f32(),
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_F32_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect(t, math.is_nan_f32(result.val), "f32 NaN did not survive roundtrip")
}

@(test)
test_roundtrip_f64_nan :: proc(t: ^testing.T) {
	input := Test_F64_Wrapper {
		val = math.nan_f64(),
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_F64_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect(t, math.is_nan_f64(result.val), "f64 NaN did not survive roundtrip")
}

@(test)
test_roundtrip_f32_positive_infinity :: proc(t: ^testing.T) {
	input := Test_F32_Wrapper {
		val = math.inf_f32(1),
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_F32_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect(t, math.is_inf_f32(result.val, 1), "f32 +Inf did not survive roundtrip")
}

@(test)
test_roundtrip_f32_negative_infinity :: proc(t: ^testing.T) {
	input := Test_F32_Wrapper {
		val = math.inf_f32(-1),
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_F32_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect(t, math.is_inf_f32(result.val, -1), "f32 -Inf did not survive roundtrip")
}

// -0.0 == 0.0 numerically; verify the sign bit survives bit-for-bit.
@(test)
test_roundtrip_f32_negative_zero_bitexact :: proc(t: ^testing.T) {
	input := Test_F32_Wrapper {
		val = f32(-0.0),
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_F32_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, transmute(u32)result.val, transmute(u32)f32(-0.0))
}

@(test)
test_roundtrip_f64_negative_zero_bitexact :: proc(t: ^testing.T) {
	input := Test_F64_Wrapper {
		val = f64(-0.0),
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_F64_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, transmute(u64)result.val, transmute(u64)f64(-0.0))
}

@(test)
test_roundtrip_f32_max_finite :: proc(t: ^testing.T) {
	input := Test_F32_Wrapper {
		val = math.F32_MAX,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_F32_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, math.F32_MAX)
}

// Smallest positive subnormal f32: bit pattern 0x00000001.
@(test)
test_roundtrip_f32_min_positive_subnormal :: proc(t: ^testing.T) {
	subnormal := transmute(f32)u32(1)
	input := Test_F32_Wrapper {
		val = subnormal,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_F32_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, transmute(u32)result.val, u32(1))
}

// All special IEEE 754 values in a single struct roundtrip.
@(test)
test_roundtrip_float_extremes_combined :: proc(t: ^testing.T) {
	input := Test_Float_Extremes {
		f32_pos_inf  = math.inf_f32(1),
		f32_neg_inf  = math.inf_f32(-1),
		f32_neg_zero = f32(-0.0),
		f32_max      = math.F32_MAX,
		f64_pos_inf  = math.inf_f64(1),
		f64_neg_inf  = math.inf_f64(-1),
		f64_neg_zero = f64(-0.0),
		f64_max      = math.F64_MAX,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Float_Extremes
	deserialize_from_buf(result, buf[:])

	testing.expect(t, math.is_inf_f32(result.f32_pos_inf, 1))
	testing.expect(t, math.is_inf_f32(result.f32_neg_inf, -1))
	testing.expect_value(t, transmute(u32)result.f32_neg_zero, transmute(u32)f32(-0.0))
	testing.expect_value(t, result.f32_max, math.F32_MAX)
	testing.expect(t, math.is_inf_f64(result.f64_pos_inf, 1))
	testing.expect(t, math.is_inf_f64(result.f64_neg_inf, -1))
	testing.expect_value(t, transmute(u64)result.f64_neg_zero, transmute(u64)f64(-0.0))
	testing.expect_value(t, result.f64_max, math.F64_MAX)
}

// ============================================================================
// String Stress Tests
// ============================================================================

// "café": len("café") = 5 bytes, 4 runes. The serializer writes len(s)*4 = 20 as
// the declared chunk size but only emits 4*4 = 16 bytes of rune data. The
// deserializer then tries to read 20/4 = 5 runes, overshooting by one and reading
// garbage from the next field's bytes — exposing the byte-length vs rune-count mismatch.
@(test)
test_roundtrip_string_unicode_multibyte :: proc(t: ^testing.T) {
	input := Test_String_Wrapper {
		val = "café",
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_String_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, "café")
}

// CJK characters are 3 bytes each in UTF-8, amplifying the len vs rune-count delta.
// "日本語": 9 bytes, 3 runes — declared size = 36, written = 12.
@(test)
test_roundtrip_string_unicode_cjk :: proc(t: ^testing.T) {
	input := Test_String_Wrapper {
		val = "日本語",
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_String_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, "日本語")
}

// Every printable ASCII codepoint (0x20–0x7E) in a single string.
@(test)
test_roundtrip_string_all_printable_ascii :: proc(t: ^testing.T) {
	buf_chars: [95]byte
	for i in 0 ..< 95 {
		buf_chars[i] = byte(0x20 + i)
	}
	s := string(buf_chars[:])
	input := Test_String_Wrapper {
		val = s,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_String_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, s)
}

// 1000-character string — stress tests string allocation path in the deserializer.
@(test)
test_roundtrip_string_very_long :: proc(t: ^testing.T) {
	chars: [1000]byte
	for i in 0 ..< 1000 {
		chars[i] = byte('a' + (i % 26))
	}
	long_str := string(chars[:])
	input := Test_String_Wrapper {
		val = long_str,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_String_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, long_str)
}

// Two long strings in the same struct (1000-char path, 512-char name).
// Both fields must deserialize correctly without one bleeding into the other.
@(test)
test_roundtrip_track_with_long_strings :: proc(t: ^testing.T) {
	path_chars: [1000]byte
	name_chars: [512]byte
	for i in 0 ..< 1000 {
		path_chars[i] = byte('/' + (i % 40))
	}
	for i in 0 ..< 512 {
		name_chars[i] = byte('A' + (i % 26))
	}
	path := string(path_chars[:])
	name := string(name_chars[:])

	bands := make([dynamic]Test_Band)
	input: Test_Track
	input.path = path
	input.name = name
	input.volume = 1.0
	input.effects = Test_Effect_Chain {
		bands   = bands,
		enabled = false,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Track
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.path, path)
	testing.expect_value(t, result.name, name)
}

// ============================================================================
// s_id Sparse Distribution
// ============================================================================

// s_id values jump 1 → 1000 → 99999 — verifies the id lookup is not range-bounded
// and that large gaps between ids don't corrupt the dispatch loop.
@(test)
test_roundtrip_sparse_s_ids :: proc(t: ^testing.T) {
	input := Test_Sparse_S_Ids {
		first  = 42,
		second = "sparse",
		third  = 3.14,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Sparse_S_Ids
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.first, 42)
	testing.expect_value(t, result.second, "sparse")
	testing.expect_value(t, result.third, f32(3.14))
}

// ============================================================================
// Array Boundary Conditions
// ============================================================================

// Serialize an 8-element fixed struct array, deserialize into the 4-slot type.
// Exercises the min(count, v.count) guard and verifies the struct-level
// cursor^ = chunk_end correctly skips the 4 overflow elements.
@(test)
test_fixed_struct_array_serialize_more_than_capacity :: proc(t: ^testing.T) {
	input: Test_Fixed_Large_Struct_Array_Wrapper
	for i in 0 ..< 8 {
		input.val[i] = Test_Marker {
			position = f32(i) * 0.1,
			index    = u32(i + 1),
		}
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	// Only the first 4 markers should land; cursor must end up at chunk_end cleanly.
	result: Test_Fixed_Struct_Array_Wrapper
	deserialize_from_buf(result, buf[:])
	for i in 0 ..< 4 {
		testing.expect_value(t, result.val[i].position, f32(i) * 0.1)
		testing.expect_value(t, result.val[i].index, u32(i + 1))
	}
}

// All 16 sampler marker slots populated — exercises fixed struct array at max capacity.
@(test)
test_roundtrip_all_sampler_markers_full :: proc(t: ^testing.T) {
	input: Test_Sampler
	input.n_markers = 16
	input.zoom = 4.0
	input.visible = true
	for i in 0 ..< 16 {
		input.markers[i] = Test_Marker {
			position = f32(i) / 15.0,
			index    = u32(i),
		}
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Sampler
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.n_markers, u32(16))
	testing.expect_value(t, result.zoom, f32(4.0))
	for i in 0 ..< 16 {
		testing.expect_value(t, result.markers[i].position, f32(i) / 15.0)
		testing.expect_value(t, result.markers[i].index, u32(i))
	}
}

// 1000-element dynamic array of structs — stresses the heap allocation and per-element
// size-prefix loop in the dynamic struct array deserialization path.
@(test)
test_dynamic_struct_array_1000_elements :: proc(t: ^testing.T) {
	bands := make([dynamic]Test_Band)
	for i in 0 ..< 1000 {
		append(
			&bands,
			Test_Band {
				freq = f64(i + 1),
				gain = f64(i % 100) - 50.0,
				q = f64(i % 10) * 0.1 + 0.1,
				active = (i % 2) == 0,
				type = Test_Effect_Type(i % 5),
			},
		)
	}
	input := Test_Dynamic_Struct_Array_Wrapper {
		val = bands,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Dynamic_Struct_Array_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, len(result.val), 1000)
	for i in 0 ..< 1000 {
		testing.expect_value(t, result.val[i].freq, f64(i + 1))
		testing.expect_value(t, result.val[i].gain, f64(i % 100) - 50.0)
		testing.expect_value(t, result.val[i].active, (i % 2) == 0)
		testing.expect_value(t, result.val[i].type, Test_Effect_Type(i % 5))
	}
}

// 1000-element dynamic int array, alternating max(int) and min(int) values.
// Stresses the raw-byte copy path for scalar dynamic arrays.
@(test)
test_dynamic_int_array_1000_elements :: proc(t: ^testing.T) {
	arr := make([dynamic]int)
	for i in 0 ..< 1000 {
		v := max(int) - i if (i % 2 == 0) else min(int) + i
		append(&arr, v)
	}
	input := Test_Dynamic_Int_Array_Wrapper {
		val = arr,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Dynamic_Int_Array_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, len(result.val), 1000)
	for i in 0 ..< 1000 {
		expected := max(int) - i if (i % 2 == 0) else min(int) + i
		testing.expect_value(t, result.val[i], expected)
	}
}

// ============================================================================
// Large-Scale Project Stress Test
// ============================================================================

// 32 tracks × 16 bands each — maximum realistic project scale.
// Every track has a fully-populated sampler, all step arrays set, and varied content
// to ensure no track's data bleeds into an adjacent track during deserialization.
@(test)
test_large_project_32_tracks_16_bands :: proc(t: ^testing.T) {
	tracks := make([dynamic]Test_Track)
	for ti in 0 ..< 32 {
		bands := make([dynamic]Test_Band)
		for bi in 0 ..< 16 {
			append(
				&bands,
				Test_Band {
					freq = f64((ti + 1) * 100 + bi * 50),
					gain = f64(bi) - 8.0,
					q = 0.5 + f64(bi) * 0.1,
					active = (bi % 3) != 0,
					type = Test_Effect_Type(bi % 5),
				},
			)
		}
		track: Test_Track
		track.track_id = ti
		track.name = "Track"
		track.volume = f32(ti + 1) / 32.0
		track.n_steps = 32
		track.loop_at = 32
		track.effects = Test_Effect_Chain {
			bands      = bands,
			enabled    = true,
			active_idx = ti % 16,
		}
		track.sampler = Test_Sampler {
			n_markers = 4,
			zoom      = 1.0,
			visible   = true,
		}
		for i in 0 ..< 4 {
			track.sampler.markers[i] = Test_Marker {
				position = f32(i) * 0.25,
				index    = u32(i),
			}
		}
		for i in 0 ..< 32 {
			track.pitches[i] = (ti * 32 + i) % 24 - 12
			track.volumes[i] = 100 - i * 3
			track.selected[i] = (i + ti) % 4 == 0
		}
		append(&tracks, track)
	}
	input := Test_Project {
		bpm      = 160,
		tracks   = tracks,
		position = 15,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Project
	deserialize_from_buf(result, buf[:])

	testing.expect_value(t, result.bpm, u16(160))
	testing.expect_value(t, result.position, 15)
	testing.expect_value(t, len(result.tracks), 32)
	for ti in 0 ..< 32 {
		testing.expect_value(t, result.tracks[ti].track_id, ti)
		testing.expect_value(t, len(result.tracks[ti].effects.bands), 16)
		testing.expect_value(t, result.tracks[ti].effects.bands[0].freq, f64((ti + 1) * 100))
		testing.expect_value(t, result.tracks[ti].effects.bands[15].freq, f64((ti + 1) * 100 + 15 * 50))
		testing.expect_value(t, result.tracks[ti].sampler.n_markers, u32(4))
		testing.expect_value(t, result.tracks[ti].pitches[0], (ti * 32) % 24 - 12)
	}
}

// ============================================================================
// Integer Boundary Values in Fixed Arrays
// ============================================================================

// All 32 pitch slots at min(int), all 32 volume slots at max(int), all selected true.
@(test)
test_roundtrip_all_int_array_extremes :: proc(t: ^testing.T) {
	bands := make([dynamic]Test_Band)
	input: Test_Track
	input.path = "extremes.wav"
	input.name = "Extremes"
	input.volume = 1.0
	input.n_steps = 32
	input.effects = Test_Effect_Chain {
		bands   = bands,
		enabled = false,
	}
	for i in 0 ..< 32 {
		input.pitches[i] = min(int)
		input.volumes[i] = max(int)
		input.selected[i] = true
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Track
	deserialize_from_buf(result, buf[:])
	for i in 0 ..< 32 {
		testing.expect_value(t, result.pitches[i], min(int))
		testing.expect_value(t, result.volumes[i], max(int))
		testing.expect_value(t, result.selected[i], true)
	}
}

// ============================================================================
// u16 Boundary Values
// ============================================================================

@(test)
test_roundtrip_u16_zero :: proc(t: ^testing.T) {
	input := Test_U16_Wrapper {
		val = 0,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_U16_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, u16(0))
}

@(test)
test_roundtrip_u16_max :: proc(t: ^testing.T) {
	input := Test_U16_Wrapper {
		val = max(u16),
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_U16_Wrapper
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.val, max(u16))
}

// ============================================================================
// Idempotency: Double Roundtrip
// ============================================================================

// Serialize → deserialize → serialize again. Both byte buffers must be bit-for-bit
// identical. Any state that bleeds in during deserialization and then alters the
// re-serialized output will be caught here.
@(test)
test_double_roundtrip_bytes_identical :: proc(t: ^testing.T) {
	bands := make([dynamic]Test_Band)
	append(&bands, Test_Band{freq = 440.0, gain = -3.0, q = 0.7, active = true, type = .Delay})
	track: Test_Track
	track.path = "C:/samples/roundtrip.wav"
	track.name = "Idempotency"
	track.volume = 0.75
	track.track_id = 3
	track.n_steps = 16
	track.loop_at = 16
	track.effects = Test_Effect_Chain {
		bands      = bands,
		enabled    = true,
		active_idx = 0,
	}
	track.sampler = Test_Sampler {
		n_markers = 2,
		zoom      = 1.5,
		visible   = true,
	}
	track.sampler.markers[0] = Test_Marker {
		position = 0.0,
		index    = 0,
	}
	track.sampler.markers[1] = Test_Marker {
		position = 0.5,
		index    = 1,
	}
	for i in 0 ..< 16 {
		track.pitches[i] = i - 8
		track.volumes[i] = 100 - i * 5
		track.selected[i] = (i % 2) == 0
	}

	buf1 := serialize_to_buf(track)
	defer delete(buf1)

	intermediate: Test_Track
	deserialize_from_buf(intermediate, buf1[:])

	buf2 := serialize_to_buf(intermediate)
	defer delete(buf2)

	testing.expect_value(t, len(buf1), len(buf2))
	for i in 0 ..< min(len(buf1), len(buf2)) {
		testing.expect_value(t, buf1[i], buf2[i])
	}
}

// ============================================================================
// Project-Level Integer Boundary Values
// ============================================================================

@(test)
test_roundtrip_project_position_min_int :: proc(t: ^testing.T) {
	tracks := make([dynamic]Test_Track)
	input := Test_Project {
		bpm      = 120,
		tracks   = tracks,
		position = min(int),
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Project
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.position, min(int))
}

@(test)
test_roundtrip_project_position_max_int :: proc(t: ^testing.T) {
	tracks := make([dynamic]Test_Track)
	input := Test_Project {
		bpm      = 120,
		tracks   = tracks,
		position = max(int),
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Project
	deserialize_from_buf(result, buf[:])
	testing.expect_value(t, result.position, max(int))
}

// ============================================================================
// Alternating Empty / Large Dynamic Arrays in Same Project
// ============================================================================

// Tracks at even indices have 0 bands, odd indices have 20 bands.
// Back-to-back empty-then-large blobs stress the length-boundary arithmetic
// between consecutive dynamic array chunks.
@(test)
test_project_alternating_empty_and_large_effect_chains :: proc(t: ^testing.T) {
	tracks := make([dynamic]Test_Track)
	for ti in 0 ..< 6 {
		bands := make([dynamic]Test_Band)
		if ti % 2 == 1 {
			for bi in 0 ..< 20 {
				append(
					&bands,
					Test_Band{freq = f64(bi + 1) * 100.0, gain = 0.0, q = 1.0, active = true, type = .Reverb},
				)
			}
		}
		track: Test_Track
		track.track_id = ti
		track.name = "Track"
		track.volume = 1.0
		track.effects = Test_Effect_Chain {
			bands   = bands,
			enabled = ti % 2 == 1,
		}
		append(&tracks, track)
	}
	input := Test_Project {
		bpm      = 130,
		tracks   = tracks,
		position = 0,
	}
	buf := serialize_to_buf(input)
	defer delete(buf)

	result: Test_Project
	deserialize_from_buf(result, buf[:])

	testing.expect_value(t, len(result.tracks), 6)
	for ti in 0 ..< 6 {
		expected_len := 20 if ti % 2 == 1 else 0
		testing.expect_value(t, len(result.tracks[ti].effects.bands), expected_len)
		if ti % 2 == 1 {
			testing.expect_value(t, result.tracks[ti].effects.bands[0].freq, 100.0)
			testing.expect_value(t, result.tracks[ti].effects.bands[19].freq, 2000.0)
		}
	}
}
