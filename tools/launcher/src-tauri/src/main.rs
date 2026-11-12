//! Project Twilight launcher.
//!
//! Finds the Godot 4 engine and the game project, remembers the player's
//! choices, shows local characters and starts the game. It never reads,
//! copies or modifies Ragnarok client data: the data folder is only passed
//! to the game as a path.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use serde::{Deserialize, Serialize};
use std::env;
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tauri::{Emitter, Manager};

#[cfg(windows)]
use std::os::windows::process::CommandExt;
#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

const GAME_USER_DIR: &str = "Godot/app_userdata/Project Twilight";
const PROJECT_DIR_NAME: &str = "06_Godot_Project";
const LINK_GITHUB: &str = "https://github.com/XiONDiGiTaL/ProjectTwilight";
const LINK_CHANGELOG: &str = "https://github.com/XiONDiGiTaL/ProjectTwilight/blob/main/CHANGELOG.md";
const LINK_GODOT: &str = "https://godotengine.org/download/windows/";
const LINK_COOP: &str = "https://github.com/XiONDiGiTaL/ProjectTwilight#private-co-op";

// --- Settings ---------------------------------------------------------------------

#[derive(Serialize, Deserialize, Clone)]
#[serde(default)]
struct Config {
    /// Full path to a Godot 4 executable ("" = find it automatically).
    godot_path: String,
    /// Folder containing project.godot ("" = find it next to the launcher).
    project_path: String,
    /// Ragnarok data folder handed to the game ("" = whatever the game has stored).
    data_path: String,
    close_on_launch: bool,
    fullscreen: bool,
    console: bool,
    /// Launcher accent hue in degrees; 200 is the Twilight blue default.
    theme_hue: i32,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            godot_path: String::new(),
            project_path: String::new(),
            data_path: String::new(),
            close_on_launch: false,
            fullscreen: false,
            console: false,
            theme_hue: 200,
        }
    }
}

fn config_file() -> PathBuf {
    let base = env::var_os("APPDATA").map(PathBuf::from).unwrap_or_else(env::temp_dir);
    base.join("ProjectTwilight").join("launcher.json")
}

fn load_config() -> Config {
    let mut cfg = fs::read_to_string(config_file())
        .ok()
        .and_then(|s| serde_json::from_str::<Config>(&s).ok())
        .unwrap_or_default();
    cfg.theme_hue = cfg.theme_hue.clamp(0, 360);
    cfg
}

fn save_config(cfg: &Config) -> Result<(), String> {
    let path = config_file();
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    let text = serde_json::to_string_pretty(cfg).map_err(|e| e.to_string())?;
    fs::write(path, text).map_err(|e| e.to_string())
}

// --- Finding Godot ------------------------------------------------------------------

fn exe_dir() -> PathBuf {
    env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(Path::to_path_buf))
        .unwrap_or_else(|| PathBuf::from("."))
}

/// Folders from the launcher's own folder up to the drive root.
fn ancestors_of_exe() -> Vec<PathBuf> {
    exe_dir().ancestors().map(Path::to_path_buf).collect()
}

/// Newest `Godot_v4*.exe` in a folder; the windowed build wins over its
/// `_console` twin, which is used only when it is alone.
fn godot_in(dir: &Path) -> Option<PathBuf> {
    let mut windowed: Vec<PathBuf> = Vec::new();
    let mut console: Vec<PathBuf> = Vec::new();
    for entry in fs::read_dir(dir).ok()?.flatten() {
        let path = entry.path();
        let name = entry.file_name().to_string_lossy().to_lowercase();
        if !path.is_file() || !name.starts_with("godot_v4") || !name.ends_with(".exe") {
            continue;
        }
        if name.contains("_console") {
            console.push(path);
        } else {
            windowed.push(path);
        }
    }
    windowed.sort();
    console.sort();
    windowed.pop().or_else(|| console.pop())
}

fn godot_on_path() -> Option<PathBuf> {
    let paths = env::var_os("PATH")?;
    for dir in env::split_paths(&paths) {
        for name in ["godot.exe", "godot4.exe"] {
            let p = dir.join(name);
            if p.is_file() {
                return Some(p);
            }
        }
    }
    None
}

