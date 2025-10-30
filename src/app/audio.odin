package app
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strconv"
import str "core:strings"
import "core:time"
import ma "vendor:miniaudio"

MAX_TRACKS :: 256
MAX_TRACK_STEPS :: 256

Track :: struct {
	sound:          ^ma.sound,
	sound_path:		string, 
	armed:          bool,
	volume:         f32,
	// PCM data is used only for rendering waveforms atm.
	pcm_data:       struct {
		left_channel:  [dynamic]f32,
		right_channel: [dynamic]f32,
	},
	curr_step:      u32,
	// Actual amount of steps in the track.
	n_steps:        u32,
	// Could make this dynamic, but for now we'll just limit the max amount of steps.
	pitches:   [MAX_TRACK_STEPS]f32,
	volumes: 	[MAX_TRACK_STEPS]f32,
	send1: 	[MAX_TRACK_STEPS]f32,
	send2: 	[MAX_TRACK_STEPS]f32,
	selected_steps: [MAX_TRACK_STEPS]bool,
}

Audio_State :: struct {
	playing:             bool,
	bpm:                 u16,
	tracks:              [dynamic]Track,
	engine:              ^ma.engine,
	// For some reason this thing needs to be globally accessible (at least according to the docs),
	// Perhaps we can localize it later.
	// delay:               ma.delay_node,
	// for now there will be a fixed amount of channels, but irl this will be dynamic.
	// channels are a miniaudio idea of basically audio processing groups. need to dive deeper into this
	// as it probably will help in designging the audio processing stuff.
	audio_groups:        [N_AUDIO_GROUPS]^ma.sound_group,
	//
	// last_step_time: time.Time,
	last_step_time_nsec: i64,
}

SOUND_FILE_LOAD_FLAGS: ma.sound_flags = {.DECODE, .NO_SPATIALIZATION}
N_AUDIO_GROUPS :: 1

/*
We need to free and nil out all pointers in our Odin code that pointed into Miniaudio data, as 
when we hot reload, this data is no longer valid. Any state related to our app, we can keep and
re-use once hot reload is complete.
*/
audio_hot_reload :: proc(old_state: ^Audio_State) { 
	app.audio.playing = false
	audio_uninit_miniaudio()
	audio_init_miniaudio(old_state)
}

/*
Init stuff that's specific to our app and not directly related to miniaudio state.
*/
audio_init :: proc() -> ^Audio_State {
	audio_state := new(Audio_State)
	audio_state.tracks = make([dynamic]Track)
	for i in 0 ..< 4 {
		append(&audio_state.tracks, Track{})
		audio_state.tracks[i].volume 	= f32(map_range(0.0, f64(4) * 10.0, 0.0, 100.0, f64(i + (i * 10.0))))
		audio_state.tracks[i].armed 	= true
		audio_state.tracks[i].n_steps 	= 32
		audio_state.tracks[i].send1 	= 0
		audio_state.tracks[i].send2 	= 0
	}
	audio_state.bpm = 120

	return audio_state
}

/*
Init just the miniaudio related things, this is seperated since we must re-init miniaudio when we
hot reload, where as our own audio state for tracks and stuff, can persist.
*/
audio_init_miniaudio :: proc(audio_state: ^Audio_State) { 
	println("initing mini audio")
	engine := new(ma.engine)

	// config := ma.engine_config_init()
	// rm_config := ma.resource_manager_config_init()
	// rm_config.jobThreadCount = 0
	// resource_manager := new(ma.resource_manager)
	// res := ma.resource_manager_init(&rm_config, resource_manager)
	// assert (res == .SUCCESS)

	// Engine config is set by default when you init the engine, but can be manually set.
	// engine_config := ma.engine_config_init()
	res := ma.engine_init(nil, engine)
	assert(res == .SUCCESS)

	sound_group_config := ma.sound_group_config {
		flags = SOUND_FILE_LOAD_FLAGS,
	}
	for i in 0 ..< N_AUDIO_GROUPS {
		audio_state.audio_groups[i] = new(ma.sound_group)
		res = ma.sound_group_init_ex(engine, &sound_group_config, audio_state.audio_groups[i])
		assert(res == .SUCCESS)
	}

	app.audio = audio_state
	audio_state.engine = engine

	// // init_delay(0.5, 0.3)
	// when ODIN_OS == .Windows {
	// 	println("c:\\Music\\tracker\\3.wav loading...")
	// 	track_set_sound("c:\\users\\n3or3tro\\Music\\tracker\\3.wav", 0)
	// } else {
	// 	track_set_sound("/home/lucas/Music/test_sounds/the-create-vol-4/loops/01-save-the-day.wav", 0)
	// }
}

