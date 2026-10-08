// agent.js v2 - Agent kontrol PC Windows: perintah teks -> 9Router (LLM) -> browser + desktop
import { chromium } from "playwright";
import fs from "fs";
import os from "os";
import path from "path";
import readline from "readline/promises";
import { execFile, spawn } from "child_process";
import { pipeline } from "stream/promises";
import { Readable } from "stream";

const BASE_URL = process.env.ROUTER_URL || "http://localhost:20128/v1";
const API_KEY = process.env.ROUTER_KEY;
const MODEL = process.env.ROUTER_MODEL || "bot-combo";
const SAFE_DIR = path.resolve(process.env.SAFE_DIR || "./upload-folder");
const CONFIRM = process.env.CONFIRM !== "0"; // minta izin sebelum aksi fisik (klik, ketik, buka)
const MAX_STEPS = 30;
const HOME = os.homedir();
const SEARCH_ROOTS = [HOME, ...(process.env.SEARCH_ROOTS ? process.env.SEARCH_ROOTS.split(";") : [])];
for (const L of "DEFGHIJKLMNOPQRSTUVWXYZ") {
  // Drive lain (D:, E:, flashdisk, dll) ikut dicari otomatis
  try {
    if (fs.existsSync(`${L}:\\`)) SEARCH_ROOTS.push(`${L}:\\`);
  } catch {}
}

if (!API_KEY) {
  console.error("ROUTER_KEY belum diisi.");
  process.exit(1);
}
fs.mkdirSync(SAFE_DIR, { recursive: true });

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ===== Pemberitahuan update (URL diberikan otomatis oleh start-agent.bat) =====
const UPD_URL = process.env.UPD_URL || "";
const localVersion = () => {
  try {
    return fs.readFileSync("version.txt", "utf8").trim() || "0";
  } catch {
    return "0";
  }
};
let pendingVersion = "";

async function checkUpdate() {
  if (!UPD_URL || process.env.AUTO_UPDATE === "0") return;
  try {
    const res = await fetch(`${UPD_URL}/version.txt`, { signal: AbortSignal.timeout(10000) });
    if (!res.ok) return;
    const remote = (await res.text()).trim();
    if (remote && remote !== localVersion() && remote !== pendingVersion) {
      pendingVersion = remote;
      console.log(`\n*** UPDATE TERSEDIA: versi ${remote} (versi kamu: ${localVersion()}) ***`);
      console.log('    Ketik "/update" untuk memperbarui otomatis sekarang.');
    }
  } catch {}
}
setInterval(checkUpdate, 15 * 60 * 1000).unref();

// ===== Browser: pakai Chrome/Edge ASLI (bukan Chromium bawaan Playwright) =====
// Alasan: video YouTube butuh codec lengkap, dan Google memblokir login di browser "otomatis".
// Chrome dijalankan biasa dengan port debug, lalu Playwright menyambung ke situ.
// Login tersimpan permanen di folder ./chrome-profile.
const DEBUG_PORT = Number(process.env.DEBUG_PORT || 9222);
const PROFILE_DIR = path.resolve("./chrome-profile");

function findBrowserExe() {
  const local = process.env.LOCALAPPDATA || "";
  const pf = process.env.ProgramFiles || "C:\\Program Files";
  const pf86 = process.env["ProgramFiles(x86)"] || "C:\\Program Files (x86)";
  return [
    process.env.CHROME_PATH,
    path.join(pf, "Google", "Chrome", "Application", "chrome.exe"),
    path.join(pf86, "Google", "Chrome", "Application", "chrome.exe"),
    path.join(local, "Google", "Chrome", "Application", "chrome.exe"),
    path.join(pf86, "Microsoft", "Edge", "Application", "msedge.exe"),
    path.join(pf, "Microsoft", "Edge", "Application", "msedge.exe"),
  ]
    .filter(Boolean)
    .find((x) => fs.existsSync(x));
}

async function debugPortUp() {
  try {
    const r = await fetch(`http://127.0.0.1:${DEBUG_PORT}/json/version`, { signal: AbortSignal.timeout(1500) });
    return r.ok;
  } catch {
    return false;
  }
}

let browserHandle = null;
async function openBrowser() {
  const exe = findBrowserExe();
  if (exe) {
    if (!(await debugPortUp())) {
      spawn(
        exe,
        [
          `--remote-debugging-port=${DEBUG_PORT}`,
          `--user-data-dir=${PROFILE_DIR}`,
          "--no-first-run",
          "--no-default-browser-check",
          "--autoplay-policy=no-user-gesture-required",
          "about:blank",
        ],
        { detached: true, stdio: "ignore" }
      ).unref();
      for (let i = 0; i < 30 && !(await debugPortUp()); i++) await sleep(500);
    }
    if (await debugPortUp()) {
      browserHandle = await chromium.connectOverCDP(`http://127.0.0.1:${DEBUG_PORT}`);
      console.log(`Browser: ${path.basename(exe)} (login tersimpan di ${PROFILE_DIR})`);
      return browserHandle.contexts()[0] || (await browserHandle.newContext());
    }
  }
  console.log("Chrome/Edge tidak ditemukan, memakai Chromium bawaan (video dan login Google mungkin bermasalah).");
  return chromium.launchPersistentContext("./browser-profile", {
    headless: false,
    args: ["--autoplay-policy=no-user-gesture-required"],
    ignoreDefaultArgs: ["--enable-automation"],
  });
}

const context = await openBrowser();
let page = context.pages().find((x) => !x.isClosed()) || (await context.newPage());

async function ensurePage() {
  if (!page.isClosed()) return;
  page = context.pages().find((x) => !x.isClosed()) || (await context.newPage());
}

async function shutdownBrowser() {
  // Chrome sengaja dibiarkan terbuka agar login dan tab tetap ada
  try {
    if (browserHandle) await browserHandle.close();
    else await context.close();
  } catch {}
}

// Nama file relatif dicari di SAFE_DIR; path lengkap di lokasi mana pun boleh.
// Pengamannya adalah izin y/n sebelum setiap upload.
function safePath(name) {
  const full = path.resolve(SAFE_DIR, String(name).replace(/^"|"$/g, ""));
  if (!fs.existsSync(full) || !fs.statSync(full).isFile()) {
    throw new Error("File tidak ditemukan: " + full);
  }
  return full;
}

async function ask(msg) {
  if (!CONFIRM) return true;
  const a = await rl.question(`\n[IZIN] ${msg} (y/n): `);
  return a.trim().toLowerCase() === "y";
}

// ===== Helper PowerShell (kontrol desktop Windows tanpa library tambahan) =====
function ps(script, env = {}, timeout = 30000) {
  const encoded = Buffer.from(script, "utf16le").toString("base64");
  return new Promise((resolve, reject) => {
    execFile(
      "powershell",
      ["-NoProfile", "-NonInteractive", "-EncodedCommand", encoded],
      { env: { ...process.env, ...env }, timeout, maxBuffer: 20 * 1024 * 1024 },
      (err, stdout, stderr) =>
        err ? reject(new Error((stderr || err.message).slice(0, 300))) : resolve(stdout.trim())
    );
  });
}

const PS_HEAD = `
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, int d, UIntPtr e);
}
"@
[W]::SetProcessDPIAware() | Out-Null
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
`;

let scale = 1; // rasio layar asli / screenshot
const pendingImages = []; // gambar yang dikirim ke model setelah tool dijalankan

const SKIP_DIRS = new Set([
  "node_modules", "appdata", ".git", "windows", "program files", "program files (x86)",
  "programdata", "$recycle.bin", "system volume information",
]);
let searchDeadline = 0;

