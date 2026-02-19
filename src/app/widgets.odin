/* 
These are hotpaths that call box_from_cache in a preconfigured way as to achieve the 
effect of what a user would normally call a 'widget' in a traditional UI framework.

The idea is that they're more specific to this application, where as the hotpaths in builder_basics.odin
should be relatively ubiqitous amongst most UIs. However I do have application specific logic in them,
so they'll need some re-thinking when I ship the UI stuff as a lib.
*/

package app
import "core:math"
import "core:time"
import "core:math/cmplx"
import "core:mem"
import "core:sync"
import "core:path/filepath"
import str "core:strings"
import ma"vendor:miniaudio"


topbar :: proc() {
	child_container(
		{
			size    = {{.Fixed, f32(app.wx)}, {.Fixed, TOPBAR_HEIGHT}},
			color = .Secondary,
			padding = {top = 3, bottom = 3}
		},
		{
			direction = .Horizontal,
			alignment_horizontal = .Space_Between,
			alignment_vertical = .Center,
			gap_horizontal = 5,
		},
		"topbar",
	)

	btn_config := Box_Config {
		size = {{.Fit_Text_And_Grow, 1}, {.Fit_Text_And_Grow, 1}},
		color = .Tertiary,
		corner_radius = 5,
		padding = {top = 0, bottom = 0, left = 2, right = 2},
	}

	left_container: {
		child_container(
			{size = {{.Fit_Children, 1}, {.Fit_Children_And_Grow, 1}}},
			{gap_horizontal = 3},
			"top-bar-left-container",
		)
		if text_button("undo", btn_config, "top-bar-undo").clicked {
			undo()
		}
		if text_button("redo", btn_config, "top-bar-redo").clicked {
			redo()
		}
		if text_button("render wav", btn_config, "top-bar-render").clicked {
			audio_export_to_wav()
		}
	}

	middle_container: {
		child_container(
			{size = {{.Fit_Children, 1}, {.Fit_Children_And_Grow, 1}}},
			{gap_horizontal = 3},
			"top-bar-middle-container",
		)
		if text_button("Reset", btn_config).clicked {
			audio_transport_reset()
		} 

		label := app.audio.playing ? "Pause" : "Play"
		if text_button(label, btn_config).clicked {
			if app.audio.playing  {
				audio_transport_pause()
			} else {
				audio_transport_play()
			} 
		}
	}

	right_container: {
		child_container(
			{size = {{.Fit_Children, 1}, {.Fit_Children_And_Grow, 1}}},
			{gap_horizontal = 3},
			"top-bar-right-container",
		)
		if text_button("Default layout", btn_config, "top-bar-default").clicked {
			ui_state.tab_num = 0
			ui_state.changed_ui_screen = true
		}
		if text_button("Test layout", btn_config, "top-bar-test").clicked {
			ui_state.tab_num = 1
			ui_state.changed_ui_screen = true
		}
		sidebar_label := ui_state.sidebar_shown ? "Close sidebar" : "Open sidebar"
		sidebar_id := ui_state.sidebar_shown ? "top-bar-sidebar-close" : "top-bar-sidebar-open"
		if text_button(sidebar_label, btn_config, sidebar_id).clicked {
			ui_state.sidebar_shown = !ui_state.sidebar_shown
		}
	}
}