/*
Only call when you want to completely destroy all audio state and start anew.
*/
audio_uninit :: proc() { 
	audio_uninit_miniaudio()
	delete(app.audio.tracks)
	free(app.audio)
}

/*
Uninit just miniaudio related data. Neccessary when hot-reloading.
*/
audio_uninit_miniaudio :: proc() {
	if app.audio != nil && app.audio.engine != nil { 
		for &track in app.audio.tracks { 
			if track.sound != nil { 
				ma.sound_stop(track.sound)
				ma.sound_uninit(track.sound)
				// Might need to call the specific miniaudio free function.
				free(track.sound)
				track.sound = nil
			}
			// PCM data is probably fine to live across frames. Since we're going to reload
			// the sounds of each track and therefore PCM data would be correct.
			// delete(track.pcm_data.left_channel)
			// delete(track.pcm_data.right_channel)
		}
		for group, i in app.audio.audio_groups { 
			if group != nil {
				ma.sound_group_stop(group)
				ma.sound_group_uninit(group)
				free(group)
				app.audio.audio_groups[i] = nil
			}
		}
		ma.engine_stop(app.audio.engine)
		ma.engine_uninit(app.audio.engine)
		// free(app.audio.engine)
		app.audio.engine = nil
	}
}

track_add_new :: proc() { 
		track : Track
		track.volume 	= 70 
		track.armed 	= true
		track.n_steps 	= 32
		track.send1 	= 0
		track.send2 	= 0
		append(&app.audio.tracks, track)
}

track_set_sound :: proc(path: cstring, which: u32) {
	track := &app.audio.tracks[which]
	if track.sound != nil {
		ma.sound_uninit(track.sound)
		delete(track.sound_path)
	}
	new_sound := new(ma.sound)

	// Need to connect sound into node graph.
	res := ma.sound_init_from_file(
		app.audio.engine,
		path,
		SOUND_FILE_LOAD_FLAGS,
		// At the moment we only have 1 audio group. This will probs change.
		app.audio.audio_groups[0],
		nil,
		new_sound,
	)
	assert(res == .SUCCESS)

	// ma.node_attach_output_bus(cast(^ma.node)new_sound, 0, cast(^ma.node)&app.audio.delay, 0)
	app.audio.tracks[which].sound = new_sound
	app.audio.tracks[which].sound_path = str.clone_from_cstring(path)
}

sound_toggle_playing :: proc(sound: ^ma.sound) {
	if sound == nil {
		println("Passed in a 'nil' sound.\nMost likely this track hasn't been loaded with a sound.")
	} else {
		if ma.sound_is_playing(sound) {
			res := ma.sound_stop(sound)
			assert(res == .SUCCESS)
		} else {
			res := ma.sound_start(sound)
			assert(res == .SUCCESS)
		}
	}
}

sound_set_volume :: proc(sound: ^ma.sound, volume: f32) {
	ma.sound_set_volume(sound, volume)
}

toggle_all_audio_playing :: proc() {
	for track in app.audio.tracks {
		sound_toggle_playing(track.sound)
	}
}

// track_play_step :: proc(which_track: u32) {
// 	track := app.audio.tracks[which_track]
// 	sound := track.sound
// 	step_num := track.curr_step

// 	// this can happen if a track is created and a sound HAS NOT been loaded.
// 	if sound == nil {
// 		return
// 	}

