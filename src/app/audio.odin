package app
import "core:fmt"
import "core:math"
import "core:slice"
import "core:sync"
import "core:mem"
import "core:os"
import "core:strconv"
import str "core:strings"
import "core:time"
import ma "vendor:miniaudio"

// At file scope
@(private="file")
spectrum_analyzer_vtable: ma.node_vtable
@(private="file")
spectrum_analyzer_input_channels: [1]u32 = {2}
@(private="file")
spectrum_analyzer_output_channels: [1]u32 = {2}
@(private="file")
spectrum_analyzer_vtable_initialized := false

SAMPLE_RATE : f64 = 44_100
AUDIO_SCHEDULING_HORIZON_MS :: 10

N_TRACK_STEPS :: 128
MAX_TRACKS :: 256
MAX_TRACK_STEPS :: 256
EQ_MAX_GAIN :f64: 24

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
	freq_hz:	f64, // 20hz - 20_000 hz
	gain_db:	f64,
	q:			f64,
	bypass: 	bool,
	type: 		EQ_Band_Type,
	coefficients: struct { 
		b0, b1, b2, a0, a1, a2: f64,
	},
	// biquad_node: Biquad_Node
	biquad_node: ^ma.biquad_node
}

EQ_State :: struct { 
	// Should be 1 list for each EQ and 1 EQ for each track.
	bands : [dynamic]EQ_Band_State,
	// Whether the UI should show this IQ, don't love having this in the audio state but
	// it helps to keep single source of truth.
	show: bool,
	active_band: int,
	frequency_spectrum_bins: [FFT_N_SPECTRUM_BINS]f32
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
	name: 			string,	// Name / label of this track.
	track_num: 		int, // Number ID of this track
	// curr_step:      u32,
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
	sampler: Sampler_State,
	spectrum_analyzer: Spectrum_Analyzer_Node,
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
	paused_at_step: int,
	// Basically in a hot reload situation, I need a way to indicate to the timing thread that it
	// should stop looping and exit when we hot reload the dll. It will be restarted once the new
	// dll is loaded.
	exit_timing_thread: bool,
	last_playback_start_time_pcm: u64,
	last_scheduled_step: int,
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
				gain_db = 0,
				q = 0.7,
			}
			if i == 0 {
				band.type = .Low_Cut
				band.freq_hz = 100
				band.q = 0.707
			}
			if i == 3 { 
				band.type = .High_Cut
				band.freq_hz = 15000 
				band.q = 0.707
			}
			if i == 1 { 
				band.type = .Bell
				band.freq_hz = 3_000 
			}
			if i == 2 { 
				band.type = .Bell
				band.freq_hz = 4_000 
			}
			append(&eq.bands, band)
			
		}
		track.eq = eq^
	}
	audio_state.bpm = 120

	// Init hann window for FFT used in displaying EQ spectrum.
	for i in 0 ..< FFT_WINDOW_SIZE {
		// FFT_HANN_WINDOW[i] = 0.5 * (1 - math.cos(f32(2 * math.PI / (FFT_WINDOW_SIZE - 1))))
		FFT_HANN_WINDOW[i] = 0.5 * (1 - math.cos(2 * math.PI * f32(i) / f32(FFT_WINDOW_SIZE - 1)))

	}
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

	engine_config := ma.engine_config_init()
	engine := new(ma.engine)
	engine_config.sampleRate = 44_100
	res := ma.engine_init(&engine_config, engine)
	assert(res == .SUCCESS)

	sound_group_config := ma.sound_group_config {
		flags = SOUND_FILE_LOAD_FLAGS,
	}
	for i in 0 ..< N_AUDIO_GROUPS {
		audio_state.audio_groups[i] = new(ma.sound_group)
		res = ma.sound_group_init_ex(engine, &sound_group_config, audio_state.audio_groups[i])
		assert(res == .SUCCESS)
	}

	// Init each tracks EQ state.
	node_graph := ma.engine_get_node_graph(engine)
	for track in audio_state.tracks {
		for &band, i in track.eq.bands { 
			eq_init_band(track, &band, node_graph)		
		}
	}
	app.audio = audio_state
	audio_state.engine = engine
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
	had_sound := false
	if track.sound != nil {
		ma.sound_uninit(track.sound)
		delete(track.sound_path)

		// Deleting might be inefficient, could maybe use clear() or something. 
		// But this happens quite infrequently, so should be okay.
		delete(track.pcm_data.left_channel)
		delete(track.pcm_data.right_channel)
		had_sound = true
	}

	new_sound := new(ma.sound)
	
	// Need to connect sound into node graph.
	res := ma.sound_init_from_file(
		app.audio.engine,
		path,
		SOUND_FILE_LOAD_FLAGS,
		nil,
		nil,
		new_sound,
	)
	assert(res == .SUCCESS)

	track.sound = new_sound
	track.sound_path = str.clone_from_cstring(path)

	left, right := sound_get_pcm_data(which)
	track.pcm_data.left_channel  = left
	track.pcm_data.right_channel = right

	/* 
	When a new sound is loaded, we need to wire it up to the EQ of that track, this function is a natural place to do that.
	EQ has to be initialized and valid at this point, otherwise we'll crash!!
	*/

	eq_bands := track.eq.bands

	// Wire sound -> first eq band 
	if len(eq_bands) < 1 do return 
	res = ma.node_attach_output_bus(cast(^ma.node)(track.sound), 0, cast(^ma.node)(eq_bands[0].biquad_node), 0) 
	assert(res == .SUCCESS, tprintf("{}", res))

	// Wire the rest of the bands to each other.
	for i in 1..<len(eq_bands) {
		res = ma.node_attach_output_bus(
			cast(^ma.node)(eq_bands[i-1].biquad_node), 
			0, 
			cast(^ma.node)(eq_bands[i].biquad_node), 
			0
		)
		assert(res == .SUCCESS, tprintf("{}", res))
	}

	// Wire up spectrum analyzer to last band of EQ and out to output.
	if !spectrum_analyzer_vtable_initialized {
		spectrum_analyzer_vtable.inputBusCount = 1
		spectrum_analyzer_vtable.outputBusCount = 1
		spectrum_analyzer_vtable.onProcess = spectrum_analyzer_node_process
		spectrum_analyzer_vtable_initialized = true
	}

	config := ma.node_config_init()
	config.vtable = &spectrum_analyzer_vtable
	config.inputBusCount = 1
	config.outputBusCount = 1
	config.pInputChannels = &spectrum_analyzer_input_channels[0]
	config.pOutputChannels = &spectrum_analyzer_output_channels[0]

	// config := ma.node_config_init()
	// config.vtable = new(ma.node_vtable)
	// config.vtable.inputBusCount = 1
	// config.vtable.outputBusCount = 1
	// config.vtable.onProcess = spectrum_analyzer_node_process
	// config.inputBusCount = 1
	// config.outputBusCount = 1

	// input_channels: [1]u32 = {2}
	// output_channels: [1]u32 = {2}
	// config.pInputChannels = &input_channels[0]
	// config.pOutputChannels = &output_channels[0]

	res = ma.node_init(ma.engine_get_node_graph(app.audio.engine), &config, nil, cast(^ma.node)&track.spectrum_analyzer)
	assert(res == .SUCCESS, tprintf("{}", res))

	last_eq_band := &eq_bands[len(track.eq.bands)-1]

	res = ma.node_attach_output_bus(cast(^ma.node)last_eq_band.biquad_node, 0, cast(^ma.node)&track.spectrum_analyzer, 0)
	assert(res == .SUCCESS, tprintf("{}", res))

	// Wire spectrum analyzer node to -> output
	res = ma.node_attach_output_bus(
		cast(^ma.node)&track.spectrum_analyzer, 
		0, 
		ma.engine_get_endpoint(app.audio.engine), 
		0
	)
	assert(res == .SUCCESS, tprintf("{}", res))
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

