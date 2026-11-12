# Project Twilight launcher

A small native launcher (`ProjectTwilight.exe`, about 4 MB) in the game's Twilight Glass style. It finds the Godot 4 engine and the game project, lets the player point at them when it cannot, shows local characters, and starts the game.

Built with Rust and [Tauri 2](https://tauri.app): the window is the system's WebView2 (part of Windows 10/11), so nothing else is bundled.

## What it does

- **Finds Godot by itself:** the `GODOT` environment variable, `godot_path.txt`, the launcher's folder and its parents (and a `Godot` subfolder), `godot.exe` / `godot4.exe` on PATH, a `Godot` folder on any drive, then Program Files, Downloads and Desktop. The windowed build is preferred over its `_console` twin.
- **Settings → GODOT ENGINE → BROWSE…** lets the player choose the executable when it is somewhere else. A file that is not Godot 4 is refused with a reason. A file that is not named like Godot is never executed to find out.
- **Game folder** and **Ragnarok data folder** can be chosen the same way. The data folder is only passed to the game as a path (`TWILIGHT_RO_CLIENT`); the launcher reads nothing from it except file names, to say whether the folder looks right.
- **Characters:** the game's own saves (`%APPDATA%\Godot\app_userdata\Project Twilight\saves`) are listed read-only, with base and job level drawn as the game's slanted bars.
- **PLAY** runs the checks on the launch bar, starts Godot with `--path`, shows RUNNING until the game closes, and reports a non-zero exit code.
- Options: start in fullscreen, close the launcher when the game starts, show the engine console.
- **Settings → INTERFACE THEME** is a live hue slider for the launcher's glass accents and controls, with a DEFAULT reset. It is launcher-only; the game keeps its own **INTERFACE HUE** setting.

Settings, including the theme hue, are stored in `%APPDATA%\ProjectTwilight\launcher.json`.

## Build

Requirements: Rust (stable) and the Microsoft C++ build tools. No Node.js is needed.

```powershell
cd tools\launcher\src-tauri
cargo build --release
copy target\release\ProjectTwilight.exe ..\..\..\ProjectTwilight.exe
```

Put the exe in the Project Twilight folder, next to `06_Godot_Project`. It also works from any subfolder: it looks upward for the project. The interface in `ui/` (HTML, CSS, JS, the logo and the background loop) is embedded in the exe at build time.

`cargo test` runs the unit tests for version parsing, job names and settings-file reading.

## Files

| Path | Role |
|---|---|
| `src-tauri/src/main.rs` | Detection, settings, save listing, launching, window commands |
| `src-tauri/tauri.conf.json` | Frameless 1120×700 window, content security policy |
| `ui/index.html`, `style.css`, `app.js` | The interface. Opened in a browser it runs on sample data (`?nogodot`, `?empty`) |
| `ui/assets/logo.png` | The project logo |
| `ui/assets/background.webm` | Blurred 16 s loop of Prontera, recorded by `tests/capture_launcher_bg.gd` and encoded by `make_background.py` |

## Background loop

The loop is recorded from the running game and then blurred and darkened **in the file itself** (`make_background.py`), so it works as atmosphere and not as a copy of any game art. To replace it, record your own frames and re-run the script, or drop any `background.webm` into `ui/assets/` and rebuild. If the file is missing the launcher shows its gradient backdrop instead.

## Not done

- No installer, updater or code signing: Windows SmartScreen may warn on first run of a downloaded build.
- The launcher does not download Godot; it links to the official download page.
- Windows only.
