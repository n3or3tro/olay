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
			// padding = {top = 10, bottom = 5},
		},
		{direction = .Horizontal, alignment_horizontal = .End, alignment_vertical = .Center, gap_horizontal = 5},
	)
	btn_config := Box_Config {
		semantic_size = {{.Fit_Text, 1}, {.Fit_Text, 1}},
		color = .Tertiary,
		corner_radius = 5,
		padding = {top = 7, bottom = 7, left = 2, right = 2},
	}
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

audio_track :: proc(track_num: int, track_width: f32, extra_flags := Box_Flags{}) -> Track_Signals {
	track := &app.audio.tracks[track_num]
	n_steps := 32

	track_armed := app.audio.tracks[track_num].armed

	track_container := child_container(
		id("@track-{}-container", track_num),
		{semantic_size = {{.Fixed, track_width}, {.Percent, 1}}},
		{direction = .Vertical, gap_vertical = 3},
		metadata = Metadata_Track {
			track_num = track_num
		}
	)
	track_container.box.disabled = !track_armed
	track_container.box.metadata = Metadata_Track{
		track_num = track_num
	}
	// track_label: {
	// 	child_container(
	// 		id("@track-{}-label-container", track_num),
	// 		{semantic_size = {{.Fixed, track_width}, {.Fit_Children, 1}}, padding = {left = 30}},
	// 		{direction = .Horizontal, alignment_horizontal = .Center, alignment_vertical = .Center},
	// 	)
	// 	text(id("{} - @track-{}-num", track_num, track_num), {semantic_size = {{.Fit_Text, 1}, {.Fit_Text, 1}}})
	// 	edit_text_box(
	// 		id("@track-{}-name", track_num),
	// 		{
	// 			semantic_size = {{.Grow, 1}, {.Fixed, 30}}, 
	// 			color = .Secondary
	// 		},
	// 		.Generic_One_Line,
	// 	)
	// }

	step_signals: Track_Steps_Signals
	steps: {
		child_container(
			id("@track-steps-container-{}", track_num),
			{
				semantic_size = {{.Fixed, track_width}, {.Percent, 0.7}}, 
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

			if pitch_box.double_clicked ||
			   volume_box.double_clicked ||
			   send1_box.double_clicked ||
			   send2_box.double_clicked {
				box_siblings_toggle_select(pitch_box.box^)
			}
		}
	}

	controls: {
		controls_container := child_container(
			id("@track-{}-controls-container", track_num),
			{
				semantic_size = {{.Fixed, track_width}, {.Percent, 0.3}}, 
				color = .Surface_Bright,
			},
			{direction = .Horizontal, alignment_horizontal = .Start, alignment_vertical = .End},
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
		if arm_button.clicked { 
			app.audio.tracks[track_num].armed = !app.audio.tracks[track_num].armed 
		}

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
	}
	return Track_Signals{step_signals, {}}
}

context_menu :: proc() {
	track_steps_context_menu :: proc(box: ^Box) {
		track_num := box.metadata.(Metadata_Track_Step).track
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

		disarm_labl := app.audio.tracks[track_num].armed ? "Disarm" : "Arm"
		top_level_btn_config.color = .Warning
		disarm_button := text_button(
			id("{} track@conext-menu-3", disarm_labl),
			top_level_btn_config
		)

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
					position_floating = .Absolute_Pixel,
					position_floating_offset = {f32(add_button.box.bottom_right.x), f32(add_button.box.top_left.y)},
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
				track_num := box.metadata.(Metadata_Track_Step).track
				set_nth_child_select(track_num, 1, true)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 2nd@context-add-2nd", btn_config).clicked {
				track_num := box.metadata.(Metadata_Track_Step).track
				set_nth_child_select(track_num, 2, true)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 3rd@context-add-3rd", btn_config).clicked {
				track_num := box.metadata.(Metadata_Track_Step).track
				set_nth_child_select(track_num, 3, true)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 4th@context-add-4th", btn_config).clicked {
				track_num := box.metadata.(Metadata_Track_Step).track
				set_nth_child_select(track_num, 4, true)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 6th@context-add-6th", btn_config).clicked {
				track_num := box.metadata.(Metadata_Track_Step).track
				set_nth_child_select(track_num, 6, true)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 8th@context-add-8th", btn_config).clicked {
				track_num := box.metadata.(Metadata_Track_Step).track
				set_nth_child_select(track_num, 8, true)
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
					position_floating = .Absolute_Pixel,
					position_floating_offset = {
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
				track_num := box.metadata.(Metadata_Track_Step).track
				set_nth_child_select(track_num, 1, false)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 2nd@context-remove-2nd", btn_config).clicked {
				track_num := box.metadata.(Metadata_Track_Step).track
				set_nth_child_select(track_num, 2, false)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 3rd@context-remove-3rd", btn_config).clicked {
				track_num := box.metadata.(Metadata_Track_Step).track
				set_nth_child_select(track_num, 3, false)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 4th@context-remove-4th", btn_config).clicked {
				track_num := box.metadata.(Metadata_Track_Step).track
				set_nth_child_select(track_num, 4, false)
				ui_state.clicked_on_context_menu = true
			}
			if text_button("Every 6th@context-remove-6th", btn_config).clicked {
				track_num := box.metadata.(Metadata_Track_Step).track
				set_nth_child_select(track_num, 6, false)
				ui_state.clicked_on_context_menu = true

			}
			if text_button("Every 8th@context-remove-8th", btn_config).clicked {
				track_num := box.metadata.(Metadata_Track_Step).track
				set_nth_child_select(track_num, 8, false)
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
			semantic_size 				= Size_Fit_Children,
			z_index 					= 100,
			position_floating 			= .Absolute_Pixel,
			position_floating_offset 	= {f32(ui_state.context_menu.pos.x), f32(ui_state.context_menu.pos.y)},
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
			color = .Secondary,
			border = 3,
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
		case Metadata_Track:
		}
	}
}
// ===============================================================================