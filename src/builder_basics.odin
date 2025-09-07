package main

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
