/* 
These are hotpaths that call box_from_cache in a preconfigured way as to achieve the 
effect of what a user would normally call a 'widget' in a traditional UI framework.

The idea is that they're more specific to this application, where as the hotpaths in builder_basics.odin
should be relatively ubiqitous amongst most UIs. However I do have application specific logic in them,
so they'll need some re-thinking when I ship the UI stuff as a lib.
*/

package app
import "core:math"
import "core:flags"
import "vendor:sdl2"
import "core:time"
import "core:math/cmplx"
import "core:mem"
import "core:sync"
import "core:path/filepath"
import str "core:strings"
import ma"vendor:miniaudio"
import sdl "vendor:sdl2"

topbar :: proc() {
	topbar_signals := child_container(
		{
			size    = {{.Fixed, f32(app.wx)}, {.Fixed, TOPBAR_HEIGHT}},
			color = .Secondary,
		},
		{
			direction = .Horizontal,
			alignment_horizontal = .Space_Between,
			alignment_vertical = .Center,
		},
		"topbar",
		box_flags = {.Draggable, .Clickable}
	)

	// Drag window when clicking on the topbar dead space.
	// Uses native DWM-composited move for smooth, flicker-free dragging.
	if ui_state.dragged_box != nil && ui_state.dragged_box.(^Box) == topbar_signals.box {
		dx := app.mouse.pos.x - app.mouse.drag_start.x
		dy := app.mouse.pos.y - app.mouse.drag_start.y
		if dx != 0 || dy != 0 {
			when ODIN_OS == .Windows {
				begin_native_window_drag()
			} else {
				win_x, win_y: i32
				sdl.GetWindowPosition(app.window, &win_x, &win_y)
				sdl.SetWindowPosition(app.window, win_x + i32(dx), win_y + i32(dy))
			}
		}
	}

	btn_config := Box_Config {
		size = {{.Fit_Text_And_Grow, 1}, {.Fit_Text_And_Grow, 1}},
		color = .Tertiary,
		padding = {top = 0, bottom = 0, left = 2, right = 2},
		border = border_x(1),
		border_color = .Primary,
		text_justify = {.Center, .Center}
	}

	left_container: {
		btn_config := btn_config
		btn_config.color = .Primary_Container
		btn_config.size = {{.Fixed, 40}, {.Grow, 20}}

		child_container(
			{size = {{.Fit_Children, 1}, {.Fit_Children_And_Grow, 1}}},
			{},
			id = "top-bar-left-container",
		)
		if icon_button(Icon_Undo, "undo", btn_config).clicked {
			undo()
		}
		if icon_button(Icon_Redo,"redo", btn_config).clicked {
			redo()
		}
	}

	left_middle_container: {
		btn_config := btn_config
		btn_config.color = .Primary_Container
		btn_config.size = {{.Fixed, 40}, {.Grow, 20}}

		child_container(
			{size = {{.Fit_Children, 1}, {.Fit_Children_And_Grow, 1}}},
			{},
			"top-bar-left-middle-container",
		)
		if icon_button(Icon_Wave, "render wav", btn_config).clicked {
			audio_export_to_wav()
		}
		if icon_button(Icon_Save,"save project", btn_config).clicked {
			audio_state_write_to_disk("saved.bin")
		}
		if icon_button(Icon_File, "load project", btn_config).clicked {
			audio_state_load_from_disk("saved.bin")
		}
	}

	middle_container: {
		btn_config := btn_config
		btn_config.color = .Primary_Container
		btn_config.size = {{.Fixed, 40}, {.Grow, 20}}
		child_container(
			{size = {{.Fit_Children, 1}, {.Fit_Children_And_Grow, 1}}},
			{alignment_horizontal = .Space_Between},
			"top-bar-middle-container",
		)


		text(
			"BPM:", 
			{size={{.Fit_Text, 1}, {.Fit_Text_And_Grow, 1}}, margin={right=5}},
		)
		bpm_input := edit_number_box(
			{
				size = {{.Fit_Text_And_Grow, 1}, {.Fit_Text_And_Grow, 1}},
				color = {},
				text_color = .On_Primary,
				min_size = {30, 0}
			},
			&app.audio.bpm,
			10,
			500,
		)

		// if bpm_input.changed {
		// 	app.audio.bpm = u16(bpm_input.box.data.(int))
		// }

		if icon_button(Icon_Restart, "Restart", btn_config).clicked { 
			audio_transport_reset()
		} 

		if app.audio.playing { 
			if icon_button(Icon_Pause, "Pause", btn_config).clicked { 
				audio_transport_pause()
			}
		} else { 
			if icon_button(Icon_Play, "Play", btn_config).clicked { 
				audio_transport_play()
			}
		}
	}

	right_container: {
		btn_config := btn_config
		btn_config.color = .Primary_Container
		btn_config.size = {{.Fixed, 40}, {.Grow, 20}}
		child_container(
			{size = {{.Fit_Children, 1}, {.Fit_Children_And_Grow, 1}}},
			{},
			"top-bar-right-container",
		)
		// if text_button("Default layout", btn_config, "top-bar-default").clicked {
		// 	ui_state.tab_num = 0
		// 	ui_state.changed_ui_screen = true
		// }
		// if text_button("Test layout", btn_config, "top-bar-test").clicked {
		// 	ui_state.tab_num = 1
		// 	ui_state.changed_ui_screen = true
		// }

		sidebar_label := ui_state.sidebar_shown ? "Close sidebar" : "Open sidebar"
		if ui_state.sidebar_shown {
			if icon_button(Icon_Closed_Folder, sidebar_label, btn_config).clicked {
				ui_state.sidebar_shown = false
				animation_start("browser-offset-x", 1.0, 1)
			}
		} else { 
			if icon_button(Icon_Open_Folder, sidebar_label, btn_config).clicked {
				ui_state.sidebar_shown = true
				animation_start("browser-offset-x", 2.0, 0.2)
			}
		}

		btn_config.color = .Yellow_500
		if text_button(
			"-",
			btn_config,
		).clicked {
			sdl.MinimizeWindow(app.window)
		}
		btn_config.color = .Green_500
		if text_button(
			"o",
			btn_config
		).clicked { 
			if app.maximized {
				sdl.RestoreWindow(app.window)
			} else { 
				sdl.MaximizeWindow(app.window)
			}
			app.maximized = !app.maximized
		}
		btn_config.color = .Red_500
		if text_button(
			"x",
			btn_config
		).clicked { 
			app_shutdown()
		}
	}
}

