// Project Twilight launcher window. Talks to the Rust side through Tauri
// commands; opened in a plain browser it runs on sample data for design work.
"use strict";

const tauri = window.__TAURI__;
const invoke = tauri ? tauri.core.invoke : mockInvoke;
const $ = (id) => document.getElementById(id);

let state = null;
let launching = false;
let toastTimer = 0;
const DEFAULT_THEME_HUE = 200;

function themeHue(value) {
  const n = Number(value);
  return Number.isFinite(n) ? Math.max(0, Math.min(360, Math.round(n))) : DEFAULT_THEME_HUE;
}

function applyTheme(value) {
  const hue = themeHue(value);
  document.documentElement.style.setProperty("--theme-hue", `${hue}deg`);
  const input = $("in-hue");
  if (input && document.activeElement !== input) input.value = String(hue);
  const output = $("hue-value");
  if (output) output.textContent = `${hue}°`;
  return hue;
}

// --- Rendering ---------------------------------------------------------------

function baseName(p) {
  return String(p || "").replace(/[\\/]+$/, "").split(/[\\/]/).pop() || "";
}

function el(tag, cls, text) {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text !== undefined) n.textContent = text;
  return n;
}

function bar(cls, value) {
  const b = el("div", "bar " + cls);
  b.style.setProperty("--v", String(Math.max(0, Math.min(1, value))));
  b.append(el("i", "trail"), el("i", "fill"), el("i", "ticks"));
  return b;
}

function setChip(id, level, value) {
  const c = $(id);
  c.classList.remove("ok", "warn", "bad");
  if (level) c.classList.add(level);
  c.querySelector(".chip-v").textContent = value;
  c.title = value;
}

function zeny(n) {
  return Number(n || 0).toLocaleString("en-US");
}

function renderCharacters(list) {
  const box = $("chars");
  box.replaceChildren();
  if (!list.length) {
    box.append(el("div", "empty", "No characters yet. Press PLAY and create one — it will appear here with its levels."));
    return;
  }
  for (const c of list) {
    const row = el("div", "char");
    const top = el("div", "char-top");
    top.append(el("span", "char-name", c.name), el("span", "char-lv", `Lv ${c.level} / Job ${c.job_level}`));
    const where = c.map ? ` · ${c.map.toUpperCase()}` : "";
    const meta = el("div", "char-meta", `${c.job_name.toUpperCase()}${where} · ${zeny(c.zeny)} Z`);
    const bars = el("div", "char-bars");
    const base = bar("base", c.level / c.level_cap);
    base.title = `Base level ${c.level} of ${c.level_cap}`;
    const job = bar("job", c.job_level / c.job_level_cap);
    job.title = `Job level ${c.job_level} of ${c.job_level_cap}`;
    bars.append(base, job);
    row.append(top, meta, bars);
    box.append(row);
  }
}

function checkRow(key, value, level, fill, action) {
  const row = el("div", "check");
  row.append(el("span", "check-k", key));
  const mid = el("div", "check-mid");
  const v = el("div", "check-v" + (level === "ok" ? "" : " dim"), value);
  v.title = value;
  mid.append(v, bar(level === "ok" ? "hp" : level, fill));
  row.append(mid);
  if (action) {
    const b = el("button", "link", action.label);
    b.addEventListener("click", action.run);
    row.append(b);
  } else {
    row.append(el("span"));
  }
  return row;
}

