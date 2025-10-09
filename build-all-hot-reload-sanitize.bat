odin build src -sanitize:address -debug -linker:radlink -define:hot_reload=true
odin build src/app -sanitize:address -debug  -build-mode:dll -out:build/app.dll

