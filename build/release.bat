odin build ../src -define:hot_reload=false -define:release=true -o:speed
odin build ../src/app -build-mode:dll -out:app.dll -o:speed

