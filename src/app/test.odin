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