audio_track :: proc(track_num: int, track_width: f32, step_containers: ^[]^Box, extra_flags := Box_Flags{}) -> Track_Signals {
	track := &app.audio.tracks[track_num]
	n_steps := 128 // This will ultimately be a dynamic size for each track.

	track_container := child_container(
		{size = {{.Fixed, track_width}, {.Percent, 1}}},
		{direction = .Vertical},
		metadata = Metadata_Track {
			track_num = track_num
		},
		id = tprintf("track-{}-container", track_num),
		box_flags = {.Glow, .Drop_Shadow}
	)
	track_container.box.disabled = !track.armed
	track_container.box.metadata = Metadata_Track{
		track_num = track_num
	}
	if track_num == app.selected_track { 
		track_container.box.config.border       = border(2)
		track_container.box.config.border_color = .Red_500
	}
	track_label: {
		child_container(
			{
				size = {{.Fixed, track_width}, {.Fit_Children, 1}},
				padding = {left = 2, right = 2}
			},
			{
				direction = .Horizontal,
				alignment_horizontal = .Center,
				alignment_vertical = .Center
			},
		)
		input := edit_text_box(
			{
				size = {{.Grow, 1}, {.Fixed, 30}},
				color = .Primary,
				text_color = .Slate_950
			},
			.Generic_One_Line,
			&track.name
		)
		if input.box.fresh {
			track.name = aprintf("Track {}", track_num)
		}
	}

	step_signals: Track_Steps_Signals
	track_dropped_on: bool

	steps: {
		step_height_ratio := f32(ui_state.show_mixer ? 1.0 / (54.0 * 0.7) : 1.0 / (80.0 * 0.7))
		// steps_container := child_container(
		vlist := virtual_list(
			{
				size = {{.Fixed, track_width}, {.Grow, 1}},
				color = .Tertiary,
				overflow_y = .Scroll,
				margin = {top = 5}
			},
			{direction = .Vertical, gap_vertical = 0},
			N_TRACK_STEPS,
			step_height_ratio,
			box_flags = {.Drag_Drop_Source, .Scrollable},
			id = tprintf("track-{}-steps-container", track_num)
		)
		step_containers[track_num] = vlist.container_signals.box
		// step_containers[track_num] = steps_container.box

		

		loop_back_step := track.loop_at
		just_pressed  := app.mouse.left_pressed && !app.mouse_last_frame.left_pressed
		drag_released := app.mouse.drag_done && !app.mouse_last_frame.drag_done
		for jj in 0 ..< len(app.audio.tracks) {
			if jj == track_num do continue
			primary := &app.audio.tracks[jj]
			if primary.step_drag_mode == .Move {
				if track.step_sel_start != -1 {
					delta     := primary.step_drag_current - primary.step_drag_origin
					sel_len   := track.step_drag_sel_origin_end - track.step_drag_sel_origin_start + 1
					new_start := clamp(track.step_drag_sel_origin_start + delta, 0, N_TRACK_STEPS - sel_len)
					track.step_sel_start = new_start
					track.step_sel_end   = new_start + sel_len - 1
				}
				break
			}
		}

		substep_config: Box_Config = {
			size    		 = {{.Percent, 0.25}, {.Percent, 1}},
			text_color 		 = .Slate_900,
			border 			 = border(1),
		}
		substep_extra_flags := Box_Flags{.Draw_Border, .Track_Step, .Drag_Drop_Sink}

		for i in vlist.first_visible ..= vlist.last_visible {
			step_row_container := child_container(
				{size = {{.Fixed, track_width}, {.Fixed, f32(vlist.item_size)}}},
				{direction = .Horizontal},
				box_flags  = {.Drag_Drop_Sink},
			)
			if loop_back_step != -1 && i > loop_back_step {
				step_row_container.box.disabled = true
			}

			if i == loop_back_step {
				loop_back_indicator := text_button(
					"remove loop-back",
					{
						size = Size_Fit_Text_And_Grow
					}
				)
				if loop_back_indicator.double_clicked {
					track.loop_at = -1
				} 
				break
			}

			if i >= track.step_sel_start && i <= track.step_sel_end { 
				substep_config.color = .Secondary
			} else { 
				substep_config.color = .Primary
			}

			display_step := i
			step_is_vacated := false
			if track.step_drag_mode == .Move {
				orig_s  := track.step_drag_sel_origin_start
				orig_e  := track.step_drag_sel_origin_end
				sel_len := orig_e - orig_s + 1
				delta   := track.step_drag_current - track.step_drag_origin
				new_s   := clamp(orig_s + delta, 0, N_TRACK_STEPS - sel_len)
				new_e   := new_s + sel_len - 1
				if i >= new_s && i <= new_e {
					display_step = orig_s + (i - new_s)
				}
				if !app.keys_held[sdl2.Scancode.LCTRL] && i >= orig_s && i <= orig_e && !(i >= new_s && i <= new_e) {
					step_is_vacated = true
				}
			} else if track.step_sel_start != -1 {
				for j in 0 ..< len(app.audio.tracks) {
					if j == track_num do continue
					primary := &app.audio.tracks[j]
					if primary.step_drag_mode == .Move {
						orig_s  := track.step_drag_sel_origin_start
						orig_e  := track.step_drag_sel_origin_end
						sel_len := orig_e - orig_s + 1
						delta   := primary.step_drag_current - primary.step_drag_origin
						new_s   := clamp(orig_s + delta, 0, N_TRACK_STEPS - sel_len)
						new_e   := new_s + sel_len - 1
						if i >= new_s && i <= new_e {
							display_step = orig_s + (i - new_s)
						}
						if !app.keys_held[sdl2.Scancode.LCTRL] && i >= orig_s && i <= orig_e && !(i >= new_s && i <= new_e) {
							step_is_vacated = true
						}
						break
					}
				}
			}

			pitch_box := edit_pitch_box(
				substep_config,
				metadata = Metadata_Track_Step {
					track = track_num,
					step  = display_step,
					type  = .Pitch,
				},
				extra_flags = substep_extra_flags,
			)

			volume_box := edit_number_box(
				substep_config,
				&track.volumes[display_step],
				0,
				100,
				metadata = Metadata_Track_Step {
					track = track_num,
					step  = display_step,
					type  = .Volume,
				},
				extra_flags = substep_extra_flags,
			)

			chop_box := edit_number_box(
				substep_config,
				&track.chops[display_step],
				0,
				int(track.sampler.n_slices),
				metadata = Metadata_Track_Step {
					track = track_num,
					step  = display_step,
					type  = .Chop,
				},
				extra_flags = substep_extra_flags,
			)

			send2_box := edit_number_box(
				substep_config,
				&track.send2[display_step],
				0,
				100,
				metadata = Metadata_Track_Step {
					track = track_num,
					step  = display_step,
					type  = .Send2,
				},
				extra_flags = substep_extra_flags,
			)

			if step_is_vacated {
				pitch_box.box.flags  -= {.Draw_Text}
				volume_box.box.flags -= {.Draw_Text}
				chop_box.box.flags   -= {.Draw_Text}
				send2_box.box.flags  -= {.Draw_Text}
			}

			step_is_pressed := pitch_box.pressed || volume_box.pressed || chop_box.pressed || send2_box.pressed

			if just_pressed && step_is_pressed && !app.keys_held[sdl2.Scancode.LSHIFT] {
				if i >= track.step_sel_start && i <= track.step_sel_end {
					track.step_drag_mode             = .Move
					track.step_drag_origin           = i
					track.step_drag_current          = i
					track.step_drag_sel_origin_start = track.step_sel_start
					track.step_drag_sel_origin_end   = track.step_sel_end
					sel_len := track.step_drag_sel_origin_end - track.step_drag_sel_origin_start + 1
					for j in 0 ..< sel_len {
						src := track.step_drag_sel_origin_start + j
						track.step_drag_cache_pitches[j]  = track.pitches[src]
						track.step_drag_cache_volumes[j]  = track.volumes[src]
						track.step_drag_cache_chops[j]    = track.chops[src]
						track.step_drag_cache_send2[j]    = track.send2[src]
						track.step_drag_cache_selected[j] = track.selected_steps[src]
					}
					for k in 0 ..< len(app.audio.tracks) {
						if k == track_num do continue
						other := &app.audio.tracks[k]
						if other.step_sel_start != -1 {
							other.step_drag_sel_origin_start = other.step_sel_start
							other.step_drag_sel_origin_end   = other.step_sel_end
							other_sel_len := other.step_drag_sel_origin_end - other.step_drag_sel_origin_start + 1
							for k in 0..<other_sel_len {
								src := other.step_drag_sel_origin_start + k
								other.step_drag_cache_pitches[k]  = other.pitches[src]
								other.step_drag_cache_volumes[k]  = other.volumes[src]
								other.step_drag_cache_chops[k]    = other.chops[src]
								other.step_drag_cache_send2[k]    = other.send2[src]
								other.step_drag_cache_selected[k] = other.selected_steps[src]
							}
						}
					}
				} else {
					track.step_drag_mode   = .Select
					track.step_drag_origin = i
					track.step_sel_start   = i
					track.step_sel_end     = i
					if !app.keys_held[sdl2.Scancode.LCTRL] {
						for jj in 0 ..< len(app.audio.tracks) {
							if jj == track_num do continue
							app.audio.tracks[jj].step_sel_start = -1
							app.audio.tracks[jj].step_sel_end   = -1
						}
					}
				}
			}

			if track.step_drag_mode == .Move && step_is_pressed {
				track.step_drag_current = i
				delta     := track.step_drag_current - track.step_drag_origin
				sel_len   := track.step_drag_sel_origin_end - track.step_drag_sel_origin_start + 1
				new_start := clamp(track.step_drag_sel_origin_start + delta, 0, N_TRACK_STEPS - sel_len)
				track.step_sel_start = new_start
				track.step_sel_end   = new_start + sel_len - 1
			}

			if track.step_drag_mode == .Select && step_is_pressed {
				track.step_sel_start = min(track.step_drag_origin, i)
				track.step_sel_end   = max(track.step_drag_origin, i)
			}

			if (pitch_box.clicked ||
			   volume_box.clicked ||
			   chop_box.clicked  ||
			   send2_box.clicked) &&
			   track.step_drag_mode == .None
			{
				if app.keys_held[sdl2.Scancode.LSHIFT] { 
					if i > track.step_sel_end  { 
						track.step_sel_end = i;  
						if track.step_sel_start == -1 do track.step_sel_start = 0
					}
					else if i < track.step_sel_start { 
						track.step_sel_end = track.step_sel_start
						track.step_sel_start = i
					// Otherwise we've clicked inside the range
					} else { 
						track.step_sel_end = i
					}
				} else { 
					track.step_sel_start = i
					track.step_sel_end   = i
					if !app.keys_held[sdl2.Scancode.LCTRL] {
						for jj in 0 ..< len(app.audio.tracks) {
							if jj == track_num do continue
							app.audio.tracks[jj].step_sel_start = -1
							app.audio.tracks[jj].step_sel_end   = -1
						}
					}
				}
			}

			if pitch_box.double_clicked  ||
			   volume_box.double_clicked ||
			   chop_box.double_clicked  ||
			   send2_box.double_clicked 
			{
				undo_push(track)
				undo_commit()
				track_toggle_step(track_num, i)
			}

			if pitch_box.dropped_on  ||
			   volume_box.dropped_on ||
			   chop_box.dropped_on  ||
			   send2_box.dropped_on  ||
			   step_row_container.dropped_on 
			{
				track_dropped_on = true
			}


			curr_step_global := audio_get_current_step()
			curr_step := track.loop_at == -1 ? curr_step_global % int(track.n_steps) : curr_step_global % track.loop_at
			// If this is the current step, indicate so.
			if curr_step == i {
				pitch_box.box.config.color  = .Primary_Container
				volume_box.box.config.color = .Primary_Container
				chop_box.box.config.color  = .Primary_Container
				send2_box.box.config.color  = .Primary_Container
			}
		}
		if drag_released {
			undo_push(track)
			switch track.step_drag_mode {
			case .Move:
				track.step_drag_mode = .None
				delta := track.step_drag_current - track.step_drag_origin
				if delta == 0 {
					track.step_sel_start = track.step_drag_origin
					track.step_sel_end   = track.step_drag_origin
				} else {
					sel_len   := track.step_drag_sel_origin_end - track.step_drag_sel_origin_start + 1
					new_start := clamp(track.step_drag_sel_origin_start + delta, 0, N_TRACK_STEPS - sel_len)
					new_end   := new_start + sel_len - 1
					is_copy   := app.keys_held[sdl2.Scancode.LCTRL]
					if !is_copy {
						for j in 0..<sel_len {
							src := track.step_drag_sel_origin_start + j
							if src < new_start || src > new_end {
								track.pitches[src]        = 0
								track.volumes[src]        = 0
								track.chops[src]          = 0
								track.send2[src]          = 0
								track.selected_steps[src] = false
							}
						}
					}
					for j in 0..<sel_len {
						dst := new_start + j
						track.pitches[dst]        = track.step_drag_cache_pitches[j]
						track.volumes[dst]        = track.step_drag_cache_volumes[j]
						track.chops[dst]          = track.step_drag_cache_chops[j]
						track.send2[dst]          = track.step_drag_cache_send2[j]
						track.selected_steps[dst] = track.step_drag_cache_selected[j]
					}
					track.step_sel_start = new_start
					track.step_sel_end   = new_end
					for jj in 0 ..< len(app.audio.tracks) {
						if jj == track_num do continue
						other := &app.audio.tracks[jj]
						if other.step_sel_start == -1 do continue
						other_sel_len   := other.step_drag_sel_origin_end - other.step_drag_sel_origin_start + 1
						other_new_start := clamp(other.step_drag_sel_origin_start + delta, 0, N_TRACK_STEPS - other_sel_len)
						other_new_end   := other_new_start + other_sel_len - 1
						if !is_copy {
							for k in 0..<other_sel_len {
								src := other.step_drag_sel_origin_start + k
								if src < other_new_start || src > other_new_end {
									other.pitches[src]        = 0
									other.volumes[src]        = 0
									other.chops[src]          = 0
									other.send2[src]          = 0
									other.selected_steps[src] = false
								}
							}
						}
						for k in 0..<other_sel_len {
							dst := other_new_start + k
							other.pitches[dst]        = other.step_drag_cache_pitches[k]
							other.volumes[dst]        = other.step_drag_cache_volumes[k]
							other.chops[dst]          = other.step_drag_cache_chops[k]
							other.send2[dst]          = other.step_drag_cache_send2[k]
							other.selected_steps[dst] = other.step_drag_cache_selected[k]
						}
						other.step_sel_start = other_new_start
						other.step_sel_end   = other_new_end
					}
				}
			case .Select:
				track.step_drag_mode = .None
			case .None:
			}
		}
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
				size = {{.Fit_Text_And_Grow, 1}, {.Fixed, 20}},
				color = .Primary_Container,
				text_justify = {.Start, .Center},
				overflow_x = .Hidden
			},
			id("{}{}-file-info", label, track_num),
			{.Drag_Drop_Source, .Draw, .Draw_Background, .Frosted},
			// {.Draw}
		)
	}

	if ui_state.show_track_waveforms {
		waveform_box := box_from_cache(
			{.Clickable, .Draw_Text, .Drag_Drop_Sink},
			{
				size = {{.Percent, 1}, {.Fixed, 60}},
				color = .Red_500
			},
			metadata = Metadata_Waveform{
				track_num = track_num
			},
			label = track.sounds[0] == nil ? "No sound" : ""
		)
		signals := box_signals(waveform_box)
		if signals.clicked 		  do app.selected_track = track_num
		if signals.double_clicked do track.sampler.show = !track.sampler.show
		if signals.dropped_on 	  do track_dropped_on = true
	}

	if ui_state.show_mixer {
		controls_container := child_container(
			{
				size = {{.Fixed, track_width}, {.Percent, 0.3}},
				color = .Red_500,
			},
			{
				direction = .Horizontal,
				alignment_horizontal = .Center,
				alignment_vertical = .End
			},
			id("track-{}-controls-container", track_num),
			{.Draw, .Drag_Drop_Sink, .Frosted, .Clickable},
		)
		if controls_container.clicked { 
			app.selected_track = track_num
		}
		if track_num == app.selected_track { 
			controls_container.box.config.border = border(2)
			controls_container.box.config.border_color = .Red_500
		}

		volume_slider := vertical_slider(
			{size = {{.Percent, 0.333}, {.Grow, 30}}, margin = {left = 30}},
			&track.volume,
			0,
			100,
			id("heytrack-{}-volume-slider", track_num),
		)

		{
			child_container(
				{
					size={{.Percent, 0.7}, {.Percent, 1}}
				}, 
				{
					direction = .Vertical, 
					alignment_vertical = .End, 
					alignment_horizontal = .Center
				}
			)
			val :f64 = 0
			circular_knob(
				"pan",
				{
					size = {{.Fixed, 50}, {.Fixed, 50}},
					margin = {bottom = 50}
				},
				&track.pan,
				-100,
				100, 
				type = .Panning,
			)
			arm_label := app.audio.tracks[track_num].armed ? "unarm" : "arm"
			arm_button := text_button(
				arm_label,
				{
					size = {{.Fit_Text_And_Grow, 0.333}, {.Fixed, 30}},
					color = .Secondary,
					text_color = .Slate_900,
					corner_radius = 3,
					max_size = {70, 50}
				},
				id("{}track-{}-arm-button", arm_label, track_num),
				{.Ignore_Parent_Disabled, .Glow},
			)
			solo_track_button := text_button(
				"solo",
				{
					size = {{.Fit_Text_And_Grow, 0.333}, {.Fixed, 30}},
					color = .Secondary,
					text_color = .Slate_900,
					corner_radius = 3,
					max_size = {70, 50}
				},
				id("loadtrack-{}-load-sound-button", track_num),
				{.Glow}
			)
			if arm_button.clicked { 
				undo_push(&track.armed)
				app.audio.tracks[track_num].armed = !app.audio.tracks[track_num].armed 
			}
			if solo_track_button.clicked {
				undo_push(&track)
				track.soloed = !track.soloed
				if track.soloed {
					for &other_track in app.audio.tracks { 
						if &other_track != track { 
							other_track.armed = false
						}
					}
				// Don't really re-arm all tracks, but it's a compromise for now.
				} else { 
					for &other_track in app.audio.tracks { 
						if &other_track != track { 
							other_track.armed = true
						}
					}
				}
			}
		}
		

	}

	show_eq: if track.eq.show {
		_, closed, maximise, maximised := draggable_window(
			id("Track {} EQ", track_num),
			{direction = .Vertical},
			id("eq-{}-dragging-container", track_num),
		)
		if closed.clicked {
			track.eq.show = false
			break show_eq
		}
		if maximised {
			equalizer_8(id("track-{}-eq", track_num), track_num, 1600, 800)
		} else {
			equalizer_8(id("track-{}-eq", track_num), track_num, 800, 400)
		}

	}

	show_sampler: if track.sampler.show {
		container, closed, maximise, maximised := draggable_window(
			id("Track {} Slicer", track_num),
			{direction = .Vertical},
			id("sampler-{}-dragging-container", track_num),
		)
		if closed.clicked {
			track.sampler.show = false
			break show_sampler
		}

		if maximised {
			sampler(track_num, id("track-{}-sampler", track_num), 1300, 600)
		} else {
			sampler(track_num, id("track-{}-sampler", track_num), 650, 300)
		}

		if maximise.clicked {
			track.sampler.cache_invalid = true
			delete(track.sampler.cached_sample_heights)
		  	track.sampler.cached_sample_heights = make([dynamic]Waveform_Sample_Render_Info)
			push_wakeup_event()
		} 
	}

	handle_drop: if track_dropped_on {
		if len(ui_state.dropped_data) < 1 do break handle_drop
		drop_data := pop(&ui_state.dropped_data)
		cpath: cstring
		#partial switch val in drop_data {
			case Browser_File:
				full_path, err := filepath.join({val.parent.path, val.name}, context.temp_allocator)
				cpath = str.clone_to_cstring(full_path)
				printfln("dropped {} onto track", full_path)
			case:
				println("Cant {} this onto a track", val)
				break handle_drop
		}
		track_set_sound(track, cpath)
		push_wakeup_event()
	}
	return Track_Signals{step_signals, {}}
}

