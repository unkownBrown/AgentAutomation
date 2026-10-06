// agent.js v2 - Agent kontrol PC Windows: perintah teks -> 9Router (LLM) -> browser + desktop
import { chromium } from "playwright";
import fs from "fs";
import os from "os";
import path from "path";
import readline from "readline/promises";
import { execFile } from "child_process";

const BASE_URL = process.env.ROUTER_URL || "http://localhost:20128/v1";
const API_KEY = process.env.ROUTER_KEY;
const MODEL = process.env.ROUTER_MODEL || "bot-combo";
const SAFE_DIR = path.resolve(process.env.SAFE_DIR || "./upload-folder");
const CONFIRM = process.env.CONFIRM !== "0"; // minta izin sebelum aksi fisik (klik, ketik, buka)
const MAX_STEPS = 30;
const HOME = os.homedir();
const SEARCH_ROOTS = [HOME, ...(process.env.SEARCH_ROOTS ? process.env.SEARCH_ROOTS.split(";") : [])];

if (!API_KEY) {
  console.error("ROUTER_KEY belum diisi.");
  process.exit(1);
}
fs.mkdirSync(SAFE_DIR, { recursive: true });

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Browser dengan profil permanen: login sekali, sesi tersimpan
const context = await chromium.launchPersistentContext("./browser-profile", {
  headless: false,
  args: ["--autoplay-policy=no-user-gesture-required"],
});
const page = context.pages()[0] || (await context.newPage());

function safePath(name) {
  const full = path.resolve(SAFE_DIR, name);
  if (!full.startsWith(SAFE_DIR)) throw new Error("File di luar folder yang diizinkan");
  return full;
}

async function ask(msg) {
  if (!CONFIRM) return true;
  const a = await rl.question(`\n[IZIN] ${msg} (y/n): `);
  return a.trim().toLowerCase() === "y";
}

