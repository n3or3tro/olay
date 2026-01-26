package app
import "core:fmt"
import "core:sync"
import "core:mem"
import "core:os"
import "core:strconv"
import str "core:strings"
import "core:time"
import ma "vendor:miniaudio"

N_TRACK_STEPS :: 128
MAX_TRACKS :: 256
MAX_TRACK_STEPS :: 256
EQ_MAX_GAIN :f32: 24

Sampler_Slice :: struct {
	// How far along into the sound is this.
	how_far: f32,
	// Which slice is this. NOT the same as it's order along the x-axis.
	// This is included because I was getting weird issues upon re-ordering the existing
	// slices in sampler.slices.
	which:   u32,
}

Sampler_State :: struct {
	n_slices:         u32,
	mode:             enum {
		slice,
		warp,
		one_shot,
	},
	// Store how far along the length of the container the marker goes: [0-1].
	slices:           [128]Sampler_Slice,
	// How zoomed in the view of the wav data is.
	zoom_amount:      f32,
	// Where the zoom occurs 'around'. This changes as you move the mouse.
	// Doesn't change when you're zooming as it's relevant to the rect, not the wave.
	zoom_point:       f32,
	// To help avoid double actions on 'clicked' when dragging a slice.
	dragging_a_slice: bool,
	// Identify which slice is being dragged. Had issues with mouse going ahead of dragged box,
	// so trying to implement 'sticky stateful' dragging.
	dragged_slice:    u32,
	// Whether to hide or show the sampler in the UI.
	show: 			  bool
}

EQ_Band_Type :: enum { 
	Bell,
	High_Cut,
	Low_Cut,
	High_Shelf,
	Low_Shelf,
	Band_Pass, 
	Notch,
}

EQ_Band_State :: struct { 
	// Not sure whether to store their frequency loation or position inside parent.
	// Either way I imagine we'll have to convert back and forth.
	pos: 		f32, // 0 = left end of parent, 1 = right end of parent.
	gain:		f32,
	q:			f32,
	bypass: 	bool,
	type: 		EQ_Band_Type
}

EQ_State :: struct { 
	// Should be 1 list for each EQ and 1 EQ for each track.
	bands : [dynamic]EQ_Band_State,
	// Whether the UI should show this IQ, don't love having this in the audio state but
	// it helps to keep single source of truth.
	show: bool,
	active_band: int,
}

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
	name: string,	// Name / label of this track.
	track_num: int, // Number ID of this track
	curr_step:      u32,
	// Actual amount of steps in the track.
	n_steps:        u32,
	// Could make this dynamic, but for now we'll just limit the max amount of steps.
	pitches:   [MAX_TRACK_STEPS]int, // 1 = C#3, 2 = D3, 0 = C3, -1 = B3, -2 = A#3, etc
	// Not sure if these should be floats or ints....
	volumes: 	[MAX_TRACK_STEPS]int,
	send1: 	[MAX_TRACK_STEPS]int,
	send2: 	[MAX_TRACK_STEPS]int,
	selected_steps: [MAX_TRACK_STEPS]bool,
	eq:		 EQ_State,
	sampler: Sampler_State
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
	// Basically in a hot reload situation, I need a way to indicate to the timing thread that it
	// should stop looping and exit when we hot reload the dll. It will be restarted once the new
	// dll is loaded.
	exit_timing_thread: bool,
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
		track_add_new(audio_state)
	}

	// For testing, add an eq for each track, with 4 points equally distributed across the frequency.
	for &track in audio_state.tracks { 
		eq := new(EQ_State)
		for i in 0..< 4 { 
			band := EQ_Band_State {
				gain = 0,
				pos = i == 0 ? 0.0 : 0.25 * f32(i + 1),
				type = .Bell,
				q = 1,
			}
			append(&eq.bands, band)
		}
		track.eq = eq^
	}
	audio_state.bpm = 120

	return audio_state
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

track_add_new :: proc(audio_state: ^Audio_State) { 
		track : Track
		track.volume 	= 50 
		track.armed 	= true
		track.n_steps 	= N_TRACK_STEPS
		for &volume in track.volumes { 
			volume = 50
		}
		// Other step values are 0 by default.
		// track.name = "Default name"
		append(&audio_state.tracks, track)
}