/// Everywhere a player is likely to have put Godot, most specific first.
fn detect_godot() -> Option<PathBuf> {
    if let Some(p) = env::var_os("GODOT").map(PathBuf::from) {
        if p.is_file() {
            return Some(p);
        }
    }
    for dir in ancestors_of_exe() {
        if let Ok(text) = fs::read_to_string(dir.join("godot_path.txt")) {
            let p = PathBuf::from(text.lines().next().unwrap_or("").trim().trim_matches('"'));
            if p.is_file() {
                return Some(p);
            }
        }
    }
    for dir in ancestors_of_exe() {
        for sub in ["", "Godot", "godot", "engine"] {
            let d = if sub.is_empty() { dir.clone() } else { dir.join(sub) };
            if let Some(p) = godot_in(&d) {
                return Some(p);
            }
        }
    }
    if let Some(p) = godot_on_path() {
        return Some(p);
    }
    for letter in b'C'..=b'Z' {
        let d = PathBuf::from(format!("{}:\\Godot", letter as char));
        if let Some(p) = godot_in(&d) {
            return Some(p);
        }
    }
    let mut dirs: Vec<PathBuf> = Vec::new();
    for (var, sub) in [
        ("ProgramFiles", "Godot"),
        ("LOCALAPPDATA", "Programs\\Godot"),
        ("LOCALAPPDATA", "Microsoft\\WinGet\\Links"),
        ("USERPROFILE", "Godot"),
        ("USERPROFILE", "Downloads"),
        ("USERPROFILE", "Desktop"),
        ("USERPROFILE", "scoop\\apps\\godot\\current"),
    ] {
        if let Some(base) = env::var_os(var) {
            dirs.push(PathBuf::from(base).join(sub));
        }
    }
    dirs.iter().find_map(|d| godot_in(d))
}

/// Runs `<exe> --version` (5 s limit). Godot prints e.g. "4.8.beta1.official.4d10419ca".
fn godot_version(exe: &Path) -> Option<String> {
    let mut cmd = Command::new(exe);
    cmd.arg("--version").stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null());
    #[cfg(windows)]
    cmd.creation_flags(CREATE_NO_WINDOW);
    let mut child = cmd.spawn().ok()?;
    let start = Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) if start.elapsed() > Duration::from_secs(5) => {
                let _ = child.kill();
                let _ = child.wait();
                return None;
            }
            Ok(None) => std::thread::sleep(Duration::from_millis(40)),
            Err(_) => return None,
        }
    }
    let mut out = String::new();
    child.stdout.take()?.read_to_string(&mut out).ok()?;
    let line = out.lines().map(str::trim).find(|l| l.chars().next().is_some_and(|c| c.is_ascii_digit()))?;
    Some(line.to_string())
}

/// "4.8.beta1.official.4d10419ca" -> "4.8 beta1"; "4.8.1.stable.official.x" -> "4.8.1".
fn pretty_version(raw: &str) -> String {
    let parts: Vec<&str> = raw.split('.').collect();
    let mut nums: Vec<&str> = Vec::new();
    let mut tag = "";
    for p in &parts {
        if p.chars().all(|c| c.is_ascii_digit()) && tag.is_empty() {
            nums.push(p);
        } else if tag.is_empty() {
            tag = p;
            break;
        }
    }
    let base = nums.join(".");
    if tag.is_empty() || tag == "stable" {
        base
    } else {
        format!("{base} {tag}")
    }
}

/// When the windowed binary cannot report its version (no console attached),
/// the file name still tells it: Godot_v4.8-beta1_win64.exe -> "4.8 beta1".
fn version_from_name(exe: &Path) -> Option<String> {
    let name = exe.file_name()?.to_string_lossy().to_string();
    let rest = name.strip_prefix("Godot_v").or_else(|| name.strip_prefix("godot_v"))?;
    let core = rest.split('_').next()?;
    Some(core.replace("-stable", "").replace('-', " "))
}

#[derive(Serialize, Default, Clone)]
struct Engine {
    path: String,
    found: bool,
    /// True when the path came from the player's setting, false when detected.
    chosen: bool,
    version: String,
    /// Godot 4 is required; 3.x and unknown binaries are refused.
    usable: bool,
    note: String,
}

