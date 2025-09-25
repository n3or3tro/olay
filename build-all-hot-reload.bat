odin build src -debug -linker:radlink -define:hot_reload=true
odin build src/app -debug  -build-mode:dll -out:build/app.dll

