@echo off
setlocal EnableExtensions
chcp 65001 >nul
title Agent Automation
set "SELF=%~f0"
set "EMBED_VER=6"

rem ======================= PENGATURAN OWNER =======================
rem Alamat update bawaan (repo GitHub owner). User tidak perlu mengisi apa pun.
set "DEFAULT_UPDATE_URL=https://raw.githubusercontent.com/unkownBrown/AgentAutomation/main"
rem Isi 2 baris di bawah jika akses 9Router DISEDIAKAN OWNER (server bersama).
rem Contoh URL : https://ai.domainkamu.com/v1
rem Jika keduanya diisi, user tidak perlu memasang 9Router atau memasukkan key.
set "OWNER_ROUTER_URL="
set "OWNER_ROUTER_KEY="
rem ================================================================

rem ============================================================
rem  AGENT AUTOMATION - All-in-one (folder + file + setup + update + run)
rem  Pemakaian biasa : klik dua kali file ini, di folder mana pun
rem  Ganti API key   : start-agent.bat reset
rem  Ganti URL update: start-agent.bat seturl  (lanjutan, biasanya tidak perlu)
rem  Matikan update  : tulis AUTO_UPDATE=0 di config.bat
rem ============================================================

rem ---------- Tentukan folder kerja ----------
for %%I in ("%~dp0.") do set "HERE=%%~fI"
for %%I in ("%~dp0.") do set "HERENAME=%%~nxI"
if /i "%HERENAME%"=="Agent Automation" goto USE_HERE
set "APPDIR=%HERE%\Agent Automation"
goto DIR_SET
:USE_HERE
set "APPDIR=%HERE%"
:DIR_SET

rem Pastikan folder Node.js dan npm global terbaca di sesi ini
set "PATH=%PATH%;%ProgramFiles%\nodejs;%APPDATA%\npm"

echo.
echo ==========================================
echo        AGENT AUTOMATION - AUTO SETUP
echo ==========================================
echo.

rem ---------- 1. Folder, konfigurasi, file agent ----------
echo [1/7] Menyiapkan folder dan file agent...
if not exist "%APPDIR%" mkdir "%APPDIR%"
if /i "%~1"=="reset" del "%APPDIR%\config.bat" 2>nul
if /i "%~1"=="reset" echo     Key lama dihapus. Kamu akan diminta memasukkan key lagi.
if exist "%APPDIR%\config.bat" call "%APPDIR%\config.bat"

set "NEED_EXTRACT="
if not exist "%APPDIR%\agent.js" set "NEED_EXTRACT=1"
if not exist "%APPDIR%\package.json" set "NEED_EXTRACT=1"
set "LOCAL_EMBED=0"
if exist "%APPDIR%\embed.ver" set /p LOCAL_EMBED=<"%APPDIR%\embed.ver"
if %EMBED_VER% GTR %LOCAL_EMBED% set "NEED_EXTRACT=1"
:EXTRACT_DECIDED
if not defined NEED_EXTRACT goto EXTRACT_SKIP
powershell -NoProfile -ExecutionPolicy Bypass -Command "$l=Get-Content -LiteralPath $env:SELF; foreach($n in 'agent.js','package.json'){ $t='::B64:'+$n+':'; $b=($l | Where-Object {$_.StartsWith($t)} | ForEach-Object {$_.Substring($t.Length).Trim()}) -join ''; [IO.File]::WriteAllBytes((Join-Path $env:APPDIR $n),[Convert]::FromBase64String($b)) }"
if errorlevel 1 goto FAIL_EXTRACT
> "%APPDIR%\embed.ver" echo %EMBED_VER%
:EXTRACT_SKIP
if not exist "%APPDIR%\agent.js" goto FAIL_EXTRACT
if not exist "%APPDIR%\package.json" goto FAIL_EXTRACT
cd /d "%APPDIR%"
echo     Folder: %APPDIR%
echo     agent.js dan package.json siap.

if /i "%~1"=="seturl" call :ASK_URL
if /i "%~1"=="seturl" call :SAVE_CONFIG

rem ---------- 2. Node.js ----------
echo [2/7] Memeriksa Node.js...
where node >nul 2>&1
if not errorlevel 1 goto NODE_OK
echo     Node.js belum terpasang. Menginstall otomatis, tunggu sebentar...
where winget >nul 2>&1
if errorlevel 1 goto NO_WINGET
winget install -e --id OpenJS.NodeJS.LTS --silent --accept-package-agreements --accept-source-agreements
where node >nul 2>&1
if errorlevel 1 goto NODE_RESTART
:NODE_OK
for /f "delims=" %%v in ('node -v') do echo     Node.js %%v siap.

rem ---------- 3. Pembaruan otomatis ----------
:STEP_UPDATE
set "NEED_INSTALL="
set "UPD_URL=%UPDATE_URL%"
if not defined UPD_URL set "UPD_URL=%DEFAULT_UPDATE_URL%"
echo [3/7] Memeriksa pembaruan...
if "%AUTO_UPDATE%"=="0" goto UPDATE_DISABLED
curl.exe -fsSL --ssl-no-revoke --max-time 15 -o ".remote-version" "%UPD_URL%/version.txt" 2>".curl-err"
if errorlevel 1 goto UPDATE_OFFLINE
set "LOCALVER=0"
if exist "version.txt" set /p LOCALVER=<"version.txt"
set "REMOTEVER="
set /p REMOTEVER=<".remote-version"
if not defined REMOTEVER goto UPDATE_OFFLINE
call :SHOW_NOTICE
if "%LOCALVER%"=="%REMOTEVER%" goto UPDATE_SAME
echo.
echo  ======================================================
echo    UPDATE TERSEDIA: versi %REMOTEVER% ^(versi kamu: %LOCALVER%^)
echo    Memperbarui otomatis, mohon tunggu...
echo  ======================================================
if exist ".remote-changelog" del ".remote-changelog"
curl.exe -fsSL --ssl-no-revoke --max-time 10 -o ".remote-changelog" "%UPD_URL%/changelog.txt" 2>nul
copy /y "package.json" "package.json.bak" >nul
set "UPDATE_FAILED="
curl.exe -fsSL --ssl-no-revoke --max-time 15 -o ".remote-files" "%UPD_URL%/files.txt" 2>nul
if errorlevel 1 goto UPDATE_FAIL
for /f "usebackq delims=" %%F in (".remote-files") do call :DL_FILE "%%F"
if defined UPDATE_FAILED goto UPDATE_FAIL
copy /y ".remote-version" "version.txt" >nul
fc "package.json" "package.json.bak" >nul 2>&1
if errorlevel 1 set "NEED_INSTALL=1"
echo     Pembaruan selesai. Sekarang versi %REMOTEVER%.
if exist ".remote-changelog" copy /y ".remote-changelog" "changelog.txt" >nul
echo     Daftar fitur baru akan tampil saat agent dibuka.
goto UPDATE_DONE
:UPDATE_SAME
echo     Sudah versi terbaru: %LOCALVER%
goto UPDATE_DONE
:UPDATE_DISABLED
echo     Update otomatis dimatikan ^(AUTO_UPDATE=0^).
goto UPDATE_DONE
:UPDATE_OFFLINE
echo     Tidak bisa cek pembaruan, melanjutkan dengan versi lokal.
if exist ".curl-err" for /f "usebackq delims=" %%E in (".curl-err") do echo     Penyebab: %%E
goto UPDATE_DONE
:UPDATE_FAIL
echo     Pembaruan gagal, melanjutkan dengan versi lokal. Akan dicoba lagi lain kali.
:UPDATE_DONE

rem ---------- 4. Dependensi ----------
echo [4/7] Memeriksa dependensi...
if defined NEED_INSTALL goto DO_INSTALL
if exist "node_modules\playwright" goto DEPS_OK
:DO_INSTALL
echo     Menginstall dependensi, tunggu sebentar...
call npm install
if errorlevel 1 goto FAIL
:DEPS_OK
echo     Dependensi siap.

rem ---------- 5. Browser Chromium ----------
echo [5/7] Memeriksa browser...
if exist ".chromium-ok" goto CHROMIUM_OK
if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" goto BROWSER_FOUND
if exist "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" goto BROWSER_FOUND
if exist "%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe" goto BROWSER_FOUND
if exist "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" goto BROWSER_FOUND
if exist "%ProgramFiles%\Microsoft\Edge\Application\msedge.exe" goto BROWSER_FOUND
echo     Chrome atau Edge tidak ditemukan. Mengunduh Chromium cadangan, hanya sekali...
call npx playwright install chromium
if errorlevel 1 goto FAIL
echo ok> ".chromium-ok"
goto CHROMIUM_OK
:BROWSER_FOUND
echo     Chrome atau Edge ditemukan. Dipakai sebagai browser agent.
goto BROWSER_DONE
:CHROMIUM_OK
echo     Chromium cadangan siap.
:BROWSER_DONE

rem ---------- 6. 9Router ----------
echo [6/7] Memeriksa 9Router...
if not defined OWNER_ROUTER_URL goto ROUTER_LOCAL
echo     Memakai server 9Router dari owner. Pemasangan lokal dilewati.
goto KEY_STEP
:ROUTER_LOCAL
where 9router >nul 2>&1
if not errorlevel 1 goto ROUTER_INSTALLED
echo     9Router belum terpasang. Menginstall...
call npm install -g 9router
if errorlevel 1 goto FAIL
:ROUTER_INSTALLED
netstat -ano | findstr ":20128 " | findstr "LISTENING" >nul
if not errorlevel 1 goto ROUTER_RUNNING
echo     Menjalankan 9Router di latar belakang...
start "9Router" /min cmd /c 9router
set /a TRIES=0
:WAIT_ROUTER
timeout /t 2 /nobreak >nul
netstat -ano | findstr ":20128 " | findstr "LISTENING" >nul
if not errorlevel 1 goto ROUTER_RUNNING
set /a TRIES+=1
if %TRIES% LSS 20 goto WAIT_ROUTER
echo     [PERINGATAN] 9Router belum merespons. Coba buka http://localhost:20128/dashboard manual.
goto KEY_STEP
:ROUTER_RUNNING
echo     9Router berjalan di http://localhost:20128

rem ---------- 7. API key ----------
:KEY_STEP
echo [7/7] Memeriksa API key...
if defined OWNER_ROUTER_URL set "ROUTER_URL=%OWNER_ROUTER_URL%"
if not defined OWNER_ROUTER_KEY goto KEY_NOT_OWNER
set "ROUTER_KEY=%OWNER_ROUTER_KEY%"
echo     Memakai akses AI dari owner. Tidak perlu memasukkan key.
goto KEY_VALIDATE
:KEY_NOT_OWNER
if exist "config.bat" call "config.bat"
if defined ROUTER_KEY goto KEY_LOADED

echo.
echo     Masukkan API key 9Router ^(dari owner, atau dari dashboard 9Router lokal^).
echo     Dashboard lokal: http://localhost:20128/dashboard  menu  Endpoint ^& Key
echo.
set /p "ROUTER_KEY=    API Key: "
if not defined ROUTER_KEY goto KEY_STEP
call :SAVE_CONFIG
echo     Key tersimpan. Berikutnya tidak perlu input lagi.
goto KEY_VALIDATE

:KEY_LOADED
echo     Key ditemukan dari penyimpanan.

:KEY_VALIDATE
set "HTTPCODE="
if not defined ROUTER_URL set "ROUTER_URL=http://localhost:20128/v1"
for /f %%i in ('curl.exe -s -o nul --max-time 15 -w "%%{http_code}" -H "Authorization: Bearer %ROUTER_KEY%" %ROUTER_URL%/models 2^>nul') do set "HTTPCODE=%%i"
if "%HTTPCODE%"=="401" goto BAD_KEY
if "%HTTPCODE%"=="403" goto BAD_KEY
if "%HTTPCODE%"=="000" echo     [PERINGATAN] Server 9Router belum bisa dihubungi. Cek internet atau hubungi owner.
goto RUN_AGENT

:BAD_KEY
if defined OWNER_ROUTER_KEY goto OWNER_REJECTED
echo.
echo     [PERINGATAN] Key ditolak oleh 9Router. Kemungkinan salah atau sudah dihapus.
set "ROUTER_KEY="
set /p "ROUTER_KEY=    Ketik key yang benar, atau tekan Enter untuk lanjut tanpa mengganti: "
if not defined ROUTER_KEY goto RELOAD_OLD
call :SAVE_CONFIG
echo     Key baru tersimpan.
goto RUN_AGENT
:RELOAD_OLD
if exist "config.bat" call "config.bat"
goto RUN_AGENT

rem ---------- Jalankan agent ----------
:RUN_AGENT
if not defined ROUTER_MODEL set "ROUTER_MODEL=bot-combo"
if not defined SAFE_DIR set "SAFE_DIR=%APPDIR%\upload-folder"
echo.
echo ==========================================
echo   Semua siap. Menjalankan agent...
echo   Tekan Ctrl+C kapan saja untuk berhenti.
echo ==========================================
echo.
node agent.js
if %errorlevel% EQU 42 goto STEP_UPDATE
echo.
echo Agent berhenti.
pause
exit /b 0

rem ---------- Subroutine: simpan konfigurasi ----------
:SAVE_CONFIG
if not defined CONFIRM set "CONFIRM=1"
if not defined AUTO_UPDATE set "AUTO_UPDATE=1"
if not defined ROUTER_MODEL set "ROUTER_MODEL=bot-combo"
if not defined SAFE_DIR set "SAFE_DIR=%APPDIR%\upload-folder"
> "config.bat" echo set "ROUTER_KEY=%ROUTER_KEY%"
>> "config.bat" echo set "ROUTER_MODEL=%ROUTER_MODEL%"
>> "config.bat" echo set "SAFE_DIR=%SAFE_DIR%"
>> "config.bat" echo set "CONFIRM=%CONFIRM%"
>> "config.bat" echo set "AUTO_UPDATE=%AUTO_UPDATE%"
if defined UPDATE_URL >> "config.bat" echo set "UPDATE_URL=%UPDATE_URL%"
exit /b 0

rem ---------- Subroutine: tanya URL update ----------
:ASK_URL
echo.
echo     Ganti alamat update ^(lanjutan^). Alamat bawaan owner sudah aktif otomatis.
echo     Contoh: https://raw.githubusercontent.com/NAMAKAMU/NAMAREPO/main
echo     Tekan Enter untuk membatalkan.
set "NEWURL="
set /p "NEWURL=    URL update: "
if not defined NEWURL exit /b 0
if /i not "%NEWURL:~0,8%"=="https://" goto ASK_URL_BAD
if "%NEWURL:~-1%"=="/" set "NEWURL=%NEWURL:~0,-1%"
set "UPDATE_URL=%NEWURL%"
echo     URL update tersimpan.
exit /b 0
:ASK_URL_BAD
echo     URL harus diawali https:// - dilewati.
exit /b 0

rem ---------- Subroutine: pengumuman dari owner ----------
:SHOW_NOTICE
if exist ".remote-notice" del ".remote-notice"
curl.exe -fsSL --ssl-no-revoke --max-time 10 -o ".remote-notice" "%UPD_URL%/notice.txt" 2>nul
if errorlevel 1 exit /b 0
if not exist ".remote-notice" exit /b 0
set "NSIZE=0"
for %%A in (".remote-notice") do set "NSIZE=%%~zA"
if %NSIZE% LEQ 2 exit /b 0
echo.
echo  ================== PENGUMUMAN DARI OWNER ==================
powershell -NoProfile -Command "[Console]::OutputEncoding=[Text.Encoding]::UTF8; Get-Content -LiteralPath '.remote-notice' -TotalCount 15 -Encoding UTF8 | ForEach-Object { '  ' + $_ }"
echo  ===========================================================
echo.
exit /b 0

rem ---------- Subroutine: daftar perubahan versi baru ----------
:SHOW_CHANGELOG
if not exist ".remote-changelog" exit /b 0
set "CSIZE=0"
for %%A in (".remote-changelog") do set "CSIZE=%%~zA"
if %CSIZE% LEQ 2 exit /b 0
echo.
echo     Yang baru di versi ini:
powershell -NoProfile -Command "[Console]::OutputEncoding=[Text.Encoding]::UTF8; Get-Content -LiteralPath '.remote-changelog' -TotalCount 20 -Encoding UTF8 | ForEach-Object { '     ' + $_ }"
echo.
exit /b 0

rem ---------- Subroutine: unduh satu file update ----------
:DL_FILE
set "FN=%~1"
if not defined FN exit /b 0
if not "%FN%"=="%FN:\=%" exit /b 0
if not "%FN%"=="%FN:/=%" exit /b 0
if not "%FN%"=="%FN:..=%" exit /b 0
if not "%FN%"=="%FN::=%" exit /b 0
if /i "%FN%"=="config.bat" exit /b 0
if /i "%FN%"=="start-agent.bat" exit /b 0
echo     Mengunduh %FN%
curl.exe -fsSL --ssl-no-revoke --max-time 60 -o "%FN%.new" "%UPD_URL%/%FN%" 2>nul
if errorlevel 1 goto DL_FAIL
move /y "%FN%.new" "%FN%" >nul
exit /b 0
:DL_FAIL
if exist "%FN%.new" del "%FN%.new"
set "UPDATE_FAILED=1"
exit /b 1

rem ---------- Error handler ----------
:NO_WINGET
echo.
echo     winget tidak ditemukan di PC ini.
echo     Install Node.js LTS secara manual dari https://nodejs.org lalu jalankan file ini lagi.
start https://nodejs.org
pause
exit /b 1

:NODE_RESTART
echo.
echo     Node.js sudah terpasang tetapi belum terbaca di jendela ini.
echo     Tutup jendela ini, lalu klik dua kali start-agent.bat sekali lagi.
pause
exit /b 0

:OWNER_REJECTED
echo.
echo     [ERROR] Akses ditolak oleh server owner. Key mungkin sudah dicabut.
echo     Hubungi owner untuk mendapatkan start-agent.bat yang baru.
pause
exit /b 1

:FAIL_EXTRACT
echo.
echo     Gagal membuat folder atau file agent di: %APPDIR%
echo     Coba pindahkan start-agent.bat ke folder yang bisa ditulis, misalnya Desktop atau Documents.
pause
exit /b 1

:FAIL
echo.
echo     Setup gagal. Baca pesan error di atas, lalu coba lagi.
pause
exit /b 1