audio_track :: proc(track_num: int, track_width: f32, step_containers: ^[dynamic]^Box, extra_flags := Box_Flags{}) -> Track_Signals {
	track := &app.audio.tracks[track_num]
	n_steps := 128 // This will ultimately be a dynamic size for each track.

	track_container := child_container(
		{size = {{.Fixed, track_width}, {.Percent, 1}}},
		{direction = .Vertical, gap_vertical = 3},
		metadata = Metadata_Track {
			track_num = track_num
		},
	)
	track_container.box.disabled = !track.armed
	track_container.box.metadata = Metadata_Track{
		track_num = track_num
	}
	track_label: {
		child_container(
			{
				size = {{.Fixed, track_width}, {.Fit_Children, 1}},
				padding = {left = 2, right = 0}
			},
			{
				direction = .Horizontal,
				alignment_horizontal = .Center,
				alignment_vertical = .Center
			},
		)
		text(
			tprintf("{}.", track_num),
			{
				size = Size_Fit_Text,
				color = .Primary_Container,
				text_justify = {.Start, .Center},
				margin = {right = 2}
			},
		)
		edit_text_box(
			{
				size = {{.Grow, 1}, {.Fixed, 30}},
				color = .Secondary
			},
			.Generic_One_Line,
		)
	}

	step_signals: Track_Steps_Signals
	track_dropped_on: bool
	steps: {
		steps_container := child_container(
			{
				size = {{.Fixed, track_width + 30}, {.Grow, 0.1}},
				color = .Tertiary,
				overflow_y = .Scroll
			},
			{direction = .Vertical, gap_vertical = 0},
			box_flags = {.Drag_Drop_Source, .Scrollable},
		)
		append(step_containers, steps_container.box)


		substep_config: Box_Config = {
			size    		 = {{.Percent, 0.25}, {.Percent, 1}},
			color 			 = .Primary,
			border 			 = 1,
		}
		substep_extra_flags := Box_Flags{.Draw_Border, .Track_Step, .Drag_Drop_Sink}

		loop_back_step := track.loop_at
		for i in 0 ..< N_TRACK_STEPS {
			child_container({size = {{.Fixed, track_width + 30}, {.Percent, 1.0/32.0}}}, {})
			text(tprintf("{}", i), {size={{.Fixed, 30}, {.Percent, 1}}, text_justify={.Center, .Center}, color = .Surface})
			step_row_container := child_container(
				{size = {{.Fixed, track_width - 30}, {.Percent, 1}}},
				{direction = .Horizontal, gap_horizontal = 0},
				box_flags = {.Drag_Drop_Sink},
			)
			if loop_back_step != -1 && i > loop_back_step {
				step_row_container.box.disabled = true
			}

			if i == loop_back_step {
				loop_back_indicator := text_button(
					"remove loop back",
					{
						size = Size_Fit_Text_And_Grow
					}
				)
				if loop_back_indicator.double_clicked {
					track.loop_at = -1
				} 
				break
			}

			pitch_box := edit_text_box(
				substep_config,
				.Pitch,
				metadata = Metadata_Track_Step {
					track = track_num,
					step  = i,
					type  = .Pitch,
				},
				extra_flags = substep_extra_flags,
			)

			volume_box := edit_number_box(
				substep_config,
				0,
				100,
				metadata = Metadata_Track_Step {
					track = track_num,
					step  = i,
					type  = .Volume,
				},
				extra_flags =substep_extra_flags,
			)

			send1_box := edit_number_box(
				substep_config,
				0,
				100,
				metadata = Metadata_Track_Step {
					track = track_num,
					step  = i,
					type  = .Send1,
				},
				extra_flags = substep_extra_flags,
			)

			send2_box := edit_number_box(
				substep_config,
				0,
				100,
				metadata = Metadata_Track_Step {
					track = track_num,
					step  = i,
					type  = .Send2,
				},
				extra_flags = substep_extra_flags,
			)

			if pitch_box.double_clicked  ||
			   volume_box.double_clicked ||
			   send1_box.double_clicked  ||
			   send2_box.double_clicked 
			{
				track_toggle_step(track_num, i)
			}

			if pitch_box.dropped_on  ||
			   volume_box.dropped_on ||
			   send1_box.dropped_on  ||
			   send2_box.dropped_on  ||
			   step_row_container.dropped_on 
			{
				track_dropped_on = true
			}


			// Set box.selected if audio state says that this step is toggled on.
			// This is kind of ugly, but old code in the renderer relies on this bool,
			// so we'll do this little hack for now.
			if track.selected_steps[i] { 
				pitch_box.box.selected  = true
				volume_box.box.selected = true
				send1_box.box.selected  = true
				send2_box.box.selected  = true
			} else { 
				pitch_box.box.selected  = false
				volume_box.box.selected = false
				send1_box.box.selected  = false
				send2_box.box.selected  = false
			}
			curr_step_global := audio_get_current_step()
			curr_step := track.loop_at == -1 ? curr_step_global % int(track.n_steps) : curr_step_global % track.loop_at
			// If this is the current step, indicate so.
			if curr_step == i {
				pitch_box.box.config.color  = .Primary_Container
				volume_box.box.config.color = .Primary_Container
				send1_box.box.config.color  = .Primary_Container
				send2_box.box.config.color  = .Primary_Container
			}
		}
	}

	// Because we check this here, only the steps part will 'absorb' a file if dropped,
	// can be refactored to support the whole track, but it'll be uglier.
	handle_drop: if track_dropped_on {
		// Right now we'll panic if the drop data len > 1, but IRL this probably isn't an error behaviour,
		// should probably just only accept the first file in the selection.
		if len(ui_state.dropped_data) < 1 do break handle_drop
		drop_data := pop(&ui_state.dropped_data)
		cpath: cstring
		#partial switch val in drop_data {
			case Browser_File:
				// full_path := tprintf("/{}/{}", val.parent.path, val.name)
				full_path, err := filepath.join({val.parent.path, val.name}, context.temp_allocator)
				cpath = str.clone_to_cstring(full_path)
				printfln("dropped {} onto track", full_path)
				// printfln("dropped {} onto track", val.name)
				// printfln("it's parent is: {}", val.parent)
			case:
				println("Cant drop this onto a track")
		}
		track_set_sound(u32(track_num), cpath)
	}

	sample_label: {
		label : string
		if track.sounds[0] != nil { 
			tokens, _ := str.split(track.sound_path, "\\", context.temp_allocator)
			label = tail(tokens)^
		} else {
			label = "No sound loaded"
		}
		text(
			label,
			{
				size = {{.Fit_Text_And_Grow, 1}, {.Fit_Text, 1}},
				color = .Primary_Container,
				text_justify = {.Start, .Center},
				overflow_x = .Hidden
			},
			id("{}{}-file-info", label, track_num),
			{.Drag_Drop_Source},
			// {.Draw}
		)
	}

	controls: {
		controls_container := child_container(
			{
				size = {{.Fixed, track_width}, {.Percent, 0.3}},
				color = .Surface_Bright,
			},
			{
				direction = .Horizontal,
				alignment_horizontal = .Start,
				alignment_vertical = .End
			},
			id("track-{}-controls-container", track_num),
			{.Draw, .Drag_Drop_Source},
		)
		arm_label := app.audio.tracks[track_num].armed ? "unarm" : "arm"
		arm_button := text_button(
			arm_label,
			{
				size = {{.Percent, 0.333}, {.Fixed, 30}},
				color = .Secondary,
				corner_radius = 3,

			},
			id("{}track-{}-arm-button", arm_label, track_num),
			{.Ignore_Parent_Disabled},
		)
		volume_slider := vertical_slider(
			{size = {{.Percent, 0.333}, {.Grow, 30}}},
			&track.volume,
			0,
			100,
			id("heytrack-{}-volume-slider", track_num),
		)
		load_sound_button := text_button(
			"load",
			{
				size = {{.Percent, 0.333}, {.Fixed, 30}},
				color = .Secondary,
				corner_radius = 3,
			},
			id("loadtrack-{}-load-sound-button", track_num),
		)
		if arm_button.clicked { 
			app.audio.tracks[track_num].armed = !app.audio.tracks[track_num].armed 
		}
		if load_sound_button.clicked {
			paths, ok := file_dialog(false)
			if ok { 
				path := paths[0]
				track_set_sound(u32(track_num), path)
			} else { 
				println("Opening the file dialog ended in NOT returning a file path")
			}
		}
	}

	show_eq: if track.eq.show {
		_, closed := draggable_window(
			id("Track {} EQ", track_num),
			{direction = .Vertical},
			id("eq-{}-dragging-container", track_num),
		)
		if closed {
			track.eq.show = false
			break show_eq
		}
		equalizer_8(id("track-{}-eq", track_num), track_num)
	}

	show_sampler: if track.sampler.show {
		_, closed := draggable_window(
			id("Track {} Sampler", track_num),
			{direction = .Vertical},
			id("sampler-{}-dragging-container", track_num),
		)
		if closed {
			track.sampler.show = false
			break show_sampler
		}
		sampler(track_num, id("track-{}-sampler", track_num))
	}
	return Track_Signals{step_signals, {}}
}