audio_toggle_all_playing_state :: proc() {
	for track in app.audio.tracks {
		sound_toggle_playing(track.sound)
	}
}

audio_stop_all :: proc() {
	for track in app.audio.tracks {
		if track.sound != nil { 
			ma.sound_stop(track.sound)
		}
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
		gain_db = 0,
		freq_hz = map_range(0.0, 1.0, 20.0, 20_000.0, f64(how_far)),
		q = 0.7,
		type = band_type
	}
	append(&eq.bands, new_band)
}

eq_init_band :: proc(track: Track, band: ^EQ_Band_State, node_graph: ^ma.node_graph) {
	coeffs := compute_biquad_coefficients(band.freq_hz, band.q, band.gain_db, SAMPLE_RATE, band.type)
	using coeffs
	config := ma.biquad_node_config_init(2, f32(b0), f32(b1), f32(b2), 1, f32(a1), f32(a2))
	node := new(ma.biquad_node)
	res := ma.biquad_node_init(node_graph, &config, nil, node)
	assert(res == .SUCCESS)
	band.biquad_node = node
}

eq_reinit_band :: proc(band: EQ_Band_State) {
	node_graph := ma.engine_get_node_graph(app.audio.engine)
	using band.coefficients
	config := ma.biquad_node_config_init(2, f32(b0), f32(b1), f32(b2), f32(a0), f32(a1), f32(a2))
	res := ma.biquad_node_reinit(&config.biquad, band.biquad_node)
	assert(res != .ERROR)
}