// ===== Helper PowerShell (kontrol desktop Windows tanpa library tambahan) =====
function ps(script, env = {}) {
  const encoded = Buffer.from(script, "utf16le").toString("base64");
  return new Promise((resolve, reject) => {
    execFile(
      "powershell",
      ["-NoProfile", "-NonInteractive", "-EncodedCommand", encoded],
      { env: { ...process.env, ...env }, timeout: 30000, maxBuffer: 20 * 1024 * 1024 },
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

function findDirs(name, root, depth, out) {
  if (depth < 0 || out.length >= 10) return;
  let entries;
  try {
    entries = fs.readdirSync(root, { withFileTypes: true });
  } catch {
    return;
  }
  for (const e of entries) {
    if (!e.isDirectory()) continue;
    if (["node_modules", "AppData", ".git"].includes(e.name) || e.name.startsWith("$")) continue;
    const full = path.join(root, e.name);
    if (e.name.toLowerCase().includes(name.toLowerCase())) out.push(full);
    findDirs(name, full, depth - 1, out);
  }
}

// ===== "Tangan" agent =====
const impl = {
  // --- Desktop: file & folder ---
  find_folder: async ({ name }) => {
    const out = [];
    for (const root of SEARCH_ROOTS) findDirs(String(name), root, 4, out);
    return out.length ? out.join("\n") : "Tidak ditemukan";
  },

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

  open_url: async ({ url }) => {
    await page.goto(url, { waitUntil: "domcontentloaded" });
    return "Terbuka: " + (await page.title());
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

  youtube_play: async ({ query, pick = 1 }) => {
    await page.bringToFront();
    await page.goto("https://www.youtube.com/results?search_query=" + encodeURIComponent(String(query)), {
      waitUntil: "domcontentloaded",
    });
    await page.waitForSelector("ytd-video-renderer a#video-title", { timeout: 20000 });
    const list = await page.$$eval("ytd-video-renderer a#video-title", (els) =>
      els.slice(0, 5).map((e) => ({ title: e.textContent.trim(), href: e.href }))
    );
    if (!list.length) return "Tidak ada hasil";
    const idx = Math.min(Math.max(Number(pick) || 1, 1), list.length) - 1;
    await page.goto(list[idx].href, { waitUntil: "domcontentloaded" });
    await sleep(2500);
    await page.evaluate(() => {
      const v = document.querySelector("video");
      if (v && v.paused) v.play().catch(() => {});
    });
    const others = list.map((v, i) => `${i + 1}. ${v.title}`).join("\n");
    return `Memutar #${idx + 1}: ${list[idx].title}\nHasil pencarian:\n${others}`;
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

  upload_file: async ({ selector, filename }) => {
    const full = safePath(filename);
    if (!(await ask(`Upload file: ${filename}`))) return "Dibatalkan user";
    await page.setInputFiles(selector, full);
    return "ok, file dipilih";
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

const tools = [
  fn("find_folder", "Cari folder di PC berdasarkan nama (sebagian nama cukup)", { name: str("Nama folder") }),
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
  fn("open_url", "Buka website di browser Playwright (untuk otomasi web)", { url: str("URL lengkap") }),
  fn("inspect_page", "Daftar tombol/input di halaman browser untuk mencari CSS selector"),
  fn(
    "youtube_play",
    "Cari video di YouTube lalu OTOMATIS memutar hasil pilihan di browser agent. Pakai ini untuk semua permintaan nonton/cari video/lagu di YouTube.",
    { query: str("Kata kunci pencarian"), pick: num("Urutan hasil yang diputar, 1-5 (default 1)") },
    ["pick"]
  ),
  fn("done", "Panggil ini jika tugas SELESAI, atau jika perlu bertanya/melapor ke user", { message: str("Pesan singkat untuk user") }),
  fn("get_page_text", "Baca teks halaman browser saat ini"),
  fn("type_text", "Isi kolom teks di browser", { selector: str("CSS selector"), text: str("Teks") }),
  fn("click", "Klik elemen di browser", { selector: str("CSS selector") }),
  fn("upload_file", "Upload file dari folder upload ke input file di browser", {
    selector: str("CSS selector input[type=file]"),
    filename: str("Nama file di folder upload"),
  }),
];

const SYSTEM = `Kamu agent yang mengontrol PC Windows milik user dan browser. Kerjakan perintah user dengan memanggil tool.
ATURAN PENTING:
- Kamu HARUS selalu memanggil tool di setiap langkah. JANGAN pernah menulis rencana, narasi, atau "saya akan ...". Langsung panggil tool-nya.
- Setelah tugas selesai (atau perlu bertanya ke user), panggil tool done dengan pesan singkat.
- Nonton/cari video/lagu di YouTube: langsung panggil youtube_play dengan kata kunci dari user. Jika judul yang diputar kurang cocok, panggil lagi dengan pick lain.
- Tafsirkan perintah singkat/typo user dengan wajar, jangan bertanya hal yang bisa ditebak.
- Folder/file di PC: pakai find_folder untuk mencari, lalu open_path untuk membuka.
- Aplikasi/jendela di PC: screenshot dulu untuk melihat layar, lalu click_screen/type_desktop/press_keys, lalu screenshot lagi untuk memeriksa hasil.
- Koordinat klik harus dari screenshot terakhir.
- Untuk otomasi website pakai tool browser (open_url, inspect_page, type_text, click, upload_file). Selalu inspect_page sebelum klik.
- Jika buntu, butuh login, atau ragu, berhenti dan tanya user.
- Jawab dalam Bahasa Indonesia, singkat. Jangan mengarang hasil; laporkan apa adanya.`;

let useToolChoice = true; // paksa model selalu memanggil tool; dimatikan otomatis jika provider menolak
async function callLLM(messages) {
  const body = { model: MODEL, messages, tools, stream: true };
  if (useToolChoice) body.tool_choice = "required";
  const res = await fetch(`${BASE_URL}/chat/completions`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${API_KEY}` },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const errText = await res.text();
    if (useToolChoice && res.status === 400) {
      useToolChoice = false;
      return callLLM(messages);
    }
    throw new Error(`9Router error ${res.status}: ${errText}`);
  }

  const raw = await res.text();
  if (!raw.trimStart().startsWith("data:")) {
    return JSON.parse(raw).choices[0].message;
  }

  let content = "";
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

  const msg = { role: "assistant", content: content || null };
  const valid = calls.filter(Boolean).map((c, i) => ({ ...c, id: c.id || `call_${i}` }));
  if (valid.length) msg.tool_calls = valid;
  return msg;
}

async function runTask(command) {
  const messages = [
    { role: "system", content: SYSTEM },
    { role: "user", content: command },
  ];
  let nudges = 0;

  for (let step = 1; step <= MAX_STEPS; step++) {
    const msg = await callLLM(messages);
    messages.push(msg);

    if (!msg.tool_calls?.length) {
      // Model cuma menulis teks/rencana tanpa memanggil tool -> paksa panggil tool
      if (nudges < 3) {
        nudges++;
        messages.push({
          role: "user",
          content: "Kamu harus memanggil tool. Jangan menulis teks biasa. Langsung panggil tool yang sesuai, atau panggil done jika tugas sudah selesai.",
        });
        continue;
      }
      console.log("\nAgent:", msg.content);
      return;
    }

    for (const call of msg.tool_calls) {
      const name = call.function.name;
      if (name === "done") {
        let m = "";
        try {
          m = JSON.parse(call.function.arguments || "{}").message || "";
        } catch {}
        console.log("\nAgent:", m || "Selesai.");
        return;
      }
      let result;
      try {
        const args = JSON.parse(call.function.arguments || "{}");
        console.log(`[${step}] ${name}`, args);
        if (!impl[name]) throw new Error("Tool tidak dikenal: " + name);
        result = await impl[name](args);
      } catch (e) {
        result = "ERROR: " + e.message;
      }
      messages.push({ role: "tool", tool_call_id: call.id, content: String(result) });
    }

    // Kirim screenshot (jika ada) sebagai gambar agar model bisa "melihat"
    if (pendingImages.length) {
      messages.push({
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
}

console.log(`Agent siap. Folder upload: ${SAFE_DIR}`);
console.log(`Izin sebelum aksi: ${CONFIRM ? "AKTIF" : "MATI"}. Tekan Ctrl+C kapan saja untuk menghentikan.`);
console.log('Ketik perintah dalam bahasa biasa (atau "exit").');
while (true) {
  const cmd = await rl.question("\nPerintah> ");
  if (cmd.trim() === "exit") break;
  if (!cmd.trim()) continue;
  try {
    await runTask(cmd);
  } catch (e) {
    console.error("Gagal:", e.message);
  }
}
await context.close();
rl.close();
