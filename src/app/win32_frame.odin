#+build windows
package app

import "base:runtime"
import "core:sys/windows"
import sdl "vendor:sdl2"

RESIZE_BORDER :: 6
RESIZE_TIMER_ID :: 1

original_wndproc: windows.WNDPROC
app_hwnd: windows.HWND
stored_context: runtime.Context
in_size_move: bool
is_resizing: bool
in_resize_render: bool

// Call after SDL window creation to set up the custom frame with native DWM border.
setup_custom_frame :: proc() {
	wm_info: sdl.SysWMinfo
	sdl.GetWindowWMInfo(app.window, &wm_info)
	app_hwnd = windows.HWND(wm_info.info.win.window)

	// Add thick frame + caption styles so Windows treats this as a resizable, framed window.
	// SDL without BORDERLESS already sets WS_OVERLAPPEDWINDOW, but be explicit.
	style := windows.GetWindowLongPtrW(app_hwnd, windows.GWL_STYLE)
	style |= cast(windows.LONG_PTR)(windows.WS_THICKFRAME | windows.WS_CAPTION | windows.WS_SYSMENU | windows.WS_MINIMIZEBOX | windows.WS_MAXIMIZEBOX)
	windows.SetWindowLongPtrW(app_hwnd, windows.GWL_STYLE, style)

	// Subclass: replace SDL's WndProc with ours, saving the original.
	original_wndproc = transmute(windows.WNDPROC)cast(rawptr)cast(uintptr)windows.GetWindowLongPtrW(app_hwnd, windows.GWLP_WNDPROC)

	// Persist these in the App struct so they survive DLL hot reloads.
	app.win32_hwnd = app_hwnd
	app.win32_original_wndproc = original_wndproc

	windows.SetWindowLongPtrW(
		app_hwnd,
		windows.GWLP_WNDPROC,
		cast(windows.LONG_PTR)cast(uintptr)transmute(rawptr)custom_wndproc,
	)

	// Extend DWM frame by 1px into the client area so the native accent-color border is drawn.
	margins := windows.MARGINS{0, 0, 0, 1}
	windows.DwmExtendFrameIntoClientArea(app_hwnd, &margins)

	// Force a WM_NCCALCSIZE so the new frame metrics take effect immediately.
	windows.SetWindowPos(
		app_hwnd, nil, 0, 0, 0, 0,
		windows.SWP_FRAMECHANGED | windows.SWP_NOMOVE | windows.SWP_NOSIZE | windows.SWP_NOZORDER | windows.SWP_NOOWNERZORDER,
	)

	// Capture the Odin context so we can restore it inside the WndProc (which uses
	// the "system" calling convention and has no implicit context).
	stored_context = context
}

// Re-register the WndProc after a hot reload. The DLL was unloaded and reloaded,
// so the old function pointer is stale. We must NOT re-read original_wndproc here
// because the current WndProc IS our old (now invalid) custom_wndproc.
// Restore the globals from the App struct (which lives on the heap and survives reload).
resubclass_wndproc :: proc() {
	app_hwnd = app.win32_hwnd
	original_wndproc = app.win32_original_wndproc
	windows.SetWindowLongPtrW(
		app_hwnd,
		windows.GWLP_WNDPROC,
		cast(windows.LONG_PTR)cast(uintptr)transmute(rawptr)custom_wndproc,
	)
	stored_context = context
}

// Initiate a native DWM-composited window move. Call when the user starts dragging
// the topbar dead space. This enters a modal move loop (blocks until mouse-up),
// but DWM composites the movement smoothly with no flicker.
begin_native_window_drag :: proc() {
	windows.ReleaseCapture()
	windows.SendMessageW(app_hwnd, windows.WM_SYSCOMMAND, windows.SC_MOVE | 0x02, 0)
}

custom_wndproc :: proc "system" (hwnd: windows.HWND, msg: windows.UINT, wparam: windows.WPARAM, lparam: windows.LPARAM) -> windows.LRESULT {

	switch msg {

	case windows.WM_NCCALCSIZE:
		// wparam == 1 means Windows is asking us to compute the client rect.
		// Returning 0 without modifying the rect makes client area = window area (removes title bar).
		// When maximized we must deflate by the frame thickness to not cover the taskbar.
		if wparam == 1 {
			if bool(windows.IsZoomed(hwnd)) {
				params := cast(^windows.NCCALCSIZE_PARAMS)cast(rawptr)cast(uintptr)lparam
				mi: windows.MONITORINFO
				mi.cbSize = size_of(windows.MONITORINFO)
				monitor := windows.MonitorFromWindow(hwnd, .MONITOR_DEFAULTTONEAREST)
				windows.GetMonitorInfoW(monitor, &mi)
				// Set client rect to the monitor's work area (excludes taskbar).
				params.rgrc[0] = mi.rcWork
			}
			return 0
		}

	case windows.WM_NCHITTEST:
		cursor_pos: windows.POINT
		cursor_pos.x = windows.GET_X_LPARAM(lparam)
		cursor_pos.y = windows.GET_Y_LPARAM(lparam)
		windows.ScreenToClient(hwnd, &cursor_pos)

		rc: windows.RECT
		windows.GetClientRect(hwnd, &rc)

		border := i32(RESIZE_BORDER)
		x := cursor_pos.x
		y := cursor_pos.y

		top    := y < border
		bottom := y >= rc.bottom - border
		left   := x < border
		right  := x >= rc.right - border

		if top && left     do return windows.HTTOPLEFT
		if top && right    do return windows.HTTOPRIGHT
		if bottom && left  do return windows.HTBOTTOMLEFT
		if bottom && right do return windows.HTBOTTOMRIGHT
		if top             do return windows.HTTOP
		if bottom          do return windows.HTBOTTOM
		if left            do return windows.HTLEFT
		if right           do return windows.HTRIGHT

		// Everything else (including topbar) returns HTCLIENT so SDL receives mouse events
		// normally. Topbar dragging is triggered from app code via begin_native_window_drag().
		return 1 // HTCLIENT

	case windows.WM_NCACTIVATE:
		// Return TRUE to prevent the default non-client repaint that causes the white flash.
		return 1

	case windows.WM_NCPAINT:
		// DWM handles the border painting; skip GDI non-client paint entirely.
		return 0

	case windows.WM_ERASEBKGND:
		return 1

	case windows.WM_ENTERSIZEMOVE:
		in_size_move = true
		is_resizing = false
		windows.SetTimer(hwnd, RESIZE_TIMER_ID, 16, nil)
		return 0

	case windows.WM_EXITSIZEMOVE:
		in_size_move = false
		is_resizing = false
		windows.KillTimer(hwnd, RESIZE_TIMER_ID)
		return 0

	case windows.WM_SIZING:
		// WM_SIZING is only sent during a resize drag, never a move.
		is_resizing = true
		return windows.CallWindowProcW(original_wndproc, hwnd, msg, wparam, lparam)

	case windows.WM_TIMER:
		if wparam == RESIZE_TIMER_ID && is_resizing && !in_resize_render {
			in_resize_render = true
			context = stored_context
			app_update()
			in_resize_render = false
		}
		return 0
	}

	return windows.CallWindowProcW(original_wndproc, hwnd, msg, wparam, lparam)
}