// ========================================= END EQ STUFF ==========================================

delay_enable :: proc() {
}


/*  
	Any data that is written to from outside this thread needs to be accessed atomically 
	inside this thread. Might need to use locks, unclear right now.
*/
audio_thread_timing_proc :: proc() {
	for {
		if sync.atomic_load(&app.audio.exit_timing_thread) do return

		playing := sync.atomic_load(&app.audio.playing)
		if playing {
			curr_time_pcm := ma.engine_get_time_in_pcm_frames(app.audio.engine)
			step_time_pcm := (SAMPLE_RATE / N_TRACK_STEPS)
			// Assumes 1/32 steps.
			beats_per_bar :: 4
			steps_per_bar :: 32
			steps_per_beat := steps_per_bar / beats_per_bar 
			samples_per_step := SAMPLE_RATE * 60 / f64(app.audio.bpm) / f64(steps_per_beat)

			// The only way to get sample accurate playback with the high level engine in miniaudio
			// is to schedule a future time for a sound to start playing.
			horizon_samples := SAMPLE_RATE * AUDIO_SCHEDULING_HORIZON_MS / 1000

			last_playback_start_time := sync.atomic_load(&app.audio.last_playback_start_time_pcm)
			last_scheduled_step := sync.atomic_load(&app.audio.last_scheduled_step)

			// Calculate which step we're currently on and how far ahead to schedule.
			elapsed_pcm := curr_time_pcm - last_playback_start_time
			current_step := int(f64(elapsed_pcm) / samples_per_step)
			horizon_step := int((elapsed_pcm + u64(horizon_samples)) / u64(samples_per_step))

			// Schedule next steps to be played.
			for step := last_scheduled_step + 1; step <= horizon_step; step += 1 {
				step_start_time_pcm := last_playback_start_time + u64(f64(step) * samples_per_step)
				
				for &track, track_num in app.audio.tracks {
					step_in_pattern := u32(step) % track.n_steps
					
					if track.armed && track.selected_steps[step_in_pattern] {
						schedule_track_step(u32(track_num), step_in_pattern, step_start_time_pcm)
					}
				}
				sync.atomic_store(&app.audio.last_scheduled_step, step)
			}
		} 
		// Sleep to conserve energy.
		time.accurate_sleep(time.Millisecond * 10)
	}
}

schedule_track_step :: proc(which_track: u32, step_num: u32, start_time_pcm: u64) {
    track := &app.audio.tracks[which_track]
    sound := track.sound
    if sound == nil do return
    
    pitch 		 := f32(track.pitches[step_num])
    sound_volume := f32(track.volumes[step_num])
    
    ma.sound_set_pitch(sound, pitch / 12)
    ma.sound_set_volume(sound, (sound_volume / 100) * track.volume / 100)
    ma.sound_seek_to_pcm_frame(sound, 0)
    ma.sound_set_start_time_in_pcm_frames(sound, start_time_pcm)
	// Sound will start the exact moment the engine reaches start_time_pcm, even though we 
	// called start already
    ma.sound_start(sound)
}

audio_get_current_step :: proc() -> int {
	paused := sync.atomic_load(&app.audio.paused_at_step) 
	if paused >= 0 {
		return paused
	}
	curr_time_pcm 	 := ma.engine_get_time_in_pcm_frames(app.audio.engine)
    last_start_time  := sync.atomic_load(&app.audio.last_playback_start_time_pcm)
	// Assumes 32 steps per beat.
    samples_per_step := u64(SAMPLE_RATE * 60 / f64(app.audio.bpm) / 8)
    elapsed 		 := curr_time_pcm - last_start_time
    return int(elapsed / samples_per_step)
}