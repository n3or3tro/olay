/* 
These are hotpaths that call box_from_cache in a preconfigured way as to achieve the 
effect of what a user would normally call a 'widget' in a traditional UI framework.

The idea is that they're more specific to this application, where as the hotpaths in builder_basics.odin
should be relatively ubiqitous amongst most UIs. However I do have application specific logic in them,
so they'll need some re-thinking when I ship the UI stuff as a lib.
*/

package app
import "core:sort"
import str "core:strings"


topbar :: proc() {
	child_container(
		"@topbar",
		{
			semantic_size    = {{.Fixed, f32(app.wx)}, {.Fixed, TOPBAR_HEIGHT}},
			color = .Secondary,
			padding = {top = 3, bottom = 3}
		},
		{
			direction = .Horizontal, 
			alignment_horizontal = .Space_Between, 
			alignment_vertical = .Center, 
			gap_horizontal = 5,
		},
	)

	btn_config := Box_Config {
		semantic_size = {{.Fit_Text_And_Grow, 1}, {.Fit_Text_And_Grow, 1}},
		color = .Tertiary,
		corner_radius = 5,
		padding = {top = 0, bottom = 0, left = 2, right = 2},
	}

	left_container: {
		child_container(
			"@top-bar-left-container", 
			{semantic_size = {{.Fit_Children, 1}, {.Fit_Children_And_Grow, 1}}}, 
			{gap_horizontal = 3}
		)
		if text_button("undo@top-bar-undo", btn_config).clicked {
			undo()
		}
		if text_button("redo@top-bar-redo", btn_config).clicked {
			redo()
		}
	}

	middle_container: {
		child_container(
			"@top-bar-middle-container", 
			{semantic_size = {{.Fit_Children, 1}, {.Fit_Children_And_Grow, 1}}}, 
			// {},
			{gap_horizontal = 3}
		)
		label := app.audio.playing ? "Stop" : "Play"
		if text_button(id("{}@top-bar-toggle-playing", label), btn_config).clicked {
			app.audio.playing = !app.audio.playing
		}
	}

	right_container: {
		child_container(
			"@top-bar-right-container", 
			{semantic_size = {{.Fit_Children, 1}, {.Fit_Children_And_Grow, 1}}}, 
			{gap_horizontal = 3}
		)
		if text_button("Default layout@top-bar-default", btn_config).clicked {
			ui_state.tab_num = 0
			ui_state.changed_ui_screen = true
		}
		if text_button("Test layout@top-bar-test", btn_config).clicked {
			ui_state.tab_num = 1
			ui_state.changed_ui_screen = true
		}
		side_bar_btn_id :=
			ui_state.sidebar_shown ? "Close sidebar@top-bar-sidebar-close" : "Open sidebar@top-bar-sidebar-open"
		if text_button(side_bar_btn_id, btn_config).clicked {
			ui_state.sidebar_shown = !ui_state.sidebar_shown
		}
	}
}