function render() {
  const s = state;
  const e = s.engine, p = s.project, d = s.data;

  // Top rail
  setChip("chip-engine", e.usable ? "ok" : "bad", e.usable ? `Godot ${e.version}` : e.found ? "wrong version" : "not found");
  setChip("chip-project", p.found ? "ok" : "bad", p.found ? `v${p.version || "?"}` : "not found");
  setChip("chip-data", d.found ? "ok" : d.path ? "bad" : "warn", d.found ? baseName(d.path) : d.path ? "missing" : "set in game");
  setChip("chip-saves", s.characters.length ? "ok" : "", `${s.characters.length} character${s.characters.length === 1 ? "" : "s"}`);

  renderCharacters(s.characters);

  // System check
  const checks = $("checks");
  checks.replaceChildren(
    checkRow("ENGINE", e.usable ? `Godot ${e.version}  ·  ${e.chosen ? "chosen" : "found automatically"}` : e.note || "Not found",
      e.usable ? "ok" : "bad", e.usable ? 1 : e.found ? 0.35 : 0.08,
      e.usable ? null : { label: "LOCATE", run: () => openSettings("godot") }),
    checkRow("GAME", p.found ? `Project Twilight ${p.version}` : p.note, p.found ? "ok" : "bad", p.found ? 1 : 0.08,
      p.found ? null : { label: "LOCATE", run: () => openSettings("project") }),
    checkRow("DATA", d.found ? `${baseName(d.path)}  ·  ${d.archives} archive${d.archives === 1 ? "" : "s"}${d.has_music ? "  ·  music" : ""}` : d.note,
      d.found ? "ok" : d.path ? "bad" : "warn", d.found ? 1 : d.path ? 0.15 : 0.5,
      d.found ? null : { label: "SET", run: () => openSettings("data") }),
  );

  // Hero call-out for whatever blocks PLAY (engine first: it is the usual one).
  const callout = $("callout");
  const alt = $("callout-alt");
  alt.hidden = true;
  if (!e.usable) {
    callout.hidden = false;
    callout.className = "callout bad";
    $("callout-title").textContent = e.found ? "THIS GODOT CANNOT RUN THE GAME" : "GODOT ENGINE NOT FOUND";
    $("callout-body").textContent = e.found
      ? e.note
      : "Project Twilight runs on Godot 4.8. Show the launcher where your Godot executable is, or download it (it is one file, no installer).";
    $("callout-fix").textContent = "LOCATE GODOT…";
    $("callout-fix").onclick = locateGodot;
    alt.hidden = false;
    alt.textContent = "DOWNLOAD";
    alt.onclick = () => open("godot");
  } else if (!p.found) {
    callout.hidden = false;
    callout.className = "callout bad";
    $("callout-title").textContent = "GAME FILES NOT FOUND";
    $("callout-body").textContent = p.note;
    $("callout-fix").textContent = "CHOOSE FOLDER…";
    $("callout-fix").onclick = () => pick("project");
  } else if (d.path && !d.found) {
    callout.hidden = false;
    callout.className = "callout";
    $("callout-title").textContent = "RAGNAROK DATA FOLDER LOOKS WRONG";
    $("callout-body").textContent = `${d.note} You can still start: the game will ask for the folder.`;
    $("callout-fix").textContent = "CHOOSE FOLDER…";
    $("callout-fix").onclick = () => pick("data");
  } else {
    callout.hidden = true;
  }

  // Play button + launch bar (left alone while a launch is animating).
  if (!launching) {
    const play = $("play");
    play.classList.remove("running", "blocked");
    const lb = $("launch-bar");
    lb.classList.remove("busy", "done", "fail");
    if (s.running) {
      play.disabled = true;
      play.classList.add("running");
      $("play-label").textContent = "RUNNING";
      $("play-sub").textContent = "THE GAME IS OPEN";
      lb.classList.add("done");
      lb.style.setProperty("--v", "1");
      $("launch-status").textContent = "Project Twilight is running. Have fun.";
      $("launch-pct").textContent = "";
    } else if (!s.ready) {
      play.disabled = false;
      play.classList.add("blocked");
      $("play-label").textContent = !e.usable ? "LOCATE GODOT" : "LOCATE GAME";
      $("play-sub").textContent = "ONE STEP BEFORE YOU CAN PLAY";
      lb.style.setProperty("--v", String((e.usable ? 0.5 : 0) + (p.found ? 0.25 : 0)));
      $("launch-status").textContent = !e.usable ? "Waiting for the Godot engine." : "Waiting for the game folder.";
      $("launch-pct").textContent = "";
    } else {
      play.disabled = false;
      $("play-label").textContent = "PLAY";
      $("play-sub").textContent = s.characters.length ? "CONTINUE YOUR ADVENTURE" : "START YOUR ADVENTURE";
      lb.style.setProperty("--v", "0");
      $("launch-status").textContent = d.found ? "Ready." : "Ready. The game will ask for your Ragnarok data folder.";
      $("launch-pct").textContent = `v${p.version}`;
    }
  }

  // Status bar
  const dot = $("sb-dot");
  dot.className = "dot " + (s.running ? "run" : s.ready ? "ok" : "bad");
  $("sb-status").textContent = s.running ? "running" : s.ready ? "ready" : "setup needed";
  $("sb-engine").textContent = e.found ? e.path : "not found";
  $("sb-build").textContent = p.found ? p.version : "-";
  $("sb-version").textContent = `launcher v${s.launcher_version}`;

  // Settings sheet
  const cfg = s.config;
  applyTheme(cfg.theme_hue);
  if (document.activeElement !== $("in-godot")) $("in-godot").value = cfg.godot_path;
  if (document.activeElement !== $("in-project")) $("in-project").value = cfg.project_path;
  if (document.activeElement !== $("in-data")) $("in-data").value = cfg.data_path;
  $("in-godot").placeholder = e.found && !e.chosen ? `Found automatically: ${e.path}` : "Found automatically";
  $("in-project").placeholder = p.found && !cfg.project_path ? `Found: ${p.path}` : "Found next to the launcher";
  $("in-data").placeholder = d.path && d.source === "game" ? `From the game: ${d.path}` : "Use what the game has stored";
  setState("st-godot", e.usable ? "ok" : "bad", e.usable ? `Godot ${e.version} — ready` : e.note);
  setState("st-project", p.found ? "ok" : "bad", p.found ? `Project Twilight ${p.version}` : p.note);
  setState("st-data", d.found ? "ok" : d.path ? "bad" : "warn",
    d.found ? `${d.archives} archive${d.archives === 1 ? "" : "s"} found${d.has_music ? ", with a BGM folder" : ", no BGM folder (no music)"}` : d.note);
  $("tg-fullscreen").checked = cfg.fullscreen;
  $("tg-close").checked = cfg.close_on_launch;
  $("tg-console").checked = cfg.console;
}

