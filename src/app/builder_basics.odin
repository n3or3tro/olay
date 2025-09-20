package app

button_text :: proc(id_string: string, config: Box_Config) -> Box_Signals {
	box := box_from_cache(id_string, {.Clickable, .Active_Animation, .Draw, .Text_Center}, config)
	return Box_Signals{box = box}
}

button_container :: proc(id_string: string, config: Box_Config) -> Box_Signals {
	box := box_from_cache(id_string, {.Clickable, .Active_Animation, .Draw, .Text_Center}, config)
	return Box_Signals{box = box}
}

container :: proc(id_string: string, config: Box_Config) -> Box_Signals {
	box := box_from_cache(id_string, {.Draw}, config)
	return Box_Signals{box = box}
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

	track_container := container("a@track-container", {semantic_size = {{.Fixed, track_width}, {.Percent, 1}}})
	box_open_children(track_container.box, {direction = .Vertical, gap_vertical = 3})
	defer box_close_children(track_container.box)

	step_signals: Track_Steps_Signals
	steps: {
		steps_container := container(
			"a@track-steps-container",
			{semantic_size = {{.Fixed, track_width}, {.Percent, 0.7}}, background_color = {1, 0.5, 1, 1}},
		)
		box_open_children(steps_container.box, {direction = .Horizontal})
		defer box_close_children(steps_container.box)
		substep_config: Box_Config = {
			semantic_size    = {{.Percent, 0.25}, {.Percent, 1 / f32(n_steps)}},
			background_color = {1, 0.5, 0, 1},
		}
		step_signals.volume = button_text("v@text-button", substep_config)
		step_signals.pitch = button_text("p@pitch-button", substep_config)
		step_signals.send1 = button_text("s1@send1-button", substep_config)
		step_signals.send2 = button_text("s2@send2-button", substep_config)
	}

	controls: {
		controls_container := container(
			"c@track-controls-container",
			{semantic_size = {{.Fixed, track_width}, {.Percent, 0.3}}, background_color = {0.5, 0.7, 0.4, 1}},
		)
		box_open_children(controls_container.box, {direction = .Horizontal})
		defer box_close_children(controls_container.box)
		arm_button := button_text(
			tprintf("arm@track-{}-arm-button", track_num),
			{semantic_size = {{.Percent, 0.333}, {.Fixed, 30}}},
		)
		volume_slider := button_text(
			tprintf("arm@track-{}-volume-slider-base", track_num),
			{semantic_size = {{.Percent, 0.333}, {.Grow, 1}}, background_color = {1, 1, 0, 1}},
		)
		load_sound_button := button_text(
			tprintf("arm@track-{}-load-sound-button", track_num),
			{semantic_size = {{.Percent, 0.333}, {.Fixed, 30}}},
		)
	}
	return Track_Signals{step_signals, {}}
}
