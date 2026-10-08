@echo off
setlocal EnableExtensions
chcp 65001 >nul
title Agent Automation
set "SELF=%~f0"
set "EMBED_VER=8"

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
::B64:agent.js:Ci8vID09PT09IEhlbHBlciB0YWIgYnJvd3NlciA9PT09PQpjb25zdCBmaXhVcmwgPSAodSkgPT4gKC9eW2Etel1bYS16MC05Ky4tXSo6XC9cLy9pLnRlc3QoU3RyaW5nKHUpKSA/IFN0cmluZyh1KSA6ICJodHRwczovLyIgKyBTdHJpbmcodSkpOwpjb25zdCBpc1Ry
::B64:agent.js:dWUgPSAodikgPT4gdiA9PT0gdHJ1ZSB8fCB2ID09PSAidHJ1ZSI7CmNvbnN0IGxpdmVQYWdlcyA9ICgpID0+IGNvbnRleHQucGFnZXMoKS5maWx0ZXIoKHgpID0+ICF4LmlzQ2xvc2VkKCkpOwoKYXN5bmMgZnVuY3Rpb24gdGFic1N1bW1hcnkoKSB7CiAgY29uc3Qg
::B64:agent.js:YWxsID0gbGl2ZVBhZ2VzKCk7CiAgY29uc3QgbGluZXMgPSBbXTsKICBmb3IgKGxldCBpID0gMDsgaSA8IGFsbC5sZW5ndGg7IGkrKykgewogICAgbGV0IHRpdGxlID0gIiI7CiAgICB0cnkgewogICAgICB0aXRsZSA9IGF3YWl0IGFsbFtpXS50aXRsZSgpOwogICAg
::B64:agent.js:fSBjYXRjaCB7fQogICAgbGluZXMucHVzaChgJHtpICsgMX0ke2FsbFtpXSA9PT0gcGFnZSA/ICIqIiA6ICIgIn0gJHt0aXRsZS5zbGljZSgwLCA2MCl9IHwgJHthbGxbaV0udXJsKCkuc2xpY2UoMCwgMTAwKX1gKTsKICB9CiAgcmV0dXJuIChsaW5lcy5qb2luKCJc
::B64:agent.js:biIpIHx8ICIodGlkYWsgYWRhIHRhYikiKSArICJcbigqID0gdGFiIGFrdGlmIHlhbmcgZGlwYWthaSBhZ2VudCkiOwp9CgpmdW5jdGlvbiBwaWNrVGFiKGFsbCwgaW5kZXgpIHsKICBjb25zdCBuID0gTnVtYmVyKGluZGV4KTsKICBpZiAoIU51bWJlci5pc0Zpbml0
::B64:agent.js:ZShuKSB8fCBuID09PSAwKSByZXR1cm4gdW5kZWZpbmVkOwogIHJldHVybiBuIDwgMCA/IGFsbC5hdChuKSA6IGFsbFtuIC0gMV07Cn0KCi8vID09PT09IEhlbHBlciBZb3VUdWJlID09PT09CmFzeW5jIGZ1bmN0aW9uIHNraXBBZHMoKSB7CiAgZm9yIChsZXQgaSA9
::B64:agent.js:IDA7IGkgPCAxMDsgaSsrKSB7CiAgICBjb25zdCBidG4gPSBhd2FpdCBwYWdlLiQoIi55dHAtc2tpcC1hZC1idXR0b24sIC55dHAtYWQtc2tpcC1idXR0b24sIC55dHAtYWQtc2tpcC1idXR0b24tbW9kZXJuIik7CiAgICBpZiAoYnRuKSB7CiAgICAgIGF3YWl0IGJ0
::B64:agent.js:bi5jbGljaygpLmNhdGNoKCgpID0+IHt9KTsKICAgICAgcmV0dXJuOwogICAgfQogICAgaWYgKCEoYXdhaXQgcGFnZS4kKCIuYWQtc2hvd2luZyIpKSkgcmV0dXJuOwogICAgYXdhaXQgc2xlZXAoMTAwMCk7CiAgfQp9Cgphc3luYyBmdW5jdGlvbiByZWFkUGxheWVy
::B64:agent.js:U3RhdGUoKSB7CiAgcmV0dXJuIHBhZ2UuZXZhbHVhdGUoKCkgPT4gewogICAgY29uc3QgdiA9IGRvY3VtZW50LnF1ZXJ5U2VsZWN0b3IoInZpZGVvIik7CiAgICBjb25zdCBlcnIgPSAhIWRvY3VtZW50LnF1ZXJ5U2VsZWN0b3IoIi55dHAtZXJyb3IiKTsKICAgIGlm
::B64:agent.js:ICh2ICYmIHYucGF1c2VkICYmICFlcnIpIHYucGxheSgpLmNhdGNoKCgpID0+IHt9KTsKICAgIHJldHVybiB7IGVyciwgcGxheWluZzogISF2ICYmICF2LnBhdXNlZCAmJiB2LnJlYWR5U3RhdGUgPiAyIH07CiAgfSk7Cn0KCmFzeW5jIGZ1bmN0aW9uIGVuc3VyZVBs
::B64:agent.js:YXlpbmcoKSB7CiAgZm9yIChsZXQgYXR0ZW1wdCA9IDA7IGF0dGVtcHQgPCAyOyBhdHRlbXB0KyspIHsKICAgIGF3YWl0IHNsZWVwKDMwMDApOwogICAgYXdhaXQgc2tpcEFkcygpOwogICAgYXdhaXQgcmVhZFBsYXllclN0YXRlKCk7IC8vIG1lbWljdSBwbGF5KCkK
::B64:agent.js:ICAgIGF3YWl0IHNsZWVwKDEyMDApOwogICAgY29uc3Qgc3QgPSBhd2FpdCByZWFkUGxheWVyU3RhdGUoKTsKICAgIGlmIChzdC5wbGF5aW5nKSByZXR1cm4gdHJ1ZTsKICAgIGlmIChzdC5lcnIpIGF3YWl0IHBhZ2UucmVsb2FkKHsgd2FpdFVudGlsOiAiZG9tY29u
::B64:agent.js:dGVudGxvYWRlZCIgfSk7CiAgfQogIHJldHVybiBmYWxzZTsKfQoKY29uc3QgaW1wbCA9IHsKICAvLyAtLS0gRGVza3RvcDogZmlsZSAmIGZvbGRlciAtLS0KICBmaW5kX2ZvbGRlcjogYXN5bmMgKHsgbmFtZSB9KSA9PiBzZWFyY2hFdmVyeXdoZXJlKG5hbWUsIGZh
::B64:agent.js:bHNlKSwKCiAgZmluZF9maWxlOiBhc3luYyAoeyBuYW1lIH0pID0+IHNlYXJjaEV2ZXJ5d2hlcmUobmFtZSwgdHJ1ZSksCgogIGxpc3RfZGlyOiBhc3luYyAoeyBwYXRoOiBwIH0pID0+IHsKICAgIGNvbnN0IGl0ZW1zID0gZnMucmVhZGRpclN5bmMocCwgeyB3aXRo
::B64:agent.js:RmlsZVR5cGVzOiB0cnVlIH0pLnNsaWNlKDAsIDEwMCk7CiAgICByZXR1cm4gaXRlbXMubWFwKChlKSA9PiAoZS5pc0RpcmVjdG9yeSgpID8gIltESVJdICIgOiAiW0ZJTEVdICIpICsgZS5uYW1lKS5qb2luKCJcbiIpIHx8ICIoa29zb25nKSI7CiAgfSwKCiAgb3Bl
::B64:agent.js:bl9wYXRoOiBhc3luYyAoeyB0YXJnZXQgfSkgPT4gewogICAgaWYgKCEoYXdhaXQgYXNrKGBCdWthOiAke3RhcmdldH1gKSkpIHJldHVybiAiRGliYXRhbGthbiB1c2VyIjsKICAgIGF3YWl0IHBzKCJTdGFydC1Qcm9jZXNzIC1GaWxlUGF0aCAkZW52OlRBUkdFVCIs
::B64:agent.js:IHsgVEFSR0VUOiBTdHJpbmcodGFyZ2V0KSB9KTsKICAgIGF3YWl0IHNsZWVwKDE1MDApOwogICAgcmV0dXJuICJvaywgZGlidWthIjsKICB9LAoKICAvLyAtLS0gRGVza3RvcDogbGF5YXIsIG1vdXNlLCBrZXlib2FyZCAtLS0KICBzY3JlZW5zaG90OiBhc3luYyAo
::B64:agent.js:KSA9PiB7CiAgICBjb25zdCBvdXQgPSBwYXRoLnJlc29sdmUoInNjcmVlbi5wbmciKTsKICAgIGNvbnN0IHIgPSBhd2FpdCBwcygKICAgICAgUFNfSEVBRCArCiAgICAgICAgYAokYiA9IFtTeXN0ZW0uV2luZG93cy5Gb3Jtcy5TY3JlZW5dOjpQcmltYXJ5U2NyZWVu
::B64:agent.js:LkJvdW5kcwokYm1wID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5CaXRtYXAgJGIuV2lkdGgsICRiLkhlaWdodAokZyA9IFtTeXN0ZW0uRHJhd2luZy5HcmFwaGljc106OkZyb21JbWFnZSgkYm1wKQokZy5Db3B5RnJvbVNjcmVlbigkYi5YLCAkYi5ZLCAwLCAw
::B64:agent.js:LCAkYm1wLlNpemUpCiRudyA9IFtNYXRoXTo6TWluKDEyODAsICRiLldpZHRoKQokbmggPSBbaW50XSgkYi5IZWlnaHQgKiAkbncgLyAkYi5XaWR0aCkKJHNtYWxsID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5CaXRtYXAgJGJtcCwgJG53LCAkbmgKJHNtYWxs
::B64:agent.js:LlNhdmUoJGVudjpPVVQsIFtTeXN0ZW0uRHJhd2luZy5JbWFnaW5nLkltYWdlRm9ybWF0XTo6UG5nKQpXcml0ZS1PdXRwdXQgIiQoJGIuV2lkdGgpLCRudywkbmgiCmAsCiAgICAgIHsgT1VUOiBvdXQgfQogICAgKTsKICAgIGNvbnN0IFt3LCBudywgbmhdID0gci5z
::B64:agent.js:cGxpdCgiXG4iKS5wb3AoKS5zcGxpdCgiLCIpLm1hcChOdW1iZXIpOwogICAgc2NhbGUgPSB3IC8gbnc7CiAgICBwZW5kaW5nSW1hZ2VzLnB1c2goZnMucmVhZEZpbGVTeW5jKG91dCkudG9TdHJpbmcoImJhc2U2NCIpKTsKICAgIHJldHVybiBgU2NyZWVuc2hvdCBk
::B64:agent.js:aWFtYmlsICgke253fXgke25ofSkuIEdhbWJhcm55YSBhZGEgZGkgcGVzYW4gYmVyaWt1dG55YS4gUGFrYWkga29vcmRpbmF0IGRhcmkgZ2FtYmFyIGl0dS5gOwogIH0sCgogIGNsaWNrX3NjcmVlbjogYXN5bmMgKHsgeCwgeSwgYnV0dG9uID0gImxlZnQiLCBkb3Vi
::B64:agent.js:bGUgPSBmYWxzZSB9KSA9PiB7CiAgICBjb25zdCByeCA9IE1hdGgucm91bmQoTnVtYmVyKHgpICogc2NhbGUpOwogICAgY29uc3QgcnkgPSBNYXRoLnJvdW5kKE51bWJlcih5KSAqIHNjYWxlKTsKICAgIGNvbnN0IGRibCA9IGRvdWJsZSA9PT0gdHJ1ZSB8fCBkb3Vi
::B64:agent.js:bGUgPT09ICJ0cnVlIjsKICAgIGlmICghKGF3YWl0IGFzayhgJHtkYmwgPyAiRG91YmxlLWtsaWsiIDogIktsaWsifSAke2J1dHRvbn0gZGkgKCR7eH0sJHt5fSlgKSkpIHJldHVybiAiRGliYXRhbGthbiB1c2VyIjsKICAgIGF3YWl0IHBzKAogICAgICBQU19IRUFE
::B64:agent.js:ICsKICAgICAgICBgCltXXTo6U2V0Q3Vyc29yUG9zKFtpbnRdJGVudjpYLCBbaW50XSRlbnY6WSkgfCBPdXQtTnVsbApTdGFydC1TbGVlcCAtTWlsbGlzZWNvbmRzIDE1MAokZG93biA9IDI7ICR1cCA9IDQKaWYgKCRlbnY6QlROIC1lcSAicmlnaHQiKSB7ICRkb3du
::B64:agent.js:ID0gODsgJHVwID0gMTYgfQpmb3IgKCRpID0gMDsgJGkgLWx0IFtpbnRdJGVudjpDT1VOVDsgJGkrKykgewogIFtXXTo6bW91c2VfZXZlbnQoJGRvd24sIDAsIDAsIDAsIFtVSW50UHRyXTo6WmVybykKICBbV106Om1vdXNlX2V2ZW50KCR1cCwgMCwgMCwgMCwgW1VJ
::B64:agent.js:bnRQdHJdOjpaZXJvKQogIFN0YXJ0LVNsZWVwIC1NaWxsaXNlY29uZHMgODAKfQpgLAogICAgICB7IFg6IFN0cmluZyhyeCksIFk6IFN0cmluZyhyeSksIEJUTjogU3RyaW5nKGJ1dHRvbiksIENPVU5UOiBkYmwgPyAiMiIgOiAiMSIgfQogICAgKTsKICAgIGF3YWl0
::B64:agent.js:IHNsZWVwKDgwMCk7CiAgICByZXR1cm4gIm9rLCBkaWtsaWsiOwogIH0sCgogIHNjcm9sbF9zY3JlZW46IGFzeW5jICh7IGFtb3VudCB9KSA9PiB7CiAgICBjb25zdCBkZWx0YSA9IC0xMjAgKiBNYXRoLnJvdW5kKE51bWJlcihhbW91bnQpKTsgLy8gcG9zaXRpZiA9
::B64:agent.js:IHR1cnVuCiAgICBpZiAoIShhd2FpdCBhc2soYFNjcm9sbCAke2Ftb3VudCA+IDAgPyAidHVydW4iIDogIm5haWsifSAke01hdGguYWJzKGFtb3VudCl9eGApKSkgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgYXdhaXQgcHMoUFNfSEVBRCArIGBbV106Om1v
::B64:agent.js:dXNlX2V2ZW50KDB4MDgwMCwgMCwgMCwgW2ludF0kZW52OkQsIFtVSW50UHRyXTo6WmVybylgLCB7IEQ6IFN0cmluZyhkZWx0YSkgfSk7CiAgICBhd2FpdCBzbGVlcCg1MDApOwogICAgcmV0dXJuICJvayI7CiAgfSwKCiAgdHlwZV9kZXNrdG9wOiBhc3luYyAoeyB0
::B64:agent.js:ZXh0IH0pID0+IHsKICAgIGlmICghKGF3YWl0IGFzayhgS2V0aWs6ICIke1N0cmluZyh0ZXh0KS5zbGljZSgwLCA2MCl9ImApKSkgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgYXdhaXQgcHMoCiAgICAgIFBTX0hFQUQgKwogICAgICAgIGAKU2V0LUNsaXBi
::B64:agent.js:b2FyZCAtVmFsdWUgJGVudjpUWFQKU3RhcnQtU2xlZXAgLU1pbGxpc2Vjb25kcyAxNTAKW1N5c3RlbS5XaW5kb3dzLkZvcm1zLlNlbmRLZXlzXTo6U2VuZFdhaXQoIl52IikKYCwKICAgICAgeyBUWFQ6IFN0cmluZyh0ZXh0KSB9CiAgICApOwogICAgYXdhaXQgc2xl
::B64:agent.js:ZXAoNTAwKTsKICAgIHJldHVybiAib2ssIGRpa2V0aWsiOwogIH0sCgogIHByZXNzX2tleXM6IGFzeW5jICh7IGtleXMgfSkgPT4gewogICAgaWYgKCEoYXdhaXQgYXNrKGBUZWthbiB0b21ib2w6ICR7a2V5c31gKSkpIHJldHVybiAiRGliYXRhbGthbiB1c2VyIjsK
::B64:agent.js:ICAgIGF3YWl0IHBzKFBTX0hFQUQgKyBgW1N5c3RlbS5XaW5kb3dzLkZvcm1zLlNlbmRLZXlzXTo6U2VuZFdhaXQoJGVudjpLRVlTKWAsIHsgS0VZUzogU3RyaW5nKGtleXMpIH0pOwogICAgYXdhaXQgc2xlZXAoNTAwKTsKICAgIHJldHVybiAib2siOwogIH0sCgog
::B64:agent.js:IHdhaXQ6IGFzeW5jICh7IHNlY29uZHMgfSkgPT4gewogICAgYXdhaXQgc2xlZXAoTWF0aC5taW4oTnVtYmVyKHNlY29uZHMpIHx8IDEsIDE1KSAqIDEwMDApOwogICAgcmV0dXJuICJvayI7CiAgfSwKCiAgLy8gLS0tIEJyb3dzZXIgKFBsYXl3cmlnaHQpIC0tLQog
::B64:agent.js:IGxpc3RfZmlsZXM6IGFzeW5jICgpID0+IGZzLnJlYWRkaXJTeW5jKFNBRkVfRElSKS5qb2luKCJcbiIpIHx8ICIoZm9sZGVyIHVwbG9hZCBrb3NvbmcpIiwKCiAgb3Blbl91cmw6IGFzeW5jICh7IHVybCwgbmV3X3RhYiA9IGZhbHNlIH0pID0+IHsKICAgIGlmIChp
::B64:agent.js:c1RydWUobmV3X3RhYikpIHBhZ2UgPSBhd2FpdCBjb250ZXh0Lm5ld1BhZ2UoKTsKICAgIGF3YWl0IHBhZ2UuYnJpbmdUb0Zyb250KCk7CiAgICBhd2FpdCBwYWdlLmdvdG8oZml4VXJsKHVybCksIHsgd2FpdFVudGlsOiAiZG9tY29udGVudGxvYWRlZCIgfSk7CiAg
::B64:agent.js:ICByZXR1cm4gIlRlcmJ1a2E6ICIgKyAoYXdhaXQgcGFnZS50aXRsZSgpKSArIChpc1RydWUobmV3X3RhYikgPyAiIChkaSB0YWIgYmFydSkiIDogIiIpOwogIH0sCgogIC8vIC0tLSBUYWIgLS0tCiAgbGlzdF90YWJzOiBhc3luYyAoKSA9PiB0YWJzU3VtbWFyeSgp
::B64:agent.js:LAoKICBuZXdfdGFiOiBhc3luYyAoeyB1cmwgfSkgPT4gewogICAgcGFnZSA9IGF3YWl0IGNvbnRleHQubmV3UGFnZSgpOwogICAgYXdhaXQgcGFnZS5icmluZ1RvRnJvbnQoKTsKICAgIGlmICh1cmwpIGF3YWl0IHBhZ2UuZ290byhmaXhVcmwodXJsKSwgeyB3YWl0
::B64:agent.js:VW50aWw6ICJkb21jb250ZW50bG9hZGVkIiB9KTsKICAgIHJldHVybiAiVGFiIGJhcnUgZGlidWthIGRhbiBqYWRpIHRhYiBha3RpZi5cbiIgKyAoYXdhaXQgdGFic1N1bW1hcnkoKSk7CiAgfSwKCiAgb3Blbl91cmxzOiBhc3luYyAoeyB1cmxzIH0pID0+IHsKICAg
::B64:agent.js:IGNvbnN0IGxpc3QgPSAoQXJyYXkuaXNBcnJheSh1cmxzKSA/IHVybHMgOiBTdHJpbmcodXJscykuc3BsaXQoL1tcbiw7fF0rLykpCiAgICAgIC5tYXAoKHgpID0+IFN0cmluZyh4KS50cmltKCkpCiAgICAgIC5maWx0ZXIoQm9vbGVhbikKICAgICAgLnNsaWNlKDAs
::B64:agent.js:IDEwKTsKICAgIGlmICghbGlzdC5sZW5ndGgpIHRocm93IG5ldyBFcnJvcigiVGlkYWsgYWRhIFVSTCIpOwogICAgY29uc3QgZ2FnYWwgPSBbXTsKICAgIGZvciAoY29uc3QgdSBvZiBsaXN0KSB7CiAgICAgIHBhZ2UgPSBhd2FpdCBjb250ZXh0Lm5ld1BhZ2UoKTsK
::B64:agent.js:ICAgICAgdHJ5IHsKICAgICAgICBhd2FpdCBwYWdlLmdvdG8oZml4VXJsKHUpLCB7IHdhaXRVbnRpbDogImRvbWNvbnRlbnRsb2FkZWQiLCB0aW1lb3V0OiAzMDAwMCB9KTsKICAgICAgfSBjYXRjaCAoZSkgewogICAgICAgIGdhZ2FsLnB1c2godSk7CiAgICAgIH0K
::B64:agent.js:ICAgIH0KICAgIHJldHVybiBgJHtsaXN0Lmxlbmd0aCAtIGdhZ2FsLmxlbmd0aH0gdGFiIGRpYnVrYSR7Z2FnYWwubGVuZ3RoID8gYCwgZ2FnYWw6ICR7Z2FnYWwuam9pbigiLCAiKX1gIDogIiJ9LlxuYCArIChhd2FpdCB0YWJzU3VtbWFyeSgpKTsKICB9LAoKICBz
::B64:agent.js:d2l0Y2hfdGFiOiBhc3luYyAoeyBpbmRleCwgbWF0Y2ggfSkgPT4gewogICAgY29uc3QgYWxsID0gbGl2ZVBhZ2VzKCk7CiAgICBsZXQgdGFyZ2V0OwogICAgaWYgKG1hdGNoKSB7CiAgICAgIGNvbnN0IHEgPSBTdHJpbmcobWF0Y2gpLnRvTG93ZXJDYXNlKCk7CiAg
::B64:agent.js:ICAgIGZvciAoY29uc3QgeCBvZiBhbGwpIHsKICAgICAgICBjb25zdCB0ID0gKChhd2FpdCB4LnRpdGxlKCkuY2F0Y2goKCkgPT4gIiIpKSArICIgIiArIHgudXJsKCkpLnRvTG93ZXJDYXNlKCk7CiAgICAgICAgaWYgKHQuaW5jbHVkZXMocSkpIHsKICAgICAgICAg
::B64:agent.js:IHRhcmdldCA9IHg7CiAgICAgICAgICBicmVhazsKICAgICAgICB9CiAgICAgIH0KICAgIH0gZWxzZSB7CiAgICAgIHRhcmdldCA9IHBpY2tUYWIoYWxsLCBpbmRleCk7CiAgICB9CiAgICBpZiAoIXRhcmdldCkgdGhyb3cgbmV3IEVycm9yKCJUYWIgdGlkYWsgZGl0
::B64:agent.js:ZW11a2FuLlxuIiArIChhd2FpdCB0YWJzU3VtbWFyeSgpKSk7CiAgICBwYWdlID0gdGFyZ2V0OwogICAgYXdhaXQgcGFnZS5icmluZ1RvRnJvbnQoKTsKICAgIHJldHVybiAiVGFiIGFrdGlmIHNla2FyYW5nOiAiICsgKGF3YWl0IHBhZ2UudGl0bGUoKS5jYXRjaCgo
::B64:agent.js:KSA9PiAiIikpICsgIiB8ICIgKyBwYWdlLnVybCgpOwogIH0sCgogIGNsb3NlX3RhYjogYXN5bmMgKHsgaW5kZXggfSkgPT4gewogICAgY29uc3QgYWxsID0gbGl2ZVBhZ2VzKCk7CiAgICBjb25zdCB0YXJnZXQgPSBpbmRleCA/IHBpY2tUYWIoYWxsLCBpbmRleCkg
::B64:agent.js:OiBwYWdlOwogICAgaWYgKCF0YXJnZXQpIHRocm93IG5ldyBFcnJvcigiVGFiIHRpZGFrIGRpdGVtdWthbi5cbiIgKyAoYXdhaXQgdGFic1N1bW1hcnkoKSkpOwogICAgaWYgKGFsbC5sZW5ndGggPT09IDEpIHRocm93IG5ldyBFcnJvcigiSW5pIHRhYiB0ZXJha2hp
::B64:agent.js:ciwgdGlkYWsgZGl0dXR1cCBhZ2FyIGJyb3dzZXIgdGV0YXAgdGVyYnVrYSIpOwogICAgY29uc3QganVkdWwgPSBhd2FpdCB0YXJnZXQudGl0bGUoKS5jYXRjaCgoKSA9PiAiIik7CiAgICBpZiAoIShhd2FpdCBhc2soYFR1dHVwIHRhYjogJHtqdWR1bH1gKSkpIHJl
::B64:agent.js:dHVybiAiRGliYXRhbGthbiB1c2VyIjsKICAgIGNvbnN0IHdhc0FjdGl2ZSA9IHRhcmdldCA9PT0gcGFnZTsKICAgIGF3YWl0IHRhcmdldC5jbG9zZSgpOwogICAgaWYgKHdhc0FjdGl2ZSkgewogICAgICBwYWdlID0gbGl2ZVBhZ2VzKCkuYXQoLTEpOwogICAgICBh
::B64:agent.js:d2FpdCBwYWdlLmJyaW5nVG9Gcm9udCgpOwogICAgfQogICAgcmV0dXJuICJvay5cbiIgKyAoYXdhaXQgdGFic1N1bW1hcnkoKSk7CiAgfSwKCiAgaW5zcGVjdF9wYWdlOiBhc3luYyAoKSA9PiB7CiAgICBjb25zdCBpdGVtcyA9IGF3YWl0IHBhZ2UuZXZhbHVhdGUo
::B64:agent.js:KCkgPT4KICAgICAgWy4uLmRvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoImlucHV0LCBidXR0b24sIGEsIHRleHRhcmVhLCBzZWxlY3QiKV0KICAgICAgICAuc2xpY2UoMCwgNjApCiAgICAgICAgLm1hcCgoZSkgPT4gKHsKICAgICAgICAgIHRhZzogZS50YWdOYW1l
::B64:agent.js:LnRvTG93ZXJDYXNlKCksCiAgICAgICAgICBpZDogZS5pZCB8fCB1bmRlZmluZWQsCiAgICAgICAgICBuYW1lOiBlLmdldEF0dHJpYnV0ZSgibmFtZSIpIHx8IHVuZGVmaW5lZCwKICAgICAgICAgIHR5cGU6IGUuZ2V0QXR0cmlidXRlKCJ0eXBlIikgfHwgdW5kZWZp
::B64:agent.js:bmVkLAogICAgICAgICAgdGV4dDogKGUuaW5uZXJUZXh0IHx8IGUudmFsdWUgfHwgZS5wbGFjZWhvbGRlciB8fCAiIikudHJpbSgpLnNsaWNlKDAsIDQwKSB8fCB1bmRlZmluZWQsCiAgICAgICAgfSkpCiAgICApOwogICAgcmV0dXJuIEpTT04uc3RyaW5naWZ5KGl0
::B64:agent.js:ZW1zKTsKICB9LAoKICB5b3V0dWJlX3BsYXk6IGFzeW5jICh7IHF1ZXJ5LCBwaWNrID0gMSwgbmV3X3RhYiA9IGZhbHNlIH0pID0+IHsKICAgIGlmIChpc1RydWUobmV3X3RhYikpIHBhZ2UgPSBhd2FpdCBjb250ZXh0Lm5ld1BhZ2UoKTsKICAgIGF3YWl0IHBhZ2Uu
::B64:agent.js:YnJpbmdUb0Zyb250KCk7CiAgICBhd2FpdCBwYWdlLmdvdG8oImh0dHBzOi8vd3d3LnlvdXR1YmUuY29tL3Jlc3VsdHM/c2VhcmNoX3F1ZXJ5PSIgKyBlbmNvZGVVUklDb21wb25lbnQoU3RyaW5nKHF1ZXJ5KSksIHsKICAgICAgd2FpdFVudGlsOiAiZG9tY29udGVu
::B64:agent.js:dGxvYWRlZCIsCiAgICB9KTsKICAgIGF3YWl0IHBhZ2Uud2FpdEZvclNlbGVjdG9yKCJ5dGQtdmlkZW8tcmVuZGVyZXIgYSN2aWRlby10aXRsZSIsIHsgdGltZW91dDogMjAwMDAgfSk7CiAgICBjb25zdCBsaXN0ID0gYXdhaXQgcGFnZS4kJGV2YWwoInl0ZC12aWRl
::B64:agent.js:by1yZW5kZXJlciBhI3ZpZGVvLXRpdGxlIiwgKGVscykgPT4KICAgICAgZWxzLnNsaWNlKDAsIDUpLm1hcCgoZSkgPT4gKHsgdGl0bGU6IGUudGV4dENvbnRlbnQudHJpbSgpLCBocmVmOiBlLmhyZWYgfSkpCiAgICApOwogICAgaWYgKCFsaXN0Lmxlbmd0aCkgcmV0
::B64:agent.js:dXJuICJUaWRhayBhZGEgaGFzaWwiOwogICAgY29uc3Qgc3RhcnQgPSBNYXRoLm1pbihNYXRoLm1heChOdW1iZXIocGljaykgfHwgMSwgMSksIGxpc3QubGVuZ3RoKSAtIDE7CiAgICBjb25zdCBvcmRlciA9IFtzdGFydCwgLi4ubGlzdC5tYXAoKF8sIGkpID0+IGkp
::B64:agent.js:LmZpbHRlcigoaSkgPT4gaSAhPT0gc3RhcnQpXS5zbGljZSgwLCAzKTsKICAgIGNvbnN0IG90aGVycyA9IGxpc3QubWFwKCh2LCBpKSA9PiBgJHtpICsgMX0uICR7di50aXRsZX1gKS5qb2luKCJcbiIpOwogICAgZm9yIChjb25zdCBpZHggb2Ygb3JkZXIpIHsKICAg
::B64:agent.js:ICAgYXdhaXQgcGFnZS5nb3RvKGxpc3RbaWR4XS5ocmVmLCB7IHdhaXRVbnRpbDogImRvbWNvbnRlbnRsb2FkZWQiIH0pOwogICAgICBpZiAoYXdhaXQgZW5zdXJlUGxheWluZygpKSB7CiAgICAgICAgcmV0dXJuIGBNZW11dGFyICMke2lkeCArIDF9OiAke2xpc3Rb
::B64:agent.js:aWR4XS50aXRsZX1cbkhhc2lsIHBlbmNhcmlhbjpcbiR7b3RoZXJzfWA7CiAgICAgIH0KICAgIH0KICAgIHJldHVybiAiVmlkZW8gZ2FnYWwgZGlwdXRhciAoWW91VHViZSBtZW5hbXBpbGthbiBlcnJvcikuIENvYmEgL2xvZ2luIGF0YXUganVkdWwgbGFpbi5cbkhh
::B64:agent.js:c2lsIHBlbmNhcmlhbjpcbiIgKyBvdGhlcnM7CiAgfSwKCiAgeW91dHViZV9jb250cm9sOiBhc3luYyAoeyBhY3Rpb24sIHNlY29uZHMgPSAxMCB9KSA9PiB7CiAgICBhd2FpdCBwYWdlLmJyaW5nVG9Gcm9udCgpOwogICAgcmV0dXJuIHBhZ2UuZXZhbHVhdGUoCiAg
::B64:agent.js:ICAgICh7IGEsIHMgfSkgPT4gewogICAgICAgIGNvbnN0IHYgPSBkb2N1bWVudC5xdWVyeVNlbGVjdG9yKCJ2aWRlbyIpOwogICAgICAgIGlmICghdikgcmV0dXJuICJUaWRhayBhZGEgdmlkZW8gZGkgaGFsYW1hbiBpbmkiOwogICAgICAgIGlmIChhID09PSAicGF1
::B64:agent.js:c2UiKSB2LnBhdXNlKCk7CiAgICAgICAgZWxzZSBpZiAoYSA9PT0gInBsYXkiKSB2LnBsYXkoKTsKICAgICAgICBlbHNlIGlmIChhID09PSAidG9nZ2xlIikgKHYucGF1c2VkID8gdi5wbGF5KCkgOiB2LnBhdXNlKCkpOwogICAgICAgIGVsc2UgaWYgKGEgPT09ICJt
::B64:agent.js:dXRlIikgdi5tdXRlZCA9IHRydWU7CiAgICAgICAgZWxzZSBpZiAoYSA9PT0gInVubXV0ZSIpIHYubXV0ZWQgPSBmYWxzZTsKICAgICAgICBlbHNlIGlmIChhID09PSAiZm9yd2FyZCIpIHYuY3VycmVudFRpbWUgKz0gczsKICAgICAgICBlbHNlIGlmIChhID09PSAi
::B64:agent.js:YmFja3dhcmQiKSB2LmN1cnJlbnRUaW1lIC09IHM7CiAgICAgICAgZWxzZSBpZiAoYSA9PT0gIm5leHQiKSB7CiAgICAgICAgICBjb25zdCBiID0gZG9jdW1lbnQucXVlcnlTZWxlY3RvcigiLnl0cC1uZXh0LWJ1dHRvbiIpOwogICAgICAgICAgaWYgKCFiKSByZXR1
::B64:agent.js:cm4gIlRvbWJvbCBuZXh0IHRpZGFrIGFkYSI7CiAgICAgICAgICBiLmNsaWNrKCk7CiAgICAgICAgfSBlbHNlIGlmIChhID09PSAicHJldmlvdXMiKSB7CiAgICAgICAgICBjb25zdCBiID0gZG9jdW1lbnQucXVlcnlTZWxlY3RvcigiLnl0cC1wcmV2LWJ1dHRvbiIp
::B64:agent.js:OwogICAgICAgICAgaWYgKGIgJiYgZ2V0Q29tcHV0ZWRTdHlsZShiKS5kaXNwbGF5ICE9PSAibm9uZSIpIGIuY2xpY2soKTsKICAgICAgICAgIGVsc2UgaGlzdG9yeS5iYWNrKCk7CiAgICAgICAgfSBlbHNlIGlmIChhID09PSAiZnVsbHNjcmVlbiIpIHsKICAgICAg
::B64:agent.js:ICAgIGNvbnN0IGIgPSBkb2N1bWVudC5xdWVyeVNlbGVjdG9yKCIueXRwLWZ1bGxzY3JlZW4tYnV0dG9uIik7CiAgICAgICAgICBpZiAoYikgYi5jbGljaygpOwogICAgICAgIH0gZWxzZSByZXR1cm4gIkFrc2kgdGlkYWsgZGlrZW5hbC4gUGlsaWg6IHBsYXksIHBh
::B64:agent.js:dXNlLCB0b2dnbGUsIG11dGUsIHVubXV0ZSwgZm9yd2FyZCwgYmFja3dhcmQsIG5leHQsIHByZXZpb3VzLCBmdWxsc2NyZWVuIjsKICAgICAgICByZXR1cm4gIm9rIjsKICAgICAgfSwKICAgICAgeyBhOiBTdHJpbmcoYWN0aW9uKS50b0xvd2VyQ2FzZSgpLCBzOiBO
::B64:agent.js:dW1iZXIoc2Vjb25kcykgfHwgMTAgfQogICAgKTsKICB9LAoKICAvLyAtLS0gV2ViIC0tLQogIHdlYl9zZWFyY2g6IGFzeW5jICh7IHF1ZXJ5LCBuZXdfdGFiID0gZmFsc2UgfSkgPT4gewogICAgaWYgKGlzVHJ1ZShuZXdfdGFiKSkgcGFnZSA9IGF3YWl0IGNvbnRl
::B64:agent.js:eHQubmV3UGFnZSgpOwogICAgYXdhaXQgcGFnZS5icmluZ1RvRnJvbnQoKTsKICAgIGF3YWl0IHBhZ2UuZ290bygiaHR0cHM6Ly9odG1sLmR1Y2tkdWNrZ28uY29tL2h0bWwvP3E9IiArIGVuY29kZVVSSUNvbXBvbmVudChTdHJpbmcocXVlcnkpKSwgewogICAgICB3
::B64:agent.js:YWl0VW50aWw6ICJkb21jb250ZW50bG9hZGVkIiwKICAgIH0pOwogICAgY29uc3Qgcm93cyA9IGF3YWl0IHBhZ2UuJCRldmFsKCIucmVzdWx0IiwgKGVscykgPT4KICAgICAgZWxzLnNsaWNlKDAsIDgpLm1hcCgoZSkgPT4gKHsKICAgICAgICB0aXRsZTogZS5xdWVy
::B64:agent.js:eVNlbGVjdG9yKCIucmVzdWx0X19hIik/LnRleHRDb250ZW50LnRyaW0oKSwKICAgICAgICB1cmw6IGUucXVlcnlTZWxlY3RvcigiLnJlc3VsdF9fYSIpPy5ocmVmLAogICAgICAgIHNuaXBwZXQ6IGUucXVlcnlTZWxlY3RvcigiLnJlc3VsdF9fc25pcHBldCIpPy50
::B64:agent.js:ZXh0Q29udGVudC50cmltKCksCiAgICAgIH0pKQogICAgKTsKICAgIGNvbnN0IHJlYWwgPSAodSkgPT4gewogICAgICB0cnkgewogICAgICAgIGNvbnN0IHggPSBuZXcgVVJMKHUpOwogICAgICAgIHJldHVybiB4LnNlYXJjaFBhcmFtcy5nZXQoInVkZGciKSB8fCB1
::B64:agent.js:OwogICAgICB9IGNhdGNoIHsKICAgICAgICByZXR1cm4gdTsKICAgICAgfQogICAgfTsKICAgIGNvbnN0IG9rID0gcm93cy5maWx0ZXIoKHIpID0+IHIudGl0bGUpOwogICAgcmV0dXJuIG9rLmxlbmd0aCA/IG9rLm1hcCgociwgaSkgPT4gYCR7aSArIDF9LiAke3Iu
::B64:agent.js:dGl0bGV9XG4gICAke3JlYWwoci51cmwpfVxuICAgJHtyLnNuaXBwZXQgfHwgIiJ9YCkuam9pbigiXG4iKSA6ICJUaWRhayBhZGEgaGFzaWwiOwogIH0sCgogIHNjcm9sbF9wYWdlOiBhc3luYyAoeyBhbW91bnQgfSkgPT4gewogICAgYXdhaXQgcGFnZS5tb3VzZS53
::B64:agent.js:aGVlbCgwLCBNYXRoLnJvdW5kKE51bWJlcihhbW91bnQpIHx8IDEpICogNzAwKTsKICAgIGF3YWl0IHNsZWVwKDQwMCk7CiAgICByZXR1cm4gIm9rIjsKICB9LAoKICB3YWl0X2Zvcl91c2VyOiBhc3luYyAoeyBtZXNzYWdlIH0pID0+IHsKICAgIGF3YWl0IHBhZ2Uu
::B64:agent.js:YnJpbmdUb0Zyb250KCkuY2F0Y2goKCkgPT4ge30pOwogICAgY29uc29sZS5sb2coYFxuW0JVVFVIIEJBTlRVQU4gS0FNVV0gJHttZXNzYWdlfWApOwogICAgYXdhaXQgcmwucXVlc3Rpb24oIlRla2FuIEVudGVyIGppa2Egc3VkYWggc2VsZXNhaS4uLiAiKTsKICAg
::B64:agent.js:IHJldHVybiAiVXNlciBzdWRhaCBzZWxlc2FpIjsKICB9LAoKICBkb3dubG9hZF9maWxlOiBhc3luYyAoeyB1cmwsIGZpbGVuYW1lIH0pID0+IHsKICAgIGlmICghL15odHRwcz86XC9cLy9pLnRlc3QoU3RyaW5nKHVybCkpKSB0aHJvdyBuZXcgRXJyb3IoIlVSTCBo
::B64:agent.js:YXJ1cyBkaWF3YWxpIGh0dHA6Ly8gYXRhdSBodHRwczovLyIpOwogICAgY29uc3QgZ3Vlc3MgPSBkZWNvZGVVUklDb21wb25lbnQobmV3IFVSTCh1cmwpLnBhdGhuYW1lLnNwbGl0KCIvIikucG9wKCkgfHwgIiIpIHx8ICJkb3dubG9hZC5iaW4iOwogICAgY29uc3Qg
::B64:agent.js:ZGVzdCA9IHBhdGguam9pbihIT01FLCAiRG93bmxvYWRzIiwgcGF0aC5iYXNlbmFtZShTdHJpbmcoZmlsZW5hbWUgfHwgZ3Vlc3MpKSk7CiAgICBpZiAoIShhd2FpdCBhc2soYFVuZHVoICR7dXJsfSAga2UgICR7ZGVzdH1gKSkpIHJldHVybiAiRGliYXRhbGthbiB1
::B64:agent.js:c2VyIjsKICAgIGNvbnN0IHJlcyA9IGF3YWl0IGZldGNoKHVybCwgeyByZWRpcmVjdDogImZvbGxvdyIsIHNpZ25hbDogQWJvcnRTaWduYWwudGltZW91dCgxMCAqIDYwICogMTAwMCkgfSk7CiAgICBpZiAoIXJlcy5vaykgdGhyb3cgbmV3IEVycm9yKCJIVFRQICIg
::B64:agent.js:KyByZXMuc3RhdHVzKTsKICAgIGF3YWl0IHBpcGVsaW5lKFJlYWRhYmxlLmZyb21XZWIocmVzLmJvZHkpLCBmcy5jcmVhdGVXcml0ZVN0cmVhbShkZXN0KSk7CiAgICByZXR1cm4gYG9rLCB0ZXJzaW1wYW46ICR7ZGVzdH0gKCR7ZnMuc3RhdFN5bmMoZGVzdCkuc2l6
::B64:agent.js:ZX0gYnl0ZSlgOwogIH0sCgogIC8vIC0tLSBQQzogaW5mbywgbWVkaWEsIGNsaXBib2FyZCwgamVuZGVsYSAtLS0KICBub3c6IGFzeW5jICgpID0+IG5ldyBEYXRlKCkudG9Mb2NhbGVTdHJpbmcoImlkLUlEIiwgeyBkYXRlU3R5bGU6ICJmdWxsIiwgdGltZVN0eWxl
::B64:agent.js:OiAibG9uZyIgfSksCgogIHN5c3RlbV9pbmZvOiBhc3luYyAoKSA9PgogICAgcHMoYAokb3MgPSBHZXQtQ2ltSW5zdGFuY2UgV2luMzJfT3BlcmF0aW5nU3lzdGVtCiRjcHUgPSBHZXQtQ2ltSW5zdGFuY2UgV2luMzJfUHJvY2Vzc29yIHwgU2VsZWN0LU9iamVjdCAt
::B64:agent.js:Rmlyc3QgMQokYmF0ID0gR2V0LUNpbUluc3RhbmNlIFdpbjMyX0JhdHRlcnkgfCBTZWxlY3QtT2JqZWN0IC1GaXJzdCAxCiRsID0gQCgpCiRsICs9ICJPUzogIiArICRvcy5DYXB0aW9uCiRsICs9ICJDUFU6ICIgKyAkY3B1Lk5hbWUgKyAiIChiZWJhbiAiICsgJGNw
::B64:agent.js:dS5Mb2FkUGVyY2VudGFnZSArICIlKSIKJGwgKz0gIlJBTTogYmViYXMgIiArIFttYXRoXTo6Um91bmQoJG9zLkZyZWVQaHlzaWNhbE1lbW9yeSAvIDFNQiwgMSkgKyAiIEdCIGRhcmkgIiArIFttYXRoXTo6Um91bmQoJG9zLlRvdGFsVmlzaWJsZU1lbW9yeVNpemUg
::B64:agent.js:LyAxTUIsIDEpICsgIiBHQiIKaWYgKCRiYXQpIHsgJGwgKz0gIkJhdGVyYWk6ICIgKyAkYmF0LkVzdGltYXRlZENoYXJnZVJlbWFpbmluZyArICIlIiB9IGVsc2UgeyAkbCArPSAiQmF0ZXJhaTogdGlkYWsgYWRhIChQQyBkZXNrdG9wKSIgfQpHZXQtQ2ltSW5zdGFu
::B64:agent.js:Y2UgV2luMzJfTG9naWNhbERpc2sgLUZpbHRlciAiRHJpdmVUeXBlPTMiIHwgRm9yRWFjaC1PYmplY3QgeyAkbCArPSAiRGlzayAiICsgJF8uRGV2aWNlSUQgKyAiIGJlYmFzICIgKyBbbWF0aF06OlJvdW5kKCRfLkZyZWVTcGFjZSAvIDFHQiwgMSkgKyAiIEdCIGRh
::B64:agent.js:cmkgIiArIFttYXRoXTo6Um91bmQoJF8uU2l6ZSAvIDFHQiwgMSkgKyAiIEdCIiB9CiRsIC1qb2luIFtFbnZpcm9ubWVudF06Ok5ld0xpbmUKYCksCgogIG1lZGlhX2tleTogYXN5bmMgKHsga2V5LCB0aW1lcyA9IDEgfSkgPT4gewogICAgY29uc3QgdmFsaWQgPSBb
::B64:agent.js:InZvbHVwIiwgInZvbGRvd24iLCAibXV0ZSIsICJwbGF5cGF1c2UiLCAibmV4dCIsICJwcmV2Il07CiAgICBpZiAoIXZhbGlkLmluY2x1ZGVzKFN0cmluZyhrZXkpKSkgcmV0dXJuICJrZXkgaGFydXMgc2FsYWggc2F0dSBkYXJpOiAiICsgdmFsaWQuam9pbigiLCAi
::B64:agent.js:KTsKICAgIGF3YWl0IHBzKAogICAgICBgCkFkZC1UeXBlIEAiCnVzaW5nIFN5c3RlbS5SdW50aW1lLkludGVyb3BTZXJ2aWNlczsKcHVibGljIGNsYXNzIEsgeyBbRGxsSW1wb3J0KCJ1c2VyMzIuZGxsIildIHB1YmxpYyBzdGF0aWMgZXh0ZXJuIHZvaWQga2V5YmRf
::B64:agent.js:ZXZlbnQoYnl0ZSBiLCBieXRlIHMsIHVpbnQgZiwgaW50IGUpOyB9CiJACiRtYXAgPSBAeyB2b2x1cCA9IDB4QUY7IHZvbGRvd24gPSAweEFFOyBtdXRlID0gMHhBRDsgcGxheXBhdXNlID0gMHhCMzsgbmV4dCA9IDB4QjA7IHByZXYgPSAweEIxIH0KJGsgPSBbYnl0
::B64:agent.js:ZV0kbWFwWyRlbnY6S0VZXQpmb3IgKCRpID0gMDsgJGkgLWx0IFtpbnRdJGVudjpOOyAkaSsrKSB7IFtLXTo6a2V5YmRfZXZlbnQoJGssIDAsIDAsIDApOyBbS106OmtleWJkX2V2ZW50KCRrLCAwLCAyLCAwKTsgU3RhcnQtU2xlZXAgLU1pbGxpc2Vjb25kcyA2MCB9
::B64:agent.js:CmAsCiAgICAgIHsgS0VZOiBTdHJpbmcoa2V5KSwgTjogU3RyaW5nKE1hdGgubWluKE1hdGgubWF4KE51bWJlcih0aW1lcykgfHwgMSwgMSksIDUwKSkgfQogICAgKTsKICAgIHJldHVybiAib2siOwogIH0sCgogIGNsaXBib2FyZF9nZXQ6IGFzeW5jICgpID0+IChh
::B64:agent.js:d2FpdCBwcygiR2V0LUNsaXBib2FyZCAtUmF3IikpLnNsaWNlKDAsIDQwMDApIHx8ICIoa29zb25nKSIsCgogIGNsaXBib2FyZF9zZXQ6IGFzeW5jICh7IHRleHQgfSkgPT4gewogICAgYXdhaXQgcHMoIlNldC1DbGlwYm9hcmQgLVZhbHVlICRlbnY6VFhUIiwgeyBU
::B64:agent.js:WFQ6IFN0cmluZyh0ZXh0KSB9KTsKICAgIHJldHVybiAib2siOwogIH0sCgogIGxpc3Rfd2luZG93czogYXN5bmMgKCkgPT4KICAgIChhd2FpdCBwcyhgR2V0LVByb2Nlc3MgfCBXaGVyZS1PYmplY3QgeyAkXy5NYWluV2luZG93VGl0bGUgfSB8IEZvckVhY2gtT2Jq
::B64:agent.js:ZWN0IHsgJF8uUHJvY2Vzc05hbWUgKyAiIHwgIiArICRfLk1haW5XaW5kb3dUaXRsZSB9YCkpIHx8CiAgICAiKHRpZGFrIGFkYSBqZW5kZWxhKSIsCgogIGZvY3VzX3dpbmRvdzogYXN5bmMgKHsgdGl0bGUgfSkgPT4KICAgIHBzKGBpZiAoKE5ldy1PYmplY3QgLUNv
::B64:agent.js:bU9iamVjdCBXU2NyaXB0LlNoZWxsKS5BcHBBY3RpdmF0ZSgkZW52OlRJVExFKSkgeyAib2siIH0gZWxzZSB7ICJqZW5kZWxhIHRpZGFrIGRpdGVtdWthbiIgfWAsIHsKICAgICAgVElUTEU6IFN0cmluZyh0aXRsZSksCiAgICB9KSwKCiAgY2xvc2Vfd2luZG93OiBh
::B64:agent.js:c3luYyAoeyB0aXRsZSB9KSA9PiB7CiAgICBpZiAoIShhd2FpdCBhc2soYFR1dHVwIGplbmRlbGE6ICR7dGl0bGV9YCkpKSByZXR1cm4gIkRpYmF0YWxrYW4gdXNlciI7CiAgICByZXR1cm4gcHMoCiAgICAgIGAkcCA9IEdldC1Qcm9jZXNzIHwgV2hlcmUtT2JqZWN0
::B64:agent.js:IHsgJF8uTWFpbldpbmRvd1RpdGxlIC1saWtlICgiKiIgKyAkZW52OlRJVExFICsgIioiKSB9IHwgU2VsZWN0LU9iamVjdCAtRmlyc3QgMQppZiAoJHApIHsgJHAuQ2xvc2VNYWluV2luZG93KCkgfCBPdXQtTnVsbDsgIm9rOiAiICsgJHAuTWFpbldpbmRvd1RpdGxl
::B64:agent.js:IH0gZWxzZSB7ICJqZW5kZWxhIHRpZGFrIGRpdGVtdWthbiIgfWAsCiAgICAgIHsgVElUTEU6IFN0cmluZyh0aXRsZSkgfQogICAgKTsKICB9LAoKICAvLyAtLS0gRmlsZSAtLS0KICByZWFkX3RleHRfZmlsZTogYXN5bmMgKHsgcGF0aDogcCB9KSA9PiB7CiAgICBj
::B64:agent.js:b25zdCBmdWxsID0gcGF0aC5yZXNvbHZlKFN0cmluZyhwKSk7CiAgICBjb25zdCBzdCA9IGZzLnN0YXRTeW5jKGZ1bGwpOwogICAgaWYgKCFzdC5pc0ZpbGUoKSkgdGhyb3cgbmV3IEVycm9yKCJCdWthbiBmaWxlOiAiICsgZnVsbCk7CiAgICBpZiAoc3Quc2l6ZSA+
::B64:agent.js:IDJfMDAwXzAwMCkgdGhyb3cgbmV3IEVycm9yKCJGaWxlIHRlcmxhbHUgYmVzYXIgdW50dWsgZGliYWNhICgiICsgc3Quc2l6ZSArICIgYnl0ZSkiKTsKICAgIHJldHVybiBmcy5yZWFkRmlsZVN5bmMoZnVsbCwgInV0ZjgiKS5zbGljZSgwLCA4MDAwKTsKICB9LAoK
::B64:agent.js:ICB3cml0ZV90ZXh0X2ZpbGU6IGFzeW5jICh7IHBhdGg6IHAsIGNvbnRlbnQsIGFwcGVuZCA9IGZhbHNlIH0pID0+IHsKICAgIGNvbnN0IGZ1bGwgPSBwYXRoLnJlc29sdmUoU3RyaW5nKHApKTsKICAgIGNvbnN0IGFkZCA9IGFwcGVuZCA9PT0gdHJ1ZSB8fCBhcHBl
::B64:agent.js:bmQgPT09ICJ0cnVlIjsKICAgIGNvbnN0IHZlcmIgPSBhZGQgPyAiVGFtYmFoIGtlIiA6IGZzLmV4aXN0c1N5bmMoZnVsbCkgPyAiVElNUEEiIDogIkJ1YXQiOwogICAgaWYgKCEoYXdhaXQgYXNrKGAke3ZlcmJ9IGZpbGU6ICR7ZnVsbH1gKSkpIHJldHVybiAiRGli
::B64:agent.js:YXRhbGthbiB1c2VyIjsKICAgIGZzLm1rZGlyU3luYyhwYXRoLmRpcm5hbWUoZnVsbCksIHsgcmVjdXJzaXZlOiB0cnVlIH0pOwogICAgaWYgKGFkZCkgZnMuYXBwZW5kRmlsZVN5bmMoZnVsbCwgU3RyaW5nKGNvbnRlbnQpKTsKICAgIGVsc2UgZnMud3JpdGVGaWxl
::B64:agent.js:U3luYyhmdWxsLCBTdHJpbmcoY29udGVudCkpOwogICAgcmV0dXJuICJvazogIiArIGZ1bGw7CiAgfSwKCiAgbWFrZV9mb2xkZXI6IGFzeW5jICh7IHBhdGg6IHAgfSkgPT4gewogICAgY29uc3QgZnVsbCA9IHBhdGgucmVzb2x2ZShTdHJpbmcocCkpOwogICAgaWYg
::B64:agent.js:KCEoYXdhaXQgYXNrKGBCdWF0IGZvbGRlcjogJHtmdWxsfWApKSkgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgZnMubWtkaXJTeW5jKGZ1bGwsIHsgcmVjdXJzaXZlOiB0cnVlIH0pOwogICAgcmV0dXJuICJvazogIiArIGZ1bGw7CiAgfSwKCiAgbW92ZV9w
::B64:agent.js:YXRoOiBhc3luYyAoeyBmcm9tLCB0byB9KSA9PiB7CiAgICBpZiAoIShhd2FpdCBhc2soYFBpbmRhaGthbjogJHtmcm9tfSAga2UgICR7dG99YCkpKSByZXR1cm4gIkRpYmF0YWxrYW4gdXNlciI7CiAgICBhd2FpdCBwcygiTW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAk
::B64:agent.js:ZW52OlNSQyAtRGVzdGluYXRpb24gJGVudjpERVNUIiwgewogICAgICBTUkM6IHBhdGgucmVzb2x2ZShTdHJpbmcoZnJvbSkpLAogICAgICBERVNUOiBwYXRoLnJlc29sdmUoU3RyaW5nKHRvKSksCiAgICB9KTsKICAgIHJldHVybiAib2siOwogIH0sCgogIHJlY3lj
::B64:agent.js:bGVfcGF0aDogYXN5bmMgKHsgcGF0aDogcCB9KSA9PiB7CiAgICBjb25zdCBmdWxsID0gcGF0aC5yZXNvbHZlKFN0cmluZyhwKSk7CiAgICBpZiAoIShhd2FpdCBhc2soYFBpbmRhaGthbiBrZSBSZWN5Y2xlIEJpbjogJHtmdWxsfWApKSkgcmV0dXJuICJEaWJhdGFs
::B64:agent.js:a2FuIHVzZXIiOwogICAgYXdhaXQgcHMoCiAgICAgIGBBZGQtVHlwZSAtQXNzZW1ibHlOYW1lIE1pY3Jvc29mdC5WaXN1YWxCYXNpYwokcCA9ICRlbnY6VEFSR0VUCmlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRwIC1QYXRoVHlwZSBDb250YWluZXIpIHsgW01p
::B64:agent.js:Y3Jvc29mdC5WaXN1YWxCYXNpYy5GaWxlSU8uRmlsZVN5c3RlbV06OkRlbGV0ZURpcmVjdG9yeSgkcCwgJ09ubHlFcnJvckRpYWxvZ3MnLCAnU2VuZFRvUmVjeWNsZUJpbicpIH0KZWxzZSB7IFtNaWNyb3NvZnQuVmlzdWFsQmFzaWMuRmlsZUlPLkZpbGVTeXN0ZW1d
::B64:agent.js:OjpEZWxldGVGaWxlKCRwLCAnT25seUVycm9yRGlhbG9ncycsICdTZW5kVG9SZWN5Y2xlQmluJykgfWAsCiAgICAgIHsgVEFSR0VUOiBmdWxsIH0KICAgICk7CiAgICByZXR1cm4gIm9rLCBkaXBpbmRhaCBrZSBSZWN5Y2xlIEJpbiAobWFzaWggYmlzYSBkaXB1bGlo
::B64:agent.js:a2FuKSI7CiAgfSwKCiAgemlwX3BhdGg6IGFzeW5jICh7IHNvdXJjZSwgemlwIH0pID0+IHsKICAgIGNvbnN0IHNyYyA9IHBhdGgucmVzb2x2ZShTdHJpbmcoc291cmNlKSk7CiAgICBjb25zdCBkZXN0ID0gcGF0aC5yZXNvbHZlKFN0cmluZyh6aXApKTsKICAgIGlm
::B64:agent.js:ICghKGF3YWl0IGFzayhgWmlwICR7c3JjfSAgbWVuamFkaSAgJHtkZXN0fWApKSkgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgYXdhaXQgcHMoIkNvbXByZXNzLUFyY2hpdmUgLUxpdGVyYWxQYXRoICRlbnY6U1JDIC1EZXN0aW5hdGlvblBhdGggJGVudjpE
::B64:agent.js:RVNUIC1Gb3JjZSIsIHsgU1JDOiBzcmMsIERFU1Q6IGRlc3QgfSwgNjAwMDAwKTsKICAgIHJldHVybiAib2s6ICIgKyBkZXN0OwogIH0sCgogIHVuemlwX3BhdGg6IGFzeW5jICh7IHppcCwgZm9sZGVyIH0pID0+IHsKICAgIGNvbnN0IHNyYyA9IHBhdGgucmVzb2x2
::B64:agent.js:ZShTdHJpbmcoemlwKSk7CiAgICBjb25zdCBkZXN0ID0gcGF0aC5yZXNvbHZlKFN0cmluZyhmb2xkZXIpKTsKICAgIGlmICghKGF3YWl0IGFzayhgRWtzdHJhayAke3NyY30gIGtlICAke2Rlc3R9YCkpKSByZXR1cm4gIkRpYmF0YWxrYW4gdXNlciI7CiAgICBhd2Fp
::B64:agent.js:dCBwcygiRXhwYW5kLUFyY2hpdmUgLUxpdGVyYWxQYXRoICRlbnY6U1JDIC1EZXN0aW5hdGlvblBhdGggJGVudjpERVNUIC1Gb3JjZSIsIHsgU1JDOiBzcmMsIERFU1Q6IGRlc3QgfSwgNjAwMDAwKTsKICAgIHJldHVybiAib2s6ICIgKyBkZXN0OwogIH0sCgogIG1v
::B64:agent.js:cmVfdG9vbHM6IGFzeW5jICh7IGdyb3VwIH0pID0+IHsKICAgIGNvbnN0IGcgPSBTdHJpbmcoZ3JvdXApLnRvTG93ZXJDYXNlKCk7CiAgICBpZiAoIVRPT0xfR1JPVVBTW2ddKSByZXR1cm4gIkdydXAgdGlkYWsgZGlrZW5hbC4gUGlsaWg6ICIgKyBPYmplY3Qua2V5
::B64:agent.js:cyhUT09MX0dST1VQUykuam9pbigiLCAiKTsKICAgIGV4dHJhR3JvdXBzLmFkZChnKTsKICAgIHJldHVybiBgQWxhdCBncnVwICR7Z30gc2VrYXJhbmcgdGVyc2VkaWE6ICR7VE9PTF9HUk9VUFNbZ10uam9pbigiLCAiKX1gOwogIH0sCgogIGdldF9wYWdlX3RleHQ6
::B64:agent.js:IGFzeW5jICgpID0+IChhd2FpdCBwYWdlLmlubmVyVGV4dCgiYm9keSIpKS5zbGljZSgwLCA0MDAwKSwKCiAgdHlwZV90ZXh0OiBhc3luYyAoeyBzZWxlY3RvciwgdGV4dCB9KSA9PiB7CiAgICBhd2FpdCBwYWdlLmZpbGwoc2VsZWN0b3IsIHRleHQpOwogICAgcmV0
::B64:agent.js:dXJuICJvayI7CiAgfSwKCiAgY2xpY2s6IGFzeW5jICh7IHNlbGVjdG9yIH0pID0+IHsKICAgIGlmICghKGF3YWl0IGFzayhgS2xpayBlbGVtZW4gYnJvd3NlcjogJHtzZWxlY3Rvcn1gKSkpIHJldHVybiAiRGliYXRhbGthbiB1c2VyIjsKICAgIGF3YWl0IHBhZ2Uu
::B64:agent.js:Y2xpY2soc2VsZWN0b3IsIHsgdGltZW91dDogMTAwMDAgfSk7CiAgICByZXR1cm4gIm9rIjsKICB9LAoKICB1cGxvYWRfZmlsZTogYXN5bmMgKHsgc2VsZWN0b3IsIGZpbGVuYW1lLCBmb2xkZXIsIHBhdHRlcm4gfSkgPT4gewogICAgbGV0IGZpbGVzID0gW107CiAg
::B64:agent.js:ICBpZiAoZmlsZW5hbWUpIHsKICAgICAgZmlsZXMgPSBTdHJpbmcoZmlsZW5hbWUpCiAgICAgICAgLnNwbGl0KCJ8IikKICAgICAgICAubWFwKCh4KSA9PiB4LnRyaW0oKSkKICAgICAgICAuZmlsdGVyKEJvb2xlYW4pCiAgICAgICAgLm1hcChzYWZlUGF0aCk7CiAg
::B64:agent.js:ICB9CiAgICBpZiAoZm9sZGVyKSB7CiAgICAgIGNvbnN0IGRpciA9IHBhdGgucmVzb2x2ZShTdHJpbmcoZm9sZGVyKSk7CiAgICAgIGNvbnN0IHEgPSBwYXR0ZXJuID8gU3RyaW5nKHBhdHRlcm4pLnRvTG93ZXJDYXNlKCkucmVwbGFjZSgvXlwqLywgIiIpIDogIiI7
::B64:agent.js:CiAgICAgIGZvciAoY29uc3QgZSBvZiBmcy5yZWFkZGlyU3luYyhkaXIsIHsgd2l0aEZpbGVUeXBlczogdHJ1ZSB9KSkgewogICAgICAgIGlmIChlLmlzRmlsZSgpICYmICghcSB8fCBlLm5hbWUudG9Mb3dlckNhc2UoKS5pbmNsdWRlcyhxKSkpIGZpbGVzLnB1c2go
::B64:agent.js:cGF0aC5qb2luKGRpciwgZS5uYW1lKSk7CiAgICAgIH0KICAgIH0KICAgIGlmICghZmlsZXMubGVuZ3RoKSB0aHJvdyBuZXcgRXJyb3IoIlRpZGFrIGFkYSBmaWxlIHlhbmcgY29jb2sgdW50dWsgZGl1cGxvYWQiKTsKICAgIGZpbGVzID0gZmlsZXMuc2xpY2UoMCwg
::B64:agent.js:NTApOwogICAgaWYgKCEoYXdhaXQgYXNrKGBVcGxvYWQgJHtmaWxlcy5sZW5ndGh9IGZpbGU6XG4gICAke2ZpbGVzLmpvaW4oIlxuICAgIil9XG4gIGApKSkgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgY29uc3QgbXVsdGlwbGUgPSBhd2FpdCBwYWdlLiRl
::B64:agent.js:dmFsKHNlbGVjdG9yLCAoZWwpID0+ICEhZWwubXVsdGlwbGUpLmNhdGNoKCgpID0+IGZhbHNlKTsKICAgIGlmIChmaWxlcy5sZW5ndGggPiAxICYmICFtdWx0aXBsZSkgewogICAgICBhd2FpdCBwYWdlLnNldElucHV0RmlsZXMoc2VsZWN0b3IsIGZpbGVzWzBdKTsK
::B64:agent.js:ICAgICAgcmV0dXJuICgKICAgICAgICBgSW5wdXQgaW5pIGhhbnlhIG1lbmVyaW1hIDEgZmlsZS4gVGVycGlsaWg6ICR7ZmlsZXNbMF19LiBTaXNhICR7ZmlsZXMubGVuZ3RoIC0gMX0gZmlsZTogYCArCiAgICAgICAgYCR7ZmlsZXMuc2xpY2UoMSkuam9pbigiIHwg
::B64:agent.js:Iil9LiBTZWxlc2Fpa2FuIHVwbG9hZCBpbmksIGxhbHUgdWxhbmdpIHVwbG9hZF9maWxlIHVudHVrIHNpc2FueWEuYAogICAgICApOwogICAgfQogICAgYXdhaXQgcGFnZS5zZXRJbnB1dEZpbGVzKHNlbGVjdG9yLCBmaWxlcyk7CiAgICByZXR1cm4gYG9rLCAke2Zp
::B64:agent.js:bGVzLmxlbmd0aH0gZmlsZSBkaXBpbGloYDsKICB9LAp9OwoKY29uc3QgZm4gPSAobmFtZSwgZGVzY3JpcHRpb24sIHByb3BlcnRpZXMgPSB7fSwgb3B0aW9uYWwgPSBbXSkgPT4gKHsKICB0eXBlOiAiZnVuY3Rpb24iLAogIGZ1bmN0aW9uOiB7CiAgICBuYW1lLAog
::B64:agent.js:ICAgZGVzY3JpcHRpb24sCiAgICBwYXJhbWV0ZXJzOiB7CiAgICAgIHR5cGU6ICJvYmplY3QiLAogICAgICBwcm9wZXJ0aWVzLAogICAgICByZXF1aXJlZDogT2JqZWN0LmtleXMocHJvcGVydGllcykuZmlsdGVyKChrKSA9PiAhb3B0aW9uYWwuaW5jbHVkZXMoaykp
::B64:agent.js:LAogICAgfSwKICB9LAp9KTsKY29uc3Qgc3RyID0gKGQpID0+ICh7IHR5cGU6ICJzdHJpbmciLCBkZXNjcmlwdGlvbjogZCB9KTsKY29uc3QgbnVtID0gKGQpID0+ICh7IHR5cGU6ICJudW1iZXIiLCBkZXNjcmlwdGlvbjogZCB9KTsKY29uc3QgYm9vbCA9IChkKSA9
::B64:agent.js:PiAoeyB0eXBlOiAiYm9vbGVhbiIsIGRlc2NyaXB0aW9uOiBkIH0pOwoKY29uc3QgdG9vbHMgPSBbCiAgZm4oImZpbmRfZm9sZGVyIiwgIkNhcmkgZm9sZGVyIGRpIHNlbHVydWggUEMgKHNlbXVhIGRyaXZlKSBiZXJkYXNhcmthbiBuYW1hOyBzZWJhZ2lhbiBuYW1h
::B64:agent.js:IGN1a3VwIiwgeyBuYW1lOiBzdHIoIk5hbWEgZm9sZGVyIikgfSksCiAgZm4oImZpbmRfZmlsZSIsICJDYXJpIGZpbGUgZGkgc2VsdXJ1aCBQQyAoc2VtdWEgZHJpdmUpIGJlcmRhc2Fya2FuIG5hbWE7IHNlYmFnaWFuIG5hbWEgY3VrdXAiLCB7IG5hbWU6IHN0cigi
::B64:agent.js:TmFtYSBmaWxlIikgfSksCiAgZm4oImxpc3RfZGlyIiwgIkxpaGF0IGlzaSBzZWJ1YWggZm9sZGVyIGRpIFBDIiwgeyBwYXRoOiBzdHIoIlBhdGggbGVuZ2thcCBmb2xkZXIiKSB9KSwKICBmbigib3Blbl9wYXRoIiwgIkJ1a2EgZm9sZGVyLCBmaWxlLCBhcGxpa2Fz
::B64:agent.js:aSAobWlzLiBub3RlcGFkKSwgYXRhdSBVUkwgZGkgUEMiLCB7IHRhcmdldDogc3RyKCJQYXRoL25hbWEgYXBsaWthc2kvVVJMIikgfSksCiAgZm4oInNjcmVlbnNob3QiLCAiQW1iaWwgc2NyZWVuc2hvdCBsYXlhciBQQyB1bnR1ayBtZWxpaGF0IGtvbmRpc2kgc2Vr
::B64:agent.js:YXJhbmciKSwKICBmbigKICAgICJjbGlja19zY3JlZW4iLAogICAgIktsaWsgZGkgbGF5YXIgUEMgcGFkYSBrb29yZGluYXQgZGFyaSBzY3JlZW5zaG90IHRlcmFraGlyIiwKICAgIHsgeDogbnVtKCJLb29yZGluYXQgWCBkaSBzY3JlZW5zaG90IiksIHk6IG51bSgi
::B64:agent.js:S29vcmRpbmF0IFkgZGkgc2NyZWVuc2hvdCIpLCBidXR0b246IHN0cigibGVmdCBhdGF1IHJpZ2h0IiksIGRvdWJsZTogeyB0eXBlOiAiYm9vbGVhbiIsIGRlc2NyaXB0aW9uOiAiZG91YmxlLWtsaWsiIH0gfSwKICAgIFsiYnV0dG9uIiwgImRvdWJsZSJdCiAgKSwK
::B64:agent.js:ICBmbigic2Nyb2xsX3NjcmVlbiIsICJTY3JvbGwgbGF5YXIuIFBvc2l0aWYgPSB0dXJ1biwgbmVnYXRpZiA9IG5haWsiLCB7IGFtb3VudDogbnVtKCJKdW1sYWggc2Nyb2xsIikgfSksCiAgZm4oInR5cGVfZGVza3RvcCIsICJLZXRpayB0ZWtzIGRpIGFwbGlrYXNp
::B64:agent.js:IHlhbmcgc2VkYW5nIGZva3VzIGRpIFBDIiwgeyB0ZXh0OiBzdHIoIlRla3MiKSB9KSwKICBmbigicHJlc3Nfa2V5cyIsICJUZWthbiB0b21ib2wgZm9ybWF0IFNlbmRLZXlzOiB7RU5URVJ9LCB7VEFCfSwge0VTQ30sIF5jIChDdHJsK0MpLCBediwgXmwsICV7RjR9
::B64:agent.js:IiwgeyBrZXlzOiBzdHIoIktvbWJpbmFzaSB0b21ib2wiKSB9KSwKICBmbigid2FpdCIsICJUdW5nZ3UgYmViZXJhcGEgZGV0aWsgKG1ha3MgMTUpIHN1cGF5YSBoYWxhbWFuL2FwbGlrYXNpIHNlbGVzYWkgZGltdWF0IiwgeyBzZWNvbmRzOiBudW0oIkRldGlrIikg
::B64:agent.js:fSksCiAgZm4oImxpc3RfZmlsZXMiLCAiTGloYXQgZGFmdGFyIGZpbGUgZGkgZm9sZGVyIHVwbG9hZCBraHVzdXMiKSwKICBmbigKICAgICJvcGVuX3VybCIsCiAgICAiQnVrYSB3ZWJzaXRlIGRpIGJyb3dzZXIuIFNlY2FyYSBiYXdhYW4gbWVuaW1wYSB0YWIgYWt0
::B64:agent.js:aWY7IHBha2FpIG5ld190YWI9dHJ1ZSBhZ2FyIGhhbGFtYW4vdmlkZW8geWFuZyBzZWRhbmcgdGVyYnVrYSB0aWRhayB0ZXJ0aW1wYSIsCiAgICB7IHVybDogc3RyKCJVUkwgbGVuZ2thcCIpLCBuZXdfdGFiOiBib29sKCJ0cnVlID0gYnVrYSBkaSB0YWIgYmFydSIp
::B64:agent.js:IH0sCiAgICBbIm5ld190YWIiXQogICksCiAgZm4oImxpc3RfdGFicyIsICJEYWZ0YXIgc2VtdWEgdGFiIGJyb3dzZXIgKHRhbmRhICogPSB0YWIgYWt0aWYpIiksCiAgZm4oIm5ld190YWIiLCAiQnVrYSB0YWIgYmFydSAoa29zb25nLCBhdGF1IGxhbmdzdW5nIGtl
::B64:agent.js:IFVSTCkgZGFuIGphZGlrYW4gdGFiIGFrdGlmIiwgeyB1cmw6IHN0cigiVVJMIChvcHNpb25hbCkiKSB9LCBbInVybCJdKSwKICBmbigib3Blbl91cmxzIiwgIkJ1a2EgQkFOWUFLIHdlYnNpdGUgc2VrYWxpZ3VzLCBtYXNpbmctbWFzaW5nIGRpIHRhYiBiYXJ1Iiwg
::B64:agent.js:ewogICAgdXJsczogeyB0eXBlOiAiYXJyYXkiLCBpdGVtczogeyB0eXBlOiAic3RyaW5nIiB9LCBkZXNjcmlwdGlvbjogIkRhZnRhciBVUkwgKG1ha3NpbWFsIDEwKSIgfSwKICB9KSwKICBmbigKICAgICJzd2l0Y2hfdGFiIiwKICAgICJQaW5kYWggdGFiIGFrdGlm
::B64:agent.js:LiBQYWthaSBpbmRleCAoMSA9IHRhYiBwZXJ0YW1hLCAtMSA9IHRhYiB0ZXJiYXJ1KSBBVEFVIG1hdGNoIChzZWJhZ2lhbiBqdWR1bC9VUkwpIiwKICAgIHsgaW5kZXg6IG51bSgiTm9tb3IgdGFiLCAtMSA9IHRlcmJhcnUiKSwgbWF0Y2g6IHN0cigiU2ViYWdpYW4g
::B64:agent.js:anVkdWwgYXRhdSBVUkwgdGFiIikgfSwKICAgIFsiaW5kZXgiLCAibWF0Y2giXQogICksCiAgZm4oImNsb3NlX3RhYiIsICJUdXR1cCB0YWIgKGJhd2FhbjogdGFiIGFrdGlmKSwgYXRhdSB0YWIgZGVuZ2FuIG5vbW9yIHRlcnRlbnR1IiwgeyBpbmRleDogbnVtKCJO
::B64:agent.js:b21vciB0YWIsIC0xID0gdGVyYmFydSIpIH0sIFsiaW5kZXgiXSksCiAgZm4oImluc3BlY3RfcGFnZSIsICJEYWZ0YXIgdG9tYm9sL2lucHV0IGRpIGhhbGFtYW4gYnJvd3NlciB1bnR1ayBtZW5jYXJpIENTUyBzZWxlY3RvciIpLAogIGZuKAogICAgInlvdXR1YmVf
::B64:agent.js:cGxheSIsCiAgICAiQ2FyaSB2aWRlbyBkaSBZb3VUdWJlIGxhbHUgT1RPTUFUSVMgbWVtdXRhciBoYXNpbCBwaWxpaGFuIGRpIGJyb3dzZXIgYWdlbnQuIFBha2FpIGluaSB1bnR1ayBzZW11YSBwZXJtaW50YWFuIG5vbnRvbi9jYXJpIHZpZGVvL2xhZ3UgZGkgWW91
::B64:agent.js:VHViZS4iLAogICAgewogICAgICBxdWVyeTogc3RyKCJLYXRhIGt1bmNpIHBlbmNhcmlhbiIpLAogICAgICBwaWNrOiBudW0oIlVydXRhbiBoYXNpbCB5YW5nIGRpcHV0YXIsIDEtNSAoZGVmYXVsdCAxKSIpLAogICAgICBuZXdfdGFiOiBib29sKCJ0cnVlID0gcHV0
::B64:agent.js:YXIgZGkgdGFiIGJhcnUgc3VwYXlhIHRhYiBha3RpZiB0aWRhayB0ZXJ0aW1wYSIpLAogICAgfSwKICAgIFsicGljayIsICJuZXdfdGFiIl0KICApLAogIGZuKCJkb25lIiwgIlBhbmdnaWwgaW5pIGppa2EgdHVnYXMgU0VMRVNBSSwgYXRhdSBqaWthIHBlcmx1IGJl
::B64:agent.js:cnRhbnlhL21lbGFwb3Iga2UgdXNlciIsIHsgbWVzc2FnZTogc3RyKCJQZXNhbiBzaW5na2F0IHVudHVrIHVzZXIiKSB9KSwKICBmbigKICAgICJ5b3V0dWJlX2NvbnRyb2wiLAogICAgIktvbnRyb2wgdmlkZW8gWW91VHViZSB5YW5nIHNlZGFuZyB0ZXJidWthIiwK
::B64:agent.js:ICAgIHsgYWN0aW9uOiBzdHIoInBsYXksIHBhdXNlLCB0b2dnbGUsIG11dGUsIHVubXV0ZSwgZm9yd2FyZCwgYmFja3dhcmQsIG5leHQsIHByZXZpb3VzLCBmdWxsc2NyZWVuIiksIHNlY29uZHM6IG51bSgiRGV0aWsgdW50dWsgZm9yd2FyZC9iYWNrd2FyZCAoZGVm
::B64:agent.js:YXVsdCAxMCkiKSB9LAogICAgWyJzZWNvbmRzIl0KICApLAogIGZuKCJ3ZWJfc2VhcmNoIiwgIkNhcmkgaW5mb3JtYXNpIGRpIGludGVybmV0LCBtZW5nZW1iYWxpa2FuIGp1ZHVsLCBsaW5rLCBkYW4gY3VwbGlrYW4gaGFzaWwiLCB7CiAgICBxdWVyeTogc3RyKCJL
::B64:agent.js:YXRhIGt1bmNpIiksCiAgICBuZXdfdGFiOiBib29sKCJ0cnVlID0gY2FyaSBkaSB0YWIgYmFydSBzdXBheWEgdGFiIGFrdGlmIHRpZGFrIHRlcnRpbXBhIiksCiAgfSwgWyJuZXdfdGFiIl0pLAogIGZuKCJzY3JvbGxfcGFnZSIsICJTY3JvbGwgaGFsYW1hbiBicm93
::B64:agent.js:c2VyLiBQb3NpdGlmID0gdHVydW4sIG5lZ2F0aWYgPSBuYWlrIiwgeyBhbW91bnQ6IG51bSgiSnVtbGFoIHNjcm9sbCIpIH0pLAogIGZuKCJ3YWl0X2Zvcl91c2VyIiwgIkJlcmhlbnRpIGRhbiBtaW50YSB1c2VyIG1lbGFrdWthbiBzZXN1YXR1IHNlbmRpcmkgKGxv
::B64:agent.js:Z2luLCBjYXB0Y2hhLCB2ZXJpZmlrYXNpKSwgbGFsdSB0dW5nZ3UgRW50ZXIiLCB7IG1lc3NhZ2U6IHN0cigiSW5zdHJ1a3NpIHVudHVrIHVzZXIiKSB9KSwKICBmbigiZG93bmxvYWRfZmlsZSIsICJVbmR1aCBmaWxlIGRhcmkgaW50ZXJuZXQga2UgZm9sZGVyIERv
::B64:agent.js:d25sb2FkcyIsIHsgdXJsOiBzdHIoIlVSTCBodHRwKHMpIiksIGZpbGVuYW1lOiBzdHIoIk5hbWEgZmlsZSAob3BzaW9uYWwpIikgfSwgWyJmaWxlbmFtZSJdKSwKICBmbigibm93IiwgIlRhbmdnYWwgZGFuIGphbSBzZWthcmFuZyIpLAogIGZuKCJzeXN0ZW1faW5m
::B64:agent.js:byIsICJJbmZvIFBDOiBPUywgQ1BVLCBSQU0sIGJhdGVyYWksIHJ1YW5nIGRpc2siKSwKICBmbigKICAgICJtZWRpYV9rZXkiLAogICAgIlRvbWJvbCBtZWRpYSBkYW4gdm9sdW1lIGdsb2JhbCBXaW5kb3dzIiwKICAgIHsga2V5OiBzdHIoInZvbHVwLCB2b2xkb3du
::B64:agent.js:LCBtdXRlLCBwbGF5cGF1c2UsIG5leHQsIHByZXYiKSwgdGltZXM6IG51bSgiSnVtbGFoIHRla2FuICh2b2x1bWUgYmVydWJhaCAyJSBwZXIgdGVrYW4pIikgfSwKICAgIFsidGltZXMiXQogICksCiAgZm4oImNsaXBib2FyZF9nZXQiLCAiQmFjYSBpc2kgY2xpcGJv
::B64:agent.js:YXJkIiksCiAgZm4oImNsaXBib2FyZF9zZXQiLCAiSXNpIGNsaXBib2FyZCIsIHsgdGV4dDogc3RyKCJUZWtzIikgfSksCiAgZm4oImxpc3Rfd2luZG93cyIsICJEYWZ0YXIgamVuZGVsYSBhdGF1IGFwbGlrYXNpIHlhbmcgc2VkYW5nIHRlcmJ1a2EiKSwKICBmbigi
::B64:agent.js:Zm9jdXNfd2luZG93IiwgIlBpbmRhaGthbiBmb2t1cyBrZSBzZWJ1YWggamVuZGVsYSIsIHsgdGl0bGU6IHN0cigiU2ViYWdpYW4ganVkdWwgamVuZGVsYSIpIH0pLAogIGZuKCJjbG9zZV93aW5kb3ciLCAiVHV0dXAgc2VidWFoIGplbmRlbGEgZGVuZ2FuIGJhaWst
::B64:agent.js:YmFpayIsIHsgdGl0bGU6IHN0cigiU2ViYWdpYW4ganVkdWwgamVuZGVsYSIpIH0pLAogIGZuKCJyZWFkX3RleHRfZmlsZSIsICJCYWNhIGlzaSBmaWxlIHRla3MiLCB7IHBhdGg6IHN0cigiUGF0aCBsZW5na2FwIGZpbGUiKSB9KSwKICBmbigid3JpdGVfdGV4dF9m
::B64:agent.js:aWxlIiwgIlR1bGlzIGF0YXUgdGFtYmFoIGlzaSBmaWxlIHRla3MiLCB7IHBhdGg6IHN0cigiUGF0aCBsZW5na2FwIGZpbGUiKSwgY29udGVudDogc3RyKCJJc2kiKSwgYXBwZW5kOiB7IHR5cGU6ICJib29sZWFuIiwgZGVzY3JpcHRpb246ICJ0cnVlID0gdGFtYmFo
::B64:agent.js:a2FuLCBidWthbiBtZW5pbXBhIiB9IH0sIFsiYXBwZW5kIl0pLAogIGZuKCJtYWtlX2ZvbGRlciIsICJCdWF0IGZvbGRlciBiYXJ1IiwgeyBwYXRoOiBzdHIoIlBhdGggbGVuZ2thcCBmb2xkZXIiKSB9KSwKICBmbigibW92ZV9wYXRoIiwgIlBpbmRhaGthbiBhdGF1
::B64:agent.js:IGdhbnRpIG5hbWEgZmlsZS9mb2xkZXIiLCB7IGZyb206IHN0cigiUGF0aCBhc2FsIiksIHRvOiBzdHIoIlBhdGggdHVqdWFuIikgfSksCiAgZm4oInJlY3ljbGVfcGF0aCIsICJIYXB1cyBmaWxlL2ZvbGRlciBkZW5nYW4gbWVtaW5kYWhrYW5ueWEga2UgUmVjeWNs
::B64:agent.js:ZSBCaW4iLCB7IHBhdGg6IHN0cigiUGF0aCBsZW5na2FwIikgfSksCiAgZm4oInppcF9wYXRoIiwgIktvbXByZXMgZmlsZSBhdGF1IGZvbGRlciBtZW5qYWRpIC56aXAiLCB7IHNvdXJjZTogc3RyKCJQYXRoIGZpbGUvZm9sZGVyIiksIHppcDogc3RyKCJQYXRoIGZp
::B64:agent.js:bGUgLnppcCBoYXNpbCIpIH0pLAogIGZuKCJ1bnppcF9wYXRoIiwgIkVrc3RyYWsgZmlsZSAuemlwIiwgeyB6aXA6IHN0cigiUGF0aCBmaWxlIC56aXAiKSwgZm9sZGVyOiBzdHIoIkZvbGRlciB0dWp1YW4iKSB9KSwKICBmbigibW9yZV90b29scyIsICJBa3RpZmth
::B64:agent.js:biBrZWxvbXBvayBhbGF0IHRhbWJhaGFuIGppa2EgYWxhdCB5YW5nIGthbXUgYnV0dWhrYW4gYmVsdW0gdGVyc2VkaWEiLCB7CiAgICBncm91cDogc3RyKCJ5b3V0dWJlLCB0YWJzLCBkZXNrdG9wLCBmaWxlcywgYXRhdSBwYyIpLAogIH0pLAogIGZuKCJnZXRfcGFn
::B64:agent.js:ZV90ZXh0IiwgIkJhY2EgdGVrcyBoYWxhbWFuIGJyb3dzZXIgc2FhdCBpbmkiKSwKICBmbigidHlwZV90ZXh0IiwgIklzaSBrb2xvbSB0ZWtzIGRpIGJyb3dzZXIiLCB7IHNlbGVjdG9yOiBzdHIoIkNTUyBzZWxlY3RvciIpLCB0ZXh0OiBzdHIoIlRla3MiKSB9KSwK
::B64:agent.js:ICBmbigiY2xpY2siLCAiS2xpayBlbGVtZW4gZGkgYnJvd3NlciIsIHsgc2VsZWN0b3I6IHN0cigiQ1NTIHNlbGVjdG9yIikgfSksCiAgZm4oCiAgICAidXBsb2FkX2ZpbGUiLAogICAgIlVwbG9hZCBTQVRVIGF0YXUgQkFOWUFLIGZpbGUga2UgaW5wdXQgZmlsZSBk
::B64:agent.js:aSBicm93c2VyLiBCZWJlcmFwYSBmaWxlIGRpIGZpbGVuYW1lIGRpcGlzYWggdGFuZGEgfC4gQXRhdSBwYWthaSBmb2xkZXIgKCsgcGF0dGVybikgdW50dWsgbWVuZ3VuZ2dhaCBzZW11YSBmaWxlIGRpIGZvbGRlciBpdHUiLAogICAgewogICAgICBzZWxlY3Rvcjog
::B64:agent.js:c3RyKCJDU1Mgc2VsZWN0b3IgaW5wdXRbdHlwZT1maWxlXSIpLAogICAgICBmaWxlbmFtZTogc3RyKCJQYXRoIGxlbmdrYXAgZmlsZSAoYm9sZWggYmFueWFrLCBkaXBpc2FoIHwpLCBhdGF1IG5hbWEgZmlsZSBkaSB1cGxvYWQtZm9sZGVyIiksCiAgICAgIGZvbGRl
::B64:agent.js:cjogc3RyKCJGb2xkZXIgYmVyaXNpIGZpbGUgeWFuZyBtYXUgZGl1cGxvYWQgc2VtdWFueWEgKG9wc2lvbmFsKSIpLAogICAgICBwYXR0ZXJuOiBzdHIoIkZpbHRlciBuYW1hIGZpbGUgZGkgZm9sZGVyLCBtaXNhbG55YSAucGRmIChvcHNpb25hbCkiKSwKICAgIH0s
::B64:agent.js:CiAgICBbImZpbGVuYW1lIiwgImZvbGRlciIsICJwYXR0ZXJuIl0KICApLApdOwoKY29uc3QgU1lTVEVNID0gYEthbXUgYWdlbnQgeWFuZyBtZW5nb250cm9sIFBDIFdpbmRvd3MgbWlsaWsgdXNlciBkYW4gYnJvd3Nlci4gS2VyamFrYW4gcGVyaW50YWggdXNlciBk
::B64:agent.js:ZW5nYW4gbWVtYW5nZ2lsIHRvb2wuCkFUVVJBTiBQRU5USU5HOgotIEthbXUgSEFSVVMgc2VsYWx1IG1lbWFuZ2dpbCB0b29sIGRpIHNldGlhcCBsYW5na2FoLiBKQU5HQU4gcGVybmFoIG1lbnVsaXMgcmVuY2FuYSwgbmFyYXNpLCBhdGF1ICJzYXlhIGFrYW4gLi4u
::B64:agent.js:Ii4gTGFuZ3N1bmcgcGFuZ2dpbCB0b29sLW55YS4KLSBTZXRlbGFoIHR1Z2FzIHNlbGVzYWkgKGF0YXUgcGVybHUgYmVydGFueWEga2UgdXNlciksIHBhbmdnaWwgdG9vbCBkb25lIGRlbmdhbiBwZXNhbiBzaW5na2F0LgotIE5vbnRvbi9jYXJpIHZpZGVvL2xhZ3Ug
::B64:agent.js:ZGkgWW91VHViZTogbGFuZ3N1bmcgcGFuZ2dpbCB5b3V0dWJlX3BsYXkgZGVuZ2FuIGthdGEga3VuY2kgZGFyaSB1c2VyLiBKaWthIGp1ZHVsIHlhbmcgZGlwdXRhciBrdXJhbmcgY29jb2ssIHBhbmdnaWwgbGFnaSBkZW5nYW4gcGljayBsYWluLgotIFRhZnNpcmth
::B64:agent.js:biBwZXJpbnRhaCBzaW5na2F0L3R5cG8gdXNlciBkZW5nYW4gd2FqYXIsIGphbmdhbiBiZXJ0YW55YSBoYWwgeWFuZyBiaXNhIGRpdGViYWsuCi0gS2FtdSBtZW5naW5nYXQgcGVyY2FrYXBhbiBzZWJlbHVtbnlhLiBKYXdhYmFuIHNpbmdrYXQgdXNlciAobWlzYWxu
::B64:agent.js:eWEgc2VidWFoIG5hbWEgZmlsZSkgYWRhbGFoIGphd2FiYW4gYXRhcyBwZXJ0YW55YWFubXUgc2ViZWx1bW55YTsgbGFuanV0a2FuIHR1Z2FzIGl0dSwgamFuZ2FuIG11bGFpIGRhcmkgbm9sLgotIE1lbWJ1a2EgYXBsaWthc2kgV2luZG93cyBsZXdhdCBvcGVuX3Bh
::B64:agent.js:dGg6IGthbWVyYSA9IG1pY3Jvc29mdC53aW5kb3dzLmNhbWVyYTogLCBrYWxrdWxhdG9yID0gY2FsYyAsIG5vdGVwYWQgPSBub3RlcGFkICwgcGFpbnQgPSBtc3BhaW50ICwgcGVuZ2F0dXJhbiA9IG1zLXNldHRpbmdzOiAsIGZpbGUgZXhwbG9yZXIgPSBleHBsb3Jl
::B64:agent.js:ciAuCi0gVXBsb2FkIGZpbGUga2Ugd2Vic2l0ZTogb3Blbl91cmwga2UgaGFsYW1hbiB1cGxvYWQsIGluc3BlY3RfcGFnZSB1bnR1ayBtZW5jYXJpIGlucHV0IHR5cGU9ZmlsZSwgbGFsdSB1cGxvYWRfZmlsZSBkZW5nYW4gcGF0aCBsZW5na2FwIGZpbGUuIEppa2Eg
::B64:agent.js:YnV0dWggbG9naW4sIHBhbmdnaWwgZG9uZSBkYW4gbWludGEgdXNlciBsb2dpbiBtYW51YWwgZGkgamVuZGVsYSBicm93c2VyLCBsYWx1IHVsYW5naS4KLSBGb2xkZXIgZGkgUEM6IGZpbmRfZm9sZGVyIGxhbHUgb3Blbl9wYXRoLiBGaWxlIGRpIFBDOiBmaW5kX2Zp
::B64:agent.js:bGUgKGF0YXUgbGlzdF9kaXIpIHVudHVrIG1lbmRhcGF0IHBhdGggbGVuZ2thcCwgbGFsdSBvcGVuX3BhdGggYXRhdSB1cGxvYWRfZmlsZS4gVGlkYWsgYWRhIGJhdGFzYW4gbG9rYXNpLCBzZW11YSBkcml2ZSBib2xlaCBkaWFrc2VzLgotIEFwbGlrYXNpL2plbmRl
::B64:agent.js:bGEgZGkgUEM6IHNjcmVlbnNob3QgZHVsdSB1bnR1ayBtZWxpaGF0IGxheWFyLCBsYWx1IGNsaWNrX3NjcmVlbi90eXBlX2Rlc2t0b3AvcHJlc3Nfa2V5cywgbGFsdSBzY3JlZW5zaG90IGxhZ2kgdW50dWsgbWVtZXJpa3NhIGhhc2lsLgotIEtvb3JkaW5hdCBrbGlr
::B64:agent.js:IGhhcnVzIGRhcmkgc2NyZWVuc2hvdCB0ZXJha2hpci4KLSBVbnR1ayBvdG9tYXNpIHdlYnNpdGUgcGFrYWkgdG9vbCBicm93c2VyIChvcGVuX3VybCwgaW5zcGVjdF9wYWdlLCB0eXBlX3RleHQsIGNsaWNrLCB1cGxvYWRfZmlsZSkuIFNlbGFsdSBpbnNwZWN0X3Bh
::B64:agent.js:Z2Ugc2ViZWx1bSBrbGlrLgotIEJ1dHVoIGxvZ2luLCBjYXB0Y2hhLCBhdGF1IHZlcmlmaWthc2k6IHBhbmdnaWwgd2FpdF9mb3JfdXNlciBkYW4gbWludGEgdXNlciBtZW5nZXJqYWthbm55YSBzZW5kaXJpIGRpIGplbmRlbGEgYnJvd3Nlci4gSkFOR0FOIHBlcm5h
::B64:agent.js:aCBtZW1pbnRhIGF0YXUgbWVuZ2V0aWtrYW4gcGFzc3dvcmQgdXNlci4KLSBQZXJ0YW55YWFuIHlhbmcgYnV0dWggaW5mbyB0ZXJiYXJ1OiB3ZWJfc2VhcmNoLCBsYWx1IG9wZW5fdXJsIGRhbiBnZXRfcGFnZV90ZXh0IHVudHVrIG1lbWJhY2Egc3VtYmVybnlhLgot
::B64:agent.js:IEtvbnRyb2wgbXVzaWsvdmlkZW86IHlvdXR1YmVfY29udHJvbCB1bnR1ayB2aWRlbyBZb3VUdWJlLCBtZWRpYV9rZXkgdW50dWsgdm9sdW1lIGRhbiB0b21ib2wgbWVkaWEgc2VsdXJ1aCBQQy4KLSBUQUI6IEphbmdhbiBtZW5pbXBhIGhhbGFtYW4geWFuZyBtYXNp
::B64:agent.js:aCBkaXBha2FpLiBKaWthIHVzZXIgbWVueWVidXQgInRhYiBiYXJ1IiwgYXRhdSBhZGEgdmlkZW8vaGFsYW1hbiBsYWluIHlhbmcgc2VkYW5nIHRlcmJ1a2EgKG1pc2FsbnlhIG11c2lrKSwgcGFrYWkgbmV3X3RhYj10cnVlIHBhZGEgb3Blbl91cmwsIHdlYl9zZWFy
::B64:agent.js:Y2gsIGF0YXUgeW91dHViZV9wbGF5LiBCZWJlcmFwYSBzaXR1cyBzZWthbGlndXM6IG9wZW5fdXJscy4gUGluZGFoIHRhYjogbGlzdF90YWJzIGxhbHUgc3dpdGNoX3RhYiAoaW5kZXggLTEgPSB0YWIgdGVyYmFydSwgYXRhdSBtYXRjaCBqdWR1bCkuIFR1dHVwOiBj
::B64:agent.js:bG9zZV90YWIuCi0gVXBsb2FkIGJhbnlhayBmaWxlOiB1cGxvYWRfZmlsZSBkZW5nYW4gYmViZXJhcGEgcGF0aCBkaXBpc2FoIHwsIGF0YXUgZm9sZGVyIChkYW4gcGF0dGVybikuIEppa2EgaW5wdXQgaGFueWEgbWVuZXJpbWEgc2F0dSBmaWxlLCB1bGFuZ2kgcGVy
::B64:agent.js:IGZpbGUgc2FtcGFpIHNlbXVhIHNlbGVzYWkuCi0gTWVuZ2hhcHVzIGZpbGU6IHBha2FpIHJlY3ljbGVfcGF0aCAobWFzdWsgUmVjeWNsZSBCaW4pLCBqYW5nYW4gbWVuZ2hhcHVzIHBlcm1hbmVuLgotIEppa2EgYWxhdCB5YW5nIGthbXUgYnV0dWhrYW4gdGlkYWsg
::B64:agent.js:YWRhIGRpIGRhZnRhciwgcGFuZ2dpbCBtb3JlX3Rvb2xzIGRlbmdhbiBncnVwOiB5b3V0dWJlLCB0YWJzLCBkZXNrdG9wLCBmaWxlcywgYXRhdSBwYy4KLSBKaWthIGJ1bnR1IGF0YXUgcmFndSwgYmVyaGVudGkgZGFuIHRhbnlhIHVzZXIuCi0gSmF3YWIgZGFsYW0g
::B64:agent.js:QmFoYXNhIEluZG9uZXNpYSwgc2luZ2thdC4gSmFuZ2FuIG1lbmdhcmFuZyBoYXNpbDsgbGFwb3JrYW4gYXBhIGFkYW55YS5gOwoKLy8gPT09PT0gS29tdW5pa2FzaSBkZW5nYW4gOVJvdXRlciAodGFoYW4gYmFudGluZykgPT09PT0KLy8gSmlrYSBiYWxhc2FuIGtv
::B64:agent.js:c29uZy9nYWdhbCwgYWdlbnQgb3RvbWF0aXM6ICgxKSBjb2JhIHRhbnBhIHRvb2xfY2hvaWNlLCAoMikga2VjaWxrYW4gZGFmdGFyIGFsYXQgZGFuCi8vIHBha2FpIGJhbGFzYW4gbm9uLXN0cmVhbWluZywgKDMpIHBpbmRhaCBrZSBtb2RlbCBsYWluIHlhbmcgZGl0
::B64:agent.js:ZW11a2FuIGxld2F0IC9tb2RlbHMuCi8vIE1vZGVsIHlhbmcgYmVyaGFzaWwgZGlpbmdhdCBzZWxhbWEgc2VzaS4gUGVyaW50YWggL3RlcyBkYW4gL21vZGVsIG1lbWJhbnR1IG1lbWlsaWggbW9kZWwgcGFsaW5nIHN0YWJpbC4KY29uc3QgTU9ERUxfRklMRSA9ICJt
::B64:agent.js:b2RlbC50eHQiOwpsZXQgYmFzZU1vZGVsID0gTU9ERUw7CnRyeSB7CiAgY29uc3Qgc2F2ZWQgPSBmcy5yZWFkRmlsZVN5bmMoTU9ERUxfRklMRSwgInV0ZjgiKS50cmltKCk7CiAgaWYgKHNhdmVkKSBiYXNlTW9kZWwgPSBzYXZlZDsKfSBjYXRjaCB7fQoKbGV0IHVz
::B64:agent.js:ZVRvb2xDaG9pY2UgPSB0cnVlOyAvLyBwYWtzYSBtb2RlbCBzZWxhbHUgbWVtYW5nZ2lsIHRvb2w7IGRpbWF0aWthbiBvdG9tYXRpcyBqaWthIGJlcm1hc2FsYWgKbGV0IHNsaW1Nb2RlID0gZmFsc2U7IC8vIHRydWUgPSBraXJpbSBoYW55YSBhbGF0IHlhbmcgcmVs
::B64:agent.js:ZXZhbiAobXVhdGFuIGxlYmloIGtlY2lsKQpsZXQgZmFsbGJhY2tNb2RlbHMgPSBudWxsOyAvLyBkaWlzaSBzYWF0IHBlcnRhbWEga2FsaSBkaWJ1dHVoa2FuCmxldCBwb29sSWR4ID0gMDsKY29uc3QgZXh0cmFHcm91cHMgPSBuZXcgU2V0KCk7CmNvbnN0IEJBQ0tP
::B64:agent.js:RkYgPSBOdW1iZXIocHJvY2Vzcy5lbnYuQkFDS09GRl9NUyB8fCAxMDAwKTsKCmNvbnN0IFRPT0xfR1JPVVBTID0gewogIHlvdXR1YmU6IFsieW91dHViZV9wbGF5IiwgInlvdXR1YmVfY29udHJvbCJdLAogIHRhYnM6IFsibmV3X3RhYiIsICJvcGVuX3VybHMiLCAi
::B64:agent.js:bGlzdF90YWJzIiwgInN3aXRjaF90YWIiLCAiY2xvc2VfdGFiIiwgInNjcm9sbF9wYWdlIiwgIndlYl9zZWFyY2giXSwKICBkZXNrdG9wOiBbImNsaWNrX3NjcmVlbiIsICJzY3JvbGxfc2NyZWVuIiwgInR5cGVfZGVza3RvcCIsICJwcmVzc19rZXlzIiwgIndhaXQi
::B64:agent.js:LCAibGlzdF93aW5kb3dzIiwgImZvY3VzX3dpbmRvdyIsICJjbG9zZV93aW5kb3ciXSwKICBmaWxlczogWyJyZWFkX3RleHRfZmlsZSIsICJ3cml0ZV90ZXh0X2ZpbGUiLCAibWFrZV9mb2xkZXIiLCAibW92ZV9wYXRoIiwgInJlY3ljbGVfcGF0aCIsICJ6aXBfcGF0
::B64:agent.js:aCIsICJ1bnppcF9wYXRoIiwgImRvd25sb2FkX2ZpbGUiXSwKICBwYzogWyJtZWRpYV9rZXkiLCAiY2xpcGJvYXJkX2dldCIsICJjbGlwYm9hcmRfc2V0IiwgInN5c3RlbV9pbmZvIl0sCn07CmNvbnN0IENPUkVfVE9PTFMgPSBbCiAgImRvbmUiLCAid2FpdF9mb3Jf
::B64:agent.js:dXNlciIsICJtb3JlX3Rvb2xzIiwgIm5vdyIsICJvcGVuX3VybCIsICJnZXRfcGFnZV90ZXh0IiwgImluc3BlY3RfcGFnZSIsICJ0eXBlX3RleHQiLCAiY2xpY2siLAogICJ1cGxvYWRfZmlsZSIsICJsaXN0X2ZpbGVzIiwgImZpbmRfZm9sZGVyIiwgImZpbmRfZmls
::B64:agent.js:ZSIsICJsaXN0X2RpciIsICJvcGVuX3BhdGgiLCAic2NyZWVuc2hvdCIsCl07CmNvbnN0IEdST1VQX0tFWVdPUkRTID0gewogIHlvdXR1YmU6IC95b3V0dWJlfHZpZGVvfGxhZ3V8bXVzaWt8bXVzaWN8cHV0YXJ8bm9udG9ufGRlbmdhcnxwYXVzZXxuZXh0L2ksCiAg
::B64:agent.js:dGFiczogL1xidGFiXGJ8Y2FyaXxzZWFyY2h8Z29vZ2xlfHdlYnxpbnRlcm5ldHxzaXR1c3x3ZWJzaXRlfHNla2FsaWd1cy9pLAogIGRlc2t0b3A6IC9rbGlrfGxheWFyfG1vdXNlfGtldGlrfGplbmRlbGF8d2luZG93fGFwbGlrYXNpfHNjcmVlbnNob3R8c2Nyb2xs
::B64:agent.js:fHRvbWJvbC9pLAogIGZpbGVzOiAvZmlsZXxmb2xkZXJ8emlwfGhhcHVzfHBpbmRhaHx0dWxpc3xiYWNhfHVuZHVofGRvd25sb2FkfGJ1YXR8Z2FudGkgbmFtYS9pLAogIHBjOiAvdm9sdW1lfHN1YXJhfGNsaXBib2FyZHxzYWxpbnxcYnJhbVxifGNwdXxiYXRlcmFp
::B64:agent.js:fHNpc3RlbXxtZWRpYXxtdXRlL2ksCn07CgovLyBQaWxpaCBhbGF0IHlhbmcgcmVsZXZhbiBzYWphIChkaXBha2FpIHNhYXQgbXVhdGFuIHBlcmx1IGRpa2VjaWxrYW4pCmZ1bmN0aW9uIHNlbGVjdFRvb2xzKG1lc3NhZ2VzKSB7CiAgY29uc3QgbmFtZXMgPSBuZXcg
::B64:agent.js:U2V0KENPUkVfVE9PTFMpOwogIGNvbnN0IHVzZXJUZXh0ID0gbWVzc2FnZXMKICAgIC5maWx0ZXIoKG0pID0+IG0ucm9sZSA9PT0gInVzZXIiICYmIHR5cGVvZiBtLmNvbnRlbnQgPT09ICJzdHJpbmciICYmICFtLmNvbnRlbnQuc3RhcnRzV2l0aCgiS2FtdSBoYXJ1
::B64:agent.js:cyBtZW1hbmdnaWwgdG9vbCIpKQogICAgLnNsaWNlKC00KQogICAgLm1hcCgobSkgPT4gbS5jb250ZW50KQogICAgLmpvaW4oIiAiKTsKICBmb3IgKGNvbnN0IFtnLCByZV0gb2YgT2JqZWN0LmVudHJpZXMoR1JPVVBfS0VZV09SRFMpKSB7CiAgICBpZiAocmUudGVz
::B64:agent.js:dCh1c2VyVGV4dCkgfHwgZXh0cmFHcm91cHMuaGFzKGcpKSBUT09MX0dST1VQU1tnXS5mb3JFYWNoKChuKSA9PiBuYW1lcy5hZGQobikpOwogIH0KICBmb3IgKGNvbnN0IG0gb2YgbWVzc2FnZXMpIGZvciAoY29uc3QgYyBvZiBtLnRvb2xfY2FsbHMgfHwgW10pIG5h
::B64:agent.js:bWVzLmFkZChjLmZ1bmN0aW9uLm5hbWUpOyAvLyBhbGF0IHlhbmcgc3VkYWggZGlwYWthaSB0ZXRhcCBhZGEKICByZXR1cm4gdG9vbHMuZmlsdGVyKCh0KSA9PiBuYW1lcy5oYXModC5mdW5jdGlvbi5uYW1lKSk7Cn0KCmNvbnN0IG1vZGVsUG9vbCA9ICgpID0+IFti
::B64:agent.js:YXNlTW9kZWwsIC4uLihmYWxsYmFja01vZGVscyB8fCBbXSkuZmlsdGVyKChtKSA9PiBtICE9PSBiYXNlTW9kZWwpXTsKCmFzeW5jIGZ1bmN0aW9uIGRpc2NvdmVyTW9kZWxzKCkgewogIGlmIChwcm9jZXNzLmVudi5ST1VURVJfRkFMTEJBQ0tfTU9ERUxTKSB7CiAg
::B64:agent.js:ICByZXR1cm4gcHJvY2Vzcy5lbnYuUk9VVEVSX0ZBTExCQUNLX01PREVMUy5zcGxpdCgiLCIpLm1hcCgoeCkgPT4geC50cmltKCkpLmZpbHRlcihCb29sZWFuKTsKICB9CiAgdHJ5IHsKICAgIGNvbnN0IHJlcyA9IGF3YWl0IGZldGNoKGAke0JBU0VfVVJMfS9tb2Rl
::B64:agent.js:bHNgLCB7CiAgICAgIGhlYWRlcnM6IHsgQXV0aG9yaXphdGlvbjogYEJlYXJlciAke0FQSV9LRVl9YCB9LAogICAgICBzaWduYWw6IEFib3J0U2lnbmFsLnRpbWVvdXQoMTAwMDApLAogICAgfSk7CiAgICBpZiAoIXJlcy5vaykgcmV0dXJuIFtdOwogICAgY29uc3Qg
::B64:agent.js:ZGF0YSA9IChhd2FpdCByZXMuanNvbigpKS5kYXRhIHx8IFtdOwogICAgY29uc3QgYmFkID0gL2VtYmVkfHdoaXNwZXJ8dHRzfGltYWdlfGF1ZGlvfHJlcmFua3xtb2RlcmF0fGRhbGx8Zmx1eHxzZHhsfHZpZGVvfHNwZWVjaHx0cmFuc2NyaS9pOwogICAgY29uc3Qg
::B64:agent.js:c2NvcmUgPSAoaWQpID0+CiAgICAgICgvY2xhdWRlL2kudGVzdChpZCkgPyAzIDogMCkgKyAoL2dlbWluaS9pLnRlc3QoaWQpID8gMyA6IDApICsgKC9ncHR8Z2xtfHF3ZW58a2ltaXxkZWVwc2Vlay9pLnRlc3QoaWQpID8gMiA6IDApICsKICAgICAgKC9oYWlrdXxm
::B64:agent.js:bGFzaHxzb25uZXQvaS50ZXN0KGlkKSA/IDEgOiAwKSAtICgvdGhpbmtpbmd8YWdlbnRpYy9pLnRlc3QoaWQpID8gMiA6IDApOwogICAgcmV0dXJuIGRhdGEKICAgICAgLm1hcCgobSkgPT4gbS5pZCkKICAgICAgLmZpbHRlcigoaWQpID0+IGlkICYmIGlkICE9PSBi
::B64:agent.js:YXNlTW9kZWwgJiYgIWJhZC50ZXN0KGlkKSkKICAgICAgLnNvcnQoKHgsIHkpID0+IHNjb3JlKHkpIC0gc2NvcmUoeCkpCiAgICAgIC5zbGljZSgwLCA4KTsKICB9IGNhdGNoIHsKICAgIHJldHVybiBbXTsKICB9Cn0KCmZ1bmN0aW9uIGZhdGFsKG1zZykgewogIGNv
::B64:agent.js:bnN0IGUgPSBuZXcgRXJyb3IobXNnKTsKICBlLmZhdGFsID0gdHJ1ZTsKICByZXR1cm4gZTsKfQoKLy8gQmFjYSBiYWxhc2FuIDlSb3V0ZXIgKEpTT04gYmlhc2EgYXRhdSBzdHJlYW1pbmcgU1NFKSBtZW5qYWRpIHNhdHUgcGVzYW4KZnVuY3Rpb24gcGFyc2VDaGF0
::B64:agent.js:KHJhdykgewogIGlmICghcmF3LnRyaW0oKSkgcmV0dXJuIHsgbXNnOiBudWxsLCBlcnI6ICJrb3NvbmciIH07CiAgaWYgKCEvKF58XG4pZGF0YTovLnRlc3QocmF3KSkgewogICAgbGV0IG9iajsKICAgIHRyeSB7CiAgICAgIG9iaiA9IEpTT04ucGFyc2UocmF3KTsK
::B64:agent.js:ICAgIH0gY2F0Y2ggewogICAgICByZXR1cm4geyBtc2c6IG51bGwsIGVycjogImJ1a2FuIEpTT04iIH07CiAgICB9CiAgICBpZiAob2JqLmVycm9yKSByZXR1cm4geyBtc2c6IG51bGwsIGVycjogSlNPTi5zdHJpbmdpZnkob2JqLmVycm9yKS5zbGljZSgwLCAxNTAp
::B64:agent.js:IH07CiAgICBjb25zdCBtID0gb2JqLmNob2ljZXM/LlswXT8ubWVzc2FnZTsKICAgIGlmICghbSB8fCAoIW0uY29udGVudCAmJiAhbS50b29sX2NhbGxzPy5sZW5ndGgpKSByZXR1cm4geyBtc2c6IG51bGwsIGVycjogInRhbnBhIGlzaSIgfTsKICAgIHJldHVybiB7
::B64:agent.js:IG1zZzogbSwgZXJyOiAiIiB9OwogIH0KICBsZXQgY29udGVudCA9ICIiOwogIGxldCBzc2VFcnIgPSAiIjsKICBjb25zdCBjYWxscyA9IFtdOwogIGZvciAoY29uc3QgbGluZSBvZiByYXcuc3BsaXQoIlxuIikpIHsKICAgIGlmICghbGluZS5zdGFydHNXaXRoKCJk
::B64:agent.js:YXRhOiIpKSBjb250aW51ZTsKICAgIGNvbnN0IGRhdGEgPSBsaW5lLnNsaWNlKDUpLnRyaW0oKTsKICAgIGlmICghZGF0YSB8fCBkYXRhID09PSAiW0RPTkVdIikgY29udGludWU7CiAgICBsZXQgY2h1bms7CiAgICB0cnkgewogICAgICBjaHVuayA9IEpTT04ucGFy
::B64:agent.js:c2UoZGF0YSk7CiAgICB9IGNhdGNoIHsKICAgICAgY29udGludWU7CiAgICB9CiAgICBpZiAoY2h1bmsuZXJyb3IpIHNzZUVyciA9IEpTT04uc3RyaW5naWZ5KGNodW5rLmVycm9yKS5zbGljZSgwLCAxNTApOwogICAgY29uc3QgY2hvaWNlID0gY2h1bmsuY2hvaWNl
::B64:agent.js:cz8uWzBdOwogICAgY29uc3QgZGVsdGEgPSBjaG9pY2U/LmRlbHRhIHx8IGNob2ljZT8ubWVzc2FnZSB8fCB7fTsKICAgIGlmIChkZWx0YS5jb250ZW50KSBjb250ZW50ICs9IGRlbHRhLmNvbnRlbnQ7CiAgICBmb3IgKGNvbnN0IHRjIG9mIGRlbHRhLnRvb2xfY2Fs
::B64:agent.js:bHMgfHwgW10pIHsKICAgICAgY29uc3QgaSA9IHRjLmluZGV4ID8/IDA7CiAgICAgIGNhbGxzW2ldID8/PSB7IGlkOiAiIiwgdHlwZTogImZ1bmN0aW9uIiwgZnVuY3Rpb246IHsgbmFtZTogIiIsIGFyZ3VtZW50czogIiIgfSB9OwogICAgICBpZiAodGMuaWQpIGNh
::B64:agent.js:bGxzW2ldLmlkID0gdGMuaWQ7CiAgICAgIGlmICh0Yy5mdW5jdGlvbj8ubmFtZSkgY2FsbHNbaV0uZnVuY3Rpb24ubmFtZSArPSB0Yy5mdW5jdGlvbi5uYW1lOwogICAgICBpZiAodGMuZnVuY3Rpb24/LmFyZ3VtZW50cykgY2FsbHNbaV0uZnVuY3Rpb24uYXJndW1l
::B64:agent.js:bnRzICs9IHRjLmZ1bmN0aW9uLmFyZ3VtZW50czsKICAgIH0KICB9CiAgY29uc3QgdmFsaWQgPSBjYWxscy5maWx0ZXIoQm9vbGVhbikubWFwKChjLCBpKSA9PiAoeyAuLi5jLCBpZDogYy5pZCB8fCBgY2FsbF8ke2l9YCB9KSk7CiAgaWYgKCFjb250ZW50ICYmICF2
::B64:agent.js:YWxpZC5sZW5ndGgpIHJldHVybiB7IG1zZzogbnVsbCwgZXJyOiBzc2VFcnIgfHwgInRhbnBhIGlzaSIgfTsKICBjb25zdCBtc2cgPSB7IHJvbGU6ICJhc3Npc3RhbnQiLCBjb250ZW50OiBjb250ZW50IHx8IG51bGwgfTsKICBpZiAodmFsaWQubGVuZ3RoKSBtc2cu
::B64:agent.js:dG9vbF9jYWxscyA9IHZhbGlkOwogIHJldHVybiB7IG1zZywgZXJyOiAiIiB9Owp9Cgphc3luYyBmdW5jdGlvbiByZXF1ZXN0T25jZShtZXNzYWdlcywgeyBtb2RlbCwgdG9vbENob2ljZSwgc3RyZWFtLCBzbGltIH0pIHsKICBjb25zdCB0b29sTGlzdCA9IHNsaW0g
::B64:agent.js:PyBzZWxlY3RUb29scyhtZXNzYWdlcykgOiB0b29scy5maWx0ZXIoKHQpID0+IHQuZnVuY3Rpb24ubmFtZSAhPT0gIm1vcmVfdG9vbHMiKTsKICBjb25zdCBib2R5ID0geyBtb2RlbCwgbWVzc2FnZXMsIHRvb2xzOiB0b29sTGlzdCwgc3RyZWFtIH07CiAgaWYgKHRv
::B64:agent.js:b2xDaG9pY2UpIGJvZHkudG9vbF9jaG9pY2UgPSAicmVxdWlyZWQiOwogIGNvbnN0IHJlcyA9IGF3YWl0IGZldGNoKGAke0JBU0VfVVJMfS9jaGF0L2NvbXBsZXRpb25zYCwgewogICAgbWV0aG9kOiAiUE9TVCIsCiAgICBoZWFkZXJzOiB7ICJDb250ZW50LVR5cGUi
::B64:agent.js:OiAiYXBwbGljYXRpb24vanNvbiIsIEF1dGhvcml6YXRpb246IGBCZWFyZXIgJHtBUElfS0VZfWAgfSwKICAgIGJvZHk6IEpTT04uc3RyaW5naWZ5KGJvZHkpLAogICAgc2lnbmFsOiBBYm9ydFNpZ25hbC50aW1lb3V0KDEyMDAwMCksCiAgfSk7CiAgaWYgKCFyZXMu
::B64:agent.js:b2spIHsKICAgIGNvbnN0IGVyclRleHQgPSAoYXdhaXQgcmVzLnRleHQoKSkucmVwbGFjZSgvXHMrL2csICIgIikuc2xpY2UoMCwgMjAwKTsKICAgIGlmIChyZXMuc3RhdHVzID09PSA0MDEgfHwgcmVzLnN0YXR1cyA9PT0gNDAzKSB0aHJvdyBmYXRhbChgQVBJIGtl
::B64:agent.js:eSBkaXRvbGFrICgke3Jlcy5zdGF0dXN9KS4gSmFsYW5rYW46IHN0YXJ0LWFnZW50LmJhdCByZXNldGApOwogICAgY29uc3QgZSA9IG5ldyBFcnJvcihgSFRUUCAke3Jlcy5zdGF0dXN9ICR7ZXJyVGV4dH1gKTsKICAgIGlmIChyZXMuc3RhdHVzID09PSA0MjkpIGUu
::B64:agent.js:d2FpdCA9IE1hdGgubWluKE51bWJlcihyZXMuaGVhZGVycy5nZXQoInJldHJ5LWFmdGVyIikpIHx8IDUsIDE1KSAqIDEwMDA7CiAgICB0aHJvdyBlOwogIH0KICBjb25zdCByYXcgPSBhd2FpdCByZXMudGV4dCgpOwogIGNvbnN0IHsgbXNnLCBlcnIgfSA9IHBhcnNl
::B64:agent.js:Q2hhdChyYXcpOwogIGlmICghbXNnKSB7CiAgICBjb25zdCBwZWVrID0gYFtIVFRQICR7cmVzLnN0YXR1c30sICR7cmF3Lmxlbmd0aH0gYnl0ZSR7cmF3LnRyaW0oKSA/ICI6ICIgKyByYXcucmVwbGFjZSgvXHMrL2csICIgIikuc2xpY2UoMCwgMTAwKSA6ICIifV1g
::B64:agent.js:OwogICAgdGhyb3cgbmV3IEVycm9yKGByZXNwb25zICR7ZXJyfSAke3BlZWt9YCk7CiAgfQogIHJldHVybiBtc2c7Cn0KCmFzeW5jIGZ1bmN0aW9uIGNhbGxMTE0obWVzc2FnZXMpIHsKICBjb25zdCBBVFRFTVBUUyA9IDc7CiAgbGV0IGxhc3RFcnIgPSAiIjsKICBm
::B64:agent.js:b3IgKGxldCBhdHRlbXB0ID0gMTsgYXR0ZW1wdCA8PSBBVFRFTVBUUzsgYXR0ZW1wdCsrKSB7CiAgICBpZiAoYXR0ZW1wdCA+PSAzKSBzbGltTW9kZSA9IHRydWU7IC8vIGtlY2lsa2FuIG11YXRhbiBhbGF0CiAgICBpZiAoYXR0ZW1wdCA+PSA0KSB7CiAgICAgIC8v
::B64:agent.js:IFBpbmRhaCBrZSBtb2RlbCBsYWluCiAgICAgIGlmICghZmFsbGJhY2tNb2RlbHMpIGZhbGxiYWNrTW9kZWxzID0gYXdhaXQgZGlzY292ZXJNb2RlbHMoKTsKICAgICAgY29uc3QgcG9vbCA9IG1vZGVsUG9vbCgpOwogICAgICBpZiAocG9vbC5sZW5ndGggPiAxKSB7
::B64:agent.js:CiAgICAgICAgcG9vbElkeCA9IChwb29sSWR4ICsgMSkgJSBwb29sLmxlbmd0aDsKICAgICAgICBjb25zb2xlLmxvZyhgICAobWVuY29iYSBtb2RlbCBsYWluOiAke3Bvb2xbcG9vbElkeF19KWApOwogICAgICB9CiAgICB9CiAgICBjb25zdCBwb29sID0gbW9kZWxQ
::B64:agent.js:b29sKCk7CiAgICBjb25zdCBtb2RlbCA9IHBvb2xbcG9vbElkeCAlIHBvb2wubGVuZ3RoXTsKICAgIHRyeSB7CiAgICAgIGNvbnN0IG1zZyA9IGF3YWl0IHJlcXVlc3RPbmNlKG1lc3NhZ2VzLCB7CiAgICAgICAgbW9kZWwsCiAgICAgICAgdG9vbENob2ljZTogYXR0
::B64:agent.js:ZW1wdCA9PT0gMSAmJiB1c2VUb29sQ2hvaWNlLAogICAgICAgIHN0cmVhbTogYXR0ZW1wdCA8IDMgfHwgYXR0ZW1wdCAlIDIgPT09IDAsCiAgICAgICAgc2xpbTogc2xpbU1vZGUsCiAgICAgIH0pOwogICAgICBjb25zdCBjbGVhbiA9IHsgcm9sZTogImFzc2lzdGFu
::B64:agent.js:dCIsIGNvbnRlbnQ6IG1zZy5jb250ZW50ID8/IG51bGwgfTsKICAgICAgaWYgKG1zZy50b29sX2NhbGxzPy5sZW5ndGgpIGNsZWFuLnRvb2xfY2FsbHMgPSBtc2cudG9vbF9jYWxsczsKICAgICAgcmV0dXJuIGNsZWFuOwogICAgfSBjYXRjaCAoZSkgewogICAgICBp
::B64:agent.js:ZiAoZS5mYXRhbCkgdGhyb3cgZTsKICAgICAgbGFzdEVyciA9IGUubWVzc2FnZTsKICAgICAgaWYgKGF0dGVtcHQgPT09IDEpIHVzZVRvb2xDaG9pY2UgPSBmYWxzZTsKICAgIH0KICAgIGlmIChhdHRlbXB0IDwgQVRURU1QVFMpIHsKICAgICAgY29uc29sZS5sb2co
::B64:agent.js:YCAgKDlSb3V0ZXIgYmVybWFzYWxhaDogJHtsYXN0RXJyLnNsaWNlKDAsIDE0MCl9LiBNZW5jb2JhIHVsYW5nICR7YXR0ZW1wdH0vJHtBVFRFTVBUUyAtIDF9Li4uKWApOwogICAgICBhd2FpdCBzbGVlcChNYXRoLm1pbihCQUNLT0ZGICogYXR0ZW1wdCwgNDAwMCkp
::B64:agent.js:OwogICAgfQogIH0KICB0aHJvdyBuZXcgRXJyb3IoCiAgICBgOVJvdXRlciBnYWdhbCBtZXJlc3BvbnMgc2V0ZWxhaCAke0FUVEVNUFRTfSBwZXJjb2JhYW4gKCR7bGFzdEVyci5zbGljZSgwLCAxNjApfSkuIGAgKwogICAgICBgS2V0aWsgL3RlcyB1bnR1ayBtZW5n
::B64:agent.js:dWppIG1vZGVsIGRhbiBtZW1pbGloIHlhbmcgc3RhYmlsLiBDZWsganVnYSBkYXNoYm9hcmQgOVJvdXRlciwgbWVudSBDb25zb2xlIExvZy5gCiAgKTsKfQoKLy8gVWppIHNhdHUgbW9kZWwgZGVuZ2FuIHBlcm1pbnRhYW4ga2VjaWwgeWFuZyBtZW1pbnRhIHBlbWFu
::B64:agent.js:Z2dpbGFuIHRvb2wKYXN5bmMgZnVuY3Rpb24gdGVzdE1vZGVsKG1vZGVsKSB7CiAgY29uc3QgdDAgPSBEYXRlLm5vdygpOwogIGNvbnN0IHBpbmdUb29sID0gWwogICAgewogICAgICB0eXBlOiAiZnVuY3Rpb24iLAogICAgICBmdW5jdGlvbjogewogICAgICAgIG5h
::B64:agent.js:bWU6ICJwaW5nIiwKICAgICAgICBkZXNjcmlwdGlvbjogIlRlcyBrb25la3NpIiwKICAgICAgICBwYXJhbWV0ZXJzOiB7IHR5cGU6ICJvYmplY3QiLCBwcm9wZXJ0aWVzOiB7IHBlc2FuOiB7IHR5cGU6ICJzdHJpbmciIH0gfSwgcmVxdWlyZWQ6IFsicGVzYW4iXSB9
::B64:agent.js:LAogICAgICB9LAogICAgfSwKICBdOwogIHRyeSB7CiAgICBjb25zdCByZXMgPSBhd2FpdCBmZXRjaChgJHtCQVNFX1VSTH0vY2hhdC9jb21wbGV0aW9uc2AsIHsKICAgICAgbWV0aG9kOiAiUE9TVCIsCiAgICAgIGhlYWRlcnM6IHsgIkNvbnRlbnQtVHlwZSI6ICJh
::B64:agent.js:cHBsaWNhdGlvbi9qc29uIiwgQXV0aG9yaXphdGlvbjogYEJlYXJlciAke0FQSV9LRVl9YCB9LAogICAgICBib2R5OiBKU09OLnN0cmluZ2lmeSh7CiAgICAgICAgbW9kZWwsCiAgICAgICAgbWVzc2FnZXM6IFt7IHJvbGU6ICJ1c2VyIiwgY29udGVudDogIlBhbmdn
::B64:agent.js:aWwgdG9vbCBwaW5nIGRlbmdhbiBwZXNhbiBvay4iIH1dLAogICAgICAgIHRvb2xzOiBwaW5nVG9vbCwKICAgICAgICBzdHJlYW06IGZhbHNlLAogICAgICB9KSwKICAgICAgc2lnbmFsOiBBYm9ydFNpZ25hbC50aW1lb3V0KDQ1MDAwKSwKICAgIH0pOwogICAgY29u
::B64:agent.js:c3QgcmF3ID0gYXdhaXQgcmVzLnRleHQoKTsKICAgIGNvbnN0IG1zID0gRGF0ZS5ub3coKSAtIHQwOwogICAgaWYgKCFyZXMub2spIHJldHVybiB7IG1hcms6ICJbWF0gIiwgbXMsIHRleHQ6IGBIVFRQICR7cmVzLnN0YXR1c30gJHtyYXcucmVwbGFjZSgvXHMrL2cs
::B64:agent.js:ICIgIikuc2xpY2UoMCwgNzApfWAgfTsKICAgIGNvbnN0IHsgbXNnLCBlcnIgfSA9IHBhcnNlQ2hhdChyYXcpOwogICAgaWYgKCFtc2cpIHJldHVybiB7IG1hcms6ICJbWF0gIiwgbXMsIHRleHQ6IGByZXNwb25zICR7ZXJyfWAgfTsKICAgIGlmIChtc2cudG9vbF9j
::B64:agent.js:YWxscz8ubGVuZ3RoKSByZXR1cm4geyBtYXJrOiAiW09LXSIsIG1zLCB0ZXh0OiAidG9vbCBjYWxsaW5nIGJlcmZ1bmdzaSIgfTsKICAgIHJldHVybiB7IG1hcms6ICJbfl0gIiwgbXMsIHRleHQ6ICJtZW5qYXdhYiB0YXBpIHRpZGFrIG1lbWFuZ2dpbCB0b29sIChr
::B64:agent.js:dXJhbmcgY29jb2sgdW50dWsgYWdlbnQpIiB9OwogIH0gY2F0Y2ggKGUpIHsKICAgIHJldHVybiB7IG1hcms6ICJbWF0gIiwgbXM6IERhdGUubm93KCkgLSB0MCwgdGV4dDogZS5uYW1lID09PSAiVGltZW91dEVycm9yIiA/ICJ0aW1lb3V0IiA6IGUubWVzc2FnZS5z
::B64:agent.js:bGljZSgwLCA3MCkgfTsKICB9Cn0KCi8vID09PT09IE1lbW9yaSBwZXJjYWthcGFuID09PT09CmNvbnN0IGhpc3RvcnkgPSBbXTsKY29uc3QgTUFYX0hJU1RPUlkgPSAzMDsKCmZ1bmN0aW9uIHN0cmlwSW1hZ2VzKCkgewogIGZvciAoY29uc3QgbSBvZiBoaXN0b3J5
::B64:agent.js:KSB7CiAgICBpZiAobS5yb2xlID09PSAidXNlciIgJiYgQXJyYXkuaXNBcnJheShtLmNvbnRlbnQpKSB7CiAgICAgIG0uY29udGVudCA9ICJbc2NyZWVuc2hvdCBsYW1hIGRpaGFwdXMgdW50dWsgbWVuZ2hlbWF0IG1lbW9yaV0iOwogICAgfQogIH0KfQoKZnVuY3Rp
::B64:agent.js:b24gdHJpbUhpc3RvcnkoKSB7CiAgd2hpbGUgKGhpc3RvcnkubGVuZ3RoID4gTUFYX0hJU1RPUlkpIHsKICAgIGxldCBpID0gMTsKICAgIHdoaWxlIChpIDwgaGlzdG9yeS5sZW5ndGggJiYgIShoaXN0b3J5W2ldLnJvbGUgPT09ICJ1c2VyIiAmJiB0eXBlb2YgaGlz
::B64:agent.js:dG9yeVtpXS5jb250ZW50ID09PSAic3RyaW5nIikpIGkrKzsKICAgIGlmIChpID49IGhpc3RvcnkubGVuZ3RoKSBicmVhazsKICAgIGhpc3Rvcnkuc3BsaWNlKDAsIGkpOwogIH0KfQoKYXN5bmMgZnVuY3Rpb24gcnVuVGFzayhjb21tYW5kKSB7CiAgY29uc3Qgc3Rh
::B64:agent.js:cnRMZW4gPSBoaXN0b3J5Lmxlbmd0aDsKICBoaXN0b3J5LnB1c2goeyByb2xlOiAidXNlciIsIGNvbnRlbnQ6IGNvbW1hbmQgfSk7CiAgbGV0IG51ZGdlcyA9IDA7CgogIHRyeSB7CiAgICBmb3IgKGxldCBzdGVwID0gMTsgc3RlcCA8PSBNQVhfU1RFUFM7IHN0ZXAr
::B64:agent.js:KykgewogICAgICBjb25zdCBtc2cgPSBhd2FpdCBjYWxsTExNKFt7IHJvbGU6ICJzeXN0ZW0iLCBjb250ZW50OiBTWVNURU0gfSwgLi4uaGlzdG9yeV0pOwogICAgICBoaXN0b3J5LnB1c2gobXNnKTsKCiAgICAgIGlmICghbXNnLnRvb2xfY2FsbHM/Lmxlbmd0aCkg
::B64:agent.js:ewogICAgICAgIC8vIE1vZGVsIGN1bWEgbWVudWxpcyB0ZWtzL3JlbmNhbmEgdGFucGEgbWVtYW5nZ2lsIHRvb2wgLT4gcGFrc2EgcGFuZ2dpbCB0b29sCiAgICAgICAgaWYgKG51ZGdlcyA8IDMpIHsKICAgICAgICAgIG51ZGdlcysrOwogICAgICAgICAgaGlzdG9y
::B64:agent.js:eS5wdXNoKHsKICAgICAgICAgICAgcm9sZTogInVzZXIiLAogICAgICAgICAgICBjb250ZW50OiAiS2FtdSBoYXJ1cyBtZW1hbmdnaWwgdG9vbC4gSmFuZ2FuIG1lbnVsaXMgdGVrcyBiaWFzYS4gTGFuZ3N1bmcgcGFuZ2dpbCB0b29sIHlhbmcgc2VzdWFpLCBhdGF1
::B64:agent.js:IHBhbmdnaWwgZG9uZSBqaWthIHR1Z2FzIHN1ZGFoIHNlbGVzYWkuIiwKICAgICAgICAgIH0pOwogICAgICAgICAgY29udGludWU7CiAgICAgICAgfQogICAgICAgIGNvbnNvbGUubG9nKCJcbkFnZW50OiIsIG1zZy5jb250ZW50IHx8ICIodGlkYWsgYWRhIGphd2Fi
::B64:agent.js:YW4pIik7CiAgICAgICAgcmV0dXJuOwogICAgICB9CgogICAgICAvLyBUdWdhcyBzZWxlc2FpOiBzZW11YSB0b29sX2NhbGwgd2FqaWIgZGlqYXdhYiBhZ2FyIHJpd2F5YXQgdGV0YXAgdmFsaWQKICAgICAgY29uc3QgZG9uZUNhbGwgPSBtc2cudG9vbF9jYWxscy5m
::B64:agent.js:aW5kKChjKSA9PiBjLmZ1bmN0aW9uLm5hbWUgPT09ICJkb25lIik7CiAgICAgIGlmIChkb25lQ2FsbCkgewogICAgICAgIGxldCBtID0gIiI7CiAgICAgICAgdHJ5IHsKICAgICAgICAgIG0gPSBKU09OLnBhcnNlKGRvbmVDYWxsLmZ1bmN0aW9uLmFyZ3VtZW50cyB8
::B64:agent.js:fCAie30iKS5tZXNzYWdlIHx8ICIiOwogICAgICAgIH0gY2F0Y2gge30KICAgICAgICBmb3IgKGNvbnN0IGNhbGwgb2YgbXNnLnRvb2xfY2FsbHMpIHsKICAgICAgICAgIGhpc3RvcnkucHVzaCh7IHJvbGU6ICJ0b29sIiwgdG9vbF9jYWxsX2lkOiBjYWxsLmlkLCBj
::B64:agent.js:b250ZW50OiBjYWxsID09PSBkb25lQ2FsbCA/ICJvayIgOiAiZGlsZXdhdGkiIH0pOwogICAgICAgIH0KICAgICAgICBjb25zb2xlLmxvZygiXG5BZ2VudDoiLCBtIHx8ICJTZWxlc2FpLiIpOwogICAgICAgIHJldHVybjsKICAgICAgfQoKICAgICAgZm9yIChjb25z
::B64:agent.js:dCBjYWxsIG9mIG1zZy50b29sX2NhbGxzKSB7CiAgICAgICAgY29uc3QgbmFtZSA9IGNhbGwuZnVuY3Rpb24ubmFtZTsKICAgICAgICBsZXQgcmVzdWx0OwogICAgICAgIHRyeSB7CiAgICAgICAgICBjb25zdCBhcmdzID0gSlNPTi5wYXJzZShjYWxsLmZ1bmN0aW9u
::B64:agent.js:LmFyZ3VtZW50cyB8fCAie30iKTsKICAgICAgICAgIGNvbnNvbGUubG9nKGBbJHtzdGVwfV0gJHtuYW1lfWAsIGFyZ3MpOwogICAgICAgICAgaWYgKCFpbXBsW25hbWVdKSB0aHJvdyBuZXcgRXJyb3IoIlRvb2wgdGlkYWsgZGlrZW5hbDogIiArIG5hbWUpOwogICAg
::B64:agent.js:ICAgICAgYXdhaXQgZW5zdXJlUGFnZSgpOwogICAgICAgICAgcmVzdWx0ID0gYXdhaXQgaW1wbFtuYW1lXShhcmdzKTsKICAgICAgICB9IGNhdGNoIChlKSB7CiAgICAgICAgICByZXN1bHQgPSAiRVJST1I6ICIgKyBlLm1lc3NhZ2U7CiAgICAgICAgfQogICAgICAg
::B64:agent.js:IGhpc3RvcnkucHVzaCh7IHJvbGU6ICJ0b29sIiwgdG9vbF9jYWxsX2lkOiBjYWxsLmlkLCBjb250ZW50OiBTdHJpbmcocmVzdWx0KS5zbGljZSgwLCA0MDAwKSB9KTsKICAgICAgfQoKICAgICAgLy8gS2lyaW0gc2NyZWVuc2hvdCAoamlrYSBhZGEpIHNlYmFnYWkg
::B64:agent.js:Z2FtYmFyOyBnYW1iYXIgbGFtYSBkaWJ1YW5nIGFnYXIgcmluZ2FuCiAgICAgIGlmIChwZW5kaW5nSW1hZ2VzLmxlbmd0aCkgewogICAgICAgIHN0cmlwSW1hZ2VzKCk7CiAgICAgICAgaGlzdG9yeS5wdXNoKHsKICAgICAgICAgIHJvbGU6ICJ1c2VyIiwKICAgICAg
::B64:agent.js:ICAgIGNvbnRlbnQ6IFsKICAgICAgICAgICAgeyB0eXBlOiAidGV4dCIsIHRleHQ6ICJJbmkgc2NyZWVuc2hvdCBsYXlhciB0ZXJiYXJ1OiIgfSwKICAgICAgICAgICAgLi4ucGVuZGluZ0ltYWdlcy5zcGxpY2UoMCkubWFwKChiNjQpID0+ICh7CiAgICAgICAgICAg
::B64:agent.js:ICAgdHlwZTogImltYWdlX3VybCIsCiAgICAgICAgICAgICAgaW1hZ2VfdXJsOiB7IHVybDogYGRhdGE6aW1hZ2UvcG5nO2Jhc2U2NCwke2I2NH1gIH0sCiAgICAgICAgICAgIH0pKSwKICAgICAgICAgIF0sCiAgICAgICAgfSk7CiAgICAgIH0KICAgICAgYXdhaXQg
::B64:agent.js:c2xlZXAoMzAwKTsKICAgIH0KICAgIGNvbnNvbGUubG9nKCJCZXJoZW50aTogbWVsZXdhdGkgYmF0YXMgbGFuZ2thaC4iKTsKICB9IGNhdGNoIChlKSB7CiAgICBoaXN0b3J5Lmxlbmd0aCA9IHN0YXJ0TGVuOyAvLyBidWFuZyByaXdheWF0IHR1Z2FzIHlhbmcgZ2Fn
::B64:agent.js:YWwgc3VwYXlhIHRpZGFrIG1lcnVzYWsgcGVyY2FrYXBhbiBiZXJpa3V0bnlhCiAgICB0aHJvdyBlOwogIH0gZmluYWxseSB7CiAgICBzdHJpcEltYWdlcygpOwogICAgdHJpbUhpc3RvcnkoKTsKICB9Cn0KCmNvbnN0IEJVSUxUSU5fQ0hBTkdFTE9HID0gYFZlcnNp
::B64:agent.js:IDYKLSBLb25la3NpIGtlIDlSb3V0ZXIgamF1aCBsZWJpaCB0YWhhbiBiYW50aW5nOiBvdG9tYXRpcyBrZWNpbGthbiBtdWF0YW4gZGFuIHBpbmRhaCBrZSBtb2RlbCBsYWluIGppa2EgYmFsYXNhbiBrb3NvbmcuCi0gUGVyaW50YWggL3RlcyBtZW5ndWppIHNlbXVh
::B64:agent.js:IG1vZGVsIGRhbiBtZW1pbGloIHlhbmcgcGFsaW5nIHN0YWJpbCB1bnR1ayBhZ2VudC4gL21vZGVsIHVudHVrIG1lbGloYXQgYXRhdSBtZW5nZ2FudGkgbW9kZWwuCi0gUGVzYW4gZXJyb3Igc2VrYXJhbmcgbWVuYW1waWxrYW4gcGVueWViYWIgc2ViZW5hcm55YSAo
::B64:agent.js:c3RhdHVzIGRhbiBpc2kgYmFsYXNhbikuCi0gVmVyc2kgNTogYmFueWFrIHRhYiBkYW4gdXBsb2FkIGJhbnlhayBmaWxlLiBWZXJzaSA0OiBDaHJvbWUvRWRnZSBhc2xpLCBsb2dpbiwgWW91VHViZSwgYWxhdCBQQyBkYW4gZmlsZS4KS2V0aWsgL2JhbnR1YW4gdW50
::B64:agent.js:dWsgZGFmdGFyIGxlbmdrYXAuYDsKCmNvbnN0IEhFTFAgPSBgCkZJVFVSIEFHRU5UCiAgQnJvd3NlciAgOiBidWthIHdlYnNpdGUsIGlzaSBmb3JtLCBrbGlrLCBjYXJpIGRpIHdlYiwgc2Nyb2xsCiAgVGFiICAgICAgOiBidWthIHRhYiBiYXJ1LCBiYW55YWsgc2l0
::B64:agent.js:dXMgc2VrYWxpZ3VzLCBwaW5kYWggZGFuIHR1dHVwIHRhYiAodmlkZW8gdGlkYWsgdGVydGltcGEpCiAgWW91VHViZSAgOiBjYXJpICsgcHV0YXIgb3RvbWF0aXMgKHNraXAgaWtsYW4pLCBrb250cm9sIHBhdXNlL25leHQvbWFqdS9tdW5kdXIvbXV0ZS9mdWxsc2Ny
::B64:agent.js:ZWVuCiAgTG9naW4gICAgOiAvbG9naW4gbGFsdSBsb2dpbiBtYW51YWwgc2VrYWxpLCBzZXNpIHRlcnNpbXBhbi4gQWdlbnQgdGlkYWsgcGVybmFoIG1lbmdldGlrIHBhc3N3b3JkbXUKICBVcGxvYWQgICA6IHNhdHUgZmlsZSwgYmFueWFrIGZpbGUgc2VrYWxpZ3Vz
::B64:agent.js:LCBhdGF1IHNhdHUgZm9sZGVyIHBlbnVoLCBkYXJpIGxva2FzaSBtYW5hIHB1bgogIExheWFyICAgIDogc2NyZWVuc2hvdCwga2xpaywgc2Nyb2xsLCBrZXRpaywgdGVrYW4gdG9tYm9sCiAgSmVuZGVsYSAgOiBkYWZ0YXIsIHBpbmRhaCBmb2t1cywgdHV0dXAKICBG
::B64:agent.js:aWxlICAgICA6IGNhcmkgZmlsZS9mb2xkZXIgZGkgc2VtdWEgZHJpdmUsIGJhY2EvdHVsaXMgdGVrcywgYnVhdCBmb2xkZXIsIHBpbmRhaCwKICAgICAgICAgICAgIGhhcHVzIGtlIFJlY3ljbGUgQmluLCB6aXAvdW56aXAsIHVuZHVoIGRhcmkgaW50ZXJuZXQKICBQ
::B64:agent.js:QyAgICAgICA6IHZvbHVtZSBkYW4gdG9tYm9sIG1lZGlhLCBjbGlwYm9hcmQsIGluZm8gc2lzdGVtLCB0YW5nZ2FsIGRhbiBqYW0KUEVSSU5UQUggS0hVU1VTCiAgL2xvZ2luIFthbGFtYXRdICBsb2dpbiBtYW51YWwgZGkgYnJvd3NlciAgICAgIC9iYXJ1ICAgICBk
::B64:agent.js:YWZ0YXIgZml0dXIgdGVyYmFydQogIC90ZXMgICAgICAgICAgICAgdWppIHNlbXVhIG1vZGVsLCBwaWxpaCB5YW5nIHN0YWJpbCAgIC9tb2RlbCBbbmFtYV0gIGxpaGF0IGF0YXUgZ2FudGkgbW9kZWwKICAvdXBkYXRlICAgICAgICAgIHBlcmJhcnVpIHNla2FyYW5n
::B64:agent.js:ICAgICAgICAgICAgL3ZlcnNpICAgIGNlayB2ZXJzaQogIC9yZXNldCAgICAgICAgICAgbHVwYWthbiBwZXJjYWthcGFuICAgICAgICAgICAvYmFudHVhbiAgdGFtcGlsa2FuIGluaSAgICAgICAgZXhpdCAga2VsdWFyCkNPTlRPSAogIGJ1a2EgdGFiIGJhcnUgbGFs
::B64:agent.js:dSBjYXJpIGNhcmEgbWVtYmFoYWdpYWthbiBvcmFuZyB0dWEgIHwgIGJ1a2EgeW91dHViZSwgZ21haWwsIGRhbiBnaXRodWIgc2VrYWxpZ3VzCiAgdXBsb2FkIHNlbXVhIHBkZiBkaSBmb2xkZXIgTGFwb3JhbiBrZSBtZWRpYWZpcmUgIHwgIHBpbmRhaCBrZSB0YWIg
::B64:agent.js:eW91dHViZSBsYWx1IHBhdXNlCmA7CgpmdW5jdGlvbiBzaG93V2hhdHNOZXcoZm9yY2UgPSBmYWxzZSkgewogIGNvbnN0IHZlciA9IGxvY2FsVmVyc2lvbigpOwogIGxldCBzZWVuID0gIiI7CiAgdHJ5IHsKICAgIHNlZW4gPSBmcy5yZWFkRmlsZVN5bmMoIi53aGF0
::B64:agent.js:c25ldy1zZWVuIiwgInV0ZjgiKS50cmltKCk7CiAgfSBjYXRjaCB7fQogIGlmICghZm9yY2UgJiYgc2VlbiA9PT0gdmVyKSByZXR1cm47CiAgbGV0IHRleHQgPSAiIjsKICB0cnkgewogICAgdGV4dCA9IGZzLnJlYWRGaWxlU3luYygiY2hhbmdlbG9nLnR4dCIsICJ1
::B64:agent.js:dGY4IikudHJpbSgpOwogIH0gY2F0Y2gge30KICBpZiAoIXRleHQpIHRleHQgPSBCVUlMVElOX0NIQU5HRUxPRzsKICBjb25zb2xlLmxvZygiXG49PT09PT09PT09PT09PT09PT0gWUFORyBCQVJVID09PT09PT09PT09PT09PT09PSIpOwogIGNvbnNvbGUubG9nKHRl
::B64:agent.js:eHQuc3BsaXQoL1xyP1xuLykuc2xpY2UoMCwgMzApLmpvaW4oIlxuIikpOwogIGNvbnNvbGUubG9nKCI9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PSIpOwogIHRyeSB7CiAgICBmcy53cml0ZUZpbGVTeW5jKCIud2hhdHNuZXct
::B64:agent.js:c2VlbiIsIHZlcik7CiAgfSBjYXRjaCB7fQp9Cgpjb25zb2xlLmxvZyhgQWdlbnQgc2lhcC4gVmVyc2kgJHtsb2NhbFZlcnNpb24oKX0uIEZvbGRlciB1cGxvYWQ6ICR7U0FGRV9ESVJ9YCk7CmNvbnNvbGUubG9nKGBJemluIHNlYmVsdW0gYWtzaTogJHtDT05GSVJN
::B64:agent.js:ID8gIkFLVElGIiA6ICJNQVRJIn0uIFRla2FuIEN0cmwrQyBrYXBhbiBzYWphIHVudHVrIG1lbmdoZW50aWthbi5gKTsKc2hvd1doYXRzTmV3KCk7CmNvbnNvbGUubG9nKCdLZXRpayBwZXJpbnRhaCBkYWxhbSBiYWhhc2EgYmlhc2EuIEtldGlrIC9iYW50dWFuIHVu
::B64:agent.js:dHVrIGRhZnRhciBmaXR1ciwgL2xvZ2luIHVudHVrIGxvZ2luLCBleGl0IHVudHVrIGtlbHVhci4nKTsKY2hlY2tVcGRhdGUoKTsKd2hpbGUgKHRydWUpIHsKICBjb25zdCBjbWQgPSBhd2FpdCBybC5xdWVzdGlvbigiXG5QZXJpbnRhaD4gIik7CiAgY29uc3QgYyA9
::B64:agent.js:IGNtZC50cmltKCk7CiAgaWYgKGMgPT09ICJleGl0IikgYnJlYWs7CiAgaWYgKCFjKSBjb250aW51ZTsKICBpZiAoYyA9PT0gIi90ZXMiKSB7CiAgICBpZiAoIWZhbGxiYWNrTW9kZWxzKSBmYWxsYmFja01vZGVscyA9IGF3YWl0IGRpc2NvdmVyTW9kZWxzKCk7CiAg
::B64:agent.js:ICBjb25zdCBsaXN0ID0gbW9kZWxQb29sKCkuc2xpY2UoMCwgOSk7CiAgICBjb25zb2xlLmxvZyhgTWVuZ3VqaSAke2xpc3QubGVuZ3RofSBtb2RlbCwgdGlhcCBtb2RlbCBtYWtzaW1hbCA0NSBkZXRpay4uLmApOwogICAgbGV0IGJlc3QgPSAiIjsKICAgIGZvciAo
::B64:agent.js:Y29uc3QgbSBvZiBsaXN0KSB7CiAgICAgIGNvbnN0IHIgPSBhd2FpdCB0ZXN0TW9kZWwobSk7CiAgICAgIGNvbnNvbGUubG9nKGAgICR7ci5tYXJrfSAke219ICAgJHtyLm1zfSBtcyAgICR7ci50ZXh0fWApOwogICAgICBpZiAoIWJlc3QgJiYgci5tYXJrID09PSAi
::B64:agent.js:W09LXSIpIGJlc3QgPSBtOwogICAgfQogICAgaWYgKCFiZXN0KSB7CiAgICAgIGNvbnNvbGUubG9nKCJcblRpZGFrIGFkYSBtb2RlbCB5YW5nIGxvbG9zLiBDZWsgZGFzaGJvYXJkIDlSb3V0ZXI6IHByb3ZpZGVyIHRlcmh1YnVuZywga3VvdGEsIGRhbiBtZW51IENv
::B64:agent.js:bnNvbGUgTG9nLiIpOwogICAgfSBlbHNlIGlmIChiZXN0ID09PSBiYXNlTW9kZWwpIHsKICAgICAgY29uc29sZS5sb2coYFxuTW9kZWwgYWt0aWYgKCR7YmFzZU1vZGVsfSkgc3VkYWggYmVyZnVuZ3NpIGJhaWsuYCk7CiAgICB9IGVsc2UgewogICAgICBiYXNlTW9k
::B64:agent.js:ZWwgPSBiZXN0OwogICAgICBwb29sSWR4ID0gMDsKICAgICAgdHJ5IHsKICAgICAgICBmcy53cml0ZUZpbGVTeW5jKE1PREVMX0ZJTEUsIGJlc3QpOwogICAgICB9IGNhdGNoIHt9CiAgICAgIGNvbnNvbGUubG9nKGBcbk1vZGVsIHRlcmJhaWsgZGlwaWxpaCBvdG9t
::B64:agent.js:YXRpczogJHtiZXN0fSAodGVyc2ltcGFuLCBrZXRpayAvbW9kZWwgcmVzZXQgdW50dWsga2VtYmFsaSBrZSBiYXdhYW4pLmApOwogICAgfQogICAgY29udGludWU7CiAgfQogIGlmIChjID09PSAiL21vZGVsIiB8fCBjLnN0YXJ0c1dpdGgoIi9tb2RlbCAiKSkgewog
::B64:agent.js:ICAgY29uc3QgYXJnID0gYy5zbGljZSg2KS50cmltKCk7CiAgICBpZiAoIWFyZykgewogICAgICBpZiAoIWZhbGxiYWNrTW9kZWxzKSBmYWxsYmFja01vZGVscyA9IGF3YWl0IGRpc2NvdmVyTW9kZWxzKCk7CiAgICAgIGNvbnNvbGUubG9nKGBNb2RlbCBha3RpZjog
::B64:agent.js:JHtiYXNlTW9kZWx9XG5Nb2RlbCBsYWluIHlhbmcgdGVyc2VkaWE6ICR7bW9kZWxQb29sKCkuc2xpY2UoMSkuam9pbigiLCAiKSB8fCAiKHRpZGFrIGFkYSkifWApOwogICAgfSBlbHNlIGlmIChhcmcgPT09ICJyZXNldCIpIHsKICAgICAgdHJ5IHsKICAgICAgICBm
::B64:agent.js:cy51bmxpbmtTeW5jKE1PREVMX0ZJTEUpOwogICAgICB9IGNhdGNoIHt9CiAgICAgIGJhc2VNb2RlbCA9IE1PREVMOwogICAgICBwb29sSWR4ID0gMDsKICAgICAgY29uc29sZS5sb2coYEtlbWJhbGkga2UgbW9kZWwgYmF3YWFuOiAke01PREVMfWApOwogICAgfSBl
::B64:agent.js:bHNlIHsKICAgICAgYmFzZU1vZGVsID0gYXJnOwogICAgICBwb29sSWR4ID0gMDsKICAgICAgdHJ5IHsKICAgICAgICBmcy53cml0ZUZpbGVTeW5jKE1PREVMX0ZJTEUsIGFyZyk7CiAgICAgIH0gY2F0Y2gge30KICAgICAgY29uc29sZS5sb2coYE1vZGVsIGRpZ2Fu
::B64:agent.js:dGkga2U6ICR7YXJnfWApOwogICAgfQogICAgY29udGludWU7CiAgfQogIGlmIChjID09PSAiL2JhbnR1YW4iKSB7CiAgICBjb25zb2xlLmxvZyhIRUxQKTsKICAgIGNvbnRpbnVlOwogIH0KICBpZiAoYyA9PT0gIi9iYXJ1IikgewogICAgc2hvd1doYXRzTmV3KHRy
::B64:agent.js:dWUpOwogICAgY29udGludWU7CiAgfQogIGlmIChjLnN0YXJ0c1dpdGgoIi9sb2dpbiIpKSB7CiAgICBsZXQgdGFyZ2V0ID0gYy5zcGxpdCgvXHMrLylbMV0gfHwgImh0dHBzOi8vYWNjb3VudHMuZ29vZ2xlLmNvbS9TZXJ2aWNlTG9naW4/c2VydmljZT15b3V0dWJl
::B64:agent.js:JmNvbnRpbnVlPWh0dHBzOi8vd3d3LnlvdXR1YmUuY29tLyI7CiAgICBpZiAoIS9eaHR0cHM/OlwvXC8vaS50ZXN0KHRhcmdldCkpIHRhcmdldCA9ICJodHRwczovLyIgKyB0YXJnZXQ7CiAgICB0cnkgewogICAgICBhd2FpdCBlbnN1cmVQYWdlKCk7CiAgICAgIGF3
::B64:agent.js:YWl0IHBhZ2UuYnJpbmdUb0Zyb250KCk7CiAgICAgIGF3YWl0IHBhZ2UuZ290byh0YXJnZXQsIHsgd2FpdFVudGlsOiAiZG9tY29udGVudGxvYWRlZCIgfSk7CiAgICB9IGNhdGNoIChlKSB7CiAgICAgIGNvbnNvbGUubG9nKCJHYWdhbCBtZW1idWthIGhhbGFtYW4g
::B64:agent.js:bG9naW46IiwgZS5tZXNzYWdlKTsKICAgIH0KICAgIGNvbnNvbGUubG9nKCJTaWxha2FuIGxvZ2luIGRpIGplbmRlbGEgYnJvd3NlciAoa2FtdSB5YW5nIG1lbmdldGlrLCBhZ2VudCB0aWRhayBtZWxpaGF0IHBhc3N3b3JkKS4iKTsKICAgIGF3YWl0IHJsLnF1ZXN0
::B64:agent.js:aW9uKCJTZXRlbGFoIHNlbGVzYWksIHRla2FuIEVudGVyIGRpIHNpbmkuLi4gIik7CiAgICBjb25zb2xlLmxvZygiTG9naW4gdGVyc2ltcGFuIGRpIHByb2ZpbCBicm93c2VyLiBCZXJpa3V0bnlhIHRpZGFrIHBlcmx1IGxvZ2luIGxhZ2kuIik7CiAgICBjb250aW51
::B64:agent.js:ZTsKICB9CiAgaWYgKGMgPT09ICIvdmVyc2kiKSB7CiAgICBjb25zb2xlLmxvZyhgVmVyc2kgYWdlbnQ6ICR7bG9jYWxWZXJzaW9uKCl9YCk7CiAgICBhd2FpdCBjaGVja1VwZGF0ZSgpOwogICAgaWYgKCFwZW5kaW5nVmVyc2lvbikgY29uc29sZS5sb2coIlN1ZGFo
::B64:agent.js:IHZlcnNpIHRlcmJhcnUgKGF0YXUgdXBkYXRlIG9ubGluZSB0aWRhayBha3RpZikuIik7CiAgICBjb250aW51ZTsKICB9CiAgaWYgKGMgPT09ICIvdXBkYXRlIikgewogICAgY29uc29sZS5sb2coIk1lbXBlcmJhcnVpLi4uIGFnZW50IGFrYW4gbWVudXR1cCBkYW4g
::B64:agent.js:bWVueWFsYSBsYWdpIG90b21hdGlzIGxld2F0IHN0YXJ0LWFnZW50LmJhdC4iKTsKICAgIGF3YWl0IHNodXRkb3duQnJvd3NlcigpOwogICAgcmwuY2xvc2UoKTsKICAgIHByb2Nlc3MuZXhpdCg0Mik7IC8vIGtvZGUgNDIgPSBwZXJtaW50YWFuIHJlc3RhcnQgdW50
::B64:agent.js:dWsgdXBkYXRlOyBkaXRhbmdrYXAgb2xlaCBzdGFydC1hZ2VudC5iYXQKICB9CiAgaWYgKGMgPT09ICIvcmVzZXQiKSB7CiAgICBoaXN0b3J5Lmxlbmd0aCA9IDA7CiAgICBleHRyYUdyb3Vwcy5jbGVhcigpOwogICAgY29uc29sZS5sb2coIlBlcmNha2FwYW4gZGls
::B64:agent.js:dXBha2FuLiIpOwogICAgY29udGludWU7CiAgfQogIHRyeSB7CiAgICBhd2FpdCBydW5UYXNrKGMpOwogIH0gY2F0Y2ggKGUpIHsKICAgIGNvbnNvbGUuZXJyb3IoIkdhZ2FsOiIsIGUubWVzc2FnZSk7CiAgfQp9CmF3YWl0IHNodXRkb3duQnJvd3NlcigpOwpybC5j
::B64:agent.js:bG9zZSgpOwo=
::B64:package.json:ewogICJuYW1lIjogImJvdC1hZ2VudCIsCiAgInZlcnNpb24iOiAiMS4wLjAiLAogICJ0eXBlIjogIm1vZHVsZSIsCiAgInNjcmlwdHMiOiB7CiAgICAic3RhcnQiOiAibm9kZSBhZ2VudC5qcyIKICB9LAogICJkZXBlbmRlbmNpZXMiOiB7CiAgICAicGxheXdyaWdo
::B64:package.json:dCI6ICJeMS40OC4wIgogIH0KfQo=