// 	pitch_box, volume_box, send1_box, send2_box := get_substeps_input_from_step(step_num, which_track)
// 	// Assumes all values in the step are valid, which should be the case when enable_step() has been called.
// 	pitch := pitch_difference("C3", pitch_box.value.?.(string)) / 12
// 	volume: f32
// 	switch _ in volume_box.value.(Step_Value_Type) {
// 	case u32:
// 		volume = f32(volume_box.value.?.(u32))
// 	case string:
// 		volume = f32(strconv.atoi(volume_box.value.?.(string)))
// 	}
// 	slice_num: u32
// 	pcm_start: u64 = 0
// 	if app.samplers[which_track].mode == .slice {
// 		slice_value: u32 = 0
// 		switch _ in pitch_box.value.(Step_Value_Type) {
// 		case u32:
// 			slice_value = pitch_box.value.?.(u32)
// 		case string:
// 			slice_value = u32(strconv.atoi(pitch_box.value.?.(string)))
// 		}
// 		if slice_value == 0 {
// 			pcm_start = 0
// 		} else {
// 			if app.samplers[which_track].n_slices > 0 && slice_value != 0 {
// 				slice_value -= 1
// 			}
// 			slice_ratio := f64(app.samplers[which_track].slices[slice_value].how_far)
// 			sound_length: u64
// 			ma.sound_get_length_in_pcm_frames(sound, &sound_length)
// 			pcm_start = u64(f64(sound_length) * slice_ratio)
// 		}
// 	}

// 	// need to figure out sends.
// 	if track.selected_steps[step_num] {
// 		ma.sound_stop(sound)
// 		pitch := track.step_pitches[step_num]
// 		ma.sound_set_pitch(sound, pitch / 12)
// 		ma.sound_set_volume(sound, volume / 100)
// 		ma.sound_seek_to_pcm_frame(sound, pcm_start)
// 		ma.sound_start(sound)
// 	}
// }

// returns number of semitones between 2 notes.
pitch_difference :: proc(from: string, to: string) -> f32 {
	chromatic_scale := make(map[string]int, context.temp_allocator)
	chromatic_scale["C"] = 0
	chromatic_scale["C#"] = 1
	chromatic_scale["D"] = 2
	chromatic_scale["D#"] = 3
	chromatic_scale["E"] = 4
	chromatic_scale["F"] = 5
	chromatic_scale["F#"] = 6
	chromatic_scale["G"] = 7
	chromatic_scale["G#"] = 8
	chromatic_scale["A"] = 9
	chromatic_scale["A#"] = 10
	chromatic_scale["B"] = 11

	from_octave := strconv.atoi(from[len(from) - 1:])
	to_octave := strconv.atoi(to[len(to) - 1:])

	octave_diff := from_octave - to_octave

	from_is_sharp := str.contains(from, "#")
	to_is_sharp := str.contains(to, "#")

	from_note := from_is_sharp ? chromatic_scale[from[0:2]] : chromatic_scale[from[0:1]]
	to_note := to_is_sharp ? chromatic_scale[to[0:2]] : chromatic_scale[to[0:1]]

	octave_diff_in_semitones := octave_diff * 12
	total_diff := octave_diff_in_semitones - (-1 * (from_note - to_note))
	return f32(total_diff)
}

// delay_init :: proc(delay_time: f32, decay_time: f32) {
// 	channels := ma.engine_get_channels(app.audio.engine)
// 	sample_rate := ma.engine_get_sample_rate(app.audio.engine)
// 	config := ma.delay_node_config_init(channels, sample_rate, u32(f32(sample_rate) * delay_time), decay_time)
// 	println(config)
// 	res := ma.delay_node_init(ma.engine_get_node_graph(app.audio.engine), &config, nil, &app.audio.delay)
// 	if res != .SUCCESS {
// 		println(res)
// 		panic("")
// 	}

// 	res = ma.node_attach_output_bus(cast(^ma.node)(&app.audio.delay), 0, ma.engine_get_endpoint(app.audio.engine), 0)
// 	assert(res == .SUCCESS)
// }