function setState(id, level, text) {
  const n = $(id);
  n.className = "state " + level;
  n.textContent = text;
}

function toast(text, bad) {
  const t = $("toast");
  t.textContent = text;
  t.className = "toast show" + (bad ? " bad" : "");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => (t.className = "toast"), bad ? 5200 : 2600);
}

// --- Actions -------------------------------------------------------------------

async function refresh() {
  try {
    state = await invoke("get_state");
    render();
  } catch (err) {
    toast(String(err), true);
  }
}

async function saveConfig(patch) {
  const config = Object.assign({}, state.config, patch);
  try {
    state = await invoke("set_config", { config });
    render();
  } catch (err) {
    toast(`Settings could not be saved: ${err}`, true);
  }
}

const FIELD_OF = { godot: "godot_path", project: "project_path", data: "data_path" };

async function pick(kind) {
  const key = FIELD_OF[kind];
  const current = state.config[key] || (kind === "godot" ? state.engine.path : kind === "project" ? state.project.path : state.data.path) || "";
  let chosen = null;
  try {
    chosen = await invoke("browse", { kind, current });
  } catch (err) {
    toast(String(err), true);
    return;
  }
  if (!chosen) return;
  await saveConfig({ [key]: chosen });
  if (kind === "godot") {
    toast(state.engine.usable ? `Godot ${state.engine.version} selected.` : state.engine.note, !state.engine.usable);
  } else if (kind === "project") {
    toast(state.project.found ? "Game folder set." : state.project.note, !state.project.found);
  } else {
    toast(state.data.found ? "Data folder set." : state.data.note, !state.data.found);
  }
}

function locateGodot() {
  openSettings("godot");
  pick("godot");
}