equalizer_8 :: proc(eq_id: string, track_num: int) {
	eq_state := &app.audio.tracks[track_num].eq
	// Fixed size for now, for ease of implementation, but in the future we want this to be inside a
	// resizable floating container.
	eq_container := child_container(
		{
			size = {{.Fixed, 800}, {.Fixed, 400}},
			color = .Secondary_Container,
			z_index = 10,
			padding = padding(3),
		},
		{
			alignment_horizontal = .Space_Between
		},
		id("{}-container", eq_id),
		{.Draw},
	)
	
	// For now, we auto create 4 bands for each eq (1 eq per track by default).
	active_band := &eq_state.bands[eq_state.active_band]

	eq: {
		child_container(
			{
				// size = {{.Percent, 0.3}, {.Percent, 0.5}},
				size = Size_Fit_Children_And_Grow,
				z_index = 30,
				color = .Error_Container,
			},
			{
				gap_horizontal = 4,
			},
			id("{}-main-content", eq_id),
			{.Draw},
		)
		main_controls: {
			eq_main_controls := child_container(
				{
					size = {{.Percent, 0.11}, {.Percent, 1}},
					// padding = {left=4, right=4, top=10, bottom=10},
				},
				{
					direction = .Vertical,
					alignment_vertical = .Space_Around,
					alignment_horizontal = .Center,
				},
				id("{}-main-controls", eq_id),
				{.Draw},
			)
			text(
				id("Band {}", eq_state.active_band),
				{size=Size_Fit_Text, color = .Secondary},
				"heya",
			)
			circular_knob(
				"Freq",
				{color = .Warning_Container},
				&active_band.freq_hz,
				20,
				20_000,
			)
			circular_knob(
				"Q",
				{color = .Warning_Container},
				&active_band.q,
				0,
				10,
			)
			circular_knob(
				"Gain",
				{color = .Warning_Container},
				&active_band.gain_db,
				-EQ_MAX_GAIN,
				EQ_MAX_GAIN,
			)
		}
		freq_display: {
			frequency_display_container := child_container(
				{
					size = Size_Grow,
					// size = {{.Fixed, 800}, {.Fixed, 500}},
					color = .Inverse_On_Surface,
					overflow_x = .Hidden,
					overflow_y = .Hidden,
				},
				{alignment_horizontal = .Space_Between},
				id("{}-frequency-display-container", eq_id),
				{.Draw, .Clickable},
			)

			if frequency_display_container.double_clicked {
				box := frequency_display_container.box
				eq_add_band(track_num, f32(map_range(f64(box.top_left.x), f64(box.bottom_right.x), 0.0, 1.0, f64(app.mouse_last_frame.pos.x))), .Bell)
			}
			
			handles := make([dynamic]^Box, context.temp_allocator)
			for &band, i in eq_state.bands {
				handle := box_from_cache(
					{.Draw, .Clickable, .Draggable, .Scrollable},
					{
						color = eq_state.active_band == i ? .Error_Container : .Warning_Container,
						floating_type = .Relative_Other,
						floating_anchor_box = frequency_display_container.box,
						floating_offset = {
							// Convert freq to log-scaled position:
							f32(math.log10(f64(band.freq_hz) / 20.0) / math.log10(f64(20_000.0 / 20.0))),
							f32(map_range(EQ_MAX_GAIN, -EQ_MAX_GAIN, 0.0, 1.0, band.gain_db))
						},
						size = {{.Fixed, 30}, {.Fixed, 30}},
						corner_radius = 15,
						z_index  = 40,
					},
					metadata = Metadata_EQ_Handle {
						which = i, 
						band = &band,
						track_num = track_num
					}
				)
				append(&handles, handle)
				handle_signals := box_signals(handle)

				if handle_signals.hovering {
					println("hovering over band")
					if handle_signals.scrolled_up {
						println("scrolled up")
						band.q += 0.07
					}
					if handle_signals.scrolled_down {
						println("scrolled down")
						band.q -= 0.07
					}
				}

				if handle_signals.clicked || handle_signals.box == ui_state.dragged_box { 
					eq_state.active_band = i
				}
				if handle_signals.box == ui_state.dragged_box { 
					mouse_y := f64(app.mouse.pos.y)
					parent_top := f64(handle.parent.top_left.y)  
					parent_height := f64(handle.parent.prev_height)
					normalized_pos := clamp((mouse_y - parent_top) / parent_height, 0.0, 1.0)
					band.gain_db = map_range(0.0, 1.0, EQ_MAX_GAIN, -EQ_MAX_GAIN, normalized_pos)

					mouse_x := f64(app.mouse.pos.x)
					parent_left := f64(handle.parent.top_left.x)
					parent_width := f64(handle.parent.prev_width)  
					normalized_pos = clamp((mouse_x - parent_left) / parent_width, 0.0, 1.0)
					// Convert position back to freq (exponential):
					band.freq_hz = 20.0 * math.pow(20_000.0 / 20.0, f64(normalized_pos))
				}
				if handle_signals.double_clicked { 
					ordered_remove(&eq_state.bands, i)
				}
			}
			
			curve_total : [256]f64
			for &band, i in eq_state.bands {
				if band.bypass do continue
				coeffs := compute_biquad_coefficients(f64(band.freq_hz), f64(band.q), f64(band.gain_db), SAMPLE_RATE, band.type)
				band.coefficients = {
					a0 = 1,
					a1 = coeffs.a1, 
					a2 = coeffs.a2, 
					b0 = coeffs.b0, 
					b1 = coeffs.b1, 
					b2 = coeffs.b2, 
				}
				band_points := generate_curve_points(coeffs, 44_100)
				for i in 0..<len(curve_total) {
					curve_total[i] += band_points[i]
				}
				// Not efficient to re-do this even when we have no changes. Must change later.
				eq_reinit_band(band)
			}

			// Draw frequency spectrum of the playing sound.
			spectrum_analyzer 	:= &app.audio.tracks[track_num].spectrum_analyzer
			ring_buffer 		:= &spectrum_analyzer.ring_buffer
			// write_pos 			:= sync.atomic_load(&spectrum_analyzer.write_pos)

			// Probably don't need to continously copy the entire buffer, since we only store like 
			// a couple hundred floats each audio upate.
			ring_buffer_copy : [FFT_WINDOW_SIZE]f32
			mem.copy(&ring_buffer_copy, ring_buffer, FFT_WINDOW_SIZE * size_of(f32))
			
			// FFT expects complex numbers that have been passed through a windowing function.
			fft_input: [FFT_WINDOW_SIZE]complex64
			for &sample, i in ring_buffer_copy { 
				fft_input[i] = complex(sample * FFT_HANN_WINDOW[i], 0)
			}

			cooley_turkey_fft(fft_input[:])
			useful_data := fft_input[0:len(fft_input)/2]
			frequency_bin_amplitudes: [FFT_WINDOW_SIZE / 2]f32
			for sample, i in useful_data {
				// !! TODO: Need to do temporal smoothing, otherwise the output will skip around eratically
				// and not be that useful, BUT, I'm skipping that for now.
				freq_hz := f32(i) * f32(SAMPLE_RATE) / f32(FFT_WINDOW_SIZE)
				if freq_hz < 20 || freq_hz > 20_000 do continue // skip sub-bass

				x := math.log10(freq_hz / 20.0) / math.log10(f32(1000.0)) // 0 <-> 1

				magnitude := max(cmplx.abs(sample), 1e-10) / (FFT_WINDOW_SIZE / 2)

				db := max(20 * math.log10(magnitude), -60)
				// y := map_range(-60.0, 20.0, 0.0, 1.0, f64(db))  // -90 dB at bottom, +20 dB at top

				// width_px  :f32 = 1.0 
				// height_px := f32(frequency_display_container.box.last_height) * f32(y)

				frequency_bin_amplitudes[i] = db
			}
			println(ma.engine_get_sample_rate(app.audio.engine))
			output_bins:[512]f32
			min_freq :: 20.0
			max_freq :: 20_000.0
			for i in 0..< FFT_N_SPECTRUM_BINS { 
				// Log-spaced frequency range for this output bin
				freq_low  := min_freq * math.pow(max_freq/min_freq, f32(i) / 511.0)
				freq_high := min_freq * math.pow(max_freq/min_freq, f32(i+1) / 511.0)	

				// Convert frequencies to FFT bin indices
				fft_low  := int(f64(freq_low)  * f64(FFT_WINDOW_SIZE) / SAMPLE_RATE)
				fft_high := int(f64(freq_high) * f64(FFT_WINDOW_SIZE) / SAMPLE_RATE)
				fft_high = max(fft_high, fft_low + 1)  // at least 1 bin
				
				// Average the FFT bins in this range
				sum: f32 = 0
				for fft_i in fft_low..<fft_high {
					sum += frequency_bin_amplitudes[fft_i]
				}
				db := sum / f32(fft_high - fft_low)
				current := (db + 60.0 )	 / 60 // -60dB -> 0, 0dB -> 1
				
				// Lerp bins from prev frame to current frame as to avoid an eratic frequency response. 
				// The response is erratic irl, but users are used to a nice smooth flowing curve.
				prev := eq_state.frequency_spectrum_bins[i]
				if current > prev { 
					eq_state.frequency_spectrum_bins[i] = math.lerp(prev, current, f32(0.30))
				} else {
					eq_state.frequency_spectrum_bins[i] = math.lerp(prev, current, f32(0.10))
				}
			}

			for i in 1..<511 {
				output_bins[i] = output_bins[i-1] * 0.25 + output_bins[i] * 0.5 + output_bins[i+1] * 0.25
			}
			// eq_state.frequency_spectrum_bins = output_bins

			// S ingle quad which pixel shader will draw the frequency response inside of.
			box_from_cache(
					{.Draw},
					{
						color = .Inverse_Primary,
						size = {
							{.Percent, 1},
							{.Percent, 1},
						},
						floating_anchor_box = frequency_display_container.box,
						floating_type = .Relative_Other,
						floating_offset = {0, 0}
					},
					metadata = Metadata_Audio_Spectrum{
						track_num = track_num
					},
			)

			// Draw filter response curve.
			for point, i in curve_total {
				// x := map_range(0.0, len(curve_total), 0.0, 1.0, f64(i))
				x := f64(i) / f64(len(curve_total) - 1)
				y := map_range(
					-EQ_MAX_GAIN, 
					EQ_MAX_GAIN, 
					1,
					0,
					point
				)
				// printfln("current freq response point is at: {}, {}", x, y)
				text_button(
					"a",
					{
						size = {{.Fixed, 2}, {.Fixed, 2}},
						color = .Primary_Container,
						floating_type = .Relative_Other,
						floating_anchor_box = frequency_display_container.box,
						floating_offset = {f32(x), f32(y)}
					}
				)
			}
		}

		level_meter := box_from_cache(
			{.Draw},
			{
				size = {{.Fixed, 30}, {.Percent, 1}},
				z_index = 30,
			},
			"",
			id("{}-level-meter", eq_id),
		)
	}
	
}