fn inspect_engine(cfg: &Config) -> Engine {
    let chosen = !cfg.godot_path.trim().is_empty();
    let path = if chosen {
        Some(PathBuf::from(cfg.godot_path.trim()))
    } else {
        detect_godot()
    };
    let Some(path) = path else {
        return Engine { note: "Godot 4 was not found on this PC.".into(), ..Default::default() };
    };
    if !path.is_file() {
        return Engine {
            path: path.to_string_lossy().into(),
            chosen,
            note: "That file does not exist any more.".into(),
            ..Default::default()
        };
    }
    // Official builds carry their version in the file name, which is instant.
    // A renamed build (godot.exe, godot4.exe) is asked directly. Anything not
    // named like Godot is never executed: the player may have picked the wrong file.
    let named_godot = path
        .file_name()
        .map(|n| n.to_string_lossy().to_lowercase().contains("godot"))
        .unwrap_or(false);
    let version = version_from_name(&path)
        .or_else(|| named_godot.then(|| godot_version(&path).map(|v| pretty_version(&v))).flatten());
    let (version, usable, note) = match version {
        Some(v) if v.starts_with("4.") => (v, true, String::new()),
        Some(v) => (v.clone(), false, format!("This is Godot {v}; Project Twilight needs Godot 4.8.")),
        None => (String::new(), false, "This does not look like a Godot executable.".into()),
    };
    Engine { path: path.to_string_lossy().into(), found: true, chosen, version, usable, note }
}

// --- The game project -----------------------------------------------------------------

#[derive(Serialize, Default, Clone)]
struct Project {
    path: String,
    found: bool,
    version: String,
    note: String,
}

fn is_project(dir: &Path) -> bool {
    fs::read_to_string(dir.join("project.godot")).map(|t| t.contains("Project Twilight")).unwrap_or(false)
}

fn detect_project() -> Option<PathBuf> {
    for dir in ancestors_of_exe() {
        let nested = dir.join(PROJECT_DIR_NAME);
        if is_project(&nested) {
            return Some(nested);
        }
        if is_project(&dir) {
            return Some(dir);
        }
    }
    None
}

fn project_version(dir: &Path) -> String {
    let text = fs::read_to_string(dir.join("project.godot")).unwrap_or_default();
    text.lines()
        .find_map(|l| l.trim().strip_prefix("config/version="))
        .map(|v| v.trim().trim_matches('"').to_string())
        .unwrap_or_default()
}

fn inspect_project(cfg: &Config) -> Project {
    let chosen = cfg.project_path.trim();
    let path = if chosen.is_empty() {
        detect_project()
    } else {
        let p = PathBuf::from(chosen);
        // Accept the repository root as well as the project folder itself.
        if is_project(&p) {
            Some(p)
        } else if is_project(&p.join(PROJECT_DIR_NAME)) {
            Some(p.join(PROJECT_DIR_NAME))
        } else {
            return Project {
                path: chosen.to_string(),
                note: "No Project Twilight project.godot in that folder.".into(),
                ..Default::default()
            };
        }
    };
    match path {
        Some(p) => Project { version: project_version(&p), path: p.to_string_lossy().into(), found: true, note: String::new() },
        None => Project {
            note: format!("Keep the launcher in the Project Twilight folder, next to {PROJECT_DIR_NAME}."),
            ..Default::default()
        },
    }
}

// --- Ragnarok data (a path only; nothing is read from it) ------------------------------

#[derive(Serialize, Default, Clone)]
struct GameData {
    path: String,
    found: bool,
    /// "launcher" = set here, "game" = stored by the game's own title screen.
    source: String,
    archives: usize,
    has_music: bool,
    note: String,
}

fn game_user_dir() -> Option<PathBuf> {
    env::var_os("APPDATA").map(|a| PathBuf::from(a).join(GAME_USER_DIR))
}

/// `key="value"` from a Godot ConfigFile, without interpreting anything else.
fn cfg_value(file: &Path, key: &str) -> Option<String> {
    let text = fs::read_to_string(file).ok()?;
    text.lines().find_map(|l| {
        let l = l.trim();
        let rest = l.strip_prefix(key)?.trim_start().strip_prefix('=')?;
        Some(rest.trim().trim_matches('"').replace("\\\\", "\\"))
    })
}