equalizer_8 :: proc(eq_id: string, track_num: int, width, height: u32) {
	eq_state := &app.audio.tracks[track_num].eq
	// Fixed size for now, for ease of implementation, but in the future we want this to be inside a
	// resizable floating container.
	eq_container := child_container(
		{
			size = {{.Fixed, f32(width)}, {.Fixed, f32(height)}},
			color = .Secondary_Container,
			z_index = 10,
		},
		{alignment_horizontal = .Space_Between},
		id("{}-container", eq_id),
		{.Draw, .Glow, .Frosted},
	)
	
	// For now, we auto create 4 bands for each eq (1 eq per track by default).
	active_band := &eq_state.bands[eq_state.active_band]

	eq: {
		child_container(
			{
				size = {{.Percent, 1}, {.Percent, 1}},
				z_index = 30,
			},
			{},
		)
		main_controls: {
			eq_main_controls := child_container(
				{
					size = {{.Percent, 0.10}, {.Percent, 1}},
				},
				{
					direction = .Vertical,
					alignment_vertical = .Space_Around,
					alignment_horizontal = .Center,
				},
				id("{}-main-controls", eq_id),
				{},
			)
			text(
				tprintf("Band {}", eq_state.active_band),
				{size=Size_Fit_Text, color = .Red_500},
				"heya",
			)
			circular_knob(
				"Freq",
				{color = .Warning_Container},
				&active_band.freq_hz,
				20,
				20_000,
				logarithmic = true,
				type = .Frequency
			)
			circular_knob(
				"Q",
				{color = .Warning_Container},
				&active_band.q,
				0.1,
				10,
				type = .Q
			)
			circular_knob(
				"Gain",
				{color = .Warning_Container},
				&active_band.gain_db,
				-EQ_MAX_GAIN,
				EQ_MAX_GAIN,
				type = .Gain
			)
		}

		freq_display: {
			frequency_display_container := child_container(
				{
					size = Size_Grow,
					color = .Inverse_On_Surface,
					overflow_x = .Hidden,
					overflow_y = .Hidden,
				},
				// {alignment_horizontal = .Space_Between},
				{},
				id("{}-frequency-display-container", eq_id),
				{.Clickable},
			)

			if frequency_display_container.double_clicked {
				box := frequency_display_container.box
				eq_add_band(track_num, f32(map_range(f64(box.top_left.x), f64(box.bottom_right.x), 0.0, 1.0, f64(app.mouse_last_frame.pos.x))), .Bell)
			}
			
			handles := make([dynamic]^Box, context.temp_allocator)
			for i in 0..<eq_state.n_bands {
				band := &eq_state.bands[i]
				handle := box_from_cache(
					{.Draw, .Clickable, .Draggable, .Scrollable},
					{
						color = eq_state.active_band == int(i) ? .Primary : .Tertiary,
						floating_type = .Relative_Other,
						floating_anchor_box = frequency_display_container.box,
						floating_offset = {
							// Convert freq to log-scaled position:
							f32(math.log10(f64(band.freq_hz) / 20.0) / math.log10(f64(20_000.0 / 20.0))),
							f32(map_range(EQ_MAX_GAIN, -EQ_MAX_GAIN, 0.0, 1.0, band.gain_db))
						},
						size = {{.Fixed, 24}, {.Fixed, 24}},
						corner_radius = 12,
						z_index  = 40,
					},
					metadata = Metadata_EQ_Handle {
						which = int(i), 
						band = band,
						track_num = track_num
					}
				)
				append(&handles, handle)
				handle_signals := box_signals(handle)

				if handle_signals.hovering {
					scroll_speed := app.keys_held[sdl.Scancode.LSHIFT] ? 200.0 : 40.0
					if handle_signals.scrolled_up {
						undo_push(&band.q)
						band.q += (10.0 - 0.1) / scroll_speed
					}
					if handle_signals.scrolled_down {
						undo_push(&band.q)
						band.q -= (10.0 - 0.1) / scroll_speed
					}
					band.q = clamp(band.q, 0.1, 10.0)
				}

				if handle_signals.clicked || handle_signals.box == ui_state.dragged_box { 
					eq_state.active_band = int(i)
				}
				if handle_signals.box == ui_state.dragged_box { 
					undo_push(&band.freq_hz)
					undo_push(&band.gain_db)
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
					undo_push(&eq_state.n_bands)
					undo_push(&eq_state.bands)
					eq_state.n_bands -= 1
					eq_state.bands[i] = eq_state.bands[eq_state.n_bands]
				}
			}
			
			curve_total : [FREQ_RESP_BINS]f64
			for &band, i in eq_state.bands[0:eq_state.n_bands] {
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
				for i in 0 ..< len(band_points) {
					curve_total[i] += band_points[i]
				}
				// Not efficient to re-do this even when we have no changes. Must change later.
				eq_reinit_band(band)
			}
			normalized_curve_points: [FREQ_RESP_BINS]f32
			for point, i in curve_total { 
				// normalized_curve_points[i] = f32(map_range(-24.0, 24.0, 0.0, 1.0, point))
				// normalized_curve_points[i] = f32((point + 24.0) / 48.0)
				normalized_curve_points[i] = clamp(f32((point + 24.0) / 48.0), 0, 1)
			}
			eq_state.frequency_response_bins = normalized_curve_points

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
				// if freq_hz < 20 || freq_hz > 20_000 do continue // skip sub-bass
				if freq_hz < 20 || freq_hz > 20_000 {
					frequency_bin_amplitudes[i] = -60.0
					continue
				}

				x := math.log10(freq_hz / 20.0) / math.log10(f32(1000.0)) // 0 <-> 1
				magnitude := max(cmplx.abs(sample), 1e-10) / (FFT_WINDOW_SIZE / 2)
				db := max(20 * math.log10(magnitude), -60)
				frequency_bin_amplitudes[i] = db
			}
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

			// Single quad which pixel shader will draw the frequency response inside of.
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
		}
	}
	
}

