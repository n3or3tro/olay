odin build ../src -sanitize:address -debug -linker:radlink -define:hot_reload=true -out:build/app-reloadable-sanitized.exe
odin build ../src/app -sanitize:address -debug  -build-mode:dll -out:app.dll

