package app

import "core:math"
slider_value: f32 = 0

TOPBAR_HEIGHT :: 50
button_text :: proc(id_string: string, config: Box_Config) -> Box_Signals {
	box := box_from_cache(id_string, {.Clickable, .Active_Animation, .Draw, .Text_Center, .Draw_Text}, config)
	return box_signals(box)
}

button_container :: proc(id_string: string, config: Box_Config) -> Box_Signals {
	box := box_from_cache(id_string, {.Clickable, .Active_Animation, .Draw, .Text_Center}, config)
	return box_signals(box)
}

container :: proc(id_string: string, config: Box_Config) -> Box_Signals {
	box := box_from_cache(id_string, {.Draw}, config)
	return box_signals(box)
}

Track_Steps_Signals :: struct {
	volume, pitch, send1, send2: Box_Signals,
}
Track_Controller_Signals :: struct {
	track, slider, play_button, load_button: Box_Signals,
}
Track_Signals :: struct {
	steps:      Track_Steps_Signals,
	controller: Track_Controller_Signals,
}

audio_track :: proc(track_num: u32, track_width: f32) -> Track_Signals {
	n_steps: f32 = 32
	track_container := container(
		tprintf("@track-{}-container", track_num),
		{semantic_size = {{.Fixed, track_width}, {.Percent, 1}}},
	)
	box_open_children(track_container.box, {direction = .Vertical, gap_vertical = 3})
	defer box_close_children(track_container.box)

	step_signals: Track_Steps_Signals
	steps: {
		steps_container := container(
			tprintf("@track-steps-container-{}", track_num),
			{semantic_size = {{.Fixed, track_width}, {.Percent, 0.7}}, background_color = {1, 0.5, 1, 1}},
		)
		box_open_children(steps_container.box, {direction = .Vertical})
		defer box_close_children(steps_container.box)
		substep_config: Box_Config = {
			semantic_size    = {{.Percent, 0.25}, {.Percent, 1}},
			background_color = {1, 0.5, 0, 1},
		}
		for i in 0 ..< 30 {
			row_container := container(
				tprintf("@track-{}-row-{}-steps-container", track_num, i),
				{semantic_size = {{.Fixed, track_width}, {.Percent, f32(1) / 32.0}}},
			)
			box_open_children(row_container.box, {direction = .Horizontal})
			button_text(id("v@track-{}-volume-step-{}", track_num, i), substep_config)
			button_text(id("p@track-{}-pitch-step-{}", track_num, i), substep_config)
			button_text(id("s1@track-{}-send1-step-{}", track_num, i), substep_config)
			button_text(id("s2@track-{}-send2-step-{}", track_num, i), substep_config)
			box_close_children(row_container.box)
		}
	}

	controls: {
		controls_container := container(
			tprintf("@track-{}-controls-container", track_num),
			{semantic_size = {{.Fixed, track_width}, {.Percent, 0.3}}, background_color = {0.5, 0.7, 0.4, 1}},
		)
		box_open_children(
			controls_container.box,
			{direction = .Horizontal, alignment_horizontal = .Start, alignment_vertical = .End},
		)
		defer box_close_children(controls_container.box)

		arm_button := button_text(
			id("arm@track-{}-arm-button", track_num),
			{semantic_size = {{.Percent, 0.333}, {.Fixed, 30}}, background_color = {1, 1, 0, 1}},
		)
		volume_slider := vertical_slider(
			id("hey@track-{}-volume-slider", track_num), // volume_slider := button_text(
			{
				semantic_size = {{.Percent, 0.333}, {.Grow, 30}}, /*background_color = {1, 0, 0, 1}*/
			},
			&slider_value,
			0,
			100,
		)
		load_sound_button := button_text(
			id("load@track-{}-load-sound-button", track_num),
			{semantic_size = {{.Percent, 0.333}, {.Fixed, 30}}, background_color = {1, 0, 0.5, 1}},
		)
		// if volume_slider.grip.scrolled || volume_slider.track.scrolled {
		// }
	}
	return Track_Signals{step_signals, {}}
}