counter :: proc(value: ^int) { 
	child_container(
		{}, 
		{direction=.Vertical, alignment_horizontal=.Center, alignment_vertical=.Center}
	)
	text(tprintf("{}", value^), {size=Size_Fit_Text})
	{
		child_container({}, {alignment_horizontal = .Space_Between})
		if text_button("Uppy", {size=Size_Fit_Text}).clicked { 
			value^ += 1
		}
		if text_button("Downer", {size=Size_Fit_Text}).clicked { 
			value^ -= 1
		}
	}
}

sampler :: proc(track_num: int, id_string: string, width, height: u32) {
	track   := &app.audio.tracks[track_num]
	sampler := &track.sampler
	sampler.prev_zoom_amount = sampler.zoom_amount
	sampler.prev_zoom_point = sampler.zoom_point
	sampler_container := child_container(
		{
			size = {{.Fixed, f32(width)}, {.Fixed, f32(height)}},
			color = .Surface_Container_High,
			// border = border(3),
		},
		{
			direction = .Horizontal
		},
		id_string,
		{.Draw, .Glow, .Drop_Shadow, .Frosted, .Drag_Drop_Sink},
	)

	// left_controls: {
	// 	control_container := child_container(
	// 		{
	// 			// size = {{.Percent, 0.1}, {.Percent, 1}},
	// 			size = Size_Grow,
	// 			// color = .Primary,
	// 		},
	// 		{
	// 			direction = .Vertical,
	// 			alignment_vertical = .Space_Around,
	// 			alignment_horizontal = .Center
	// 		},
	// 		id("sampler-{}-left-controls", track_num),
	// 		{.Draw},
	// 	)
	// 	extra_flags := Box_Flags{.Glow}
	// 	text_button(
	// 		"Control 1",
	// 		{
	// 			size = Size_Fit_Text_And_Grow,
	// 			color = .Secondary_Container
	// 		},
	// 		id("sampler-{}-controls-button-1", track_num),
	// 		extra_flags = extra_flags
	// 	)
	// 	text_button(
	// 		"Control 2",
	// 		{
	// 			size = Size_Fit_Text_And_Grow,
	// 			color = .Secondary_Container
	// 		},
	// 		id("sampler-{}-controls-button-2", track_num),
	// 		extra_flags = extra_flags
	// 	)
	// 	text_button(
	// 		"Control 3",
	// 		{
	// 			size = Size_Fit_Text_And_Grow,
	// 			color = .Secondary_Container
	// 		},
	// 		id("sampler-{}-controls-button-3", track_num),
	// 		extra_flags = extra_flags
	// 	)
	// 	text_button(
	// 		"Control 4",
	// 		{
	// 			size = Size_Fit_Text_And_Grow,
	// 			color = .Secondary_Container
	// 		},
	// 		id("sampler-{}-controls-button-4", track_num),
	// 		extra_flags = extra_flags
	// 	)
	// }

	main_content: {
		// Inside here we'll render the waveform and the slice markers.
		waveform_parent := child_container(
			{
				size = {{.Percent, 1}, {.Percent, 1}},
				color = .Secondary,
			},
			{
			},
			id("{}-waveform-display", sampler_container.box.id),
			{.Clickable, .Scrollable},
			Metadata_Sampler{
				track_num
			},
		)
		if waveform_parent.double_clicked {
			if sampler.n_slices == len(sampler.slices) do return
			undo_push(&sampler.slices)
			undo_push(&sampler.n_slices)
			undo_commit()
			screen_normalized :=
				f32(app.mouse.pos.x - waveform_parent.box.top_left.x) /
				f32(waveform_parent.box.prev_width)
			new_slice := Sampler_Slice {
				how_far = sampler.zoom_point + screen_normalized * (1.0 - sampler.zoom_amount),
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
		if waveform_parent.scrolled_up || waveform_parent.scrolled_down {
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

		if waveform_parent.scrolled_left && sampler.zoom_amount > 0.01 { 
			sampler.zoom_point = max(0.01, sampler.zoom_point - 0.01)
		}
		if waveform_parent.scrolled_right && sampler.zoom_amount > 0.01 { 
			sampler.zoom_point = min(0.99, sampler.zoom_point + 0.01)
		}

		slice_config := Box_Config {
			line_thickness = 2,
			color = .Warning,
		}

		// Render slices:
		visible_width := 1.0 - sampler.zoom_amount
		parent_width  := f32(waveform_parent.box.prev_width)
		for i in 0..< sampler.n_slices {
			config := slice_config
			slice := sampler.slices[i]
			screen_normalized := (slice.how_far - sampler.zoom_point) / visible_width
			if screen_normalized < 0 || screen_normalized > 1 do continue
			slice_x_pos := screen_normalized * f32(waveform_parent.box.prev_width) + f32(waveform_parent.box.top_left.x)
			handle_x_frac := (screen_normalized * parent_width - 10) / (parent_width - 20)
			
			drag_handle := text_button(
				tprintf("{}", slice.which + 1),
				{
					floating_type = .Relative_Parent,
					floating_offset = {handle_x_frac, 0},
					size = {{.Fixed, 20}, {.Fixed, 20}},
					color = .Red_500,
					z_index = 50,
				},
				id = id("sampler-{}-slice-{}-handle", track_num, i),
				extra_flags = {.Frosted}
			)
			box_from_cache(
				{.Draw},
				{
					floating_type = .Relative_Other,
					floating_anchor_box = drag_handle.box,
					floating_offset = {0.5, 0},
					size = {{.Fixed, 1}, {.Percent, 1}},
					color = .Yellow_400,
					z_index = 49,
				}
			)
			if drag_handle.box == ui_state.dragged_box {
				drag_delta := get_drag_delta()
				change_as_prct := f32(drag_delta.x) / f32(waveform_parent.box.prev_width)
				sampler.slices[i].how_far -= change_as_prct * visible_width
				sampler.slices[i].how_far = clamp(sampler.slices[i].how_far, 0.0, 1.0)
			}
			if drag_handle.double_clicked {
				sampler.n_slices -= 1
				sampler.slices[i] = sampler.slices[sampler.n_slices]
			}
		}


		// Handle dropping of audio file onto sampler.
		if waveform_parent.dropped_on { 
			println(ui_state.dropped_data)
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
		step_num := metadata.step
		track := &app.audio.tracks[track_num]

		top_level_btn_config := Box_Config {
			size = Size_Fit_Text_And_Grow,
			text_justify  = {.Start, .Center},
			padding = {top = 7, bottom = 7, left = 10, right = 10},
			// border = 1,
		}
		extra_flags := Box_Flags{.Frosted}

		top_level_btn_config.color = .Primary_Container
		add_button := text_button(
			"Add steps",
			top_level_btn_config,
			extra_flags = extra_flags,
		)
		if add_button.clicked { 
			undo_push(track)
			if track.step_sel_start == -1 do track.step_sel_start = 0
			for step in track.step_sel_start ..= track.step_sel_end { 
				track.selected_steps[step] = true
			}
		}

		top_level_btn_config.color = .Warning_Container
		remove_button := text_button(
			"Remove steps",
			top_level_btn_config,
			extra_flags = extra_flags,
		)
		if remove_button.clicked { 
			undo_push(track)
			for step in track.step_sel_start ..= track.step_sel_end { 
				track.selected_steps[step] = false
			}
		}

		box_from_cache({.Draw}, {
			size={{.Grow, 1}, {.Fixed, 1}}, 
			color=.Gray_900,
			margin = {top = 4, bottom = 4}
		})
		top_level_btn_config.color = .Primary_Container
		loop_button := text_button(
			"Loop back here",
			top_level_btn_config,
			extra_flags = extra_flags,
		)

		if loop_button.clicked {
			track.loop_at = metadata.step
		}

		box_from_cache({.Draw}, {
			size={{.Grow, 1}, {.Fixed, 1}}, 
			color=.Gray_900,
			margin = {top = 4, bottom = 4}
		})

		copy_button := text_button(
			"Copy",
			top_level_btn_config,
			extra_flags = extra_flags,
		)
		if copy_button.clicked {
			clear(&track.copied_steps.pitches)
			clear(&track.copied_steps.volumes)
			clear(&track.copied_steps.chops)
			clear(&track.copied_steps.send2)
			clear(&track.copied_steps.selected)

			start := track.step_sel_start
			end   := track.step_sel_end + 1
			printfln("copying from {} to {}", start,end)
			for pitch in track.pitches[start:end] {
				append(&track.copied_steps.pitches, pitch)
			}
			for volume in track.volumes[start:end] {
				append(&track.copied_steps.volumes, volume)
			}
			for s1 in track.chops[start:end] {
				append(&track.copied_steps.chops, s1)
			}
			for s2 in track.send2[start:end] {
				append(&track.copied_steps.send2, s2)
			}
			for selected, i in track.selected_steps[start:end] {
				printfln("track {} selected: {}", i + start, selected)
				append(&track.copied_steps.selected, selected)
			}
		}

		paste_button := text_button(
			"Paste",
			top_level_btn_config,
			extra_flags = extra_flags,
		)
		if paste_button.clicked {
			undo_push(track)
			start := step_num
			for step, i in step_num ..< step_num + len(track.copied_steps.pitches) {
				track.pitches[step] = track.copied_steps.pitches[i] 
			}
			for step, i in step_num ..< step_num + len(track.copied_steps.volumes) {
				track.volumes[step] = track.copied_steps.volumes[i] 
			}
			for step, i in step_num ..< step_num + len(track.copied_steps.selected) {
				track.selected_steps[step] = track.copied_steps.selected[i] 
			}
			for step, i in step_num ..< step_num + len(track.copied_steps.chops) {
				track.chops[step] = track.copied_steps.chops[i] 
			}
			for step, i in step_num ..< step_num + len(track.copied_steps.send2) {
				track.send2[step] = track.copied_steps.send2[i] 
			}
		}

		box_from_cache({.Draw}, {
			size={{.Grow, 1}, {.Fixed, 1}}, 
			color=.Gray_900,
			margin = {top = 4, bottom = 4}
		})


		label := track.eq.show ? "Hide EQ" : "Show EQ"
		activate_eq_button := text_button(
			label,
			top_level_btn_config,
			id("conext-menu-track-{}-EQ", track_num),
			extra_flags = extra_flags,
		)

		if activate_eq_button.clicked {
			track.eq.show = !track.eq.show
		}

		label = track.sampler.show ? "Hide Sampler" : "Show Sampler"
		activate_sampler_button := text_button(
			label,
			top_level_btn_config,
			id("conext-menu-track-{}-sampler", track_num),
			extra_flags = extra_flags,
		)

		if activate_sampler_button.clicked {
			track.sampler.show = !track.sampler.show
		}

		box_from_cache({.Draw}, {
			size={{.Grow, 1}, {.Fixed, 1}}, 
			color=.Gray_900,
			margin = {top = 4, bottom = 4}
		})

		disarm_labl := track.armed ? "Disarm" : "Arm"
		top_level_btn_config.color = .Surface
		disarm_button := text_button(
			id("{} track", disarm_labl),
			top_level_btn_config,
			"conext-menu-3",
			extra_flags = extra_flags,
		)

		box_from_cache({.Draw}, {
			size={{.Grow, 1}, {.Fixed, 1}}, 
			color=.Gray_900,
			margin = {top = 4, bottom = 4}
		})

		top_level_btn_config.color = .Error_Container
		delete_track_button := text_button(
			"Delete Track",
			top_level_btn_config,
			"conext-menu-4",
			extra_flags = extra_flags,
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
				border = border(1)
			}
			if text_button("All steps", btn_config, "context-add-all").clicked {
				track_turn_on_steps(track_num, step_num, 1)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 2nd", btn_config, "context-add-2nd").clicked {
				track_turn_on_steps(track_num, step_num, 2)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 3rd", btn_config, "context-add-3rd").clicked {
				track_turn_on_steps(track_num, step_num, 3)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 4th", btn_config, "context-add-4th").clicked {
				track_turn_on_steps(track_num, step_num, 4)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 6th", btn_config, "context-add-6th").clicked {
				track_turn_on_steps(track_num, step_num, 6)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 8th", btn_config, "context-add-8th").clicked {
				track_turn_on_steps(track_num, step_num, 8)
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
				track_turn_off_steps(track_num, step_num, 1)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 2nd", btn_config, "context-remove-2nd").clicked {
				track_turn_off_steps(track_num, step_num, 2)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 3rd", btn_config, "context-remove-3rd").clicked {
				track_turn_off_steps(track_num, step_num, 3)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 4th", btn_config, "context-remove-4th").clicked {
				track_turn_off_steps(track_num, step_num, 4)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 6th", btn_config, "context-remove-6th").clicked {
				track_turn_off_steps(track_num, step_num, 6)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 8th", btn_config, "context-remove-8th").clicked {
				track_turn_off_steps(track_num, step_num, 8)
				ui_state.clicked_on_context_menu = true
			}
		}

		if disarm_button.clicked { 
			undo_push(track)
			app.audio.tracks[track_num].armed = !app.audio.tracks[track_num].armed
		}
		if delete_track_button.clicked {
			printfln("deleting track: {}", box.metadata.(Metadata_Track_Step).track)
			track_delete(box.metadata.(Metadata_Track_Step).track)
		}
	}

	file_browser_context_menu :: proc(box: ^Box) {
		metadata := box.metadata.(Metadata_Browser_Item)
		dir := metadata.dir
		if dir == nil do return

		config := Box_Config {
			size = Size_Fit_Text_And_Grow,
			text_justify = {.Start, .Center},
			padding = padding(5),
		}

		// Only show "Remove folder" for top-level directories.
		if dir.parent == app.browser_root_dir {
			config.color = .Error_Container
			remove := text_button(
				"Remove folder",
				config,
				"ctx-menu-browser-remove-folder",
			)
			if remove.clicked {
				ui_state.clicked_on_context_menu = true
				if app.browser_selected_dir == dir {
					app.browser_selected_dir = nil
				}
				for sub, i in dir.parent.sub_directories {
					if sub == dir {
						ordered_remove(&dir.parent.sub_directories, i)
						break
					}
				}
				browser_dir_free(dir)
				file_browser_write_to_disk()
				ui_state.context_menu.active = false
			}
		}
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

	waveform_box_context_menu :: proc(track_num: int) {
		btn := text_button(
			"Delete sound",
			{
				size = Size_Fit_Text_And_Grow,
				text_justify = {.Center, .Center},
				padding = padding(10),
				text_color = .Primary
			},
			extra_flags = {.Frosted}
		)

		if btn.clicked { 
			println("Deleting track")
		}
	}

	context_menu_container := child_container(
		{
			size 		= Size_Fit_Children,
			z_index 			= 500,
			floating_type		= .Absolute_Pixel,
			floating_offset 	= {f32(ui_state.context_menu.pos.x), f32(ui_state.context_menu.pos.y)},
			color 				= .Secondary_Container,
			corner_radius 		= 3, 	
			// padding 			= padding(10),
			edge_softness 		= 2,
			// border = 5,
		},
		{
			direction 			 = .Vertical,
			alignment_horizontal = .Center,
			alignment_vertical   = .Center,
		},
		box_flags = {.Draw, .Frosted, .Draw_Border},
	)


	if ui_state.right_clicked_on == nil {
		println("This shouldnt happen ::(")
		return
	}
	switch metadata in ui_state.right_clicked_on.metadata {
	case Metadata_Track_Step:
		track_steps_context_menu(ui_state.right_clicked_on)
	case Metadata_Browser_Item:
		file_browser_context_menu(ui_state.right_clicked_on)
	case Metadata_EQ_Handle:
		eq_handle_context_menu(metadata.which, metadata.track_num, metadata.band)
	case Metadata_Waveform:
		waveform_box_context_menu(metadata.track_num)
	case Metadata_Sampler, Metadata_Audio_Spectrum, Metadata_Track, Metadata_Knob, Metadata_Browser_Waveform:
		text(
			"Context menu not implemented for this box type @ alskdaajfalskdjfladf",
			{size = Size_Fit_Text},
		)
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
		case Metadata_Track, Metadata_Sampler, Metadata_Browser_Item, Metadata_EQ_Handle, Metadata_Audio_Spectrum, Metadata_Knob, Metadata_Waveform, Metadata_Browser_Waveform:
			panic("set_nth_child() should only be called on box with Metadata_Track_Step")
		}
	}
}

hover_help_text :: proc(label: string, main_box: ^Box) { 
	// By default hover text is rendered inline with the left edge of the parent box,
	// unless it would overflow.
	font_size :u32 = 20
	padding_size := 4
	text_len := font_get_strings_rendered_len(label, font_size) + padding_size * 2 
	floating_offset: [2]f32 
	if (text_len + main_box.top_left.x) > app.wx {
		printfln("help label: {} will go offscreen, so render it to the left", label)
		floating_offset = {
			f32(main_box.bottom_right.x - text_len),
			f32(main_box.bottom_right.y + 2)
		}
	} else { 
		floating_offset = {
			f32(main_box.top_left.x + padding_size),
			f32(main_box.bottom_right.y + 2)
		}
	}
	child_container(
		{
			floating_type = .Absolute_Pixel,
			floating_offset = floating_offset,
			size = Size_Fit_Children,
			padding = padding(padding_size),
			border = border(1),
			border_color = .Red_500,
			z_index = 500,
			min_size = {50, 30},
			corner_radius = 3,
		},
		{alignment_horizontal = .Center, alignment_vertical = .Center},
		box_flags = {.Draw, .Frosted, .Draw_Border}
	)
	text(label, {size=Size_Fit_Text, text_justify = {.Center, .Center}, color = .Stone_500, font_size = 20})
}
// ===============================================================================