fn inspect_data(cfg: &Config, project: &Project) -> GameData {
    let mut source = "launcher";
    let mut path = cfg.data_path.trim().to_string();
    if path.is_empty() {
        source = "game";
        path = game_user_dir()
            .and_then(|d| cfg_value(&d.join("settings.cfg"), "client_path"))
            .or_else(|| {
                project.found.then(|| cfg_value(&Path::new(&project.path).join("twilight.local.cfg"), "client_path")).flatten()
            })
            .or_else(|| env::var("TWILIGHT_RO_CLIENT").ok())
            .unwrap_or_default();
    }
    if path.is_empty() {
        return GameData { note: "Not set. The game asks for it on the title screen.".into(), ..Default::default() };
    }
    let dir = PathBuf::from(&path);
    if !dir.is_dir() {
        return GameData { path, source: source.into(), note: "That folder does not exist.".into(), ..Default::default() };
    }
    // Only file names are looked at, to tell the player whether the folder is plausible.
    let archives = fs::read_dir(&dir)
        .map(|rd| {
            rd.flatten()
                .filter(|e| {
                    let n = e.file_name().to_string_lossy().to_lowercase();
                    n.ends_with(".grf") || n.ends_with(".gpf")
                })
                .count()
        })
        .unwrap_or(0);
    let has_music = dir.join("BGM").is_dir();
    let found = archives > 0 || dir.join("data").is_dir();
    let note = if found { String::new() } else { "No .grf archive or data folder in there.".into() };
    GameData { path, found, source: source.into(), archives, has_music, note }
}

// --- Characters (the game's own local saves, read-only) ---------------------------------

#[derive(Serialize, Clone)]
struct Character {
    slot: String,
    name: String,
    job: String,
    job_name: String,
    level: i64,
    level_cap: i64,
    job_level: i64,
    job_level_cap: i64,
    zeny: i64,
    map: String,
    saved_at: i64,
}