async function autoDetect() {
  const found = await invoke("auto_detect_godot");
  await saveConfig({ godot_path: "" });
  toast(found ? `Found Godot at ${found}` : "No Godot 4 executable was found. Use BROWSE… to point at it.", !found);
}

function open(target) {
  invoke("open_target", { target }).catch((err) => toast(String(err), true));
}

function openSettings(focus) {
  $("scrim").hidden = false;
  $("sheet").classList.add("open");
  $("sheet").setAttribute("aria-hidden", "false");
  if (focus) {
    const f = $("field-" + focus);
    f.scrollIntoView({ block: "nearest" });
    f.classList.add("flash");
    setTimeout(() => f.classList.remove("flash"), 1400);
  }
}

function closeSettings() {
  $("scrim").hidden = true;
  $("sheet").classList.remove("open");
  $("sheet").setAttribute("aria-hidden", "true");
}

const wait = (ms) => new Promise((r) => setTimeout(r, ms));

async function play() {
  if (launching || !state) return;
  if (!state.engine.usable) return locateGodot();
  if (!state.project.found) return pick("project");
  launching = true;
  const btn = $("play"), lb = $("launch-bar");
  btn.disabled = true;
  btn.classList.remove("blocked", "running");
  $("play-label").textContent = "STARTING";
  $("play-sub").textContent = "PLEASE WAIT";
  lb.classList.remove("done", "fail");
  lb.classList.add("busy");
  const step = async (v, text) => {
    lb.style.setProperty("--v", String(v));
    $("launch-status").textContent = text;
    $("launch-pct").textContent = `${Math.round(v * 100)}%`;
    await wait(360);
  };
  try {
    await step(0.2, `Engine: Godot ${state.engine.version}`);
    await step(0.45, `Game: Project Twilight ${state.project.version}`);
    await step(0.7, state.data.found ? `Data: ${baseName(state.data.path)}` : "Data: the game will ask for it");
    await step(0.88, "Starting the engine…");
    await invoke("launch");
    lb.style.setProperty("--v", "1");
    lb.classList.remove("busy");
    lb.classList.add("done");
    $("launch-pct").textContent = "100%";
    launching = false;
    state.running = true;
    render();
  } catch (err) {
    lb.classList.remove("busy");
    lb.classList.add("fail");
    $("launch-status").textContent = String(err);
    $("launch-pct").textContent = "failed";
    toast(String(err), true);
    await wait(2200);
    launching = false;
    await refresh();
  }
}

// --- Wiring ----------------------------------------------------------------------