delay_enable :: proc() {
}
// This indirection is here coz I was thinking about cachine the pcm wav rendering data,
// since it's a little expensive to re-calc every frame.
track_get_pcm_data :: proc(track: u32) -> (left_channel, right_channel: [dynamic]f32) {
	return app.audio.tracks[track].pcm_data.left_channel, app.audio.tracks[track].pcm_data.right_channel
}

track_store_pcm_data :: proc(track: u32) {
	sound := app.audio.tracks[track].sound
	n_frames: u64
	res := ma.sound_get_length_in_pcm_frames(sound, &n_frames)
	assert(res == .SUCCESS)

	// Code will break if you pass in a .wav file that doesn't have 2 channels.
	buf := make([dynamic]f32, n_frames * 2, context.temp_allocator) // assuming stereo
	defer delete(buf)

	frames_read: u64

	data_source := ma.sound_get_data_source(sound)
	res = ma.data_source_read_pcm_frames(data_source, raw_data(buf), n_frames, &frames_read)
	assert(res == .SUCCESS || res == .AT_END)

	// might have weird off by one errors further in the system. CBF figuring out the math
	// so we just add + 1 the capacity for now
	// left_channel := make([dynamic]f32, frames_read / 2 + 1)
	// right_channel := make([dynamic]f32, frames_read / 2 + 1)
	left_channel := make([dynamic]f32, frames_read)
	right_channel := make([dynamic]f32, frames_read)
	lc_pointer: u64 = 0
	rc_pointer: u64 = 1
	i := 0
	for rc_pointer < frames_read * 2 {
		left_channel[i] = buf[lc_pointer]
		right_channel[i] = buf[rc_pointer]
		i += 1
		lc_pointer += 2
		rc_pointer += 2
	}
	app.audio.tracks[track].pcm_data.left_channel = left_channel
	app.audio.tracks[track].pcm_data.right_channel = right_channel
}


up_one_semitone :: proc(curr_note: string) -> string {
	if len(curr_note) < 2 {
		return curr_note
	}
	curr_value, _ := str.to_upper(curr_note, context.temp_allocator)
	is_sharp := str.contains(curr_value, "#")
	octave := is_sharp ? strconv.atoi(curr_value[2:]) : strconv.atoi(curr_value[1:])
	new_value: string
	switch curr_value[0] {
	case 'A':
		new_value = is_sharp ? tprintf("B{}", octave) : tprintf("A#{}", octave)
	case 'B':
		new_value = tprintf("C{}", octave)
	case 'C':
		new_value = is_sharp ? tprintf("D{}", octave) : tprintf("C#{}", octave)
	case 'D':
		new_value = is_sharp ? tprintf("E{}", octave) : tprintf("D#{}", octave)
	case 'E':
		new_value = tprintf("F{}", octave)
	case 'F':
		new_value = is_sharp ? tprintf("G{}", octave) : tprintf("F#{}", octave)
	case 'G':
		new_value = is_sharp ? tprintf("A{}", octave + 1) : tprintf("G#{}", octave)
	case:
		panic("fuck1")
	}
	return new_value
}

down_one_semitone :: proc(curr_note: string) -> string {
	curr_value := str.to_upper(curr_note, context.temp_allocator)
	is_sharp := str.contains(curr_value, "#")
	octave := is_sharp ? strconv.atoi(curr_value[2:]) : strconv.atoi(curr_value[1:])
	new_value: string

	switch curr_value[0] {
	case 'A':
		new_value = is_sharp ? tprintf("A{}", octave) : tprintf("G#{}", octave - 1)
	case 'B':
		new_value = tprintf("A#{}", octave)
	case 'C':
		new_value = is_sharp ? tprintf("C{}", octave) : tprintf("B{}", octave)
	case 'D':
		new_value = is_sharp ? tprintf("D{}", octave) : tprintf("C#{}", octave)
	case 'E':
		new_value = tprintf("D#{}", octave)
	case 'F':
		new_value = is_sharp ? tprintf("F{}", octave) : tprintf("E{}", octave)
	case 'G':
		new_value = is_sharp ? tprintf("G{}", octave) : tprintf("F#{}", octave)
	case:
		panic("fuck1")
	}
	return new_value
}