sampler :: proc(track_num: int, id_string: string) {
	track   := &app.audio.tracks[track_num]
	sampler := &track.sampler
	sampler.prev_zoom_amount = sampler.zoom_amount
	sampler_container := child_container(
		{
			size = {{.Fixed, 850}, {.Fixed, 400}},
			color = .Surface_Container_High
		},
		{
			direction = .Horizontal
		},
		id_string,
		{.Draw},
	)

	left_controls: {
		control_container := child_container(
			{
				// size = {{.Percent, 0.1}, {.Percent, 1}},
				size = Size_Grow,
				// color = .Primary,
			},
			{
				direction = .Vertical,
				alignment_vertical = .Space_Around,
				alignment_horizontal = .Center
			},
			id("sampler-{}-left-controls", track_num),
			{.Draw},
		)
		text_button(
			"Control 1",
			{
				size = Size_Fit_Text_And_Grow,
				color = .Secondary_Container
			},
			id("sampler-{}-controls-button-1", track_num),
		)
		text_button(
			"Control 2",
			{
				size = Size_Fit_Text_And_Grow,
				color = .Secondary_Container
			},
			id("sampler-{}-controls-button-2", track_num),
		)
		text_button(
			"Control 3",
			{
				size = Size_Fit_Text_And_Grow,
				color = .Secondary_Container
			},
			id("sampler-{}-controls-button-3", track_num),
		)
		text_button(
			"Control 4",
			{
				size = Size_Fit_Text_And_Grow,
				color = .Secondary_Container
			},
			id("sampler-{}-controls-button-4", track_num),
		)
	}

	main_content: {
		// Inside here we'll render the waveform and the slice markers.
		waveform_parent := child_container(
			{
				size = {{.Percent, 0.90}, {.Percent, 0.85}},
				color = .Secondary,
			},
			{
			},
			id("{}-waveform-display", sampler_container.box.id),
			{.Draw, .Clickable, .Scrollable},
			Metadata_Sampler{
				track_num
			},
		)
		if waveform_parent.double_clicked {
			slice_x_pos := 
				f32(app.mouse.pos.x - waveform_parent.box.top_left.x) / 
				f32(waveform_parent.box.prev_width)
			new_slice := Sampler_Slice {
				how_far = slice_x_pos,
				which = sampler.n_slices
			}
			// We hard limit the amount of slices so eventually we'll need to check for that.
			sampler.n_slices += 1
			sampler.slices[sampler.n_slices - 1] = new_slice
		}

		// ============= Handle waveform zooming =============================
		decrease_zoom :: proc(sampler: ^Sampler_State) {
			zoom_factor := 1 / (1 - sampler.zoom_amount)
			zoom_factor /= 1.2
			sampler.zoom_amount = clamp(1 - (1 / zoom_factor), 0, 0.99999)
		}
		increase_zoom :: proc(sampler: ^Sampler_State) {
			zoom_factor := 1 / (1 - sampler.zoom_amount)
			zoom_factor *= 1.2
			// sampler.zoom_amount = clamp(sampler.zoom_amount + zoom_factor, 0, 0.99999)
			sampler.zoom_amount = clamp(1 - (1 / zoom_factor), 0, 0.99999)
		}

		waveform_box := waveform_parent.box
		if waveform_parent.scrolled {
			// ==== HELP FROM CLAUDE WITH PROPPER ZOOMING ======
			// Calculate where the mouse is in the current visible waveform (0-1 range)
			mouse_screen_normalized := f32(map_range(
				f64(waveform_box.top_left.x),
				f64(waveform_box.bottom_right.x),
				0.0,
				1.0,
				f64(app.mouse.pos.x),
			))

			// Get current zoom values
			old_zoom_amount := sampler.zoom_amount
			old_visible_width := 1.0 - old_zoom_amount

			// Calculate the waveform position under the mouse BEFORE zooming
			// This is the key: we need to know what part of the actual waveform is under the cursor
			waveform_position_under_mouse := sampler.zoom_point + f32(mouse_screen_normalized) * old_visible_width

			if waveform_parent.scrolled_up {
				increase_zoom(sampler)
			} else if waveform_parent.scrolled_down {
				decrease_zoom(sampler)
			}

			// Calculate new visible width after zoom
			new_visible_width := 1.0 - sampler.zoom_amount

			// Calculate new zoom_point to keep the same waveform position under the mouse
			// We want: waveform_position_under_mouse = new_zoom_point + mouse_screen_normalized * new_visible_width
			// Solving for new_zoom_point:
			sampler.zoom_point = waveform_position_under_mouse - f32(mouse_screen_normalized) * new_visible_width

			// Clamp zoom_point to valid range
			sampler.zoom_point = clamp(sampler.zoom_point, 0, 1 - new_visible_width)

			printfln("changed zoom - point: {}  amount: {}", sampler.zoom_point, sampler.zoom_amount)
		}

		text(
			"Here is where the waveform goes",
			{
				size = Size_Fit_Text,
				color = .Secondary,
			},
			id("sampler-{}-waveform-placeholder", track_num),
		)

		slice_config := Box_Config { 
			line_thickness = 2,
			color = .Warning, 
		}

		// Render slices:
		for i in 0..< sampler.n_slices {
			config := slice_config
			slice_x_pos := sampler.slices[i].how_far * f32(waveform_parent.box.prev_width) + f32(waveform_parent.box.top_left.x)
			config.line_start = {slice_x_pos, f32(waveform_parent.box.top_left.y)}
			config.line_end = {slice_x_pos, f32(waveform_parent.box.bottom_right.y)}
			line(
				config,
				id("sampler-{}-slice-{}", track_num, i),
			)
			// Draw drag handle for slice
			drag_handle := button(
				{
					floating_type = .Absolute_Pixel,
					floating_offset = {config.line_start.x - 10, config.line_start.y},
					size = {{.Fixed, 20}, {.Fixed, 20}},
					color = .Error_Container,
					z_index = 50,
				},
				id("sampler-{}-slice-{}-handle", track_num, i),
			)
			if drag_handle.box == ui_state.dragged_box {
				drag_delta := get_drag_delta()
				change_as_prct := f32(drag_delta.x) / f32(waveform_parent.box.prev_width)
				sampler.slices[i].how_far += change_as_prct * 1.001
			}
		}

		bottom_controls: {
			child_container(
				{
					color = .Secondary,
					size = Size_Grow,
				},
				{
					alignment_vertical = .Center,
					alignment_horizontal = .Space_Between,
				},
				id("sampler-{}-bottom-controls", track_num),
			)
		}
	}
}

