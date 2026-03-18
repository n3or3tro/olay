@echo off
setlocal EnableDelayedExpansion
cd /d "%~dp0\.."

set OPTIMIZED=0
set MEM_PROFILE=0
set PERF_PROFILE=0
set DEBUG=0
set SANITIZE=0

:parse_args
if "%~1"=="" goto done_args
if /i "%~1"=="/optimized"    set OPTIMIZED=1
if /i "%~1"=="/mem_profile"  set MEM_PROFILE=1
if /i "%~1"=="/perf_profile" set PERF_PROFILE=1
if /i "%~1"=="/debug"        set DEBUG=1
if /i "%~1"=="/sanitize"     set SANITIZE=1
shift
goto parse_args
:done_args

set DLL_FLAGS=-build-mode:dll -ignore-warnings
set EXE_FLAGS=-define:hot_reload=true -define:release=false -ignore-warnings

if %DEBUG%==1 (
    set DLL_FLAGS=!DLL_FLAGS! -debug
    set EXE_FLAGS=!EXE_FLAGS! -debug
)

if %OPTIMIZED%==1 (
    set DLL_FLAGS=!DLL_FLAGS! -o:speed
    set EXE_FLAGS=!EXE_FLAGS! -o:speed
)

if %MEM_PROFILE%==1 (
    set DLL_FLAGS=!DLL_FLAGS! -define:mem_profile=true
)

if %PERF_PROFILE%==1 (
    set DLL_FLAGS=!DLL_FLAGS! -define:perf_profile=true
)

if %SANITIZE%==1 (
    set DLL_FLAGS=!DLL_FLAGS! -sanitize:address
    set EXE_FLAGS=!EXE_FLAGS! -sanitize:address -linker:radlink
)

echo [dll] odin build src/app %DLL_FLAGS% -out:build/app.dll
odin build src/app %DLL_FLAGS% -out:build/app.dll
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%

echo [exe] odin build src %EXE_FLAGS% -debug -out:build/app-reloadable.exe
odin build src %EXE_FLAGS% -out:build/app-reloadable.exe