rem ============ DATA TERSEMBUNYI - JANGAN DIHAPUS / DIUBAH ============
::B64:agent.js:Ly8gYWdlbnQuanMgdjIgLSBBZ2VudCBrb250cm9sIFBDIFdpbmRvd3M6IHBlcmludGFoIHRla3MgLT4gOVJvdXRlciAoTExNKSAtPiBicm93c2VyICsgZGVza3RvcAppbXBvcnQgeyBjaHJvbWl1bSB9IGZyb20gInBsYXl3cmlnaHQiOwppbXBvcnQgZnMgZnJvbSAi
::B64:agent.js:ZnMiOwppbXBvcnQgb3MgZnJvbSAib3MiOwppbXBvcnQgcGF0aCBmcm9tICJwYXRoIjsKaW1wb3J0IHJlYWRsaW5lIGZyb20gInJlYWRsaW5lL3Byb21pc2VzIjsKaW1wb3J0IHsgZXhlY0ZpbGUsIHNwYXduIH0gZnJvbSAiY2hpbGRfcHJvY2VzcyI7CmltcG9ydCB7
::B64:agent.js:IHBpcGVsaW5lIH0gZnJvbSAic3RyZWFtL3Byb21pc2VzIjsKaW1wb3J0IHsgUmVhZGFibGUgfSBmcm9tICJzdHJlYW0iOwoKY29uc3QgQkFTRV9VUkwgPSBwcm9jZXNzLmVudi5ST1VURVJfVVJMIHx8ICJodHRwOi8vbG9jYWxob3N0OjIwMTI4L3YxIjsKY29uc3Qg
::B64:agent.js:QVBJX0tFWSA9IHByb2Nlc3MuZW52LlJPVVRFUl9LRVk7CmNvbnN0IE1PREVMID0gcHJvY2Vzcy5lbnYuUk9VVEVSX01PREVMIHx8ICJib3QtY29tYm8iOwpjb25zdCBTQUZFX0RJUiA9IHBhdGgucmVzb2x2ZShwcm9jZXNzLmVudi5TQUZFX0RJUiB8fCAiLi91cGxv
::B64:agent.js:YWQtZm9sZGVyIik7CmNvbnN0IENPTkZJUk0gPSBwcm9jZXNzLmVudi5DT05GSVJNICE9PSAiMCI7IC8vIG1pbnRhIGl6aW4gc2ViZWx1bSBha3NpIGZpc2lrIChrbGlrLCBrZXRpaywgYnVrYSkKY29uc3QgTUFYX1NURVBTID0gMzA7CmNvbnN0IEhPTUUgPSBvcy5o
::B64:agent.js:b21lZGlyKCk7CmNvbnN0IFNFQVJDSF9ST09UUyA9IFtIT01FLCAuLi4ocHJvY2Vzcy5lbnYuU0VBUkNIX1JPT1RTID8gcHJvY2Vzcy5lbnYuU0VBUkNIX1JPT1RTLnNwbGl0KCI7IikgOiBbXSldOwpmb3IgKGNvbnN0IEwgb2YgIkRFRkdISUpLTE1OT1BRUlNUVVZX
::B64:agent.js:WFlaIikgewogIC8vIERyaXZlIGxhaW4gKEQ6LCBFOiwgZmxhc2hkaXNrLCBkbGwpIGlrdXQgZGljYXJpIG90b21hdGlzCiAgdHJ5IHsKICAgIGlmIChmcy5leGlzdHNTeW5jKGAke0x9OlxcYCkpIFNFQVJDSF9ST09UUy5wdXNoKGAke0x9OlxcYCk7CiAgfSBjYXRj
::B64:agent.js:aCB7fQp9CgppZiAoIUFQSV9LRVkpIHsKICBjb25zb2xlLmVycm9yKCJST1VURVJfS0VZIGJlbHVtIGRpaXNpLiIpOwogIHByb2Nlc3MuZXhpdCgxKTsKfQpmcy5ta2RpclN5bmMoU0FGRV9ESVIsIHsgcmVjdXJzaXZlOiB0cnVlIH0pOwoKY29uc3QgcmwgPSByZWFk
::B64:agent.js:bGluZS5jcmVhdGVJbnRlcmZhY2UoeyBpbnB1dDogcHJvY2Vzcy5zdGRpbiwgb3V0cHV0OiBwcm9jZXNzLnN0ZG91dCB9KTsKY29uc3Qgc2xlZXAgPSAobXMpID0+IG5ldyBQcm9taXNlKChyKSA9PiBzZXRUaW1lb3V0KHIsIG1zKSk7CgovLyA9PT09PSBQZW1iZXJp
::B64:agent.js:dGFodWFuIHVwZGF0ZSAoVVJMIGRpYmVyaWthbiBvdG9tYXRpcyBvbGVoIHN0YXJ0LWFnZW50LmJhdCkgPT09PT0KY29uc3QgVVBEX1VSTCA9IHByb2Nlc3MuZW52LlVQRF9VUkwgfHwgIiI7CmNvbnN0IGxvY2FsVmVyc2lvbiA9ICgpID0+IHsKICB0cnkgewogICAg
::B64:agent.js:cmV0dXJuIGZzLnJlYWRGaWxlU3luYygidmVyc2lvbi50eHQiLCAidXRmOCIpLnRyaW0oKSB8fCAiMCI7CiAgfSBjYXRjaCB7CiAgICByZXR1cm4gIjAiOwogIH0KfTsKbGV0IHBlbmRpbmdWZXJzaW9uID0gIiI7Cgphc3luYyBmdW5jdGlvbiBjaGVja1VwZGF0ZSgp
::B64:agent.js:IHsKICBpZiAoIVVQRF9VUkwgfHwgcHJvY2Vzcy5lbnYuQVVUT19VUERBVEUgPT09ICIwIikgcmV0dXJuOwogIHRyeSB7CiAgICBjb25zdCByZXMgPSBhd2FpdCBmZXRjaChgJHtVUERfVVJMfS92ZXJzaW9uLnR4dGAsIHsgc2lnbmFsOiBBYm9ydFNpZ25hbC50aW1l
::B64:agent.js:b3V0KDEwMDAwKSB9KTsKICAgIGlmICghcmVzLm9rKSByZXR1cm47CiAgICBjb25zdCByZW1vdGUgPSAoYXdhaXQgcmVzLnRleHQoKSkudHJpbSgpOwogICAgaWYgKHJlbW90ZSAmJiByZW1vdGUgIT09IGxvY2FsVmVyc2lvbigpICYmIHJlbW90ZSAhPT0gcGVuZGlu
::B64:agent.js:Z1ZlcnNpb24pIHsKICAgICAgcGVuZGluZ1ZlcnNpb24gPSByZW1vdGU7CiAgICAgIGNvbnNvbGUubG9nKGBcbioqKiBVUERBVEUgVEVSU0VESUE6IHZlcnNpICR7cmVtb3RlfSAodmVyc2kga2FtdTogJHtsb2NhbFZlcnNpb24oKX0pICoqKmApOwogICAgICBjb25z
::B64:agent.js:b2xlLmxvZygnICAgIEtldGlrICIvdXBkYXRlIiB1bnR1ayBtZW1wZXJiYXJ1aSBvdG9tYXRpcyBzZWthcmFuZy4nKTsKICAgIH0KICB9IGNhdGNoIHt9Cn0Kc2V0SW50ZXJ2YWwoY2hlY2tVcGRhdGUsIDE1ICogNjAgKiAxMDAwKS51bnJlZigpOwoKLy8gPT09PT0g
::B64:agent.js:QnJvd3NlcjogcGFrYWkgQ2hyb21lL0VkZ2UgQVNMSSAoYnVrYW4gQ2hyb21pdW0gYmF3YWFuIFBsYXl3cmlnaHQpID09PT09Ci8vIEFsYXNhbjogdmlkZW8gWW91VHViZSBidXR1aCBjb2RlYyBsZW5na2FwLCBkYW4gR29vZ2xlIG1lbWJsb2tpciBsb2dpbiBkaSBi
::B64:agent.js:cm93c2VyICJvdG9tYXRpcyIuCi8vIENocm9tZSBkaWphbGFua2FuIGJpYXNhIGRlbmdhbiBwb3J0IGRlYnVnLCBsYWx1IFBsYXl3cmlnaHQgbWVueWFtYnVuZyBrZSBzaXR1LgovLyBMb2dpbiB0ZXJzaW1wYW4gcGVybWFuZW4gZGkgZm9sZGVyIC4vY2hyb21lLXBy
::B64:agent.js:b2ZpbGUuCmNvbnN0IERFQlVHX1BPUlQgPSBOdW1iZXIocHJvY2Vzcy5lbnYuREVCVUdfUE9SVCB8fCA5MjIyKTsKY29uc3QgUFJPRklMRV9ESVIgPSBwYXRoLnJlc29sdmUoIi4vY2hyb21lLXByb2ZpbGUiKTsKCmZ1bmN0aW9uIGZpbmRCcm93c2VyRXhlKCkgewog
::B64:agent.js:IGNvbnN0IGxvY2FsID0gcHJvY2Vzcy5lbnYuTE9DQUxBUFBEQVRBIHx8ICIiOwogIGNvbnN0IHBmID0gcHJvY2Vzcy5lbnYuUHJvZ3JhbUZpbGVzIHx8ICJDOlxcUHJvZ3JhbSBGaWxlcyI7CiAgY29uc3QgcGY4NiA9IHByb2Nlc3MuZW52WyJQcm9ncmFtRmlsZXMo
::B64:agent.js:eDg2KSJdIHx8ICJDOlxcUHJvZ3JhbSBGaWxlcyAoeDg2KSI7CiAgcmV0dXJuIFsKICAgIHByb2Nlc3MuZW52LkNIUk9NRV9QQVRILAogICAgcGF0aC5qb2luKHBmLCAiR29vZ2xlIiwgIkNocm9tZSIsICJBcHBsaWNhdGlvbiIsICJjaHJvbWUuZXhlIiksCiAgICBw
::B64:agent.js:YXRoLmpvaW4ocGY4NiwgIkdvb2dsZSIsICJDaHJvbWUiLCAiQXBwbGljYXRpb24iLCAiY2hyb21lLmV4ZSIpLAogICAgcGF0aC5qb2luKGxvY2FsLCAiR29vZ2xlIiwgIkNocm9tZSIsICJBcHBsaWNhdGlvbiIsICJjaHJvbWUuZXhlIiksCiAgICBwYXRoLmpvaW4o
::B64:agent.js:cGY4NiwgIk1pY3Jvc29mdCIsICJFZGdlIiwgIkFwcGxpY2F0aW9uIiwgIm1zZWRnZS5leGUiKSwKICAgIHBhdGguam9pbihwZiwgIk1pY3Jvc29mdCIsICJFZGdlIiwgIkFwcGxpY2F0aW9uIiwgIm1zZWRnZS5leGUiKSwKICBdCiAgICAuZmlsdGVyKEJvb2xlYW4p
::B64:agent.js:CiAgICAuZmluZCgoeCkgPT4gZnMuZXhpc3RzU3luYyh4KSk7Cn0KCmFzeW5jIGZ1bmN0aW9uIGRlYnVnUG9ydFVwKCkgewogIHRyeSB7CiAgICBjb25zdCByID0gYXdhaXQgZmV0Y2goYGh0dHA6Ly8xMjcuMC4wLjE6JHtERUJVR19QT1JUfS9qc29uL3ZlcnNpb25g
::B64:agent.js:LCB7IHNpZ25hbDogQWJvcnRTaWduYWwudGltZW91dCgxNTAwKSB9KTsKICAgIHJldHVybiByLm9rOwogIH0gY2F0Y2ggewogICAgcmV0dXJuIGZhbHNlOwogIH0KfQoKbGV0IGJyb3dzZXJIYW5kbGUgPSBudWxsOwphc3luYyBmdW5jdGlvbiBvcGVuQnJvd3Nlcigp
::B64:agent.js:IHsKICBjb25zdCBleGUgPSBmaW5kQnJvd3NlckV4ZSgpOwogIGlmIChleGUpIHsKICAgIGlmICghKGF3YWl0IGRlYnVnUG9ydFVwKCkpKSB7CiAgICAgIHNwYXduKAogICAgICAgIGV4ZSwKICAgICAgICBbCiAgICAgICAgICBgLS1yZW1vdGUtZGVidWdnaW5nLXBv
::B64:agent.js:cnQ9JHtERUJVR19QT1JUfWAsCiAgICAgICAgICBgLS11c2VyLWRhdGEtZGlyPSR7UFJPRklMRV9ESVJ9YCwKICAgICAgICAgICItLW5vLWZpcnN0LXJ1biIsCiAgICAgICAgICAiLS1uby1kZWZhdWx0LWJyb3dzZXItY2hlY2siLAogICAgICAgICAgIi0tYXV0b3Bs
::B64:agent.js:YXktcG9saWN5PW5vLXVzZXItZ2VzdHVyZS1yZXF1aXJlZCIsCiAgICAgICAgICAiYWJvdXQ6YmxhbmsiLAogICAgICAgIF0sCiAgICAgICAgeyBkZXRhY2hlZDogdHJ1ZSwgc3RkaW86ICJpZ25vcmUiIH0KICAgICAgKS51bnJlZigpOwogICAgICBmb3IgKGxldCBp
::B64:agent.js:ID0gMDsgaSA8IDMwICYmICEoYXdhaXQgZGVidWdQb3J0VXAoKSk7IGkrKykgYXdhaXQgc2xlZXAoNTAwKTsKICAgIH0KICAgIGlmIChhd2FpdCBkZWJ1Z1BvcnRVcCgpKSB7CiAgICAgIGJyb3dzZXJIYW5kbGUgPSBhd2FpdCBjaHJvbWl1bS5jb25uZWN0T3ZlckNE
::B64:agent.js:UChgaHR0cDovLzEyNy4wLjAuMToke0RFQlVHX1BPUlR9YCk7CiAgICAgIGNvbnNvbGUubG9nKGBCcm93c2VyOiAke3BhdGguYmFzZW5hbWUoZXhlKX0gKGxvZ2luIHRlcnNpbXBhbiBkaSAke1BST0ZJTEVfRElSfSlgKTsKICAgICAgcmV0dXJuIGJyb3dzZXJIYW5k
::B64:agent.js:bGUuY29udGV4dHMoKVswXSB8fCAoYXdhaXQgYnJvd3NlckhhbmRsZS5uZXdDb250ZXh0KCkpOwogICAgfQogIH0KICBjb25zb2xlLmxvZygiQ2hyb21lL0VkZ2UgdGlkYWsgZGl0ZW11a2FuLCBtZW1ha2FpIENocm9taXVtIGJhd2FhbiAodmlkZW8gZGFuIGxvZ2lu
::B64:agent.js:IEdvb2dsZSBtdW5na2luIGJlcm1hc2FsYWgpLiIpOwogIHJldHVybiBjaHJvbWl1bS5sYXVuY2hQZXJzaXN0ZW50Q29udGV4dCgiLi9icm93c2VyLXByb2ZpbGUiLCB7CiAgICBoZWFkbGVzczogZmFsc2UsCiAgICBhcmdzOiBbIi0tYXV0b3BsYXktcG9saWN5PW5v
::B64:agent.js:LXVzZXItZ2VzdHVyZS1yZXF1aXJlZCJdLAogICAgaWdub3JlRGVmYXVsdEFyZ3M6IFsiLS1lbmFibGUtYXV0b21hdGlvbiJdLAogIH0pOwp9Cgpjb25zdCBjb250ZXh0ID0gYXdhaXQgb3BlbkJyb3dzZXIoKTsKbGV0IHBhZ2UgPSBjb250ZXh0LnBhZ2VzKCkuZmlu
::B64:agent.js:ZCgoeCkgPT4gIXguaXNDbG9zZWQoKSkgfHwgKGF3YWl0IGNvbnRleHQubmV3UGFnZSgpKTsKCmFzeW5jIGZ1bmN0aW9uIGVuc3VyZVBhZ2UoKSB7CiAgaWYgKCFwYWdlLmlzQ2xvc2VkKCkpIHJldHVybjsKICBwYWdlID0gY29udGV4dC5wYWdlcygpLmZpbmQoKHgp
::B64:agent.js:ID0+ICF4LmlzQ2xvc2VkKCkpIHx8IChhd2FpdCBjb250ZXh0Lm5ld1BhZ2UoKSk7Cn0KCmFzeW5jIGZ1bmN0aW9uIHNodXRkb3duQnJvd3NlcigpIHsKICAvLyBDaHJvbWUgc2VuZ2FqYSBkaWJpYXJrYW4gdGVyYnVrYSBhZ2FyIGxvZ2luIGRhbiB0YWIgdGV0YXAg
::B64:agent.js:YWRhCiAgdHJ5IHsKICAgIGlmIChicm93c2VySGFuZGxlKSBhd2FpdCBicm93c2VySGFuZGxlLmNsb3NlKCk7CiAgICBlbHNlIGF3YWl0IGNvbnRleHQuY2xvc2UoKTsKICB9IGNhdGNoIHt9Cn0KCi8vIE5hbWEgZmlsZSByZWxhdGlmIGRpY2FyaSBkaSBTQUZFX0RJ
::B64:agent.js:UjsgcGF0aCBsZW5na2FwIGRpIGxva2FzaSBtYW5hIHB1biBib2xlaC4KLy8gUGVuZ2FtYW5ueWEgYWRhbGFoIGl6aW4geS9uIHNlYmVsdW0gc2V0aWFwIHVwbG9hZC4KZnVuY3Rpb24gc2FmZVBhdGgobmFtZSkgewogIGNvbnN0IGZ1bGwgPSBwYXRoLnJlc29sdmUo
::B64:agent.js:U0FGRV9ESVIsIFN0cmluZyhuYW1lKS5yZXBsYWNlKC9eInwiJC9nLCAiIikpOwogIGlmICghZnMuZXhpc3RzU3luYyhmdWxsKSB8fCAhZnMuc3RhdFN5bmMoZnVsbCkuaXNGaWxlKCkpIHsKICAgIHRocm93IG5ldyBFcnJvcigiRmlsZSB0aWRhayBkaXRlbXVrYW46
::B64:agent.js:ICIgKyBmdWxsKTsKICB9CiAgcmV0dXJuIGZ1bGw7Cn0KCmFzeW5jIGZ1bmN0aW9uIGFzayhtc2cpIHsKICBpZiAoIUNPTkZJUk0pIHJldHVybiB0cnVlOwogIGNvbnN0IGEgPSBhd2FpdCBybC5xdWVzdGlvbihgXG5bSVpJTl0gJHttc2d9ICh5L24pOiBgKTsKICBy
::B64:agent.js:ZXR1cm4gYS50cmltKCkudG9Mb3dlckNhc2UoKSA9PT0gInkiOwp9CgovLyA9PT09PSBIZWxwZXIgUG93ZXJTaGVsbCAoa29udHJvbCBkZXNrdG9wIFdpbmRvd3MgdGFucGEgbGlicmFyeSB0YW1iYWhhbikgPT09PT0KZnVuY3Rpb24gcHMoc2NyaXB0LCBlbnYgPSB7
::B64:agent.js:fSwgdGltZW91dCA9IDMwMDAwKSB7CiAgY29uc3QgZW5jb2RlZCA9IEJ1ZmZlci5mcm9tKHNjcmlwdCwgInV0ZjE2bGUiKS50b1N0cmluZygiYmFzZTY0Iik7CiAgcmV0dXJuIG5ldyBQcm9taXNlKChyZXNvbHZlLCByZWplY3QpID0+IHsKICAgIGV4ZWNGaWxlKAog
::B64:agent.js:ICAgICAicG93ZXJzaGVsbCIsCiAgICAgIFsiLU5vUHJvZmlsZSIsICItTm9uSW50ZXJhY3RpdmUiLCAiLUVuY29kZWRDb21tYW5kIiwgZW5jb2RlZF0sCiAgICAgIHsgZW52OiB7IC4uLnByb2Nlc3MuZW52LCAuLi5lbnYgfSwgdGltZW91dCwgbWF4QnVmZmVyOiAy
::B64:agent.js:MCAqIDEwMjQgKiAxMDI0IH0sCiAgICAgIChlcnIsIHN0ZG91dCwgc3RkZXJyKSA9PgogICAgICAgIGVyciA/IHJlamVjdChuZXcgRXJyb3IoKHN0ZGVyciB8fCBlcnIubWVzc2FnZSkuc2xpY2UoMCwgMzAwKSkpIDogcmVzb2x2ZShzdGRvdXQudHJpbSgpKQogICAg
::B64:agent.js:KTsKICB9KTsKfQoKY29uc3QgUFNfSEVBRCA9IGAKQWRkLVR5cGUgQCIKdXNpbmcgU3lzdGVtOwp1c2luZyBTeXN0ZW0uUnVudGltZS5JbnRlcm9wU2VydmljZXM7CnB1YmxpYyBjbGFzcyBXIHsKICBbRGxsSW1wb3J0KCJ1c2VyMzIuZGxsIildIHB1YmxpYyBzdGF0
::B64:agent.js:aWMgZXh0ZXJuIGJvb2wgU2V0UHJvY2Vzc0RQSUF3YXJlKCk7CiAgW0RsbEltcG9ydCgidXNlcjMyLmRsbCIpXSBwdWJsaWMgc3RhdGljIGV4dGVybiBib29sIFNldEN1cnNvclBvcyhpbnQgeCwgaW50IHkpOwogIFtEbGxJbXBvcnQoInVzZXIzMi5kbGwiKV0gcHVi
::B64:agent.js:bGljIHN0YXRpYyBleHRlcm4gdm9pZCBtb3VzZV9ldmVudCh1aW50IGYsIHVpbnQgZHgsIHVpbnQgZHksIGludCBkLCBVSW50UHRyIGUpOwp9CiJACltXXTo6U2V0UHJvY2Vzc0RQSUF3YXJlKCkgfCBPdXQtTnVsbApBZGQtVHlwZSAtQXNzZW1ibHlOYW1lIFN5c3Rl
::B64:agent.js:bS5XaW5kb3dzLkZvcm1zLFN5c3RlbS5EcmF3aW5nCmA7CgpsZXQgc2NhbGUgPSAxOyAvLyByYXNpbyBsYXlhciBhc2xpIC8gc2NyZWVuc2hvdApjb25zdCBwZW5kaW5nSW1hZ2VzID0gW107IC8vIGdhbWJhciB5YW5nIGRpa2lyaW0ga2UgbW9kZWwgc2V0ZWxhaCB0
::B64:agent.js:b29sIGRpamFsYW5rYW4KCmNvbnN0IFNLSVBfRElSUyA9IG5ldyBTZXQoWwogICJub2RlX21vZHVsZXMiLCAiYXBwZGF0YSIsICIuZ2l0IiwgIndpbmRvd3MiLCAicHJvZ3JhbSBmaWxlcyIsICJwcm9ncmFtIGZpbGVzICh4ODYpIiwKICAicHJvZ3JhbWRhdGEiLCAi
::B64:agent.js:JHJlY3ljbGUuYmluIiwgInN5c3RlbSB2b2x1bWUgaW5mb3JtYXRpb24iLApdKTsKbGV0IHNlYXJjaERlYWRsaW5lID0gMDsKCi8vIENhcmkgZm9sZGVyICh3YW50RmlsZXM9ZmFsc2UpIGF0YXUgZmlsZSAod2FudEZpbGVzPXRydWUpIGJlcmRhc2Fya2FuIHNlYmFn
::B64:agent.js:aWFuIG5hbWEKZnVuY3Rpb24gZmluZFBhdGhzKG5hbWUsIHJvb3QsIGRlcHRoLCBvdXQsIHdhbnRGaWxlcykgewogIGlmIChkZXB0aCA8IDAgfHwgb3V0Lmxlbmd0aCA+PSAxMiB8fCBEYXRlLm5vdygpID4gc2VhcmNoRGVhZGxpbmUpIHJldHVybjsKICBsZXQgZW50
::B64:agent.js:cmllczsKICB0cnkgewogICAgZW50cmllcyA9IGZzLnJlYWRkaXJTeW5jKHJvb3QsIHsgd2l0aEZpbGVUeXBlczogdHJ1ZSB9KTsKICB9IGNhdGNoIHsKICAgIHJldHVybjsKICB9CiAgY29uc3QgcSA9IG5hbWUudG9Mb3dlckNhc2UoKTsKICBmb3IgKGNvbnN0IGUg
::B64:agent.js:b2YgZW50cmllcykgewogICAgY29uc3QgZnVsbCA9IHBhdGguam9pbihyb290LCBlLm5hbWUpOwogICAgaWYgKGUuaXNEaXJlY3RvcnkoKSkgewogICAgICBpZiAoU0tJUF9ESVJTLmhhcyhlLm5hbWUudG9Mb3dlckNhc2UoKSkgfHwgZS5uYW1lLnN0YXJ0c1dpdGgo
::B64:agent.js:IiQiKSkgY29udGludWU7CiAgICAgIGlmICghd2FudEZpbGVzICYmIGUubmFtZS50b0xvd2VyQ2FzZSgpLmluY2x1ZGVzKHEpKSBvdXQucHVzaChmdWxsKTsKICAgICAgZmluZFBhdGhzKG5hbWUsIGZ1bGwsIGRlcHRoIC0gMSwgb3V0LCB3YW50RmlsZXMpOwogICAg
::B64:agent.js:fSBlbHNlIGlmICh3YW50RmlsZXMgJiYgZS5pc0ZpbGUoKSAmJiBlLm5hbWUudG9Mb3dlckNhc2UoKS5pbmNsdWRlcyhxKSkgewogICAgICBvdXQucHVzaChmdWxsKTsKICAgIH0KICB9Cn0KCmZ1bmN0aW9uIHNlYXJjaEV2ZXJ5d2hlcmUobmFtZSwgd2FudEZpbGVz
::B64:agent.js:KSB7CiAgY29uc3Qgb3V0ID0gW107CiAgc2VhcmNoRGVhZGxpbmUgPSBEYXRlLm5vdygpICsgMTIwMDA7IC8vIG1ha3NpbWFsIDEyIGRldGlrIGFnYXIgdGlkYWsgbWVuZ2dhbnR1bmcKICBmb3IgKGNvbnN0IHJvb3Qgb2YgU0VBUkNIX1JPT1RTKSBmaW5kUGF0aHMo
::B64:agent.js:U3RyaW5nKG5hbWUpLCByb290LCByb290ID09PSBIT01FID8gNSA6IDMsIG91dCwgd2FudEZpbGVzKTsKICByZXR1cm4gb3V0Lmxlbmd0aCA/IG91dC5qb2luKCJcbiIpIDogIlRpZGFrIGRpdGVtdWthbiI7Cn0KCi8vID09PT09ICJUYW5nYW4iIGFnZW50ID09PT09
::B64:agent.js:Ci8vID09PT09IEhlbHBlciBZb3VUdWJlID09PT09CmFzeW5jIGZ1bmN0aW9uIHNraXBBZHMoKSB7CiAgZm9yIChsZXQgaSA9IDA7IGkgPCAxMDsgaSsrKSB7CiAgICBjb25zdCBidG4gPSBhd2FpdCBwYWdlLiQoIi55dHAtc2tpcC1hZC1idXR0b24sIC55dHAtYWQt
::B64:agent.js:c2tpcC1idXR0b24sIC55dHAtYWQtc2tpcC1idXR0b24tbW9kZXJuIik7CiAgICBpZiAoYnRuKSB7CiAgICAgIGF3YWl0IGJ0bi5jbGljaygpLmNhdGNoKCgpID0+IHt9KTsKICAgICAgcmV0dXJuOwogICAgfQogICAgaWYgKCEoYXdhaXQgcGFnZS4kKCIuYWQtc2hv
::B64:agent.js:d2luZyIpKSkgcmV0dXJuOwogICAgYXdhaXQgc2xlZXAoMTAwMCk7CiAgfQp9Cgphc3luYyBmdW5jdGlvbiByZWFkUGxheWVyU3RhdGUoKSB7CiAgcmV0dXJuIHBhZ2UuZXZhbHVhdGUoKCkgPT4gewogICAgY29uc3QgdiA9IGRvY3VtZW50LnF1ZXJ5U2VsZWN0b3Io
::B64:agent.js:InZpZGVvIik7CiAgICBjb25zdCBlcnIgPSAhIWRvY3VtZW50LnF1ZXJ5U2VsZWN0b3IoIi55dHAtZXJyb3IiKTsKICAgIGlmICh2ICYmIHYucGF1c2VkICYmICFlcnIpIHYucGxheSgpLmNhdGNoKCgpID0+IHt9KTsKICAgIHJldHVybiB7IGVyciwgcGxheWluZzog
::B64:agent.js:ISF2ICYmICF2LnBhdXNlZCAmJiB2LnJlYWR5U3RhdGUgPiAyIH07CiAgfSk7Cn0KCmFzeW5jIGZ1bmN0aW9uIGVuc3VyZVBsYXlpbmcoKSB7CiAgZm9yIChsZXQgYXR0ZW1wdCA9IDA7IGF0dGVtcHQgPCAyOyBhdHRlbXB0KyspIHsKICAgIGF3YWl0IHNsZWVwKDMw
::B64:agent.js:MDApOwogICAgYXdhaXQgc2tpcEFkcygpOwogICAgYXdhaXQgcmVhZFBsYXllclN0YXRlKCk7IC8vIG1lbWljdSBwbGF5KCkKICAgIGF3YWl0IHNsZWVwKDEyMDApOwogICAgY29uc3Qgc3QgPSBhd2FpdCByZWFkUGxheWVyU3RhdGUoKTsKICAgIGlmIChzdC5wbGF5
::B64:agent.js:aW5nKSByZXR1cm4gdHJ1ZTsKICAgIGlmIChzdC5lcnIpIGF3YWl0IHBhZ2UucmVsb2FkKHsgd2FpdFVudGlsOiAiZG9tY29udGVudGxvYWRlZCIgfSk7CiAgfQogIHJldHVybiBmYWxzZTsKfQoKY29uc3QgaW1wbCA9IHsKICAvLyAtLS0gRGVza3RvcDogZmlsZSAm
::B64:agent.js:IGZvbGRlciAtLS0KICBmaW5kX2ZvbGRlcjogYXN5bmMgKHsgbmFtZSB9KSA9PiBzZWFyY2hFdmVyeXdoZXJlKG5hbWUsIGZhbHNlKSwKCiAgZmluZF9maWxlOiBhc3luYyAoeyBuYW1lIH0pID0+IHNlYXJjaEV2ZXJ5d2hlcmUobmFtZSwgdHJ1ZSksCgogIGxpc3Rf
::B64:agent.js:ZGlyOiBhc3luYyAoeyBwYXRoOiBwIH0pID0+IHsKICAgIGNvbnN0IGl0ZW1zID0gZnMucmVhZGRpclN5bmMocCwgeyB3aXRoRmlsZVR5cGVzOiB0cnVlIH0pLnNsaWNlKDAsIDEwMCk7CiAgICByZXR1cm4gaXRlbXMubWFwKChlKSA9PiAoZS5pc0RpcmVjdG9yeSgp
::B64:agent.js:ID8gIltESVJdICIgOiAiW0ZJTEVdICIpICsgZS5uYW1lKS5qb2luKCJcbiIpIHx8ICIoa29zb25nKSI7CiAgfSwKCiAgb3Blbl9wYXRoOiBhc3luYyAoeyB0YXJnZXQgfSkgPT4gewogICAgaWYgKCEoYXdhaXQgYXNrKGBCdWthOiAke3RhcmdldH1gKSkpIHJldHVy
::B64:agent.js:biAiRGliYXRhbGthbiB1c2VyIjsKICAgIGF3YWl0IHBzKCJTdGFydC1Qcm9jZXNzIC1GaWxlUGF0aCAkZW52OlRBUkdFVCIsIHsgVEFSR0VUOiBTdHJpbmcodGFyZ2V0KSB9KTsKICAgIGF3YWl0IHNsZWVwKDE1MDApOwogICAgcmV0dXJuICJvaywgZGlidWthIjsK
::B64:agent.js:ICB9LAoKICAvLyAtLS0gRGVza3RvcDogbGF5YXIsIG1vdXNlLCBrZXlib2FyZCAtLS0KICBzY3JlZW5zaG90OiBhc3luYyAoKSA9PiB7CiAgICBjb25zdCBvdXQgPSBwYXRoLnJlc29sdmUoInNjcmVlbi5wbmciKTsKICAgIGNvbnN0IHIgPSBhd2FpdCBwcygKICAg
::B64:agent.js:ICAgUFNfSEVBRCArCiAgICAgICAgYAokYiA9IFtTeXN0ZW0uV2luZG93cy5Gb3Jtcy5TY3JlZW5dOjpQcmltYXJ5U2NyZWVuLkJvdW5kcwokYm1wID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5CaXRtYXAgJGIuV2lkdGgsICRiLkhlaWdodAokZyA9IFtTeXN0
::B64:agent.js:ZW0uRHJhd2luZy5HcmFwaGljc106OkZyb21JbWFnZSgkYm1wKQokZy5Db3B5RnJvbVNjcmVlbigkYi5YLCAkYi5ZLCAwLCAwLCAkYm1wLlNpemUpCiRudyA9IFtNYXRoXTo6TWluKDEyODAsICRiLldpZHRoKQokbmggPSBbaW50XSgkYi5IZWlnaHQgKiAkbncgLyAk
::B64:agent.js:Yi5XaWR0aCkKJHNtYWxsID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5CaXRtYXAgJGJtcCwgJG53LCAkbmgKJHNtYWxsLlNhdmUoJGVudjpPVVQsIFtTeXN0ZW0uRHJhd2luZy5JbWFnaW5nLkltYWdlRm9ybWF0XTo6UG5nKQpXcml0ZS1PdXRwdXQgIiQoJGIu
::B64:agent.js:V2lkdGgpLCRudywkbmgiCmAsCiAgICAgIHsgT1VUOiBvdXQgfQogICAgKTsKICAgIGNvbnN0IFt3LCBudywgbmhdID0gci5zcGxpdCgiXG4iKS5wb3AoKS5zcGxpdCgiLCIpLm1hcChOdW1iZXIpOwogICAgc2NhbGUgPSB3IC8gbnc7CiAgICBwZW5kaW5nSW1hZ2Vz
::B64:agent.js:LnB1c2goZnMucmVhZEZpbGVTeW5jKG91dCkudG9TdHJpbmcoImJhc2U2NCIpKTsKICAgIHJldHVybiBgU2NyZWVuc2hvdCBkaWFtYmlsICgke253fXgke25ofSkuIEdhbWJhcm55YSBhZGEgZGkgcGVzYW4gYmVyaWt1dG55YS4gUGFrYWkga29vcmRpbmF0IGRhcmkg
::B64:agent.js:Z2FtYmFyIGl0dS5gOwogIH0sCgogIGNsaWNrX3NjcmVlbjogYXN5bmMgKHsgeCwgeSwgYnV0dG9uID0gImxlZnQiLCBkb3VibGUgPSBmYWxzZSB9KSA9PiB7CiAgICBjb25zdCByeCA9IE1hdGgucm91bmQoTnVtYmVyKHgpICogc2NhbGUpOwogICAgY29uc3Qgcnkg
::B64:agent.js:PSBNYXRoLnJvdW5kKE51bWJlcih5KSAqIHNjYWxlKTsKICAgIGNvbnN0IGRibCA9IGRvdWJsZSA9PT0gdHJ1ZSB8fCBkb3VibGUgPT09ICJ0cnVlIjsKICAgIGlmICghKGF3YWl0IGFzayhgJHtkYmwgPyAiRG91YmxlLWtsaWsiIDogIktsaWsifSAke2J1dHRvbn0g
::B64:agent.js:ZGkgKCR7eH0sJHt5fSlgKSkpIHJldHVybiAiRGliYXRhbGthbiB1c2VyIjsKICAgIGF3YWl0IHBzKAogICAgICBQU19IRUFEICsKICAgICAgICBgCltXXTo6U2V0Q3Vyc29yUG9zKFtpbnRdJGVudjpYLCBbaW50XSRlbnY6WSkgfCBPdXQtTnVsbApTdGFydC1TbGVl
::B64:agent.js:cCAtTWlsbGlzZWNvbmRzIDE1MAokZG93biA9IDI7ICR1cCA9IDQKaWYgKCRlbnY6QlROIC1lcSAicmlnaHQiKSB7ICRkb3duID0gODsgJHVwID0gMTYgfQpmb3IgKCRpID0gMDsgJGkgLWx0IFtpbnRdJGVudjpDT1VOVDsgJGkrKykgewogIFtXXTo6bW91c2VfZXZl
::B64:agent.js:bnQoJGRvd24sIDAsIDAsIDAsIFtVSW50UHRyXTo6WmVybykKICBbV106Om1vdXNlX2V2ZW50KCR1cCwgMCwgMCwgMCwgW1VJbnRQdHJdOjpaZXJvKQogIFN0YXJ0LVNsZWVwIC1NaWxsaXNlY29uZHMgODAKfQpgLAogICAgICB7IFg6IFN0cmluZyhyeCksIFk6IFN0
::B64:agent.js:cmluZyhyeSksIEJUTjogU3RyaW5nKGJ1dHRvbiksIENPVU5UOiBkYmwgPyAiMiIgOiAiMSIgfQogICAgKTsKICAgIGF3YWl0IHNsZWVwKDgwMCk7CiAgICByZXR1cm4gIm9rLCBkaWtsaWsiOwogIH0sCgogIHNjcm9sbF9zY3JlZW46IGFzeW5jICh7IGFtb3VudCB9
::B64:agent.js:KSA9PiB7CiAgICBjb25zdCBkZWx0YSA9IC0xMjAgKiBNYXRoLnJvdW5kKE51bWJlcihhbW91bnQpKTsgLy8gcG9zaXRpZiA9IHR1cnVuCiAgICBpZiAoIShhd2FpdCBhc2soYFNjcm9sbCAke2Ftb3VudCA+IDAgPyAidHVydW4iIDogIm5haWsifSAke01hdGguYWJz
::B64:agent.js:KGFtb3VudCl9eGApKSkgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgYXdhaXQgcHMoUFNfSEVBRCArIGBbV106Om1vdXNlX2V2ZW50KDB4MDgwMCwgMCwgMCwgW2ludF0kZW52OkQsIFtVSW50UHRyXTo6WmVybylgLCB7IEQ6IFN0cmluZyhkZWx0YSkgfSk7
::B64:agent.js:CiAgICBhd2FpdCBzbGVlcCg1MDApOwogICAgcmV0dXJuICJvayI7CiAgfSwKCiAgdHlwZV9kZXNrdG9wOiBhc3luYyAoeyB0ZXh0IH0pID0+IHsKICAgIGlmICghKGF3YWl0IGFzayhgS2V0aWs6ICIke1N0cmluZyh0ZXh0KS5zbGljZSgwLCA2MCl9ImApKSkgcmV0
::B64:agent.js:dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgYXdhaXQgcHMoCiAgICAgIFBTX0hFQUQgKwogICAgICAgIGAKU2V0LUNsaXBib2FyZCAtVmFsdWUgJGVudjpUWFQKU3RhcnQtU2xlZXAgLU1pbGxpc2Vjb25kcyAxNTAKW1N5c3RlbS5XaW5kb3dzLkZvcm1zLlNlbmRL
::B64:agent.js:ZXlzXTo6U2VuZFdhaXQoIl52IikKYCwKICAgICAgeyBUWFQ6IFN0cmluZyh0ZXh0KSB9CiAgICApOwogICAgYXdhaXQgc2xlZXAoNTAwKTsKICAgIHJldHVybiAib2ssIGRpa2V0aWsiOwogIH0sCgogIHByZXNzX2tleXM6IGFzeW5jICh7IGtleXMgfSkgPT4gewog
::B64:agent.js:ICAgaWYgKCEoYXdhaXQgYXNrKGBUZWthbiB0b21ib2w6ICR7a2V5c31gKSkpIHJldHVybiAiRGliYXRhbGthbiB1c2VyIjsKICAgIGF3YWl0IHBzKFBTX0hFQUQgKyBgW1N5c3RlbS5XaW5kb3dzLkZvcm1zLlNlbmRLZXlzXTo6U2VuZFdhaXQoJGVudjpLRVlTKWAs
::B64:agent.js:IHsgS0VZUzogU3RyaW5nKGtleXMpIH0pOwogICAgYXdhaXQgc2xlZXAoNTAwKTsKICAgIHJldHVybiAib2siOwogIH0sCgogIHdhaXQ6IGFzeW5jICh7IHNlY29uZHMgfSkgPT4gewogICAgYXdhaXQgc2xlZXAoTWF0aC5taW4oTnVtYmVyKHNlY29uZHMpIHx8IDEs
::B64:agent.js:IDE1KSAqIDEwMDApOwogICAgcmV0dXJuICJvayI7CiAgfSwKCiAgLy8gLS0tIEJyb3dzZXIgKFBsYXl3cmlnaHQpIC0tLQogIGxpc3RfZmlsZXM6IGFzeW5jICgpID0+IGZzLnJlYWRkaXJTeW5jKFNBRkVfRElSKS5qb2luKCJcbiIpIHx8ICIoZm9sZGVyIHVwbG9h
::B64:agent.js:ZCBrb3NvbmcpIiwKCiAgb3Blbl91cmw6IGFzeW5jICh7IHVybCB9KSA9PiB7CiAgICBhd2FpdCBwYWdlLmdvdG8odXJsLCB7IHdhaXRVbnRpbDogImRvbWNvbnRlbnRsb2FkZWQiIH0pOwogICAgcmV0dXJuICJUZXJidWthOiAiICsgKGF3YWl0IHBhZ2UudGl0bGUo
::B64:agent.js:KSk7CiAgfSwKCiAgaW5zcGVjdF9wYWdlOiBhc3luYyAoKSA9PiB7CiAgICBjb25zdCBpdGVtcyA9IGF3YWl0IHBhZ2UuZXZhbHVhdGUoKCkgPT4KICAgICAgWy4uLmRvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoImlucHV0LCBidXR0b24sIGEsIHRleHRhcmVhLCBz
::B64:agent.js:ZWxlY3QiKV0KICAgICAgICAuc2xpY2UoMCwgNjApCiAgICAgICAgLm1hcCgoZSkgPT4gKHsKICAgICAgICAgIHRhZzogZS50YWdOYW1lLnRvTG93ZXJDYXNlKCksCiAgICAgICAgICBpZDogZS5pZCB8fCB1bmRlZmluZWQsCiAgICAgICAgICBuYW1lOiBlLmdldEF0
::B64:agent.js:dHJpYnV0ZSgibmFtZSIpIHx8IHVuZGVmaW5lZCwKICAgICAgICAgIHR5cGU6IGUuZ2V0QXR0cmlidXRlKCJ0eXBlIikgfHwgdW5kZWZpbmVkLAogICAgICAgICAgdGV4dDogKGUuaW5uZXJUZXh0IHx8IGUudmFsdWUgfHwgZS5wbGFjZWhvbGRlciB8fCAiIikudHJp
::B64:agent.js:bSgpLnNsaWNlKDAsIDQwKSB8fCB1bmRlZmluZWQsCiAgICAgICAgfSkpCiAgICApOwogICAgcmV0dXJuIEpTT04uc3RyaW5naWZ5KGl0ZW1zKTsKICB9LAoKICB5b3V0dWJlX3BsYXk6IGFzeW5jICh7IHF1ZXJ5LCBwaWNrID0gMSB9KSA9PiB7CiAgICBhd2FpdCBw
::B64:agent.js:YWdlLmJyaW5nVG9Gcm9udCgpOwogICAgYXdhaXQgcGFnZS5nb3RvKCJodHRwczovL3d3dy55b3V0dWJlLmNvbS9yZXN1bHRzP3NlYXJjaF9xdWVyeT0iICsgZW5jb2RlVVJJQ29tcG9uZW50KFN0cmluZyhxdWVyeSkpLCB7CiAgICAgIHdhaXRVbnRpbDogImRvbWNv
::B64:agent.js:bnRlbnRsb2FkZWQiLAogICAgfSk7CiAgICBhd2FpdCBwYWdlLndhaXRGb3JTZWxlY3RvcigieXRkLXZpZGVvLXJlbmRlcmVyIGEjdmlkZW8tdGl0bGUiLCB7IHRpbWVvdXQ6IDIwMDAwIH0pOwogICAgY29uc3QgbGlzdCA9IGF3YWl0IHBhZ2UuJCRldmFsKCJ5dGQt
::B64:agent.js:dmlkZW8tcmVuZGVyZXIgYSN2aWRlby10aXRsZSIsIChlbHMpID0+CiAgICAgIGVscy5zbGljZSgwLCA1KS5tYXAoKGUpID0+ICh7IHRpdGxlOiBlLnRleHRDb250ZW50LnRyaW0oKSwgaHJlZjogZS5ocmVmIH0pKQogICAgKTsKICAgIGlmICghbGlzdC5sZW5ndGgp
::B64:agent.js:IHJldHVybiAiVGlkYWsgYWRhIGhhc2lsIjsKICAgIGNvbnN0IHN0YXJ0ID0gTWF0aC5taW4oTWF0aC5tYXgoTnVtYmVyKHBpY2spIHx8IDEsIDEpLCBsaXN0Lmxlbmd0aCkgLSAxOwogICAgY29uc3Qgb3JkZXIgPSBbc3RhcnQsIC4uLmxpc3QubWFwKChfLCBpKSA9
::B64:agent.js:PiBpKS5maWx0ZXIoKGkpID0+IGkgIT09IHN0YXJ0KV0uc2xpY2UoMCwgMyk7CiAgICBjb25zdCBvdGhlcnMgPSBsaXN0Lm1hcCgodiwgaSkgPT4gYCR7aSArIDF9LiAke3YudGl0bGV9YCkuam9pbigiXG4iKTsKICAgIGZvciAoY29uc3QgaWR4IG9mIG9yZGVyKSB7
::B64:agent.js:CiAgICAgIGF3YWl0IHBhZ2UuZ290byhsaXN0W2lkeF0uaHJlZiwgeyB3YWl0VW50aWw6ICJkb21jb250ZW50bG9hZGVkIiB9KTsKICAgICAgaWYgKGF3YWl0IGVuc3VyZVBsYXlpbmcoKSkgewogICAgICAgIHJldHVybiBgTWVtdXRhciAjJHtpZHggKyAxfTogJHts
::B64:agent.js:aXN0W2lkeF0udGl0bGV9XG5IYXNpbCBwZW5jYXJpYW46XG4ke290aGVyc31gOwogICAgICB9CiAgICB9CiAgICByZXR1cm4gIlZpZGVvIGdhZ2FsIGRpcHV0YXIgKFlvdVR1YmUgbWVuYW1waWxrYW4gZXJyb3IpLiBDb2JhIC9sb2dpbiBhdGF1IGp1ZHVsIGxhaW4u
::B64:agent.js:XG5IYXNpbCBwZW5jYXJpYW46XG4iICsgb3RoZXJzOwogIH0sCgogIHlvdXR1YmVfY29udHJvbDogYXN5bmMgKHsgYWN0aW9uLCBzZWNvbmRzID0gMTAgfSkgPT4gewogICAgYXdhaXQgcGFnZS5icmluZ1RvRnJvbnQoKTsKICAgIHJldHVybiBwYWdlLmV2YWx1YXRl
::B64:agent.js:KAogICAgICAoeyBhLCBzIH0pID0+IHsKICAgICAgICBjb25zdCB2ID0gZG9jdW1lbnQucXVlcnlTZWxlY3RvcigidmlkZW8iKTsKICAgICAgICBpZiAoIXYpIHJldHVybiAiVGlkYWsgYWRhIHZpZGVvIGRpIGhhbGFtYW4gaW5pIjsKICAgICAgICBpZiAoYSA9PT0g
::B64:agent.js:InBhdXNlIikgdi5wYXVzZSgpOwogICAgICAgIGVsc2UgaWYgKGEgPT09ICJwbGF5Iikgdi5wbGF5KCk7CiAgICAgICAgZWxzZSBpZiAoYSA9PT0gInRvZ2dsZSIpICh2LnBhdXNlZCA/IHYucGxheSgpIDogdi5wYXVzZSgpKTsKICAgICAgICBlbHNlIGlmIChhID09
::B64:agent.js:PSAibXV0ZSIpIHYubXV0ZWQgPSB0cnVlOwogICAgICAgIGVsc2UgaWYgKGEgPT09ICJ1bm11dGUiKSB2Lm11dGVkID0gZmFsc2U7CiAgICAgICAgZWxzZSBpZiAoYSA9PT0gImZvcndhcmQiKSB2LmN1cnJlbnRUaW1lICs9IHM7CiAgICAgICAgZWxzZSBpZiAoYSA9
::B64:agent.js:PT0gImJhY2t3YXJkIikgdi5jdXJyZW50VGltZSAtPSBzOwogICAgICAgIGVsc2UgaWYgKGEgPT09ICJuZXh0IikgewogICAgICAgICAgY29uc3QgYiA9IGRvY3VtZW50LnF1ZXJ5U2VsZWN0b3IoIi55dHAtbmV4dC1idXR0b24iKTsKICAgICAgICAgIGlmICghYikg
::B64:agent.js:cmV0dXJuICJUb21ib2wgbmV4dCB0aWRhayBhZGEiOwogICAgICAgICAgYi5jbGljaygpOwogICAgICAgIH0gZWxzZSBpZiAoYSA9PT0gInByZXZpb3VzIikgewogICAgICAgICAgY29uc3QgYiA9IGRvY3VtZW50LnF1ZXJ5U2VsZWN0b3IoIi55dHAtcHJldi1idXR0
::B64:agent.js:b24iKTsKICAgICAgICAgIGlmIChiICYmIGdldENvbXB1dGVkU3R5bGUoYikuZGlzcGxheSAhPT0gIm5vbmUiKSBiLmNsaWNrKCk7CiAgICAgICAgICBlbHNlIGhpc3RvcnkuYmFjaygpOwogICAgICAgIH0gZWxzZSBpZiAoYSA9PT0gImZ1bGxzY3JlZW4iKSB7CiAg
::B64:agent.js:ICAgICAgICBjb25zdCBiID0gZG9jdW1lbnQucXVlcnlTZWxlY3RvcigiLnl0cC1mdWxsc2NyZWVuLWJ1dHRvbiIpOwogICAgICAgICAgaWYgKGIpIGIuY2xpY2soKTsKICAgICAgICB9IGVsc2UgcmV0dXJuICJBa3NpIHRpZGFrIGRpa2VuYWwuIFBpbGloOiBwbGF5
::B64:agent.js:LCBwYXVzZSwgdG9nZ2xlLCBtdXRlLCB1bm11dGUsIGZvcndhcmQsIGJhY2t3YXJkLCBuZXh0LCBwcmV2aW91cywgZnVsbHNjcmVlbiI7CiAgICAgICAgcmV0dXJuICJvayI7CiAgICAgIH0sCiAgICAgIHsgYTogU3RyaW5nKGFjdGlvbikudG9Mb3dlckNhc2UoKSwg
::B64:agent.js:czogTnVtYmVyKHNlY29uZHMpIHx8IDEwIH0KICAgICk7CiAgfSwKCiAgLy8gLS0tIFdlYiAtLS0KICB3ZWJfc2VhcmNoOiBhc3luYyAoeyBxdWVyeSB9KSA9PiB7CiAgICBhd2FpdCBwYWdlLmJyaW5nVG9Gcm9udCgpOwogICAgYXdhaXQgcGFnZS5nb3RvKCJodHRw
::B64:agent.js:czovL2h0bWwuZHVja2R1Y2tnby5jb20vaHRtbC8/cT0iICsgZW5jb2RlVVJJQ29tcG9uZW50KFN0cmluZyhxdWVyeSkpLCB7CiAgICAgIHdhaXRVbnRpbDogImRvbWNvbnRlbnRsb2FkZWQiLAogICAgfSk7CiAgICBjb25zdCByb3dzID0gYXdhaXQgcGFnZS4kJGV2
::B64:agent.js:YWwoIi5yZXN1bHQiLCAoZWxzKSA9PgogICAgICBlbHMuc2xpY2UoMCwgOCkubWFwKChlKSA9PiAoewogICAgICAgIHRpdGxlOiBlLnF1ZXJ5U2VsZWN0b3IoIi5yZXN1bHRfX2EiKT8udGV4dENvbnRlbnQudHJpbSgpLAogICAgICAgIHVybDogZS5xdWVyeVNlbGVj
::B64:agent.js:dG9yKCIucmVzdWx0X19hIik/LmhyZWYsCiAgICAgICAgc25pcHBldDogZS5xdWVyeVNlbGVjdG9yKCIucmVzdWx0X19zbmlwcGV0Iik/LnRleHRDb250ZW50LnRyaW0oKSwKICAgICAgfSkpCiAgICApOwogICAgY29uc3QgcmVhbCA9ICh1KSA9PiB7CiAgICAgIHRy
::B64:agent.js:eSB7CiAgICAgICAgY29uc3QgeCA9IG5ldyBVUkwodSk7CiAgICAgICAgcmV0dXJuIHguc2VhcmNoUGFyYW1zLmdldCgidWRkZyIpIHx8IHU7CiAgICAgIH0gY2F0Y2ggewogICAgICAgIHJldHVybiB1OwogICAgICB9CiAgICB9OwogICAgY29uc3Qgb2sgPSByb3dz
::B64:agent.js:LmZpbHRlcigocikgPT4gci50aXRsZSk7CiAgICByZXR1cm4gb2subGVuZ3RoID8gb2subWFwKChyLCBpKSA9PiBgJHtpICsgMX0uICR7ci50aXRsZX1cbiAgICR7cmVhbChyLnVybCl9XG4gICAke3Iuc25pcHBldCB8fCAiIn1gKS5qb2luKCJcbiIpIDogIlRpZGFr
::B64:agent.js:IGFkYSBoYXNpbCI7CiAgfSwKCiAgc2Nyb2xsX3BhZ2U6IGFzeW5jICh7IGFtb3VudCB9KSA9PiB7CiAgICBhd2FpdCBwYWdlLm1vdXNlLndoZWVsKDAsIE1hdGgucm91bmQoTnVtYmVyKGFtb3VudCkgfHwgMSkgKiA3MDApOwogICAgYXdhaXQgc2xlZXAoNDAwKTsK
::B64:agent.js:ICAgIHJldHVybiAib2siOwogIH0sCgogIHdhaXRfZm9yX3VzZXI6IGFzeW5jICh7IG1lc3NhZ2UgfSkgPT4gewogICAgYXdhaXQgcGFnZS5icmluZ1RvRnJvbnQoKS5jYXRjaCgoKSA9PiB7fSk7CiAgICBjb25zb2xlLmxvZyhgXG5bQlVUVUggQkFOVFVBTiBLQU1V
::B64:agent.js:XSAke21lc3NhZ2V9YCk7CiAgICBhd2FpdCBybC5xdWVzdGlvbigiVGVrYW4gRW50ZXIgamlrYSBzdWRhaCBzZWxlc2FpLi4uICIpOwogICAgcmV0dXJuICJVc2VyIHN1ZGFoIHNlbGVzYWkiOwogIH0sCgogIGRvd25sb2FkX2ZpbGU6IGFzeW5jICh7IHVybCwgZmls
::B64:agent.js:ZW5hbWUgfSkgPT4gewogICAgaWYgKCEvXmh0dHBzPzpcL1wvL2kudGVzdChTdHJpbmcodXJsKSkpIHRocm93IG5ldyBFcnJvcigiVVJMIGhhcnVzIGRpYXdhbGkgaHR0cDovLyBhdGF1IGh0dHBzOi8vIik7CiAgICBjb25zdCBndWVzcyA9IGRlY29kZVVSSUNvbXBv
::B64:agent.js:bmVudChuZXcgVVJMKHVybCkucGF0aG5hbWUuc3BsaXQoIi8iKS5wb3AoKSB8fCAiIikgfHwgImRvd25sb2FkLmJpbiI7CiAgICBjb25zdCBkZXN0ID0gcGF0aC5qb2luKEhPTUUsICJEb3dubG9hZHMiLCBwYXRoLmJhc2VuYW1lKFN0cmluZyhmaWxlbmFtZSB8fCBn
::B64:agent.js:dWVzcykpKTsKICAgIGlmICghKGF3YWl0IGFzayhgVW5kdWggJHt1cmx9ICBrZSAgJHtkZXN0fWApKSkgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgY29uc3QgcmVzID0gYXdhaXQgZmV0Y2godXJsLCB7IHJlZGlyZWN0OiAiZm9sbG93Iiwgc2lnbmFsOiBB
::B64:agent.js:Ym9ydFNpZ25hbC50aW1lb3V0KDEwICogNjAgKiAxMDAwKSB9KTsKICAgIGlmICghcmVzLm9rKSB0aHJvdyBuZXcgRXJyb3IoIkhUVFAgIiArIHJlcy5zdGF0dXMpOwogICAgYXdhaXQgcGlwZWxpbmUoUmVhZGFibGUuZnJvbVdlYihyZXMuYm9keSksIGZzLmNyZWF0
::B64:agent.js:ZVdyaXRlU3RyZWFtKGRlc3QpKTsKICAgIHJldHVybiBgb2ssIHRlcnNpbXBhbjogJHtkZXN0fSAoJHtmcy5zdGF0U3luYyhkZXN0KS5zaXplfSBieXRlKWA7CiAgfSwKCiAgLy8gLS0tIFBDOiBpbmZvLCBtZWRpYSwgY2xpcGJvYXJkLCBqZW5kZWxhIC0tLQogIG5v
::B64:agent.js:dzogYXN5bmMgKCkgPT4gbmV3IERhdGUoKS50b0xvY2FsZVN0cmluZygiaWQtSUQiLCB7IGRhdGVTdHlsZTogImZ1bGwiLCB0aW1lU3R5bGU6ICJsb25nIiB9KSwKCiAgc3lzdGVtX2luZm86IGFzeW5jICgpID0+CiAgICBwcyhgCiRvcyA9IEdldC1DaW1JbnN0YW5j
::B64:agent.js:ZSBXaW4zMl9PcGVyYXRpbmdTeXN0ZW0KJGNwdSA9IEdldC1DaW1JbnN0YW5jZSBXaW4zMl9Qcm9jZXNzb3IgfCBTZWxlY3QtT2JqZWN0IC1GaXJzdCAxCiRiYXQgPSBHZXQtQ2ltSW5zdGFuY2UgV2luMzJfQmF0dGVyeSB8IFNlbGVjdC1PYmplY3QgLUZpcnN0IDEK
::B64:agent.js:JGwgPSBAKCkKJGwgKz0gIk9TOiAiICsgJG9zLkNhcHRpb24KJGwgKz0gIkNQVTogIiArICRjcHUuTmFtZSArICIgKGJlYmFuICIgKyAkY3B1LkxvYWRQZXJjZW50YWdlICsgIiUpIgokbCArPSAiUkFNOiBiZWJhcyAiICsgW21hdGhdOjpSb3VuZCgkb3MuRnJlZVBo
::B64:agent.js:eXNpY2FsTWVtb3J5IC8gMU1CLCAxKSArICIgR0IgZGFyaSAiICsgW21hdGhdOjpSb3VuZCgkb3MuVG90YWxWaXNpYmxlTWVtb3J5U2l6ZSAvIDFNQiwgMSkgKyAiIEdCIgppZiAoJGJhdCkgeyAkbCArPSAiQmF0ZXJhaTogIiArICRiYXQuRXN0aW1hdGVkQ2hhcmdl
::B64:agent.js:UmVtYWluaW5nICsgIiUiIH0gZWxzZSB7ICRsICs9ICJCYXRlcmFpOiB0aWRhayBhZGEgKFBDIGRlc2t0b3ApIiB9CkdldC1DaW1JbnN0YW5jZSBXaW4zMl9Mb2dpY2FsRGlzayAtRmlsdGVyICJEcml2ZVR5cGU9MyIgfCBGb3JFYWNoLU9iamVjdCB7ICRsICs9ICJE
::B64:agent.js:aXNrICIgKyAkXy5EZXZpY2VJRCArICIgYmViYXMgIiArIFttYXRoXTo6Um91bmQoJF8uRnJlZVNwYWNlIC8gMUdCLCAxKSArICIgR0IgZGFyaSAiICsgW21hdGhdOjpSb3VuZCgkXy5TaXplIC8gMUdCLCAxKSArICIgR0IiIH0KJGwgLWpvaW4gW0Vudmlyb25tZW50
::B64:agent.js:XTo6TmV3TGluZQpgKSwKCiAgbWVkaWFfa2V5OiBhc3luYyAoeyBrZXksIHRpbWVzID0gMSB9KSA9PiB7CiAgICBjb25zdCB2YWxpZCA9IFsidm9sdXAiLCAidm9sZG93biIsICJtdXRlIiwgInBsYXlwYXVzZSIsICJuZXh0IiwgInByZXYiXTsKICAgIGlmICghdmFs
::B64:agent.js:aWQuaW5jbHVkZXMoU3RyaW5nKGtleSkpKSByZXR1cm4gImtleSBoYXJ1cyBzYWxhaCBzYXR1IGRhcmk6ICIgKyB2YWxpZC5qb2luKCIsICIpOwogICAgYXdhaXQgcHMoCiAgICAgIGAKQWRkLVR5cGUgQCIKdXNpbmcgU3lzdGVtLlJ1bnRpbWUuSW50ZXJvcFNlcnZp
::B64:agent.js:Y2VzOwpwdWJsaWMgY2xhc3MgSyB7IFtEbGxJbXBvcnQoInVzZXIzMi5kbGwiKV0gcHVibGljIHN0YXRpYyBleHRlcm4gdm9pZCBrZXliZF9ldmVudChieXRlIGIsIGJ5dGUgcywgdWludCBmLCBpbnQgZSk7IH0KIkAKJG1hcCA9IEB7IHZvbHVwID0gMHhBRjsgdm9s
::B64:agent.js:ZG93biA9IDB4QUU7IG11dGUgPSAweEFEOyBwbGF5cGF1c2UgPSAweEIzOyBuZXh0ID0gMHhCMDsgcHJldiA9IDB4QjEgfQokayA9IFtieXRlXSRtYXBbJGVudjpLRVldCmZvciAoJGkgPSAwOyAkaSAtbHQgW2ludF0kZW52Ok47ICRpKyspIHsgW0tdOjprZXliZF9l
::B64:agent.js:dmVudCgkaywgMCwgMCwgMCk7IFtLXTo6a2V5YmRfZXZlbnQoJGssIDAsIDIsIDApOyBTdGFydC1TbGVlcCAtTWlsbGlzZWNvbmRzIDYwIH0KYCwKICAgICAgeyBLRVk6IFN0cmluZyhrZXkpLCBOOiBTdHJpbmcoTWF0aC5taW4oTWF0aC5tYXgoTnVtYmVyKHRpbWVz
::B64:agent.js:KSB8fCAxLCAxKSwgNTApKSB9CiAgICApOwogICAgcmV0dXJuICJvayI7CiAgfSwKCiAgY2xpcGJvYXJkX2dldDogYXN5bmMgKCkgPT4gKGF3YWl0IHBzKCJHZXQtQ2xpcGJvYXJkIC1SYXciKSkuc2xpY2UoMCwgNDAwMCkgfHwgIihrb3NvbmcpIiwKCiAgY2xpcGJv
::B64:agent.js:YXJkX3NldDogYXN5bmMgKHsgdGV4dCB9KSA9PiB7CiAgICBhd2FpdCBwcygiU2V0LUNsaXBib2FyZCAtVmFsdWUgJGVudjpUWFQiLCB7IFRYVDogU3RyaW5nKHRleHQpIH0pOwogICAgcmV0dXJuICJvayI7CiAgfSwKCiAgbGlzdF93aW5kb3dzOiBhc3luYyAoKSA9
::B64:agent.js:PgogICAgKGF3YWl0IHBzKGBHZXQtUHJvY2VzcyB8IFdoZXJlLU9iamVjdCB7ICRfLk1haW5XaW5kb3dUaXRsZSB9IHwgRm9yRWFjaC1PYmplY3QgeyAkXy5Qcm9jZXNzTmFtZSArICIgfCAiICsgJF8uTWFpbldpbmRvd1RpdGxlIH1gKSkgfHwKICAgICIodGlkYWsg
::B64:agent.js:YWRhIGplbmRlbGEpIiwKCiAgZm9jdXNfd2luZG93OiBhc3luYyAoeyB0aXRsZSB9KSA9PgogICAgcHMoYGlmICgoTmV3LU9iamVjdCAtQ29tT2JqZWN0IFdTY3JpcHQuU2hlbGwpLkFwcEFjdGl2YXRlKCRlbnY6VElUTEUpKSB7ICJvayIgfSBlbHNlIHsgImplbmRl
::B64:agent.js:bGEgdGlkYWsgZGl0ZW11a2FuIiB9YCwgewogICAgICBUSVRMRTogU3RyaW5nKHRpdGxlKSwKICAgIH0pLAoKICBjbG9zZV93aW5kb3c6IGFzeW5jICh7IHRpdGxlIH0pID0+IHsKICAgIGlmICghKGF3YWl0IGFzayhgVHV0dXAgamVuZGVsYTogJHt0aXRsZX1gKSkp
::B64:agent.js:IHJldHVybiAiRGliYXRhbGthbiB1c2VyIjsKICAgIHJldHVybiBwcygKICAgICAgYCRwID0gR2V0LVByb2Nlc3MgfCBXaGVyZS1PYmplY3QgeyAkXy5NYWluV2luZG93VGl0bGUgLWxpa2UgKCIqIiArICRlbnY6VElUTEUgKyAiKiIpIH0gfCBTZWxlY3QtT2JqZWN0
::B64:agent.js:IC1GaXJzdCAxCmlmICgkcCkgeyAkcC5DbG9zZU1haW5XaW5kb3coKSB8IE91dC1OdWxsOyAib2s6ICIgKyAkcC5NYWluV2luZG93VGl0bGUgfSBlbHNlIHsgImplbmRlbGEgdGlkYWsgZGl0ZW11a2FuIiB9YCwKICAgICAgeyBUSVRMRTogU3RyaW5nKHRpdGxlKSB9
::B64:agent.js:CiAgICApOwogIH0sCgogIC8vIC0tLSBGaWxlIC0tLQogIHJlYWRfdGV4dF9maWxlOiBhc3luYyAoeyBwYXRoOiBwIH0pID0+IHsKICAgIGNvbnN0IGZ1bGwgPSBwYXRoLnJlc29sdmUoU3RyaW5nKHApKTsKICAgIGNvbnN0IHN0ID0gZnMuc3RhdFN5bmMoZnVsbCk7
::B64:agent.js:CiAgICBpZiAoIXN0LmlzRmlsZSgpKSB0aHJvdyBuZXcgRXJyb3IoIkJ1a2FuIGZpbGU6ICIgKyBmdWxsKTsKICAgIGlmIChzdC5zaXplID4gMl8wMDBfMDAwKSB0aHJvdyBuZXcgRXJyb3IoIkZpbGUgdGVybGFsdSBiZXNhciB1bnR1ayBkaWJhY2EgKCIgKyBzdC5z
::B64:agent.js:aXplICsgIiBieXRlKSIpOwogICAgcmV0dXJuIGZzLnJlYWRGaWxlU3luYyhmdWxsLCAidXRmOCIpLnNsaWNlKDAsIDgwMDApOwogIH0sCgogIHdyaXRlX3RleHRfZmlsZTogYXN5bmMgKHsgcGF0aDogcCwgY29udGVudCwgYXBwZW5kID0gZmFsc2UgfSkgPT4gewog
::B64:agent.js:ICAgY29uc3QgZnVsbCA9IHBhdGgucmVzb2x2ZShTdHJpbmcocCkpOwogICAgY29uc3QgYWRkID0gYXBwZW5kID09PSB0cnVlIHx8IGFwcGVuZCA9PT0gInRydWUiOwogICAgY29uc3QgdmVyYiA9IGFkZCA/ICJUYW1iYWgga2UiIDogZnMuZXhpc3RzU3luYyhmdWxs
::B64:agent.js:KSA/ICJUSU1QQSIgOiAiQnVhdCI7CiAgICBpZiAoIShhd2FpdCBhc2soYCR7dmVyYn0gZmlsZTogJHtmdWxsfWApKSkgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgZnMubWtkaXJTeW5jKHBhdGguZGlybmFtZShmdWxsKSwgeyByZWN1cnNpdmU6IHRydWUg
::B64:agent.js:fSk7CiAgICBpZiAoYWRkKSBmcy5hcHBlbmRGaWxlU3luYyhmdWxsLCBTdHJpbmcoY29udGVudCkpOwogICAgZWxzZSBmcy53cml0ZUZpbGVTeW5jKGZ1bGwsIFN0cmluZyhjb250ZW50KSk7CiAgICByZXR1cm4gIm9rOiAiICsgZnVsbDsKICB9LAoKICBtYWtlX2Zv
::B64:agent.js:bGRlcjogYXN5bmMgKHsgcGF0aDogcCB9KSA9PiB7CiAgICBjb25zdCBmdWxsID0gcGF0aC5yZXNvbHZlKFN0cmluZyhwKSk7CiAgICBpZiAoIShhd2FpdCBhc2soYEJ1YXQgZm9sZGVyOiAke2Z1bGx9YCkpKSByZXR1cm4gIkRpYmF0YWxrYW4gdXNlciI7CiAgICBm
::B64:agent.js:cy5ta2RpclN5bmMoZnVsbCwgeyByZWN1cnNpdmU6IHRydWUgfSk7CiAgICByZXR1cm4gIm9rOiAiICsgZnVsbDsKICB9LAoKICBtb3ZlX3BhdGg6IGFzeW5jICh7IGZyb20sIHRvIH0pID0+IHsKICAgIGlmICghKGF3YWl0IGFzayhgUGluZGFoa2FuOiAke2Zyb219
::B64:agent.js:ICBrZSAgJHt0b31gKSkpIHJldHVybiAiRGliYXRhbGthbiB1c2VyIjsKICAgIGF3YWl0IHBzKCJNb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRlbnY6U1JDIC1EZXN0aW5hdGlvbiAkZW52OkRFU1QiLCB7CiAgICAgIFNSQzogcGF0aC5yZXNvbHZlKFN0cmluZyhmcm9t
::B64:agent.js:KSksCiAgICAgIERFU1Q6IHBhdGgucmVzb2x2ZShTdHJpbmcodG8pKSwKICAgIH0pOwogICAgcmV0dXJuICJvayI7CiAgfSwKCiAgcmVjeWNsZV9wYXRoOiBhc3luYyAoeyBwYXRoOiBwIH0pID0+IHsKICAgIGNvbnN0IGZ1bGwgPSBwYXRoLnJlc29sdmUoU3RyaW5n
::B64:agent.js:KHApKTsKICAgIGlmICghKGF3YWl0IGFzayhgUGluZGFoa2FuIGtlIFJlY3ljbGUgQmluOiAke2Z1bGx9YCkpKSByZXR1cm4gIkRpYmF0YWxrYW4gdXNlciI7CiAgICBhd2FpdCBwcygKICAgICAgYEFkZC1UeXBlIC1Bc3NlbWJseU5hbWUgTWljcm9zb2Z0LlZpc3Vh
::B64:agent.js:bEJhc2ljCiRwID0gJGVudjpUQVJHRVQKaWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJHAgLVBhdGhUeXBlIENvbnRhaW5lcikgeyBbTWljcm9zb2Z0LlZpc3VhbEJhc2ljLkZpbGVJTy5GaWxlU3lzdGVtXTo6RGVsZXRlRGlyZWN0b3J5KCRwLCAnT25seUVycm9y
::B64:agent.js:RGlhbG9ncycsICdTZW5kVG9SZWN5Y2xlQmluJykgfQplbHNlIHsgW01pY3Jvc29mdC5WaXN1YWxCYXNpYy5GaWxlSU8uRmlsZVN5c3RlbV06OkRlbGV0ZUZpbGUoJHAsICdPbmx5RXJyb3JEaWFsb2dzJywgJ1NlbmRUb1JlY3ljbGVCaW4nKSB9YCwKICAgICAgeyBU
::B64:agent.js:QVJHRVQ6IGZ1bGwgfQogICAgKTsKICAgIHJldHVybiAib2ssIGRpcGluZGFoIGtlIFJlY3ljbGUgQmluIChtYXNpaCBiaXNhIGRpcHVsaWhrYW4pIjsKICB9LAoKICB6aXBfcGF0aDogYXN5bmMgKHsgc291cmNlLCB6aXAgfSkgPT4gewogICAgY29uc3Qgc3JjID0g
::B64:agent.js:cGF0aC5yZXNvbHZlKFN0cmluZyhzb3VyY2UpKTsKICAgIGNvbnN0IGRlc3QgPSBwYXRoLnJlc29sdmUoU3RyaW5nKHppcCkpOwogICAgaWYgKCEoYXdhaXQgYXNrKGBaaXAgJHtzcmN9ICBtZW5qYWRpICAke2Rlc3R9YCkpKSByZXR1cm4gIkRpYmF0YWxrYW4gdXNl
::B64:agent.js:ciI7CiAgICBhd2FpdCBwcygiQ29tcHJlc3MtQXJjaGl2ZSAtTGl0ZXJhbFBhdGggJGVudjpTUkMgLURlc3RpbmF0aW9uUGF0aCAkZW52OkRFU1QgLUZvcmNlIiwgeyBTUkM6IHNyYywgREVTVDogZGVzdCB9LCA2MDAwMDApOwogICAgcmV0dXJuICJvazogIiArIGRl
::B64:agent.js:c3Q7CiAgfSwKCiAgdW56aXBfcGF0aDogYXN5bmMgKHsgemlwLCBmb2xkZXIgfSkgPT4gewogICAgY29uc3Qgc3JjID0gcGF0aC5yZXNvbHZlKFN0cmluZyh6aXApKTsKICAgIGNvbnN0IGRlc3QgPSBwYXRoLnJlc29sdmUoU3RyaW5nKGZvbGRlcikpOwogICAgaWYg
::B64:agent.js:KCEoYXdhaXQgYXNrKGBFa3N0cmFrICR7c3JjfSAga2UgICR7ZGVzdH1gKSkpIHJldHVybiAiRGliYXRhbGthbiB1c2VyIjsKICAgIGF3YWl0IHBzKCJFeHBhbmQtQXJjaGl2ZSAtTGl0ZXJhbFBhdGggJGVudjpTUkMgLURlc3RpbmF0aW9uUGF0aCAkZW52OkRFU1Qg
::B64:agent.js:LUZvcmNlIiwgeyBTUkM6IHNyYywgREVTVDogZGVzdCB9LCA2MDAwMDApOwogICAgcmV0dXJuICJvazogIiArIGRlc3Q7CiAgfSwKCiAgZ2V0X3BhZ2VfdGV4dDogYXN5bmMgKCkgPT4gKGF3YWl0IHBhZ2UuaW5uZXJUZXh0KCJib2R5IikpLnNsaWNlKDAsIDQwMDAp
::B64:agent.js:LAoKICB0eXBlX3RleHQ6IGFzeW5jICh7IHNlbGVjdG9yLCB0ZXh0IH0pID0+IHsKICAgIGF3YWl0IHBhZ2UuZmlsbChzZWxlY3RvciwgdGV4dCk7CiAgICByZXR1cm4gIm9rIjsKICB9LAoKICBjbGljazogYXN5bmMgKHsgc2VsZWN0b3IgfSkgPT4gewogICAgaWYg
::B64:agent.js:KCEoYXdhaXQgYXNrKGBLbGlrIGVsZW1lbiBicm93c2VyOiAke3NlbGVjdG9yfWApKSkgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgYXdhaXQgcGFnZS5jbGljayhzZWxlY3RvciwgeyB0aW1lb3V0OiAxMDAwMCB9KTsKICAgIHJldHVybiAib2siOwogIH0s
::B64:agent.js:CgogIHVwbG9hZF9maWxlOiBhc3luYyAoeyBzZWxlY3RvciwgZmlsZW5hbWUgfSkgPT4gewogICAgY29uc3QgZnVsbCA9IHNhZmVQYXRoKGZpbGVuYW1lKTsKICAgIGlmICghKGF3YWl0IGFzayhgVXBsb2FkIGZpbGU6ICR7ZnVsbH1gKSkpIHJldHVybiAiRGliYXRh
::B64:agent.js:bGthbiB1c2VyIjsKICAgIGF3YWl0IHBhZ2Uuc2V0SW5wdXRGaWxlcyhzZWxlY3RvciwgZnVsbCk7CiAgICByZXR1cm4gIm9rLCBmaWxlIGRpcGlsaWgiOwogIH0sCn07Cgpjb25zdCBmbiA9IChuYW1lLCBkZXNjcmlwdGlvbiwgcHJvcGVydGllcyA9IHt9LCBvcHRp
::B64:agent.js:b25hbCA9IFtdKSA9PiAoewogIHR5cGU6ICJmdW5jdGlvbiIsCiAgZnVuY3Rpb246IHsKICAgIG5hbWUsCiAgICBkZXNjcmlwdGlvbiwKICAgIHBhcmFtZXRlcnM6IHsKICAgICAgdHlwZTogIm9iamVjdCIsCiAgICAgIHByb3BlcnRpZXMsCiAgICAgIHJlcXVpcmVk
::B64:agent.js:OiBPYmplY3Qua2V5cyhwcm9wZXJ0aWVzKS5maWx0ZXIoKGspID0+ICFvcHRpb25hbC5pbmNsdWRlcyhrKSksCiAgICB9LAogIH0sCn0pOwpjb25zdCBzdHIgPSAoZCkgPT4gKHsgdHlwZTogInN0cmluZyIsIGRlc2NyaXB0aW9uOiBkIH0pOwpjb25zdCBudW0gPSAo
::B64:agent.js:ZCkgPT4gKHsgdHlwZTogIm51bWJlciIsIGRlc2NyaXB0aW9uOiBkIH0pOwoKY29uc3QgdG9vbHMgPSBbCiAgZm4oImZpbmRfZm9sZGVyIiwgIkNhcmkgZm9sZGVyIGRpIHNlbHVydWggUEMgKHNlbXVhIGRyaXZlKSBiZXJkYXNhcmthbiBuYW1hOyBzZWJhZ2lhbiBu
::B64:agent.js:YW1hIGN1a3VwIiwgeyBuYW1lOiBzdHIoIk5hbWEgZm9sZGVyIikgfSksCiAgZm4oImZpbmRfZmlsZSIsICJDYXJpIGZpbGUgZGkgc2VsdXJ1aCBQQyAoc2VtdWEgZHJpdmUpIGJlcmRhc2Fya2FuIG5hbWE7IHNlYmFnaWFuIG5hbWEgY3VrdXAiLCB7IG5hbWU6IHN0
::B64:agent.js:cigiTmFtYSBmaWxlIikgfSksCiAgZm4oImxpc3RfZGlyIiwgIkxpaGF0IGlzaSBzZWJ1YWggZm9sZGVyIGRpIFBDIiwgeyBwYXRoOiBzdHIoIlBhdGggbGVuZ2thcCBmb2xkZXIiKSB9KSwKICBmbigib3Blbl9wYXRoIiwgIkJ1a2EgZm9sZGVyLCBmaWxlLCBhcGxp
::B64:agent.js:a2FzaSAobWlzLiBub3RlcGFkKSwgYXRhdSBVUkwgZGkgUEMiLCB7IHRhcmdldDogc3RyKCJQYXRoL25hbWEgYXBsaWthc2kvVVJMIikgfSksCiAgZm4oInNjcmVlbnNob3QiLCAiQW1iaWwgc2NyZWVuc2hvdCBsYXlhciBQQyB1bnR1ayBtZWxpaGF0IGtvbmRpc2kg
::B64:agent.js:c2VrYXJhbmciKSwKICBmbigKICAgICJjbGlja19zY3JlZW4iLAogICAgIktsaWsgZGkgbGF5YXIgUEMgcGFkYSBrb29yZGluYXQgZGFyaSBzY3JlZW5zaG90IHRlcmFraGlyIiwKICAgIHsgeDogbnVtKCJLb29yZGluYXQgWCBkaSBzY3JlZW5zaG90IiksIHk6IG51
::B64:agent.js:bSgiS29vcmRpbmF0IFkgZGkgc2NyZWVuc2hvdCIpLCBidXR0b246IHN0cigibGVmdCBhdGF1IHJpZ2h0IiksIGRvdWJsZTogeyB0eXBlOiAiYm9vbGVhbiIsIGRlc2NyaXB0aW9uOiAiZG91YmxlLWtsaWsiIH0gfSwKICAgIFsiYnV0dG9uIiwgImRvdWJsZSJdCiAg
::B64:agent.js:KSwKICBmbigic2Nyb2xsX3NjcmVlbiIsICJTY3JvbGwgbGF5YXIuIFBvc2l0aWYgPSB0dXJ1biwgbmVnYXRpZiA9IG5haWsiLCB7IGFtb3VudDogbnVtKCJKdW1sYWggc2Nyb2xsIikgfSksCiAgZm4oInR5cGVfZGVza3RvcCIsICJLZXRpayB0ZWtzIGRpIGFwbGlr
::B64:agent.js:YXNpIHlhbmcgc2VkYW5nIGZva3VzIGRpIFBDIiwgeyB0ZXh0OiBzdHIoIlRla3MiKSB9KSwKICBmbigicHJlc3Nfa2V5cyIsICJUZWthbiB0b21ib2wgZm9ybWF0IFNlbmRLZXlzOiB7RU5URVJ9LCB7VEFCfSwge0VTQ30sIF5jIChDdHJsK0MpLCBediwgXmwsICV7
::B64:agent.js:RjR9IiwgeyBrZXlzOiBzdHIoIktvbWJpbmFzaSB0b21ib2wiKSB9KSwKICBmbigid2FpdCIsICJUdW5nZ3UgYmViZXJhcGEgZGV0aWsgKG1ha3MgMTUpIHN1cGF5YSBoYWxhbWFuL2FwbGlrYXNpIHNlbGVzYWkgZGltdWF0IiwgeyBzZWNvbmRzOiBudW0oIkRldGlr
::B64:agent.js:IikgfSksCiAgZm4oImxpc3RfZmlsZXMiLCAiTGloYXQgZGFmdGFyIGZpbGUgZGkgZm9sZGVyIHVwbG9hZCBraHVzdXMiKSwKICBmbigib3Blbl91cmwiLCAiQnVrYSB3ZWJzaXRlIGRpIGJyb3dzZXIgUGxheXdyaWdodCAodW50dWsgb3RvbWFzaSB3ZWIpIiwgeyB1
::B64:agent.js:cmw6IHN0cigiVVJMIGxlbmdrYXAiKSB9KSwKICBmbigiaW5zcGVjdF9wYWdlIiwgIkRhZnRhciB0b21ib2wvaW5wdXQgZGkgaGFsYW1hbiBicm93c2VyIHVudHVrIG1lbmNhcmkgQ1NTIHNlbGVjdG9yIiksCiAgZm4oCiAgICAieW91dHViZV9wbGF5IiwKICAgICJD
::B64:agent.js:YXJpIHZpZGVvIGRpIFlvdVR1YmUgbGFsdSBPVE9NQVRJUyBtZW11dGFyIGhhc2lsIHBpbGloYW4gZGkgYnJvd3NlciBhZ2VudC4gUGFrYWkgaW5pIHVudHVrIHNlbXVhIHBlcm1pbnRhYW4gbm9udG9uL2NhcmkgdmlkZW8vbGFndSBkaSBZb3VUdWJlLiIsCiAgICB7
::B64:agent.js:IHF1ZXJ5OiBzdHIoIkthdGEga3VuY2kgcGVuY2FyaWFuIiksIHBpY2s6IG51bSgiVXJ1dGFuIGhhc2lsIHlhbmcgZGlwdXRhciwgMS01IChkZWZhdWx0IDEpIikgfSwKICAgIFsicGljayJdCiAgKSwKICBmbigiZG9uZSIsICJQYW5nZ2lsIGluaSBqaWthIHR1Z2Fz
::B64:agent.js:IFNFTEVTQUksIGF0YXUgamlrYSBwZXJsdSBiZXJ0YW55YS9tZWxhcG9yIGtlIHVzZXIiLCB7IG1lc3NhZ2U6IHN0cigiUGVzYW4gc2luZ2thdCB1bnR1ayB1c2VyIikgfSksCiAgZm4oCiAgICAieW91dHViZV9jb250cm9sIiwKICAgICJLb250cm9sIHZpZGVvIFlv
::B64:agent.js:dVR1YmUgeWFuZyBzZWRhbmcgdGVyYnVrYSIsCiAgICB7IGFjdGlvbjogc3RyKCJwbGF5LCBwYXVzZSwgdG9nZ2xlLCBtdXRlLCB1bm11dGUsIGZvcndhcmQsIGJhY2t3YXJkLCBuZXh0LCBwcmV2aW91cywgZnVsbHNjcmVlbiIpLCBzZWNvbmRzOiBudW0oIkRldGlr
::B64:agent.js:IHVudHVrIGZvcndhcmQvYmFja3dhcmQgKGRlZmF1bHQgMTApIikgfSwKICAgIFsic2Vjb25kcyJdCiAgKSwKICBmbigid2ViX3NlYXJjaCIsICJDYXJpIGluZm9ybWFzaSBkaSBpbnRlcm5ldCwgbWVuZ2VtYmFsaWthbiBqdWR1bCwgbGluaywgZGFuIGN1cGxpa2Fu
::B64:agent.js:IGhhc2lsIiwgeyBxdWVyeTogc3RyKCJLYXRhIGt1bmNpIikgfSksCiAgZm4oInNjcm9sbF9wYWdlIiwgIlNjcm9sbCBoYWxhbWFuIGJyb3dzZXIuIFBvc2l0aWYgPSB0dXJ1biwgbmVnYXRpZiA9IG5haWsiLCB7IGFtb3VudDogbnVtKCJKdW1sYWggc2Nyb2xsIikg
::B64:agent.js:fSksCiAgZm4oIndhaXRfZm9yX3VzZXIiLCAiQmVyaGVudGkgZGFuIG1pbnRhIHVzZXIgbWVsYWt1a2FuIHNlc3VhdHUgc2VuZGlyaSAobG9naW4sIGNhcHRjaGEsIHZlcmlmaWthc2kpLCBsYWx1IHR1bmdndSBFbnRlciIsIHsgbWVzc2FnZTogc3RyKCJJbnN0cnVr
::B64:agent.js:c2kgdW50dWsgdXNlciIpIH0pLAogIGZuKCJkb3dubG9hZF9maWxlIiwgIlVuZHVoIGZpbGUgZGFyaSBpbnRlcm5ldCBrZSBmb2xkZXIgRG93bmxvYWRzIiwgeyB1cmw6IHN0cigiVVJMIGh0dHAocykiKSwgZmlsZW5hbWU6IHN0cigiTmFtYSBmaWxlIChvcHNpb25h
::B64:agent.js:bCkiKSB9LCBbImZpbGVuYW1lIl0pLAogIGZuKCJub3ciLCAiVGFuZ2dhbCBkYW4gamFtIHNla2FyYW5nIiksCiAgZm4oInN5c3RlbV9pbmZvIiwgIkluZm8gUEM6IE9TLCBDUFUsIFJBTSwgYmF0ZXJhaSwgcnVhbmcgZGlzayIpLAogIGZuKAogICAgIm1lZGlhX2tl
::B64:agent.js:eSIsCiAgICAiVG9tYm9sIG1lZGlhIGRhbiB2b2x1bWUgZ2xvYmFsIFdpbmRvd3MiLAogICAgeyBrZXk6IHN0cigidm9sdXAsIHZvbGRvd24sIG11dGUsIHBsYXlwYXVzZSwgbmV4dCwgcHJldiIpLCB0aW1lczogbnVtKCJKdW1sYWggdGVrYW4gKHZvbHVtZSBiZXJ1
::B64:agent.js:YmFoIDIlIHBlciB0ZWthbikiKSB9LAogICAgWyJ0aW1lcyJdCiAgKSwKICBmbigiY2xpcGJvYXJkX2dldCIsICJCYWNhIGlzaSBjbGlwYm9hcmQiKSwKICBmbigiY2xpcGJvYXJkX3NldCIsICJJc2kgY2xpcGJvYXJkIiwgeyB0ZXh0OiBzdHIoIlRla3MiKSB9KSwK
::B64:agent.js:ICBmbigibGlzdF93aW5kb3dzIiwgIkRhZnRhciBqZW5kZWxhIGF0YXUgYXBsaWthc2kgeWFuZyBzZWRhbmcgdGVyYnVrYSIpLAogIGZuKCJmb2N1c193aW5kb3ciLCAiUGluZGFoa2FuIGZva3VzIGtlIHNlYnVhaCBqZW5kZWxhIiwgeyB0aXRsZTogc3RyKCJTZWJh
::B64:agent.js:Z2lhbiBqdWR1bCBqZW5kZWxhIikgfSksCiAgZm4oImNsb3NlX3dpbmRvdyIsICJUdXR1cCBzZWJ1YWggamVuZGVsYSBkZW5nYW4gYmFpay1iYWlrIiwgeyB0aXRsZTogc3RyKCJTZWJhZ2lhbiBqdWR1bCBqZW5kZWxhIikgfSksCiAgZm4oInJlYWRfdGV4dF9maWxl
::B64:agent.js:IiwgIkJhY2EgaXNpIGZpbGUgdGVrcyIsIHsgcGF0aDogc3RyKCJQYXRoIGxlbmdrYXAgZmlsZSIpIH0pLAogIGZuKCJ3cml0ZV90ZXh0X2ZpbGUiLCAiVHVsaXMgYXRhdSB0YW1iYWggaXNpIGZpbGUgdGVrcyIsIHsgcGF0aDogc3RyKCJQYXRoIGxlbmdrYXAgZmls
::B64:agent.js:ZSIpLCBjb250ZW50OiBzdHIoIklzaSIpLCBhcHBlbmQ6IHsgdHlwZTogImJvb2xlYW4iLCBkZXNjcmlwdGlvbjogInRydWUgPSB0YW1iYWhrYW4sIGJ1a2FuIG1lbmltcGEiIH0gfSwgWyJhcHBlbmQiXSksCiAgZm4oIm1ha2VfZm9sZGVyIiwgIkJ1YXQgZm9sZGVy
::B64:agent.js:IGJhcnUiLCB7IHBhdGg6IHN0cigiUGF0aCBsZW5na2FwIGZvbGRlciIpIH0pLAogIGZuKCJtb3ZlX3BhdGgiLCAiUGluZGFoa2FuIGF0YXUgZ2FudGkgbmFtYSBmaWxlL2ZvbGRlciIsIHsgZnJvbTogc3RyKCJQYXRoIGFzYWwiKSwgdG86IHN0cigiUGF0aCB0dWp1
::B64:agent.js:YW4iKSB9KSwKICBmbigicmVjeWNsZV9wYXRoIiwgIkhhcHVzIGZpbGUvZm9sZGVyIGRlbmdhbiBtZW1pbmRhaGthbm55YSBrZSBSZWN5Y2xlIEJpbiIsIHsgcGF0aDogc3RyKCJQYXRoIGxlbmdrYXAiKSB9KSwKICBmbigiemlwX3BhdGgiLCAiS29tcHJlcyBmaWxl
::B64:agent.js:IGF0YXUgZm9sZGVyIG1lbmphZGkgLnppcCIsIHsgc291cmNlOiBzdHIoIlBhdGggZmlsZS9mb2xkZXIiKSwgemlwOiBzdHIoIlBhdGggZmlsZSAuemlwIGhhc2lsIikgfSksCiAgZm4oInVuemlwX3BhdGgiLCAiRWtzdHJhayBmaWxlIC56aXAiLCB7IHppcDogc3Ry
::B64:agent.js:KCJQYXRoIGZpbGUgLnppcCIpLCBmb2xkZXI6IHN0cigiRm9sZGVyIHR1anVhbiIpIH0pLAogIGZuKCJnZXRfcGFnZV90ZXh0IiwgIkJhY2EgdGVrcyBoYWxhbWFuIGJyb3dzZXIgc2FhdCBpbmkiKSwKICBmbigidHlwZV90ZXh0IiwgIklzaSBrb2xvbSB0ZWtzIGRp
::B64:agent.js:IGJyb3dzZXIiLCB7IHNlbGVjdG9yOiBzdHIoIkNTUyBzZWxlY3RvciIpLCB0ZXh0OiBzdHIoIlRla3MiKSB9KSwKICBmbigiY2xpY2siLCAiS2xpayBlbGVtZW4gZGkgYnJvd3NlciIsIHsgc2VsZWN0b3I6IHN0cigiQ1NTIHNlbGVjdG9yIikgfSksCiAgZm4oInVw
::B64:agent.js:bG9hZF9maWxlIiwgIlVwbG9hZCBmaWxlIGtlIGlucHV0IGZpbGUgZGkgYnJvd3NlciIsIHsKICAgIHNlbGVjdG9yOiBzdHIoIkNTUyBzZWxlY3RvciBpbnB1dFt0eXBlPWZpbGVdIiksCiAgICBmaWxlbmFtZTogc3RyKCJQYXRoIGxlbmdrYXAgZmlsZSBkaSBtYW5h
::B64:agent.js:IHNhamEgZGkgUEMsIGF0YXUgbmFtYSBmaWxlIGRpIHVwbG9hZC1mb2xkZXIiKSwKICB9KSwKXTsKCmNvbnN0IFNZU1RFTSA9IGBLYW11IGFnZW50IHlhbmcgbWVuZ29udHJvbCBQQyBXaW5kb3dzIG1pbGlrIHVzZXIgZGFuIGJyb3dzZXIuIEtlcmpha2FuIHBlcmlu
::B64:agent.js:dGFoIHVzZXIgZGVuZ2FuIG1lbWFuZ2dpbCB0b29sLgpBVFVSQU4gUEVOVElORzoKLSBLYW11IEhBUlVTIHNlbGFsdSBtZW1hbmdnaWwgdG9vbCBkaSBzZXRpYXAgbGFuZ2thaC4gSkFOR0FOIHBlcm5haCBtZW51bGlzIHJlbmNhbmEsIG5hcmFzaSwgYXRhdSAic2F5
::B64:agent.js:YSBha2FuIC4uLiIuIExhbmdzdW5nIHBhbmdnaWwgdG9vbC1ueWEuCi0gU2V0ZWxhaCB0dWdhcyBzZWxlc2FpIChhdGF1IHBlcmx1IGJlcnRhbnlhIGtlIHVzZXIpLCBwYW5nZ2lsIHRvb2wgZG9uZSBkZW5nYW4gcGVzYW4gc2luZ2thdC4KLSBOb250b24vY2FyaSB2
::B64:agent.js:aWRlby9sYWd1IGRpIFlvdVR1YmU6IGxhbmdzdW5nIHBhbmdnaWwgeW91dHViZV9wbGF5IGRlbmdhbiBrYXRhIGt1bmNpIGRhcmkgdXNlci4gSmlrYSBqdWR1bCB5YW5nIGRpcHV0YXIga3VyYW5nIGNvY29rLCBwYW5nZ2lsIGxhZ2kgZGVuZ2FuIHBpY2sgbGFpbi4K
::B64:agent.js:LSBUYWZzaXJrYW4gcGVyaW50YWggc2luZ2thdC90eXBvIHVzZXIgZGVuZ2FuIHdhamFyLCBqYW5nYW4gYmVydGFueWEgaGFsIHlhbmcgYmlzYSBkaXRlYmFrLgotIEthbXUgbWVuZ2luZ2F0IHBlcmNha2FwYW4gc2ViZWx1bW55YS4gSmF3YWJhbiBzaW5na2F0IHVz
::B64:agent.js:ZXIgKG1pc2FsbnlhIHNlYnVhaCBuYW1hIGZpbGUpIGFkYWxhaCBqYXdhYmFuIGF0YXMgcGVydGFueWFhbm11IHNlYmVsdW1ueWE7IGxhbmp1dGthbiB0dWdhcyBpdHUsIGphbmdhbiBtdWxhaSBkYXJpIG5vbC4KLSBNZW1idWthIGFwbGlrYXNpIFdpbmRvd3MgbGV3
::B64:agent.js:YXQgb3Blbl9wYXRoOiBrYW1lcmEgPSBtaWNyb3NvZnQud2luZG93cy5jYW1lcmE6ICwga2Fsa3VsYXRvciA9IGNhbGMgLCBub3RlcGFkID0gbm90ZXBhZCAsIHBhaW50ID0gbXNwYWludCAsIHBlbmdhdHVyYW4gPSBtcy1zZXR0aW5nczogLCBmaWxlIGV4cGxvcmVy
::B64:agent.js:ID0gZXhwbG9yZXIgLgotIFVwbG9hZCBmaWxlIGtlIHdlYnNpdGU6IG9wZW5fdXJsIGtlIGhhbGFtYW4gdXBsb2FkLCBpbnNwZWN0X3BhZ2UgdW50dWsgbWVuY2FyaSBpbnB1dCB0eXBlPWZpbGUsIGxhbHUgdXBsb2FkX2ZpbGUgZGVuZ2FuIHBhdGggbGVuZ2thcCBm
::B64:agent.js:aWxlLiBKaWthIGJ1dHVoIGxvZ2luLCBwYW5nZ2lsIGRvbmUgZGFuIG1pbnRhIHVzZXIgbG9naW4gbWFudWFsIGRpIGplbmRlbGEgYnJvd3NlciwgbGFsdSB1bGFuZ2kuCi0gRm9sZGVyIGRpIFBDOiBmaW5kX2ZvbGRlciBsYWx1IG9wZW5fcGF0aC4gRmlsZSBkaSBQ
::B64:agent.js:QzogZmluZF9maWxlIChhdGF1IGxpc3RfZGlyKSB1bnR1ayBtZW5kYXBhdCBwYXRoIGxlbmdrYXAsIGxhbHUgb3Blbl9wYXRoIGF0YXUgdXBsb2FkX2ZpbGUuIFRpZGFrIGFkYSBiYXRhc2FuIGxva2FzaSwgc2VtdWEgZHJpdmUgYm9sZWggZGlha3Nlcy4KLSBBcGxp
::B64:agent.js:a2FzaS9qZW5kZWxhIGRpIFBDOiBzY3JlZW5zaG90IGR1bHUgdW50dWsgbWVsaWhhdCBsYXlhciwgbGFsdSBjbGlja19zY3JlZW4vdHlwZV9kZXNrdG9wL3ByZXNzX2tleXMsIGxhbHUgc2NyZWVuc2hvdCBsYWdpIHVudHVrIG1lbWVyaWtzYSBoYXNpbC4KLSBLb29y
::B64:agent.js:ZGluYXQga2xpayBoYXJ1cyBkYXJpIHNjcmVlbnNob3QgdGVyYWtoaXIuCi0gVW50dWsgb3RvbWFzaSB3ZWJzaXRlIHBha2FpIHRvb2wgYnJvd3NlciAob3Blbl91cmwsIGluc3BlY3RfcGFnZSwgdHlwZV90ZXh0LCBjbGljaywgdXBsb2FkX2ZpbGUpLiBTZWxhbHUg
::B64:agent.js:aW5zcGVjdF9wYWdlIHNlYmVsdW0ga2xpay4KLSBCdXR1aCBsb2dpbiwgY2FwdGNoYSwgYXRhdSB2ZXJpZmlrYXNpOiBwYW5nZ2lsIHdhaXRfZm9yX3VzZXIgZGFuIG1pbnRhIHVzZXIgbWVuZ2VyamFrYW5ueWEgc2VuZGlyaSBkaSBqZW5kZWxhIGJyb3dzZXIuIEpB
::B64:agent.js:TkdBTiBwZXJuYWggbWVtaW50YSBhdGF1IG1lbmdldGlra2FuIHBhc3N3b3JkIHVzZXIuCi0gUGVydGFueWFhbiB5YW5nIGJ1dHVoIGluZm8gdGVyYmFydTogd2ViX3NlYXJjaCwgbGFsdSBvcGVuX3VybCBkYW4gZ2V0X3BhZ2VfdGV4dCB1bnR1ayBtZW1iYWNhIHN1
::B64:agent.js:bWJlcm55YS4KLSBLb250cm9sIG11c2lrL3ZpZGVvOiB5b3V0dWJlX2NvbnRyb2wgdW50dWsgdmlkZW8gWW91VHViZSwgbWVkaWFfa2V5IHVudHVrIHZvbHVtZSBkYW4gdG9tYm9sIG1lZGlhIHNlbHVydWggUEMuCi0gTWVuZ2hhcHVzIGZpbGU6IHBha2FpIHJlY3lj
::B64:agent.js:bGVfcGF0aCAobWFzdWsgUmVjeWNsZSBCaW4pLCBqYW5nYW4gbWVuZ2hhcHVzIHBlcm1hbmVuLgotIEppa2EgYnVudHUgYXRhdSByYWd1LCBiZXJoZW50aSBkYW4gdGFueWEgdXNlci4KLSBKYXdhYiBkYWxhbSBCYWhhc2EgSW5kb25lc2lhLCBzaW5na2F0LiBKYW5n
::B64:agent.js:YW4gbWVuZ2FyYW5nIGhhc2lsOyBsYXBvcmthbiBhcGEgYWRhbnlhLmA7CgovLyA9PT09PSBLb211bmlrYXNpIGRlbmdhbiA5Um91dGVyICh0YWhhbiBiYW50aW5nOiBjb2JhIHVsYW5nIG90b21hdGlzKSA9PT09PQpsZXQgdXNlVG9vbENob2ljZSA9IHRydWU7IC8v
::B64:agent.js:IHBha3NhIG1vZGVsIHNlbGFsdSBtZW1hbmdnaWwgdG9vbDsgZGltYXRpa2FuIG90b21hdGlzIGppa2EgYmVybWFzYWxhaAoKZnVuY3Rpb24gZmF0YWwobXNnKSB7CiAgY29uc3QgZSA9IG5ldyBFcnJvcihtc2cpOwogIGUuZmF0YWwgPSB0cnVlOwogIHJldHVybiBl
::B64:agent.js:Owp9Cgphc3luYyBmdW5jdGlvbiByZXF1ZXN0T25jZShtZXNzYWdlcykgewogIGNvbnN0IGJvZHkgPSB7IG1vZGVsOiBNT0RFTCwgbWVzc2FnZXMsIHRvb2xzLCBzdHJlYW06IHRydWUgfTsKICBpZiAodXNlVG9vbENob2ljZSkgYm9keS50b29sX2Nob2ljZSA9ICJy
::B64:agent.js:ZXF1aXJlZCI7CiAgY29uc3QgcmVzID0gYXdhaXQgZmV0Y2goYCR7QkFTRV9VUkx9L2NoYXQvY29tcGxldGlvbnNgLCB7CiAgICBtZXRob2Q6ICJQT1NUIiwKICAgIGhlYWRlcnM6IHsgIkNvbnRlbnQtVHlwZSI6ICJhcHBsaWNhdGlvbi9qc29uIiwgQXV0aG9yaXph
::B64:agent.js:dGlvbjogYEJlYXJlciAke0FQSV9LRVl9YCB9LAogICAgYm9keTogSlNPTi5zdHJpbmdpZnkoYm9keSksCiAgICBzaWduYWw6IEFib3J0U2lnbmFsLnRpbWVvdXQoMTIwMDAwKSwKICB9KTsKCiAgaWYgKCFyZXMub2spIHsKICAgIGNvbnN0IGVyclRleHQgPSAoYXdh
::B64:agent.js:aXQgcmVzLnRleHQoKSkuc2xpY2UoMCwgMzAwKTsKICAgIGlmIChyZXMuc3RhdHVzID09PSA0MDEgfHwgcmVzLnN0YXR1cyA9PT0gNDAzKSB0aHJvdyBmYXRhbChgQVBJIGtleSBkaXRvbGFrICgke3Jlcy5zdGF0dXN9KS4gSmFsYW5rYW46IHN0YXJ0LWFnZW50LmJh
::B64:agent.js:dCByZXNldGApOwogICAgaWYgKHJlcy5zdGF0dXMgPT09IDQwNCkgdGhyb3cgZmF0YWwoYE1vZGVsIGF0YXUgZW5kcG9pbnQgdGlkYWsgZGl0ZW11a2FuICg0MDQpLiBDZWsgbmFtYSBjb21ibzogJHtNT0RFTH0uICR7ZXJyVGV4dH1gKTsKICAgIGlmIChyZXMuc3Rh
::B64:agent.js:dHVzID09PSA0MDApIHVzZVRvb2xDaG9pY2UgPSBmYWxzZTsKICAgIHRocm93IG5ldyBFcnJvcihgSFRUUCAke3Jlcy5zdGF0dXN9ICR7ZXJyVGV4dH1gKTsKICB9CgogIGNvbnN0IHJhdyA9IGF3YWl0IHJlcy50ZXh0KCk7CiAgaWYgKCFyYXcudHJpbSgpKSByZXR1
::B64:agent.js:cm4gbnVsbDsgLy8gYmFsYXNhbiBrb3NvbmcKCiAgLy8gQmFsYXNhbiBKU09OIGJpYXNhIChidWthbiBzdHJlYW1pbmcpCiAgaWYgKCEvKF58XG4pZGF0YTovLnRlc3QocmF3KSkgewogICAgbGV0IG9iajsKICAgIHRyeSB7CiAgICAgIG9iaiA9IEpTT04ucGFyc2Uo
::B64:agent.js:cmF3KTsKICAgIH0gY2F0Y2ggewogICAgICByZXR1cm4gbnVsbDsKICAgIH0KICAgIGlmIChvYmouZXJyb3IpIHRocm93IG5ldyBFcnJvcihKU09OLnN0cmluZ2lmeShvYmouZXJyb3IpLnNsaWNlKDAsIDIwMCkpOwogICAgcmV0dXJuIG9iai5jaG9pY2VzPy5bMF0/
::B64:agent.js:Lm1lc3NhZ2UgPz8gbnVsbDsKICB9CgogIC8vIEJhbGFzYW4gc3RyZWFtaW5nIChTU0UpOiBnYWJ1bmdrYW4gcG90b25nYW4gbWVuamFkaSBzYXR1IHBlc2FuIHV0dWgKICBsZXQgY29udGVudCA9ICIiOwogIGxldCBzc2VFcnIgPSAiIjsKICBjb25zdCBjYWxscyA9
::B64:agent.js:IFtdOwogIGZvciAoY29uc3QgbGluZSBvZiByYXcuc3BsaXQoIlxuIikpIHsKICAgIGlmICghbGluZS5zdGFydHNXaXRoKCJkYXRhOiIpKSBjb250aW51ZTsKICAgIGNvbnN0IGRhdGEgPSBsaW5lLnNsaWNlKDUpLnRyaW0oKTsKICAgIGlmICghZGF0YSB8fCBkYXRh
::B64:agent.js:ID09PSAiW0RPTkVdIikgY29udGludWU7CiAgICBsZXQgY2h1bms7CiAgICB0cnkgewogICAgICBjaHVuayA9IEpTT04ucGFyc2UoZGF0YSk7CiAgICB9IGNhdGNoIHsKICAgICAgY29udGludWU7CiAgICB9CiAgICBpZiAoY2h1bmsuZXJyb3IpIHNzZUVyciA9IEpT
::B64:agent.js:T04uc3RyaW5naWZ5KGNodW5rLmVycm9yKS5zbGljZSgwLCAyMDApOwogICAgY29uc3QgY2hvaWNlID0gY2h1bmsuY2hvaWNlcz8uWzBdOwogICAgY29uc3QgZGVsdGEgPSBjaG9pY2U/LmRlbHRhIHx8IGNob2ljZT8ubWVzc2FnZSB8fCB7fTsKICAgIGlmIChkZWx0
::B64:agent.js:YS5jb250ZW50KSBjb250ZW50ICs9IGRlbHRhLmNvbnRlbnQ7CiAgICBmb3IgKGNvbnN0IHRjIG9mIGRlbHRhLnRvb2xfY2FsbHMgfHwgW10pIHsKICAgICAgY29uc3QgaSA9IHRjLmluZGV4ID8/IDA7CiAgICAgIGNhbGxzW2ldID8/PSB7IGlkOiAiIiwgdHlwZTog
::B64:agent.js:ImZ1bmN0aW9uIiwgZnVuY3Rpb246IHsgbmFtZTogIiIsIGFyZ3VtZW50czogIiIgfSB9OwogICAgICBpZiAodGMuaWQpIGNhbGxzW2ldLmlkID0gdGMuaWQ7CiAgICAgIGlmICh0Yy5mdW5jdGlvbj8ubmFtZSkgY2FsbHNbaV0uZnVuY3Rpb24ubmFtZSArPSB0Yy5m
::B64:agent.js:dW5jdGlvbi5uYW1lOwogICAgICBpZiAodGMuZnVuY3Rpb24/LmFyZ3VtZW50cykgY2FsbHNbaV0uZnVuY3Rpb24uYXJndW1lbnRzICs9IHRjLmZ1bmN0aW9uLmFyZ3VtZW50czsKICAgIH0KICB9CiAgY29uc3QgdmFsaWQgPSBjYWxscy5maWx0ZXIoQm9vbGVhbiku
::B64:agent.js:bWFwKChjLCBpKSA9PiAoeyAuLi5jLCBpZDogYy5pZCB8fCBgY2FsbF8ke2l9YCB9KSk7CiAgaWYgKCFjb250ZW50ICYmICF2YWxpZC5sZW5ndGgpIHsKICAgIGlmIChzc2VFcnIpIHRocm93IG5ldyBFcnJvcihzc2VFcnIpOwogICAgcmV0dXJuIG51bGw7CiAgfQog
::B64:agent.js:IGNvbnN0IG1zZyA9IHsgcm9sZTogImFzc2lzdGFudCIsIGNvbnRlbnQ6IGNvbnRlbnQgfHwgbnVsbCB9OwogIGlmICh2YWxpZC5sZW5ndGgpIG1zZy50b29sX2NhbGxzID0gdmFsaWQ7CiAgcmV0dXJuIG1zZzsKfQoKYXN5bmMgZnVuY3Rpb24gY2FsbExMTShtZXNz
::B64:agent.js:YWdlcykgewogIGxldCBsYXN0RXJyID0gInJlc3BvbnMga29zb25nIjsKICBmb3IgKGxldCBhdHRlbXB0ID0gMTsgYXR0ZW1wdCA8PSA0OyBhdHRlbXB0KyspIHsKICAgIHRyeSB7CiAgICAgIGNvbnN0IG1zZyA9IGF3YWl0IHJlcXVlc3RPbmNlKG1lc3NhZ2VzKTsK
::B64:agent.js:ICAgICAgaWYgKG1zZykgewogICAgICAgIGNvbnN0IGNsZWFuID0geyByb2xlOiAiYXNzaXN0YW50IiwgY29udGVudDogbXNnLmNvbnRlbnQgPz8gbnVsbCB9OwogICAgICAgIGlmIChtc2cudG9vbF9jYWxscz8ubGVuZ3RoKSBjbGVhbi50b29sX2NhbGxzID0gbXNn
::B64:agent.js:LnRvb2xfY2FsbHM7CiAgICAgICAgcmV0dXJuIGNsZWFuOwogICAgICB9CiAgICAgIGxhc3RFcnIgPSAicmVzcG9ucyBrb3NvbmciOwogICAgfSBjYXRjaCAoZSkgewogICAgICBpZiAoZS5mYXRhbCkgdGhyb3cgZTsKICAgICAgbGFzdEVyciA9IGUubWVzc2FnZTsK
::B64:agent.js:ICAgIH0KICAgIGlmIChhdHRlbXB0ID09PSAyKSB1c2VUb29sQ2hvaWNlID0gZmFsc2U7IC8vIHNldGVsYWggMnggZ2FnYWwsIGNvYmEgdGFucGEgdG9vbF9jaG9pY2UKICAgIGlmIChhdHRlbXB0IDwgNCkgewogICAgICBjb25zb2xlLmxvZyhgICAoOVJvdXRlciBi
::B64:agent.js:ZXJtYXNhbGFoOiAke2xhc3RFcnIuc2xpY2UoMCwgMTIwKX0uIE1lbmNvYmEgdWxhbmcgJHthdHRlbXB0fS8zLi4uKWApOwogICAgICBhd2FpdCBzbGVlcCgxMDAwICogYXR0ZW1wdCk7CiAgICB9CiAgfQogIHRocm93IG5ldyBFcnJvcigKICAgIGA5Um91dGVyIGdh
::B64:agent.js:Z2FsIG1lcmVzcG9ucyBzZXRlbGFoIDQgcGVyY29iYWFuICgke2xhc3RFcnIuc2xpY2UoMCwgMTUwKX0pLiBgICsKICAgICAgYENlayBtZW51IENvbnNvbGUgTG9nIGRpIGRhc2hib2FyZCA5Um91dGVyLCBkYW4gcGFzdGlrYW4gY29tYm8gbWVtYWthaSBtb2RlbCB5
::B64:agent.js:YW5nIG1lbmR1a3VuZyB0b29sIGNhbGxpbmcuYAogICk7Cn0KCi8vID09PT09IE1lbW9yaSBwZXJjYWthcGFuID09PT09CmNvbnN0IGhpc3RvcnkgPSBbXTsKY29uc3QgTUFYX0hJU1RPUlkgPSA0MDsKCmZ1bmN0aW9uIHN0cmlwSW1hZ2VzKCkgewogIGZvciAoY29u
::B64:agent.js:c3QgbSBvZiBoaXN0b3J5KSB7CiAgICBpZiAobS5yb2xlID09PSAidXNlciIgJiYgQXJyYXkuaXNBcnJheShtLmNvbnRlbnQpKSB7CiAgICAgIG0uY29udGVudCA9ICJbc2NyZWVuc2hvdCBsYW1hIGRpaGFwdXMgdW50dWsgbWVuZ2hlbWF0IG1lbW9yaV0iOwogICAg
::B64:agent.js:fQogIH0KfQoKZnVuY3Rpb24gdHJpbUhpc3RvcnkoKSB7CiAgd2hpbGUgKGhpc3RvcnkubGVuZ3RoID4gTUFYX0hJU1RPUlkpIHsKICAgIGxldCBpID0gMTsKICAgIHdoaWxlIChpIDwgaGlzdG9yeS5sZW5ndGggJiYgIShoaXN0b3J5W2ldLnJvbGUgPT09ICJ1c2Vy
::B64:agent.js:IiAmJiB0eXBlb2YgaGlzdG9yeVtpXS5jb250ZW50ID09PSAic3RyaW5nIikpIGkrKzsKICAgIGlmIChpID49IGhpc3RvcnkubGVuZ3RoKSBicmVhazsKICAgIGhpc3Rvcnkuc3BsaWNlKDAsIGkpOwogIH0KfQoKYXN5bmMgZnVuY3Rpb24gcnVuVGFzayhjb21tYW5k
::B64:agent.js:KSB7CiAgY29uc3Qgc3RhcnRMZW4gPSBoaXN0b3J5Lmxlbmd0aDsKICBoaXN0b3J5LnB1c2goeyByb2xlOiAidXNlciIsIGNvbnRlbnQ6IGNvbW1hbmQgfSk7CiAgbGV0IG51ZGdlcyA9IDA7CgogIHRyeSB7CiAgICBmb3IgKGxldCBzdGVwID0gMTsgc3RlcCA8PSBN
::B64:agent.js:QVhfU1RFUFM7IHN0ZXArKykgewogICAgICBjb25zdCBtc2cgPSBhd2FpdCBjYWxsTExNKFt7IHJvbGU6ICJzeXN0ZW0iLCBjb250ZW50OiBTWVNURU0gfSwgLi4uaGlzdG9yeV0pOwogICAgICBoaXN0b3J5LnB1c2gobXNnKTsKCiAgICAgIGlmICghbXNnLnRvb2xf
::B64:agent.js:Y2FsbHM/Lmxlbmd0aCkgewogICAgICAgIC8vIE1vZGVsIGN1bWEgbWVudWxpcyB0ZWtzL3JlbmNhbmEgdGFucGEgbWVtYW5nZ2lsIHRvb2wgLT4gcGFrc2EgcGFuZ2dpbCB0b29sCiAgICAgICAgaWYgKG51ZGdlcyA8IDMpIHsKICAgICAgICAgIG51ZGdlcysrOwog
::B64:agent.js:ICAgICAgICAgaGlzdG9yeS5wdXNoKHsKICAgICAgICAgICAgcm9sZTogInVzZXIiLAogICAgICAgICAgICBjb250ZW50OiAiS2FtdSBoYXJ1cyBtZW1hbmdnaWwgdG9vbC4gSmFuZ2FuIG1lbnVsaXMgdGVrcyBiaWFzYS4gTGFuZ3N1bmcgcGFuZ2dpbCB0b29sIHlh
::B64:agent.js:bmcgc2VzdWFpLCBhdGF1IHBhbmdnaWwgZG9uZSBqaWthIHR1Z2FzIHN1ZGFoIHNlbGVzYWkuIiwKICAgICAgICAgIH0pOwogICAgICAgICAgY29udGludWU7CiAgICAgICAgfQogICAgICAgIGNvbnNvbGUubG9nKCJcbkFnZW50OiIsIG1zZy5jb250ZW50IHx8ICIo
::B64:agent.js:dGlkYWsgYWRhIGphd2FiYW4pIik7CiAgICAgICAgcmV0dXJuOwogICAgICB9CgogICAgICAvLyBUdWdhcyBzZWxlc2FpOiBzZW11YSB0b29sX2NhbGwgd2FqaWIgZGlqYXdhYiBhZ2FyIHJpd2F5YXQgdGV0YXAgdmFsaWQKICAgICAgY29uc3QgZG9uZUNhbGwgPSBt
::B64:agent.js:c2cudG9vbF9jYWxscy5maW5kKChjKSA9PiBjLmZ1bmN0aW9uLm5hbWUgPT09ICJkb25lIik7CiAgICAgIGlmIChkb25lQ2FsbCkgewogICAgICAgIGxldCBtID0gIiI7CiAgICAgICAgdHJ5IHsKICAgICAgICAgIG0gPSBKU09OLnBhcnNlKGRvbmVDYWxsLmZ1bmN0
::B64:agent.js:aW9uLmFyZ3VtZW50cyB8fCAie30iKS5tZXNzYWdlIHx8ICIiOwogICAgICAgIH0gY2F0Y2gge30KICAgICAgICBmb3IgKGNvbnN0IGNhbGwgb2YgbXNnLnRvb2xfY2FsbHMpIHsKICAgICAgICAgIGhpc3RvcnkucHVzaCh7IHJvbGU6ICJ0b29sIiwgdG9vbF9jYWxs
::B64:agent.js:X2lkOiBjYWxsLmlkLCBjb250ZW50OiBjYWxsID09PSBkb25lQ2FsbCA/ICJvayIgOiAiZGlsZXdhdGkiIH0pOwogICAgICAgIH0KICAgICAgICBjb25zb2xlLmxvZygiXG5BZ2VudDoiLCBtIHx8ICJTZWxlc2FpLiIpOwogICAgICAgIHJldHVybjsKICAgICAgfQoK
::B64:agent.js:ICAgICAgZm9yIChjb25zdCBjYWxsIG9mIG1zZy50b29sX2NhbGxzKSB7CiAgICAgICAgY29uc3QgbmFtZSA9IGNhbGwuZnVuY3Rpb24ubmFtZTsKICAgICAgICBsZXQgcmVzdWx0OwogICAgICAgIHRyeSB7CiAgICAgICAgICBjb25zdCBhcmdzID0gSlNPTi5wYXJz
::B64:agent.js:ZShjYWxsLmZ1bmN0aW9uLmFyZ3VtZW50cyB8fCAie30iKTsKICAgICAgICAgIGNvbnNvbGUubG9nKGBbJHtzdGVwfV0gJHtuYW1lfWAsIGFyZ3MpOwogICAgICAgICAgaWYgKCFpbXBsW25hbWVdKSB0aHJvdyBuZXcgRXJyb3IoIlRvb2wgdGlkYWsgZGlrZW5hbDog
::B64:agent.js:IiArIG5hbWUpOwogICAgICAgICAgYXdhaXQgZW5zdXJlUGFnZSgpOwogICAgICAgICAgcmVzdWx0ID0gYXdhaXQgaW1wbFtuYW1lXShhcmdzKTsKICAgICAgICB9IGNhdGNoIChlKSB7CiAgICAgICAgICByZXN1bHQgPSAiRVJST1I6ICIgKyBlLm1lc3NhZ2U7CiAg
::B64:agent.js:ICAgICAgfQogICAgICAgIGhpc3RvcnkucHVzaCh7IHJvbGU6ICJ0b29sIiwgdG9vbF9jYWxsX2lkOiBjYWxsLmlkLCBjb250ZW50OiBTdHJpbmcocmVzdWx0KS5zbGljZSgwLCA2MDAwKSB9KTsKICAgICAgfQoKICAgICAgLy8gS2lyaW0gc2NyZWVuc2hvdCAoamlr
::B64:agent.js:YSBhZGEpIHNlYmFnYWkgZ2FtYmFyOyBnYW1iYXIgbGFtYSBkaWJ1YW5nIGFnYXIgcmluZ2FuCiAgICAgIGlmIChwZW5kaW5nSW1hZ2VzLmxlbmd0aCkgewogICAgICAgIHN0cmlwSW1hZ2VzKCk7CiAgICAgICAgaGlzdG9yeS5wdXNoKHsKICAgICAgICAgIHJvbGU6
::B64:agent.js:ICJ1c2VyIiwKICAgICAgICAgIGNvbnRlbnQ6IFsKICAgICAgICAgICAgeyB0eXBlOiAidGV4dCIsIHRleHQ6ICJJbmkgc2NyZWVuc2hvdCBsYXlhciB0ZXJiYXJ1OiIgfSwKICAgICAgICAgICAgLi4ucGVuZGluZ0ltYWdlcy5zcGxpY2UoMCkubWFwKChiNjQpID0+
::B64:agent.js:ICh7CiAgICAgICAgICAgICAgdHlwZTogImltYWdlX3VybCIsCiAgICAgICAgICAgICAgaW1hZ2VfdXJsOiB7IHVybDogYGRhdGE6aW1hZ2UvcG5nO2Jhc2U2NCwke2I2NH1gIH0sCiAgICAgICAgICAgIH0pKSwKICAgICAgICAgIF0sCiAgICAgICAgfSk7CiAgICAg
::B64:agent.js:IH0KICAgICAgYXdhaXQgc2xlZXAoMzAwKTsKICAgIH0KICAgIGNvbnNvbGUubG9nKCJCZXJoZW50aTogbWVsZXdhdGkgYmF0YXMgbGFuZ2thaC4iKTsKICB9IGNhdGNoIChlKSB7CiAgICBoaXN0b3J5Lmxlbmd0aCA9IHN0YXJ0TGVuOyAvLyBidWFuZyByaXdheWF0
::B64:agent.js:IHR1Z2FzIHlhbmcgZ2FnYWwgc3VwYXlhIHRpZGFrIG1lcnVzYWsgcGVyY2FrYXBhbiBiZXJpa3V0bnlhCiAgICB0aHJvdyBlOwogIH0gZmluYWxseSB7CiAgICBzdHJpcEltYWdlcygpOwogICAgdHJpbUhpc3RvcnkoKTsKICB9Cn0KCmNvbnN0IEJVSUxUSU5fQ0hB
::B64:agent.js:TkdFTE9HID0gYFZlcnNpIDQKLSBCcm93c2VyIG1lbWFrYWkgQ2hyb21lL0VkZ2UgYXNsaTogdmlkZW8gWW91VHViZSB0aWRhayBlcnJvciBsYWdpIGRhbiBsb2dpbiBHb29nbGUgYmlzYSBkaWxha3VrYW4uCi0gTG9naW4gc2VrYWxpIGxld2F0IC9sb2dpbiwgc2Vz
::B64:agent.js:aSB0ZXJzaW1wYW4gdW50dWsgc2V0ZXJ1c255YS4KLSBZb3VUdWJlOiBza2lwIGlrbGFuIG90b21hdGlzLCBwaW5kYWgga2UgaGFzaWwgbGFpbiBqaWthIGVycm9yLCBrb250cm9sIHBhdXNlL25leHQvbWFqdS9tdW5kdXIvbXV0ZS9mdWxsc2NyZWVuLgotIENhcmkg
::B64:agent.js:ZGkgd2ViLCB1bmR1aCBmaWxlLCBiYWNhIGRhbiB0dWxpcyBmaWxlIHRla3MsIHppcCBkYW4gdW56aXAsIHBpbmRhaCBkYW4gaGFwdXMga2UgUmVjeWNsZSBCaW4uCi0gS29udHJvbCBQQzogdm9sdW1lIGRhbiB0b21ib2wgbWVkaWEsIGluZm8gc2lzdGVtLCBjbGlw
::B64:agent.js:Ym9hcmQsIGRhZnRhciBkYW4gZm9rdXMgamVuZGVsYS4KLSBBZ2VudCBiZXJoZW50aSBkYW4gbWludGEgYmFudHVhbm11IHNhYXQgYnV0dWggbG9naW4sIGNhcHRjaGEsIGF0YXUgdmVyaWZpa2FzaS4KLSBEYWZ0YXIgZml0dXIgYmFydSB0YW1waWwgb3RvbWF0aXMg
::B64:agent.js:c2V0ZWxhaCB1cGRhdGUuIEtldGlrIC9iYW50dWFuIHVudHVrIGRhZnRhciBsZW5na2FwLmA7Cgpjb25zdCBIRUxQID0gYApGSVRVUiBBR0VOVAogIEJyb3dzZXIgIDogYnVrYSB3ZWJzaXRlLCBpc2kgZm9ybSwga2xpaywgdXBsb2FkIGZpbGUsIGNhcmkgZGkgd2Vi
::B64:agent.js:LCBzY3JvbGwKICBZb3VUdWJlICA6IGNhcmkgKyBwdXRhciBvdG9tYXRpcyAoc2tpcCBpa2xhbiksIGtvbnRyb2wgcGF1c2UvbmV4dC9tYWp1L211bmR1ci9tdXRlL2Z1bGxzY3JlZW4KICBMb2dpbiAgICA6IC9sb2dpbiBsYWx1IGxvZ2luIG1hbnVhbCBzZWthbGks
::B64:agent.js:IHNlc2kgdGVyc2ltcGFuLiBBZ2VudCB0aWRhayBwZXJuYWggbWVuZ2V0aWsgcGFzc3dvcmRtdQogIExheWFyICAgIDogc2NyZWVuc2hvdCwga2xpaywgc2Nyb2xsLCBrZXRpaywgdGVrYW4gdG9tYm9sCiAgSmVuZGVsYSAgOiBkYWZ0YXIsIHBpbmRhaCBmb2t1cywg
::B64:agent.js:dHV0dXAKICBGaWxlICAgICA6IGNhcmkgZmlsZS9mb2xkZXIgZGkgc2VtdWEgZHJpdmUsIGJhY2EvdHVsaXMgdGVrcywgYnVhdCBmb2xkZXIsIHBpbmRhaCwKICAgICAgICAgICAgIGhhcHVzIGtlIFJlY3ljbGUgQmluLCB6aXAvdW56aXAsIHVuZHVoIGRhcmkgaW50
::B64:agent.js:ZXJuZXQsIHVwbG9hZCBrZSB3ZWJzaXRlCiAgUEMgICAgICAgOiB2b2x1bWUgZGFuIHRvbWJvbCBtZWRpYSwgY2xpcGJvYXJkLCBpbmZvIHNpc3RlbSwgdGFuZ2dhbCBkYW4gamFtClBFUklOVEFIIEtIVVNVUwogIC9sb2dpbiBbYWxhbWF0XSAgbG9naW4gbWFudWFs
::B64:agent.js:IGRpIGJyb3dzZXIgICAgICAvYmFydSAgICAgZGFmdGFyIGZpdHVyIHRlcmJhcnUKICAvdXBkYXRlICAgICAgICAgIHBlcmJhcnVpIHNla2FyYW5nICAgICAgICAgICAgL3ZlcnNpICAgIGNlayB2ZXJzaQogIC9yZXNldCAgICAgICAgICAgbHVwYWthbiBwZXJjYWth
::B64:agent.js:cGFuICAgICAgICAgICAvYmFudHVhbiAgdGFtcGlsa2FuIGluaSAgICAgICAgZXhpdCAga2VsdWFyCkNPTlRPSAogIG5vbnRvbiB5b3V0dWJlIGxhZ3Uga2lzcyBtZSAgfCAgY2FyaSB0YXUgY3VhY2EgYmVzb2sgZGkgd2ViICB8ICBuYWlraW4gdm9sdW1lCiAgY2Fy
::B64:agent.js:aSBmaWxlIGxhcG9yYW4gbGFsdSB1cGxvYWQga2UgbWVkaWFmaXJlICB8ICB6aXAgZm9sZGVyIFJlaWEgbGFsdSB0YXJ1aCBkaSBEZXNrdG9wCmA7CgpmdW5jdGlvbiBzaG93V2hhdHNOZXcoZm9yY2UgPSBmYWxzZSkgewogIGNvbnN0IHZlciA9IGxvY2FsVmVyc2lv
::B64:agent.js:bigpOwogIGxldCBzZWVuID0gIiI7CiAgdHJ5IHsKICAgIHNlZW4gPSBmcy5yZWFkRmlsZVN5bmMoIi53aGF0c25ldy1zZWVuIiwgInV0ZjgiKS50cmltKCk7CiAgfSBjYXRjaCB7fQogIGlmICghZm9yY2UgJiYgc2VlbiA9PT0gdmVyKSByZXR1cm47CiAgbGV0IHRl
::B64:agent.js:eHQgPSAiIjsKICB0cnkgewogICAgdGV4dCA9IGZzLnJlYWRGaWxlU3luYygiY2hhbmdlbG9nLnR4dCIsICJ1dGY4IikudHJpbSgpOwogIH0gY2F0Y2gge30KICBpZiAoIXRleHQpIHRleHQgPSBCVUlMVElOX0NIQU5HRUxPRzsKICBjb25zb2xlLmxvZygiXG49PT09
::B64:agent.js:PT09PT09PT09PT09PT0gWUFORyBCQVJVID09PT09PT09PT09PT09PT09PSIpOwogIGNvbnNvbGUubG9nKHRleHQuc3BsaXQoL1xyP1xuLykuc2xpY2UoMCwgMzApLmpvaW4oIlxuIikpOwogIGNvbnNvbGUubG9nKCI9PT09PT09PT09PT09PT09PT09PT09PT09PT09
::B64:agent.js:PT09PT09PT09PT09PT09PT09PSIpOwogIHRyeSB7CiAgICBmcy53cml0ZUZpbGVTeW5jKCIud2hhdHNuZXctc2VlbiIsIHZlcik7CiAgfSBjYXRjaCB7fQp9Cgpjb25zb2xlLmxvZyhgQWdlbnQgc2lhcC4gVmVyc2kgJHtsb2NhbFZlcnNpb24oKX0uIEZvbGRlciB1
::B64:agent.js:cGxvYWQ6ICR7U0FGRV9ESVJ9YCk7CmNvbnNvbGUubG9nKGBJemluIHNlYmVsdW0gYWtzaTogJHtDT05GSVJNID8gIkFLVElGIiA6ICJNQVRJIn0uIFRla2FuIEN0cmwrQyBrYXBhbiBzYWphIHVudHVrIG1lbmdoZW50aWthbi5gKTsKc2hvd1doYXRzTmV3KCk7CmNv
::B64:agent.js:bnNvbGUubG9nKCdLZXRpayBwZXJpbnRhaCBkYWxhbSBiYWhhc2EgYmlhc2EuIEtldGlrIC9iYW50dWFuIHVudHVrIGRhZnRhciBmaXR1ciwgL2xvZ2luIHVudHVrIGxvZ2luLCBleGl0IHVudHVrIGtlbHVhci4nKTsKY2hlY2tVcGRhdGUoKTsKd2hpbGUgKHRydWUp
::B64:agent.js:IHsKICBjb25zdCBjbWQgPSBhd2FpdCBybC5xdWVzdGlvbigiXG5QZXJpbnRhaD4gIik7CiAgY29uc3QgYyA9IGNtZC50cmltKCk7CiAgaWYgKGMgPT09ICJleGl0IikgYnJlYWs7CiAgaWYgKCFjKSBjb250aW51ZTsKICBpZiAoYyA9PT0gIi9iYW50dWFuIikgewog
::B64:agent.js:ICAgY29uc29sZS5sb2coSEVMUCk7CiAgICBjb250aW51ZTsKICB9CiAgaWYgKGMgPT09ICIvYmFydSIpIHsKICAgIHNob3dXaGF0c05ldyh0cnVlKTsKICAgIGNvbnRpbnVlOwogIH0KICBpZiAoYy5zdGFydHNXaXRoKCIvbG9naW4iKSkgewogICAgbGV0IHRhcmdl
::B64:agent.js:dCA9IGMuc3BsaXQoL1xzKy8pWzFdIHx8ICJodHRwczovL2FjY291bnRzLmdvb2dsZS5jb20vU2VydmljZUxvZ2luP3NlcnZpY2U9eW91dHViZSZjb250aW51ZT1odHRwczovL3d3dy55b3V0dWJlLmNvbS8iOwogICAgaWYgKCEvXmh0dHBzPzpcL1wvL2kudGVzdCh0
::B64:agent.js:YXJnZXQpKSB0YXJnZXQgPSAiaHR0cHM6Ly8iICsgdGFyZ2V0OwogICAgdHJ5IHsKICAgICAgYXdhaXQgZW5zdXJlUGFnZSgpOwogICAgICBhd2FpdCBwYWdlLmJyaW5nVG9Gcm9udCgpOwogICAgICBhd2FpdCBwYWdlLmdvdG8odGFyZ2V0LCB7IHdhaXRVbnRpbDog
::B64:agent.js:ImRvbWNvbnRlbnRsb2FkZWQiIH0pOwogICAgfSBjYXRjaCAoZSkgewogICAgICBjb25zb2xlLmxvZygiR2FnYWwgbWVtYnVrYSBoYWxhbWFuIGxvZ2luOiIsIGUubWVzc2FnZSk7CiAgICB9CiAgICBjb25zb2xlLmxvZygiU2lsYWthbiBsb2dpbiBkaSBqZW5kZWxh
::B64:agent.js:IGJyb3dzZXIgKGthbXUgeWFuZyBtZW5nZXRpaywgYWdlbnQgdGlkYWsgbWVsaWhhdCBwYXNzd29yZCkuIik7CiAgICBhd2FpdCBybC5xdWVzdGlvbigiU2V0ZWxhaCBzZWxlc2FpLCB0ZWthbiBFbnRlciBkaSBzaW5pLi4uICIpOwogICAgY29uc29sZS5sb2coIkxv
::B64:agent.js:Z2luIHRlcnNpbXBhbiBkaSBwcm9maWwgYnJvd3Nlci4gQmVyaWt1dG55YSB0aWRhayBwZXJsdSBsb2dpbiBsYWdpLiIpOwogICAgY29udGludWU7CiAgfQogIGlmIChjID09PSAiL3ZlcnNpIikgewogICAgY29uc29sZS5sb2coYFZlcnNpIGFnZW50OiAke2xvY2Fs
::B64:agent.js:VmVyc2lvbigpfWApOwogICAgYXdhaXQgY2hlY2tVcGRhdGUoKTsKICAgIGlmICghcGVuZGluZ1ZlcnNpb24pIGNvbnNvbGUubG9nKCJTdWRhaCB2ZXJzaSB0ZXJiYXJ1IChhdGF1IHVwZGF0ZSBvbmxpbmUgdGlkYWsgYWt0aWYpLiIpOwogICAgY29udGludWU7CiAg
::B64:agent.js:fQogIGlmIChjID09PSAiL3VwZGF0ZSIpIHsKICAgIGNvbnNvbGUubG9nKCJNZW1wZXJiYXJ1aS4uLiBhZ2VudCBha2FuIG1lbnV0dXAgZGFuIG1lbnlhbGEgbGFnaSBvdG9tYXRpcyBsZXdhdCBzdGFydC1hZ2VudC5iYXQuIik7CiAgICBhd2FpdCBzaHV0ZG93bkJy
::B64:agent.js:b3dzZXIoKTsKICAgIHJsLmNsb3NlKCk7CiAgICBwcm9jZXNzLmV4aXQoNDIpOyAvLyBrb2RlIDQyID0gcGVybWludGFhbiByZXN0YXJ0IHVudHVrIHVwZGF0ZTsgZGl0YW5na2FwIG9sZWggc3RhcnQtYWdlbnQuYmF0CiAgfQogIGlmIChjID09PSAiL3Jlc2V0Iikg
::B64:agent.js:ewogICAgaGlzdG9yeS5sZW5ndGggPSAwOwogICAgY29uc29sZS5sb2coIlBlcmNha2FwYW4gZGlsdXBha2FuLiIpOwogICAgY29udGludWU7CiAgfQogIHRyeSB7CiAgICBhd2FpdCBydW5UYXNrKGMpOwogIH0gY2F0Y2ggKGUpIHsKICAgIGNvbnNvbGUuZXJyb3Io
::B64:agent.js:IkdhZ2FsOiIsIGUubWVzc2FnZSk7CiAgfQp9CmF3YWl0IHNodXRkb3duQnJvd3NlcigpOwpybC5jbG9zZSgpOwo=
::B64:package.json:ewogICJuYW1lIjogImJvdC1hZ2VudCIsCiAgInZlcnNpb24iOiAiMS4wLjAiLAogICJ0eXBlIjogIm1vZHVsZSIsCiAgInNjcmlwdHMiOiB7CiAgICAic3RhcnQiOiAibm9kZSBhZ2VudC5qcyIKICB9LAogICJkZXBlbmRlbmNpZXMiOiB7CiAgICAicGxheXdyaWdo
::B64:package.json:dCI6ICJeMS40OC4wIgogIH0KfQo=
