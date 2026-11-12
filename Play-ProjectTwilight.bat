@echo off
setlocal EnableExtensions
title Project Twilight
rem Launches Project Twilight. Godot 4.8 is the engine; this script only finds it.
rem Where it looks, in order:
rem   1. the GODOT environment variable (full path to a Godot 4 executable)
rem   2. godot_path.txt next to this file (one line: the full path; never committed)
rem   3. this folder and its Godot subfolder
rem   4. "godot" / "godot4" on PATH
rem   5. a Godot folder at the root of any drive, then common install folders

set "PROJECT=%~dp006_Godot_Project"
set "EXE="

if not exist "%PROJECT%\project.godot" (
    echo The game project was not found at:
    echo   %PROJECT%
    echo Keep this file in the Project Twilight folder, next to 06_Godot_Project.
    goto :fail
)

if defined GODOT if exist "%GODOT%" set "EXE=%GODOT%"
if defined EXE goto :run

if exist "%~dp0godot_path.txt" (
    for /f "usebackq delims=" %%P in ("%~dp0godot_path.txt") do if not defined EXE if exist "%%~P" set "EXE=%%~P"
)
if defined EXE goto :run

call :search "%~dp0"
call :search "%~dp0Godot"
if defined EXE goto :run

for %%N in (godot.exe godot4.exe godot.cmd godot.bat) do if not defined EXE if not "%%~$PATH:N"=="" set "EXE=%%~$PATH:N"
if defined EXE goto :run

for %%D in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do call :search "%%D:\Godot"
call :search "%ProgramFiles%\Godot"
call :search "%LOCALAPPDATA%\Programs\Godot"
call :search "%USERPROFILE%\Godot"
call :search "%USERPROFILE%\Downloads"
call :search "%USERPROFILE%\Desktop"
if defined EXE goto :run

echo Godot 4.8 was not found, so the game cannot start.
echo.
echo Project Twilight runs on the Godot engine. Do ONE of these, then run this file again:
echo   - put the Godot 4.8 executable in this folder, or in a "Godot" folder on any drive
echo   - create godot_path.txt next to this file containing the full path to it, e.g.
echo         D:\Tools\Godot_v4.8-stable_win64.exe
echo   - set the GODOT environment variable to that path
echo.
echo Download: https://godotengine.org/download/windows/
goto :fail

:run
echo Starting Project Twilight with:
echo   %EXE%
start "" "%EXE%" --path "%PROJECT%"
if errorlevel 1 (
    echo Godot could not be started.
    goto :fail
)
endlocal
exit /b 0

:fail
echo.
pause
endlocal
exit /b 1

rem Sets EXE to the newest Godot 4 executable in the folder %1 (the windowed
rem build; the "_console" twin is only used when it is the only one there).
:search
if defined EXE exit /b 0
if not exist "%~1\" exit /b 0
for /f "delims=" %%F in ('dir /b /a-d /on "%~1\Godot_v4*.exe" 2^>nul ^| findstr /v /i "_console"') do set "EXE=%~1\%%F"
if defined EXE exit /b 0
for /f "delims=" %%F in ('dir /b /a-d /on "%~1\Godot_v4*.exe" 2^>nul') do set "EXE=%~1\%%F"
exit /b 0