// Cari folder (wantFiles=false) atau file (wantFiles=true) berdasarkan sebagian nama
function findPaths(name, root, depth, out, wantFiles) {
  if (depth < 0 || out.length >= 12 || Date.now() > searchDeadline) return;
  let entries;
  try {
    entries = fs.readdirSync(root, { withFileTypes: true });
  } catch {
    return;
  }
  const q = name.toLowerCase();
  for (const e of entries) {
    const full = path.join(root, e.name);
    if (e.isDirectory()) {
      if (SKIP_DIRS.has(e.name.toLowerCase()) || e.name.startsWith("$")) continue;
      if (!wantFiles && e.name.toLowerCase().includes(q)) out.push(full);
      findPaths(name, full, depth - 1, out, wantFiles);
    } else if (wantFiles && e.isFile() && e.name.toLowerCase().includes(q)) {
      out.push(full);
    }
  }
}

function searchEverywhere(name, wantFiles) {
  const out = [];
  searchDeadline = Date.now() + 12000; // maksimal 12 detik agar tidak menggantung
  for (const root of SEARCH_ROOTS) findPaths(String(name), root, root === HOME ? 5 : 3, out, wantFiles);
  return out.length ? out.join("\n") : "Tidak ditemukan";
}

// ===== "Tangan" agent =====
// ===== Helper tab browser =====
const fixUrl = (u) => (/^[a-z][a-z0-9+.-]*:\/\//i.test(String(u)) ? String(u) : "https://" + String(u));
const isTrue = (v) => v === true || v === "true";
const livePages = () => context.pages().filter((x) => !x.isClosed());

async function tabsSummary() {
  const all = livePages();
  const lines = [];
  for (let i = 0; i < all.length; i++) {
    let title = "";
    try {
      title = await all[i].title();
    } catch {}
    lines.push(`${i + 1}${all[i] === page ? "*" : " "} ${title.slice(0, 60)} | ${all[i].url().slice(0, 100)}`);
  }
  return (lines.join("\n") || "(tidak ada tab)") + "\n(* = tab aktif yang dipakai agent)";
}

function pickTab(all, index) {
  const n = Number(index);
  if (!Number.isFinite(n) || n === 0) return undefined;
  return n < 0 ? all.at(n) : all[n - 1];
}

// ===== Helper YouTube =====
async function skipAds() {
  for (let i = 0; i < 10; i++) {
    const btn = await page.$(".ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern");
    if (btn) {
      await btn.click().catch(() => {});
      return;
    }
    if (!(await page.$(".ad-showing"))) return;
    await sleep(1000);
  }
}

async function readPlayerState() {
  return page.evaluate(() => {
    const v = document.querySelector("video");
    const err = !!document.querySelector(".ytp-error");
    if (v && v.paused && !err) v.play().catch(() => {});
    return { err, playing: !!v && !v.paused && v.readyState > 2 };
  });
}

async function ensurePlaying() {
  for (let attempt = 0; attempt < 2; attempt++) {
    await sleep(3000);
    await skipAds();
    await readPlayerState(); // memicu play()
    await sleep(1200);
    const st = await readPlayerState();
    if (st.playing) return true;
    if (st.err) await page.reload({ waitUntil: "domcontentloaded" });
  }
  return false;
}

const impl = {
  // --- Desktop: file & folder ---
  find_folder: async ({ name }) => searchEverywhere(name, false),

  find_file: async ({ name }) => searchEverywhere(name, true),

  list_dir: async ({ path: p }) => {
    const items = fs.readdirSync(p, { withFileTypes: true }).slice(0, 100);
    return items.map((e) => (e.isDirectory() ? "[DIR] " : "[FILE] ") + e.name).join("\n") || "(kosong)";
  },

  open_path: async ({ target }) => {
    if (!(await ask(`Buka: ${target}`))) return "Dibatalkan user";
    await ps("Start-Process -FilePath $env:TARGET", { TARGET: String(target) });
    await sleep(1500);
    return "ok, dibuka";
  },

  // --- Desktop: layar, mouse, keyboard ---
  screenshot: async () => {
    const out = path.resolve("screen.png");
    const r = await ps(
      PS_HEAD +
        `
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.X, $b.Y, 0, 0, $bmp.Size)
$nw = [Math]::Min(1280, $b.Width)
$nh = [int]($b.Height * $nw / $b.Width)
$small = New-Object System.Drawing.Bitmap $bmp, $nw, $nh
$small.Save($env:OUT, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Output "$($b.Width),$nw,$nh"
`,
      { OUT: out }
    );
    const [w, nw, nh] = r.split("\n").pop().split(",").map(Number);
    scale = w / nw;
    pendingImages.push(fs.readFileSync(out).toString("base64"));
    return `Screenshot diambil (${nw}x${nh}). Gambarnya ada di pesan berikutnya. Pakai koordinat dari gambar itu.`;
  },

  click_screen: async ({ x, y, button = "left", double = false }) => {
    const rx = Math.round(Number(x) * scale);
    const ry = Math.round(Number(y) * scale);
    const dbl = double === true || double === "true";
    if (!(await ask(`${dbl ? "Double-klik" : "Klik"} ${button} di (${x},${y})`))) return "Dibatalkan user";
    await ps(
      PS_HEAD +
        `
[W]::SetCursorPos([int]$env:X, [int]$env:Y) | Out-Null
Start-Sleep -Milliseconds 150
$down = 2; $up = 4
if ($env:BTN -eq "right") { $down = 8; $up = 16 }
for ($i = 0; $i -lt [int]$env:COUNT; $i++) {
  [W]::mouse_event($down, 0, 0, 0, [UIntPtr]::Zero)
  [W]::mouse_event($up, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 80
}
`,
      { X: String(rx), Y: String(ry), BTN: String(button), COUNT: dbl ? "2" : "1" }
    );
    await sleep(800);
    return "ok, diklik";
  },

  scroll_screen: async ({ amount }) => {
    const delta = -120 * Math.round(Number(amount)); // positif = turun
    if (!(await ask(`Scroll ${amount > 0 ? "turun" : "naik"} ${Math.abs(amount)}x`))) return "Dibatalkan user";
    await ps(PS_HEAD + `[W]::mouse_event(0x0800, 0, 0, [int]$env:D, [UIntPtr]::Zero)`, { D: String(delta) });
    await sleep(500);
    return "ok";
  },

  type_desktop: async ({ text }) => {
    if (!(await ask(`Ketik: "${String(text).slice(0, 60)}"`))) return "Dibatalkan user";
    await ps(
      PS_HEAD +
        `
Set-Clipboard -Value $env:TXT
Start-Sleep -Milliseconds 150
[System.Windows.Forms.SendKeys]::SendWait("^v")
`,
      { TXT: String(text) }
    );
    await sleep(500);
    return "ok, diketik";
  },

  press_keys: async ({ keys }) => {
    if (!(await ask(`Tekan tombol: ${keys}`))) return "Dibatalkan user";
    await ps(PS_HEAD + `[System.Windows.Forms.SendKeys]::SendWait($env:KEYS)`, { KEYS: String(keys) });
    await sleep(500);
    return "ok";
  },

  wait: async ({ seconds }) => {
    await sleep(Math.min(Number(seconds) || 1, 15) * 1000);
    return "ok";
  },

  // --- Browser (Playwright) ---
  list_files: async () => fs.readdirSync(SAFE_DIR).join("\n") || "(folder upload kosong)",

  open_url: async ({ url, new_tab = false }) => {
    if (isTrue(new_tab)) page = await context.newPage();
    await page.bringToFront();
    await page.goto(fixUrl(url), { waitUntil: "domcontentloaded" });
    return "Terbuka: " + (await page.title()) + (isTrue(new_tab) ? " (di tab baru)" : "");
  },

  // --- Tab ---
  list_tabs: async () => tabsSummary(),

  new_tab: async ({ url }) => {
    page = await context.newPage();
    await page.bringToFront();
    if (url) await page.goto(fixUrl(url), { waitUntil: "domcontentloaded" });
    return "Tab baru dibuka dan jadi tab aktif.\n" + (await tabsSummary());
  },

  open_urls: async ({ urls }) => {
    const list = (Array.isArray(urls) ? urls : String(urls).split(/[\n,;|]+/))
      .map((x) => String(x).trim())
      .filter(Boolean)
      .slice(0, 10);
    if (!list.length) throw new Error("Tidak ada URL");
    const gagal = [];
    for (const u of list) {
      page = await context.newPage();
      try {
        await page.goto(fixUrl(u), { waitUntil: "domcontentloaded", timeout: 30000 });
      } catch (e) {
        gagal.push(u);
      }
    }
    return `${list.length - gagal.length} tab dibuka${gagal.length ? `, gagal: ${gagal.join(", ")}` : ""}.\n` + (await tabsSummary());
  },

  switch_tab: async ({ index, match }) => {
    const all = livePages();
    let target;
    if (match) {
      const q = String(match).toLowerCase();
      for (const x of all) {
        const t = ((await x.title().catch(() => "")) + " " + x.url()).toLowerCase();
        if (t.includes(q)) {
          target = x;
          break;
        }
      }
    } else {
      target = pickTab(all, index);
    }
    if (!target) throw new Error("Tab tidak ditemukan.\n" + (await tabsSummary()));
    page = target;
    await page.bringToFront();
    return "Tab aktif sekarang: " + (await page.title().catch(() => "")) + " | " + page.url();
  },

  close_tab: async ({ index }) => {
    const all = livePages();
    const target = index ? pickTab(all, index) : page;
    if (!target) throw new Error("Tab tidak ditemukan.\n" + (await tabsSummary()));
    if (all.length === 1) throw new Error("Ini tab terakhir, tidak ditutup agar browser tetap terbuka");
    const judul = await target.title().catch(() => "");
    if (!(await ask(`Tutup tab: ${judul}`))) return "Dibatalkan user";
    const wasActive = target === page;
    await target.close();
    if (wasActive) {
      page = livePages().at(-1);
      await page.bringToFront();
    }
    return "ok.\n" + (await tabsSummary());
  },

  inspect_page: async () => {
    const items = await page.evaluate(() =>
      [...document.querySelectorAll("input, button, a, textarea, select")]
        .slice(0, 60)
        .map((e) => ({
          tag: e.tagName.toLowerCase(),
          id: e.id || undefined,
          name: e.getAttribute("name") || undefined,
          type: e.getAttribute("type") || undefined,
          text: (e.innerText || e.value || e.placeholder || "").trim().slice(0, 40) || undefined,
        }))
    );
    return JSON.stringify(items);
  },

  youtube_play: async ({ query, pick = 1, new_tab = false }) => {
    if (isTrue(new_tab)) page = await context.newPage();
    await page.bringToFront();
    await page.goto("https://www.youtube.com/results?search_query=" + encodeURIComponent(String(query)), {
      waitUntil: "domcontentloaded",
    });
    await page.waitForSelector("ytd-video-renderer a#video-title", { timeout: 20000 });
    const list = await page.$$eval("ytd-video-renderer a#video-title", (els) =>
      els.slice(0, 5).map((e) => ({ title: e.textContent.trim(), href: e.href }))
    );
    if (!list.length) return "Tidak ada hasil";
    const start = Math.min(Math.max(Number(pick) || 1, 1), list.length) - 1;
    const order = [start, ...list.map((_, i) => i).filter((i) => i !== start)].slice(0, 3);
    const others = list.map((v, i) => `${i + 1}. ${v.title}`).join("\n");
    for (const idx of order) {
      await page.goto(list[idx].href, { waitUntil: "domcontentloaded" });
      if (await ensurePlaying()) {
        return `Memutar #${idx + 1}: ${list[idx].title}\nHasil pencarian:\n${others}`;
      }
    }
    return "Video gagal diputar (YouTube menampilkan error). Coba /login atau judul lain.\nHasil pencarian:\n" + others;
  },

  youtube_control: async ({ action, seconds = 10 }) => {
    await page.bringToFront();
    return page.evaluate(
      ({ a, s }) => {
        const v = document.querySelector("video");
        if (!v) return "Tidak ada video di halaman ini";
        if (a === "pause") v.pause();
        else if (a === "play") v.play();
        else if (a === "toggle") (v.paused ? v.play() : v.pause());
        else if (a === "mute") v.muted = true;
        else if (a === "unmute") v.muted = false;
        else if (a === "forward") v.currentTime += s;
        else if (a === "backward") v.currentTime -= s;
        else if (a === "next") {
          const b = document.querySelector(".ytp-next-button");
          if (!b) return "Tombol next tidak ada";
          b.click();
        } else if (a === "previous") {
          const b = document.querySelector(".ytp-prev-button");
          if (b && getComputedStyle(b).display !== "none") b.click();
          else history.back();
        } else if (a === "fullscreen") {
          const b = document.querySelector(".ytp-fullscreen-button");
          if (b) b.click();
        } else return "Aksi tidak dikenal. Pilih: play, pause, toggle, mute, unmute, forward, backward, next, previous, fullscreen";
        return "ok";
      },
      { a: String(action).toLowerCase(), s: Number(seconds) || 10 }
    );
  },

  // --- Web ---
  web_search: async ({ query, new_tab = false }) => {
    if (isTrue(new_tab)) page = await context.newPage();
    await page.bringToFront();
    await page.goto("https://html.duckduckgo.com/html/?q=" + encodeURIComponent(String(query)), {
      waitUntil: "domcontentloaded",
    });
    const rows = await page.$$eval(".result", (els) =>
      els.slice(0, 8).map((e) => ({
        title: e.querySelector(".result__a")?.textContent.trim(),
        url: e.querySelector(".result__a")?.href,
        snippet: e.querySelector(".result__snippet")?.textContent.trim(),
      }))
    );
    const real = (u) => {
      try {
        const x = new URL(u);
        return x.searchParams.get("uddg") || u;
      } catch {
        return u;
      }
    };
    const ok = rows.filter((r) => r.title);
    return ok.length ? ok.map((r, i) => `${i + 1}. ${r.title}\n   ${real(r.url)}\n   ${r.snippet || ""}`).join("\n") : "Tidak ada hasil";
  },

  scroll_page: async ({ amount }) => {
    await page.mouse.wheel(0, Math.round(Number(amount) || 1) * 700);
    await sleep(400);
    return "ok";
  },

  wait_for_user: async ({ message }) => {
    await page.bringToFront().catch(() => {});
    console.log(`\n[BUTUH BANTUAN KAMU] ${message}`);
    await rl.question("Tekan Enter jika sudah selesai... ");
    return "User sudah selesai";
  },

  download_file: async ({ url, filename }) => {
    if (!/^https?:\/\//i.test(String(url))) throw new Error("URL harus diawali http:// atau https://");
    const guess = decodeURIComponent(new URL(url).pathname.split("/").pop() || "") || "download.bin";
    const dest = path.join(HOME, "Downloads", path.basename(String(filename || guess)));
    if (!(await ask(`Unduh ${url}  ke  ${dest}`))) return "Dibatalkan user";
    const res = await fetch(url, { redirect: "follow", signal: AbortSignal.timeout(10 * 60 * 1000) });
    if (!res.ok) throw new Error("HTTP " + res.status);
    await pipeline(Readable.fromWeb(res.body), fs.createWriteStream(dest));
    return `ok, tersimpan: ${dest} (${fs.statSync(dest).size} byte)`;
  },

  // --- PC: info, media, clipboard, jendela ---
  now: async () => new Date().toLocaleString("id-ID", { dateStyle: "full", timeStyle: "long" }),

  system_info: async () =>
    ps(`
$os = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$bat = Get-CimInstance Win32_Battery | Select-Object -First 1
$l = @()
$l += "OS: " + $os.Caption
$l += "CPU: " + $cpu.Name + " (beban " + $cpu.LoadPercentage + "%)"
$l += "RAM: bebas " + [math]::Round($os.FreePhysicalMemory / 1MB, 1) + " GB dari " + [math]::Round($os.TotalVisibleMemorySize / 1MB, 1) + " GB"
if ($bat) { $l += "Baterai: " + $bat.EstimatedChargeRemaining + "%" } else { $l += "Baterai: tidak ada (PC desktop)" }
Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object { $l += "Disk " + $_.DeviceID + " bebas " + [math]::Round($_.FreeSpace / 1GB, 1) + " GB dari " + [math]::Round($_.Size / 1GB, 1) + " GB" }
$l -join [Environment]::NewLine
`),

  media_key: async ({ key, times = 1 }) => {
    const valid = ["volup", "voldown", "mute", "playpause", "next", "prev"];
    if (!valid.includes(String(key))) return "key harus salah satu dari: " + valid.join(", ");
    await ps(
      `
Add-Type @"
using System.Runtime.InteropServices;
public class K { [DllImport("user32.dll")] public static extern void keybd_event(byte b, byte s, uint f, int e); }
"@
$map = @{ volup = 0xAF; voldown = 0xAE; mute = 0xAD; playpause = 0xB3; next = 0xB0; prev = 0xB1 }
$k = [byte]$map[$env:KEY]
for ($i = 0; $i -lt [int]$env:N; $i++) { [K]::keybd_event($k, 0, 0, 0); [K]::keybd_event($k, 0, 2, 0); Start-Sleep -Milliseconds 60 }
`,
      { KEY: String(key), N: String(Math.min(Math.max(Number(times) || 1, 1), 50)) }
    );
    return "ok";
  },

  clipboard_get: async () => (await ps("Get-Clipboard -Raw")).slice(0, 4000) || "(kosong)",

  clipboard_set: async ({ text }) => {
    await ps("Set-Clipboard -Value $env:TXT", { TXT: String(text) });
    return "ok";
  },

  list_windows: async () =>
    (await ps(`Get-Process | Where-Object { $_.MainWindowTitle } | ForEach-Object { $_.ProcessName + " | " + $_.MainWindowTitle }`)) ||
    "(tidak ada jendela)",

  focus_window: async ({ title }) =>
    ps(`if ((New-Object -ComObject WScript.Shell).AppActivate($env:TITLE)) { "ok" } else { "jendela tidak ditemukan" }`, {
      TITLE: String(title),
    }),

  close_window: async ({ title }) => {
    if (!(await ask(`Tutup jendela: ${title}`))) return "Dibatalkan user";
    return ps(
      `$p = Get-Process | Where-Object { $_.MainWindowTitle -like ("*" + $env:TITLE + "*") } | Select-Object -First 1
if ($p) { $p.CloseMainWindow() | Out-Null; "ok: " + $p.MainWindowTitle } else { "jendela tidak ditemukan" }`,
      { TITLE: String(title) }
    );
  },

  // --- File ---
  read_text_file: async ({ path: p }) => {
    const full = path.resolve(String(p));
    const st = fs.statSync(full);
    if (!st.isFile()) throw new Error("Bukan file: " + full);
    if (st.size > 2_000_000) throw new Error("File terlalu besar untuk dibaca (" + st.size + " byte)");
    return fs.readFileSync(full, "utf8").slice(0, 8000);
  },

  write_text_file: async ({ path: p, content, append = false }) => {
    const full = path.resolve(String(p));
    const add = append === true || append === "true";
    const verb = add ? "Tambah ke" : fs.existsSync(full) ? "TIMPA" : "Buat";
    if (!(await ask(`${verb} file: ${full}`))) return "Dibatalkan user";
    fs.mkdirSync(path.dirname(full), { recursive: true });
    if (add) fs.appendFileSync(full, String(content));
    else fs.writeFileSync(full, String(content));
    return "ok: " + full;
  },

  make_folder: async ({ path: p }) => {
    const full = path.resolve(String(p));
    if (!(await ask(`Buat folder: ${full}`))) return "Dibatalkan user";
    fs.mkdirSync(full, { recursive: true });
    return "ok: " + full;
  },

  move_path: async ({ from, to }) => {
    if (!(await ask(`Pindahkan: ${from}  ke  ${to}`))) return "Dibatalkan user";
    await ps("Move-Item -LiteralPath $env:SRC -Destination $env:DEST", {
      SRC: path.resolve(String(from)),
      DEST: path.resolve(String(to)),
    });
    return "ok";
  },

  recycle_path: async ({ path: p }) => {
    const full = path.resolve(String(p));
    if (!(await ask(`Pindahkan ke Recycle Bin: ${full}`))) return "Dibatalkan user";
    await ps(
      `Add-Type -AssemblyName Microsoft.VisualBasic
$p = $env:TARGET
if (Test-Path -LiteralPath $p -PathType Container) { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($p, 'OnlyErrorDialogs', 'SendToRecycleBin') }
else { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p, 'OnlyErrorDialogs', 'SendToRecycleBin') }`,
      { TARGET: full }
    );
    return "ok, dipindah ke Recycle Bin (masih bisa dipulihkan)";
  },

  zip_path: async ({ source, zip }) => {
    const src = path.resolve(String(source));
    const dest = path.resolve(String(zip));
    if (!(await ask(`Zip ${src}  menjadi  ${dest}`))) return "Dibatalkan user";
    await ps("Compress-Archive -LiteralPath $env:SRC -DestinationPath $env:DEST -Force", { SRC: src, DEST: dest }, 600000);
    return "ok: " + dest;
  },

  unzip_path: async ({ zip, folder }) => {
    const src = path.resolve(String(zip));
    const dest = path.resolve(String(folder));
    if (!(await ask(`Ekstrak ${src}  ke  ${dest}`))) return "Dibatalkan user";
    await ps("Expand-Archive -LiteralPath $env:SRC -DestinationPath $env:DEST -Force", { SRC: src, DEST: dest }, 600000);
    return "ok: " + dest;
  },

  more_tools: async ({ group }) => {
    const g = String(group).toLowerCase();
    if (!TOOL_GROUPS[g]) return "Grup tidak dikenal. Pilih: " + Object.keys(TOOL_GROUPS).join(", ");
    extraGroups.add(g);
    return `Alat grup ${g} sekarang tersedia: ${TOOL_GROUPS[g].join(", ")}`;
  },

  get_page_text: async () => (await page.innerText("body")).slice(0, 4000),

  type_text: async ({ selector, text }) => {
    await page.fill(selector, text);
    return "ok";
  },

  click: async ({ selector }) => {
    if (!(await ask(`Klik elemen browser: ${selector}`))) return "Dibatalkan user";
    await page.click(selector, { timeout: 10000 });
    return "ok";
  },

  upload_file: async ({ selector, filename, folder, pattern }) => {
    let files = [];
    if (filename) {
      files = String(filename)
        .split("|")
        .map((x) => x.trim())
        .filter(Boolean)
        .map(safePath);
    }
    if (folder) {
      const dir = path.resolve(String(folder));
      const q = pattern ? String(pattern).toLowerCase().replace(/^\*/, "") : "";
      for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        if (e.isFile() && (!q || e.name.toLowerCase().includes(q))) files.push(path.join(dir, e.name));
      }
    }
    if (!files.length) throw new Error("Tidak ada file yang cocok untuk diupload");
    files = files.slice(0, 50);
    if (!(await ask(`Upload ${files.length} file:\n   ${files.join("\n   ")}\n  `))) return "Dibatalkan user";
    const multiple = await page.$eval(selector, (el) => !!el.multiple).catch(() => false);
    if (files.length > 1 && !multiple) {
      await page.setInputFiles(selector, files[0]);
      return (
        `Input ini hanya menerima 1 file. Terpilih: ${files[0]}. Sisa ${files.length - 1} file: ` +
        `${files.slice(1).join(" | ")}. Selesaikan upload ini, lalu ulangi upload_file untuk sisanya.`
      );
    }
    await page.setInputFiles(selector, files);
    return `ok, ${files.length} file dipilih`;
  },
};

const fn = (name, description, properties = {}, optional = []) => ({
  type: "function",
  function: {
    name,
    description,
    parameters: {
      type: "object",
      properties,
      required: Object.keys(properties).filter((k) => !optional.includes(k)),
    },
  },
});
const str = (d) => ({ type: "string", description: d });
const num = (d) => ({ type: "number", description: d });
const bool = (d) => ({ type: "boolean", description: d });

const tools = [
  fn("find_folder", "Cari folder di seluruh PC (semua drive) berdasarkan nama; sebagian nama cukup", { name: str("Nama folder") }),
  fn("find_file", "Cari file di seluruh PC (semua drive) berdasarkan nama; sebagian nama cukup", { name: str("Nama file") }),
  fn("list_dir", "Lihat isi sebuah folder di PC", { path: str("Path lengkap folder") }),
  fn("open_path", "Buka folder, file, aplikasi (mis. notepad), atau URL di PC", { target: str("Path/nama aplikasi/URL") }),
  fn("screenshot", "Ambil screenshot layar PC untuk melihat kondisi sekarang"),
  fn(
    "click_screen",
    "Klik di layar PC pada koordinat dari screenshot terakhir",
    { x: num("Koordinat X di screenshot"), y: num("Koordinat Y di screenshot"), button: str("left atau right"), double: { type: "boolean", description: "double-klik" } },
    ["button", "double"]
  ),
  fn("scroll_screen", "Scroll layar. Positif = turun, negatif = naik", { amount: num("Jumlah scroll") }),
  fn("type_desktop", "Ketik teks di aplikasi yang sedang fokus di PC", { text: str("Teks") }),
  fn("press_keys", "Tekan tombol format SendKeys: {ENTER}, {TAB}, {ESC}, ^c (Ctrl+C), ^v, ^l, %{F4}", { keys: str("Kombinasi tombol") }),
  fn("wait", "Tunggu beberapa detik (maks 15) supaya halaman/aplikasi selesai dimuat", { seconds: num("Detik") }),
  fn("list_files", "Lihat daftar file di folder upload khusus"),
  fn(
    "open_url",
    "Buka website di browser. Secara bawaan menimpa tab aktif; pakai new_tab=true agar halaman/video yang sedang terbuka tidak tertimpa",
    { url: str("URL lengkap"), new_tab: bool("true = buka di tab baru") },
    ["new_tab"]
  ),
  fn("list_tabs", "Daftar semua tab browser (tanda * = tab aktif)"),
  fn("new_tab", "Buka tab baru (kosong, atau langsung ke URL) dan jadikan tab aktif", { url: str("URL (opsional)") }, ["url"]),
  fn("open_urls", "Buka BANYAK website sekaligus, masing-masing di tab baru", {
    urls: { type: "array", items: { type: "string" }, description: "Daftar URL (maksimal 10)" },
  }),
  fn(
    "switch_tab",
    "Pindah tab aktif. Pakai index (1 = tab pertama, -1 = tab terbaru) ATAU match (sebagian judul/URL)",
    { index: num("Nomor tab, -1 = terbaru"), match: str("Sebagian judul atau URL tab") },
    ["index", "match"]
  ),
  fn("close_tab", "Tutup tab (bawaan: tab aktif), atau tab dengan nomor tertentu", { index: num("Nomor tab, -1 = terbaru") }, ["index"]),
  fn("inspect_page", "Daftar tombol/input di halaman browser untuk mencari CSS selector"),
  fn(
    "youtube_play",
    "Cari video di YouTube lalu OTOMATIS memutar hasil pilihan di browser agent. Pakai ini untuk semua permintaan nonton/cari video/lagu di YouTube.",
    {
      query: str("Kata kunci pencarian"),
      pick: num("Urutan hasil yang diputar, 1-5 (default 1)"),
      new_tab: bool("true = putar di tab baru supaya tab aktif tidak tertimpa"),
    },
    ["pick", "new_tab"]
  ),
  fn("done", "Panggil ini jika tugas SELESAI, atau jika perlu bertanya/melapor ke user", { message: str("Pesan singkat untuk user") }),
  fn(
    "youtube_control",
    "Kontrol video YouTube yang sedang terbuka",
    { action: str("play, pause, toggle, mute, unmute, forward, backward, next, previous, fullscreen"), seconds: num("Detik untuk forward/backward (default 10)") },
    ["seconds"]
  ),
  fn("web_search", "Cari informasi di internet, mengembalikan judul, link, dan cuplikan hasil", {
    query: str("Kata kunci"),
    new_tab: bool("true = cari di tab baru supaya tab aktif tidak tertimpa"),
  }, ["new_tab"]),
  fn("scroll_page", "Scroll halaman browser. Positif = turun, negatif = naik", { amount: num("Jumlah scroll") }),
  fn("wait_for_user", "Berhenti dan minta user melakukan sesuatu sendiri (login, captcha, verifikasi), lalu tunggu Enter", { message: str("Instruksi untuk user") }),
  fn("download_file", "Unduh file dari internet ke folder Downloads", { url: str("URL http(s)"), filename: str("Nama file (opsional)") }, ["filename"]),
  fn("now", "Tanggal dan jam sekarang"),
  fn("system_info", "Info PC: OS, CPU, RAM, baterai, ruang disk"),
  fn(
    "media_key",
    "Tombol media dan volume global Windows",
    { key: str("volup, voldown, mute, playpause, next, prev"), times: num("Jumlah tekan (volume berubah 2% per tekan)") },
    ["times"]
  ),
  fn("clipboard_get", "Baca isi clipboard"),
  fn("clipboard_set", "Isi clipboard", { text: str("Teks") }),
  fn("list_windows", "Daftar jendela atau aplikasi yang sedang terbuka"),
  fn("focus_window", "Pindahkan fokus ke sebuah jendela", { title: str("Sebagian judul jendela") }),
  fn("close_window", "Tutup sebuah jendela dengan baik-baik", { title: str("Sebagian judul jendela") }),
  fn("read_text_file", "Baca isi file teks", { path: str("Path lengkap file") }),
  fn("write_text_file", "Tulis atau tambah isi file teks", { path: str("Path lengkap file"), content: str("Isi"), append: { type: "boolean", description: "true = tambahkan, bukan menimpa" } }, ["append"]),
  fn("make_folder", "Buat folder baru", { path: str("Path lengkap folder") }),
  fn("move_path", "Pindahkan atau ganti nama file/folder", { from: str("Path asal"), to: str("Path tujuan") }),
  fn("recycle_path", "Hapus file/folder dengan memindahkannya ke Recycle Bin", { path: str("Path lengkap") }),
  fn("zip_path", "Kompres file atau folder menjadi .zip", { source: str("Path file/folder"), zip: str("Path file .zip hasil") }),
  fn("unzip_path", "Ekstrak file .zip", { zip: str("Path file .zip"), folder: str("Folder tujuan") }),
  fn("more_tools", "Aktifkan kelompok alat tambahan jika alat yang kamu butuhkan belum tersedia", {
    group: str("youtube, tabs, desktop, files, atau pc"),
  }),
  fn("get_page_text", "Baca teks halaman browser saat ini"),
  fn("type_text", "Isi kolom teks di browser", { selector: str("CSS selector"), text: str("Teks") }),
  fn("click", "Klik elemen di browser", { selector: str("CSS selector") }),
  fn(
    "upload_file",
    "Upload SATU atau BANYAK file ke input file di browser. Beberapa file di filename dipisah tanda |. Atau pakai folder (+ pattern) untuk mengunggah semua file di folder itu",
    {
      selector: str("CSS selector input[type=file]"),
      filename: str("Path lengkap file (boleh banyak, dipisah |), atau nama file di upload-folder"),
      folder: str("Folder berisi file yang mau diupload semuanya (opsional)"),
      pattern: str("Filter nama file di folder, misalnya .pdf (opsional)"),
    },
    ["filename", "folder", "pattern"]
  ),
];

const SYSTEM = `Kamu agent yang mengontrol PC Windows milik user dan browser. Kerjakan perintah user dengan memanggil tool.
ATURAN PENTING:
- Kamu HARUS selalu memanggil tool di setiap langkah. JANGAN pernah menulis rencana, narasi, atau "saya akan ...". Langsung panggil tool-nya.
- Setelah tugas selesai (atau perlu bertanya ke user), panggil tool done dengan pesan singkat.
- Nonton/cari video/lagu di YouTube: langsung panggil youtube_play dengan kata kunci dari user. Jika judul yang diputar kurang cocok, panggil lagi dengan pick lain.
- Tafsirkan perintah singkat/typo user dengan wajar, jangan bertanya hal yang bisa ditebak.
- Kamu mengingat percakapan sebelumnya. Jawaban singkat user (misalnya sebuah nama file) adalah jawaban atas pertanyaanmu sebelumnya; lanjutkan tugas itu, jangan mulai dari nol.
- Membuka aplikasi Windows lewat open_path: kamera = microsoft.windows.camera: , kalkulator = calc , notepad = notepad , paint = mspaint , pengaturan = ms-settings: , file explorer = explorer .
- Upload file ke website: open_url ke halaman upload, inspect_page untuk mencari input type=file, lalu upload_file dengan path lengkap file. Jika butuh login, panggil done dan minta user login manual di jendela browser, lalu ulangi.
- Folder di PC: find_folder lalu open_path. File di PC: find_file (atau list_dir) untuk mendapat path lengkap, lalu open_path atau upload_file. Tidak ada batasan lokasi, semua drive boleh diakses.
- Aplikasi/jendela di PC: screenshot dulu untuk melihat layar, lalu click_screen/type_desktop/press_keys, lalu screenshot lagi untuk memeriksa hasil.
- Koordinat klik harus dari screenshot terakhir.
- Untuk otomasi website pakai tool browser (open_url, inspect_page, type_text, click, upload_file). Selalu inspect_page sebelum klik.
- Butuh login, captcha, atau verifikasi: panggil wait_for_user dan minta user mengerjakannya sendiri di jendela browser. JANGAN pernah meminta atau mengetikkan password user.
- Pertanyaan yang butuh info terbaru: web_search, lalu open_url dan get_page_text untuk membaca sumbernya.
- Kontrol musik/video: youtube_control untuk video YouTube, media_key untuk volume dan tombol media seluruh PC.
- TAB: Jangan menimpa halaman yang masih dipakai. Jika user menyebut "tab baru", atau ada video/halaman lain yang sedang terbuka (misalnya musik), pakai new_tab=true pada open_url, web_search, atau youtube_play. Beberapa situs sekaligus: open_urls. Pindah tab: list_tabs lalu switch_tab (index -1 = tab terbaru, atau match judul). Tutup: close_tab.
- Upload banyak file: upload_file dengan beberapa path dipisah |, atau folder (dan pattern). Jika input hanya menerima satu file, ulangi per file sampai semua selesai.
- Menghapus file: pakai recycle_path (masuk Recycle Bin), jangan menghapus permanen.
- Jika alat yang kamu butuhkan tidak ada di daftar, panggil more_tools dengan grup: youtube, tabs, desktop, files, atau pc.
- Jika buntu atau ragu, berhenti dan tanya user.
- Jawab dalam Bahasa Indonesia, singkat. Jangan mengarang hasil; laporkan apa adanya.`;

// ===== Komunikasi dengan 9Router (tahan banting) =====
// Jika balasan kosong/gagal, agent otomatis: (1) coba tanpa tool_choice, (2) kecilkan daftar alat dan
// pakai balasan non-streaming, (3) pindah ke model lain yang ditemukan lewat /models.
// Model yang berhasil diingat selama sesi. Perintah /tes dan /model membantu memilih model paling stabil.
const MODEL_FILE = "model.txt";
let baseModel = MODEL;
try {
  const saved = fs.readFileSync(MODEL_FILE, "utf8").trim();
  if (saved) baseModel = saved;
} catch {}

let useToolChoice = true; // paksa model selalu memanggil tool; dimatikan otomatis jika bermasalah
let slimMode = false; // true = kirim hanya alat yang relevan (muatan lebih kecil)
let fallbackModels = null; // diisi saat pertama kali dibutuhkan
let poolIdx = 0;
const extraGroups = new Set();
const BACKOFF = Number(process.env.BACKOFF_MS || 1000);

const TOOL_GROUPS = {
  youtube: ["youtube_play", "youtube_control"],
  tabs: ["new_tab", "open_urls", "list_tabs", "switch_tab", "close_tab", "scroll_page", "web_search"],
  desktop: ["click_screen", "scroll_screen", "type_desktop", "press_keys", "wait", "list_windows", "focus_window", "close_window"],
  files: ["read_text_file", "write_text_file", "make_folder", "move_path", "recycle_path", "zip_path", "unzip_path", "download_file"],
  pc: ["media_key", "clipboard_get", "clipboard_set", "system_info"],
};
const CORE_TOOLS = [
  "done", "wait_for_user", "more_tools", "now", "open_url", "get_page_text", "inspect_page", "type_text", "click",
  "upload_file", "list_files", "find_folder", "find_file", "list_dir", "open_path", "screenshot",
];
const GROUP_KEYWORDS = {
  youtube: /youtube|video|lagu|musik|music|putar|nonton|dengar|pause|next/i,
  tabs: /\btab\b|cari|search|google|web|internet|situs|website|sekaligus/i,
  desktop: /klik|layar|mouse|ketik|jendela|window|aplikasi|screenshot|scroll|tombol/i,
  files: /file|folder|zip|hapus|pindah|tulis|baca|unduh|download|buat|ganti nama/i,
  pc: /volume|suara|clipboard|salin|\bram\b|cpu|baterai|sistem|media|mute/i,
};

// Pilih alat yang relevan saja (dipakai saat muatan perlu dikecilkan)
function selectTools(messages) {
  const names = new Set(CORE_TOOLS);
  const userText = messages
    .filter((m) => m.role === "user" && typeof m.content === "string" && !m.content.startsWith("Kamu harus memanggil tool"))
    .slice(-4)
    .map((m) => m.content)
    .join(" ");
  for (const [g, re] of Object.entries(GROUP_KEYWORDS)) {
    if (re.test(userText) || extraGroups.has(g)) TOOL_GROUPS[g].forEach((n) => names.add(n));
  }
  for (const m of messages) for (const c of m.tool_calls || []) names.add(c.function.name); // alat yang sudah dipakai tetap ada
  return tools.filter((t) => names.has(t.function.name));
}

const modelPool = () => [baseModel, ...(fallbackModels || []).filter((m) => m !== baseModel)];

async function discoverModels() {
  if (process.env.ROUTER_FALLBACK_MODELS) {
    return process.env.ROUTER_FALLBACK_MODELS.split(",").map((x) => x.trim()).filter(Boolean);
  }
  try {
    const res = await fetch(`${BASE_URL}/models`, {
      headers: { Authorization: `Bearer ${API_KEY}` },
      signal: AbortSignal.timeout(10000),
    });
    if (!res.ok) return [];
    const data = (await res.json()).data || [];
    const bad = /embed|whisper|tts|image|audio|rerank|moderat|dall|flux|sdxl|video|speech|transcri/i;
    const score = (id) =>
      (/claude/i.test(id) ? 3 : 0) + (/gemini/i.test(id) ? 3 : 0) + (/gpt|glm|qwen|kimi|deepseek/i.test(id) ? 2 : 0) +
      (/haiku|flash|sonnet/i.test(id) ? 1 : 0) - (/thinking|agentic/i.test(id) ? 2 : 0);
    return data
      .map((m) => m.id)
      .filter((id) => id && id !== baseModel && !bad.test(id))
      .sort((x, y) => score(y) - score(x))
      .slice(0, 8);
  } catch {
    return [];
  }
}

function fatal(msg) {
  const e = new Error(msg);
  e.fatal = true;
  return e;
}

// Baca balasan 9Router (JSON biasa atau streaming SSE) menjadi satu pesan
function parseChat(raw) {
  if (!raw.trim()) return { msg: null, err: "kosong" };
  if (!/(^|\n)data:/.test(raw)) {
    let obj;
    try {
      obj = JSON.parse(raw);
    } catch {
      return { msg: null, err: "bukan JSON" };
    }
    if (obj.error) return { msg: null, err: JSON.stringify(obj.error).slice(0, 150) };
    const m = obj.choices?.[0]?.message;
    if (!m || (!m.content && !m.tool_calls?.length)) return { msg: null, err: "tanpa isi" };
    return { msg: m, err: "" };
  }
  let content = "";
  let sseErr = "";
  const calls = [];
  for (const line of raw.split("\n")) {
    if (!line.startsWith("data:")) continue;
    const data = line.slice(5).trim();
    if (!data || data === "[DONE]") continue;
    let chunk;
    try {
      chunk = JSON.parse(data);
    } catch {
      continue;
    }
    if (chunk.error) sseErr = JSON.stringify(chunk.error).slice(0, 150);
    const choice = chunk.choices?.[0];
    const delta = choice?.delta || choice?.message || {};
    if (delta.content) content += delta.content;
    for (const tc of delta.tool_calls || []) {
      const i = tc.index ?? 0;
      calls[i] ??= { id: "", type: "function", function: { name: "", arguments: "" } };
      if (tc.id) calls[i].id = tc.id;
      if (tc.function?.name) calls[i].function.name += tc.function.name;
      if (tc.function?.arguments) calls[i].function.arguments += tc.function.arguments;
    }
  }
  const valid = calls.filter(Boolean).map((c, i) => ({ ...c, id: c.id || `call_${i}` }));
  if (!content && !valid.length) return { msg: null, err: sseErr || "tanpa isi" };
  const msg = { role: "assistant", content: content || null };
  if (valid.length) msg.tool_calls = valid;
  return { msg, err: "" };
}

async function requestOnce(messages, { model, toolChoice, stream, slim }) {
  const toolList = slim ? selectTools(messages) : tools.filter((t) => t.function.name !== "more_tools");
  const body = { model, messages, tools: toolList, stream };
  if (toolChoice) body.tool_choice = "required";
  const res = await fetch(`${BASE_URL}/chat/completions`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${API_KEY}` },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(120000),
  });
  if (!res.ok) {
    const errText = (await res.text()).replace(/\s+/g, " ").slice(0, 200);
    if (res.status === 401 || res.status === 403) throw fatal(`API key ditolak (${res.status}). Jalankan: start-agent.bat reset`);
    const e = new Error(`HTTP ${res.status} ${errText}`);
    if (res.status === 429) e.wait = Math.min(Number(res.headers.get("retry-after")) || 5, 15) * 1000;
    throw e;
  }
  const raw = await res.text();
  const { msg, err } = parseChat(raw);
  if (!msg) {
    const peek = `[HTTP ${res.status}, ${raw.length} byte${raw.trim() ? ": " + raw.replace(/\s+/g, " ").slice(0, 100) : ""}]`;
    throw new Error(`respons ${err} ${peek}`);
  }
  return msg;
}

async function callLLM(messages) {
  const ATTEMPTS = 7;
  let lastErr = "";
  for (let attempt = 1; attempt <= ATTEMPTS; attempt++) {
    if (attempt >= 3) slimMode = true; // kecilkan muatan alat
    if (attempt >= 4) {
      // Pindah ke model lain
      if (!fallbackModels) fallbackModels = await discoverModels();
      const pool = modelPool();
      if (pool.length > 1) {
        poolIdx = (poolIdx + 1) % pool.length;
        console.log(`  (mencoba model lain: ${pool[poolIdx]})`);
      }
    }
    const pool = modelPool();
    const model = pool[poolIdx % pool.length];
    try {
      const msg = await requestOnce(messages, {
        model,
        toolChoice: attempt === 1 && useToolChoice,
        stream: attempt < 3 || attempt % 2 === 0,
        slim: slimMode,
      });
      const clean = { role: "assistant", content: msg.content ?? null };
      if (msg.tool_calls?.length) clean.tool_calls = msg.tool_calls;
      return clean;
    } catch (e) {
      if (e.fatal) throw e;
      lastErr = e.message;
      if (attempt === 1) useToolChoice = false;
    }
    if (attempt < ATTEMPTS) {
      console.log(`  (9Router bermasalah: ${lastErr.slice(0, 140)}. Mencoba ulang ${attempt}/${ATTEMPTS - 1}...)`);
      await sleep(Math.min(BACKOFF * attempt, 4000));
    }
  }
  throw new Error(
    `9Router gagal merespons setelah ${ATTEMPTS} percobaan (${lastErr.slice(0, 160)}). ` +
      `Ketik /tes untuk menguji model dan memilih yang stabil. Cek juga dashboard 9Router, menu Console Log.`
  );
}

// Uji satu model dengan permintaan kecil yang meminta pemanggilan tool
async function testModel(model) {
  const t0 = Date.now();
  const pingTool = [
    {
      type: "function",
      function: {
        name: "ping",
        description: "Tes koneksi",
        parameters: { type: "object", properties: { pesan: { type: "string" } }, required: ["pesan"] },
      },
    },
  ];
  try {
    const res = await fetch(`${BASE_URL}/chat/completions`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${API_KEY}` },
      body: JSON.stringify({
        model,
        messages: [{ role: "user", content: "Panggil tool ping dengan pesan ok." }],
        tools: pingTool,
        stream: false,
      }),
      signal: AbortSignal.timeout(45000),
    });
    const raw = await res.text();
    const ms = Date.now() - t0;
    if (!res.ok) return { mark: "[X] ", ms, text: `HTTP ${res.status} ${raw.replace(/\s+/g, " ").slice(0, 70)}` };
    const { msg, err } = parseChat(raw);
    if (!msg) return { mark: "[X] ", ms, text: `respons ${err}` };
    if (msg.tool_calls?.length) return { mark: "[OK]", ms, text: "tool calling berfungsi" };
    return { mark: "[~] ", ms, text: "menjawab tapi tidak memanggil tool (kurang cocok untuk agent)" };
  } catch (e) {
    return { mark: "[X] ", ms: Date.now() - t0, text: e.name === "TimeoutError" ? "timeout" : e.message.slice(0, 70) };
  }
}

