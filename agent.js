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
// ===== Izin aksi =====
// on    = semua izin otomatis "y" (tidak menunggu kamu)
// aman  = otomatis "y" kecuali aksi yang merusak/sulit dibatalkan (menimpa file, hapus, tutup jendela, pindah)
// off   = selalu bertanya y/n
// Ubah kapan saja dengan perintah /auto on|aman|off (tersimpan di auto.txt). Bawaan ada di DEFAULT_AUTO.
const DEFAULT_AUTO = "on";
const AUTO_FILE = "auto.txt";
let autoMode = DEFAULT_AUTO;
{
  const env = String(process.env.AUTO_APPROVE || "").toLowerCase();
  if (["on", "aman", "off"].includes(env)) autoMode = env;
  try {
    const saved = fs.readFileSync(AUTO_FILE, "utf8").trim().toLowerCase();
    if (["on", "aman", "off"].includes(saved)) autoMode = saved;
  } catch {}
}
const RISKY_ASK = /^(TIMPA|Pindahkan ke Recycle|Tutup jendela|Pindahkan:|Ekstrak|Matikan proses)/i;
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
    const loc = localVersion();
    const newer = /^\d+$/.test(remote) && /^\d+$/.test(loc) ? Number(remote) > Number(loc) : remote !== loc;
    if (remote && newer && remote !== pendingVersion) {
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
  const first = String(msg).split("\n")[0];
  if (autoMode === "on" || (autoMode === "aman" && !RISKY_ASK.test(first))) {
    console.log(`  [izin otomatis: ya] ${first.slice(0, 140)}`);
    return true;
  }
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
    await sleep(1800);
    await skipAds();
    await readPlayerState(); // memicu play()
    await sleep(700);
    const st = await readPlayerState();
    if (st.playing) return true;
    if (st.err) await page.reload({ waitUntil: "domcontentloaded" });
  }
  return false;
}

// ===== Pencarian YouTube cepat (tanpa memuat halaman hasil di browser) =====
async function ytSearchFast(query) {
  const res = await fetch("https://www.youtube.com/results?hl=id&search_query=" + encodeURIComponent(query), {
    headers: {
      "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
      "Accept-Language": "id-ID,id;q=0.9,en;q=0.8",
    },
    signal: AbortSignal.timeout(8000),
  });
  if (!res.ok) throw new Error("HTTP " + res.status);
  const html = await res.text();
  const m = html.match(/ytInitialData\s*=\s*(\{.+?\});\s*<\/script>/s);
  if (!m) throw new Error("data YouTube tidak ditemukan");
  const data = JSON.parse(m[1]);
  const out = [];
  const walk = (o) => {
    if (!o || typeof o !== "object" || out.length >= 8) return;
    const v = o.videoRenderer;
    if (v && v.videoId) {
      out.push({
        id: v.videoId,
        title: (v.title?.runs || []).map((r) => r.text).join("") || "(tanpa judul)",
        channel: v.ownerText?.runs?.[0]?.text || "",
      });
      return;
    }
    for (const k of Object.keys(o)) walk(o[k]);
  };
  walk(data);
  return out;
}

// ===== Upload cepat =====
const UPLOAD_TIMEOUT_MS = Number(process.env.UPLOAD_TIMEOUT_MIN || 15) * 60000;
const HOSTS_RE = /mediafire\.com\/(file|view|download|folder)|drive\.google\.com\/(file|drive\/folders)|wetransfer\.com\/downloads|we\.tl\/|gofile\.io\/d\/|pixeldrain\.com\/u\/|files\.catbox\.moe|catbox\.moe\/|file\.io\/|sendspace\.com\/file|transfer\.sh\/|tmpfiles\.org\/\d|dropbox\.com\/s|mega\.nz\/(file|folder)|1drv\.ms|filebin\.net\/\w|uploadhaven|bayfiles/i;
const UPLOAD_BTN = /^\s*(upload|unggah|mengunggah|tambah(kan)? file|add files?|select files?|choose files?|pilih file|browse|telusuri)\b/i;
const SUBMIT_BTN = /^\s*(begin upload|start upload|upload( now| files?)?|unggah( sekarang)?|mulai( upload| unggah)?|kirim|send|submit|selesai|done|lanjut|continue)\s*$/i;

async function findFileInputAny(timeoutMs = 0) {
  const deadline = Date.now() + timeoutMs;
  do {
    for (const fr of page.frames()) {
      const h = await fr.$("input[type=file]").catch(() => null);
      if (h) return h;
    }
    if (timeoutMs) await sleep(200);
  } while (Date.now() < deadline);
  return null;
}

async function hasLoginForm() {
  for (const fr of page.frames()) {
    const pw = await fr.$("input[type=password]").catch(() => null);
    if (pw && (await pw.isVisible().catch(() => false))) return true;
  }
  return false;
}

async function clickByText(re, timeout = 1500) {
  const groups = [page.getByRole("button", { name: re }), page.getByRole("link", { name: re }), page.getByText(re)];
  for (const g of groups) {
    const n = Math.min(await g.count().catch(() => 0), 5);
    for (let i = 0; i < n; i++) {
      const el = g.nth(i);
      if (!(await el.isVisible().catch(() => false))) continue;
      try {
        const label = ((await el.innerText({ timeout: 400 }).catch(() => "")) || "").trim().slice(0, 40);
        await el.click({ timeout });
        return label || "(tombol)";
      } catch {}
    }
  }
  return "";
}

// Klik tombol "Upload" lalu tangkap dialog pilih file ATAU input file yang muncul
async function openUploader(queue) {
  const groups = [page.getByRole("button", { name: UPLOAD_BTN }), page.getByRole("link", { name: UPLOAD_BTN }), page.getByText(UPLOAD_BTN)];
  for (const g of groups) {
    const n = Math.min(await g.count().catch(() => 0), 4);
    for (let i = 0; i < n; i++) {
      const el = g.nth(i);
      if (!(await el.isVisible().catch(() => false))) continue;
      const chooserP = page.waitForEvent("filechooser", { timeout: 2000 }).catch(() => null);
      try {
        await el.click({ timeout: 1500 });
      } catch {
        continue;
      }
      const chooser = await chooserP;
      if (chooser) {
        const batch = chooser.isMultiple() ? queue : [queue[0]];
        await chooser.setFiles(batch);
        return { used: batch.length };
      }
      const input = await findFileInputAny(1200);
      if (input) return { input };
    }
  }
  return null;
}

// Masukkan file ke halaman. Mengembalikan jumlah file yang dipakai (0 = gagal)
async function provideFiles(queue) {
  let input = await findFileInputAny(1200);
  if (!input) {
    const r = await openUploader(queue);
    if (r && r.used) return r.used;
    input = r && r.input;
  }
  if (!input) return 0;
  const multiple = await input.evaluate((el) => !!el.multiple).catch(() => false);
  const batch = multiple ? queue : [queue[0]];
  await input.setInputFiles(batch);
  return batch.length;
}

