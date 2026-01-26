odin build src/app -debug -build-mode:dll  -ignore-warnings -out:build/app.dll
odin build src -debug -define:hot_reload=true -define:release=false -ignore-warnings -out:build/app-reloadable.exe