function wire() {
  $("play").addEventListener("click", play);
  $("open-settings").addEventListener("click", () => openSettings());
  $("sheet-close").addEventListener("click", closeSettings);
  $("sheet-done").addEventListener("click", closeSettings);
  $("scrim").addEventListener("click", closeSettings);
  $("recheck").addEventListener("click", async () => { await refresh(); toast("Checked again."); });
  $("auto-godot").addEventListener("click", autoDetect);
  $("win-min").addEventListener("click", () => invoke("win_minimize"));
  $("win-close").addEventListener("click", () => invoke("win_close"));
  document.querySelectorAll("[data-target]").forEach((b) => b.addEventListener("click", () => open(b.dataset.target)));
  document.querySelectorAll("[data-open]").forEach((b) => b.addEventListener("click", () => openSettings(b.dataset.open)));
  document.querySelectorAll("[data-browse]").forEach((b) => b.addEventListener("click", () => pick(b.dataset.browse)));
  document.querySelectorAll("[data-clear]").forEach((b) => b.addEventListener("click", () => saveConfig({ [FIELD_OF[b.dataset.clear]]: "" })));
  for (const [id, key] of [["in-godot", "godot_path"], ["in-project", "project_path"], ["in-data", "data_path"]]) {
    const input = $(id);
    const commit = () => { if (state && input.value.trim() !== state.config[key]) saveConfig({ [key]: input.value.trim() }); };
    input.addEventListener("change", commit);
    input.addEventListener("keydown", (ev) => { if (ev.key === "Enter") input.blur(); });
  }
  for (const [id, key] of [["tg-fullscreen", "fullscreen"], ["tg-close", "close_on_launch"], ["tg-console", "console"]]) {
    $(id).addEventListener("change", (ev) => saveConfig({ [key]: ev.target.checked }));
  }
  $("in-hue").addEventListener("input", (ev) => applyTheme(ev.target.value));
  $("in-hue").addEventListener("change", (ev) => saveConfig({ theme_hue: themeHue(ev.target.value) }));
  $("hue-reset").addEventListener("click", () => {
    applyTheme(DEFAULT_THEME_HUE);
    saveConfig({ theme_hue: DEFAULT_THEME_HUE });
  });
  document.addEventListener("keydown", (ev) => {
    if (ev.key === "Escape") closeSettings();
    if (ev.key === "Enter" && !$("sheet").classList.contains("open") && document.activeElement === document.body) play();
  });
  document.addEventListener("contextmenu", (ev) => { if (ev.target.tagName !== "INPUT") ev.preventDefault(); });
  // Saves change while the game runs: look again whenever the launcher gets attention.
  window.addEventListener("focus", () => { if (!launching) refresh(); });

  const video = $("bg");
  video.addEventListener("playing", () => video.classList.add("on"), { once: true });
  video.addEventListener("error", () => video.remove());
  video.playbackRate = 0.75;
  const p = video.play();
  if (p && p.catch) p.catch(() => {});

  if (tauri) {
    tauri.event.listen("game-exited", (ev) => {
      launching = false;
      refresh().then(() => {
        if (ev.payload !== 0) toast(`The game closed with code ${ev.payload}. Turn on the engine console in Settings to see why.`, true);
      });
    });
  }
}

// --- Sample data for opening index.html in a browser -------------------------------

function mockInvoke(cmd, args) {
  const q = new URLSearchParams(location.search);
  const missing = q.has("nogodot");
  const m = (window.__mock = window.__mock || {
    config: { godot_path: "", project_path: "", data_path: "", close_on_launch: false, fullscreen: false, console: false, theme_hue: 200 },
    running: false,
  });
  if (cmd === "set_config") m.config = args.config;
  if (cmd === "launch") { m.running = true; return wait(500).then(() => 4242); }
  if (cmd === "browse") return Promise.resolve(null);
  if (cmd === "auto_detect_godot") return Promise.resolve(missing ? null : "X:\\Godot\\Godot_v4.8-beta1_win64.exe");
  if (cmd !== "get_state" && cmd !== "set_config") return Promise.resolve(null);
  return Promise.resolve({
    config: m.config,
    engine: missing
      ? { path: "", found: false, chosen: false, version: "", usable: false, note: "Godot 4 was not found on this PC." }
      : { path: "X:\\Godot\\Godot_v4.8-beta1_win64.exe", found: true, chosen: false, version: "4.8 beta1", usable: true, note: "" },
    project: { path: "E:\\ProjectTwilight\\06_Godot_Project", found: true, version: "0.1.0", note: "" },
    data: { path: "E:/RO/kRO_Latest", found: true, source: "game", archives: 1, has_music: true, note: "" },
    characters: q.has("empty") ? [] : [
      { slot: "slot1", name: "Aldric", job: "knight", job_name: "Knight", level: 72, level_cap: 99, job_level: 41, job_level_cap: 50, zeny: 184220, map: "prontera", saved_at: 0 },
      { slot: "slot2", name: "Seraphine", job: "priest", job_name: "Priest", level: 58, level_cap: 99, job_level: 33, job_level_cap: 50, zeny: 40210, map: "prt_fild08", saved_at: 0 },
      { slot: "slot3", name: "Nyla", job: "assassin_cross", job_name: "Assassin Cross", level: 99, level_cap: 99, job_level: 64, job_level_cap: 70, zeny: 2204100, map: "geffen", saved_at: 0 },
    ],
    launcher_version: "0.1.0",
    running: m.running,
    ready: !missing,
  });
}

wire();
refresh();