function trackUploads() {
  let pending = 0;
  let seen = 0;
  const isUp = (r) => ["POST", "PUT", "PATCH"].includes(r.method());
  const onReq = (r) => {
    if (isUp(r)) {
      pending++;
      seen++;
    }
  };
  const onDone = (r) => {
    if (isUp(r)) pending = Math.max(0, pending - 1);
  };
  context.on("request", onReq);
  context.on("requestfinished", onDone);
  context.on("requestfailed", onDone);
  return {
    get pending() {
      return pending;
    },
    get seen() {
      return seen;
    },
    stop() {
      context.off("request", onReq);
      context.off("requestfinished", onDone);
      context.off("requestfailed", onDone);
    },
  };
}

// true = selesai, string = selesai dengan catatan, false = waktu habis
async function waitUploadDone(tr, maxMs) {
  const t0 = Date.now();
  let quiet = 0;
  while (Date.now() - t0 < maxMs) {
    await sleep(600);
    const busy = await page
      .evaluate(() => {
        const vis = (e) => e.offsetParent !== null;
        const bars = [...document.querySelectorAll("progress, [role=progressbar]")].filter(vis);
        const t = document.body ? document.body.innerText : "";
        const inProgress = /\b(uploading|mengunggah|sedang mengunggah|upload in progress|memproses|processing)\b/i.test(t);
        const unfinished = bars.some((b) => {
          const v = b.getAttribute("aria-valuenow") ?? b.value;
          const mx = b.getAttribute("aria-valuemax") ?? b.max ?? 100;
          return v == null || Number(v) < Number(mx);
        });
        return unfinished || inProgress;
      })
      .catch(() => false);
    if (tr.pending === 0 && !busy) {
      quiet++;
      if (quiet >= 3 && tr.seen > 0) return true;
      if (quiet >= 8) return tr.seen > 0 ? true : "tidak ada aktivitas upload terdeteksi, periksa halaman";
    } else {
      quiet = 0;
    }
  }
  return false;
}

// Folder dikirim sebagai zip. Pakai tar bawaan Windows (cepat); cadangan: Compress-Archive
async function zipForUpload(dir) {
  const zip = path.join(os.tmpdir(), path.basename(dir) + ".zip");
  try {
    fs.rmSync(zip, { force: true });
  } catch {}
  const viaTar = await new Promise((resolve) => {
    execFile("tar", ["-a", "-c", "-f", zip, "-C", path.dirname(dir), path.basename(dir)], { timeout: 900000 }, (err) => resolve(!err));
  });
  if (!viaTar) {
    await ps("Compress-Archive -LiteralPath $env:SRC -DestinationPath $env:DEST -Force", { SRC: dir, DEST: zip }, 900000);
  }
  return zip;
}

function recentList(dir, count = 10) {
  const bad = /\.(crdownload|tmp|part|download|partial)$/i;
  const items = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (!e.isFile() || bad.test(e.name)) continue;
    const f = path.join(dir, e.name);
    try {
      const st = fs.statSync(f);
      items.push({ f, t: st.mtimeMs, s: st.size });
    } catch {}
  }
  return items.sort((a, b) => b.t - a.t).slice(0, Math.min(Math.max(Number(count) || 10, 1), 50));
}

const timers = [];
const SAFE_PARALLEL = new Set([
  "find_folder", "find_file", "list_dir", "read_text_file", "system_info", "now", "clipboard_get",
  "list_tabs", "list_windows", "recent_files", "search_text", "list_files", "list_processes",
]);