// ===== Memori percakapan =====
const history = [];
const MAX_HISTORY = 30;

function stripImages() {
  for (const m of history) {
    if (m.role === "user" && Array.isArray(m.content)) {
      m.content = "[screenshot lama dihapus untuk menghemat memori]";
    }
  }
}

function trimHistory() {
  while (history.length > MAX_HISTORY) {
    let i = 1;
    while (i < history.length && !(history[i].role === "user" && typeof history[i].content === "string")) i++;
    if (i >= history.length) break;
    history.splice(0, i);
  }
}

async function runTask(command) {
  const startLen = history.length;
  history.push({ role: "user", content: command });
  let nudges = 0;

  try {
    for (let step = 1; step <= MAX_STEPS; step++) {
      const msg = await callLLM([{ role: "system", content: SYSTEM }, ...history]);
      history.push(msg);

      if (!msg.tool_calls?.length) {
        // Model cuma menulis teks/rencana tanpa memanggil tool -> paksa panggil tool
        if (nudges < 3) {
          nudges++;
          history.push({
            role: "user",
            content: "Kamu harus memanggil tool. Jangan menulis teks biasa. Langsung panggil tool yang sesuai, atau panggil done jika tugas sudah selesai.",
          });
          continue;
        }
        console.log("\nAgent:", msg.content || "(tidak ada jawaban)");
        return;
      }

      // Tugas selesai: semua tool_call wajib dijawab agar riwayat tetap valid
      const doneCall = msg.tool_calls.find((c) => c.function.name === "done");
      if (doneCall) {
        let m = "";
        try {
          m = JSON.parse(doneCall.function.arguments || "{}").message || "";
        } catch {}
        for (const call of msg.tool_calls) {
          history.push({ role: "tool", tool_call_id: call.id, content: call === doneCall ? "ok" : "dilewati" });
        }
        console.log("\nAgent:", m || "Selesai.");
        return;
      }

      for (const call of msg.tool_calls) {
        const name = call.function.name;
        let result;
        try {
          const args = JSON.parse(call.function.arguments || "{}");
          console.log(`[${step}] ${name}`, args);
          if (!impl[name]) throw new Error("Tool tidak dikenal: " + name);
          await ensurePage();
          result = await impl[name](args);
        } catch (e) {
          result = "ERROR: " + e.message;
        }
        history.push({ role: "tool", tool_call_id: call.id, content: String(result).slice(0, 4000) });
      }

      // Kirim screenshot (jika ada) sebagai gambar; gambar lama dibuang agar ringan
      if (pendingImages.length) {
        stripImages();
        history.push({
          role: "user",
          content: [
            { type: "text", text: "Ini screenshot layar terbaru:" },
            ...pendingImages.splice(0).map((b64) => ({
              type: "image_url",
              image_url: { url: `data:image/png;base64,${b64}` },
            })),
          ],
        });
      }
      await sleep(300);
    }
    console.log("Berhenti: melewati batas langkah.");
  } catch (e) {
    history.length = startLen; // buang riwayat tugas yang gagal supaya tidak merusak percakapan berikutnya
    throw e;
  } finally {
    stripImages();
    trimHistory();
  }
}