track_set_sound :: proc(which: u32, path: cstring) {
	track := &app.audio.tracks[which]
	if track.sound != nil {
		ma.sound_uninit(track.sound)
		delete(track.sound_path)

		// Deleting might be inefficient, could maybe use clear() or something. 
		// But this happens quite infrequently, so should be okay.
		delete(track.pcm_data.left_channel)
		delete(track.pcm_data.right_channel)
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
	track.sound = new_sound
	track.sound_path = str.clone_from_cstring(path)

	left, right := sound_get_pcm_data(which)
	track.pcm_data.left_channel  = left
	track.pcm_data.right_channel = right
}

track_play_step :: proc(which_track: u32) {
	track := app.audio.tracks[which_track]
	sound := track.sound
	step_num := track.curr_step

	// This can happen if a track is created and a sound HAS NOT been loaded.
	if sound == nil {
		return
	}

	pcm_start: u64 = 0
	// slice_num: u32
	// if app.audio.tracks[which_track].sampler.mode == .slice {
	// 	slice_value: u32 = 0
	// 	switch _ in pitch_box.value.(Step_Value_Type) {
	// 	case u32:
	// 		slice_value = pitch_box.value.?.(u32)
	// 	case string:
	// 		slice_value = u32(strconv.atoi(pitch_box.value.?.(string)))
	// 	}
	// 	if slice_value == 0 {
	// 		pcm_start = 0
	// 	} else {
	// 		if app.samplers[which_track].n_slices > 0 && slice_value != 0 {
	// 			slice_value -= 1
	// 		}
	// 		slice_ratio := f64(app.samplers[which_track].slices[slice_value].how_far)
	// 		sound_length: u64
	// 		ma.sound_get_length_in_pcm_frames(sound, &sound_length)
	// 		pcm_start = u64(f64(sound_length) * slice_ratio)
	// 	}
	// }

	// need to figure out sends.
	if track.selected_steps[step_num] {
		ma.sound_stop(sound)
		pitch := f32(track.pitches[step_num])
		volume := f32(track.volumes[step_num])
		ma.sound_set_pitch(sound, pitch / 12)
		ma.sound_set_volume(sound, volume / 100)
		ma.sound_seek_to_pcm_frame(sound, pcm_start)
		ma.sound_start(sound)
	}
}

/*
This function will turn on step <starting_step> for track <track_num>,
and then <every_nth> step after that.
*/
track_turn_on_steps :: proc(track_num, starting_step, every_nth: int) {
	track := &app.audio.tracks[track_num]	
	for i := starting_step; i < int(track.n_steps); i += every_nth { 
		track.selected_steps[i] = true
	}
}

/*
As above, but it turns steps off.
*/
track_turn_off_steps :: proc(track_num, starting_step, every_nth: int) {
	track := &app.audio.tracks[track_num]	
	for i := starting_step; i < int(track.n_steps); i += every_nth { 
		track.selected_steps[i] = false
	}
}

track_toggle_step :: proc(track_num, step: int) {
	app.audio.tracks[track_num].selected_steps[step] = !app.audio.tracks[track_num].selected_steps[step]
}

track_delete :: proc(track_num: int) { 
	printfln("removing track {}", track_num)
	ordered_remove(&app.audio.tracks, track_num)
}

// This indirection is here coz I was thinking about caching the pcm wav rendering data,
// since it's a little expensive to re-calc every frame.
track_get_pcm_data :: proc(track: u32) -> (left_channel, right_channel: [dynamic]f32) {
	return app.audio.tracks[track].pcm_data.left_channel, app.audio.tracks[track].pcm_data.right_channel
}

sound_get_pcm_data :: proc(track: u32, allocator:=context.allocator) -> (left_channel, right_channel: [dynamic]f32) {
	sound := app.audio.tracks[track].sound
	n_frames: u64
	res := ma.sound_get_length_in_pcm_frames(sound, &n_frames)
	assert(res == .SUCCESS)

	// Code will break if you pass in a .wav file that doesn't have 2 channels.
	buf := make([dynamic]f32, n_frames * 2, context.temp_allocator) // assuming stereo
	frames_read: u64

	data_source := ma.sound_get_data_source(sound)
	res = ma.data_source_read_pcm_frames(data_source, raw_data(buf), n_frames, &frames_read)
	assert(res == .SUCCESS || res == .AT_END)

	left_channel  = make([dynamic]f32, frames_read, allocator)
	right_channel = make([dynamic]f32, frames_read, allocator)
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
	return left_channel, right_channel
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

// returns number of semitones between 2 notes.
pitch_difference :: proc(from: string, to: string) -> int {
	chromatic_scale := make(map[string]int, context.temp_allocator)

	chromatic_scale["A"] = 0
	chromatic_scale["A#"] = 1
	chromatic_scale["B"] = 2
	chromatic_scale["C"] = 3
	chromatic_scale["C#"] = 4
	chromatic_scale["D"] = 5
	chromatic_scale["D#"] = 6
	chromatic_scale["E"] = 7
	chromatic_scale["F"] = 8
	chromatic_scale["F#"] = 9
	chromatic_scale["G"] = 10
	chromatic_scale["G#"] = 11

	from_octave := strconv.atoi(from[len(from) - 1:])
	to_octave := strconv.atoi(to[len(to) - 1:])

	octave_diff := from_octave - to_octave

	from_is_sharp := str.contains(from, "#")
	to_is_sharp := str.contains(to, "#")

	from_note := from_is_sharp ? chromatic_scale[from[0:2]] : chromatic_scale[from[0:1]]
	to_note := to_is_sharp ? chromatic_scale[to[0:2]] : chromatic_scale[to[0:1]]

	octave_diff_in_semitones := octave_diff * 12
	total_diff := octave_diff_in_semitones - (-1 * (from_note - to_note))
	return -1 * int(total_diff)
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

valid_pitch :: proc(s: string) -> bool { 
	s_len := len(s)

	if s_len != 2 && s_len != 3 {
		return false
	} 
	else if s_len == 2 { 
		if !str.contains("ABCDEFGabcdefg", s[0:1]) { 
			return false
		}
		if !str.contains("0123456789", s[1:2]) { 
			return false
		}
		return true
	}
	else if s_len == 3 {
		if !str.contains("ABCDEFGabcdefg", s[0:1]) { 
			return false
		}
		if s[1] != '#' { 
			return false
		}
		if !str.contains("0123456789", s[2:3]) { 
			return false
		}
		return true
	} 
	return false
}

/*
Pitches are stored as ints, but represented and edited throughout the UI as strings. So These 2 functions below
help swap to and fro.
*/
pitch_get_from_note :: proc(pitch: string) -> int{ 
	return int(pitch_difference("C3", pitch))
}
pitch_set_from_note :: proc(track, step: int, pitch: string) { 
	app.audio.tracks[track].pitches[step] = int(pitch_difference("C3", pitch))
}

get_note_from_num :: proc(pitch: int) -> string{ 
	if pitch > 0 { 
		// We're up from C3
		curr_note := "C3"
		for i in 0 ..< pitch { 
			curr_note = up_one_semitone(curr_note)
		}
		return curr_note
	}
	else if pitch < 0 { 
		// We're down from C3
		curr_note := "C3"
		for i in 0 ..< -1*pitch { 
			curr_note = down_one_semitone(curr_note)
		}
		return curr_note
	}
	else {
		return "C3"
	}
}


// ========================================= EQ STUFF ==============================================
eq_add_band::proc(track_num: int, how_far:f32, band_type: EQ_Band_Type) {
	eq := &app.audio.tracks[track_num].eq
	new_band := EQ_Band_State {
		bypass = false,
		gain = 0,
		pos = how_far,
		q = 0.7,
		type = band_type
	}
	append(&eq.bands, new_band)
}
// ========================================= END EQ STUFF ==========================================


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


/*  
	Any data that is written to from outside this thread needs to be accessed atomically 
	inside this thread. Might need to use locks, unclear right now.
	Re-runs every 1ms.
*/
audio_thread_timing_proc :: proc() {
	audio_start_time := time.now()
	// This moves the step marker at 1/4 steps at 120 BPM.
	time_between_beats := i64(60_000 / f64(app.audio.bpm) / 4)
	// Probably need a special case to handle the first step.
	SCROLL_THRESHOLD :: 16
	for {
		if sync.atomic_load(&app.audio.exit_timing_thread) { 
			return
		}
		start_time := time.now()
		last_step_time := app.audio.last_step_time_nsec
		if sync.atomic_load(&app.audio.playing) {
			curr_time := time.now()
			time_since_last_step := (curr_time._nsec - last_step_time) / 1000 / 1000
			if time_since_last_step >= time_between_beats {
				for &track, track_num in app.audio.tracks {
					track.curr_step = (track.curr_step + 1) % track.n_steps
					// if track.curr_step > ui_state.steps_vertical_offset + NUM_VISIBLE_STEPS - SCROLL_THRESHOLD {
					// 	ui_state.steps_vertical_offset = track.curr_step - (NUM_VISIBLE_STEPS - SCROLL_THRESHOLD)
					// }
					// if track.curr_step < ui_state.steps_vertical_offset {
					// 	ui_state.steps_vertical_offset = track.curr_step
					// }
					if track.armed {
						if track.selected_steps[track.curr_step] {
							track_play_step(u32(track_num))
						}
					}
				}
				sync.atomic_store(&app.audio.last_step_time_nsec, time.now()._nsec)
			}
		}
		end_time := time.now()
		// This might break if we take > 1ms in the above loop.
		time.accurate_sleep(time.Microsecond * 1000 - time.Duration(end_time._nsec - start_time._nsec))
	}
}