context_menu :: proc() {
	track_steps_context_menu :: proc(box: ^Box) {
		metadata := box.metadata.(Metadata_Track_Step)
		track_num := metadata.track
		track := &app.audio.tracks[track_num]

		top_level_btn_config := Box_Config {
			size = Size_Fit_Text_And_Grow,
			text_justify  = {.Start, .Center},
			padding = padding(10),
			border = 1,
		}

		top_level_btn_config.color = .Primary_Container
		add_button := text_button(
			"Add steps",
			top_level_btn_config,
		)

		top_level_btn_config.color = .Warning_Container
		remove_button := text_button(
			"Remove steps",
			top_level_btn_config,
		)

		top_level_btn_config.color = .Primary_Container
		loop_button := text_button(
			"Loop back here",
			top_level_btn_config,
		)

		if loop_button.clicked {
			track.loop_at = metadata.step
		}

		disarm_labl := track.armed ? "Disarm" : "Arm"
		top_level_btn_config.color = .Surface
		disarm_button := text_button(
			id("{} track", disarm_labl),
			top_level_btn_config,
			"conext-menu-3",
		)

		label := track.eq.show ? "Hide EQ" : "Show EQ"
		activate_eq_button := text_button(
			label,
			top_level_btn_config,
			id("conext-menu-track-{}-EQ", track_num),
		)

		if activate_eq_button.clicked {
			track.eq.show = !track.eq.show
		}

		label = track.sampler.show ? "Hide Sampler" : "Show Sampler"
		activate_sampler_button := text_button(
			label,
			top_level_btn_config,
			id("conext-menu-track-{}-sampler", track_num),
		)

		if activate_sampler_button.clicked {
			track.sampler.show = !track.sampler.show
		}

		top_level_btn_config.color = .Error_Container
		delete_track_button := text_button(
			"Delete Track",
			top_level_btn_config,
			"conext-menu-4",
		)

		add_submenu_id := "@add-step-hover-container"
		add_submenu_hovered := false
		if submenu_box, ok := ui_state.box_cache[add_submenu_id]; ok {
			add_submenu_hovered = mouse_inside_box(submenu_box, app.mouse.pos)
		}
		if add_button.hovering || add_submenu_hovered {
			hover_container := child_container(
				{
					floating_type = .Absolute_Pixel,
					floating_offset = {f32(add_button.box.bottom_right.x), f32(add_button.box.top_left.y)},
					size = Size_Fit_Children,
					z_index = 20,
				},
				{direction = .Vertical, gap_vertical = 2},
				add_submenu_id,
				{.Clickable},
			)
			btn_config := Box_Config {
				size    = Size_Fit_Text_And_Grow,
				text_justify 	 = {.Start, .Center},
				color 			 = .Primary_Container,
				padding          = {10, 10, 10, 10},
				border = 1
			}
			if text_button("All steps", btn_config, "context-add-all").clicked {
				track_turn_on_steps(track_num, 0, 1)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 2nd", btn_config, "context-add-2nd").clicked {
				track_turn_on_steps(track_num, 0, 2)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 3rd", btn_config, "context-add-3rd").clicked {
				track_turn_on_steps(track_num, 0, 3)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 4th", btn_config, "context-add-4th").clicked {
				track_turn_on_steps(track_num, 0, 4)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 6th", btn_config, "context-add-6th").clicked {
				track_turn_on_steps(track_num, 0, 6)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 8th", btn_config, "context-add-8th").clicked {
				track_turn_on_steps(track_num, 0, 8)
				ui_state.clicked_on_context_menu = true
			}
		}

		id := "@remove-step-hover-container"
		remove_submenu_hovered := false
		if submenu_box, ok := ui_state.box_cache[id]; ok {
			remove_submenu_hovered = mouse_inside_box(submenu_box, app.mouse.pos)
		}
		if remove_button.hovering || remove_submenu_hovered {
			hover_container := child_container(
				{
					floating_type = .Absolute_Pixel,
					floating_offset = {
						f32(remove_button.box.bottom_right.x),
						f32(remove_button.box.top_left.y),
					},
					size = Size_Fit_Children,
					z_index = 20,
				},
				{direction = .Vertical, gap_vertical = 2},
				id,
				{.Clickable},
			)
			btn_config := Box_Config {
				size    		= Size_Fit_Text_And_Grow,
				color 			 = .Warning_Container,
				padding          = {10, 10, 10, 10},
			}
			if text_button("All steps", btn_config, "context-remove-all").clicked {
				track_turn_off_steps(track_num, 0, 1)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 2nd", btn_config, "context-remove-2nd").clicked {
				track_turn_off_steps(track_num, 0, 2)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 3rd", btn_config, "context-remove-3rd").clicked {
				track_turn_off_steps(track_num, 0, 3)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 4th", btn_config, "context-remove-4th").clicked {
				track_turn_off_steps(track_num, 0, 4)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 6th", btn_config, "context-remove-6th").clicked {
				track_turn_off_steps(track_num, 0, 6)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 8th", btn_config, "context-remove-8th").clicked {
				track_turn_off_steps(track_num, 0, 8)
				ui_state.clicked_on_context_menu = true
			}
		}

		if disarm_button.clicked { 
			app.audio.tracks[track_num].armed = !app.audio.tracks[track_num].armed
		}
		if delete_track_button.clicked {
			track_delete(box.metadata.(Metadata_Track_Step).track)
			printfln("deletring track that contains {}", ui_state.right_clicked_on.id)
		}
	}

	file_browser_context_menu :: proc(box: ^Box) {
		config := Box_Config {
			size = Size_Fit_Text_And_Grow,
			text_justify = {.Start, .Center},
			padding = padding(5),
		}
		config.color = .Secondary_Container
		edit := text_button(
			"Edit name",
			config,
			"ctx-menu-file-edit-name",
		)

		config.color = .Error_Container
		delete := text_button(
			"Delete",
			config,
			"ctx-menu-file-delete",
		)
	}

	eq_handle_context_menu :: proc(which:int, track_num: int, band: ^EQ_Band_State) { 
		child_container(
			{
				size = Size_Fit_Children
			},
			{
				direction = .Vertical
			},
		)
		btn_config := Box_Config {
			size = Size_Fit_Text_And_Grow,
			color = .Primary_Container,
			padding = padding(5),
		}
		shape_btn := text_button(
			"Shape",
			btn_config
		)
		btn_config.margin = {top = 4}
		btn_config.color = .Error_Container
		text_button(
			"Delete",
			btn_config
		)

		id := "eq-handle-context-submenu"
		hovering_submenu := false
		if id in ui_state.box_cache {
			hovering_submenu = mouse_inside_box(ui_state.box_cache[id], app.mouse.pos)
		}
		if shape_btn.hovering || hovering_submenu {
			child_container(
				{
					size = Size_Fit_Children,
					floating_type = .Absolute_Pixel,
					floating_offset = ({
						f32(shape_btn.box.bottom_right.x),
						f32(shape_btn.box.top_left.y),
					})
				},
				{
					direction = .Vertical
				},
				id = id
			)
			altered := false
			if text_button("Bell", btn_config).clicked {
				band.type = .Bell
				altered = true
			}

			if text_button("High Cut", btn_config).clicked {
				band.type = .High_Cut
				altered = true
			}

			if text_button("Low Cut", btn_config).clicked {
				band.type = .Low_Cut
				altered = true
			}

			if text_button("High Shelf", btn_config).clicked {
				band.type = .High_Shelf
				altered = true
			}

			if text_button("Low Shelf", btn_config).clicked {
				band.type = .Low_Shelf
				altered = true
			}

			if text_button("Notch", btn_config).clicked {
				band.type = .Notch
				altered = true
			}

			if text_button("Band Pass", btn_config).clicked {
				band.type = .Band_Pass
				altered = true
			}
			if altered {
				// Might need some more logic to set sane defaults for certain band types,
				// this is okay for now though.
				band.q = 0.7
				band.gain_db = 0
				band.coefficients.a0 = 1
				band.coefficients.a1 = 0
				band.coefficients.a2 = 0
				band.coefficients.b0 = 1
				band.coefficients.b1 = 0
				band.coefficients.b2 = 0
				eq_reinit_band(band^)
			}
		}
	}

	if ui_state.right_clicked_on.disabled { 
		println("right clicked on a disabled box")
		return
	}

	context_menu_container := child_container(
		{
			size 		= Size_Fit_Children,
			z_index 			= 100,
			floating_type		= .Absolute_Pixel,
			floating_offset 	= {f32(ui_state.context_menu.pos.x), f32(ui_state.context_menu.pos.y)},
			color 				= .Secondary_Container,
			corner_radius 		= 3, 	
			padding 			= padding(10),
			edge_softness 		= 2,
		},
		{
			direction 			 = .Vertical,
			alignment_horizontal = .Center,
			alignment_vertical   = .Center,
		},
		box_flags = {.Draw},
	)


	switch metadata in ui_state.right_clicked_on.metadata {
	case Metadata_Track_Step:
		track_steps_context_menu(ui_state.right_clicked_on)
	case Metadata_Browser_Item:
		file_browser_context_menu(ui_state.right_clicked_on)
	case Metadata_Sampler, Metadata_Audio_Spectrum, Metadata_Track:
		text(
			"Context menu not implemented for this box type @ alskdaajfalskdjfladf",
			{size = Size_Fit_Text},
		)
	case Metadata_EQ_Handle:
		eq_handle_context_menu(metadata.which, metadata.track_num, metadata.band)
	}
}


// ============== Helper functions for our higher level widgets ===================

/*
Takes in any box and activates that box and all of it's siblings.
*/
@(private="file")
box_siblings_toggle_select :: proc(box: Box) {
	for sibling in box.parent.children {
		sibling.selected = !sibling.selected
	}
}

@(private="file")
box_siblings_set_select :: proc(box: Box, activate: bool) {
	for sibling in box.parent.children {
		sibling.selected = activate
	}
}

@(private="file")
set_nth_child_select :: proc(track_num, nth: int, selected: bool) {
	// Is inefficient to traverse all boxes in the UI but should be okay for now.
	root := ui_state.root	
	assert(root != nil)
	boxes := box_tree_to_list(root, context.temp_allocator)
	for box in boxes {
		switch metadata in box.metadata {
		case Metadata_Track_Step:
			if metadata.track != track_num do continue
			if metadata.step % nth == 0 do box.selected = selected
		case Metadata_Track, Metadata_Sampler, Metadata_Browser_Item, Metadata_EQ_Handle, Metadata_Audio_Spectrum:
			panic("set_nth_child() should only be called on box with Metadata_Track_Step")
		}
	}
}
// ===============================================================================