const BUILTIN_CHANGELOG = `Versi 6
- Koneksi ke 9Router jauh lebih tahan banting: otomatis kecilkan muatan dan pindah ke model lain jika balasan kosong.
- Perintah /tes menguji semua model dan memilih yang paling stabil untuk agent. /model untuk melihat atau mengganti model.
- Pesan error sekarang menampilkan penyebab sebenarnya (status dan isi balasan).
- Versi 5: banyak tab dan upload banyak file. Versi 4: Chrome/Edge asli, login, YouTube, alat PC dan file.
Ketik /bantuan untuk daftar lengkap.`;

const HELP = `
FITUR AGENT
  Browser  : buka website, isi form, klik, cari di web, scroll
  Tab      : buka tab baru, banyak situs sekaligus, pindah dan tutup tab (video tidak tertimpa)
  YouTube  : cari + putar otomatis (skip iklan), kontrol pause/next/maju/mundur/mute/fullscreen
  Login    : /login lalu login manual sekali, sesi tersimpan. Agent tidak pernah mengetik passwordmu
  Upload   : satu file, banyak file sekaligus, atau satu folder penuh, dari lokasi mana pun
  Layar    : screenshot, klik, scroll, ketik, tekan tombol
  Jendela  : daftar, pindah fokus, tutup
  File     : cari file/folder di semua drive, baca/tulis teks, buat folder, pindah,
             hapus ke Recycle Bin, zip/unzip, unduh dari internet
  PC       : volume dan tombol media, clipboard, info sistem, tanggal dan jam
PERINTAH KHUSUS
  /login [alamat]  login manual di browser      /baru     daftar fitur terbaru
  /tes             uji semua model, pilih yang stabil   /model [nama]  lihat atau ganti model
  /update          perbarui sekarang            /versi    cek versi
  /reset           lupakan percakapan           /bantuan  tampilkan ini        exit  keluar
CONTOH
  buka tab baru lalu cari cara membahagiakan orang tua  |  buka youtube, gmail, dan github sekaligus
  upload semua pdf di folder Laporan ke mediafire  |  pindah ke tab youtube lalu pause
`;