Slider_Signals :: struct {
	track: Box_Signals,
	grip:  Box_Signals,
}

vertical_slider :: proc(
	id_string: string,
	config: Box_Config,
	slider_value: ^f32,
	min_val: f32,
	max_val: f32,
) -> Slider_Signals {
	slider_container := container(id("{}-container", get_id_from_id_string(id_string)), config)
	box_open_children(slider_container.box, {direction = .Vertical, alignment_horizontal = .Center})
	defer box_close_children(slider_container.box)

	track := box_from_cache(
		id("{}-track", get_id_from_id_string(id_string)),
		{.Clickable, .Draw, .Scrollable},
		{semantic_size = {{.Percent, 0.5}, {.Percent, 1}}, background_color = {1, 1, 1, 1}},
	)
	track_signals := box_signals(track)

	grip := box_from_cache(
		id("{}-grip", get_id_from_id_string(id_string)),
		{.Clickable, .Draggable, .Draw},
		{
			semantic_size = {{.Percent, 0.7}, {.Percent, 0.1}},
			background_color = {0, 0.1, 0.7, 1},
			position_absolute = true,
			offset_from_parent = {0.5, map_range(min_val, max_val, 0, 1, slider_value^)},
		},
	)
	grip_signals := box_signals(grip)

	if track_signals.scrolled || grip_signals.scrolled {
		printfln("changing slider value: {}", app.mouse.wheel)
		if track_signals.scrolled_up || grip_signals.scrolled_up {
			slider_value^ = max(slider_value^ - 1, 0)
		} else if track_signals.scrolled_down || grip_signals.scrolled_down {
			slider_value^ = min(slider_value^ + 1, max_val)
		}
	}
	return Slider_Signals{track_signals, grip_signals}
}

// Can use mouse pos when summoned
test_context_menu :: proc() {
	context_menu_container := container(
		"@context-menu",
		{
			semantic_size = {{.Fit_Children, 1}, {.Fit_Children, 1}},
			padding = {2, 2, 2, 2},
			background_color = {0.5, 0.2, 1, 0.5},
			position_absolute = true,
			offset_from_parent = {f32(app.mouse.pos.x) / f32(app.wx), f32(app.mouse.pos.y) / f32(app.wy)},
		},
	)
	btn_height: f32 = 30
	box_open_children(
		context_menu_container.box,
		{direction = .Vertical, alignment_horizontal = .Center, gap_vertical = 3},
	)
	defer box_close_children(context_menu_container.box)

	b1 := button_text(
	"button1@conext-menu-1",
	{semantic_size = {{.Fit_Text, 1}, {.Fit_Text, btn_height}}, background_color = {1, 0.5, 1, 1}},
	// {semantic_size = {{.Fixed, 50}, {.Fixed, btn_height}}, background_color = {1, 0.5, 1, 1}},
	)
	b2 := button_text(
	"button2@conext-menu-2",
	{semantic_size = {{.Fit_Text, 1}, {.Fit_Text, btn_height}}, background_color = {1, 0.5, 0.7, 1}},
	// {semantic_size = {{.Fixed, 50}, {.Fixed, btn_height}}, background_color = {1, 0.5, 0.7, 1}},
	)
}

/*
Has to be placed in the root container to display properly.
*/
topbar :: proc() {
	topbar_container := container(
	"@topbar",
	{
		semantic_size    = {{.Fixed, f32(app.wx)}, {.Fixed, TOPBAR_HEIGHT}},
		background_color = {1, 1, 1, 0.8},
		// padding = {top = 10, bottom = 5},
	},
	)
	box_open_children(
		topbar_container.box,
		{direction = .Horizontal, alignment_horizontal = .Start, alignment_vertical = .Center, gap_horizontal = 5},
	)
	defer box_close_children(topbar_container.box)
	btn_config := Box_Config {
		semantic_size    = {{.Fit_Text, 1}, {.Fit_Text, 1}},
		background_color = {0.5, 0.7, 0.7, 1},
		corner_radius    = 5,
	}
	button_text("Default layout@top-bar-default", btn_config)
	button_text("Test layout@top-bar-test", btn_config)
}
