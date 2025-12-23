package app
import test "core:testing"
import "core:log"
import os "core:os/os2"
import "../app"
import "core:encoding/json"

@(test)
json_theme_parsing :: proc(t: ^test.T) { 
    path := "util/dark-theme.json"
    token_map := parse_json_token_color_mapping(path, context.temp_allocator)
    for key, val in token_map {
        printfln("{}: {}", key, val)
    }
}

@(test)
test_pitch_from_note_string :: proc(t: ^test.T) { 
    test.expect_value(t, pitch_get_from_note("C3"), 0)
    test.expect_value(t, pitch_get_from_note("B3"), -1)
    test.expect_value(t, pitch_get_from_note("C4"), 12)
    test.expect_value(t, pitch_get_from_note("C2"), -12)
    test.expect_value(t, pitch_get_from_note("C#3"), 1)
}