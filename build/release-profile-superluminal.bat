odin build src -define:hot_reload=false -define:release=true -define:profile=false -o:speed -debug -no-bounds-check -disable-assert -no-type-assert -out:build/app-release-profile-superluminal.bat
REM for superluminal to detect symbols, we need to compile with debug enabled.