fn title_case(id: &str) -> String {
    id.split('_')
        .map(|w| {
            let mut c = w.chars();
            c.next().map(|f| f.to_uppercase().collect::<String>() + c.as_str()).unwrap_or_default()
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn list_characters() -> Vec<Character> {
    let Some(dir) = game_user_dir().map(|d| d.join("saves")) else { return Vec::new() };
    let mut out = Vec::new();
    let Ok(rd) = fs::read_dir(dir) else { return out };
    for entry in rd.flatten() {
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("json") {
            continue;
        }
        let Ok(text) = fs::read_to_string(&path) else { continue };
        let Ok(v) = serde_json::from_str::<serde_json::Value>(&text) else { continue };
        let c = &v["character"];
        let Some(name) = c["name"].as_str() else { continue };
        let num = |x: &serde_json::Value| x.as_f64().map(|f| f as i64).unwrap_or(0);
        let level = num(&c["level"]).max(1);
        let job_level = num(&c["job_level"]).max(1);
        let job = c["job"].as_str().unwrap_or("novice").to_string();
        out.push(Character {
            slot: path.file_stem().map(|s| s.to_string_lossy().to_string()).unwrap_or_default(),
            name: name.chars().take(24).collect(),
            job_name: title_case(&job),
            job,
            level,
            level_cap: if level > 99 { 150 } else { 99 },
            job_level,
            job_level_cap: if job_level > 50 { 70 } else if job_level > 10 { 50 } else { 10 },
            zeny: num(&c["zeny"]),
            map: c["map"].as_str().unwrap_or("").chars().take(24).collect(),
            saved_at: num(&v["saved_at"]),
        });
    }
    out.sort_by(|a, b| a.slot.cmp(&b.slot));
    out
}

// --- State sent to the window ------------------------------------------------------------

#[derive(Serialize, Clone)]
struct Snapshot {
    config: Config,
    engine: Engine,
    project: Project,
    data: GameData,
    characters: Vec<Character>,
    launcher_version: String,
    running: bool,
    ready: bool,
}

struct Shared {
    running: Arc<AtomicBool>,
}

fn snapshot(cfg: Config, running: bool) -> Snapshot {
    let engine = inspect_engine(&cfg);
    let project = inspect_project(&cfg);
    let data = inspect_data(&cfg, &project);
    let ready = engine.usable && project.found;
    Snapshot {
        config: cfg,
        engine,
        project,
        data,
        characters: list_characters(),
        launcher_version: env!("CARGO_PKG_VERSION").into(),
        running,
        ready,
    }
}

#[tauri::command]
async fn get_state(shared: tauri::State<'_, Shared>) -> Result<Snapshot, String> {
    Ok(snapshot(load_config(), shared.running.load(Ordering::SeqCst)))
}

#[tauri::command]
async fn set_config(mut config: Config, shared: tauri::State<'_, Shared>) -> Result<Snapshot, String> {
    config.theme_hue = config.theme_hue.clamp(0, 360);
    save_config(&config)?;
    Ok(snapshot(config, shared.running.load(Ordering::SeqCst)))
}

/// File / folder pickers. `kind`: "godot" (an .exe), "project" or "data" (a folder).
#[tauri::command]
async fn browse(kind: String, current: String) -> Result<Option<String>, String> {
    let start = PathBuf::from(current.trim());
    let start_dir = if start.is_dir() { Some(start) } else { start.parent().filter(|p| p.is_dir()).map(Path::to_path_buf) };
    let picked = match kind.as_str() {
        "godot" => {
            let mut d = rfd::AsyncFileDialog::new()
                .set_title("Locate the Godot 4 executable")
                .add_filter("Godot engine", &["exe"]);
            if let Some(dir) = start_dir {
                d = d.set_directory(dir);
            }
            d.pick_file().await.map(|f| f.path().to_path_buf())
        }
        "project" | "data" => {
            let title = if kind == "project" {
                "Choose the Project Twilight folder"
            } else {
                "Choose your Ragnarok Online data folder"
            };
            let mut d = rfd::AsyncFileDialog::new().set_title(title);
            if let Some(dir) = start_dir {
                d = d.set_directory(dir);
            }
            d.pick_folder().await.map(|f| f.path().to_path_buf())
        }
        _ => return Err("Unknown picker.".into()),
    };
    Ok(picked.map(|p| p.to_string_lossy().to_string()))
}

#[tauri::command]
async fn auto_detect_godot() -> Result<Option<String>, String> {
    Ok(detect_godot().map(|p| p.to_string_lossy().to_string()))
}

/// Starts the game. Emits "game-exited" (exit code) when it closes.
#[tauri::command]
async fn launch(app: tauri::AppHandle, shared: tauri::State<'_, Shared>) -> Result<u32, String> {
    if shared.running.load(Ordering::SeqCst) {
        return Err("Project Twilight is already running.".into());
    }
    let cfg = load_config();
    let engine = inspect_engine(&cfg);
    let project = inspect_project(&cfg);
    if !engine.found {
        return Err(if engine.note.is_empty() { "Godot 4 was not found.".into() } else { engine.note });
    }
    if !engine.usable {
        return Err(engine.note);
    }
    if !project.found {
        return Err(project.note);
    }
    let mut exe = PathBuf::from(&engine.path);
    if cfg.console {
        // Godot ships a console twin next to the windowed binary.
        let stem = exe.file_stem().map(|s| s.to_string_lossy().to_string()).unwrap_or_default();
        let twin = exe.with_file_name(format!("{stem}_console.exe"));
        if !stem.ends_with("_console") && twin.is_file() {
            exe = twin;
        }
    }
    let mut cmd = Command::new(&exe);
    cmd.arg("--path").arg(&project.path);
    if cfg.fullscreen {
        cmd.arg("--fullscreen");
    }
    if !cfg.data_path.trim().is_empty() {
        cmd.env("TWILIGHT_RO_CLIENT", cfg.data_path.trim());
    }
    cmd.env("GODOT", &engine.path);
    cmd.current_dir(&project.path).stdin(Stdio::null());
    let mut child = cmd.spawn().map_err(|e| format!("Godot could not be started: {e}"))?;
    let pid = child.id();
    let running = shared.running.clone();
    running.store(true, Ordering::SeqCst);
    let close_after = cfg.close_on_launch;
    std::thread::spawn(move || {
        if close_after {
            // Give the game a moment to show its window, then get out of the way.
            std::thread::sleep(Duration::from_millis(2500));
            if matches!(child.try_wait(), Ok(None)) {
                app.exit(0);
                return;
            }
        }
        let code = child.wait().ok().and_then(|s| s.code()).unwrap_or(-1);
        running.store(false, Ordering::SeqCst);
        let _ = app.emit("game-exited", code);
    });
    Ok(pid)
}

/// Opens one of a fixed set of links or folders; nothing from the page is executed.
#[tauri::command]
async fn open_target(target: String) -> Result<(), String> {
    let cfg = load_config();
    let url = match target.as_str() {
        "github" => Some(LINK_GITHUB),
        "changelog" => Some(LINK_CHANGELOG),
        "godot" => Some(LINK_GODOT),
        "coop" => Some(LINK_COOP),
        _ => None,
    };
    if let Some(url) = url {
        let mut cmd = Command::new("rundll32");
        cmd.args(["url.dll,FileProtocolHandler", url]);
        #[cfg(windows)]
        cmd.creation_flags(CREATE_NO_WINDOW);
        return cmd.spawn().map(|_| ()).map_err(|e| e.to_string());
    }
    let folder = match target.as_str() {
        "saves" => game_user_dir().map(|d| d.join("saves")),
        "userdata" => game_user_dir(),
        "project" => {
            let p = inspect_project(&cfg);
            p.found.then(|| PathBuf::from(p.path))
        }
        "config" => config_file().parent().map(Path::to_path_buf),
        _ => return Err("Unknown target.".into()),
    };
    let Some(folder) = folder.filter(|f| f.is_dir()) else {
        return Err("That folder does not exist yet.".into());
    };
    Command::new("explorer").arg(folder).spawn().map(|_| ()).map_err(|e| e.to_string())
}

#[tauri::command]
fn win_minimize(window: tauri::Window) {
    let _ = window.minimize();
}

#[tauri::command]
fn win_close(app: tauri::AppHandle) {
    app.exit(0);
}

fn main() {
    tauri::Builder::default()
        .manage(Shared { running: Arc::new(AtomicBool::new(false)) })
        .setup(|app| {
            if let Some(w) = app.get_webview_window("main") {
                let _ = w.set_title("Project Twilight");
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_state,
            set_config,
            browse,
            auto_detect_godot,
            launch,
            open_target,
            win_minimize,
            win_close
        ])
        .run(tauri::generate_context!())
        .expect("the launcher window could not be created");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn versions_read_like_godot_prints_them() {
        assert_eq!(pretty_version("4.8.beta1.official.4d10419ca"), "4.8 beta1");
        assert_eq!(pretty_version("4.8.1.stable.official.abcdef"), "4.8.1");
        assert_eq!(pretty_version("4.8.stable.official"), "4.8");
        assert_eq!(pretty_version("3.6.stable.official"), "3.6");
    }

    #[test]
    fn version_falls_back_to_the_file_name() {
        assert_eq!(version_from_name(Path::new("X:/Godot/Godot_v4.8-beta1_win64.exe")).as_deref(), Some("4.8 beta1"));
        assert_eq!(version_from_name(Path::new("Godot_v4.8-stable_win64.exe")).as_deref(), Some("4.8"));
        assert_eq!(version_from_name(Path::new("notgodot.exe")), None);
    }

    #[test]
    fn theme_hue_defaults_and_round_trips() {
        let cfg: Config = serde_json::from_str("{}").unwrap();
        assert_eq!(cfg.theme_hue, 200);
        let cfg: Config = serde_json::from_str("{\"theme_hue\": 42}").unwrap();
        assert_eq!(cfg.theme_hue, 42);
        let text = serde_json::to_string(&cfg).unwrap();
        assert!(text.contains("\"theme_hue\":42"));
    }

    #[test]
    fn job_ids_become_names() {
        assert_eq!(title_case("assassin_cross"), "Assassin Cross");
        assert_eq!(title_case("novice"), "Novice");
    }

    #[test]
    fn godot_cfg_values_are_read_plainly() {
        let dir = env::temp_dir().join("twilight_launcher_cfg_test");
        let _ = fs::create_dir_all(&dir);
        let f = dir.join("settings.cfg");
        fs::write(&f, "[resources]\n\nclient_path=\"E:/RO/kRO\"\nother=1\n").unwrap();
        assert_eq!(cfg_value(&f, "client_path").as_deref(), Some("E:/RO/kRO"));
        assert_eq!(cfg_value(&f, "missing"), None);
    }
}