const impl = {
  // --- Desktop: file & folder ---
  find_folder: async ({ name }) => searchEverywhere(name, false),

  find_file: async ({ name }) => searchEverywhere(name, true),

  list_dir: async ({ path: p }) => {
    const items = fs.readdirSync(p, { withFileTypes: true }).slice(0, 100);
    return items.map((e) => (e.isDirectory() ? "[DIR] " : "[FILE] ") + e.name).join("\n") || "(kosong)";
  },

  open_path: async ({ target }) => {
    if (/^\s*(taskkill|shutdown|del|erase|rd|rmdir|format|reg|net|sc|wmic|powershell|cmd\s+\/c)\b/i.test(String(target))) {
      throw new Error("open_path hanya untuk membuka folder/file/aplikasi/URL. Untuk menutup aplikasi atau game gunakan kill_process.");
    }
    if (!(await ask(`Buka: ${target}`))) return "Dibatalkan user";
    await ps("Start-Process -FilePath $env:TARGET", { TARGET: String(target) });
    await sleep(800);
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
    await sleep(350);
    return "ok, diklik";
  },

  scroll_screen: async ({ amount }) => {
    const delta = -120 * Math.round(Number(amount)); // positif = turun
    if (!(await ask(`Scroll ${amount > 0 ? "turun" : "naik"} ${Math.abs(amount)}x`))) return "Dibatalkan user";
    await ps(PS_HEAD + `[W]::mouse_event(0x0800, 0, 0, [int]$env:D, [UIntPtr]::Zero)`, { D: String(delta) });
    await sleep(250);
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
    await sleep(250);
    return "ok, diketik";
  },

  press_keys: async ({ keys }) => {
    if (!(await ask(`Tekan tombol: ${keys}`))) return "Dibatalkan user";
    await ps(PS_HEAD + `[System.Windows.Forms.SendKeys]::SendWait($env:KEYS)`, { KEYS: String(keys) });
    await sleep(250);
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
    let list = [];
    try {
      list = (await ytSearchFast(String(query))).slice(0, 5).map((v) => ({
        title: v.title + (v.channel ? " | " + v.channel : ""),
        href: "https://www.youtube.com/watch?v=" + v.id,
      }));
    } catch {}
    if (!list.length) {
      await page.goto("https://www.youtube.com/results?search_query=" + encodeURIComponent(String(query)), {
        waitUntil: "domcontentloaded",
      });
      await page.waitForSelector("ytd-video-renderer a#video-title", { timeout: 20000 });
      list = await page.$$eval("ytd-video-renderer a#video-title", (els) =>
        els.slice(0, 5).map((e) => ({ title: e.textContent.trim(), href: e.href }))
      );
    }
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
    await sleep(200);
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

  // --- Upload cepat: satu panggilan menggantikan banyak langkah AI ---
  fast_upload: async ({ url, filename, folder, pattern, submit = true, new_tab = true }) => {
    const t0 = Date.now();
    const doSubmit = !(submit === false || submit === "false");
    let files = [];
    if (filename) {
      for (const tok of String(filename).split("|").map((x) => x.trim()).filter(Boolean)) {
        const abs = path.resolve(SAFE_DIR, tok.replace(/^"|"$/g, ""));
        if (fs.existsSync(abs) && fs.statSync(abs).isDirectory()) files.push(await zipForUpload(abs));
        else files.push(safePath(tok));
      }
    }
    if (folder) {
      const dir = path.resolve(String(folder));
      const pats = pattern ? String(pattern).toLowerCase().split("|").map((x) => x.trim().replace(/^\*/, "")).filter(Boolean) : [];
      for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        if (e.isFile() && (!pats.length || pats.some((p) => e.name.toLowerCase().includes(p)))) files.push(path.join(dir, e.name));
      }
    }
    files = [...new Set(files)].slice(0, 50);
    if (!files.length) throw new Error("Tidak ada file yang cocok untuk diupload");
    const sizeMB = files.reduce((a, f) => a + fs.statSync(f).size, 0) / 1048576;
    const daftar = files.slice(0, 15).join("\n   ") + (files.length > 15 ? `\n   ... +${files.length - 15} lagi` : "");
    if (!(await ask(`UPLOAD CEPAT ${files.length} file (${sizeMB.toFixed(1)} MB)${url ? " ke " + url : ""}:\n   ${daftar}\n  `))) {
      return "Dibatalkan user";
    }
    if (url) {
      if (isTrue(new_tab) && !isBlankPage()) page = await context.newPage();
      await page.bringToFront();
      await page.goto(fixUrl(url), { waitUntil: "domcontentloaded" });
      await sleep(400);
    }
    const tr = trackUploads();
    try {
      const queue = [...files];
      let rounds = 0;
      let loginAsked = false;
      let note = "";
      while (queue.length && rounds < 60) {
        rounds++;
        let used = await provideFiles(queue);
        if (!used && !loginAsked && (await hasLoginForm())) {
          loginAsked = true;
          await impl.wait_for_user({ message: "Halaman ini meminta login. Login dulu di jendela browser, lalu tekan Enter." });
          used = await provideFiles(queue);
        }
        if (!used) {
          throw new Error("Tombol atau input upload tidak ditemukan di halaman ini. Pastikan sudah login dan berada di halaman yang benar (coba /login).");
        }
        queue.splice(0, used);
        if (doSubmit) {
          await sleep(400);
          await clickByText(SUBMIT_BTN, 1500);
        }
        const r = await waitUploadDone(tr, UPLOAD_TIMEOUT_MS);
        if (r === false) {
          note = "Batas waktu menunggu habis; upload mungkin masih berjalan di halaman.";
          break;
        }
        if (typeof r === "string") note = r;
      }
      const links = await page
        .evaluate((src) => {
          const re = new RegExp(src, "i");
          const out = new Set();
          document.querySelectorAll("a[href], input, textarea").forEach((e) => {
            const v = e.href || e.value || "";
            if (re.test(v)) out.add(v);
          });
          ((document.body && document.body.innerText.match(/https?:\/\/[^\s"'<>]+/g)) || []).forEach((u) => {
            if (re.test(u)) out.add(u);
          });
          return [...out].slice(0, 10);
        }, HOSTS_RE.source)
        .catch(() => []);
      const secs = ((Date.now() - t0) / 1000).toFixed(1);
      return (
        `Upload ${files.length - queue.length}/${files.length} file selesai dalam ${secs} dtk.` +
        (note ? ` Catatan: ${note}` : "") +
        (links.length ? `\nLink terdeteksi:\n${links.join("\n")}` : "\nLink belum terdeteksi otomatis; lihat halaman di browser.")
      );
    } finally {
      tr.stop();
    }
  },

  recent_files: async ({ folder, count = 10 }) => {
    const dir = path.resolve(String(folder || path.join(HOME, "Downloads")));
    const items = recentList(dir, count);
    return items.length
      ? items.map((x, i) => `${i + 1}. ${x.f} (${new Date(x.t).toLocaleString("id-ID")}, ${(x.s / 1048576).toFixed(1)} MB)`).join("\n")
      : "(tidak ada file)";
  },

  search_text: async ({ folder, text }) => {
    const root = path.resolve(String(folder));
    const q = String(text).toLowerCase();
    const okExt = /\.(txt|md|js|ts|json|csv|log|html|css|py|java|xml|ini|yml|yaml|cfg|bat|php|sql)$/i;
    const hits = [];
    const deadline = Date.now() + 15000;
    const walk = (dir, depth) => {
      if (depth < 0 || hits.length >= 20 || Date.now() > deadline) return;
      let entries;
      try {
        entries = fs.readdirSync(dir, { withFileTypes: true });
      } catch {
        return;
      }
      for (const e of entries) {
        const full = path.join(dir, e.name);
        if (e.isDirectory()) {
          if (!SKIP_DIRS.has(e.name.toLowerCase()) && !e.name.startsWith("$")) walk(full, depth - 1);
        } else if (okExt.test(e.name)) {
          try {
            if (fs.statSync(full).size > 2_000_000) continue;
            const lines = fs.readFileSync(full, "utf8").split(/\r?\n/);
            for (let i = 0; i < lines.length && hits.length < 20; i++) {
              if (lines[i].toLowerCase().includes(q)) hits.push(`${full}:${i + 1}: ${lines[i].trim().slice(0, 120)}`);
            }
          } catch {}
        }
      }
    };
    walk(root, 5);
    return hits.length ? hits.join("\n") : "Tidak ditemukan";
  },

  copy_path: async ({ from, to }) => {
    if (!(await ask(`Salin: ${from}  ke  ${to}`))) return "Dibatalkan user";
    await ps("Copy-Item -LiteralPath $env:SRC -Destination $env:DEST -Recurse -Force", {
      SRC: path.resolve(String(from)),
      DEST: path.resolve(String(to)),
    }, 600000);
    return "ok";
  },

  save_screenshot: async ({ path: p }) => {
    const stamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
    const dest = p ? path.resolve(String(p)) : path.join(HOME, "Pictures", "Screenshots", `layar-${stamp}.png`);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    await ps(
      PS_HEAD +
        `
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.X, $b.Y, 0, 0, $bmp.Size)
$bmp.Save($env:OUT, [System.Drawing.Imaging.ImageFormat]::Png)
`,
      { OUT: dest }
    );
    return "Tersimpan: " + dest;
  },

  set_volume: async ({ level }) => {
    const n = Math.min(Math.max(Math.round(Number(level)), 0), 100);
    await ps(
      `
Add-Type @"
using System.Runtime.InteropServices;
public class K { [DllImport("user32.dll")] public static extern void keybd_event(byte b, byte s, uint f, int e); }
"@
for ($i = 0; $i -lt 50; $i++) { [K]::keybd_event(0xAE, 0, 0, 0); [K]::keybd_event(0xAE, 0, 2, 0); Start-Sleep -Milliseconds 12 }
for ($i = 0; $i -lt [int]$env:UP; $i++) { [K]::keybd_event(0xAF, 0, 0, 0); [K]::keybd_event(0xAF, 0, 2, 0); Start-Sleep -Milliseconds 12 }
`,
      { UP: String(Math.round(n / 2)) }
    );
    return `Volume diatur sekitar ${n}%`;
  },

  speak: async ({ text }) => {
    await ps("Add-Type -AssemblyName System.Speech; $s = New-Object System.Speech.Synthesis.SpeechSynthesizer; $s.Speak($env:TXT)", { TXT: String(text).slice(0, 500) }, 60000);
    return "ok, diucapkan";
  },

  set_timer: async ({ amount, unit = "menit", message = "Waktunya!" }) => {
    const mult = /detik/i.test(String(unit)) ? 1000 : /jam/i.test(String(unit)) ? 3600000 : 60000;
    const ms = Math.round(Number(String(amount).replace(",", ".")) * mult);
    if (!(ms > 0) || ms > 24 * 3600000) throw new Error("Durasi tidak valid (maksimal 24 jam)");
    timers.push(
      setTimeout(async () => {
        console.log(`\n*** PENGINGAT: ${message} ***`);
        try {
          await ps("[console]::Beep(880,300); [console]::Beep(1175,400); Add-Type -AssemblyName System.Speech; (New-Object System.Speech.Synthesis.SpeechSynthesizer).Speak($env:TXT)", { TXT: String(message) }, 60000);
        } catch {}
      }, ms)
    );
    return `Pengingat diatur ${amount} ${unit} lagi: "${message}" (aktif selama agent terbuka)`;
  },

  list_processes: async ({ filter }) => {
    const out = await ps(
      `$f = $env:F
Get-Process | Where-Object { $_.ProcessName -like ("*" + $f + "*") } | Sort-Object WorkingSet64 -Descending | Select-Object -First 15 | ForEach-Object { $_.ProcessName + " | PID " + $_.Id + " | " + [math]::Round($_.WorkingSet64 / 1MB) + " MB" + $(if ($_.MainWindowTitle) { " | " + $_.MainWindowTitle } else { "" }) }`,
      { F: String(filter || "") }
    );
    return out || "Tidak ada proses yang cocok";
  },

  kill_process: async ({ name }) => {
    const n = String(name).trim().replace(/\.exe$/i, "");
    if (!/^[\w][\w .()-]{0,59}$/.test(n)) throw new Error("Nama proses tidak valid");
    if (/^(system|idle|registry|smss|csrss|wininit|winlogon|services|lsass|svchost|dwm|fontdrvhost|explorer|sihost|ctfmon|node|chrome|msedge)$/i.test(n)) {
      throw new Error(`Proses "${n}" dilindungi (penting untuk Windows atau dipakai agent). Untuk tab atau jendela browser gunakan close_tab atau close_window.`);
    }
    if (!(await ask(`Matikan proses: ${n}`))) return "Dibatalkan user";
    return ps(
      `$p = @(Get-Process -Name $env:N -ErrorAction SilentlyContinue)
if ($p.Count -eq 0) { "Proses tidak ditemukan (sedang tidak berjalan): " + $env:N } else { $p | Stop-Process -Force; "ok, dihentikan " + $p.Count + " proses " + $env:N }`,
      { N: n }
    );
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
  fn(
    "fast_upload",
    "UPLOAD CEPAT dalam satu langkah (dahulukan alat ini untuk semua permintaan upload): buka URL di tab baru, temukan tombol/input upload otomatis, pilih satu/banyak file atau isi folder (folder tunggal dikirim sebagai zip), klik tombol kirim, tunggu selesai, kembalikan link jika terdeteksi. Jika halaman sudah terbuka, url boleh kosong.",
    {
      url: str("Alamat situs upload (opsional jika halaman sudah terbuka)"),
      filename: str("Path file (banyak dipisah |) atau path folder (akan di-zip)"),
      folder: str("Folder berisi file yang diupload semuanya (opsional)"),
      pattern: str("Filter nama file di folder, misal .pdf atau .jpg|.png (opsional)"),
      submit: bool("false = jangan klik tombol kirim otomatis (default true)"),
      new_tab: bool("false = pakai tab aktif (default true)"),
    },
    ["url", "filename", "folder", "pattern", "submit", "new_tab"]
  ),
  fn("recent_files", "Daftar file terbaru di sebuah folder (bawaan: Downloads)", { folder: str("Path folder (opsional)"), count: num("Jumlah (default 10)") }, ["folder", "count"]),
  fn("search_text", "Cari teks di dalam file teks/kode pada sebuah folder", { folder: str("Path folder"), text: str("Teks yang dicari") }),
  fn("copy_path", "Salin file atau folder", { from: str("Path asal"), to: str("Path tujuan") }),
  fn("save_screenshot", "Simpan screenshot layar penuh ke file (bawaan: Pictures\\Screenshots)", { path: str("Path file .png (opsional)") }, ["path"]),
  fn("set_volume", "Atur volume Windows ke angka tertentu (0-100)", { level: num("Persen volume") }),
  fn("speak", "Ucapkan teks dengan suara komputer", { text: str("Teks yang diucapkan") }),
  fn(
    "set_timer",
    "Atur pengingat: setelah waktu tertentu muncul pesan, bunyi, dan suara (aktif selama agent terbuka)",
    { amount: num("Jumlah waktu"), unit: str("detik, menit, atau jam"), message: str("Pesan pengingat") },
    ["unit", "message"]
  ),
  fn("list_processes", "Daftar proses yang sedang berjalan (15 terbesar), bisa difilter nama", { filter: str("Sebagian nama proses (opsional)") }, ["filter"]),
  fn("kill_process", "Matikan paksa sebuah aplikasi/game/proses berdasarkan nama proses, misalnya cs2 atau notepad (tanpa .exe). Pakai ini untuk menutup aplikasi, BUKAN open_path", { name: str("Nama proses, contoh: cs2") }),
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
- HEMAT LANGKAH: jika beberapa langkah tidak saling bergantung, panggil beberapa tool sekaligus dalam satu jawaban.
- UPLOAD: selalu pakai fast_upload (satu panggilan, otomatis menemukan tombol upload, mendukung banyak file, folder, dan zip). Pakai upload_file hanya jika fast_upload gagal.
- Volume ke angka tertentu: set_volume. File terbaru: recent_files.
- Menutup/mematikan aplikasi atau game (misalnya cs2): pakai kill_process dengan nama proses tanpa .exe. JANGAN pakai open_path untuk taskkill.
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
let slimMode = process.env.SLIM !== "0"; // true = kirim hanya alat yang relevan (muatan kecil = lebih cepat)
let fallbackModels = null; // diisi saat pertama kali dibutuhkan
let poolIdx = 0;
const extraGroups = new Set();
const BACKOFF = Number(process.env.BACKOFF_MS || 1000);

const TOOL_GROUPS = {
  youtube: ["youtube_play", "youtube_control"],
  tabs: ["new_tab", "open_urls", "list_tabs", "switch_tab", "close_tab", "scroll_page", "web_search"],
  desktop: ["click_screen", "scroll_screen", "type_desktop", "press_keys", "wait", "list_windows", "focus_window", "close_window"],
  files: ["read_text_file", "write_text_file", "make_folder", "move_path", "copy_path", "recycle_path", "zip_path", "unzip_path", "download_file", "recent_files", "search_text"],
  pc: ["media_key", "set_volume", "clipboard_get", "clipboard_set", "system_info", "save_screenshot", "speak", "set_timer", "kill_process", "list_processes"],
};
const CORE_TOOLS = [
  "done", "wait_for_user", "more_tools", "now", "open_url", "get_page_text", "inspect_page", "type_text", "click",
  "upload_file", "fast_upload", "list_files", "find_folder", "find_file", "list_dir", "open_path", "screenshot",
];
const GROUP_KEYWORDS = {
  youtube: /youtube|video|lagu|musik|music|putar|nonton|dengar|pause|next/i,
  tabs: /\btab\b|cari|search|google|web|internet|situs|website|sekaligus/i,
  desktop: /klik|layar|mouse|ketik|jendela|window|aplikasi|screenshot|scroll|tombol/i,
  files: /file|folder|zip|hapus|pindah|tulis|baca|unduh|download|buat|ganti nama|salin|copy|terbaru|cari teks/i,
  pc: /volume|suara|clipboard|salin|\bram\b|cpu|baterai|sistem|media|mute|timer|ingatkan|pengingat|ucap|bicara|screenshot|tangkap|matikan|hentikan|kill|proses|\.exe|game|aplikasi|taskkill|paksa/i,
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

// ===== Jalur cepat: perintah umum langsung dijalankan TANPA AI (hasil dalam hitungan detik) =====
// Jika perintah tidak dikenali atau jalur cepat gagal, otomatis diserahkan ke AI.
let FAST = process.env.FAST !== "0";

const tidy = (s) =>
  String(s)
    .replace(/\s+(dong|ya|yah|deh|aja|donk|sih|nih|please|pls|plis|dulu)\s*$/i, "")
    .replace(/[.!?]+$/, "")
    .trim();

const KNOWN_SITES = {
  youtube: "youtube.com", yt: "youtube.com", google: "google.com", gmail: "mail.google.com", github: "github.com",
  tiktok: "tiktok.com", facebook: "facebook.com", fb: "facebook.com", instagram: "instagram.com", ig: "instagram.com",
  twitter: "x.com", x: "x.com", whatsapp: "web.whatsapp.com", wa: "web.whatsapp.com", mediafire: "mediafire.com",
  drive: "drive.google.com", maps: "maps.google.com", netflix: "netflix.com", spotify: "open.spotify.com",
  chatgpt: "chatgpt.com", claude: "claude.ai", gemini: "gemini.google.com", tokopedia: "tokopedia.com",
  shopee: "shopee.co.id", telegram: "web.telegram.org", linkedin: "linkedin.com", pinterest: "pinterest.com",
  twitch: "twitch.tv", discord: "discord.com", reddit: "reddit.com", wikipedia: "id.wikipedia.org",
};
const UPLOAD_SITES = {
  mediafire: "https://app.mediafire.com/myfiles", gofile: "https://gofile.io", pixeldrain: "https://pixeldrain.com",
  catbox: "https://catbox.moe", wetransfer: "https://wetransfer.com", drive: "https://drive.google.com/drive/my-drive",
  tmpfiles: "https://tmpfiles.org", filebin: "https://filebin.net",
};
const APPS = {
  kamera: "microsoft.windows.camera:", camera: "microsoft.windows.camera:", notepad: "notepad", kalkulator: "calc",
  calculator: "calc", paint: "mspaint", pengaturan: "ms-settings:", settings: "ms-settings:", "file explorer": "explorer",
  explorer: "explorer", cmd: "cmd", "task manager": "taskmgr", "pengelola tugas": "taskmgr", "recycle bin": "shell:RecycleBinFolder",
};
const FILE_KINDS = {
  foto: ".jpg|.jpeg|.png|.webp", gambar: ".jpg|.jpeg|.png|.webp", video: ".mp4|.mkv|.avi|.mov", vidio: ".mp4|.mkv|.avi|.mov",
  musik: ".mp3|.wav|.flac|.m4a", lagu: ".mp3|.wav|.flac|.m4a", dokumen: ".pdf|.doc|.docx|.txt|.xlsx|.pptx",
};
const DOMAIN_RE = /^(?:https?:\/\/)?[a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:com|id|net|org|io|co|me|app|dev|tv|ai|xyz|info|co\.id|go\.id|ac\.id)(?:\/\S*)?$/i;

const siteUrl = (t) => {
  const k = String(t).trim().toLowerCase();
  if (KNOWN_SITES[k]) return "https://" + KNOWN_SITES[k];
  if (DOMAIN_RE.test(String(t).trim())) return fixUrl(String(t).trim());
  return "";
};
const uploadUrl = (t) => {
  const k = String(t).trim().toLowerCase().replace(/\.(com|io|org|net|me|moe|app)$/, "");
  if (UPLOAD_SITES[k]) return UPLOAD_SITES[k];
  if (DOMAIN_RE.test(String(t).trim())) return fixUrl(String(t).trim());
  return "";
};
const onYouTube = () => /youtube\.com\/watch/i.test(page.url());
const onYouTubeSite = () => /youtube\.com/i.test(page.url());
const isBlankPage = () => {
  const u = page.url();
  return !u || /^(about:blank|chrome:\/\/new-?tab|edge:\/\/newtab)/i.test(u);
};
const knownDir = (name) => {
  const k = String(name).trim().toLowerCase();
  if (/^(downloads?|unduhan)$/.test(k)) return path.join(HOME, "Downloads");
  if (k === "desktop") return path.join(HOME, "Desktop");
  if (/^(documents?|dokumen)$/.test(k)) return path.join(HOME, "Documents");
  if (/^(pictures?|gambar|foto)$/.test(k)) return path.join(HOME, "Pictures");
  return "";
};

// Pilih hasil pencarian terbaik: nama paling mirip, lalu lokasi umum, lalu path terpendek
function bestPath(lines, query) {
  const raw = String(query).toLowerCase();
  const q = raw.replace(/\.[a-z0-9]{2,4}$/, "");
  const score = (p) => {
    const base = path.basename(p).toLowerCase();
    const stem = base.replace(/\.[a-z0-9]{2,4}$/, "");
    let s = 0;
    if (base === raw || stem === q) s += 10;
    else if (stem.startsWith(q)) s += 4;
    if (/[\\/](downloads|desktop|documents|unduhan)[\\/]/i.test(p)) s += 3;
    return s - p.length / 200;
  };
  return [...lines].sort((a, b) => score(b) - score(a))[0];
}
const resultLines = (out) => String(out).split("\n").filter((l) => l && l !== "Tidak ditemukan");

// Ubah ucapan seperti "laporan.pdf", "folder Reia", "yang terbaru di downloads" menjadi path nyata
async function resolveUploadSource(what) {
  const w = tidy(what).replace(/^["']|["']$/g, "");
  let mm;
  if ((mm = w.match(/^semua\s+(?:file\s+)?(.+?)\s+(?:di|dari)\s+(?:folder\s+)?(.+)$/i))) {
    const kind = mm[1].trim().toLowerCase();
    const pattern = FILE_KINDS[kind] || (/^[a-z0-9]{2,5}$/.test(kind) ? "." + kind : kind);
    let folder = knownDir(mm[2]);
    if (!folder) {
      const lines = resultLines(searchEverywhere(mm[2].trim(), false));
      if (!lines.length) throw new Error(`Folder "${mm[2]}" tidak ditemukan`);
      folder = bestPath(lines, mm[2]);
    }
    return { folder, pattern, label: `semua ${kind} di ${folder}` };
  }
  if ((mm = w.match(/^(?:file\s+)?(?:yang\s+)?(?:paling\s+)?(?:terbaru|terakhir|baru)(?:\s+(?:di|dari)\s+(?:folder\s+)?(.+))?$/i))) {
    const dir = mm[1] ? knownDir(mm[1]) || path.resolve(mm[1]) : path.join(HOME, "Downloads");
    const newest = recentList(dir, 1)[0];
    if (!newest) throw new Error("Tidak ada file di " + dir);
    return { filename: newest.f, label: `file terbaru di ${dir}` };
  }
  if ((mm = w.match(/^folder\s+(.+)$/i))) {
    let folder = knownDir(mm[1]);
    if (!folder) {
      const lines = resultLines(searchEverywhere(mm[1].trim(), false));
      if (!lines.length) throw new Error(`Folder "${mm[1]}" tidak ditemukan`);
      folder = bestPath(lines, mm[1]);
    }
    return { filename: folder, label: `folder ${folder} (dikirim sebagai zip)` };
  }
  const direct = path.resolve(SAFE_DIR, w);
  if (fs.existsSync(direct)) return { filename: direct, label: direct };
  const lines = resultLines(searchEverywhere(w, true));
  if (!lines.length) throw new Error(`File "${w}" tidak ditemukan`);
  return { filename: bestPath(lines, w), label: w };
}

async function tryFastCommand(raw) {
  const c = String(raw).trim().replace(/\s+/g, " ");
  let m;
  const yt = onYouTube();

  // ---- Volume ----
  if ((m = c.match(/^(?:(?:atur|set|ubah)\s+)?(?:volume|suara)(?:nya)?\s*(?:jadi|ke|menjadi|=|di)?\s*(\d{1,3})\s*%?$/i)) ||
      (m = c.match(/^(?:naikin|naikkan|turunin|turunkan|kecilin|kecilkan|besarin|besarkan)\s+(?:volume|suara)(?:nya)?\s+(?:jadi|ke|menjadi)\s*(\d{1,3})\s*%?$/i))) {
    return await impl.set_volume({ level: m[1] });
  }
  if ((m = c.match(/^(?:naikin|naikkan|besarin|besarkan|keraskan|tambah(?:in|kan)?)\s+(?:volume|suara)(?:nya)?(?:\s+(\d{1,3})\s*%?)?$/i))) {
    await impl.media_key({ key: "volup", times: m[1] ? Math.max(1, Math.round(Number(m[1]) / 2)) : 5 });
    return `Volume dinaikkan ${m[1] ? m[1] + "%" : "sekitar 10%"}.`;
  }
  if ((m = c.match(/^(?:turunin|turunkan|kecilin|kecilkan|pelanin|pelankan|kurangi|kurangin)\s+(?:volume|suara)(?:nya)?(?:\s+(\d{1,3})\s*%?)?$/i))) {
    await impl.media_key({ key: "voldown", times: m[1] ? Math.max(1, Math.round(Number(m[1]) / 2)) : 5 });
    return `Volume diturunkan ${m[1] ? m[1] + "%" : "sekitar 10%"}.`;
  }
  if (/^(?:mute|unmute|bisukan|senyapkan|matikan suara|nyalakan suara|bunyikan)(?:\s+(?:suara|volume))?$/i.test(c)) {
    await impl.media_key({ key: "mute" });
    return "Mute diubah (toggle).";
  }

  // ---- Kontrol pemutar ----
  if (/^(?:pause|jeda)(?:\s+(?:dulu|videonya|musiknya|lagunya|lagu|video|musik|youtube))*$/i.test(c) ||
      (yt && /^(?:stop|setop|berhenti|hentikan)(?:\s+(?:dulu|videonya|musiknya|lagunya))*$/i.test(c))) {
    if (yt) await impl.youtube_control({ action: "pause" });
    else await impl.media_key({ key: "playpause" });
    return "Dijeda.";
  }
  if (/^(?:play|resume|putar lagi|mulai lagi)(?:\s+(?:dulu|videonya|musiknya|lagunya|lagu|video|musik))*$/i.test(c) ||
      (yt && /^(?:lanjut|lanjutkan|terusin)$/i.test(c))) {
    if (yt) await impl.youtube_control({ action: "play" });
    else await impl.media_key({ key: "playpause" });
    return "Dilanjutkan.";
  }
  if (/^(?:next|skip|selanjutnya|berikutnya|lagu berikutnya|lagu selanjutnya|ganti lagu)$/i.test(c)) {
    if (yt) await impl.youtube_control({ action: "next" });
    else await impl.media_key({ key: "next" });
    return "Lagu/video berikutnya.";
  }
  if (/^(?:previous|prev|sebelumnya|lagu sebelumnya)$/i.test(c)) {
    if (yt) await impl.youtube_control({ action: "previous" });
    else await impl.media_key({ key: "prev" });
    return "Lagu/video sebelumnya.";
  }
  if (yt && (m = c.match(/^(?:maju|majuin|forward)\s*(\d+)?\s*(?:detik)?$/i))) {
    await impl.youtube_control({ action: "forward", seconds: m[1] || 10 });
    return `Maju ${m[1] || 10} detik.`;
  }
  if (yt && (m = c.match(/^(?:mundur|mundurin|rewind)\s*(\d+)?\s*(?:detik)?$/i))) {
    await impl.youtube_control({ action: "backward", seconds: m[1] || 10 });
    return `Mundur ${m[1] || 10} detik.`;
  }
  if (yt && /^(?:fullscreen|layar penuh)$/i.test(c)) {
    await impl.youtube_control({ action: "fullscreen" });
    return "Fullscreen diubah.";
  }

  // ---- YouTube: putar lagu/video ----
  if (/^(?:nonton|tonton|buka|putar)\s+youtube$/i.test(c)) {
    await impl.open_url({ url: "https://www.youtube.com", new_tab: !isBlankPage() });
    return "YouTube dibuka.";
  }
  if ((m = c.match(/^(?:putar(?:kan|in)?|setel(?:in)?|play|dengerin|dengarkan|nonton(?:in)?|tonton|cari(?:in|kan)?)\s+(?:lagu|musik|music|video|vidio|film)\s+(.+)$/i)) ||
      (m = c.match(/^(?:putar(?:kan|in)?|setel(?:in)?|play|dengerin|dengarkan|nonton(?:in)?|tonton)\s+(.+)$/i))) {
    const q = tidy(m[1]).replace(/\s+(?:di|dari|lewat)\s+youtube$/i, "");
    if (!q || /^(?:file|folder|dokumen)\b/i.test(q) || /[a-z]:\\|\.(?:mp3|mp4|mkv|avi|wav|pdf|zip|txt)\b/i.test(q)) return null;
    const out = await impl.youtube_play({ query: q, new_tab: !onYouTubeSite() && !isBlankPage() });
    return String(out).split("\n")[0];
  }

  // ---- Upload cepat ----
  if ((m = c.match(/^(?:upload|unggah|uploud|kirim)\s+(?:file\s+)?(.+?)\s+ke\s+(\S+)$/i))) {
    const target = uploadUrl(m[2]);
    if (!target) return null; // tujuan tidak dikenal -> serahkan ke AI
    const src = await resolveUploadSource(m[1]);
    return await impl.fast_upload({ url: target, filename: src.filename, folder: src.folder, pattern: src.pattern });
  }

  // ---- Buka folder / situs / aplikasi ----
  if ((m = c.match(/^buka(?:in|kan)?\s+folder\s+(.+)$/i))) {
    const name = tidy(m[1]);
    let dir = knownDir(name);
    let extra = "";
    if (!dir) {
      const lines = resultLines(searchEverywhere(name, false));
      if (!lines.length) return `Folder "${name}" tidak ditemukan.`;
      dir = bestPath(lines, name);
      if (lines.length > 1) extra = `\n(${lines.length - 1} folder lain cocok: ${lines.filter((l) => l !== dir).slice(0, 3).join(" | ")})`;
    }
    const r = await impl.open_path({ target: dir });
    return String(r).startsWith("Dibatalkan") ? r : `Folder dibuka: ${dir}${extra}`;
  }
  if ((m = c.match(/^(?:buka(?:in|kan)?|open)\s+(.+?)(?:\s+sekaligus)?$/i))) {
    const tokens = m[1]
      .split(/\s*(?:,|\bdan\b|&|\+)\s*/i)
      .map((x) => x.replace(/\s+(?:di\s+)?tab\s+baru$/i, "").trim())
      .filter(Boolean);
    const urls = tokens.map(siteUrl);
    if (tokens.length && urls.every(Boolean)) {
      if (urls.length === 1) {
        await impl.open_url({ url: urls[0], new_tab: !isBlankPage() });
        return `Dibuka: ${urls[0]}`;
      }
      await impl.open_urls({ urls });
      return `${urls.length} tab dibuka: ${urls.join(", ")}`;
    }
    if (tokens.length === 1 && APPS[tokens[0].toLowerCase()]) {
      const r = await impl.open_path({ target: APPS[tokens[0].toLowerCase()] });
      return String(r).startsWith("Dibatalkan") ? r : `${tokens[0]} dibuka.`;
    }
  }

  // ---- Cari file / folder / web ----
  if ((m = c.match(/^cari(?:in|kan)?\s+(file|folder)\s+(.+)$/i))) {
    const out = searchEverywhere(tidy(m[2]), m[1].toLowerCase() === "file");
    return out === "Tidak ditemukan" ? `${m[1]} "${tidy(m[2])}" tidak ditemukan.` : out;
  }
  if ((m = c.match(/^(?:cari(?:in|kan)?|googling)\s+(?:tau\s+)?(.+?)\s+(?:di\s+)?(?:web|google|internet|browser)$/i))) {
    return await impl.web_search({ query: tidy(m[1]), new_tab: !isBlankPage() });
  }
  if (/^(?:lihat|tampilkan|cek)?\s*(?:file|unduhan|download(?:an)?)\s+(?:yang\s+)?terbaru(?:\s+(?:di\s+)?\S+)?$/i.test(c)) {
    return await impl.recent_files({});
  }

  // ---- Tab ----
  if (/^(?:tutup)\s+tab(?:\s+ini)?$/i.test(c)) return (await impl.close_tab({})).split("\n")[0];
  if ((m = c.match(/^(?:pindah|ke|buka)\s+tab\s+(terbaru|baru|terakhir|\d+)$/i))) {
    const idx = /^\d+$/.test(m[1]) ? Number(m[1]) : -1;
    return await impl.switch_tab({ index: idx });
  }
  if (/^(?:daftar|list|lihat)\s+tab$/i.test(c)) return await impl.list_tabs();

  // ---- Matikan aplikasi / game ----
  if ((m = c.match(/^taskkill\s+.*?\/im\s+([\w.-]+)/i)) ||
      (m = c.match(/^(?:matikan|tutup|kill|stop|hentikan|paksa tutup|force close)\s+(?:aplikasi |app |program |game |proses )?([\w.-]+(?: [\w.-]+)?)$/i))) {
    const target = m[1].trim();
    if (/^(?:suara|volume|komputer|laptop|pc|wifi|bluetooth|layar|lampu|tab|jendela|window|musik|lagu|video|timer|alarm|youtube|semua|ini|itu|chrome|browser)\b/i.test(target)) return null;
    return await impl.kill_process({ name: target });
  }

  // ---- PC ----
  if (/^(?:info|cek|status|lihat)\s*(?:pc|komputer|laptop|sistem|spek|ram|cpu|baterai|disk|storage|memori)\b/i.test(c)) return await impl.system_info();
  if (/^(?:jam berapa|tanggal berapa|hari apa|sekarang jam berapa|sekarang tanggal berapa|jam berapa sekarang)\??$/i.test(c)) return await impl.now();
  if (/^(?:screenshot|tangkap layar|ss|capture)(?:\s+layar)?$/i.test(c)) return await impl.save_screenshot({});
  if ((m = c.match(/^(?:ingatkan|ingetin|ingatin|timer|alarm|set timer)\s+(?:aku\s+|saya\s+|gue\s+)?(?:dalam\s+)?(\d+(?:[.,]\d+)?)\s*(menit|detik|jam)\s*(?:lagi)?\s*(?:untuk|buat|:)?\s*(.*)$/i))) {
    return await impl.set_timer({ amount: m[1], unit: m[2], message: tidy(m[3]) || "Waktunya!" });
  }
  if ((m = c.match(/^(?:ucapkan|bilang|katakan|bacakan)\s+(.+)$/i))) return await impl.speak({ text: tidy(m[1]) });

  return null; // tidak dikenal -> AI
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

      const execCall = async (call) => {
        const name = call.function.name;
        try {
          const args = JSON.parse(call.function.arguments || "{}");
          console.log(`[${step}] ${name}`, args);
          if (!impl[name]) throw new Error("Tool tidak dikenal: " + name);
          await ensurePage();
          return await impl[name](args);
        } catch (e) {
          return "ERROR: " + e.message;
        }
      };
      const calls = msg.tool_calls;
      const results = [];
      if (calls.length > 1 && calls.every((c) => SAFE_PARALLEL.has(c.function.name))) {
        results.push(...(await Promise.all(calls.map(execCall)))); // alat baca-saja dijalankan bersamaan
      } else {
        for (const call of calls) results.push(await execCall(call));
      }
      calls.forEach((call, i) =>
        history.push({ role: "tool", tool_call_id: call.id, content: String(results[i]).slice(0, 4000) })
      );

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

const BUILTIN_CHANGELOG = `Versi 9
- Bisa mematikan aplikasi/game: ketik "matikan cs2" atau "tutup notepad". Proses penting Windows dilindungi.
- Perbaikan update: versi lama di GitHub tidak bisa lagi menimpa agent yang lebih baru. Update hanya jika versi GitHub LEBIH BARU.
- Izin otomatis tetap berlaku pada semua versi (kecuali kamu memilih /auto off).
- Versi 8: izin otomatis. Versi 7: jalur cepat tanpa AI dan upload cepat.
Ketik /bantuan untuk daftar lengkap.`;

const HELP = `
JALUR CEPAT (tanpa AI, langsung jalan)
  putar lagu kiss me  |  volume 50  |  naikin volume  |  pause / next / maju 30  |  buka youtube, gmail
  buka folder Reia  |  buka kamera  |  cari file laporan  |  cari cuaca besok di web  |  screenshot
  upload laporan.pdf ke mediafire  |  upload file terbaru ke mediafire  |  upload semua pdf di folder Laporan ke mediafire
  ingatkan 10 menit lagi minum obat  |  info pc  |  jam berapa  |  matikan cs2  |  tutup notepad
FITUR AGENT (lewat AI untuk tugas yang lebih rumit)
  Browser  : buka website, isi form, klik, cari di web, scroll, banyak tab
  YouTube  : putar otomatis (skip iklan), kontrol pause/next/maju/mundur/mute/fullscreen
  Upload   : cepat, banyak file, satu folder (di-zip), dari lokasi mana pun, menampilkan link hasil
  Login    : /login lalu login manual sekali, sesi tersimpan. Agent tidak pernah mengetik passwordmu
  Layar    : screenshot, klik, scroll, ketik, tekan tombol, jendela
  File     : cari file/folder semua drive, baca/tulis, salin, pindah, zip, hapus ke Recycle Bin, unduh, cari teks
  PC       : volume, tombol media, clipboard, info sistem, bicara, pengingat
PERINTAH KHUSUS
  /login [alamat]  login manual            /baru   fitur terbaru          /fast on|off  jalur cepat
  /tes             uji model, pilih TERCEPAT    /model [nama]  lihat/ganti model
  /update          perbarui sekarang       /versi  cek versi              /reset  lupakan percakapan
  /auto on|aman|off  izin otomatis ya / otomatis kecuali aksi merusak / selalu tanya
  /bantuan         tampilkan ini           exit    keluar
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
console.log(`Izin aksi: ${{ on: "OTOMATIS (semua langsung ya)", aman: "OTOMATIS kecuali aksi merusak", off: "SELALU TANYA" }[autoMode]}. Ubah dengan /auto. Ctrl+C untuk menghentikan.`);
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
    const results = await Promise.all(list.map(async (m) => ({ m, r: await testModel(m) }))); // diuji bersamaan
    for (const { m, r } of results) console.log(`  ${r.mark} ${m}   ${r.ms} ms   ${r.text}`);
    const best = results.filter((x) => x.r.mark === "[OK]").sort((x, y) => x.r.ms - y.r.ms)[0]?.m || "";
    if (!best) {
      console.log("\nTidak ada model yang lolos. Cek dashboard 9Router: provider terhubung, kuota, dan menu Console Log.");
    } else if (best === baseModel) {
      console.log(`\nModel aktif (${baseModel}) sudah yang tercepat dan berfungsi.`);
    } else {
      baseModel = best;
      poolIdx = 0;
      try {
        fs.writeFileSync(MODEL_FILE, best);
      } catch {}
      console.log(`\nModel tercepat yang berfungsi dipilih otomatis: ${best} (tersimpan, ketik /model reset untuk kembali ke bawaan).`);
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
  if (c === "/auto" || c.startsWith("/auto ")) {
    const arg = c.slice(5).trim().toLowerCase();
    const alias = { ya: "on", otomatis: "on", true: "on", tanya: "off", manual: "off", mati: "off" };
    const mode = alias[arg] || arg;
    if (["on", "aman", "off"].includes(mode)) {
      autoMode = mode;
      try {
        fs.writeFileSync(AUTO_FILE, mode);
      } catch {}
    } else if (arg) {
      console.log("Pilihan: /auto on, /auto aman, /auto off");
      continue;
    }
    console.log(
      `Izin aksi sekarang: ${{ on: "OTOMATIS, semua langsung ya (kamu tidak perlu menunggu)", aman: "OTOMATIS kecuali aksi merusak (timpa file, hapus, tutup jendela, pindah) yang tetap bertanya", off: "SELALU TANYA y/n" }[autoMode]}`
    );
    continue;
  }
  if (c === "/fast" || c.startsWith("/fast ")) {
    const arg = c.slice(5).trim().toLowerCase();
    if (arg === "on") FAST = true;
    else if (arg === "off") FAST = false;
    console.log(`Jalur cepat (tanpa AI untuk perintah umum): ${FAST ? "AKTIF" : "MATI"}. Ketik /fast on atau /fast off.`);
    continue;
  }
  if (c === "/reset") {
    history.length = 0;
    extraGroups.clear();
    console.log("Percakapan dilupakan.");
    continue;
  }
  const t0 = Date.now();
  const detik = () => ((Date.now() - t0) / 1000).toFixed(1);
  if (FAST) {
    let r = null;
    try {
      r = await tryFastCommand(c);
    } catch (e) {
      console.log(`  (jalur cepat gagal: ${String(e.message).slice(0, 160)}. Diserahkan ke AI...)`);
    }
    if (r != null) {
      console.log(`\n[cepat] ${r}\n(${detik()} dtk, tanpa AI)`);
      history.push({ role: "user", content: c }, { role: "assistant", content: `[jalur cepat] ${String(r).slice(0, 500)}` });
      trimHistory();
      continue;
    }
  }
  try {
    await runTask(c);
    console.log(`(selesai dalam ${detik()} dtk)`);
  } catch (e) {
    console.error("Gagal:", e.message);
  }
}
await shutdownBrowser();
rl.close();