function showWhatsNew(force = false) {
  const ver = localVersion();
  let seen = "";
  try {
    seen = fs.readFileSync(".whatsnew-seen", "utf8").trim();
  } catch {}
  if (!force && seen === ver) return;
  let text = "";
  try {
    text = fs.readFileSync("changelog.txt", "utf8").trim();
  } catch {}
  if (!text) text = BUILTIN_CHANGELOG;
  console.log("\n================== YANG BARU ==================");
  console.log(text.split(/\r?\n/).slice(0, 30).join("\n"));
  console.log("===============================================");
  try {
    fs.writeFileSync(".whatsnew-seen", ver);
  } catch {}
}

console.log(`Agent siap. Versi ${localVersion()}. Folder upload: ${SAFE_DIR}`);
console.log(`Izin sebelum aksi: ${CONFIRM ? "AKTIF" : "MATI"}. Tekan Ctrl+C kapan saja untuk menghentikan.`);
showWhatsNew();
console.log('Ketik perintah dalam bahasa biasa. Ketik /bantuan untuk daftar fitur, /login untuk login, exit untuk keluar.');
checkUpdate();
while (true) {
  const cmd = await rl.question("\nPerintah> ");
  const c = cmd.trim();
  if (c === "exit") break;
  if (!c) continue;
  if (c === "/tes") {
    if (!fallbackModels) fallbackModels = await discoverModels();
    const list = modelPool().slice(0, 9);
    console.log(`Menguji ${list.length} model, tiap model maksimal 45 detik...`);
    let best = "";
    for (const m of list) {
      const r = await testModel(m);
      console.log(`  ${r.mark} ${m}   ${r.ms} ms   ${r.text}`);
      if (!best && r.mark === "[OK]") best = m;
    }
    if (!best) {
      console.log("\nTidak ada model yang lolos. Cek dashboard 9Router: provider terhubung, kuota, dan menu Console Log.");
    } else if (best === baseModel) {
      console.log(`\nModel aktif (${baseModel}) sudah berfungsi baik.`);
    } else {
      baseModel = best;
      poolIdx = 0;
      try {
        fs.writeFileSync(MODEL_FILE, best);
      } catch {}
      console.log(`\nModel terbaik dipilih otomatis: ${best} (tersimpan, ketik /model reset untuk kembali ke bawaan).`);
    }
    continue;
  }
  if (c === "/model" || c.startsWith("/model ")) {
    const arg = c.slice(6).trim();
    if (!arg) {
      if (!fallbackModels) fallbackModels = await discoverModels();
      console.log(`Model aktif: ${baseModel}\nModel lain yang tersedia: ${modelPool().slice(1).join(", ") || "(tidak ada)"}`);
    } else if (arg === "reset") {
      try {
        fs.unlinkSync(MODEL_FILE);
      } catch {}
      baseModel = MODEL;
      poolIdx = 0;
      console.log(`Kembali ke model bawaan: ${MODEL}`);
    } else {
      baseModel = arg;
      poolIdx = 0;
      try {
        fs.writeFileSync(MODEL_FILE, arg);
      } catch {}
      console.log(`Model diganti ke: ${arg}`);
    }
    continue;
  }
  if (c === "/bantuan") {
    console.log(HELP);
    continue;
  }
  if (c === "/baru") {
    showWhatsNew(true);
    continue;
  }
  if (c.startsWith("/login")) {
    let target = c.split(/\s+/)[1] || "https://accounts.google.com/ServiceLogin?service=youtube&continue=https://www.youtube.com/";
    if (!/^https?:\/\//i.test(target)) target = "https://" + target;
    try {
      await ensurePage();
      await page.bringToFront();
      await page.goto(target, { waitUntil: "domcontentloaded" });
    } catch (e) {
      console.log("Gagal membuka halaman login:", e.message);
    }
    console.log("Silakan login di jendela browser (kamu yang mengetik, agent tidak melihat password).");
    await rl.question("Setelah selesai, tekan Enter di sini... ");
    console.log("Login tersimpan di profil browser. Berikutnya tidak perlu login lagi.");
    continue;
  }
  if (c === "/versi") {
    console.log(`Versi agent: ${localVersion()}`);
    await checkUpdate();
    if (!pendingVersion) console.log("Sudah versi terbaru (atau update online tidak aktif).");
    continue;
  }
  if (c === "/update") {
    console.log("Memperbarui... agent akan menutup dan menyala lagi otomatis lewat start-agent.bat.");
    await shutdownBrowser();
    rl.close();
    process.exit(42); // kode 42 = permintaan restart untuk update; ditangkap oleh start-agent.bat
  }
  if (c === "/reset") {
    history.length = 0;
    extraGroups.clear();
    console.log("Percakapan dilupakan.");
    continue;
  }
  try {
    await runTask(c);
  } catch (e) {
    console.error("Gagal:", e.message);
  }
}
await shutdownBrowser();
rl.close();