audio_track :: proc(track_num: int, track_width: f32, extra_flags := Box_Flags{}) -> Track_Signals {
	track := &app.audio.tracks[track_num]
	n_steps := 32 // This will ultimately be a dynamic size for each track.

	track_container := child_container(
		id("@track-{}-container", track_num),
		{semantic_size = {{.Fixed, track_width}, {.Percent, 1}}},
		{direction = .Vertical, gap_vertical = 3},
		metadata = Metadata_Track {
			track_num = track_num
		}
	)
	track_container.box.disabled = !track.armed
	track_container.box.metadata = Metadata_Track{
		track_num = track_num
	}
	track_label: {
		child_container(
			id("@track-{}-label-container", track_num),
			{
				semantic_size = {{.Fixed, track_width}, {.Fit_Children, 1}}, 
				padding = {left = 4, right = 0}
			},
			{
				direction = .Horizontal,
				alignment_horizontal = .Center, 
				alignment_vertical = .Center
			},
		)
		text(
			id("{} - @track-{}-num", track_num, track_num), 
			{
				semantic_size = Size_Fit_Text,
				color = .Primary_Container,
				text_justify = {.Start, .Center}
			}
		)
		edit_text_box(
			id("@track-{}-name", track_num),
			{
				semantic_size = {{.Grow, 1}, {.Fixed, 30}}, 
				color = .Secondary
			},
			.Generic_One_Line,
		)
	}

	step_signals: Track_Steps_Signals
	steps: {
		child_container(
			id("@track-steps-container-{}", track_num),
			{
				// semantic_size = {{.Fixed, track_width}, {.Percent, 0.7}}, 
				semantic_size = {{.Fixed, track_width}, {.Grow, 0.7}}, 
				color = .Tertiary 
			},
			{direction = .Vertical, gap_vertical = 0},
		)

		substep_config: Box_Config = {
			semantic_size    = {{.Percent, 0.25}, {.Percent, 1}},
			color 			 = .Primary,
			border 			 = 1,
		}
		substep_extra_flags := Box_Flags{.Draw_Border, .Track_Step}

		for i in 0 ..< N_TRACK_STEPS {
			child_container(
				id("@track-{}-row-{}-steps-container", track_num, i),
				{semantic_size = {{.Fixed, track_width}, {.Percent, f32(1) / N_TRACK_STEPS}}},
				{direction = .Horizontal, gap_horizontal = 0},
			)

			pitch_box := edit_text_box(
				id("@track-{}-pitch-step-{}", track_num, i),
				substep_config,
				.Pitch,
				substep_extra_flags,
				metadata = Metadata_Track_Step {
					track = track_num,
					step  = i,
					type  = .Pitch,
				}
			)

			volume_box := edit_number_box(
				id("@track-{}-volume-step-{}", track_num, i),
				substep_config,
				0,
				100,
				Metadata_Track_Step {
					track = track_num,
					step  = i,
					type  = .Volume,
				},
				substep_extra_flags,
			)

			send1_box := edit_number_box(
				id("@track-{}-send1-step-{}", track_num, i),
				substep_config,
				0,
				100,
				Metadata_Track_Step {
					track = track_num,
					step  = i,
					type  = .Send1,
				},
				substep_extra_flags,
			)

			send2_box := edit_number_box(
				id("@track-{}-send2-step-{}", track_num, i),
				substep_config,
				0,
				100,
				Metadata_Track_Step {
					track = track_num,
					step  = i,
					type  = .Send2,
				},
				substep_extra_flags,
			)

			if pitch_box.double_clicked  ||
			   volume_box.double_clicked ||
			   send1_box.double_clicked  ||
			   send2_box.double_clicked 
			{
				track_toggle_step(track_num, i)
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

			// If this is the current step, indicate so.
			if app.audio.tracks[track_num].curr_step == u32(i) {
			 	box_from_cache(
					id("@track-{}-curr-step-indicator", track_num),
					{
						.Draw, .Draw_Border
					},
					{
						floating_anchor_box = pitch_box.box,
						floating_type = .Relative_Other,
						floating_offset = {0, 0},
						semantic_size = {{.Fixed, f32(pitch_box.box.last_width * 4)}, {.Fixed, f32(pitch_box.box.last_height)}},
						color = .Warning_Container,
						border = 2,
					}
				)
				// printfln("created curr_step indicator: {}", curr_step_inidcator)
			}
		}
	}

	sample_label: {
		label : string
		if track.sound != nil { 
			tokens, _ := str.split(track.sound_path, "\\", context.temp_allocator)
			label = tail(tokens)^
		} else {
			label = "No sound loaded"
		}
		text(
			id("{}@{}-file-info", label, track_num),
			{
				semantic_size = {{.Fit_Text_And_Grow, 1}, {.Fit_Text, 1}},
				color = .Primary_Container,
				text_justify = {.Center, .Center},
			},
			// {.Draw}
		)
	}

	controls: {
		controls_container := child_container(
			id("@track-{}-controls-container", track_num),
			{
				semantic_size = {{.Fixed, track_width}, {.Percent, 0.3}}, 
				color = .Surface_Bright,
			},
			{
				direction = .Horizontal, 
				alignment_horizontal = .Start, 
				alignment_vertical = .End
			},
			{.Draw}
		)
		arm_label := app.audio.tracks[track_num].armed ? "unarm" : "arm"
		arm_button := text_button(
			id("{}@track-{}-arm-button", arm_label, track_num),
			{
				semantic_size = {{.Percent, 0.333}, {.Fixed, 30}}, 
				color = .Secondary,
				corner_radius = 3,

			},
			{.Ignore_Parent_Disabled}
		)
		volume_slider := vertical_slider(
			id("hey@track-{}-volume-slider", track_num),
			{semantic_size = {{.Percent, 0.333}, {.Grow, 30}}},
			&track.volume,
			0,
			100,
		)
		load_sound_button := text_button(
			id("load@track-{}-load-sound-button", track_num),
			{
				semantic_size = {{.Percent, 0.333}, {.Fixed, 30}}, 
				color = .Secondary,
				corner_radius = 3,
			},
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

	if track.eq.show { 
		draggable_window(id("Track {} EQ@eq-{}-dragging-container", track_num, track_num), {
			direction = .Vertical,
		})
		equalizer_8("@track-{}-eq", track_num)
	}

	if track.sampler.show { 
		draggable_window(id("Track {} Sampler@sampler-{}-dragging-container", track_num, track_num), {
			direction = .Vertical,
		})
		sampler("@track-{}-sampler", track_num)
	}
	return Track_Signals{step_signals, {}}
}

context_menu :: proc() {
	track_steps_context_menu :: proc(box: ^Box) {
		track_num := box.metadata.(Metadata_Track_Step).track
		track := &app.audio.tracks[track_num]

		top_level_btn_config := Box_Config {
			semantic_size = Size_Fit_Text_And_Grow,
			text_justify  = {.Start, .Center},
			padding = padding(10),
			border = 1,
		}

		top_level_btn_config.color = .Tertiary
		add_button := text_button(
			"Add steps@context-menu-1",
			top_level_btn_config,
		)

		top_level_btn_config.color = .Primary_Container
		remove_button := text_button(
			"Remove steps@conext-menu-2",
			top_level_btn_config,
		)

		disarm_labl := track.armed ? "Disarm" : "Arm"
		top_level_btn_config.color = .Warning
		disarm_button := text_button(
			id("{} track@conext-menu-3", disarm_labl),
			top_level_btn_config
		)

		label := track.eq.show ? "Hide EQ" : "Show EQ"
		activate_eq_button := text_button(
			id("{}@conext-menu-track-{}-EQ", label, track_num),
			top_level_btn_config
		)

		if activate_eq_button.clicked { 
			track.eq.show = !track.eq.show
		}

		label = track.sampler.show ? "Hide Sampler" : "Show Sampler"
		activate_sampler_button := text_button(
			id("{}@conext-menu-track-{}-sampler", label, track_num),
			top_level_btn_config
		)

		if activate_sampler_button.clicked { 
			track.sampler.show = !track.sampler.show
		}

		top_level_btn_config.color = .Error_Container
		delete_track_button := text_button(
			"Delete Track@conext-menu-4",
			top_level_btn_config,
		)

		add_submenu_id := "@add-step-hover-container"
		add_submenu_hovered := false
		if submenu_box, ok := ui_state.box_cache[add_submenu_id[1:]]; ok {
			add_submenu_hovered = mouse_inside_box(submenu_box, app.mouse.pos)
		}
		if add_button.hovering || add_submenu_hovered {
			hover_container := child_container(
				add_submenu_id,
				{
					floating_type = .Absolute_Pixel,
					floating_offset = {f32(add_button.box.bottom_right.x), f32(add_button.box.top_left.y)},
					semantic_size = Size_Fit_Children,
					z_index = 20,
				},
				{direction = .Vertical, gap_vertical = 2},
				{.Clickable},
			)
			btn_config := Box_Config {
				semantic_size    = Size_Fit_Text_And_Grow,
				text_justify 	 = {.Start, .Center},
				color 			 = .Secondary,
				padding          = {10, 10, 10, 10},
				border = 1
			}
			if text_button("All steps@context-add-all", btn_config).clicked {
				track_turn_on_steps(track_num, 0, 1)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 2nd@context-add-2nd", btn_config).clicked {
				track_turn_on_steps(track_num, 0, 2)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 3rd@context-add-3rd", btn_config).clicked {
				track_turn_on_steps(track_num, 0, 3)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 4th@context-add-4th", btn_config).clicked {
				track_turn_on_steps(track_num, 0, 4)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 6th@context-add-6th", btn_config).clicked {
				track_turn_on_steps(track_num, 0, 6)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 8th@context-add-8th", btn_config).clicked {
				track_turn_on_steps(track_num, 0, 8)
				ui_state.clicked_on_context_menu = true
			}
		}

		remove_submenu_id := "@remove-step-hover-container"
		remove_submenu_hovered := false
		if submenu_box, ok := ui_state.box_cache[remove_submenu_id[1:]]; ok {
			remove_submenu_hovered = mouse_inside_box(submenu_box, app.mouse.pos)
		}
		if remove_button.hovering || remove_submenu_hovered {
			hover_container := child_container(
				remove_submenu_id,
				{
					floating_type = .Absolute_Pixel,
					floating_offset = {
						f32(remove_button.box.bottom_right.x),
						f32(remove_button.box.top_left.y),
					},
					semantic_size = Size_Fit_Children,
					z_index = 20,
				},
				{direction = .Vertical, gap_vertical = 2},
				{.Clickable},
			)
			btn_config := Box_Config {
				semantic_size    = Size_Fit_Text_And_Grow,
				color 			 = .Secondary,
				padding          = {10, 10, 10, 10},
			}
			if text_button("All steps@context-remove-all", btn_config).clicked {
				track_turn_off_steps(track_num, 0, 1)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 2nd@context-remove-2nd", btn_config).clicked {
				track_turn_off_steps(track_num, 0, 2)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 3rd@context-remove-3rd", btn_config).clicked {
				track_turn_off_steps(track_num, 0, 3)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 4th@context-remove-4th", btn_config).clicked {
				track_turn_off_steps(track_num, 0, 4)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 6th@context-remove-6th", btn_config).clicked {
				track_turn_off_steps(track_num, 0, 6)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 8th@context-remove-8th", btn_config).clicked {
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

	context_menu_container := child_container(
		"@context-menu",
		{
			semantic_size 		= Size_Fit_Children,
			z_index 			= 100,
			floating_type		= .Absolute_Pixel,
			floating_offset 	= {f32(ui_state.context_menu.pos.x), f32(ui_state.context_menu.pos.y)},
		},
		{
			direction 			 = .Vertical, 
			alignment_horizontal = .Center, 
			alignment_vertical   = .Center, 
		},
		{.Draw}
	)

	if ui_state.right_clicked_on.disabled { 
		println("right clicked on a disabled box")
		return
	}
	switch metadata in ui_state.right_clicked_on.metadata {
	case Metadata_Track_Step:
		track_steps_context_menu(ui_state.right_clicked_on)
	case Metadata_Track:
		text(
			"Context menu not implemented for this box type @ alskdjfalskdjfladf",
			{semantic_size = Size_Fit_Text},
		)
	case Metadata_Sampler:
		text(
			"Context menu not implemented for this box type @ alskdaajfalskdjfladf",
			{semantic_size = Size_Fit_Text},
		)
	}
}

file_browser_menu :: proc() {
	child_container(
		"@file-browser-container",
		{
			semantic_size 	= {{.Fit_Children, 1}, {.Fit_Children, 1}},
			color 			= .Primary_Container,
			padding 		= {bottom = 5},
			z_index 		= 10,
		},
		{direction = .Vertical},
		{.Draw}
	)
	top_menu: {
		child_container(
			"@file-browser-options-container",
			{
				semantic_size 	= Size_Fit_Children,
				padding 		= padding(10),
				color 			= .Tertiary,
			},
			{direction = .Horizontal, alignment_horizontal = .Center, alignment_vertical = .Center},
		)
		btn_config := Box_Config {
			color 			 = .Secondary,
			border			 = 3,
			padding          = {10, 10, 10, 10},
			semantic_size    = Size_Fit_Text_And_Grow,
			corner_radius    = 0,
		}
		option_load := text_button("Add@browser-options-folder-button", btn_config)
		option_sort := text_button("Sort@browser-options-sort-button", btn_config)
		box_from_cache("@filler-hehe", {.Draw}, {semantic_size = Size_Grow})
		option_flip := text_button("Flip@browser-options-flip-button", btn_config)

		if option_load.clicked {
			res, ok := file_dialog_windows(true, context.temp_allocator)
			if !ok {
				// panic(
				println(
					"File dialogue failure, either:\n- Failed to open dialogue.\n- Failed to return files from dialogue.",
				)
			}
			for path in res {
				path_string := str.clone_from_cstring(path)
				append(&app.browser_files, path_string)
			}
		}
		// --- Don't think this sorting actually changes anything.
		sort.quick_sort(app.browser_files[:])
	}

	files_and_folders: {
		child_container(
			"@browser-files-container",
			{
				semantic_size = Size_Fit_Children, 
				color = .Surface,
				padding = {5,5,5,0}
			},
			{
				direction = .Vertical,
				gap_vertical = 0,
			},
		)

		// Can see having issues with the index being in the id here.
		for file, i in app.browser_files {
			text(
				id("{}@browser-file-{}", file, i),
				{
					semantic_size = Size_Fit_Text_And_Grow,
					padding = padding(5),
					corner_radius = 4,
					text_justify = {.Start, .Center},
					color = .Surface
				},
				{.Hot_Animation, .Clickable}
			)
			// Don't draw divider on last line.
			if i != len(app.browser_files) - 1  {
			}
		}
	}
}

equalizer_8 :: proc(id_string: string, track_num: int) {
	eq_state := &app.audio.tracks[track_num].eq
	// Fixed size for now, for ease of implementation, but in the future we want this to be inside a 
	// resizable floating container.
	eq_container := child_container(
		id_string, 
		{
			semantic_size = {{.Fixed, 800}, {.Fixed, 400}},
			color = .Secondary_Container,
			z_index = 10,
			padding = padding(3),
		},
		{
			alignment_horizontal = .Space_Between
		},
		{.Draw}
	)
	actual_id := get_id_from_id_string(id_string)
	
	// For now, we auto create 4 bands for each eq (1 eq per track by default).
	active_band := &eq_state.bands[eq_state.active_band]

	eq: {
		child_container(
			id("@{}-main-content", actual_id),
			{
				// semantic_size = {{.Percent, 0.3}, {.Percent, 0.5}},
				semantic_size = Size_Fit_Children_And_Grow,
				z_index = 30,
				color = .Error_Container,
			},
			{
				gap_horizontal = 4,
			},
			{.Draw},
		)
		main_controls: {
			eq_main_controls := child_container(
				id("@{}-main-controls", actual_id),
				{
					semantic_size = {{.Percent, 0.11}, {.Percent, 1}},
					// padding = {left=4, right=4, top=10, bottom=10},
				},
				{
					direction = .Vertical, 
					alignment_vertical = .Space_Around,
					alignment_horizontal = .Center,
				},
				{.Draw}
			)
			text(
				id("Band {}@heya", eq_state.active_band),
				{semantic_size=Size_Fit_Text, color = .Secondary},
			)
			circular_knob(
				id("Freq@{}-freq-cntrl", actual_id),
				{color = .Warning_Container},
				&active_band.pos,
				0, 
				1
			)
			circular_knob(
				id("Q@{}-q-cntrl", actual_id),
				{color = .Warning_Container},
				&active_band.q,
				0, 
				1
			)
			circular_knob(
				id("Gain@{}-gain-cntrl", actual_id),
				{color = .Warning_Container},
				&active_band.gain,
				-1 * EQ_MAX_GAIN, 
				EQ_MAX_GAIN	
			)
		}
		freq_display: {
			frequency_display_container := child_container(
				id("@{}-frequency-display-container", actual_id),
				{
					semantic_size = Size_Grow,
					color = .Inverse_On_Surface,
				},
				{alignment_horizontal = .Space_Between},
				{.Draw},
			)
			/* Draw background frequency ranges. */
			// Draw DB levels: 
			line_base_config := Box_Config {
				color = .Tertiary,
				line_thickness = 2,
				edge_softness  = 1,
				z_index = 30,
			}
			// Center 0db line
			tl := frequency_display_container.box.top_left
			br := frequency_display_container.box.bottom_right
			box_height := f32(frequency_display_container.box.last_height)
			db_0_line_start := [2]f32{f32(tl.x), f32(tl.y) + box_height / 2.0 }
			db_0_line_end   := [2]f32{f32(br.x), f32(br.y) - box_height / 2.0 }
			db_0_config := line_base_config
			db_0_config.line_start = db_0_line_start
			db_0_config.line_end   = db_0_line_end
			line(
				id("@{}-graph-hori-0", actual_id),
				db_0_config
			)

			// Probably need to account for padding.
			gap_to_top := box_height / 2
			// Since we want 3db, 6db, 9db, 12db,
			gap := gap_to_top / 4
			for i in -4 ..= 4 {
				if i == 0 do continue
				new_config := line_base_config
				tl := frequency_display_container.box.top_left
				br := frequency_display_container.box.bottom_right
				line_start := db_0_line_start.xy + {0, gap * f32(i)}
				line_end   :=   db_0_line_end.xy   + {0, gap * f32(i)}
				new_config.line_start = line_start
				new_config.line_end   = line_end
				line(
					id("@{}-graph-hori-{}", actual_id, i),
					new_config,
				)
			}

			// I'm thinking I could maybe leverage the auto layout algos to place the gridlines,
			// but we'll hardcode for it now.
			// freq_graph: {
			// 	child_container(
			// 		id("@{}-freq-grid", actual_id),
			// 		{
			// 			semantic_size = {{.Percent, 1}, {.Percent, 1}} 
			// 		},
			// 		{
			// 			direction = .Vertical,
			// 		}
			// 	)
			// }

			handles := make([dynamic]^Box, context.temp_allocator)
			for &band, i in eq_state.bands { 
				handle := box_from_cache(
					id("@{}-band-{}-handle", actual_id, i),
					{.Draw, .Clickable, .Draggable},
					{
						color = eq_state.active_band == i ? .Error_Container : .Warning_Container,
						floating_type = .Relative_Other,
						floating_anchor_box = frequency_display_container.box,
						floating_offset = {
							band.pos, 
							map_range(-1*EQ_MAX_GAIN, EQ_MAX_GAIN, 0, 1, band.gain)
						},
						semantic_size = {{.Fixed, 30}, {.Fixed, 30}},
						corner_radius = 15,
						z_index  = 40,
					}
				)
				append(&handles, handle)
				handle_signals := box_signals(handle)
				if handle_signals.clicked || handle_signals.dragging { 
					eq_state.active_band = i
				}
				if handle_signals.dragging { 
					printfln("Dragging grip, drag delta: {}", handle_signals.drag_delta)
					// drag_delta is automatically populated
					mouse_y := f32(app.mouse.pos.y)
					parent_top := f32(handle.parent.top_left.y)  
					parent_height := f32(handle.parent.last_height)
					normalized_pos := clamp((mouse_y - parent_top) / parent_height, 0, 1)
					band.gain = map_range(f32(0), f32(1), -EQ_MAX_GAIN, EQ_MAX_GAIN, normalized_pos)

					mouse_x := f32(app.mouse.pos.x)
					parent_left := f32(handle.parent.top_left.x)
					parent_width := f32(handle.parent.last_width)  
					normalized_pos = clamp((mouse_x - parent_left) / parent_width, 0, 1)
					band.pos = map_range(f32(0), f32(1), 0, 1, normalized_pos)
				}
			}
			// Draw lines between handles.
			for handle, i in handles { 
				// Actually the last band in the list might not be the further to the right
				// so in prod, this isn't how we'd structure it.
				if i == len(eq_state.bands) - 1 do continue
				config := Box_Config {
					line_start = box_center(handles[i]^),
					line_end   = box_center(handles[i+1]^),
					line_thickness = 4,
					z_index = 35,
					edge_softness = 1,
				}
				line(
					id("@{}-line-from-{}-to-{}", actual_id, i, i+1),
					config,
				)
			}
		}
		level_meter := box_from_cache(
			id("@{}-level-meter", actual_id),
			{.Draw},
			{
				semantic_size = {{.Fixed, 30}, {.Percent, 1}},
				z_index = 30,
			}
		)
	}
	
}

sampler :: proc(id_string: string, track_num: int) {
	track   := &app.audio.tracks[track_num]
	sampler := &track.sampler

	sampler_container := child_container(
		id_string,
		{
			semantic_size = {{.Fixed, 850}, {.Fixed, 400}},
			color = .Surface_Container_High
		},
		{
			direction = .Horizontal
		},
		{.Draw}
	)

	left_controls: {
		control_container := child_container(
			id("@sampler-{}-left-controls"),
			{
				// semantic_size = {{.Percent, 0.1}, {.Percent, 1}},
				semantic_size = Size_Grow,
				// color = .Primary,
			},
			{
				direction = .Vertical,
				alignment_vertical = .Space_Around,
				alignment_horizontal = .Center
			},
			{.Draw}
		)
		text_button(
			id("Control 1@sampler-{}-controls-button-1"),
			{
				semantic_size = Size_Fit_Text_And_Grow
			}
		)
		text_button(
			id("Control 2@sampler-{}-controls-button-2"),
			{
				semantic_size = Size_Fit_Text_And_Grow
			}
		)
		text_button(
			id("Control 3@sampler-{}-controls-button-3"),
			{
				semantic_size = Size_Fit_Text_And_Grow
			}
		)
		text_button(
			id("Control 4@sampler-{}-controls-button-4"),
			{
				semantic_size = Size_Fit_Text_And_Grow
			}
		)
	}

	main_content: {
		// Inside here we'll render the waveform and the slice markers.
		waveform_parent := child_container(
			id("@{}-waveform-display", sampler_container.box.id),
			{
				semantic_size = {{.Percent, 0.90}, {.Percent, 0.85}},
				color = .Secondary,
			},
			{
			},
			{.Draw, .Clickable},
			metadata = Metadata_Sampler{
				track_num
			}
		)
		if waveform_parent.double_clicked {
			slice_x_pos := 
				f32(app.mouse.pos.x - waveform_parent.box.top_left.x) / 
				f32(waveform_parent.box.last_width)
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
			id("Here is where the waveform goes@sampler-{}-waveform-placeholder", track_num),
			{
				semantic_size = Size_Fit_Text,
				color = .Secondary,
			}
		)

		slice_config := Box_Config { 
			line_thickness = 2,
			color = .Warning, 
		}
		// Render slices:
		for i in 0..< sampler.n_slices {
			config := slice_config
			slice_x_pos := sampler.slices[i].how_far * f32(waveform_parent.box.last_width) + f32(waveform_parent.box.top_left.x) 
			config.line_start = {slice_x_pos, f32(waveform_parent.box.top_left.y)}
			config.line_end = {slice_x_pos, f32(waveform_parent.box.bottom_right.y)}
			line(
				id("@sampler-{}-slice-{}", track_num, i),
				config,
			)
			// Draw drag handle for slice
			drag_handle := button(
				id("@sampler-{}-slice-{}-handle", track_num, i),
				{
					floating_type = .Absolute_Pixel,
					floating_offset = {config.line_start.x - 10, config.line_start.y},
					semantic_size = {{.Fixed, 20}, {.Fixed, 20}},
					color = .Error_Container,
					z_index = 50,
				}
			)
			if drag_handle.dragging {
				change_as_prct := f32(drag_handle.drag_delta.x) / f32(waveform_parent.box.last_width)
				sampler.slices[i].how_far += change_as_prct * 1.001
			}
		}

		bottom_controls: {
			child_container(
				id("@sampler-{}-bottom-controls"),
				{
					color = .Secondary,
					semantic_size = Size_Grow,
				},
				{
					alignment_vertical = .Center,
					alignment_horizontal = .Space_Between,
				}
			)
		}
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
		case Metadata_Track, Metadata_Sampler:
			panic("set_nth_child() should only be called on box with Metadata_Track_Step")
		}
	}
}
// ===============================================================================