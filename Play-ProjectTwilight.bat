@echo off
rem Launches Project Twilight (offline). Set GODOT to your Godot 4.8 executable if it is not on PATH.
if "%GODOT%"=="" set GODOT=godot
"%GODOT%" --path "%~dp006_Godot_Project"
