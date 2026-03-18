# Neo Retro Tracker

<img width="1402" height="958" alt="Screenshot 2026-03-19 050917" src="https://github.com/user-attachments/assets/710db8ad-c2ec-487e-b4da-5bcda51917b9" />

A modern take on an old school tracker style step-sequencer.

If you're here as a spectator and just want to run the app, you can skip to [the build instructions](#build). 
Otherwise the rest of this article is targeted at recruiters and technical hiring staff.

--------------
Built from relative scratch (sane use of minimal dependencies) in [Odin](https://odin-lang.org/).

### Key points of interest 
These apply to this specific application, but these are also capabilities that will be surfaced to any user who leverages the underlying UI + application library:

- Hot reloadable dev builds, allows live-reloading of running application code without restarting the process.
- Relatively low memory footprint ~80MB runtime at start-up, with ~50MB runtime working set (on Windows).
- Multithreaded to support real time audio with no audio dropouts or glitches and sample accurate playback.
- Hand made serialization / deserialization system using Odin's runtime type information + reflection capabilities. Used for saving / loading project files and in parts of the undo / redo system.
- SIMD processing of audio visualisations. Written about in depth [here](https://www.neoretro.tech/audio-waveforms-0): 
- Hand made from scratch Immediate Mode UI (IMGUI) system, supporting:
    - Re-usable core widgets (buttons, sliders, text/number input fields).
    - Custom widgets.
    - Auto-layouts + semantic sizing.
    - Animations.
    - Hot reloadable theming.
    - Relatively efficient and good looking font rendering. Builds rendered glyph cache on demand, caches shaped strings, etc.
    - Clipping, scrolling, scrollbars.
    - Virtual scroll lists, significantly reducing CPU / GPU overhead for potentially thousands of off-screen widgets.
    - Integrated font shaping, layout and rendering.
    - Efficient 'wait' based architecture, uses 0% CPU / GPU when there's no user interaction. This was written about in detail in this [blog post](https://www.neoretro.tech/imgui-waste-0)
    - + more
- Hand made OpenGL renderer.
    - Efficient batched instanced quad renderer.
    - Draws entire UI in a single draw call if no blur used. 3 draw calls if using blur.
    - Accurate real time Gaussian blur for frosted glass effects.
    - Hot reloadable shaders.
    - Naive SDF based anti aliasing of basic geometry.
    - Uses <= OpenGL 4.1 features, so cross-platform on Windows, MacOS, Linux.
    - On-screen visibility culling to reduce redundant GPU work.
    - Optional tile-grid based dirty rect tracing to avoid re-rendering parts of the screen which don't change.
- Simple single file build system.
- Simple memory profiler that identifies how much memory has been allocated on each specific arena at the end of each frame.
- Audio:
    - 32 band graphical EQ with real time frequency spectrum visualisation.
    - Slicing sampler with waveform amplitude visualisation.
    - Sample accurate playback across an arbitrary amount of audio tracks.
    - Near instant project exporting to `.wav` output.
    - Fully cross platform via `miniaudio`.
    - Memory efficient - only needs to load each sound in use once, even if a sound is used on many tracks.
- Extensive use of lifetime based arena allocators + scratch allocators for efficient & simple manual memory management.
- Cross platform: Windows, Linux; MacOS coming soon ...

I've written a few in depth blog posts about specific parts of the project you can find [here](https://neoretro.tech/).


---

## Architecture
The base / core layer of the project isn't very creative, it consists of the Odin standard library and [SDL2](https://www.libsdl.org/). Sane, performant, unobtrusive choices which provide plenty of power with few drawbacks.

### Hot Reloading
The core application logic compiles to a versioned DLL (`app_N.dll`). The loader executable holds the SDL window, OpenGL context, and audio threads. The DLL exposes a fixed ABI via an `App_API` struct of function pointers loaded with `dynlib.initialize_symbols`. The two relevant procs are `memory() -> rawptr` and `hot_reload(mem: rawptr)` - the loader retrieves the application state pointer before unloading, then passes it back into the new DLL after loading. Because state lives behind this pointer on the heap owned by the loader's allocator, not in the DLL's data segment, it survives the unload intact. Miniaudio is torn down and reinitialised around the swap since its internal state references DLL memory. Colors (JSON theme file) and GLSL shaders are also hot-reloadable independently via file-modification timestamp polling, without requiring a full DLL reload.

### UI
The entire UI is built on a single primitive: `Box`. Widget capabilities - clickability, scrollability, drag-and-drop, text editing, clipping, simple animations, etc, are encoded as flags on the `Box.flags` bit-set rather than as distinct widget types.

The naïve alternative forces you to model each widget explicitly. Say you've written the code for a draggable and clickable widget (a floating button); the moment you need a widget that is _both_ scrollable _and_ draggable _and_ clickable, you either duplicate code or write a bespoke type / widget. Each new capability multiplies the combinations you have to handle - with N capabilities, that's up to 2^N distinct code paths.

The box model collapses this. Each flag has exactly one implementation in the UI core, layout and rendering passes. A custom widget is (mostly) just a specific combination of flags. Custom widgets with unusual combinations of capabilities or the extension of existing widgets require no new code - just specific flags set, and if a new capability is needed, only one new code path needs to be created in order to afford this capability to all other widgets.

This also means that functions that operate on a heterogenous set of widgets only needs to know about `Box`. For example, `text_button`, `slider`, `scrollbar`, `text_edit_input` or run through the exact same code for: interaction reporting , hit testing, animation ticking, layout traversal, render data collection. Adding a new high-level widget doesn't touch any of these underlying systems and therefore requires minimal new code. 
### Audio + Threading
There are three application-owned threads, not counting threads spawned internally by SDL and miniaudio.

The **main thread** runs the SDL event loop, builds the UI tree, and drives rendering each frame.

The **UI refresh thread** runs at does one thing: while playback is active, it fires a high-resolution waitable timer at ~8ms intervals (`CreateWaitableTimerExW` with `CREATE_WAITABLE_TIMER_HIGH_RESOLUTION` on Windows, `time.accurate_sleep` elsewhere) and pushes a synthetic SDL `USEREVENT` each tick to wake the main thread. This is necessary because the main thread uses a blocking `SDL_WaitEventTimeout` - without the refresh thread prodding it, the UI would not update during playback. When playback stops, this thread blocks on a condition variable rather than spinning.

The **audio timing thread** is responsible for scheduling audio steps ahead of time within an audio time horizon that depends on how many sound copies are configured; the trade-off here is that more sound copies reduce the how often this thread needs to wake, *but* any change to the audio state triggered by the user via the UI isn't reflected in the audio until the next time this thread wakes up. Each track holds `N_SOUND_COPIES` miniaudio sound handles that share the same underlying decoded PCM (audio sample) data - they are round-robined so a future step can be queued before the current one finishes. Using only a single step and resetting it's play head position would lead to audio glitches and also wouldn't facilitate sample accurate playback, since a single sound cant both be set to be playing right now and scheduled to play in the future. Step timing is computed in PCM sample counts against the audio engine's PCM clock, not wall clock time, which is what gives sample-accurate playback regardless of system load.
### Wait Based Event Loop
The main thread blocks on `SDL_WaitEventTimeout` rather than spinning. During playback, the timing thread pushes a synthetic SDL `USEREVENT` each frame to wake the main thread on schedule. When nothing is playing and there is no user input, the process consumes no CPU. The timeout is tuned based on whether animations are active - if something is animating, the wait is short enough to sustain the target frame rate; otherwise it waits indefinitely.

### Rendering
Each frame the UI tree is traversed and per-quad render data is written to a dynamic array allocated on the frame-scoped arena. Each `Rect_Render_Data` entry carries the information required to visually encode the desired widget: position, per-corner colours, corner radius, edge softness (for shadows), border thickness, clipping rect, and so on. Special rendering features are encoded in a `bit_set[UI_Render_Flag; u32]` that the pixel shader switches on to handle different cases:

- **Regular** - rect passthrough, position and colors.
- **Font** - sample from font atlas texture.
- **Waveform** - sample from waveform texture.
- **Frosted glass** - sample from the blurred background FBO.
- **Glow** - blur passed-in colors with edge-lit physics so the box appears to emit light.
- etc.

All of this is encoded in a single `u32` field per instanced quad vertex, kept compact to minimise bandwidth. The array of `Rect_Render_Data` is uploaded to a vertex buffer and dispatched in one draw call into an offscreen FBO. If blur is active, a second pass runs Gaussian blur into a second FBO, and a third pass composites to screen. Visibility culling happens before submission to discard off-screen quads.

### Memory Management
The application makes extensive use of arena allocation techniques.

UI's and most desktop applications can be classed as 'frame oriented', i.e. the application is one big loop where you update the screen once per loop. Many of the allocations made during a single frame, have roughly, the lifetime of that frame. This is perfect use-case for Odin's `context.temp_allocator`  which is just a pre-setup linear arena. It's written to (and grown if needed) linearly as the computations to create and render that frame are performed, and then we clear it at the end of each frame. Clearing it doesn't delete the underlying memory requested from the OS, and therefore next frames allocations, are O(1).

For allocations which don't live as long as the entire frame or live for multiple frames, we use on demand arena allocators. When one is needed, a call to `arena_allocator_new` returns an allocator and it's associated arena. This can then trivially be passed around to relevant functions that handle that widget / subsystem, and when that widget / subsystem is no longer needed, a *single* call to `arena_allocator_destroy` cleans up the memory.

There is the odd use of the general purpose heap allocator via `context.allocator` for allocations whose lifetime  / size is impossible to predict, but these are quite rare.

The combination of these 3 approaches has made manual memory management fairly trivial and more performant than thousands of individual `free` and `delete` calls per frame.

In debug builds, a `mem.Tracking_Allocator` wraps the heap allocator, records every allocation with its call site, and reports any leaks on shutdown as well as the memory usage. In addition to this calls to `arena_allocator_new` / `arena_allocator_destroy` can be hooked as to replace the internal allocator with a tracking allocator, those tracking allocators are stored such that at the end of the frame we can run diagnostics on the amount of memory used by each allocator.

### (De)Serialization
Particular attention has been paid to ensuring the entire application UI is a function of the audio state. When saving and loading project files, only the audio state needs to be serialized, when loading, the UI reconstructs itself 'automagically'.

Struct fields that need to persist are tagged with an `s_id:N` tag:
```odin
Eq_State :: struct { 
	n_eq_band: int `s_id:1`
	freq_hz:   f64 `s_id:2`
	gain_db:   f64 `s_id:3`
	...
	// notice this isn't tagged.
	frequency_spectrum_data: [dynamic]f32
}
```
Fields without a tag are skipped, they are considered runtime-only and recomputed on demand. The serializer uses Odin's `core:reflect` to iterate struct fields at runtime, reading the tag value as a stable numeric identifier in the binary format. This means field ordering and naming can change freely without breaking existing save files, as long as the `s_id` values are preserved. The same mechanism is reused in the undo/redo system to snapshot and restore state without writing separate serialization logic.

### Dependencies

Dependencies are kept as lean as possible. The libraries used solve problems that aren't feasible for one person to solve in a reasonable amount of time. The key requirements were: simple to integrate, stable, low overhead, and flexible.

- **SDL2** - platform layer: windowing, raw mouse/keyboard input, OpenGL context creation. This application could have been built without SDL, but future plans for the UI/application layer may require it.
- **Odin** - the language itself vendors several of its own dependencies:
    - `kb_text_shape` - text shaping, similar in purpose to HarfBuzz but a single-file C header, significantly leaner.
    - `miniaudio` - cross-platform audio I/O and basic sound abstractions.
    - `OpenGL` - GPU-accelerated rendering.
- **FreeType** - rasterising TrueType fonts.
---
# Build

### Windows
I've created pre-built binaries forand Windows [here](https://github.com/n3or3tro/olay/releases).

### Linux
Pre-packaging binaries for distribution for Linux is notoriously painful, so building from source is required.

Requirements:
- SDL2 installed on your system.
- The Odin Programming Language available in the path.
	- Requires version <= dev-2025-12a due to using older version of `vendor:kb_text_shape`.
	- Alternatively you can use the latest version of Odin and patch `vendor:kb_text_shape` with the one from Odin version dev-2025-12a.
- Freetype installed on your system.

Building and running:
- `odin build src -define:hot_reload=false -define:release=true -o:speed -out:<name-of-the-binary>`
- `./<name-of-the-binary>`
