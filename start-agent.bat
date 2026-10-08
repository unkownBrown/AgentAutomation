@echo off
setlocal EnableExtensions
chcp 65001 >nul
title Agent Automation
set "SELF=%~f0"
set "EMBED_VER=9"

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
::B64:agent.js:YXlpbmcoKSB7CiAgZm9yIChsZXQgYXR0ZW1wdCA9IDA7IGF0dGVtcHQgPCAyOyBhdHRlbXB0KyspIHsKICAgIGF3YWl0IHNsZWVwKDE4MDApOwogICAgYXdhaXQgc2tpcEFkcygpOwogICAgYXdhaXQgcmVhZFBsYXllclN0YXRlKCk7IC8vIG1lbWljdSBwbGF5KCkK
::B64:agent.js:ICAgIGF3YWl0IHNsZWVwKDcwMCk7CiAgICBjb25zdCBzdCA9IGF3YWl0IHJlYWRQbGF5ZXJTdGF0ZSgpOwogICAgaWYgKHN0LnBsYXlpbmcpIHJldHVybiB0cnVlOwogICAgaWYgKHN0LmVycikgYXdhaXQgcGFnZS5yZWxvYWQoeyB3YWl0VW50aWw6ICJkb21jb250
::B64:agent.js:ZW50bG9hZGVkIiB9KTsKICB9CiAgcmV0dXJuIGZhbHNlOwp9CgovLyA9PT09PSBQZW5jYXJpYW4gWW91VHViZSBjZXBhdCAodGFucGEgbWVtdWF0IGhhbGFtYW4gaGFzaWwgZGkgYnJvd3NlcikgPT09PT0KYXN5bmMgZnVuY3Rpb24geXRTZWFyY2hGYXN0KHF1ZXJ5
::B64:agent.js:KSB7CiAgY29uc3QgcmVzID0gYXdhaXQgZmV0Y2goImh0dHBzOi8vd3d3LnlvdXR1YmUuY29tL3Jlc3VsdHM/aGw9aWQmc2VhcmNoX3F1ZXJ5PSIgKyBlbmNvZGVVUklDb21wb25lbnQocXVlcnkpLCB7CiAgICBoZWFkZXJzOiB7CiAgICAgICJVc2VyLUFnZW50Ijog
::B64:agent.js:Ik1vemlsbGEvNS4wIChXaW5kb3dzIE5UIDEwLjA7IFdpbjY0OyB4NjQpIEFwcGxlV2ViS2l0LzUzNy4zNiAoS0hUTUwsIGxpa2UgR2Vja28pIENocm9tZS8xMjQuMCBTYWZhcmkvNTM3LjM2IiwKICAgICAgIkFjY2VwdC1MYW5ndWFnZSI6ICJpZC1JRCxpZDtxPTAu
::B64:agent.js:OSxlbjtxPTAuOCIsCiAgICB9LAogICAgc2lnbmFsOiBBYm9ydFNpZ25hbC50aW1lb3V0KDgwMDApLAogIH0pOwogIGlmICghcmVzLm9rKSB0aHJvdyBuZXcgRXJyb3IoIkhUVFAgIiArIHJlcy5zdGF0dXMpOwogIGNvbnN0IGh0bWwgPSBhd2FpdCByZXMudGV4dCgp
::B64:agent.js:OwogIGNvbnN0IG0gPSBodG1sLm1hdGNoKC95dEluaXRpYWxEYXRhXHMqPVxzKihcey4rP1x9KTtccyo8XC9zY3JpcHQ+L3MpOwogIGlmICghbSkgdGhyb3cgbmV3IEVycm9yKCJkYXRhIFlvdVR1YmUgdGlkYWsgZGl0ZW11a2FuIik7CiAgY29uc3QgZGF0YSA9IEpT
::B64:agent.js:T04ucGFyc2UobVsxXSk7CiAgY29uc3Qgb3V0ID0gW107CiAgY29uc3Qgd2FsayA9IChvKSA9PiB7CiAgICBpZiAoIW8gfHwgdHlwZW9mIG8gIT09ICJvYmplY3QiIHx8IG91dC5sZW5ndGggPj0gOCkgcmV0dXJuOwogICAgY29uc3QgdiA9IG8udmlkZW9SZW5kZXJl
::B64:agent.js:cjsKICAgIGlmICh2ICYmIHYudmlkZW9JZCkgewogICAgICBvdXQucHVzaCh7CiAgICAgICAgaWQ6IHYudmlkZW9JZCwKICAgICAgICB0aXRsZTogKHYudGl0bGU/LnJ1bnMgfHwgW10pLm1hcCgocikgPT4gci50ZXh0KS5qb2luKCIiKSB8fCAiKHRhbnBhIGp1ZHVs
::B64:agent.js:KSIsCiAgICAgICAgY2hhbm5lbDogdi5vd25lclRleHQ/LnJ1bnM/LlswXT8udGV4dCB8fCAiIiwKICAgICAgfSk7CiAgICAgIHJldHVybjsKICAgIH0KICAgIGZvciAoY29uc3QgayBvZiBPYmplY3Qua2V5cyhvKSkgd2FsayhvW2tdKTsKICB9OwogIHdhbGsoZGF0
::B64:agent.js:YSk7CiAgcmV0dXJuIG91dDsKfQoKLy8gPT09PT0gVXBsb2FkIGNlcGF0ID09PT09CmNvbnN0IFVQTE9BRF9USU1FT1VUX01TID0gTnVtYmVyKHByb2Nlc3MuZW52LlVQTE9BRF9USU1FT1VUX01JTiB8fCAxNSkgKiA2MDAwMDsKY29uc3QgSE9TVFNfUkUgPSAvbWVk
::B64:agent.js:aWFmaXJlXC5jb21cLyhmaWxlfHZpZXd8ZG93bmxvYWR8Zm9sZGVyKXxkcml2ZVwuZ29vZ2xlXC5jb21cLyhmaWxlfGRyaXZlXC9mb2xkZXJzKXx3ZXRyYW5zZmVyXC5jb21cL2Rvd25sb2Fkc3x3ZVwudGxcL3xnb2ZpbGVcLmlvXC9kXC98cGl4ZWxkcmFpblwuY29t
::B64:agent.js:XC91XC98ZmlsZXNcLmNhdGJveFwubW9lfGNhdGJveFwubW9lXC98ZmlsZVwuaW9cL3xzZW5kc3BhY2VcLmNvbVwvZmlsZXx0cmFuc2Zlclwuc2hcL3x0bXBmaWxlc1wub3JnXC9cZHxkcm9wYm94XC5jb21cL3N8bWVnYVwubnpcLyhmaWxlfGZvbGRlcil8MWRydlwu
::B64:agent.js:bXN8ZmlsZWJpblwubmV0XC9cd3x1cGxvYWRoYXZlbnxiYXlmaWxlcy9pOwpjb25zdCBVUExPQURfQlROID0gL15ccyoodXBsb2FkfHVuZ2dhaHxtZW5ndW5nZ2FofHRhbWJhaChrYW4pPyBmaWxlfGFkZCBmaWxlcz98c2VsZWN0IGZpbGVzP3xjaG9vc2UgZmlsZXM/
::B64:agent.js:fHBpbGloIGZpbGV8YnJvd3NlfHRlbHVzdXJpKVxiL2k7CmNvbnN0IFNVQk1JVF9CVE4gPSAvXlxzKihiZWdpbiB1cGxvYWR8c3RhcnQgdXBsb2FkfHVwbG9hZCggbm93fCBmaWxlcz8pP3x1bmdnYWgoIHNla2FyYW5nKT98bXVsYWkoIHVwbG9hZHwgdW5nZ2FoKT98
::B64:agent.js:a2lyaW18c2VuZHxzdWJtaXR8c2VsZXNhaXxkb25lfGxhbmp1dHxjb250aW51ZSlccyokL2k7Cgphc3luYyBmdW5jdGlvbiBmaW5kRmlsZUlucHV0QW55KHRpbWVvdXRNcyA9IDApIHsKICBjb25zdCBkZWFkbGluZSA9IERhdGUubm93KCkgKyB0aW1lb3V0TXM7CiAg
::B64:agent.js:ZG8gewogICAgZm9yIChjb25zdCBmciBvZiBwYWdlLmZyYW1lcygpKSB7CiAgICAgIGNvbnN0IGggPSBhd2FpdCBmci4kKCJpbnB1dFt0eXBlPWZpbGVdIikuY2F0Y2goKCkgPT4gbnVsbCk7CiAgICAgIGlmIChoKSByZXR1cm4gaDsKICAgIH0KICAgIGlmICh0aW1l
::B64:agent.js:b3V0TXMpIGF3YWl0IHNsZWVwKDIwMCk7CiAgfSB3aGlsZSAoRGF0ZS5ub3coKSA8IGRlYWRsaW5lKTsKICByZXR1cm4gbnVsbDsKfQoKYXN5bmMgZnVuY3Rpb24gaGFzTG9naW5Gb3JtKCkgewogIGZvciAoY29uc3QgZnIgb2YgcGFnZS5mcmFtZXMoKSkgewogICAg
::B64:agent.js:Y29uc3QgcHcgPSBhd2FpdCBmci4kKCJpbnB1dFt0eXBlPXBhc3N3b3JkXSIpLmNhdGNoKCgpID0+IG51bGwpOwogICAgaWYgKHB3ICYmIChhd2FpdCBwdy5pc1Zpc2libGUoKS5jYXRjaCgoKSA9PiBmYWxzZSkpKSByZXR1cm4gdHJ1ZTsKICB9CiAgcmV0dXJuIGZh
::B64:agent.js:bHNlOwp9Cgphc3luYyBmdW5jdGlvbiBjbGlja0J5VGV4dChyZSwgdGltZW91dCA9IDE1MDApIHsKICBjb25zdCBncm91cHMgPSBbcGFnZS5nZXRCeVJvbGUoImJ1dHRvbiIsIHsgbmFtZTogcmUgfSksIHBhZ2UuZ2V0QnlSb2xlKCJsaW5rIiwgeyBuYW1lOiByZSB9
::B64:agent.js:KSwgcGFnZS5nZXRCeVRleHQocmUpXTsKICBmb3IgKGNvbnN0IGcgb2YgZ3JvdXBzKSB7CiAgICBjb25zdCBuID0gTWF0aC5taW4oYXdhaXQgZy5jb3VudCgpLmNhdGNoKCgpID0+IDApLCA1KTsKICAgIGZvciAobGV0IGkgPSAwOyBpIDwgbjsgaSsrKSB7CiAgICAg
::B64:agent.js:IGNvbnN0IGVsID0gZy5udGgoaSk7CiAgICAgIGlmICghKGF3YWl0IGVsLmlzVmlzaWJsZSgpLmNhdGNoKCgpID0+IGZhbHNlKSkpIGNvbnRpbnVlOwogICAgICB0cnkgewogICAgICAgIGNvbnN0IGxhYmVsID0gKChhd2FpdCBlbC5pbm5lclRleHQoeyB0aW1lb3V0
::B64:agent.js:OiA0MDAgfSkuY2F0Y2goKCkgPT4gIiIpKSB8fCAiIikudHJpbSgpLnNsaWNlKDAsIDQwKTsKICAgICAgICBhd2FpdCBlbC5jbGljayh7IHRpbWVvdXQgfSk7CiAgICAgICAgcmV0dXJuIGxhYmVsIHx8ICIodG9tYm9sKSI7CiAgICAgIH0gY2F0Y2gge30KICAgIH0K
::B64:agent.js:ICB9CiAgcmV0dXJuICIiOwp9CgovLyBLbGlrIHRvbWJvbCAiVXBsb2FkIiBsYWx1IHRhbmdrYXAgZGlhbG9nIHBpbGloIGZpbGUgQVRBVSBpbnB1dCBmaWxlIHlhbmcgbXVuY3VsCmFzeW5jIGZ1bmN0aW9uIG9wZW5VcGxvYWRlcihxdWV1ZSkgewogIGNvbnN0IGdy
::B64:agent.js:b3VwcyA9IFtwYWdlLmdldEJ5Um9sZSgiYnV0dG9uIiwgeyBuYW1lOiBVUExPQURfQlROIH0pLCBwYWdlLmdldEJ5Um9sZSgibGluayIsIHsgbmFtZTogVVBMT0FEX0JUTiB9KSwgcGFnZS5nZXRCeVRleHQoVVBMT0FEX0JUTildOwogIGZvciAoY29uc3QgZyBvZiBn
::B64:agent.js:cm91cHMpIHsKICAgIGNvbnN0IG4gPSBNYXRoLm1pbihhd2FpdCBnLmNvdW50KCkuY2F0Y2goKCkgPT4gMCksIDQpOwogICAgZm9yIChsZXQgaSA9IDA7IGkgPCBuOyBpKyspIHsKICAgICAgY29uc3QgZWwgPSBnLm50aChpKTsKICAgICAgaWYgKCEoYXdhaXQgZWwu
::B64:agent.js:aXNWaXNpYmxlKCkuY2F0Y2goKCkgPT4gZmFsc2UpKSkgY29udGludWU7CiAgICAgIGNvbnN0IGNob29zZXJQID0gcGFnZS53YWl0Rm9yRXZlbnQoImZpbGVjaG9vc2VyIiwgeyB0aW1lb3V0OiAyMDAwIH0pLmNhdGNoKCgpID0+IG51bGwpOwogICAgICB0cnkgewog
::B64:agent.js:ICAgICAgIGF3YWl0IGVsLmNsaWNrKHsgdGltZW91dDogMTUwMCB9KTsKICAgICAgfSBjYXRjaCB7CiAgICAgICAgY29udGludWU7CiAgICAgIH0KICAgICAgY29uc3QgY2hvb3NlciA9IGF3YWl0IGNob29zZXJQOwogICAgICBpZiAoY2hvb3NlcikgewogICAgICAg
::B64:agent.js:IGNvbnN0IGJhdGNoID0gY2hvb3Nlci5pc011bHRpcGxlKCkgPyBxdWV1ZSA6IFtxdWV1ZVswXV07CiAgICAgICAgYXdhaXQgY2hvb3Nlci5zZXRGaWxlcyhiYXRjaCk7CiAgICAgICAgcmV0dXJuIHsgdXNlZDogYmF0Y2gubGVuZ3RoIH07CiAgICAgIH0KICAgICAg
::B64:agent.js:Y29uc3QgaW5wdXQgPSBhd2FpdCBmaW5kRmlsZUlucHV0QW55KDEyMDApOwogICAgICBpZiAoaW5wdXQpIHJldHVybiB7IGlucHV0IH07CiAgICB9CiAgfQogIHJldHVybiBudWxsOwp9CgovLyBNYXN1a2thbiBmaWxlIGtlIGhhbGFtYW4uIE1lbmdlbWJhbGlrYW4g
::B64:agent.js:anVtbGFoIGZpbGUgeWFuZyBkaXBha2FpICgwID0gZ2FnYWwpCmFzeW5jIGZ1bmN0aW9uIHByb3ZpZGVGaWxlcyhxdWV1ZSkgewogIGxldCBpbnB1dCA9IGF3YWl0IGZpbmRGaWxlSW5wdXRBbnkoMTIwMCk7CiAgaWYgKCFpbnB1dCkgewogICAgY29uc3QgciA9IGF3
::B64:agent.js:YWl0IG9wZW5VcGxvYWRlcihxdWV1ZSk7CiAgICBpZiAociAmJiByLnVzZWQpIHJldHVybiByLnVzZWQ7CiAgICBpbnB1dCA9IHIgJiYgci5pbnB1dDsKICB9CiAgaWYgKCFpbnB1dCkgcmV0dXJuIDA7CiAgY29uc3QgbXVsdGlwbGUgPSBhd2FpdCBpbnB1dC5ldmFs
::B64:agent.js:dWF0ZSgoZWwpID0+ICEhZWwubXVsdGlwbGUpLmNhdGNoKCgpID0+IGZhbHNlKTsKICBjb25zdCBiYXRjaCA9IG11bHRpcGxlID8gcXVldWUgOiBbcXVldWVbMF1dOwogIGF3YWl0IGlucHV0LnNldElucHV0RmlsZXMoYmF0Y2gpOwogIHJldHVybiBiYXRjaC5sZW5n
::B64:agent.js:dGg7Cn0KCmZ1bmN0aW9uIHRyYWNrVXBsb2FkcygpIHsKICBsZXQgcGVuZGluZyA9IDA7CiAgbGV0IHNlZW4gPSAwOwogIGNvbnN0IGlzVXAgPSAocikgPT4gWyJQT1NUIiwgIlBVVCIsICJQQVRDSCJdLmluY2x1ZGVzKHIubWV0aG9kKCkpOwogIGNvbnN0IG9uUmVx
::B64:agent.js:ID0gKHIpID0+IHsKICAgIGlmIChpc1VwKHIpKSB7CiAgICAgIHBlbmRpbmcrKzsKICAgICAgc2VlbisrOwogICAgfQogIH07CiAgY29uc3Qgb25Eb25lID0gKHIpID0+IHsKICAgIGlmIChpc1VwKHIpKSBwZW5kaW5nID0gTWF0aC5tYXgoMCwgcGVuZGluZyAtIDEp
::B64:agent.js:OwogIH07CiAgY29udGV4dC5vbigicmVxdWVzdCIsIG9uUmVxKTsKICBjb250ZXh0Lm9uKCJyZXF1ZXN0ZmluaXNoZWQiLCBvbkRvbmUpOwogIGNvbnRleHQub24oInJlcXVlc3RmYWlsZWQiLCBvbkRvbmUpOwogIHJldHVybiB7CiAgICBnZXQgcGVuZGluZygpIHsK
::B64:agent.js:ICAgICAgcmV0dXJuIHBlbmRpbmc7CiAgICB9LAogICAgZ2V0IHNlZW4oKSB7CiAgICAgIHJldHVybiBzZWVuOwogICAgfSwKICAgIHN0b3AoKSB7CiAgICAgIGNvbnRleHQub2ZmKCJyZXF1ZXN0Iiwgb25SZXEpOwogICAgICBjb250ZXh0Lm9mZigicmVxdWVzdGZp
::B64:agent.js:bmlzaGVkIiwgb25Eb25lKTsKICAgICAgY29udGV4dC5vZmYoInJlcXVlc3RmYWlsZWQiLCBvbkRvbmUpOwogICAgfSwKICB9Owp9CgovLyB0cnVlID0gc2VsZXNhaSwgc3RyaW5nID0gc2VsZXNhaSBkZW5nYW4gY2F0YXRhbiwgZmFsc2UgPSB3YWt0dSBoYWJpcwph
::B64:agent.js:c3luYyBmdW5jdGlvbiB3YWl0VXBsb2FkRG9uZSh0ciwgbWF4TXMpIHsKICBjb25zdCB0MCA9IERhdGUubm93KCk7CiAgbGV0IHF1aWV0ID0gMDsKICB3aGlsZSAoRGF0ZS5ub3coKSAtIHQwIDwgbWF4TXMpIHsKICAgIGF3YWl0IHNsZWVwKDYwMCk7CiAgICBjb25z
::B64:agent.js:dCBidXN5ID0gYXdhaXQgcGFnZQogICAgICAuZXZhbHVhdGUoKCkgPT4gewogICAgICAgIGNvbnN0IHZpcyA9IChlKSA9PiBlLm9mZnNldFBhcmVudCAhPT0gbnVsbDsKICAgICAgICBjb25zdCBiYXJzID0gWy4uLmRvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoInBy
::B64:agent.js:b2dyZXNzLCBbcm9sZT1wcm9ncmVzc2Jhcl0iKV0uZmlsdGVyKHZpcyk7CiAgICAgICAgY29uc3QgdCA9IGRvY3VtZW50LmJvZHkgPyBkb2N1bWVudC5ib2R5LmlubmVyVGV4dCA6ICIiOwogICAgICAgIGNvbnN0IGluUHJvZ3Jlc3MgPSAvXGIodXBsb2FkaW5nfG1l
::B64:agent.js:bmd1bmdnYWh8c2VkYW5nIG1lbmd1bmdnYWh8dXBsb2FkIGluIHByb2dyZXNzfG1lbXByb3Nlc3xwcm9jZXNzaW5nKVxiL2kudGVzdCh0KTsKICAgICAgICBjb25zdCB1bmZpbmlzaGVkID0gYmFycy5zb21lKChiKSA9PiB7CiAgICAgICAgICBjb25zdCB2ID0gYi5n
::B64:agent.js:ZXRBdHRyaWJ1dGUoImFyaWEtdmFsdWVub3ciKSA/PyBiLnZhbHVlOwogICAgICAgICAgY29uc3QgbXggPSBiLmdldEF0dHJpYnV0ZSgiYXJpYS12YWx1ZW1heCIpID8/IGIubWF4ID8/IDEwMDsKICAgICAgICAgIHJldHVybiB2ID09IG51bGwgfHwgTnVtYmVyKHYp
::B64:agent.js:IDwgTnVtYmVyKG14KTsKICAgICAgICB9KTsKICAgICAgICByZXR1cm4gdW5maW5pc2hlZCB8fCBpblByb2dyZXNzOwogICAgICB9KQogICAgICAuY2F0Y2goKCkgPT4gZmFsc2UpOwogICAgaWYgKHRyLnBlbmRpbmcgPT09IDAgJiYgIWJ1c3kpIHsKICAgICAgcXVp
::B64:agent.js:ZXQrKzsKICAgICAgaWYgKHF1aWV0ID49IDMgJiYgdHIuc2VlbiA+IDApIHJldHVybiB0cnVlOwogICAgICBpZiAocXVpZXQgPj0gOCkgcmV0dXJuIHRyLnNlZW4gPiAwID8gdHJ1ZSA6ICJ0aWRhayBhZGEgYWt0aXZpdGFzIHVwbG9hZCB0ZXJkZXRla3NpLCBwZXJp
::B64:agent.js:a3NhIGhhbGFtYW4iOwogICAgfSBlbHNlIHsKICAgICAgcXVpZXQgPSAwOwogICAgfQogIH0KICByZXR1cm4gZmFsc2U7Cn0KCi8vIEZvbGRlciBkaWtpcmltIHNlYmFnYWkgemlwLiBQYWthaSB0YXIgYmF3YWFuIFdpbmRvd3MgKGNlcGF0KTsgY2FkYW5nYW46IENv
::B64:agent.js:bXByZXNzLUFyY2hpdmUKYXN5bmMgZnVuY3Rpb24gemlwRm9yVXBsb2FkKGRpcikgewogIGNvbnN0IHppcCA9IHBhdGguam9pbihvcy50bXBkaXIoKSwgcGF0aC5iYXNlbmFtZShkaXIpICsgIi56aXAiKTsKICB0cnkgewogICAgZnMucm1TeW5jKHppcCwgeyBmb3Jj
::B64:agent.js:ZTogdHJ1ZSB9KTsKICB9IGNhdGNoIHt9CiAgY29uc3QgdmlhVGFyID0gYXdhaXQgbmV3IFByb21pc2UoKHJlc29sdmUpID0+IHsKICAgIGV4ZWNGaWxlKCJ0YXIiLCBbIi1hIiwgIi1jIiwgIi1mIiwgemlwLCAiLUMiLCBwYXRoLmRpcm5hbWUoZGlyKSwgcGF0aC5i
::B64:agent.js:YXNlbmFtZShkaXIpXSwgeyB0aW1lb3V0OiA5MDAwMDAgfSwgKGVycikgPT4gcmVzb2x2ZSghZXJyKSk7CiAgfSk7CiAgaWYgKCF2aWFUYXIpIHsKICAgIGF3YWl0IHBzKCJDb21wcmVzcy1BcmNoaXZlIC1MaXRlcmFsUGF0aCAkZW52OlNSQyAtRGVzdGluYXRpb25Q
::B64:agent.js:YXRoICRlbnY6REVTVCAtRm9yY2UiLCB7IFNSQzogZGlyLCBERVNUOiB6aXAgfSwgOTAwMDAwKTsKICB9CiAgcmV0dXJuIHppcDsKfQoKZnVuY3Rpb24gcmVjZW50TGlzdChkaXIsIGNvdW50ID0gMTApIHsKICBjb25zdCBiYWQgPSAvXC4oY3Jkb3dubG9hZHx0bXB8
::B64:agent.js:cGFydHxkb3dubG9hZHxwYXJ0aWFsKSQvaTsKICBjb25zdCBpdGVtcyA9IFtdOwogIGZvciAoY29uc3QgZSBvZiBmcy5yZWFkZGlyU3luYyhkaXIsIHsgd2l0aEZpbGVUeXBlczogdHJ1ZSB9KSkgewogICAgaWYgKCFlLmlzRmlsZSgpIHx8IGJhZC50ZXN0KGUubmFt
::B64:agent.js:ZSkpIGNvbnRpbnVlOwogICAgY29uc3QgZiA9IHBhdGguam9pbihkaXIsIGUubmFtZSk7CiAgICB0cnkgewogICAgICBjb25zdCBzdCA9IGZzLnN0YXRTeW5jKGYpOwogICAgICBpdGVtcy5wdXNoKHsgZiwgdDogc3QubXRpbWVNcywgczogc3Quc2l6ZSB9KTsKICAg
::B64:agent.js:IH0gY2F0Y2gge30KICB9CiAgcmV0dXJuIGl0ZW1zLnNvcnQoKGEsIGIpID0+IGIudCAtIGEudCkuc2xpY2UoMCwgTWF0aC5taW4oTWF0aC5tYXgoTnVtYmVyKGNvdW50KSB8fCAxMCwgMSksIDUwKSk7Cn0KCmNvbnN0IHRpbWVycyA9IFtdOwpjb25zdCBTQUZFX1BB
::B64:agent.js:UkFMTEVMID0gbmV3IFNldChbCiAgImZpbmRfZm9sZGVyIiwgImZpbmRfZmlsZSIsICJsaXN0X2RpciIsICJyZWFkX3RleHRfZmlsZSIsICJzeXN0ZW1faW5mbyIsICJub3ciLCAiY2xpcGJvYXJkX2dldCIsCiAgImxpc3RfdGFicyIsICJsaXN0X3dpbmRvd3MiLCAi
::B64:agent.js:cmVjZW50X2ZpbGVzIiwgInNlYXJjaF90ZXh0IiwgImxpc3RfZmlsZXMiLApdKTsKCmNvbnN0IGltcGwgPSB7CiAgLy8gLS0tIERlc2t0b3A6IGZpbGUgJiBmb2xkZXIgLS0tCiAgZmluZF9mb2xkZXI6IGFzeW5jICh7IG5hbWUgfSkgPT4gc2VhcmNoRXZlcnl3aGVy
::B64:agent.js:ZShuYW1lLCBmYWxzZSksCgogIGZpbmRfZmlsZTogYXN5bmMgKHsgbmFtZSB9KSA9PiBzZWFyY2hFdmVyeXdoZXJlKG5hbWUsIHRydWUpLAoKICBsaXN0X2RpcjogYXN5bmMgKHsgcGF0aDogcCB9KSA9PiB7CiAgICBjb25zdCBpdGVtcyA9IGZzLnJlYWRkaXJTeW5j
::B64:agent.js:KHAsIHsgd2l0aEZpbGVUeXBlczogdHJ1ZSB9KS5zbGljZSgwLCAxMDApOwogICAgcmV0dXJuIGl0ZW1zLm1hcCgoZSkgPT4gKGUuaXNEaXJlY3RvcnkoKSA/ICJbRElSXSAiIDogIltGSUxFXSAiKSArIGUubmFtZSkuam9pbigiXG4iKSB8fCAiKGtvc29uZykiOwog
::B64:agent.js:IH0sCgogIG9wZW5fcGF0aDogYXN5bmMgKHsgdGFyZ2V0IH0pID0+IHsKICAgIGlmICghKGF3YWl0IGFzayhgQnVrYTogJHt0YXJnZXR9YCkpKSByZXR1cm4gIkRpYmF0YWxrYW4gdXNlciI7CiAgICBhd2FpdCBwcygiU3RhcnQtUHJvY2VzcyAtRmlsZVBhdGggJGVu
::B64:agent.js:djpUQVJHRVQiLCB7IFRBUkdFVDogU3RyaW5nKHRhcmdldCkgfSk7CiAgICBhd2FpdCBzbGVlcCg4MDApOwogICAgcmV0dXJuICJvaywgZGlidWthIjsKICB9LAoKICAvLyAtLS0gRGVza3RvcDogbGF5YXIsIG1vdXNlLCBrZXlib2FyZCAtLS0KICBzY3JlZW5zaG90
::B64:agent.js:OiBhc3luYyAoKSA9PiB7CiAgICBjb25zdCBvdXQgPSBwYXRoLnJlc29sdmUoInNjcmVlbi5wbmciKTsKICAgIGNvbnN0IHIgPSBhd2FpdCBwcygKICAgICAgUFNfSEVBRCArCiAgICAgICAgYAokYiA9IFtTeXN0ZW0uV2luZG93cy5Gb3Jtcy5TY3JlZW5dOjpQcmlt
::B64:agent.js:YXJ5U2NyZWVuLkJvdW5kcwokYm1wID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5CaXRtYXAgJGIuV2lkdGgsICRiLkhlaWdodAokZyA9IFtTeXN0ZW0uRHJhd2luZy5HcmFwaGljc106OkZyb21JbWFnZSgkYm1wKQokZy5Db3B5RnJvbVNjcmVlbigkYi5YLCAk
::B64:agent.js:Yi5ZLCAwLCAwLCAkYm1wLlNpemUpCiRudyA9IFtNYXRoXTo6TWluKDEyODAsICRiLldpZHRoKQokbmggPSBbaW50XSgkYi5IZWlnaHQgKiAkbncgLyAkYi5XaWR0aCkKJHNtYWxsID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5CaXRtYXAgJGJtcCwgJG53LCAk
::B64:agent.js:bmgKJHNtYWxsLlNhdmUoJGVudjpPVVQsIFtTeXN0ZW0uRHJhd2luZy5JbWFnaW5nLkltYWdlRm9ybWF0XTo6UG5nKQpXcml0ZS1PdXRwdXQgIiQoJGIuV2lkdGgpLCRudywkbmgiCmAsCiAgICAgIHsgT1VUOiBvdXQgfQogICAgKTsKICAgIGNvbnN0IFt3LCBudywg
::B64:agent.js:bmhdID0gci5zcGxpdCgiXG4iKS5wb3AoKS5zcGxpdCgiLCIpLm1hcChOdW1iZXIpOwogICAgc2NhbGUgPSB3IC8gbnc7CiAgICBwZW5kaW5nSW1hZ2VzLnB1c2goZnMucmVhZEZpbGVTeW5jKG91dCkudG9TdHJpbmcoImJhc2U2NCIpKTsKICAgIHJldHVybiBgU2Ny
::B64:agent.js:ZWVuc2hvdCBkaWFtYmlsICgke253fXgke25ofSkuIEdhbWJhcm55YSBhZGEgZGkgcGVzYW4gYmVyaWt1dG55YS4gUGFrYWkga29vcmRpbmF0IGRhcmkgZ2FtYmFyIGl0dS5gOwogIH0sCgogIGNsaWNrX3NjcmVlbjogYXN5bmMgKHsgeCwgeSwgYnV0dG9uID0gImxl
::B64:agent.js:ZnQiLCBkb3VibGUgPSBmYWxzZSB9KSA9PiB7CiAgICBjb25zdCByeCA9IE1hdGgucm91bmQoTnVtYmVyKHgpICogc2NhbGUpOwogICAgY29uc3QgcnkgPSBNYXRoLnJvdW5kKE51bWJlcih5KSAqIHNjYWxlKTsKICAgIGNvbnN0IGRibCA9IGRvdWJsZSA9PT0gdHJ1
::B64:agent.js:ZSB8fCBkb3VibGUgPT09ICJ0cnVlIjsKICAgIGlmICghKGF3YWl0IGFzayhgJHtkYmwgPyAiRG91YmxlLWtsaWsiIDogIktsaWsifSAke2J1dHRvbn0gZGkgKCR7eH0sJHt5fSlgKSkpIHJldHVybiAiRGliYXRhbGthbiB1c2VyIjsKICAgIGF3YWl0IHBzKAogICAg
::B64:agent.js:ICBQU19IRUFEICsKICAgICAgICBgCltXXTo6U2V0Q3Vyc29yUG9zKFtpbnRdJGVudjpYLCBbaW50XSRlbnY6WSkgfCBPdXQtTnVsbApTdGFydC1TbGVlcCAtTWlsbGlzZWNvbmRzIDE1MAokZG93biA9IDI7ICR1cCA9IDQKaWYgKCRlbnY6QlROIC1lcSAicmlnaHQi
::B64:agent.js:KSB7ICRkb3duID0gODsgJHVwID0gMTYgfQpmb3IgKCRpID0gMDsgJGkgLWx0IFtpbnRdJGVudjpDT1VOVDsgJGkrKykgewogIFtXXTo6bW91c2VfZXZlbnQoJGRvd24sIDAsIDAsIDAsIFtVSW50UHRyXTo6WmVybykKICBbV106Om1vdXNlX2V2ZW50KCR1cCwgMCwg
::B64:agent.js:MCwgMCwgW1VJbnRQdHJdOjpaZXJvKQogIFN0YXJ0LVNsZWVwIC1NaWxsaXNlY29uZHMgODAKfQpgLAogICAgICB7IFg6IFN0cmluZyhyeCksIFk6IFN0cmluZyhyeSksIEJUTjogU3RyaW5nKGJ1dHRvbiksIENPVU5UOiBkYmwgPyAiMiIgOiAiMSIgfQogICAgKTsK
::B64:agent.js:ICAgIGF3YWl0IHNsZWVwKDM1MCk7CiAgICByZXR1cm4gIm9rLCBkaWtsaWsiOwogIH0sCgogIHNjcm9sbF9zY3JlZW46IGFzeW5jICh7IGFtb3VudCB9KSA9PiB7CiAgICBjb25zdCBkZWx0YSA9IC0xMjAgKiBNYXRoLnJvdW5kKE51bWJlcihhbW91bnQpKTsgLy8g
::B64:agent.js:cG9zaXRpZiA9IHR1cnVuCiAgICBpZiAoIShhd2FpdCBhc2soYFNjcm9sbCAke2Ftb3VudCA+IDAgPyAidHVydW4iIDogIm5haWsifSAke01hdGguYWJzKGFtb3VudCl9eGApKSkgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgYXdhaXQgcHMoUFNfSEVBRCAr
::B64:agent.js:IGBbV106Om1vdXNlX2V2ZW50KDB4MDgwMCwgMCwgMCwgW2ludF0kZW52OkQsIFtVSW50UHRyXTo6WmVybylgLCB7IEQ6IFN0cmluZyhkZWx0YSkgfSk7CiAgICBhd2FpdCBzbGVlcCgyNTApOwogICAgcmV0dXJuICJvayI7CiAgfSwKCiAgdHlwZV9kZXNrdG9wOiBh
::B64:agent.js:c3luYyAoeyB0ZXh0IH0pID0+IHsKICAgIGlmICghKGF3YWl0IGFzayhgS2V0aWs6ICIke1N0cmluZyh0ZXh0KS5zbGljZSgwLCA2MCl9ImApKSkgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgYXdhaXQgcHMoCiAgICAgIFBTX0hFQUQgKwogICAgICAgIGAK
::B64:agent.js:U2V0LUNsaXBib2FyZCAtVmFsdWUgJGVudjpUWFQKU3RhcnQtU2xlZXAgLU1pbGxpc2Vjb25kcyAxNTAKW1N5c3RlbS5XaW5kb3dzLkZvcm1zLlNlbmRLZXlzXTo6U2VuZFdhaXQoIl52IikKYCwKICAgICAgeyBUWFQ6IFN0cmluZyh0ZXh0KSB9CiAgICApOwogICAg
::B64:agent.js:YXdhaXQgc2xlZXAoMjUwKTsKICAgIHJldHVybiAib2ssIGRpa2V0aWsiOwogIH0sCgogIHByZXNzX2tleXM6IGFzeW5jICh7IGtleXMgfSkgPT4gewogICAgaWYgKCEoYXdhaXQgYXNrKGBUZWthbiB0b21ib2w6ICR7a2V5c31gKSkpIHJldHVybiAiRGliYXRhbGth
::B64:agent.js:biB1c2VyIjsKICAgIGF3YWl0IHBzKFBTX0hFQUQgKyBgW1N5c3RlbS5XaW5kb3dzLkZvcm1zLlNlbmRLZXlzXTo6U2VuZFdhaXQoJGVudjpLRVlTKWAsIHsgS0VZUzogU3RyaW5nKGtleXMpIH0pOwogICAgYXdhaXQgc2xlZXAoMjUwKTsKICAgIHJldHVybiAib2si
::B64:agent.js:OwogIH0sCgogIHdhaXQ6IGFzeW5jICh7IHNlY29uZHMgfSkgPT4gewogICAgYXdhaXQgc2xlZXAoTWF0aC5taW4oTnVtYmVyKHNlY29uZHMpIHx8IDEsIDE1KSAqIDEwMDApOwogICAgcmV0dXJuICJvayI7CiAgfSwKCiAgLy8gLS0tIEJyb3dzZXIgKFBsYXl3cmln
::B64:agent.js:aHQpIC0tLQogIGxpc3RfZmlsZXM6IGFzeW5jICgpID0+IGZzLnJlYWRkaXJTeW5jKFNBRkVfRElSKS5qb2luKCJcbiIpIHx8ICIoZm9sZGVyIHVwbG9hZCBrb3NvbmcpIiwKCiAgb3Blbl91cmw6IGFzeW5jICh7IHVybCwgbmV3X3RhYiA9IGZhbHNlIH0pID0+IHsK
::B64:agent.js:ICAgIGlmIChpc1RydWUobmV3X3RhYikpIHBhZ2UgPSBhd2FpdCBjb250ZXh0Lm5ld1BhZ2UoKTsKICAgIGF3YWl0IHBhZ2UuYnJpbmdUb0Zyb250KCk7CiAgICBhd2FpdCBwYWdlLmdvdG8oZml4VXJsKHVybCksIHsgd2FpdFVudGlsOiAiZG9tY29udGVudGxvYWRl
::B64:agent.js:ZCIgfSk7CiAgICByZXR1cm4gIlRlcmJ1a2E6ICIgKyAoYXdhaXQgcGFnZS50aXRsZSgpKSArIChpc1RydWUobmV3X3RhYikgPyAiIChkaSB0YWIgYmFydSkiIDogIiIpOwogIH0sCgogIC8vIC0tLSBUYWIgLS0tCiAgbGlzdF90YWJzOiBhc3luYyAoKSA9PiB0YWJz
::B64:agent.js:U3VtbWFyeSgpLAoKICBuZXdfdGFiOiBhc3luYyAoeyB1cmwgfSkgPT4gewogICAgcGFnZSA9IGF3YWl0IGNvbnRleHQubmV3UGFnZSgpOwogICAgYXdhaXQgcGFnZS5icmluZ1RvRnJvbnQoKTsKICAgIGlmICh1cmwpIGF3YWl0IHBhZ2UuZ290byhmaXhVcmwodXJs
::B64:agent.js:KSwgeyB3YWl0VW50aWw6ICJkb21jb250ZW50bG9hZGVkIiB9KTsKICAgIHJldHVybiAiVGFiIGJhcnUgZGlidWthIGRhbiBqYWRpIHRhYiBha3RpZi5cbiIgKyAoYXdhaXQgdGFic1N1bW1hcnkoKSk7CiAgfSwKCiAgb3Blbl91cmxzOiBhc3luYyAoeyB1cmxzIH0p
::B64:agent.js:ID0+IHsKICAgIGNvbnN0IGxpc3QgPSAoQXJyYXkuaXNBcnJheSh1cmxzKSA/IHVybHMgOiBTdHJpbmcodXJscykuc3BsaXQoL1tcbiw7fF0rLykpCiAgICAgIC5tYXAoKHgpID0+IFN0cmluZyh4KS50cmltKCkpCiAgICAgIC5maWx0ZXIoQm9vbGVhbikKICAgICAg
::B64:agent.js:LnNsaWNlKDAsIDEwKTsKICAgIGlmICghbGlzdC5sZW5ndGgpIHRocm93IG5ldyBFcnJvcigiVGlkYWsgYWRhIFVSTCIpOwogICAgY29uc3QgZ2FnYWwgPSBbXTsKICAgIGZvciAoY29uc3QgdSBvZiBsaXN0KSB7CiAgICAgIHBhZ2UgPSBhd2FpdCBjb250ZXh0Lm5l
::B64:agent.js:d1BhZ2UoKTsKICAgICAgdHJ5IHsKICAgICAgICBhd2FpdCBwYWdlLmdvdG8oZml4VXJsKHUpLCB7IHdhaXRVbnRpbDogImRvbWNvbnRlbnRsb2FkZWQiLCB0aW1lb3V0OiAzMDAwMCB9KTsKICAgICAgfSBjYXRjaCAoZSkgewogICAgICAgIGdhZ2FsLnB1c2godSk7
::B64:agent.js:CiAgICAgIH0KICAgIH0KICAgIHJldHVybiBgJHtsaXN0Lmxlbmd0aCAtIGdhZ2FsLmxlbmd0aH0gdGFiIGRpYnVrYSR7Z2FnYWwubGVuZ3RoID8gYCwgZ2FnYWw6ICR7Z2FnYWwuam9pbigiLCAiKX1gIDogIiJ9LlxuYCArIChhd2FpdCB0YWJzU3VtbWFyeSgpKTsK
::B64:agent.js:ICB9LAoKICBzd2l0Y2hfdGFiOiBhc3luYyAoeyBpbmRleCwgbWF0Y2ggfSkgPT4gewogICAgY29uc3QgYWxsID0gbGl2ZVBhZ2VzKCk7CiAgICBsZXQgdGFyZ2V0OwogICAgaWYgKG1hdGNoKSB7CiAgICAgIGNvbnN0IHEgPSBTdHJpbmcobWF0Y2gpLnRvTG93ZXJD
::B64:agent.js:YXNlKCk7CiAgICAgIGZvciAoY29uc3QgeCBvZiBhbGwpIHsKICAgICAgICBjb25zdCB0ID0gKChhd2FpdCB4LnRpdGxlKCkuY2F0Y2goKCkgPT4gIiIpKSArICIgIiArIHgudXJsKCkpLnRvTG93ZXJDYXNlKCk7CiAgICAgICAgaWYgKHQuaW5jbHVkZXMocSkpIHsK
::B64:agent.js:ICAgICAgICAgIHRhcmdldCA9IHg7CiAgICAgICAgICBicmVhazsKICAgICAgICB9CiAgICAgIH0KICAgIH0gZWxzZSB7CiAgICAgIHRhcmdldCA9IHBpY2tUYWIoYWxsLCBpbmRleCk7CiAgICB9CiAgICBpZiAoIXRhcmdldCkgdGhyb3cgbmV3IEVycm9yKCJUYWIg
::B64:agent.js:dGlkYWsgZGl0ZW11a2FuLlxuIiArIChhd2FpdCB0YWJzU3VtbWFyeSgpKSk7CiAgICBwYWdlID0gdGFyZ2V0OwogICAgYXdhaXQgcGFnZS5icmluZ1RvRnJvbnQoKTsKICAgIHJldHVybiAiVGFiIGFrdGlmIHNla2FyYW5nOiAiICsgKGF3YWl0IHBhZ2UudGl0bGUo
::B64:agent.js:KS5jYXRjaCgoKSA9PiAiIikpICsgIiB8ICIgKyBwYWdlLnVybCgpOwogIH0sCgogIGNsb3NlX3RhYjogYXN5bmMgKHsgaW5kZXggfSkgPT4gewogICAgY29uc3QgYWxsID0gbGl2ZVBhZ2VzKCk7CiAgICBjb25zdCB0YXJnZXQgPSBpbmRleCA/IHBpY2tUYWIoYWxs
::B64:agent.js:LCBpbmRleCkgOiBwYWdlOwogICAgaWYgKCF0YXJnZXQpIHRocm93IG5ldyBFcnJvcigiVGFiIHRpZGFrIGRpdGVtdWthbi5cbiIgKyAoYXdhaXQgdGFic1N1bW1hcnkoKSkpOwogICAgaWYgKGFsbC5sZW5ndGggPT09IDEpIHRocm93IG5ldyBFcnJvcigiSW5pIHRh
::B64:agent.js:YiB0ZXJha2hpciwgdGlkYWsgZGl0dXR1cCBhZ2FyIGJyb3dzZXIgdGV0YXAgdGVyYnVrYSIpOwogICAgY29uc3QganVkdWwgPSBhd2FpdCB0YXJnZXQudGl0bGUoKS5jYXRjaCgoKSA9PiAiIik7CiAgICBpZiAoIShhd2FpdCBhc2soYFR1dHVwIHRhYjogJHtqdWR1
::B64:agent.js:bH1gKSkpIHJldHVybiAiRGliYXRhbGthbiB1c2VyIjsKICAgIGNvbnN0IHdhc0FjdGl2ZSA9IHRhcmdldCA9PT0gcGFnZTsKICAgIGF3YWl0IHRhcmdldC5jbG9zZSgpOwogICAgaWYgKHdhc0FjdGl2ZSkgewogICAgICBwYWdlID0gbGl2ZVBhZ2VzKCkuYXQoLTEp
::B64:agent.js:OwogICAgICBhd2FpdCBwYWdlLmJyaW5nVG9Gcm9udCgpOwogICAgfQogICAgcmV0dXJuICJvay5cbiIgKyAoYXdhaXQgdGFic1N1bW1hcnkoKSk7CiAgfSwKCiAgaW5zcGVjdF9wYWdlOiBhc3luYyAoKSA9PiB7CiAgICBjb25zdCBpdGVtcyA9IGF3YWl0IHBhZ2Uu
::B64:agent.js:ZXZhbHVhdGUoKCkgPT4KICAgICAgWy4uLmRvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoImlucHV0LCBidXR0b24sIGEsIHRleHRhcmVhLCBzZWxlY3QiKV0KICAgICAgICAuc2xpY2UoMCwgNjApCiAgICAgICAgLm1hcCgoZSkgPT4gKHsKICAgICAgICAgIHRhZzog
::B64:agent.js:ZS50YWdOYW1lLnRvTG93ZXJDYXNlKCksCiAgICAgICAgICBpZDogZS5pZCB8fCB1bmRlZmluZWQsCiAgICAgICAgICBuYW1lOiBlLmdldEF0dHJpYnV0ZSgibmFtZSIpIHx8IHVuZGVmaW5lZCwKICAgICAgICAgIHR5cGU6IGUuZ2V0QXR0cmlidXRlKCJ0eXBlIikg
::B64:agent.js:fHwgdW5kZWZpbmVkLAogICAgICAgICAgdGV4dDogKGUuaW5uZXJUZXh0IHx8IGUudmFsdWUgfHwgZS5wbGFjZWhvbGRlciB8fCAiIikudHJpbSgpLnNsaWNlKDAsIDQwKSB8fCB1bmRlZmluZWQsCiAgICAgICAgfSkpCiAgICApOwogICAgcmV0dXJuIEpTT04uc3Ry
::B64:agent.js:aW5naWZ5KGl0ZW1zKTsKICB9LAoKICB5b3V0dWJlX3BsYXk6IGFzeW5jICh7IHF1ZXJ5LCBwaWNrID0gMSwgbmV3X3RhYiA9IGZhbHNlIH0pID0+IHsKICAgIGlmIChpc1RydWUobmV3X3RhYikpIHBhZ2UgPSBhd2FpdCBjb250ZXh0Lm5ld1BhZ2UoKTsKICAgIGF3
::B64:agent.js:YWl0IHBhZ2UuYnJpbmdUb0Zyb250KCk7CiAgICBsZXQgbGlzdCA9IFtdOwogICAgdHJ5IHsKICAgICAgbGlzdCA9IChhd2FpdCB5dFNlYXJjaEZhc3QoU3RyaW5nKHF1ZXJ5KSkpLnNsaWNlKDAsIDUpLm1hcCgodikgPT4gKHsKICAgICAgICB0aXRsZTogdi50aXRs
::B64:agent.js:ZSArICh2LmNoYW5uZWwgPyAiIHwgIiArIHYuY2hhbm5lbCA6ICIiKSwKICAgICAgICBocmVmOiAiaHR0cHM6Ly93d3cueW91dHViZS5jb20vd2F0Y2g/dj0iICsgdi5pZCwKICAgICAgfSkpOwogICAgfSBjYXRjaCB7fQogICAgaWYgKCFsaXN0Lmxlbmd0aCkgewog
::B64:agent.js:ICAgICBhd2FpdCBwYWdlLmdvdG8oImh0dHBzOi8vd3d3LnlvdXR1YmUuY29tL3Jlc3VsdHM/c2VhcmNoX3F1ZXJ5PSIgKyBlbmNvZGVVUklDb21wb25lbnQoU3RyaW5nKHF1ZXJ5KSksIHsKICAgICAgICB3YWl0VW50aWw6ICJkb21jb250ZW50bG9hZGVkIiwKICAg
::B64:agent.js:ICAgfSk7CiAgICAgIGF3YWl0IHBhZ2Uud2FpdEZvclNlbGVjdG9yKCJ5dGQtdmlkZW8tcmVuZGVyZXIgYSN2aWRlby10aXRsZSIsIHsgdGltZW91dDogMjAwMDAgfSk7CiAgICAgIGxpc3QgPSBhd2FpdCBwYWdlLiQkZXZhbCgieXRkLXZpZGVvLXJlbmRlcmVyIGEj
::B64:agent.js:dmlkZW8tdGl0bGUiLCAoZWxzKSA9PgogICAgICAgIGVscy5zbGljZSgwLCA1KS5tYXAoKGUpID0+ICh7IHRpdGxlOiBlLnRleHRDb250ZW50LnRyaW0oKSwgaHJlZjogZS5ocmVmIH0pKQogICAgICApOwogICAgfQogICAgaWYgKCFsaXN0Lmxlbmd0aCkgcmV0dXJu
::B64:agent.js:ICJUaWRhayBhZGEgaGFzaWwiOwogICAgY29uc3Qgc3RhcnQgPSBNYXRoLm1pbihNYXRoLm1heChOdW1iZXIocGljaykgfHwgMSwgMSksIGxpc3QubGVuZ3RoKSAtIDE7CiAgICBjb25zdCBvcmRlciA9IFtzdGFydCwgLi4ubGlzdC5tYXAoKF8sIGkpID0+IGkpLmZp
::B64:agent.js:bHRlcigoaSkgPT4gaSAhPT0gc3RhcnQpXS5zbGljZSgwLCAzKTsKICAgIGNvbnN0IG90aGVycyA9IGxpc3QubWFwKCh2LCBpKSA9PiBgJHtpICsgMX0uICR7di50aXRsZX1gKS5qb2luKCJcbiIpOwogICAgZm9yIChjb25zdCBpZHggb2Ygb3JkZXIpIHsKICAgICAg
::B64:agent.js:YXdhaXQgcGFnZS5nb3RvKGxpc3RbaWR4XS5ocmVmLCB7IHdhaXRVbnRpbDogImRvbWNvbnRlbnRsb2FkZWQiIH0pOwogICAgICBpZiAoYXdhaXQgZW5zdXJlUGxheWluZygpKSB7CiAgICAgICAgcmV0dXJuIGBNZW11dGFyICMke2lkeCArIDF9OiAke2xpc3RbaWR4
::B64:agent.js:XS50aXRsZX1cbkhhc2lsIHBlbmNhcmlhbjpcbiR7b3RoZXJzfWA7CiAgICAgIH0KICAgIH0KICAgIHJldHVybiAiVmlkZW8gZ2FnYWwgZGlwdXRhciAoWW91VHViZSBtZW5hbXBpbGthbiBlcnJvcikuIENvYmEgL2xvZ2luIGF0YXUganVkdWwgbGFpbi5cbkhhc2ls
::B64:agent.js:IHBlbmNhcmlhbjpcbiIgKyBvdGhlcnM7CiAgfSwKCiAgeW91dHViZV9jb250cm9sOiBhc3luYyAoeyBhY3Rpb24sIHNlY29uZHMgPSAxMCB9KSA9PiB7CiAgICBhd2FpdCBwYWdlLmJyaW5nVG9Gcm9udCgpOwogICAgcmV0dXJuIHBhZ2UuZXZhbHVhdGUoCiAgICAg
::B64:agent.js:ICh7IGEsIHMgfSkgPT4gewogICAgICAgIGNvbnN0IHYgPSBkb2N1bWVudC5xdWVyeVNlbGVjdG9yKCJ2aWRlbyIpOwogICAgICAgIGlmICghdikgcmV0dXJuICJUaWRhayBhZGEgdmlkZW8gZGkgaGFsYW1hbiBpbmkiOwogICAgICAgIGlmIChhID09PSAicGF1c2Ui
::B64:agent.js:KSB2LnBhdXNlKCk7CiAgICAgICAgZWxzZSBpZiAoYSA9PT0gInBsYXkiKSB2LnBsYXkoKTsKICAgICAgICBlbHNlIGlmIChhID09PSAidG9nZ2xlIikgKHYucGF1c2VkID8gdi5wbGF5KCkgOiB2LnBhdXNlKCkpOwogICAgICAgIGVsc2UgaWYgKGEgPT09ICJtdXRl
::B64:agent.js:Iikgdi5tdXRlZCA9IHRydWU7CiAgICAgICAgZWxzZSBpZiAoYSA9PT0gInVubXV0ZSIpIHYubXV0ZWQgPSBmYWxzZTsKICAgICAgICBlbHNlIGlmIChhID09PSAiZm9yd2FyZCIpIHYuY3VycmVudFRpbWUgKz0gczsKICAgICAgICBlbHNlIGlmIChhID09PSAiYmFj
::B64:agent.js:a3dhcmQiKSB2LmN1cnJlbnRUaW1lIC09IHM7CiAgICAgICAgZWxzZSBpZiAoYSA9PT0gIm5leHQiKSB7CiAgICAgICAgICBjb25zdCBiID0gZG9jdW1lbnQucXVlcnlTZWxlY3RvcigiLnl0cC1uZXh0LWJ1dHRvbiIpOwogICAgICAgICAgaWYgKCFiKSByZXR1cm4g
::B64:agent.js:IlRvbWJvbCBuZXh0IHRpZGFrIGFkYSI7CiAgICAgICAgICBiLmNsaWNrKCk7CiAgICAgICAgfSBlbHNlIGlmIChhID09PSAicHJldmlvdXMiKSB7CiAgICAgICAgICBjb25zdCBiID0gZG9jdW1lbnQucXVlcnlTZWxlY3RvcigiLnl0cC1wcmV2LWJ1dHRvbiIpOwog
::B64:agent.js:ICAgICAgICAgaWYgKGIgJiYgZ2V0Q29tcHV0ZWRTdHlsZShiKS5kaXNwbGF5ICE9PSAibm9uZSIpIGIuY2xpY2soKTsKICAgICAgICAgIGVsc2UgaGlzdG9yeS5iYWNrKCk7CiAgICAgICAgfSBlbHNlIGlmIChhID09PSAiZnVsbHNjcmVlbiIpIHsKICAgICAgICAg
::B64:agent.js:IGNvbnN0IGIgPSBkb2N1bWVudC5xdWVyeVNlbGVjdG9yKCIueXRwLWZ1bGxzY3JlZW4tYnV0dG9uIik7CiAgICAgICAgICBpZiAoYikgYi5jbGljaygpOwogICAgICAgIH0gZWxzZSByZXR1cm4gIkFrc2kgdGlkYWsgZGlrZW5hbC4gUGlsaWg6IHBsYXksIHBhdXNl
::B64:agent.js:LCB0b2dnbGUsIG11dGUsIHVubXV0ZSwgZm9yd2FyZCwgYmFja3dhcmQsIG5leHQsIHByZXZpb3VzLCBmdWxsc2NyZWVuIjsKICAgICAgICByZXR1cm4gIm9rIjsKICAgICAgfSwKICAgICAgeyBhOiBTdHJpbmcoYWN0aW9uKS50b0xvd2VyQ2FzZSgpLCBzOiBOdW1i
::B64:agent.js:ZXIoc2Vjb25kcykgfHwgMTAgfQogICAgKTsKICB9LAoKICAvLyAtLS0gV2ViIC0tLQogIHdlYl9zZWFyY2g6IGFzeW5jICh7IHF1ZXJ5LCBuZXdfdGFiID0gZmFsc2UgfSkgPT4gewogICAgaWYgKGlzVHJ1ZShuZXdfdGFiKSkgcGFnZSA9IGF3YWl0IGNvbnRleHQu
::B64:agent.js:bmV3UGFnZSgpOwogICAgYXdhaXQgcGFnZS5icmluZ1RvRnJvbnQoKTsKICAgIGF3YWl0IHBhZ2UuZ290bygiaHR0cHM6Ly9odG1sLmR1Y2tkdWNrZ28uY29tL2h0bWwvP3E9IiArIGVuY29kZVVSSUNvbXBvbmVudChTdHJpbmcocXVlcnkpKSwgewogICAgICB3YWl0
::B64:agent.js:VW50aWw6ICJkb21jb250ZW50bG9hZGVkIiwKICAgIH0pOwogICAgY29uc3Qgcm93cyA9IGF3YWl0IHBhZ2UuJCRldmFsKCIucmVzdWx0IiwgKGVscykgPT4KICAgICAgZWxzLnNsaWNlKDAsIDgpLm1hcCgoZSkgPT4gKHsKICAgICAgICB0aXRsZTogZS5xdWVyeVNl
::B64:agent.js:bGVjdG9yKCIucmVzdWx0X19hIik/LnRleHRDb250ZW50LnRyaW0oKSwKICAgICAgICB1cmw6IGUucXVlcnlTZWxlY3RvcigiLnJlc3VsdF9fYSIpPy5ocmVmLAogICAgICAgIHNuaXBwZXQ6IGUucXVlcnlTZWxlY3RvcigiLnJlc3VsdF9fc25pcHBldCIpPy50ZXh0
::B64:agent.js:Q29udGVudC50cmltKCksCiAgICAgIH0pKQogICAgKTsKICAgIGNvbnN0IHJlYWwgPSAodSkgPT4gewogICAgICB0cnkgewogICAgICAgIGNvbnN0IHggPSBuZXcgVVJMKHUpOwogICAgICAgIHJldHVybiB4LnNlYXJjaFBhcmFtcy5nZXQoInVkZGciKSB8fCB1Owog
::B64:agent.js:ICAgICB9IGNhdGNoIHsKICAgICAgICByZXR1cm4gdTsKICAgICAgfQogICAgfTsKICAgIGNvbnN0IG9rID0gcm93cy5maWx0ZXIoKHIpID0+IHIudGl0bGUpOwogICAgcmV0dXJuIG9rLmxlbmd0aCA/IG9rLm1hcCgociwgaSkgPT4gYCR7aSArIDF9LiAke3IudGl0
::B64:agent.js:bGV9XG4gICAke3JlYWwoci51cmwpfVxuICAgJHtyLnNuaXBwZXQgfHwgIiJ9YCkuam9pbigiXG4iKSA6ICJUaWRhayBhZGEgaGFzaWwiOwogIH0sCgogIHNjcm9sbF9wYWdlOiBhc3luYyAoeyBhbW91bnQgfSkgPT4gewogICAgYXdhaXQgcGFnZS5tb3VzZS53aGVl
::B64:agent.js:bCgwLCBNYXRoLnJvdW5kKE51bWJlcihhbW91bnQpIHx8IDEpICogNzAwKTsKICAgIGF3YWl0IHNsZWVwKDIwMCk7CiAgICByZXR1cm4gIm9rIjsKICB9LAoKICB3YWl0X2Zvcl91c2VyOiBhc3luYyAoeyBtZXNzYWdlIH0pID0+IHsKICAgIGF3YWl0IHBhZ2UuYnJp
::B64:agent.js:bmdUb0Zyb250KCkuY2F0Y2goKCkgPT4ge30pOwogICAgY29uc29sZS5sb2coYFxuW0JVVFVIIEJBTlRVQU4gS0FNVV0gJHttZXNzYWdlfWApOwogICAgYXdhaXQgcmwucXVlc3Rpb24oIlRla2FuIEVudGVyIGppa2Egc3VkYWggc2VsZXNhaS4uLiAiKTsKICAgIHJl
::B64:agent.js:dHVybiAiVXNlciBzdWRhaCBzZWxlc2FpIjsKICB9LAoKICBkb3dubG9hZF9maWxlOiBhc3luYyAoeyB1cmwsIGZpbGVuYW1lIH0pID0+IHsKICAgIGlmICghL15odHRwcz86XC9cLy9pLnRlc3QoU3RyaW5nKHVybCkpKSB0aHJvdyBuZXcgRXJyb3IoIlVSTCBoYXJ1
::B64:agent.js:cyBkaWF3YWxpIGh0dHA6Ly8gYXRhdSBodHRwczovLyIpOwogICAgY29uc3QgZ3Vlc3MgPSBkZWNvZGVVUklDb21wb25lbnQobmV3IFVSTCh1cmwpLnBhdGhuYW1lLnNwbGl0KCIvIikucG9wKCkgfHwgIiIpIHx8ICJkb3dubG9hZC5iaW4iOwogICAgY29uc3QgZGVz
::B64:agent.js:dCA9IHBhdGguam9pbihIT01FLCAiRG93bmxvYWRzIiwgcGF0aC5iYXNlbmFtZShTdHJpbmcoZmlsZW5hbWUgfHwgZ3Vlc3MpKSk7CiAgICBpZiAoIShhd2FpdCBhc2soYFVuZHVoICR7dXJsfSAga2UgICR7ZGVzdH1gKSkpIHJldHVybiAiRGliYXRhbGthbiB1c2Vy
::B64:agent.js:IjsKICAgIGNvbnN0IHJlcyA9IGF3YWl0IGZldGNoKHVybCwgeyByZWRpcmVjdDogImZvbGxvdyIsIHNpZ25hbDogQWJvcnRTaWduYWwudGltZW91dCgxMCAqIDYwICogMTAwMCkgfSk7CiAgICBpZiAoIXJlcy5vaykgdGhyb3cgbmV3IEVycm9yKCJIVFRQICIgKyBy
::B64:agent.js:ZXMuc3RhdHVzKTsKICAgIGF3YWl0IHBpcGVsaW5lKFJlYWRhYmxlLmZyb21XZWIocmVzLmJvZHkpLCBmcy5jcmVhdGVXcml0ZVN0cmVhbShkZXN0KSk7CiAgICByZXR1cm4gYG9rLCB0ZXJzaW1wYW46ICR7ZGVzdH0gKCR7ZnMuc3RhdFN5bmMoZGVzdCkuc2l6ZX0g
::B64:agent.js:Ynl0ZSlgOwogIH0sCgogIC8vIC0tLSBQQzogaW5mbywgbWVkaWEsIGNsaXBib2FyZCwgamVuZGVsYSAtLS0KICBub3c6IGFzeW5jICgpID0+IG5ldyBEYXRlKCkudG9Mb2NhbGVTdHJpbmcoImlkLUlEIiwgeyBkYXRlU3R5bGU6ICJmdWxsIiwgdGltZVN0eWxlOiAi
::B64:agent.js:bG9uZyIgfSksCgogIHN5c3RlbV9pbmZvOiBhc3luYyAoKSA9PgogICAgcHMoYAokb3MgPSBHZXQtQ2ltSW5zdGFuY2UgV2luMzJfT3BlcmF0aW5nU3lzdGVtCiRjcHUgPSBHZXQtQ2ltSW5zdGFuY2UgV2luMzJfUHJvY2Vzc29yIHwgU2VsZWN0LU9iamVjdCAtRmly
::B64:agent.js:c3QgMQokYmF0ID0gR2V0LUNpbUluc3RhbmNlIFdpbjMyX0JhdHRlcnkgfCBTZWxlY3QtT2JqZWN0IC1GaXJzdCAxCiRsID0gQCgpCiRsICs9ICJPUzogIiArICRvcy5DYXB0aW9uCiRsICs9ICJDUFU6ICIgKyAkY3B1Lk5hbWUgKyAiIChiZWJhbiAiICsgJGNwdS5M
::B64:agent.js:b2FkUGVyY2VudGFnZSArICIlKSIKJGwgKz0gIlJBTTogYmViYXMgIiArIFttYXRoXTo6Um91bmQoJG9zLkZyZWVQaHlzaWNhbE1lbW9yeSAvIDFNQiwgMSkgKyAiIEdCIGRhcmkgIiArIFttYXRoXTo6Um91bmQoJG9zLlRvdGFsVmlzaWJsZU1lbW9yeVNpemUgLyAx
::B64:agent.js:TUIsIDEpICsgIiBHQiIKaWYgKCRiYXQpIHsgJGwgKz0gIkJhdGVyYWk6ICIgKyAkYmF0LkVzdGltYXRlZENoYXJnZVJlbWFpbmluZyArICIlIiB9IGVsc2UgeyAkbCArPSAiQmF0ZXJhaTogdGlkYWsgYWRhIChQQyBkZXNrdG9wKSIgfQpHZXQtQ2ltSW5zdGFuY2Ug
::B64:agent.js:V2luMzJfTG9naWNhbERpc2sgLUZpbHRlciAiRHJpdmVUeXBlPTMiIHwgRm9yRWFjaC1PYmplY3QgeyAkbCArPSAiRGlzayAiICsgJF8uRGV2aWNlSUQgKyAiIGJlYmFzICIgKyBbbWF0aF06OlJvdW5kKCRfLkZyZWVTcGFjZSAvIDFHQiwgMSkgKyAiIEdCIGRhcmkg
::B64:agent.js:IiArIFttYXRoXTo6Um91bmQoJF8uU2l6ZSAvIDFHQiwgMSkgKyAiIEdCIiB9CiRsIC1qb2luIFtFbnZpcm9ubWVudF06Ok5ld0xpbmUKYCksCgogIG1lZGlhX2tleTogYXN5bmMgKHsga2V5LCB0aW1lcyA9IDEgfSkgPT4gewogICAgY29uc3QgdmFsaWQgPSBbInZv
::B64:agent.js:bHVwIiwgInZvbGRvd24iLCAibXV0ZSIsICJwbGF5cGF1c2UiLCAibmV4dCIsICJwcmV2Il07CiAgICBpZiAoIXZhbGlkLmluY2x1ZGVzKFN0cmluZyhrZXkpKSkgcmV0dXJuICJrZXkgaGFydXMgc2FsYWggc2F0dSBkYXJpOiAiICsgdmFsaWQuam9pbigiLCAiKTsK
::B64:agent.js:ICAgIGF3YWl0IHBzKAogICAgICBgCkFkZC1UeXBlIEAiCnVzaW5nIFN5c3RlbS5SdW50aW1lLkludGVyb3BTZXJ2aWNlczsKcHVibGljIGNsYXNzIEsgeyBbRGxsSW1wb3J0KCJ1c2VyMzIuZGxsIildIHB1YmxpYyBzdGF0aWMgZXh0ZXJuIHZvaWQga2V5YmRfZXZl
::B64:agent.js:bnQoYnl0ZSBiLCBieXRlIHMsIHVpbnQgZiwgaW50IGUpOyB9CiJACiRtYXAgPSBAeyB2b2x1cCA9IDB4QUY7IHZvbGRvd24gPSAweEFFOyBtdXRlID0gMHhBRDsgcGxheXBhdXNlID0gMHhCMzsgbmV4dCA9IDB4QjA7IHByZXYgPSAweEIxIH0KJGsgPSBbYnl0ZV0k
::B64:agent.js:bWFwWyRlbnY6S0VZXQpmb3IgKCRpID0gMDsgJGkgLWx0IFtpbnRdJGVudjpOOyAkaSsrKSB7IFtLXTo6a2V5YmRfZXZlbnQoJGssIDAsIDAsIDApOyBbS106OmtleWJkX2V2ZW50KCRrLCAwLCAyLCAwKTsgU3RhcnQtU2xlZXAgLU1pbGxpc2Vjb25kcyA2MCB9CmAs
::B64:agent.js:CiAgICAgIHsgS0VZOiBTdHJpbmcoa2V5KSwgTjogU3RyaW5nKE1hdGgubWluKE1hdGgubWF4KE51bWJlcih0aW1lcykgfHwgMSwgMSksIDUwKSkgfQogICAgKTsKICAgIHJldHVybiAib2siOwogIH0sCgogIGNsaXBib2FyZF9nZXQ6IGFzeW5jICgpID0+IChhd2Fp
::B64:agent.js:dCBwcygiR2V0LUNsaXBib2FyZCAtUmF3IikpLnNsaWNlKDAsIDQwMDApIHx8ICIoa29zb25nKSIsCgogIGNsaXBib2FyZF9zZXQ6IGFzeW5jICh7IHRleHQgfSkgPT4gewogICAgYXdhaXQgcHMoIlNldC1DbGlwYm9hcmQgLVZhbHVlICRlbnY6VFhUIiwgeyBUWFQ6
::B64:agent.js:IFN0cmluZyh0ZXh0KSB9KTsKICAgIHJldHVybiAib2siOwogIH0sCgogIGxpc3Rfd2luZG93czogYXN5bmMgKCkgPT4KICAgIChhd2FpdCBwcyhgR2V0LVByb2Nlc3MgfCBXaGVyZS1PYmplY3QgeyAkXy5NYWluV2luZG93VGl0bGUgfSB8IEZvckVhY2gtT2JqZWN0
::B64:agent.js:IHsgJF8uUHJvY2Vzc05hbWUgKyAiIHwgIiArICRfLk1haW5XaW5kb3dUaXRsZSB9YCkpIHx8CiAgICAiKHRpZGFrIGFkYSBqZW5kZWxhKSIsCgogIGZvY3VzX3dpbmRvdzogYXN5bmMgKHsgdGl0bGUgfSkgPT4KICAgIHBzKGBpZiAoKE5ldy1PYmplY3QgLUNvbU9i
::B64:agent.js:amVjdCBXU2NyaXB0LlNoZWxsKS5BcHBBY3RpdmF0ZSgkZW52OlRJVExFKSkgeyAib2siIH0gZWxzZSB7ICJqZW5kZWxhIHRpZGFrIGRpdGVtdWthbiIgfWAsIHsKICAgICAgVElUTEU6IFN0cmluZyh0aXRsZSksCiAgICB9KSwKCiAgY2xvc2Vfd2luZG93OiBhc3lu
::B64:agent.js:YyAoeyB0aXRsZSB9KSA9PiB7CiAgICBpZiAoIShhd2FpdCBhc2soYFR1dHVwIGplbmRlbGE6ICR7dGl0bGV9YCkpKSByZXR1cm4gIkRpYmF0YWxrYW4gdXNlciI7CiAgICByZXR1cm4gcHMoCiAgICAgIGAkcCA9IEdldC1Qcm9jZXNzIHwgV2hlcmUtT2JqZWN0IHsg
::B64:agent.js:JF8uTWFpbldpbmRvd1RpdGxlIC1saWtlICgiKiIgKyAkZW52OlRJVExFICsgIioiKSB9IHwgU2VsZWN0LU9iamVjdCAtRmlyc3QgMQppZiAoJHApIHsgJHAuQ2xvc2VNYWluV2luZG93KCkgfCBPdXQtTnVsbDsgIm9rOiAiICsgJHAuTWFpbldpbmRvd1RpdGxlIH0g
::B64:agent.js:ZWxzZSB7ICJqZW5kZWxhIHRpZGFrIGRpdGVtdWthbiIgfWAsCiAgICAgIHsgVElUTEU6IFN0cmluZyh0aXRsZSkgfQogICAgKTsKICB9LAoKICAvLyAtLS0gRmlsZSAtLS0KICByZWFkX3RleHRfZmlsZTogYXN5bmMgKHsgcGF0aDogcCB9KSA9PiB7CiAgICBjb25z
::B64:agent.js:dCBmdWxsID0gcGF0aC5yZXNvbHZlKFN0cmluZyhwKSk7CiAgICBjb25zdCBzdCA9IGZzLnN0YXRTeW5jKGZ1bGwpOwogICAgaWYgKCFzdC5pc0ZpbGUoKSkgdGhyb3cgbmV3IEVycm9yKCJCdWthbiBmaWxlOiAiICsgZnVsbCk7CiAgICBpZiAoc3Quc2l6ZSA+IDJf
::B64:agent.js:MDAwXzAwMCkgdGhyb3cgbmV3IEVycm9yKCJGaWxlIHRlcmxhbHUgYmVzYXIgdW50dWsgZGliYWNhICgiICsgc3Quc2l6ZSArICIgYnl0ZSkiKTsKICAgIHJldHVybiBmcy5yZWFkRmlsZVN5bmMoZnVsbCwgInV0ZjgiKS5zbGljZSgwLCA4MDAwKTsKICB9LAoKICB3
::B64:agent.js:cml0ZV90ZXh0X2ZpbGU6IGFzeW5jICh7IHBhdGg6IHAsIGNvbnRlbnQsIGFwcGVuZCA9IGZhbHNlIH0pID0+IHsKICAgIGNvbnN0IGZ1bGwgPSBwYXRoLnJlc29sdmUoU3RyaW5nKHApKTsKICAgIGNvbnN0IGFkZCA9IGFwcGVuZCA9PT0gdHJ1ZSB8fCBhcHBlbmQg
::B64:agent.js:PT09ICJ0cnVlIjsKICAgIGNvbnN0IHZlcmIgPSBhZGQgPyAiVGFtYmFoIGtlIiA6IGZzLmV4aXN0c1N5bmMoZnVsbCkgPyAiVElNUEEiIDogIkJ1YXQiOwogICAgaWYgKCEoYXdhaXQgYXNrKGAke3ZlcmJ9IGZpbGU6ICR7ZnVsbH1gKSkpIHJldHVybiAiRGliYXRh
::B64:agent.js:bGthbiB1c2VyIjsKICAgIGZzLm1rZGlyU3luYyhwYXRoLmRpcm5hbWUoZnVsbCksIHsgcmVjdXJzaXZlOiB0cnVlIH0pOwogICAgaWYgKGFkZCkgZnMuYXBwZW5kRmlsZVN5bmMoZnVsbCwgU3RyaW5nKGNvbnRlbnQpKTsKICAgIGVsc2UgZnMud3JpdGVGaWxlU3lu
::B64:agent.js:YyhmdWxsLCBTdHJpbmcoY29udGVudCkpOwogICAgcmV0dXJuICJvazogIiArIGZ1bGw7CiAgfSwKCiAgbWFrZV9mb2xkZXI6IGFzeW5jICh7IHBhdGg6IHAgfSkgPT4gewogICAgY29uc3QgZnVsbCA9IHBhdGgucmVzb2x2ZShTdHJpbmcocCkpOwogICAgaWYgKCEo
::B64:agent.js:YXdhaXQgYXNrKGBCdWF0IGZvbGRlcjogJHtmdWxsfWApKSkgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgZnMubWtkaXJTeW5jKGZ1bGwsIHsgcmVjdXJzaXZlOiB0cnVlIH0pOwogICAgcmV0dXJuICJvazogIiArIGZ1bGw7CiAgfSwKCiAgbW92ZV9wYXRo
::B64:agent.js:OiBhc3luYyAoeyBmcm9tLCB0byB9KSA9PiB7CiAgICBpZiAoIShhd2FpdCBhc2soYFBpbmRhaGthbjogJHtmcm9tfSAga2UgICR7dG99YCkpKSByZXR1cm4gIkRpYmF0YWxrYW4gdXNlciI7CiAgICBhd2FpdCBwcygiTW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkZW52
::B64:agent.js:OlNSQyAtRGVzdGluYXRpb24gJGVudjpERVNUIiwgewogICAgICBTUkM6IHBhdGgucmVzb2x2ZShTdHJpbmcoZnJvbSkpLAogICAgICBERVNUOiBwYXRoLnJlc29sdmUoU3RyaW5nKHRvKSksCiAgICB9KTsKICAgIHJldHVybiAib2siOwogIH0sCgogIHJlY3ljbGVf
::B64:agent.js:cGF0aDogYXN5bmMgKHsgcGF0aDogcCB9KSA9PiB7CiAgICBjb25zdCBmdWxsID0gcGF0aC5yZXNvbHZlKFN0cmluZyhwKSk7CiAgICBpZiAoIShhd2FpdCBhc2soYFBpbmRhaGthbiBrZSBSZWN5Y2xlIEJpbjogJHtmdWxsfWApKSkgcmV0dXJuICJEaWJhdGFsa2Fu
::B64:agent.js:IHVzZXIiOwogICAgYXdhaXQgcHMoCiAgICAgIGBBZGQtVHlwZSAtQXNzZW1ibHlOYW1lIE1pY3Jvc29mdC5WaXN1YWxCYXNpYwokcCA9ICRlbnY6VEFSR0VUCmlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRwIC1QYXRoVHlwZSBDb250YWluZXIpIHsgW01pY3Jv
::B64:agent.js:c29mdC5WaXN1YWxCYXNpYy5GaWxlSU8uRmlsZVN5c3RlbV06OkRlbGV0ZURpcmVjdG9yeSgkcCwgJ09ubHlFcnJvckRpYWxvZ3MnLCAnU2VuZFRvUmVjeWNsZUJpbicpIH0KZWxzZSB7IFtNaWNyb3NvZnQuVmlzdWFsQmFzaWMuRmlsZUlPLkZpbGVTeXN0ZW1dOjpE
::B64:agent.js:ZWxldGVGaWxlKCRwLCAnT25seUVycm9yRGlhbG9ncycsICdTZW5kVG9SZWN5Y2xlQmluJykgfWAsCiAgICAgIHsgVEFSR0VUOiBmdWxsIH0KICAgICk7CiAgICByZXR1cm4gIm9rLCBkaXBpbmRhaCBrZSBSZWN5Y2xlIEJpbiAobWFzaWggYmlzYSBkaXB1bGloa2Fu
::B64:agent.js:KSI7CiAgfSwKCiAgemlwX3BhdGg6IGFzeW5jICh7IHNvdXJjZSwgemlwIH0pID0+IHsKICAgIGNvbnN0IHNyYyA9IHBhdGgucmVzb2x2ZShTdHJpbmcoc291cmNlKSk7CiAgICBjb25zdCBkZXN0ID0gcGF0aC5yZXNvbHZlKFN0cmluZyh6aXApKTsKICAgIGlmICgh
::B64:agent.js:KGF3YWl0IGFzayhgWmlwICR7c3JjfSAgbWVuamFkaSAgJHtkZXN0fWApKSkgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgYXdhaXQgcHMoIkNvbXByZXNzLUFyY2hpdmUgLUxpdGVyYWxQYXRoICRlbnY6U1JDIC1EZXN0aW5hdGlvblBhdGggJGVudjpERVNU
::B64:agent.js:IC1Gb3JjZSIsIHsgU1JDOiBzcmMsIERFU1Q6IGRlc3QgfSwgNjAwMDAwKTsKICAgIHJldHVybiAib2s6ICIgKyBkZXN0OwogIH0sCgogIHVuemlwX3BhdGg6IGFzeW5jICh7IHppcCwgZm9sZGVyIH0pID0+IHsKICAgIGNvbnN0IHNyYyA9IHBhdGgucmVzb2x2ZShT
::B64:agent.js:dHJpbmcoemlwKSk7CiAgICBjb25zdCBkZXN0ID0gcGF0aC5yZXNvbHZlKFN0cmluZyhmb2xkZXIpKTsKICAgIGlmICghKGF3YWl0IGFzayhgRWtzdHJhayAke3NyY30gIGtlICAke2Rlc3R9YCkpKSByZXR1cm4gIkRpYmF0YWxrYW4gdXNlciI7CiAgICBhd2FpdCBw
::B64:agent.js:cygiRXhwYW5kLUFyY2hpdmUgLUxpdGVyYWxQYXRoICRlbnY6U1JDIC1EZXN0aW5hdGlvblBhdGggJGVudjpERVNUIC1Gb3JjZSIsIHsgU1JDOiBzcmMsIERFU1Q6IGRlc3QgfSwgNjAwMDAwKTsKICAgIHJldHVybiAib2s6ICIgKyBkZXN0OwogIH0sCgogIC8vIC0t
::B64:agent.js:LSBVcGxvYWQgY2VwYXQ6IHNhdHUgcGFuZ2dpbGFuIG1lbmdnYW50aWthbiBiYW55YWsgbGFuZ2thaCBBSSAtLS0KICBmYXN0X3VwbG9hZDogYXN5bmMgKHsgdXJsLCBmaWxlbmFtZSwgZm9sZGVyLCBwYXR0ZXJuLCBzdWJtaXQgPSB0cnVlLCBuZXdfdGFiID0gdHJ1
::B64:agent.js:ZSB9KSA9PiB7CiAgICBjb25zdCB0MCA9IERhdGUubm93KCk7CiAgICBjb25zdCBkb1N1Ym1pdCA9ICEoc3VibWl0ID09PSBmYWxzZSB8fCBzdWJtaXQgPT09ICJmYWxzZSIpOwogICAgbGV0IGZpbGVzID0gW107CiAgICBpZiAoZmlsZW5hbWUpIHsKICAgICAgZm9y
::B64:agent.js:IChjb25zdCB0b2sgb2YgU3RyaW5nKGZpbGVuYW1lKS5zcGxpdCgifCIpLm1hcCgoeCkgPT4geC50cmltKCkpLmZpbHRlcihCb29sZWFuKSkgewogICAgICAgIGNvbnN0IGFicyA9IHBhdGgucmVzb2x2ZShTQUZFX0RJUiwgdG9rLnJlcGxhY2UoL14ifCIkL2csICIi
::B64:agent.js:KSk7CiAgICAgICAgaWYgKGZzLmV4aXN0c1N5bmMoYWJzKSAmJiBmcy5zdGF0U3luYyhhYnMpLmlzRGlyZWN0b3J5KCkpIGZpbGVzLnB1c2goYXdhaXQgemlwRm9yVXBsb2FkKGFicykpOwogICAgICAgIGVsc2UgZmlsZXMucHVzaChzYWZlUGF0aCh0b2spKTsKICAg
::B64:agent.js:ICAgfQogICAgfQogICAgaWYgKGZvbGRlcikgewogICAgICBjb25zdCBkaXIgPSBwYXRoLnJlc29sdmUoU3RyaW5nKGZvbGRlcikpOwogICAgICBjb25zdCBwYXRzID0gcGF0dGVybiA/IFN0cmluZyhwYXR0ZXJuKS50b0xvd2VyQ2FzZSgpLnNwbGl0KCJ8IikubWFw
::B64:agent.js:KCh4KSA9PiB4LnRyaW0oKS5yZXBsYWNlKC9eXCovLCAiIikpLmZpbHRlcihCb29sZWFuKSA6IFtdOwogICAgICBmb3IgKGNvbnN0IGUgb2YgZnMucmVhZGRpclN5bmMoZGlyLCB7IHdpdGhGaWxlVHlwZXM6IHRydWUgfSkpIHsKICAgICAgICBpZiAoZS5pc0ZpbGUo
::B64:agent.js:KSAmJiAoIXBhdHMubGVuZ3RoIHx8IHBhdHMuc29tZSgocCkgPT4gZS5uYW1lLnRvTG93ZXJDYXNlKCkuaW5jbHVkZXMocCkpKSkgZmlsZXMucHVzaChwYXRoLmpvaW4oZGlyLCBlLm5hbWUpKTsKICAgICAgfQogICAgfQogICAgZmlsZXMgPSBbLi4ubmV3IFNldChm
::B64:agent.js:aWxlcyldLnNsaWNlKDAsIDUwKTsKICAgIGlmICghZmlsZXMubGVuZ3RoKSB0aHJvdyBuZXcgRXJyb3IoIlRpZGFrIGFkYSBmaWxlIHlhbmcgY29jb2sgdW50dWsgZGl1cGxvYWQiKTsKICAgIGNvbnN0IHNpemVNQiA9IGZpbGVzLnJlZHVjZSgoYSwgZikgPT4gYSAr
::B64:agent.js:IGZzLnN0YXRTeW5jKGYpLnNpemUsIDApIC8gMTA0ODU3NjsKICAgIGNvbnN0IGRhZnRhciA9IGZpbGVzLnNsaWNlKDAsIDE1KS5qb2luKCJcbiAgICIpICsgKGZpbGVzLmxlbmd0aCA+IDE1ID8gYFxuICAgLi4uICske2ZpbGVzLmxlbmd0aCAtIDE1fSBsYWdpYCA6
::B64:agent.js:ICIiKTsKICAgIGlmICghKGF3YWl0IGFzayhgVVBMT0FEIENFUEFUICR7ZmlsZXMubGVuZ3RofSBmaWxlICgke3NpemVNQi50b0ZpeGVkKDEpfSBNQikke3VybCA/ICIga2UgIiArIHVybCA6ICIifTpcbiAgICR7ZGFmdGFyfVxuICBgKSkpIHsKICAgICAgcmV0dXJu
::B64:agent.js:ICJEaWJhdGFsa2FuIHVzZXIiOwogICAgfQogICAgaWYgKHVybCkgewogICAgICBpZiAoaXNUcnVlKG5ld190YWIpICYmICFpc0JsYW5rUGFnZSgpKSBwYWdlID0gYXdhaXQgY29udGV4dC5uZXdQYWdlKCk7CiAgICAgIGF3YWl0IHBhZ2UuYnJpbmdUb0Zyb250KCk7
::B64:agent.js:CiAgICAgIGF3YWl0IHBhZ2UuZ290byhmaXhVcmwodXJsKSwgeyB3YWl0VW50aWw6ICJkb21jb250ZW50bG9hZGVkIiB9KTsKICAgICAgYXdhaXQgc2xlZXAoNDAwKTsKICAgIH0KICAgIGNvbnN0IHRyID0gdHJhY2tVcGxvYWRzKCk7CiAgICB0cnkgewogICAgICBj
::B64:agent.js:b25zdCBxdWV1ZSA9IFsuLi5maWxlc107CiAgICAgIGxldCByb3VuZHMgPSAwOwogICAgICBsZXQgbG9naW5Bc2tlZCA9IGZhbHNlOwogICAgICBsZXQgbm90ZSA9ICIiOwogICAgICB3aGlsZSAocXVldWUubGVuZ3RoICYmIHJvdW5kcyA8IDYwKSB7CiAgICAgICAg
::B64:agent.js:cm91bmRzKys7CiAgICAgICAgbGV0IHVzZWQgPSBhd2FpdCBwcm92aWRlRmlsZXMocXVldWUpOwogICAgICAgIGlmICghdXNlZCAmJiAhbG9naW5Bc2tlZCAmJiAoYXdhaXQgaGFzTG9naW5Gb3JtKCkpKSB7CiAgICAgICAgICBsb2dpbkFza2VkID0gdHJ1ZTsKICAg
::B64:agent.js:ICAgICAgIGF3YWl0IGltcGwud2FpdF9mb3JfdXNlcih7IG1lc3NhZ2U6ICJIYWxhbWFuIGluaSBtZW1pbnRhIGxvZ2luLiBMb2dpbiBkdWx1IGRpIGplbmRlbGEgYnJvd3NlciwgbGFsdSB0ZWthbiBFbnRlci4iIH0pOwogICAgICAgICAgdXNlZCA9IGF3YWl0IHBy
::B64:agent.js:b3ZpZGVGaWxlcyhxdWV1ZSk7CiAgICAgICAgfQogICAgICAgIGlmICghdXNlZCkgewogICAgICAgICAgdGhyb3cgbmV3IEVycm9yKCJUb21ib2wgYXRhdSBpbnB1dCB1cGxvYWQgdGlkYWsgZGl0ZW11a2FuIGRpIGhhbGFtYW4gaW5pLiBQYXN0aWthbiBzdWRhaCBs
::B64:agent.js:b2dpbiBkYW4gYmVyYWRhIGRpIGhhbGFtYW4geWFuZyBiZW5hciAoY29iYSAvbG9naW4pLiIpOwogICAgICAgIH0KICAgICAgICBxdWV1ZS5zcGxpY2UoMCwgdXNlZCk7CiAgICAgICAgaWYgKGRvU3VibWl0KSB7CiAgICAgICAgICBhd2FpdCBzbGVlcCg0MDApOwog
::B64:agent.js:ICAgICAgICAgYXdhaXQgY2xpY2tCeVRleHQoU1VCTUlUX0JUTiwgMTUwMCk7CiAgICAgICAgfQogICAgICAgIGNvbnN0IHIgPSBhd2FpdCB3YWl0VXBsb2FkRG9uZSh0ciwgVVBMT0FEX1RJTUVPVVRfTVMpOwogICAgICAgIGlmIChyID09PSBmYWxzZSkgewogICAg
::B64:agent.js:ICAgICAgbm90ZSA9ICJCYXRhcyB3YWt0dSBtZW51bmdndSBoYWJpczsgdXBsb2FkIG11bmdraW4gbWFzaWggYmVyamFsYW4gZGkgaGFsYW1hbi4iOwogICAgICAgICAgYnJlYWs7CiAgICAgICAgfQogICAgICAgIGlmICh0eXBlb2YgciA9PT0gInN0cmluZyIpIG5v
::B64:agent.js:dGUgPSByOwogICAgICB9CiAgICAgIGNvbnN0IGxpbmtzID0gYXdhaXQgcGFnZQogICAgICAgIC5ldmFsdWF0ZSgoc3JjKSA9PiB7CiAgICAgICAgICBjb25zdCByZSA9IG5ldyBSZWdFeHAoc3JjLCAiaSIpOwogICAgICAgICAgY29uc3Qgb3V0ID0gbmV3IFNldCgp
::B64:agent.js:OwogICAgICAgICAgZG9jdW1lbnQucXVlcnlTZWxlY3RvckFsbCgiYVtocmVmXSwgaW5wdXQsIHRleHRhcmVhIikuZm9yRWFjaCgoZSkgPT4gewogICAgICAgICAgICBjb25zdCB2ID0gZS5ocmVmIHx8IGUudmFsdWUgfHwgIiI7CiAgICAgICAgICAgIGlmIChyZS50
::B64:agent.js:ZXN0KHYpKSBvdXQuYWRkKHYpOwogICAgICAgICAgfSk7CiAgICAgICAgICAoKGRvY3VtZW50LmJvZHkgJiYgZG9jdW1lbnQuYm9keS5pbm5lclRleHQubWF0Y2goL2h0dHBzPzpcL1wvW15ccyInPD5dKy9nKSkgfHwgW10pLmZvckVhY2goKHUpID0+IHsKICAgICAg
::B64:agent.js:ICAgICAgaWYgKHJlLnRlc3QodSkpIG91dC5hZGQodSk7CiAgICAgICAgICB9KTsKICAgICAgICAgIHJldHVybiBbLi4ub3V0XS5zbGljZSgwLCAxMCk7CiAgICAgICAgfSwgSE9TVFNfUkUuc291cmNlKQogICAgICAgIC5jYXRjaCgoKSA9PiBbXSk7CiAgICAgIGNv
::B64:agent.js:bnN0IHNlY3MgPSAoKERhdGUubm93KCkgLSB0MCkgLyAxMDAwKS50b0ZpeGVkKDEpOwogICAgICByZXR1cm4gKAogICAgICAgIGBVcGxvYWQgJHtmaWxlcy5sZW5ndGggLSBxdWV1ZS5sZW5ndGh9LyR7ZmlsZXMubGVuZ3RofSBmaWxlIHNlbGVzYWkgZGFsYW0gJHtz
::B64:agent.js:ZWNzfSBkdGsuYCArCiAgICAgICAgKG5vdGUgPyBgIENhdGF0YW46ICR7bm90ZX1gIDogIiIpICsKICAgICAgICAobGlua3MubGVuZ3RoID8gYFxuTGluayB0ZXJkZXRla3NpOlxuJHtsaW5rcy5qb2luKCJcbiIpfWAgOiAiXG5MaW5rIGJlbHVtIHRlcmRldGVrc2kg
::B64:agent.js:b3RvbWF0aXM7IGxpaGF0IGhhbGFtYW4gZGkgYnJvd3Nlci4iKQogICAgICApOwogICAgfSBmaW5hbGx5IHsKICAgICAgdHIuc3RvcCgpOwogICAgfQogIH0sCgogIHJlY2VudF9maWxlczogYXN5bmMgKHsgZm9sZGVyLCBjb3VudCA9IDEwIH0pID0+IHsKICAgIGNv
::B64:agent.js:bnN0IGRpciA9IHBhdGgucmVzb2x2ZShTdHJpbmcoZm9sZGVyIHx8IHBhdGguam9pbihIT01FLCAiRG93bmxvYWRzIikpKTsKICAgIGNvbnN0IGl0ZW1zID0gcmVjZW50TGlzdChkaXIsIGNvdW50KTsKICAgIHJldHVybiBpdGVtcy5sZW5ndGgKICAgICAgPyBpdGVt
::B64:agent.js:cy5tYXAoKHgsIGkpID0+IGAke2kgKyAxfS4gJHt4LmZ9ICgke25ldyBEYXRlKHgudCkudG9Mb2NhbGVTdHJpbmcoImlkLUlEIil9LCAkeyh4LnMgLyAxMDQ4NTc2KS50b0ZpeGVkKDEpfSBNQilgKS5qb2luKCJcbiIpCiAgICAgIDogIih0aWRhayBhZGEgZmlsZSki
::B64:agent.js:OwogIH0sCgogIHNlYXJjaF90ZXh0OiBhc3luYyAoeyBmb2xkZXIsIHRleHQgfSkgPT4gewogICAgY29uc3Qgcm9vdCA9IHBhdGgucmVzb2x2ZShTdHJpbmcoZm9sZGVyKSk7CiAgICBjb25zdCBxID0gU3RyaW5nKHRleHQpLnRvTG93ZXJDYXNlKCk7CiAgICBjb25z
::B64:agent.js:dCBva0V4dCA9IC9cLih0eHR8bWR8anN8dHN8anNvbnxjc3Z8bG9nfGh0bWx8Y3NzfHB5fGphdmF8eG1sfGluaXx5bWx8eWFtbHxjZmd8YmF0fHBocHxzcWwpJC9pOwogICAgY29uc3QgaGl0cyA9IFtdOwogICAgY29uc3QgZGVhZGxpbmUgPSBEYXRlLm5vdygpICsg
::B64:agent.js:MTUwMDA7CiAgICBjb25zdCB3YWxrID0gKGRpciwgZGVwdGgpID0+IHsKICAgICAgaWYgKGRlcHRoIDwgMCB8fCBoaXRzLmxlbmd0aCA+PSAyMCB8fCBEYXRlLm5vdygpID4gZGVhZGxpbmUpIHJldHVybjsKICAgICAgbGV0IGVudHJpZXM7CiAgICAgIHRyeSB7CiAg
::B64:agent.js:ICAgICAgZW50cmllcyA9IGZzLnJlYWRkaXJTeW5jKGRpciwgeyB3aXRoRmlsZVR5cGVzOiB0cnVlIH0pOwogICAgICB9IGNhdGNoIHsKICAgICAgICByZXR1cm47CiAgICAgIH0KICAgICAgZm9yIChjb25zdCBlIG9mIGVudHJpZXMpIHsKICAgICAgICBjb25zdCBm
::B64:agent.js:dWxsID0gcGF0aC5qb2luKGRpciwgZS5uYW1lKTsKICAgICAgICBpZiAoZS5pc0RpcmVjdG9yeSgpKSB7CiAgICAgICAgICBpZiAoIVNLSVBfRElSUy5oYXMoZS5uYW1lLnRvTG93ZXJDYXNlKCkpICYmICFlLm5hbWUuc3RhcnRzV2l0aCgiJCIpKSB3YWxrKGZ1bGws
::B64:agent.js:IGRlcHRoIC0gMSk7CiAgICAgICAgfSBlbHNlIGlmIChva0V4dC50ZXN0KGUubmFtZSkpIHsKICAgICAgICAgIHRyeSB7CiAgICAgICAgICAgIGlmIChmcy5zdGF0U3luYyhmdWxsKS5zaXplID4gMl8wMDBfMDAwKSBjb250aW51ZTsKICAgICAgICAgICAgY29uc3Qg
::B64:agent.js:bGluZXMgPSBmcy5yZWFkRmlsZVN5bmMoZnVsbCwgInV0ZjgiKS5zcGxpdCgvXHI/XG4vKTsKICAgICAgICAgICAgZm9yIChsZXQgaSA9IDA7IGkgPCBsaW5lcy5sZW5ndGggJiYgaGl0cy5sZW5ndGggPCAyMDsgaSsrKSB7CiAgICAgICAgICAgICAgaWYgKGxpbmVz
::B64:agent.js:W2ldLnRvTG93ZXJDYXNlKCkuaW5jbHVkZXMocSkpIGhpdHMucHVzaChgJHtmdWxsfToke2kgKyAxfTogJHtsaW5lc1tpXS50cmltKCkuc2xpY2UoMCwgMTIwKX1gKTsKICAgICAgICAgICAgfQogICAgICAgICAgfSBjYXRjaCB7fQogICAgICAgIH0KICAgICAgfQog
::B64:agent.js:ICAgfTsKICAgIHdhbGsocm9vdCwgNSk7CiAgICByZXR1cm4gaGl0cy5sZW5ndGggPyBoaXRzLmpvaW4oIlxuIikgOiAiVGlkYWsgZGl0ZW11a2FuIjsKICB9LAoKICBjb3B5X3BhdGg6IGFzeW5jICh7IGZyb20sIHRvIH0pID0+IHsKICAgIGlmICghKGF3YWl0IGFz
::B64:agent.js:ayhgU2FsaW46ICR7ZnJvbX0gIGtlICAke3RvfWApKSkgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgYXdhaXQgcHMoIkNvcHktSXRlbSAtTGl0ZXJhbFBhdGggJGVudjpTUkMgLURlc3RpbmF0aW9uICRlbnY6REVTVCAtUmVjdXJzZSAtRm9yY2UiLCB7CiAg
::B64:agent.js:ICAgIFNSQzogcGF0aC5yZXNvbHZlKFN0cmluZyhmcm9tKSksCiAgICAgIERFU1Q6IHBhdGgucmVzb2x2ZShTdHJpbmcodG8pKSwKICAgIH0sIDYwMDAwMCk7CiAgICByZXR1cm4gIm9rIjsKICB9LAoKICBzYXZlX3NjcmVlbnNob3Q6IGFzeW5jICh7IHBhdGg6IHAg
::B64:agent.js:fSkgPT4gewogICAgY29uc3Qgc3RhbXAgPSBuZXcgRGF0ZSgpLnRvSVNPU3RyaW5nKCkucmVwbGFjZSgvWzouXS9nLCAiLSIpLnNsaWNlKDAsIDE5KTsKICAgIGNvbnN0IGRlc3QgPSBwID8gcGF0aC5yZXNvbHZlKFN0cmluZyhwKSkgOiBwYXRoLmpvaW4oSE9NRSwg
::B64:agent.js:IlBpY3R1cmVzIiwgIlNjcmVlbnNob3RzIiwgYGxheWFyLSR7c3RhbXB9LnBuZ2ApOwogICAgZnMubWtkaXJTeW5jKHBhdGguZGlybmFtZShkZXN0KSwgeyByZWN1cnNpdmU6IHRydWUgfSk7CiAgICBhd2FpdCBwcygKICAgICAgUFNfSEVBRCArCiAgICAgICAgYAok
::B64:agent.js:YiA9IFtTeXN0ZW0uV2luZG93cy5Gb3Jtcy5TY3JlZW5dOjpQcmltYXJ5U2NyZWVuLkJvdW5kcwokYm1wID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5CaXRtYXAgJGIuV2lkdGgsICRiLkhlaWdodAokZyA9IFtTeXN0ZW0uRHJhd2luZy5HcmFwaGljc106OkZy
::B64:agent.js:b21JbWFnZSgkYm1wKQokZy5Db3B5RnJvbVNjcmVlbigkYi5YLCAkYi5ZLCAwLCAwLCAkYm1wLlNpemUpCiRibXAuU2F2ZSgkZW52Ok9VVCwgW1N5c3RlbS5EcmF3aW5nLkltYWdpbmcuSW1hZ2VGb3JtYXRdOjpQbmcpCmAsCiAgICAgIHsgT1VUOiBkZXN0IH0KICAg
::B64:agent.js:ICk7CiAgICByZXR1cm4gIlRlcnNpbXBhbjogIiArIGRlc3Q7CiAgfSwKCiAgc2V0X3ZvbHVtZTogYXN5bmMgKHsgbGV2ZWwgfSkgPT4gewogICAgY29uc3QgbiA9IE1hdGgubWluKE1hdGgubWF4KE1hdGgucm91bmQoTnVtYmVyKGxldmVsKSksIDApLCAxMDApOwog
::B64:agent.js:ICAgYXdhaXQgcHMoCiAgICAgIGAKQWRkLVR5cGUgQCIKdXNpbmcgU3lzdGVtLlJ1bnRpbWUuSW50ZXJvcFNlcnZpY2VzOwpwdWJsaWMgY2xhc3MgSyB7IFtEbGxJbXBvcnQoInVzZXIzMi5kbGwiKV0gcHVibGljIHN0YXRpYyBleHRlcm4gdm9pZCBrZXliZF9ldmVu
::B64:agent.js:dChieXRlIGIsIGJ5dGUgcywgdWludCBmLCBpbnQgZSk7IH0KIkAKZm9yICgkaSA9IDA7ICRpIC1sdCA1MDsgJGkrKykgeyBbS106OmtleWJkX2V2ZW50KDB4QUUsIDAsIDAsIDApOyBbS106OmtleWJkX2V2ZW50KDB4QUUsIDAsIDIsIDApOyBTdGFydC1TbGVlcCAt
::B64:agent.js:TWlsbGlzZWNvbmRzIDEyIH0KZm9yICgkaSA9IDA7ICRpIC1sdCBbaW50XSRlbnY6VVA7ICRpKyspIHsgW0tdOjprZXliZF9ldmVudCgweEFGLCAwLCAwLCAwKTsgW0tdOjprZXliZF9ldmVudCgweEFGLCAwLCAyLCAwKTsgU3RhcnQtU2xlZXAgLU1pbGxpc2Vjb25k
::B64:agent.js:cyAxMiB9CmAsCiAgICAgIHsgVVA6IFN0cmluZyhNYXRoLnJvdW5kKG4gLyAyKSkgfQogICAgKTsKICAgIHJldHVybiBgVm9sdW1lIGRpYXR1ciBzZWtpdGFyICR7bn0lYDsKICB9LAoKICBzcGVhazogYXN5bmMgKHsgdGV4dCB9KSA9PiB7CiAgICBhd2FpdCBwcygi
::B64:agent.js:QWRkLVR5cGUgLUFzc2VtYmx5TmFtZSBTeXN0ZW0uU3BlZWNoOyAkcyA9IE5ldy1PYmplY3QgU3lzdGVtLlNwZWVjaC5TeW50aGVzaXMuU3BlZWNoU3ludGhlc2l6ZXI7ICRzLlNwZWFrKCRlbnY6VFhUKSIsIHsgVFhUOiBTdHJpbmcodGV4dCkuc2xpY2UoMCwgNTAw
::B64:agent.js:KSB9LCA2MDAwMCk7CiAgICByZXR1cm4gIm9rLCBkaXVjYXBrYW4iOwogIH0sCgogIHNldF90aW1lcjogYXN5bmMgKHsgYW1vdW50LCB1bml0ID0gIm1lbml0IiwgbWVzc2FnZSA9ICJXYWt0dW55YSEiIH0pID0+IHsKICAgIGNvbnN0IG11bHQgPSAvZGV0aWsvaS50
::B64:agent.js:ZXN0KFN0cmluZyh1bml0KSkgPyAxMDAwIDogL2phbS9pLnRlc3QoU3RyaW5nKHVuaXQpKSA/IDM2MDAwMDAgOiA2MDAwMDsKICAgIGNvbnN0IG1zID0gTWF0aC5yb3VuZChOdW1iZXIoU3RyaW5nKGFtb3VudCkucmVwbGFjZSgiLCIsICIuIikpICogbXVsdCk7CiAg
::B64:agent.js:ICBpZiAoIShtcyA+IDApIHx8IG1zID4gMjQgKiAzNjAwMDAwKSB0aHJvdyBuZXcgRXJyb3IoIkR1cmFzaSB0aWRhayB2YWxpZCAobWFrc2ltYWwgMjQgamFtKSIpOwogICAgdGltZXJzLnB1c2goCiAgICAgIHNldFRpbWVvdXQoYXN5bmMgKCkgPT4gewogICAgICAg
::B64:agent.js:IGNvbnNvbGUubG9nKGBcbioqKiBQRU5HSU5HQVQ6ICR7bWVzc2FnZX0gKioqYCk7CiAgICAgICAgdHJ5IHsKICAgICAgICAgIGF3YWl0IHBzKCJbY29uc29sZV06OkJlZXAoODgwLDMwMCk7IFtjb25zb2xlXTo6QmVlcCgxMTc1LDQwMCk7IEFkZC1UeXBlIC1Bc3Nl
::B64:agent.js:bWJseU5hbWUgU3lzdGVtLlNwZWVjaDsgKE5ldy1PYmplY3QgU3lzdGVtLlNwZWVjaC5TeW50aGVzaXMuU3BlZWNoU3ludGhlc2l6ZXIpLlNwZWFrKCRlbnY6VFhUKSIsIHsgVFhUOiBTdHJpbmcobWVzc2FnZSkgfSwgNjAwMDApOwogICAgICAgIH0gY2F0Y2gge30K
::B64:agent.js:ICAgICAgfSwgbXMpCiAgICApOwogICAgcmV0dXJuIGBQZW5naW5nYXQgZGlhdHVyICR7YW1vdW50fSAke3VuaXR9IGxhZ2k6ICIke21lc3NhZ2V9IiAoYWt0aWYgc2VsYW1hIGFnZW50IHRlcmJ1a2EpYDsKICB9LAoKICBtb3JlX3Rvb2xzOiBhc3luYyAoeyBncm91
::B64:agent.js:cCB9KSA9PiB7CiAgICBjb25zdCBnID0gU3RyaW5nKGdyb3VwKS50b0xvd2VyQ2FzZSgpOwogICAgaWYgKCFUT09MX0dST1VQU1tnXSkgcmV0dXJuICJHcnVwIHRpZGFrIGRpa2VuYWwuIFBpbGloOiAiICsgT2JqZWN0LmtleXMoVE9PTF9HUk9VUFMpLmpvaW4oIiwg
::B64:agent.js:Iik7CiAgICBleHRyYUdyb3Vwcy5hZGQoZyk7CiAgICByZXR1cm4gYEFsYXQgZ3J1cCAke2d9IHNla2FyYW5nIHRlcnNlZGlhOiAke1RPT0xfR1JPVVBTW2ddLmpvaW4oIiwgIil9YDsKICB9LAoKICBnZXRfcGFnZV90ZXh0OiBhc3luYyAoKSA9PiAoYXdhaXQgcGFn
::B64:agent.js:ZS5pbm5lclRleHQoImJvZHkiKSkuc2xpY2UoMCwgNDAwMCksCgogIHR5cGVfdGV4dDogYXN5bmMgKHsgc2VsZWN0b3IsIHRleHQgfSkgPT4gewogICAgYXdhaXQgcGFnZS5maWxsKHNlbGVjdG9yLCB0ZXh0KTsKICAgIHJldHVybiAib2siOwogIH0sCgogIGNsaWNr
::B64:agent.js:OiBhc3luYyAoeyBzZWxlY3RvciB9KSA9PiB7CiAgICBpZiAoIShhd2FpdCBhc2soYEtsaWsgZWxlbWVuIGJyb3dzZXI6ICR7c2VsZWN0b3J9YCkpKSByZXR1cm4gIkRpYmF0YWxrYW4gdXNlciI7CiAgICBhd2FpdCBwYWdlLmNsaWNrKHNlbGVjdG9yLCB7IHRpbWVv
::B64:agent.js:dXQ6IDEwMDAwIH0pOwogICAgcmV0dXJuICJvayI7CiAgfSwKCiAgdXBsb2FkX2ZpbGU6IGFzeW5jICh7IHNlbGVjdG9yLCBmaWxlbmFtZSwgZm9sZGVyLCBwYXR0ZXJuIH0pID0+IHsKICAgIGxldCBmaWxlcyA9IFtdOwogICAgaWYgKGZpbGVuYW1lKSB7CiAgICAg
::B64:agent.js:IGZpbGVzID0gU3RyaW5nKGZpbGVuYW1lKQogICAgICAgIC5zcGxpdCgifCIpCiAgICAgICAgLm1hcCgoeCkgPT4geC50cmltKCkpCiAgICAgICAgLmZpbHRlcihCb29sZWFuKQogICAgICAgIC5tYXAoc2FmZVBhdGgpOwogICAgfQogICAgaWYgKGZvbGRlcikgewog
::B64:agent.js:ICAgICBjb25zdCBkaXIgPSBwYXRoLnJlc29sdmUoU3RyaW5nKGZvbGRlcikpOwogICAgICBjb25zdCBxID0gcGF0dGVybiA/IFN0cmluZyhwYXR0ZXJuKS50b0xvd2VyQ2FzZSgpLnJlcGxhY2UoL15cKi8sICIiKSA6ICIiOwogICAgICBmb3IgKGNvbnN0IGUgb2Yg
::B64:agent.js:ZnMucmVhZGRpclN5bmMoZGlyLCB7IHdpdGhGaWxlVHlwZXM6IHRydWUgfSkpIHsKICAgICAgICBpZiAoZS5pc0ZpbGUoKSAmJiAoIXEgfHwgZS5uYW1lLnRvTG93ZXJDYXNlKCkuaW5jbHVkZXMocSkpKSBmaWxlcy5wdXNoKHBhdGguam9pbihkaXIsIGUubmFtZSkp
::B64:agent.js:OwogICAgICB9CiAgICB9CiAgICBpZiAoIWZpbGVzLmxlbmd0aCkgdGhyb3cgbmV3IEVycm9yKCJUaWRhayBhZGEgZmlsZSB5YW5nIGNvY29rIHVudHVrIGRpdXBsb2FkIik7CiAgICBmaWxlcyA9IGZpbGVzLnNsaWNlKDAsIDUwKTsKICAgIGlmICghKGF3YWl0IGFz
::B64:agent.js:ayhgVXBsb2FkICR7ZmlsZXMubGVuZ3RofSBmaWxlOlxuICAgJHtmaWxlcy5qb2luKCJcbiAgICIpfVxuICBgKSkpIHJldHVybiAiRGliYXRhbGthbiB1c2VyIjsKICAgIGNvbnN0IG11bHRpcGxlID0gYXdhaXQgcGFnZS4kZXZhbChzZWxlY3RvciwgKGVsKSA9PiAh
::B64:agent.js:IWVsLm11bHRpcGxlKS5jYXRjaCgoKSA9PiBmYWxzZSk7CiAgICBpZiAoZmlsZXMubGVuZ3RoID4gMSAmJiAhbXVsdGlwbGUpIHsKICAgICAgYXdhaXQgcGFnZS5zZXRJbnB1dEZpbGVzKHNlbGVjdG9yLCBmaWxlc1swXSk7CiAgICAgIHJldHVybiAoCiAgICAgICAg
::B64:agent.js:YElucHV0IGluaSBoYW55YSBtZW5lcmltYSAxIGZpbGUuIFRlcnBpbGloOiAke2ZpbGVzWzBdfS4gU2lzYSAke2ZpbGVzLmxlbmd0aCAtIDF9IGZpbGU6IGAgKwogICAgICAgIGAke2ZpbGVzLnNsaWNlKDEpLmpvaW4oIiB8ICIpfS4gU2VsZXNhaWthbiB1cGxvYWQg
::B64:agent.js:aW5pLCBsYWx1IHVsYW5naSB1cGxvYWRfZmlsZSB1bnR1ayBzaXNhbnlhLmAKICAgICAgKTsKICAgIH0KICAgIGF3YWl0IHBhZ2Uuc2V0SW5wdXRGaWxlcyhzZWxlY3RvciwgZmlsZXMpOwogICAgcmV0dXJuIGBvaywgJHtmaWxlcy5sZW5ndGh9IGZpbGUgZGlwaWxp
::B64:agent.js:aGA7CiAgfSwKfTsKCmNvbnN0IGZuID0gKG5hbWUsIGRlc2NyaXB0aW9uLCBwcm9wZXJ0aWVzID0ge30sIG9wdGlvbmFsID0gW10pID0+ICh7CiAgdHlwZTogImZ1bmN0aW9uIiwKICBmdW5jdGlvbjogewogICAgbmFtZSwKICAgIGRlc2NyaXB0aW9uLAogICAgcGFy
::B64:agent.js:YW1ldGVyczogewogICAgICB0eXBlOiAib2JqZWN0IiwKICAgICAgcHJvcGVydGllcywKICAgICAgcmVxdWlyZWQ6IE9iamVjdC5rZXlzKHByb3BlcnRpZXMpLmZpbHRlcigoaykgPT4gIW9wdGlvbmFsLmluY2x1ZGVzKGspKSwKICAgIH0sCiAgfSwKfSk7CmNvbnN0
::B64:agent.js:IHN0ciA9IChkKSA9PiAoeyB0eXBlOiAic3RyaW5nIiwgZGVzY3JpcHRpb246IGQgfSk7CmNvbnN0IG51bSA9IChkKSA9PiAoeyB0eXBlOiAibnVtYmVyIiwgZGVzY3JpcHRpb246IGQgfSk7CmNvbnN0IGJvb2wgPSAoZCkgPT4gKHsgdHlwZTogImJvb2xlYW4iLCBk
::B64:agent.js:ZXNjcmlwdGlvbjogZCB9KTsKCmNvbnN0IHRvb2xzID0gWwogIGZuKCJmaW5kX2ZvbGRlciIsICJDYXJpIGZvbGRlciBkaSBzZWx1cnVoIFBDIChzZW11YSBkcml2ZSkgYmVyZGFzYXJrYW4gbmFtYTsgc2ViYWdpYW4gbmFtYSBjdWt1cCIsIHsgbmFtZTogc3RyKCJO
::B64:agent.js:YW1hIGZvbGRlciIpIH0pLAogIGZuKCJmaW5kX2ZpbGUiLCAiQ2FyaSBmaWxlIGRpIHNlbHVydWggUEMgKHNlbXVhIGRyaXZlKSBiZXJkYXNhcmthbiBuYW1hOyBzZWJhZ2lhbiBuYW1hIGN1a3VwIiwgeyBuYW1lOiBzdHIoIk5hbWEgZmlsZSIpIH0pLAogIGZuKCJs
::B64:agent.js:aXN0X2RpciIsICJMaWhhdCBpc2kgc2VidWFoIGZvbGRlciBkaSBQQyIsIHsgcGF0aDogc3RyKCJQYXRoIGxlbmdrYXAgZm9sZGVyIikgfSksCiAgZm4oIm9wZW5fcGF0aCIsICJCdWthIGZvbGRlciwgZmlsZSwgYXBsaWthc2kgKG1pcy4gbm90ZXBhZCksIGF0YXUg
::B64:agent.js:VVJMIGRpIFBDIiwgeyB0YXJnZXQ6IHN0cigiUGF0aC9uYW1hIGFwbGlrYXNpL1VSTCIpIH0pLAogIGZuKCJzY3JlZW5zaG90IiwgIkFtYmlsIHNjcmVlbnNob3QgbGF5YXIgUEMgdW50dWsgbWVsaWhhdCBrb25kaXNpIHNla2FyYW5nIiksCiAgZm4oCiAgICAiY2xp
::B64:agent.js:Y2tfc2NyZWVuIiwKICAgICJLbGlrIGRpIGxheWFyIFBDIHBhZGEga29vcmRpbmF0IGRhcmkgc2NyZWVuc2hvdCB0ZXJha2hpciIsCiAgICB7IHg6IG51bSgiS29vcmRpbmF0IFggZGkgc2NyZWVuc2hvdCIpLCB5OiBudW0oIktvb3JkaW5hdCBZIGRpIHNjcmVlbnNo
::B64:agent.js:b3QiKSwgYnV0dG9uOiBzdHIoImxlZnQgYXRhdSByaWdodCIpLCBkb3VibGU6IHsgdHlwZTogImJvb2xlYW4iLCBkZXNjcmlwdGlvbjogImRvdWJsZS1rbGlrIiB9IH0sCiAgICBbImJ1dHRvbiIsICJkb3VibGUiXQogICksCiAgZm4oInNjcm9sbF9zY3JlZW4iLCAi
::B64:agent.js:U2Nyb2xsIGxheWFyLiBQb3NpdGlmID0gdHVydW4sIG5lZ2F0aWYgPSBuYWlrIiwgeyBhbW91bnQ6IG51bSgiSnVtbGFoIHNjcm9sbCIpIH0pLAogIGZuKCJ0eXBlX2Rlc2t0b3AiLCAiS2V0aWsgdGVrcyBkaSBhcGxpa2FzaSB5YW5nIHNlZGFuZyBmb2t1cyBkaSBQ
::B64:agent.js:QyIsIHsgdGV4dDogc3RyKCJUZWtzIikgfSksCiAgZm4oInByZXNzX2tleXMiLCAiVGVrYW4gdG9tYm9sIGZvcm1hdCBTZW5kS2V5czoge0VOVEVSfSwge1RBQn0sIHtFU0N9LCBeYyAoQ3RybCtDKSwgXnYsIF5sLCAle0Y0fSIsIHsga2V5czogc3RyKCJLb21iaW5h
::B64:agent.js:c2kgdG9tYm9sIikgfSksCiAgZm4oIndhaXQiLCAiVHVuZ2d1IGJlYmVyYXBhIGRldGlrIChtYWtzIDE1KSBzdXBheWEgaGFsYW1hbi9hcGxpa2FzaSBzZWxlc2FpIGRpbXVhdCIsIHsgc2Vjb25kczogbnVtKCJEZXRpayIpIH0pLAogIGZuKCJsaXN0X2ZpbGVzIiwg
::B64:agent.js:IkxpaGF0IGRhZnRhciBmaWxlIGRpIGZvbGRlciB1cGxvYWQga2h1c3VzIiksCiAgZm4oCiAgICAib3Blbl91cmwiLAogICAgIkJ1a2Egd2Vic2l0ZSBkaSBicm93c2VyLiBTZWNhcmEgYmF3YWFuIG1lbmltcGEgdGFiIGFrdGlmOyBwYWthaSBuZXdfdGFiPXRydWUg
::B64:agent.js:YWdhciBoYWxhbWFuL3ZpZGVvIHlhbmcgc2VkYW5nIHRlcmJ1a2EgdGlkYWsgdGVydGltcGEiLAogICAgeyB1cmw6IHN0cigiVVJMIGxlbmdrYXAiKSwgbmV3X3RhYjogYm9vbCgidHJ1ZSA9IGJ1a2EgZGkgdGFiIGJhcnUiKSB9LAogICAgWyJuZXdfdGFiIl0KICAp
::B64:agent.js:LAogIGZuKCJsaXN0X3RhYnMiLCAiRGFmdGFyIHNlbXVhIHRhYiBicm93c2VyICh0YW5kYSAqID0gdGFiIGFrdGlmKSIpLAogIGZuKCJuZXdfdGFiIiwgIkJ1a2EgdGFiIGJhcnUgKGtvc29uZywgYXRhdSBsYW5nc3VuZyBrZSBVUkwpIGRhbiBqYWRpa2FuIHRhYiBh
::B64:agent.js:a3RpZiIsIHsgdXJsOiBzdHIoIlVSTCAob3BzaW9uYWwpIikgfSwgWyJ1cmwiXSksCiAgZm4oIm9wZW5fdXJscyIsICJCdWthIEJBTllBSyB3ZWJzaXRlIHNla2FsaWd1cywgbWFzaW5nLW1hc2luZyBkaSB0YWIgYmFydSIsIHsKICAgIHVybHM6IHsgdHlwZTogImFy
::B64:agent.js:cmF5IiwgaXRlbXM6IHsgdHlwZTogInN0cmluZyIgfSwgZGVzY3JpcHRpb246ICJEYWZ0YXIgVVJMIChtYWtzaW1hbCAxMCkiIH0sCiAgfSksCiAgZm4oCiAgICAic3dpdGNoX3RhYiIsCiAgICAiUGluZGFoIHRhYiBha3RpZi4gUGFrYWkgaW5kZXggKDEgPSB0YWIg
::B64:agent.js:cGVydGFtYSwgLTEgPSB0YWIgdGVyYmFydSkgQVRBVSBtYXRjaCAoc2ViYWdpYW4ganVkdWwvVVJMKSIsCiAgICB7IGluZGV4OiBudW0oIk5vbW9yIHRhYiwgLTEgPSB0ZXJiYXJ1IiksIG1hdGNoOiBzdHIoIlNlYmFnaWFuIGp1ZHVsIGF0YXUgVVJMIHRhYiIpIH0s
::B64:agent.js:CiAgICBbImluZGV4IiwgIm1hdGNoIl0KICApLAogIGZuKCJjbG9zZV90YWIiLCAiVHV0dXAgdGFiIChiYXdhYW46IHRhYiBha3RpZiksIGF0YXUgdGFiIGRlbmdhbiBub21vciB0ZXJ0ZW50dSIsIHsgaW5kZXg6IG51bSgiTm9tb3IgdGFiLCAtMSA9IHRlcmJhcnUi
::B64:agent.js:KSB9LCBbImluZGV4Il0pLAogIGZuKCJpbnNwZWN0X3BhZ2UiLCAiRGFmdGFyIHRvbWJvbC9pbnB1dCBkaSBoYWxhbWFuIGJyb3dzZXIgdW50dWsgbWVuY2FyaSBDU1Mgc2VsZWN0b3IiKSwKICBmbigKICAgICJ5b3V0dWJlX3BsYXkiLAogICAgIkNhcmkgdmlkZW8g
::B64:agent.js:ZGkgWW91VHViZSBsYWx1IE9UT01BVElTIG1lbXV0YXIgaGFzaWwgcGlsaWhhbiBkaSBicm93c2VyIGFnZW50LiBQYWthaSBpbmkgdW50dWsgc2VtdWEgcGVybWludGFhbiBub250b24vY2FyaSB2aWRlby9sYWd1IGRpIFlvdVR1YmUuIiwKICAgIHsKICAgICAgcXVl
::B64:agent.js:cnk6IHN0cigiS2F0YSBrdW5jaSBwZW5jYXJpYW4iKSwKICAgICAgcGljazogbnVtKCJVcnV0YW4gaGFzaWwgeWFuZyBkaXB1dGFyLCAxLTUgKGRlZmF1bHQgMSkiKSwKICAgICAgbmV3X3RhYjogYm9vbCgidHJ1ZSA9IHB1dGFyIGRpIHRhYiBiYXJ1IHN1cGF5YSB0
::B64:agent.js:YWIgYWt0aWYgdGlkYWsgdGVydGltcGEiKSwKICAgIH0sCiAgICBbInBpY2siLCAibmV3X3RhYiJdCiAgKSwKICBmbigiZG9uZSIsICJQYW5nZ2lsIGluaSBqaWthIHR1Z2FzIFNFTEVTQUksIGF0YXUgamlrYSBwZXJsdSBiZXJ0YW55YS9tZWxhcG9yIGtlIHVzZXIi
::B64:agent.js:LCB7IG1lc3NhZ2U6IHN0cigiUGVzYW4gc2luZ2thdCB1bnR1ayB1c2VyIikgfSksCiAgZm4oCiAgICAieW91dHViZV9jb250cm9sIiwKICAgICJLb250cm9sIHZpZGVvIFlvdVR1YmUgeWFuZyBzZWRhbmcgdGVyYnVrYSIsCiAgICB7IGFjdGlvbjogc3RyKCJwbGF5
::B64:agent.js:LCBwYXVzZSwgdG9nZ2xlLCBtdXRlLCB1bm11dGUsIGZvcndhcmQsIGJhY2t3YXJkLCBuZXh0LCBwcmV2aW91cywgZnVsbHNjcmVlbiIpLCBzZWNvbmRzOiBudW0oIkRldGlrIHVudHVrIGZvcndhcmQvYmFja3dhcmQgKGRlZmF1bHQgMTApIikgfSwKICAgIFsic2Vj
::B64:agent.js:b25kcyJdCiAgKSwKICBmbigid2ViX3NlYXJjaCIsICJDYXJpIGluZm9ybWFzaSBkaSBpbnRlcm5ldCwgbWVuZ2VtYmFsaWthbiBqdWR1bCwgbGluaywgZGFuIGN1cGxpa2FuIGhhc2lsIiwgewogICAgcXVlcnk6IHN0cigiS2F0YSBrdW5jaSIpLAogICAgbmV3X3Rh
::B64:agent.js:YjogYm9vbCgidHJ1ZSA9IGNhcmkgZGkgdGFiIGJhcnUgc3VwYXlhIHRhYiBha3RpZiB0aWRhayB0ZXJ0aW1wYSIpLAogIH0sIFsibmV3X3RhYiJdKSwKICBmbigic2Nyb2xsX3BhZ2UiLCAiU2Nyb2xsIGhhbGFtYW4gYnJvd3Nlci4gUG9zaXRpZiA9IHR1cnVuLCBu
::B64:agent.js:ZWdhdGlmID0gbmFpayIsIHsgYW1vdW50OiBudW0oIkp1bWxhaCBzY3JvbGwiKSB9KSwKICBmbigid2FpdF9mb3JfdXNlciIsICJCZXJoZW50aSBkYW4gbWludGEgdXNlciBtZWxha3VrYW4gc2VzdWF0dSBzZW5kaXJpIChsb2dpbiwgY2FwdGNoYSwgdmVyaWZpa2Fz
::B64:agent.js:aSksIGxhbHUgdHVuZ2d1IEVudGVyIiwgeyBtZXNzYWdlOiBzdHIoIkluc3RydWtzaSB1bnR1ayB1c2VyIikgfSksCiAgZm4oImRvd25sb2FkX2ZpbGUiLCAiVW5kdWggZmlsZSBkYXJpIGludGVybmV0IGtlIGZvbGRlciBEb3dubG9hZHMiLCB7IHVybDogc3RyKCJV
::B64:agent.js:UkwgaHR0cChzKSIpLCBmaWxlbmFtZTogc3RyKCJOYW1hIGZpbGUgKG9wc2lvbmFsKSIpIH0sIFsiZmlsZW5hbWUiXSksCiAgZm4oIm5vdyIsICJUYW5nZ2FsIGRhbiBqYW0gc2VrYXJhbmciKSwKICBmbigic3lzdGVtX2luZm8iLCAiSW5mbyBQQzogT1MsIENQVSwg
::B64:agent.js:UkFNLCBiYXRlcmFpLCBydWFuZyBkaXNrIiksCiAgZm4oCiAgICAibWVkaWFfa2V5IiwKICAgICJUb21ib2wgbWVkaWEgZGFuIHZvbHVtZSBnbG9iYWwgV2luZG93cyIsCiAgICB7IGtleTogc3RyKCJ2b2x1cCwgdm9sZG93biwgbXV0ZSwgcGxheXBhdXNlLCBuZXh0
::B64:agent.js:LCBwcmV2IiksIHRpbWVzOiBudW0oIkp1bWxhaCB0ZWthbiAodm9sdW1lIGJlcnViYWggMiUgcGVyIHRla2FuKSIpIH0sCiAgICBbInRpbWVzIl0KICApLAogIGZuKCJjbGlwYm9hcmRfZ2V0IiwgIkJhY2EgaXNpIGNsaXBib2FyZCIpLAogIGZuKCJjbGlwYm9hcmRf
::B64:agent.js:c2V0IiwgIklzaSBjbGlwYm9hcmQiLCB7IHRleHQ6IHN0cigiVGVrcyIpIH0pLAogIGZuKCJsaXN0X3dpbmRvd3MiLCAiRGFmdGFyIGplbmRlbGEgYXRhdSBhcGxpa2FzaSB5YW5nIHNlZGFuZyB0ZXJidWthIiksCiAgZm4oImZvY3VzX3dpbmRvdyIsICJQaW5kYWhr
::B64:agent.js:YW4gZm9rdXMga2Ugc2VidWFoIGplbmRlbGEiLCB7IHRpdGxlOiBzdHIoIlNlYmFnaWFuIGp1ZHVsIGplbmRlbGEiKSB9KSwKICBmbigiY2xvc2Vfd2luZG93IiwgIlR1dHVwIHNlYnVhaCBqZW5kZWxhIGRlbmdhbiBiYWlrLWJhaWsiLCB7IHRpdGxlOiBzdHIoIlNl
::B64:agent.js:YmFnaWFuIGp1ZHVsIGplbmRlbGEiKSB9KSwKICBmbigicmVhZF90ZXh0X2ZpbGUiLCAiQmFjYSBpc2kgZmlsZSB0ZWtzIiwgeyBwYXRoOiBzdHIoIlBhdGggbGVuZ2thcCBmaWxlIikgfSksCiAgZm4oIndyaXRlX3RleHRfZmlsZSIsICJUdWxpcyBhdGF1IHRhbWJh
::B64:agent.js:aCBpc2kgZmlsZSB0ZWtzIiwgeyBwYXRoOiBzdHIoIlBhdGggbGVuZ2thcCBmaWxlIiksIGNvbnRlbnQ6IHN0cigiSXNpIiksIGFwcGVuZDogeyB0eXBlOiAiYm9vbGVhbiIsIGRlc2NyaXB0aW9uOiAidHJ1ZSA9IHRhbWJhaGthbiwgYnVrYW4gbWVuaW1wYSIgfSB9
::B64:agent.js:LCBbImFwcGVuZCJdKSwKICBmbigibWFrZV9mb2xkZXIiLCAiQnVhdCBmb2xkZXIgYmFydSIsIHsgcGF0aDogc3RyKCJQYXRoIGxlbmdrYXAgZm9sZGVyIikgfSksCiAgZm4oIm1vdmVfcGF0aCIsICJQaW5kYWhrYW4gYXRhdSBnYW50aSBuYW1hIGZpbGUvZm9sZGVy
::B64:agent.js:IiwgeyBmcm9tOiBzdHIoIlBhdGggYXNhbCIpLCB0bzogc3RyKCJQYXRoIHR1anVhbiIpIH0pLAogIGZuKCJyZWN5Y2xlX3BhdGgiLCAiSGFwdXMgZmlsZS9mb2xkZXIgZGVuZ2FuIG1lbWluZGFoa2FubnlhIGtlIFJlY3ljbGUgQmluIiwgeyBwYXRoOiBzdHIoIlBh
::B64:agent.js:dGggbGVuZ2thcCIpIH0pLAogIGZuKCJ6aXBfcGF0aCIsICJLb21wcmVzIGZpbGUgYXRhdSBmb2xkZXIgbWVuamFkaSAuemlwIiwgeyBzb3VyY2U6IHN0cigiUGF0aCBmaWxlL2ZvbGRlciIpLCB6aXA6IHN0cigiUGF0aCBmaWxlIC56aXAgaGFzaWwiKSB9KSwKICBm
::B64:agent.js:bigidW56aXBfcGF0aCIsICJFa3N0cmFrIGZpbGUgLnppcCIsIHsgemlwOiBzdHIoIlBhdGggZmlsZSAuemlwIiksIGZvbGRlcjogc3RyKCJGb2xkZXIgdHVqdWFuIikgfSksCiAgZm4oCiAgICAiZmFzdF91cGxvYWQiLAogICAgIlVQTE9BRCBDRVBBVCBkYWxhbSBz
::B64:agent.js:YXR1IGxhbmdrYWggKGRhaHVsdWthbiBhbGF0IGluaSB1bnR1ayBzZW11YSBwZXJtaW50YWFuIHVwbG9hZCk6IGJ1a2EgVVJMIGRpIHRhYiBiYXJ1LCB0ZW11a2FuIHRvbWJvbC9pbnB1dCB1cGxvYWQgb3RvbWF0aXMsIHBpbGloIHNhdHUvYmFueWFrIGZpbGUgYXRh
::B64:agent.js:dSBpc2kgZm9sZGVyIChmb2xkZXIgdHVuZ2dhbCBkaWtpcmltIHNlYmFnYWkgemlwKSwga2xpayB0b21ib2wga2lyaW0sIHR1bmdndSBzZWxlc2FpLCBrZW1iYWxpa2FuIGxpbmsgamlrYSB0ZXJkZXRla3NpLiBKaWthIGhhbGFtYW4gc3VkYWggdGVyYnVrYSwgdXJs
::B64:agent.js:IGJvbGVoIGtvc29uZy4iLAogICAgewogICAgICB1cmw6IHN0cigiQWxhbWF0IHNpdHVzIHVwbG9hZCAob3BzaW9uYWwgamlrYSBoYWxhbWFuIHN1ZGFoIHRlcmJ1a2EpIiksCiAgICAgIGZpbGVuYW1lOiBzdHIoIlBhdGggZmlsZSAoYmFueWFrIGRpcGlzYWggfCkg
::B64:agent.js:YXRhdSBwYXRoIGZvbGRlciAoYWthbiBkaS16aXApIiksCiAgICAgIGZvbGRlcjogc3RyKCJGb2xkZXIgYmVyaXNpIGZpbGUgeWFuZyBkaXVwbG9hZCBzZW11YW55YSAob3BzaW9uYWwpIiksCiAgICAgIHBhdHRlcm46IHN0cigiRmlsdGVyIG5hbWEgZmlsZSBkaSBm
::B64:agent.js:b2xkZXIsIG1pc2FsIC5wZGYgYXRhdSAuanBnfC5wbmcgKG9wc2lvbmFsKSIpLAogICAgICBzdWJtaXQ6IGJvb2woImZhbHNlID0gamFuZ2FuIGtsaWsgdG9tYm9sIGtpcmltIG90b21hdGlzIChkZWZhdWx0IHRydWUpIiksCiAgICAgIG5ld190YWI6IGJvb2woImZh
::B64:agent.js:bHNlID0gcGFrYWkgdGFiIGFrdGlmIChkZWZhdWx0IHRydWUpIiksCiAgICB9LAogICAgWyJ1cmwiLCAiZmlsZW5hbWUiLCAiZm9sZGVyIiwgInBhdHRlcm4iLCAic3VibWl0IiwgIm5ld190YWIiXQogICksCiAgZm4oInJlY2VudF9maWxlcyIsICJEYWZ0YXIgZmls
::B64:agent.js:ZSB0ZXJiYXJ1IGRpIHNlYnVhaCBmb2xkZXIgKGJhd2FhbjogRG93bmxvYWRzKSIsIHsgZm9sZGVyOiBzdHIoIlBhdGggZm9sZGVyIChvcHNpb25hbCkiKSwgY291bnQ6IG51bSgiSnVtbGFoIChkZWZhdWx0IDEwKSIpIH0sIFsiZm9sZGVyIiwgImNvdW50Il0pLAog
::B64:agent.js:IGZuKCJzZWFyY2hfdGV4dCIsICJDYXJpIHRla3MgZGkgZGFsYW0gZmlsZSB0ZWtzL2tvZGUgcGFkYSBzZWJ1YWggZm9sZGVyIiwgeyBmb2xkZXI6IHN0cigiUGF0aCBmb2xkZXIiKSwgdGV4dDogc3RyKCJUZWtzIHlhbmcgZGljYXJpIikgfSksCiAgZm4oImNvcHlf
::B64:agent.js:cGF0aCIsICJTYWxpbiBmaWxlIGF0YXUgZm9sZGVyIiwgeyBmcm9tOiBzdHIoIlBhdGggYXNhbCIpLCB0bzogc3RyKCJQYXRoIHR1anVhbiIpIH0pLAogIGZuKCJzYXZlX3NjcmVlbnNob3QiLCAiU2ltcGFuIHNjcmVlbnNob3QgbGF5YXIgcGVudWgga2UgZmlsZSAo
::B64:agent.js:YmF3YWFuOiBQaWN0dXJlc1xcU2NyZWVuc2hvdHMpIiwgeyBwYXRoOiBzdHIoIlBhdGggZmlsZSAucG5nIChvcHNpb25hbCkiKSB9LCBbInBhdGgiXSksCiAgZm4oInNldF92b2x1bWUiLCAiQXR1ciB2b2x1bWUgV2luZG93cyBrZSBhbmdrYSB0ZXJ0ZW50dSAoMC0x
::B64:agent.js:MDApIiwgeyBsZXZlbDogbnVtKCJQZXJzZW4gdm9sdW1lIikgfSksCiAgZm4oInNwZWFrIiwgIlVjYXBrYW4gdGVrcyBkZW5nYW4gc3VhcmEga29tcHV0ZXIiLCB7IHRleHQ6IHN0cigiVGVrcyB5YW5nIGRpdWNhcGthbiIpIH0pLAogIGZuKAogICAgInNldF90aW1l
::B64:agent.js:ciIsCiAgICAiQXR1ciBwZW5naW5nYXQ6IHNldGVsYWggd2FrdHUgdGVydGVudHUgbXVuY3VsIHBlc2FuLCBidW55aSwgZGFuIHN1YXJhIChha3RpZiBzZWxhbWEgYWdlbnQgdGVyYnVrYSkiLAogICAgeyBhbW91bnQ6IG51bSgiSnVtbGFoIHdha3R1IiksIHVuaXQ6
::B64:agent.js:IHN0cigiZGV0aWssIG1lbml0LCBhdGF1IGphbSIpLCBtZXNzYWdlOiBzdHIoIlBlc2FuIHBlbmdpbmdhdCIpIH0sCiAgICBbInVuaXQiLCAibWVzc2FnZSJdCiAgKSwKICBmbigibW9yZV90b29scyIsICJBa3RpZmthbiBrZWxvbXBvayBhbGF0IHRhbWJhaGFuIGpp
::B64:agent.js:a2EgYWxhdCB5YW5nIGthbXUgYnV0dWhrYW4gYmVsdW0gdGVyc2VkaWEiLCB7CiAgICBncm91cDogc3RyKCJ5b3V0dWJlLCB0YWJzLCBkZXNrdG9wLCBmaWxlcywgYXRhdSBwYyIpLAogIH0pLAogIGZuKCJnZXRfcGFnZV90ZXh0IiwgIkJhY2EgdGVrcyBoYWxhbWFu
::B64:agent.js:IGJyb3dzZXIgc2FhdCBpbmkiKSwKICBmbigidHlwZV90ZXh0IiwgIklzaSBrb2xvbSB0ZWtzIGRpIGJyb3dzZXIiLCB7IHNlbGVjdG9yOiBzdHIoIkNTUyBzZWxlY3RvciIpLCB0ZXh0OiBzdHIoIlRla3MiKSB9KSwKICBmbigiY2xpY2siLCAiS2xpayBlbGVtZW4g
::B64:agent.js:ZGkgYnJvd3NlciIsIHsgc2VsZWN0b3I6IHN0cigiQ1NTIHNlbGVjdG9yIikgfSksCiAgZm4oCiAgICAidXBsb2FkX2ZpbGUiLAogICAgIlVwbG9hZCBTQVRVIGF0YXUgQkFOWUFLIGZpbGUga2UgaW5wdXQgZmlsZSBkaSBicm93c2VyLiBCZWJlcmFwYSBmaWxlIGRp
::B64:agent.js:IGZpbGVuYW1lIGRpcGlzYWggdGFuZGEgfC4gQXRhdSBwYWthaSBmb2xkZXIgKCsgcGF0dGVybikgdW50dWsgbWVuZ3VuZ2dhaCBzZW11YSBmaWxlIGRpIGZvbGRlciBpdHUiLAogICAgewogICAgICBzZWxlY3Rvcjogc3RyKCJDU1Mgc2VsZWN0b3IgaW5wdXRbdHlw
::B64:agent.js:ZT1maWxlXSIpLAogICAgICBmaWxlbmFtZTogc3RyKCJQYXRoIGxlbmdrYXAgZmlsZSAoYm9sZWggYmFueWFrLCBkaXBpc2FoIHwpLCBhdGF1IG5hbWEgZmlsZSBkaSB1cGxvYWQtZm9sZGVyIiksCiAgICAgIGZvbGRlcjogc3RyKCJGb2xkZXIgYmVyaXNpIGZpbGUg
::B64:agent.js:eWFuZyBtYXUgZGl1cGxvYWQgc2VtdWFueWEgKG9wc2lvbmFsKSIpLAogICAgICBwYXR0ZXJuOiBzdHIoIkZpbHRlciBuYW1hIGZpbGUgZGkgZm9sZGVyLCBtaXNhbG55YSAucGRmIChvcHNpb25hbCkiKSwKICAgIH0sCiAgICBbImZpbGVuYW1lIiwgImZvbGRlciIs
::B64:agent.js:ICJwYXR0ZXJuIl0KICApLApdOwoKY29uc3QgU1lTVEVNID0gYEthbXUgYWdlbnQgeWFuZyBtZW5nb250cm9sIFBDIFdpbmRvd3MgbWlsaWsgdXNlciBkYW4gYnJvd3Nlci4gS2VyamFrYW4gcGVyaW50YWggdXNlciBkZW5nYW4gbWVtYW5nZ2lsIHRvb2wuCkFUVVJB
::B64:agent.js:TiBQRU5USU5HOgotIEthbXUgSEFSVVMgc2VsYWx1IG1lbWFuZ2dpbCB0b29sIGRpIHNldGlhcCBsYW5na2FoLiBKQU5HQU4gcGVybmFoIG1lbnVsaXMgcmVuY2FuYSwgbmFyYXNpLCBhdGF1ICJzYXlhIGFrYW4gLi4uIi4gTGFuZ3N1bmcgcGFuZ2dpbCB0b29sLW55
::B64:agent.js:YS4KLSBTZXRlbGFoIHR1Z2FzIHNlbGVzYWkgKGF0YXUgcGVybHUgYmVydGFueWEga2UgdXNlciksIHBhbmdnaWwgdG9vbCBkb25lIGRlbmdhbiBwZXNhbiBzaW5na2F0LgotIE5vbnRvbi9jYXJpIHZpZGVvL2xhZ3UgZGkgWW91VHViZTogbGFuZ3N1bmcgcGFuZ2dp
::B64:agent.js:bCB5b3V0dWJlX3BsYXkgZGVuZ2FuIGthdGEga3VuY2kgZGFyaSB1c2VyLiBKaWthIGp1ZHVsIHlhbmcgZGlwdXRhciBrdXJhbmcgY29jb2ssIHBhbmdnaWwgbGFnaSBkZW5nYW4gcGljayBsYWluLgotIFRhZnNpcmthbiBwZXJpbnRhaCBzaW5na2F0L3R5cG8gdXNl
::B64:agent.js:ciBkZW5nYW4gd2FqYXIsIGphbmdhbiBiZXJ0YW55YSBoYWwgeWFuZyBiaXNhIGRpdGViYWsuCi0gS2FtdSBtZW5naW5nYXQgcGVyY2FrYXBhbiBzZWJlbHVtbnlhLiBKYXdhYmFuIHNpbmdrYXQgdXNlciAobWlzYWxueWEgc2VidWFoIG5hbWEgZmlsZSkgYWRhbGFo
::B64:agent.js:IGphd2FiYW4gYXRhcyBwZXJ0YW55YWFubXUgc2ViZWx1bW55YTsgbGFuanV0a2FuIHR1Z2FzIGl0dSwgamFuZ2FuIG11bGFpIGRhcmkgbm9sLgotIE1lbWJ1a2EgYXBsaWthc2kgV2luZG93cyBsZXdhdCBvcGVuX3BhdGg6IGthbWVyYSA9IG1pY3Jvc29mdC53aW5k
::B64:agent.js:b3dzLmNhbWVyYTogLCBrYWxrdWxhdG9yID0gY2FsYyAsIG5vdGVwYWQgPSBub3RlcGFkICwgcGFpbnQgPSBtc3BhaW50ICwgcGVuZ2F0dXJhbiA9IG1zLXNldHRpbmdzOiAsIGZpbGUgZXhwbG9yZXIgPSBleHBsb3JlciAuCi0gVXBsb2FkIGZpbGUga2Ugd2Vic2l0
::B64:agent.js:ZTogb3Blbl91cmwga2UgaGFsYW1hbiB1cGxvYWQsIGluc3BlY3RfcGFnZSB1bnR1ayBtZW5jYXJpIGlucHV0IHR5cGU9ZmlsZSwgbGFsdSB1cGxvYWRfZmlsZSBkZW5nYW4gcGF0aCBsZW5na2FwIGZpbGUuIEppa2EgYnV0dWggbG9naW4sIHBhbmdnaWwgZG9uZSBk
::B64:agent.js:YW4gbWludGEgdXNlciBsb2dpbiBtYW51YWwgZGkgamVuZGVsYSBicm93c2VyLCBsYWx1IHVsYW5naS4KLSBGb2xkZXIgZGkgUEM6IGZpbmRfZm9sZGVyIGxhbHUgb3Blbl9wYXRoLiBGaWxlIGRpIFBDOiBmaW5kX2ZpbGUgKGF0YXUgbGlzdF9kaXIpIHVudHVrIG1l
::B64:agent.js:bmRhcGF0IHBhdGggbGVuZ2thcCwgbGFsdSBvcGVuX3BhdGggYXRhdSB1cGxvYWRfZmlsZS4gVGlkYWsgYWRhIGJhdGFzYW4gbG9rYXNpLCBzZW11YSBkcml2ZSBib2xlaCBkaWFrc2VzLgotIEFwbGlrYXNpL2plbmRlbGEgZGkgUEM6IHNjcmVlbnNob3QgZHVsdSB1
::B64:agent.js:bnR1ayBtZWxpaGF0IGxheWFyLCBsYWx1IGNsaWNrX3NjcmVlbi90eXBlX2Rlc2t0b3AvcHJlc3Nfa2V5cywgbGFsdSBzY3JlZW5zaG90IGxhZ2kgdW50dWsgbWVtZXJpa3NhIGhhc2lsLgotIEtvb3JkaW5hdCBrbGlrIGhhcnVzIGRhcmkgc2NyZWVuc2hvdCB0ZXJh
::B64:agent.js:a2hpci4KLSBVbnR1ayBvdG9tYXNpIHdlYnNpdGUgcGFrYWkgdG9vbCBicm93c2VyIChvcGVuX3VybCwgaW5zcGVjdF9wYWdlLCB0eXBlX3RleHQsIGNsaWNrLCB1cGxvYWRfZmlsZSkuIFNlbGFsdSBpbnNwZWN0X3BhZ2Ugc2ViZWx1bSBrbGlrLgotIEJ1dHVoIGxv
::B64:agent.js:Z2luLCBjYXB0Y2hhLCBhdGF1IHZlcmlmaWthc2k6IHBhbmdnaWwgd2FpdF9mb3JfdXNlciBkYW4gbWludGEgdXNlciBtZW5nZXJqYWthbm55YSBzZW5kaXJpIGRpIGplbmRlbGEgYnJvd3Nlci4gSkFOR0FOIHBlcm5haCBtZW1pbnRhIGF0YXUgbWVuZ2V0aWtrYW4g
::B64:agent.js:cGFzc3dvcmQgdXNlci4KLSBQZXJ0YW55YWFuIHlhbmcgYnV0dWggaW5mbyB0ZXJiYXJ1OiB3ZWJfc2VhcmNoLCBsYWx1IG9wZW5fdXJsIGRhbiBnZXRfcGFnZV90ZXh0IHVudHVrIG1lbWJhY2Egc3VtYmVybnlhLgotIEtvbnRyb2wgbXVzaWsvdmlkZW86IHlvdXR1
::B64:agent.js:YmVfY29udHJvbCB1bnR1ayB2aWRlbyBZb3VUdWJlLCBtZWRpYV9rZXkgdW50dWsgdm9sdW1lIGRhbiB0b21ib2wgbWVkaWEgc2VsdXJ1aCBQQy4KLSBUQUI6IEphbmdhbiBtZW5pbXBhIGhhbGFtYW4geWFuZyBtYXNpaCBkaXBha2FpLiBKaWthIHVzZXIgbWVueWVi
::B64:agent.js:dXQgInRhYiBiYXJ1IiwgYXRhdSBhZGEgdmlkZW8vaGFsYW1hbiBsYWluIHlhbmcgc2VkYW5nIHRlcmJ1a2EgKG1pc2FsbnlhIG11c2lrKSwgcGFrYWkgbmV3X3RhYj10cnVlIHBhZGEgb3Blbl91cmwsIHdlYl9zZWFyY2gsIGF0YXUgeW91dHViZV9wbGF5LiBCZWJl
::B64:agent.js:cmFwYSBzaXR1cyBzZWthbGlndXM6IG9wZW5fdXJscy4gUGluZGFoIHRhYjogbGlzdF90YWJzIGxhbHUgc3dpdGNoX3RhYiAoaW5kZXggLTEgPSB0YWIgdGVyYmFydSwgYXRhdSBtYXRjaCBqdWR1bCkuIFR1dHVwOiBjbG9zZV90YWIuCi0gVXBsb2FkIGJhbnlhayBm
::B64:agent.js:aWxlOiB1cGxvYWRfZmlsZSBkZW5nYW4gYmViZXJhcGEgcGF0aCBkaXBpc2FoIHwsIGF0YXUgZm9sZGVyIChkYW4gcGF0dGVybikuIEppa2EgaW5wdXQgaGFueWEgbWVuZXJpbWEgc2F0dSBmaWxlLCB1bGFuZ2kgcGVyIGZpbGUgc2FtcGFpIHNlbXVhIHNlbGVzYWku
::B64:agent.js:Ci0gSEVNQVQgTEFOR0tBSDogamlrYSBiZWJlcmFwYSBsYW5na2FoIHRpZGFrIHNhbGluZyBiZXJnYW50dW5nLCBwYW5nZ2lsIGJlYmVyYXBhIHRvb2wgc2VrYWxpZ3VzIGRhbGFtIHNhdHUgamF3YWJhbi4KLSBVUExPQUQ6IHNlbGFsdSBwYWthaSBmYXN0X3VwbG9h
::B64:agent.js:ZCAoc2F0dSBwYW5nZ2lsYW4sIG90b21hdGlzIG1lbmVtdWthbiB0b21ib2wgdXBsb2FkLCBtZW5kdWt1bmcgYmFueWFrIGZpbGUsIGZvbGRlciwgZGFuIHppcCkuIFBha2FpIHVwbG9hZF9maWxlIGhhbnlhIGppa2EgZmFzdF91cGxvYWQgZ2FnYWwuCi0gVm9sdW1l
::B64:agent.js:IGtlIGFuZ2thIHRlcnRlbnR1OiBzZXRfdm9sdW1lLiBGaWxlIHRlcmJhcnU6IHJlY2VudF9maWxlcy4KLSBNZW5naGFwdXMgZmlsZTogcGFrYWkgcmVjeWNsZV9wYXRoIChtYXN1ayBSZWN5Y2xlIEJpbiksIGphbmdhbiBtZW5naGFwdXMgcGVybWFuZW4uCi0gSmlr
::B64:agent.js:YSBhbGF0IHlhbmcga2FtdSBidXR1aGthbiB0aWRhayBhZGEgZGkgZGFmdGFyLCBwYW5nZ2lsIG1vcmVfdG9vbHMgZGVuZ2FuIGdydXA6IHlvdXR1YmUsIHRhYnMsIGRlc2t0b3AsIGZpbGVzLCBhdGF1IHBjLgotIEppa2EgYnVudHUgYXRhdSByYWd1LCBiZXJoZW50
::B64:agent.js:aSBkYW4gdGFueWEgdXNlci4KLSBKYXdhYiBkYWxhbSBCYWhhc2EgSW5kb25lc2lhLCBzaW5na2F0LiBKYW5nYW4gbWVuZ2FyYW5nIGhhc2lsOyBsYXBvcmthbiBhcGEgYWRhbnlhLmA7CgovLyA9PT09PSBLb211bmlrYXNpIGRlbmdhbiA5Um91dGVyICh0YWhhbiBi
::B64:agent.js:YW50aW5nKSA9PT09PQovLyBKaWthIGJhbGFzYW4ga29zb25nL2dhZ2FsLCBhZ2VudCBvdG9tYXRpczogKDEpIGNvYmEgdGFucGEgdG9vbF9jaG9pY2UsICgyKSBrZWNpbGthbiBkYWZ0YXIgYWxhdCBkYW4KLy8gcGFrYWkgYmFsYXNhbiBub24tc3RyZWFtaW5nLCAo
::B64:agent.js:MykgcGluZGFoIGtlIG1vZGVsIGxhaW4geWFuZyBkaXRlbXVrYW4gbGV3YXQgL21vZGVscy4KLy8gTW9kZWwgeWFuZyBiZXJoYXNpbCBkaWluZ2F0IHNlbGFtYSBzZXNpLiBQZXJpbnRhaCAvdGVzIGRhbiAvbW9kZWwgbWVtYmFudHUgbWVtaWxpaCBtb2RlbCBwYWxp
::B64:agent.js:bmcgc3RhYmlsLgpjb25zdCBNT0RFTF9GSUxFID0gIm1vZGVsLnR4dCI7CmxldCBiYXNlTW9kZWwgPSBNT0RFTDsKdHJ5IHsKICBjb25zdCBzYXZlZCA9IGZzLnJlYWRGaWxlU3luYyhNT0RFTF9GSUxFLCAidXRmOCIpLnRyaW0oKTsKICBpZiAoc2F2ZWQpIGJhc2VN
::B64:agent.js:b2RlbCA9IHNhdmVkOwp9IGNhdGNoIHt9CgpsZXQgdXNlVG9vbENob2ljZSA9IHRydWU7IC8vIHBha3NhIG1vZGVsIHNlbGFsdSBtZW1hbmdnaWwgdG9vbDsgZGltYXRpa2FuIG90b21hdGlzIGppa2EgYmVybWFzYWxhaApsZXQgc2xpbU1vZGUgPSBwcm9jZXNzLmVu
::B64:agent.js:di5TTElNICE9PSAiMCI7IC8vIHRydWUgPSBraXJpbSBoYW55YSBhbGF0IHlhbmcgcmVsZXZhbiAobXVhdGFuIGtlY2lsID0gbGViaWggY2VwYXQpCmxldCBmYWxsYmFja01vZGVscyA9IG51bGw7IC8vIGRpaXNpIHNhYXQgcGVydGFtYSBrYWxpIGRpYnV0dWhrYW4K
::B64:agent.js:bGV0IHBvb2xJZHggPSAwOwpjb25zdCBleHRyYUdyb3VwcyA9IG5ldyBTZXQoKTsKY29uc3QgQkFDS09GRiA9IE51bWJlcihwcm9jZXNzLmVudi5CQUNLT0ZGX01TIHx8IDEwMDApOwoKY29uc3QgVE9PTF9HUk9VUFMgPSB7CiAgeW91dHViZTogWyJ5b3V0dWJlX3Bs
::B64:agent.js:YXkiLCAieW91dHViZV9jb250cm9sIl0sCiAgdGFiczogWyJuZXdfdGFiIiwgIm9wZW5fdXJscyIsICJsaXN0X3RhYnMiLCAic3dpdGNoX3RhYiIsICJjbG9zZV90YWIiLCAic2Nyb2xsX3BhZ2UiLCAid2ViX3NlYXJjaCJdLAogIGRlc2t0b3A6IFsiY2xpY2tfc2Ny
::B64:agent.js:ZWVuIiwgInNjcm9sbF9zY3JlZW4iLCAidHlwZV9kZXNrdG9wIiwgInByZXNzX2tleXMiLCAid2FpdCIsICJsaXN0X3dpbmRvd3MiLCAiZm9jdXNfd2luZG93IiwgImNsb3NlX3dpbmRvdyJdLAogIGZpbGVzOiBbInJlYWRfdGV4dF9maWxlIiwgIndyaXRlX3RleHRf
::B64:agent.js:ZmlsZSIsICJtYWtlX2ZvbGRlciIsICJtb3ZlX3BhdGgiLCAiY29weV9wYXRoIiwgInJlY3ljbGVfcGF0aCIsICJ6aXBfcGF0aCIsICJ1bnppcF9wYXRoIiwgImRvd25sb2FkX2ZpbGUiLCAicmVjZW50X2ZpbGVzIiwgInNlYXJjaF90ZXh0Il0sCiAgcGM6IFsibWVk
::B64:agent.js:aWFfa2V5IiwgInNldF92b2x1bWUiLCAiY2xpcGJvYXJkX2dldCIsICJjbGlwYm9hcmRfc2V0IiwgInN5c3RlbV9pbmZvIiwgInNhdmVfc2NyZWVuc2hvdCIsICJzcGVhayIsICJzZXRfdGltZXIiXSwKfTsKY29uc3QgQ09SRV9UT09MUyA9IFsKICAiZG9uZSIsICJ3
::B64:agent.js:YWl0X2Zvcl91c2VyIiwgIm1vcmVfdG9vbHMiLCAibm93IiwgIm9wZW5fdXJsIiwgImdldF9wYWdlX3RleHQiLCAiaW5zcGVjdF9wYWdlIiwgInR5cGVfdGV4dCIsICJjbGljayIsCiAgInVwbG9hZF9maWxlIiwgImZhc3RfdXBsb2FkIiwgImxpc3RfZmlsZXMiLCAi
::B64:agent.js:ZmluZF9mb2xkZXIiLCAiZmluZF9maWxlIiwgImxpc3RfZGlyIiwgIm9wZW5fcGF0aCIsICJzY3JlZW5zaG90IiwKXTsKY29uc3QgR1JPVVBfS0VZV09SRFMgPSB7CiAgeW91dHViZTogL3lvdXR1YmV8dmlkZW98bGFndXxtdXNpa3xtdXNpY3xwdXRhcnxub250b258
::B64:agent.js:ZGVuZ2FyfHBhdXNlfG5leHQvaSwKICB0YWJzOiAvXGJ0YWJcYnxjYXJpfHNlYXJjaHxnb29nbGV8d2VifGludGVybmV0fHNpdHVzfHdlYnNpdGV8c2VrYWxpZ3VzL2ksCiAgZGVza3RvcDogL2tsaWt8bGF5YXJ8bW91c2V8a2V0aWt8amVuZGVsYXx3aW5kb3d8YXBs
::B64:agent.js:aWthc2l8c2NyZWVuc2hvdHxzY3JvbGx8dG9tYm9sL2ksCiAgZmlsZXM6IC9maWxlfGZvbGRlcnx6aXB8aGFwdXN8cGluZGFofHR1bGlzfGJhY2F8dW5kdWh8ZG93bmxvYWR8YnVhdHxnYW50aSBuYW1hfHNhbGlufGNvcHl8dGVyYmFydXxjYXJpIHRla3MvaSwKICBw
::B64:agent.js:YzogL3ZvbHVtZXxzdWFyYXxjbGlwYm9hcmR8c2FsaW58XGJyYW1cYnxjcHV8YmF0ZXJhaXxzaXN0ZW18bWVkaWF8bXV0ZXx0aW1lcnxpbmdhdGthbnxwZW5naW5nYXR8dWNhcHxiaWNhcmF8c2NyZWVuc2hvdHx0YW5na2FwL2ksCn07CgovLyBQaWxpaCBhbGF0IHlh
::B64:agent.js:bmcgcmVsZXZhbiBzYWphIChkaXBha2FpIHNhYXQgbXVhdGFuIHBlcmx1IGRpa2VjaWxrYW4pCmZ1bmN0aW9uIHNlbGVjdFRvb2xzKG1lc3NhZ2VzKSB7CiAgY29uc3QgbmFtZXMgPSBuZXcgU2V0KENPUkVfVE9PTFMpOwogIGNvbnN0IHVzZXJUZXh0ID0gbWVzc2Fn
::B64:agent.js:ZXMKICAgIC5maWx0ZXIoKG0pID0+IG0ucm9sZSA9PT0gInVzZXIiICYmIHR5cGVvZiBtLmNvbnRlbnQgPT09ICJzdHJpbmciICYmICFtLmNvbnRlbnQuc3RhcnRzV2l0aCgiS2FtdSBoYXJ1cyBtZW1hbmdnaWwgdG9vbCIpKQogICAgLnNsaWNlKC00KQogICAgLm1h
::B64:agent.js:cCgobSkgPT4gbS5jb250ZW50KQogICAgLmpvaW4oIiAiKTsKICBmb3IgKGNvbnN0IFtnLCByZV0gb2YgT2JqZWN0LmVudHJpZXMoR1JPVVBfS0VZV09SRFMpKSB7CiAgICBpZiAocmUudGVzdCh1c2VyVGV4dCkgfHwgZXh0cmFHcm91cHMuaGFzKGcpKSBUT09MX0dS
::B64:agent.js:T1VQU1tnXS5mb3JFYWNoKChuKSA9PiBuYW1lcy5hZGQobikpOwogIH0KICBmb3IgKGNvbnN0IG0gb2YgbWVzc2FnZXMpIGZvciAoY29uc3QgYyBvZiBtLnRvb2xfY2FsbHMgfHwgW10pIG5hbWVzLmFkZChjLmZ1bmN0aW9uLm5hbWUpOyAvLyBhbGF0IHlhbmcgc3Vk
::B64:agent.js:YWggZGlwYWthaSB0ZXRhcCBhZGEKICByZXR1cm4gdG9vbHMuZmlsdGVyKCh0KSA9PiBuYW1lcy5oYXModC5mdW5jdGlvbi5uYW1lKSk7Cn0KCmNvbnN0IG1vZGVsUG9vbCA9ICgpID0+IFtiYXNlTW9kZWwsIC4uLihmYWxsYmFja01vZGVscyB8fCBbXSkuZmlsdGVy
::B64:agent.js:KChtKSA9PiBtICE9PSBiYXNlTW9kZWwpXTsKCmFzeW5jIGZ1bmN0aW9uIGRpc2NvdmVyTW9kZWxzKCkgewogIGlmIChwcm9jZXNzLmVudi5ST1VURVJfRkFMTEJBQ0tfTU9ERUxTKSB7CiAgICByZXR1cm4gcHJvY2Vzcy5lbnYuUk9VVEVSX0ZBTExCQUNLX01PREVM
::B64:agent.js:Uy5zcGxpdCgiLCIpLm1hcCgoeCkgPT4geC50cmltKCkpLmZpbHRlcihCb29sZWFuKTsKICB9CiAgdHJ5IHsKICAgIGNvbnN0IHJlcyA9IGF3YWl0IGZldGNoKGAke0JBU0VfVVJMfS9tb2RlbHNgLCB7CiAgICAgIGhlYWRlcnM6IHsgQXV0aG9yaXphdGlvbjogYEJl
::B64:agent.js:YXJlciAke0FQSV9LRVl9YCB9LAogICAgICBzaWduYWw6IEFib3J0U2lnbmFsLnRpbWVvdXQoMTAwMDApLAogICAgfSk7CiAgICBpZiAoIXJlcy5vaykgcmV0dXJuIFtdOwogICAgY29uc3QgZGF0YSA9IChhd2FpdCByZXMuanNvbigpKS5kYXRhIHx8IFtdOwogICAg
::B64:agent.js:Y29uc3QgYmFkID0gL2VtYmVkfHdoaXNwZXJ8dHRzfGltYWdlfGF1ZGlvfHJlcmFua3xtb2RlcmF0fGRhbGx8Zmx1eHxzZHhsfHZpZGVvfHNwZWVjaHx0cmFuc2NyaS9pOwogICAgY29uc3Qgc2NvcmUgPSAoaWQpID0+CiAgICAgICgvY2xhdWRlL2kudGVzdChpZCkg
::B64:agent.js:PyAzIDogMCkgKyAoL2dlbWluaS9pLnRlc3QoaWQpID8gMyA6IDApICsgKC9ncHR8Z2xtfHF3ZW58a2ltaXxkZWVwc2Vlay9pLnRlc3QoaWQpID8gMiA6IDApICsKICAgICAgKC9oYWlrdXxmbGFzaHxzb25uZXQvaS50ZXN0KGlkKSA/IDEgOiAwKSAtICgvdGhpbmtp
::B64:agent.js:bmd8YWdlbnRpYy9pLnRlc3QoaWQpID8gMiA6IDApOwogICAgcmV0dXJuIGRhdGEKICAgICAgLm1hcCgobSkgPT4gbS5pZCkKICAgICAgLmZpbHRlcigoaWQpID0+IGlkICYmIGlkICE9PSBiYXNlTW9kZWwgJiYgIWJhZC50ZXN0KGlkKSkKICAgICAgLnNvcnQoKHgs
::B64:agent.js:IHkpID0+IHNjb3JlKHkpIC0gc2NvcmUoeCkpCiAgICAgIC5zbGljZSgwLCA4KTsKICB9IGNhdGNoIHsKICAgIHJldHVybiBbXTsKICB9Cn0KCmZ1bmN0aW9uIGZhdGFsKG1zZykgewogIGNvbnN0IGUgPSBuZXcgRXJyb3IobXNnKTsKICBlLmZhdGFsID0gdHJ1ZTsK
::B64:agent.js:ICByZXR1cm4gZTsKfQoKLy8gQmFjYSBiYWxhc2FuIDlSb3V0ZXIgKEpTT04gYmlhc2EgYXRhdSBzdHJlYW1pbmcgU1NFKSBtZW5qYWRpIHNhdHUgcGVzYW4KZnVuY3Rpb24gcGFyc2VDaGF0KHJhdykgewogIGlmICghcmF3LnRyaW0oKSkgcmV0dXJuIHsgbXNnOiBu
::B64:agent.js:dWxsLCBlcnI6ICJrb3NvbmciIH07CiAgaWYgKCEvKF58XG4pZGF0YTovLnRlc3QocmF3KSkgewogICAgbGV0IG9iajsKICAgIHRyeSB7CiAgICAgIG9iaiA9IEpTT04ucGFyc2UocmF3KTsKICAgIH0gY2F0Y2ggewogICAgICByZXR1cm4geyBtc2c6IG51bGwsIGVy
::B64:agent.js:cjogImJ1a2FuIEpTT04iIH07CiAgICB9CiAgICBpZiAob2JqLmVycm9yKSByZXR1cm4geyBtc2c6IG51bGwsIGVycjogSlNPTi5zdHJpbmdpZnkob2JqLmVycm9yKS5zbGljZSgwLCAxNTApIH07CiAgICBjb25zdCBtID0gb2JqLmNob2ljZXM/LlswXT8ubWVzc2Fn
::B64:agent.js:ZTsKICAgIGlmICghbSB8fCAoIW0uY29udGVudCAmJiAhbS50b29sX2NhbGxzPy5sZW5ndGgpKSByZXR1cm4geyBtc2c6IG51bGwsIGVycjogInRhbnBhIGlzaSIgfTsKICAgIHJldHVybiB7IG1zZzogbSwgZXJyOiAiIiB9OwogIH0KICBsZXQgY29udGVudCA9ICIi
::B64:agent.js:OwogIGxldCBzc2VFcnIgPSAiIjsKICBjb25zdCBjYWxscyA9IFtdOwogIGZvciAoY29uc3QgbGluZSBvZiByYXcuc3BsaXQoIlxuIikpIHsKICAgIGlmICghbGluZS5zdGFydHNXaXRoKCJkYXRhOiIpKSBjb250aW51ZTsKICAgIGNvbnN0IGRhdGEgPSBsaW5lLnNs
::B64:agent.js:aWNlKDUpLnRyaW0oKTsKICAgIGlmICghZGF0YSB8fCBkYXRhID09PSAiW0RPTkVdIikgY29udGludWU7CiAgICBsZXQgY2h1bms7CiAgICB0cnkgewogICAgICBjaHVuayA9IEpTT04ucGFyc2UoZGF0YSk7CiAgICB9IGNhdGNoIHsKICAgICAgY29udGludWU7CiAg
::B64:agent.js:ICB9CiAgICBpZiAoY2h1bmsuZXJyb3IpIHNzZUVyciA9IEpTT04uc3RyaW5naWZ5KGNodW5rLmVycm9yKS5zbGljZSgwLCAxNTApOwogICAgY29uc3QgY2hvaWNlID0gY2h1bmsuY2hvaWNlcz8uWzBdOwogICAgY29uc3QgZGVsdGEgPSBjaG9pY2U/LmRlbHRhIHx8
::B64:agent.js:IGNob2ljZT8ubWVzc2FnZSB8fCB7fTsKICAgIGlmIChkZWx0YS5jb250ZW50KSBjb250ZW50ICs9IGRlbHRhLmNvbnRlbnQ7CiAgICBmb3IgKGNvbnN0IHRjIG9mIGRlbHRhLnRvb2xfY2FsbHMgfHwgW10pIHsKICAgICAgY29uc3QgaSA9IHRjLmluZGV4ID8/IDA7
::B64:agent.js:CiAgICAgIGNhbGxzW2ldID8/PSB7IGlkOiAiIiwgdHlwZTogImZ1bmN0aW9uIiwgZnVuY3Rpb246IHsgbmFtZTogIiIsIGFyZ3VtZW50czogIiIgfSB9OwogICAgICBpZiAodGMuaWQpIGNhbGxzW2ldLmlkID0gdGMuaWQ7CiAgICAgIGlmICh0Yy5mdW5jdGlvbj8u
::B64:agent.js:bmFtZSkgY2FsbHNbaV0uZnVuY3Rpb24ubmFtZSArPSB0Yy5mdW5jdGlvbi5uYW1lOwogICAgICBpZiAodGMuZnVuY3Rpb24/LmFyZ3VtZW50cykgY2FsbHNbaV0uZnVuY3Rpb24uYXJndW1lbnRzICs9IHRjLmZ1bmN0aW9uLmFyZ3VtZW50czsKICAgIH0KICB9CiAg
::B64:agent.js:Y29uc3QgdmFsaWQgPSBjYWxscy5maWx0ZXIoQm9vbGVhbikubWFwKChjLCBpKSA9PiAoeyAuLi5jLCBpZDogYy5pZCB8fCBgY2FsbF8ke2l9YCB9KSk7CiAgaWYgKCFjb250ZW50ICYmICF2YWxpZC5sZW5ndGgpIHJldHVybiB7IG1zZzogbnVsbCwgZXJyOiBzc2VF
::B64:agent.js:cnIgfHwgInRhbnBhIGlzaSIgfTsKICBjb25zdCBtc2cgPSB7IHJvbGU6ICJhc3Npc3RhbnQiLCBjb250ZW50OiBjb250ZW50IHx8IG51bGwgfTsKICBpZiAodmFsaWQubGVuZ3RoKSBtc2cudG9vbF9jYWxscyA9IHZhbGlkOwogIHJldHVybiB7IG1zZywgZXJyOiAi
::B64:agent.js:IiB9Owp9Cgphc3luYyBmdW5jdGlvbiByZXF1ZXN0T25jZShtZXNzYWdlcywgeyBtb2RlbCwgdG9vbENob2ljZSwgc3RyZWFtLCBzbGltIH0pIHsKICBjb25zdCB0b29sTGlzdCA9IHNsaW0gPyBzZWxlY3RUb29scyhtZXNzYWdlcykgOiB0b29scy5maWx0ZXIoKHQp
::B64:agent.js:ID0+IHQuZnVuY3Rpb24ubmFtZSAhPT0gIm1vcmVfdG9vbHMiKTsKICBjb25zdCBib2R5ID0geyBtb2RlbCwgbWVzc2FnZXMsIHRvb2xzOiB0b29sTGlzdCwgc3RyZWFtIH07CiAgaWYgKHRvb2xDaG9pY2UpIGJvZHkudG9vbF9jaG9pY2UgPSAicmVxdWlyZWQiOwog
::B64:agent.js:IGNvbnN0IHJlcyA9IGF3YWl0IGZldGNoKGAke0JBU0VfVVJMfS9jaGF0L2NvbXBsZXRpb25zYCwgewogICAgbWV0aG9kOiAiUE9TVCIsCiAgICBoZWFkZXJzOiB7ICJDb250ZW50LVR5cGUiOiAiYXBwbGljYXRpb24vanNvbiIsIEF1dGhvcml6YXRpb246IGBCZWFy
::B64:agent.js:ZXIgJHtBUElfS0VZfWAgfSwKICAgIGJvZHk6IEpTT04uc3RyaW5naWZ5KGJvZHkpLAogICAgc2lnbmFsOiBBYm9ydFNpZ25hbC50aW1lb3V0KDEyMDAwMCksCiAgfSk7CiAgaWYgKCFyZXMub2spIHsKICAgIGNvbnN0IGVyclRleHQgPSAoYXdhaXQgcmVzLnRleHQo
::B64:agent.js:KSkucmVwbGFjZSgvXHMrL2csICIgIikuc2xpY2UoMCwgMjAwKTsKICAgIGlmIChyZXMuc3RhdHVzID09PSA0MDEgfHwgcmVzLnN0YXR1cyA9PT0gNDAzKSB0aHJvdyBmYXRhbChgQVBJIGtleSBkaXRvbGFrICgke3Jlcy5zdGF0dXN9KS4gSmFsYW5rYW46IHN0YXJ0
::B64:agent.js:LWFnZW50LmJhdCByZXNldGApOwogICAgY29uc3QgZSA9IG5ldyBFcnJvcihgSFRUUCAke3Jlcy5zdGF0dXN9ICR7ZXJyVGV4dH1gKTsKICAgIGlmIChyZXMuc3RhdHVzID09PSA0MjkpIGUud2FpdCA9IE1hdGgubWluKE51bWJlcihyZXMuaGVhZGVycy5nZXQoInJl
::B64:agent.js:dHJ5LWFmdGVyIikpIHx8IDUsIDE1KSAqIDEwMDA7CiAgICB0aHJvdyBlOwogIH0KICBjb25zdCByYXcgPSBhd2FpdCByZXMudGV4dCgpOwogIGNvbnN0IHsgbXNnLCBlcnIgfSA9IHBhcnNlQ2hhdChyYXcpOwogIGlmICghbXNnKSB7CiAgICBjb25zdCBwZWVrID0g
::B64:agent.js:YFtIVFRQICR7cmVzLnN0YXR1c30sICR7cmF3Lmxlbmd0aH0gYnl0ZSR7cmF3LnRyaW0oKSA/ICI6ICIgKyByYXcucmVwbGFjZSgvXHMrL2csICIgIikuc2xpY2UoMCwgMTAwKSA6ICIifV1gOwogICAgdGhyb3cgbmV3IEVycm9yKGByZXNwb25zICR7ZXJyfSAke3Bl
::B64:agent.js:ZWt9YCk7CiAgfQogIHJldHVybiBtc2c7Cn0KCmFzeW5jIGZ1bmN0aW9uIGNhbGxMTE0obWVzc2FnZXMpIHsKICBjb25zdCBBVFRFTVBUUyA9IDc7CiAgbGV0IGxhc3RFcnIgPSAiIjsKICBmb3IgKGxldCBhdHRlbXB0ID0gMTsgYXR0ZW1wdCA8PSBBVFRFTVBUUzsg
::B64:agent.js:YXR0ZW1wdCsrKSB7CiAgICBpZiAoYXR0ZW1wdCA+PSAzKSBzbGltTW9kZSA9IHRydWU7IC8vIGtlY2lsa2FuIG11YXRhbiBhbGF0CiAgICBpZiAoYXR0ZW1wdCA+PSA0KSB7CiAgICAgIC8vIFBpbmRhaCBrZSBtb2RlbCBsYWluCiAgICAgIGlmICghZmFsbGJhY2tN
::B64:agent.js:b2RlbHMpIGZhbGxiYWNrTW9kZWxzID0gYXdhaXQgZGlzY292ZXJNb2RlbHMoKTsKICAgICAgY29uc3QgcG9vbCA9IG1vZGVsUG9vbCgpOwogICAgICBpZiAocG9vbC5sZW5ndGggPiAxKSB7CiAgICAgICAgcG9vbElkeCA9IChwb29sSWR4ICsgMSkgJSBwb29sLmxl
::B64:agent.js:bmd0aDsKICAgICAgICBjb25zb2xlLmxvZyhgICAobWVuY29iYSBtb2RlbCBsYWluOiAke3Bvb2xbcG9vbElkeF19KWApOwogICAgICB9CiAgICB9CiAgICBjb25zdCBwb29sID0gbW9kZWxQb29sKCk7CiAgICBjb25zdCBtb2RlbCA9IHBvb2xbcG9vbElkeCAlIHBv
::B64:agent.js:b2wubGVuZ3RoXTsKICAgIHRyeSB7CiAgICAgIGNvbnN0IG1zZyA9IGF3YWl0IHJlcXVlc3RPbmNlKG1lc3NhZ2VzLCB7CiAgICAgICAgbW9kZWwsCiAgICAgICAgdG9vbENob2ljZTogYXR0ZW1wdCA9PT0gMSAmJiB1c2VUb29sQ2hvaWNlLAogICAgICAgIHN0cmVh
::B64:agent.js:bTogYXR0ZW1wdCA8IDMgfHwgYXR0ZW1wdCAlIDIgPT09IDAsCiAgICAgICAgc2xpbTogc2xpbU1vZGUsCiAgICAgIH0pOwogICAgICBjb25zdCBjbGVhbiA9IHsgcm9sZTogImFzc2lzdGFudCIsIGNvbnRlbnQ6IG1zZy5jb250ZW50ID8/IG51bGwgfTsKICAgICAg
::B64:agent.js:aWYgKG1zZy50b29sX2NhbGxzPy5sZW5ndGgpIGNsZWFuLnRvb2xfY2FsbHMgPSBtc2cudG9vbF9jYWxsczsKICAgICAgcmV0dXJuIGNsZWFuOwogICAgfSBjYXRjaCAoZSkgewogICAgICBpZiAoZS5mYXRhbCkgdGhyb3cgZTsKICAgICAgbGFzdEVyciA9IGUubWVz
::B64:agent.js:c2FnZTsKICAgICAgaWYgKGF0dGVtcHQgPT09IDEpIHVzZVRvb2xDaG9pY2UgPSBmYWxzZTsKICAgIH0KICAgIGlmIChhdHRlbXB0IDwgQVRURU1QVFMpIHsKICAgICAgY29uc29sZS5sb2coYCAgKDlSb3V0ZXIgYmVybWFzYWxhaDogJHtsYXN0RXJyLnNsaWNlKDAs
::B64:agent.js:IDE0MCl9LiBNZW5jb2JhIHVsYW5nICR7YXR0ZW1wdH0vJHtBVFRFTVBUUyAtIDF9Li4uKWApOwogICAgICBhd2FpdCBzbGVlcChNYXRoLm1pbihCQUNLT0ZGICogYXR0ZW1wdCwgNDAwMCkpOwogICAgfQogIH0KICB0aHJvdyBuZXcgRXJyb3IoCiAgICBgOVJvdXRl
::B64:agent.js:ciBnYWdhbCBtZXJlc3BvbnMgc2V0ZWxhaCAke0FUVEVNUFRTfSBwZXJjb2JhYW4gKCR7bGFzdEVyci5zbGljZSgwLCAxNjApfSkuIGAgKwogICAgICBgS2V0aWsgL3RlcyB1bnR1ayBtZW5ndWppIG1vZGVsIGRhbiBtZW1pbGloIHlhbmcgc3RhYmlsLiBDZWsganVn
::B64:agent.js:YSBkYXNoYm9hcmQgOVJvdXRlciwgbWVudSBDb25zb2xlIExvZy5gCiAgKTsKfQoKLy8gVWppIHNhdHUgbW9kZWwgZGVuZ2FuIHBlcm1pbnRhYW4ga2VjaWwgeWFuZyBtZW1pbnRhIHBlbWFuZ2dpbGFuIHRvb2wKYXN5bmMgZnVuY3Rpb24gdGVzdE1vZGVsKG1vZGVs
::B64:agent.js:KSB7CiAgY29uc3QgdDAgPSBEYXRlLm5vdygpOwogIGNvbnN0IHBpbmdUb29sID0gWwogICAgewogICAgICB0eXBlOiAiZnVuY3Rpb24iLAogICAgICBmdW5jdGlvbjogewogICAgICAgIG5hbWU6ICJwaW5nIiwKICAgICAgICBkZXNjcmlwdGlvbjogIlRlcyBrb25l
::B64:agent.js:a3NpIiwKICAgICAgICBwYXJhbWV0ZXJzOiB7IHR5cGU6ICJvYmplY3QiLCBwcm9wZXJ0aWVzOiB7IHBlc2FuOiB7IHR5cGU6ICJzdHJpbmciIH0gfSwgcmVxdWlyZWQ6IFsicGVzYW4iXSB9LAogICAgICB9LAogICAgfSwKICBdOwogIHRyeSB7CiAgICBjb25zdCBy
::B64:agent.js:ZXMgPSBhd2FpdCBmZXRjaChgJHtCQVNFX1VSTH0vY2hhdC9jb21wbGV0aW9uc2AsIHsKICAgICAgbWV0aG9kOiAiUE9TVCIsCiAgICAgIGhlYWRlcnM6IHsgIkNvbnRlbnQtVHlwZSI6ICJhcHBsaWNhdGlvbi9qc29uIiwgQXV0aG9yaXphdGlvbjogYEJlYXJlciAk
::B64:agent.js:e0FQSV9LRVl9YCB9LAogICAgICBib2R5OiBKU09OLnN0cmluZ2lmeSh7CiAgICAgICAgbW9kZWwsCiAgICAgICAgbWVzc2FnZXM6IFt7IHJvbGU6ICJ1c2VyIiwgY29udGVudDogIlBhbmdnaWwgdG9vbCBwaW5nIGRlbmdhbiBwZXNhbiBvay4iIH1dLAogICAgICAg
::B64:agent.js:IHRvb2xzOiBwaW5nVG9vbCwKICAgICAgICBzdHJlYW06IGZhbHNlLAogICAgICB9KSwKICAgICAgc2lnbmFsOiBBYm9ydFNpZ25hbC50aW1lb3V0KDQ1MDAwKSwKICAgIH0pOwogICAgY29uc3QgcmF3ID0gYXdhaXQgcmVzLnRleHQoKTsKICAgIGNvbnN0IG1zID0g
::B64:agent.js:RGF0ZS5ub3coKSAtIHQwOwogICAgaWYgKCFyZXMub2spIHJldHVybiB7IG1hcms6ICJbWF0gIiwgbXMsIHRleHQ6IGBIVFRQICR7cmVzLnN0YXR1c30gJHtyYXcucmVwbGFjZSgvXHMrL2csICIgIikuc2xpY2UoMCwgNzApfWAgfTsKICAgIGNvbnN0IHsgbXNnLCBl
::B64:agent.js:cnIgfSA9IHBhcnNlQ2hhdChyYXcpOwogICAgaWYgKCFtc2cpIHJldHVybiB7IG1hcms6ICJbWF0gIiwgbXMsIHRleHQ6IGByZXNwb25zICR7ZXJyfWAgfTsKICAgIGlmIChtc2cudG9vbF9jYWxscz8ubGVuZ3RoKSByZXR1cm4geyBtYXJrOiAiW09LXSIsIG1zLCB0
::B64:agent.js:ZXh0OiAidG9vbCBjYWxsaW5nIGJlcmZ1bmdzaSIgfTsKICAgIHJldHVybiB7IG1hcms6ICJbfl0gIiwgbXMsIHRleHQ6ICJtZW5qYXdhYiB0YXBpIHRpZGFrIG1lbWFuZ2dpbCB0b29sIChrdXJhbmcgY29jb2sgdW50dWsgYWdlbnQpIiB9OwogIH0gY2F0Y2ggKGUp
::B64:agent.js:IHsKICAgIHJldHVybiB7IG1hcms6ICJbWF0gIiwgbXM6IERhdGUubm93KCkgLSB0MCwgdGV4dDogZS5uYW1lID09PSAiVGltZW91dEVycm9yIiA/ICJ0aW1lb3V0IiA6IGUubWVzc2FnZS5zbGljZSgwLCA3MCkgfTsKICB9Cn0KCi8vID09PT09IEphbHVyIGNlcGF0
::B64:agent.js:OiBwZXJpbnRhaCB1bXVtIGxhbmdzdW5nIGRpamFsYW5rYW4gVEFOUEEgQUkgKGhhc2lsIGRhbGFtIGhpdHVuZ2FuIGRldGlrKSA9PT09PQovLyBKaWthIHBlcmludGFoIHRpZGFrIGRpa2VuYWxpIGF0YXUgamFsdXIgY2VwYXQgZ2FnYWwsIG90b21hdGlzIGRpc2Vy
::B64:agent.js:YWhrYW4ga2UgQUkuCmxldCBGQVNUID0gcHJvY2Vzcy5lbnYuRkFTVCAhPT0gIjAiOwoKY29uc3QgdGlkeSA9IChzKSA9PgogIFN0cmluZyhzKQogICAgLnJlcGxhY2UoL1xzKyhkb25nfHlhfHlhaHxkZWh8YWphfGRvbmt8c2lofG5paHxwbGVhc2V8cGxzfHBsaXN8
::B64:agent.js:ZHVsdSlccyokL2ksICIiKQogICAgLnJlcGxhY2UoL1suIT9dKyQvLCAiIikKICAgIC50cmltKCk7Cgpjb25zdCBLTk9XTl9TSVRFUyA9IHsKICB5b3V0dWJlOiAieW91dHViZS5jb20iLCB5dDogInlvdXR1YmUuY29tIiwgZ29vZ2xlOiAiZ29vZ2xlLmNvbSIsIGdt
::B64:agent.js:YWlsOiAibWFpbC5nb29nbGUuY29tIiwgZ2l0aHViOiAiZ2l0aHViLmNvbSIsCiAgdGlrdG9rOiAidGlrdG9rLmNvbSIsIGZhY2Vib29rOiAiZmFjZWJvb2suY29tIiwgZmI6ICJmYWNlYm9vay5jb20iLCBpbnN0YWdyYW06ICJpbnN0YWdyYW0uY29tIiwgaWc6ICJp
::B64:agent.js:bnN0YWdyYW0uY29tIiwKICB0d2l0dGVyOiAieC5jb20iLCB4OiAieC5jb20iLCB3aGF0c2FwcDogIndlYi53aGF0c2FwcC5jb20iLCB3YTogIndlYi53aGF0c2FwcC5jb20iLCBtZWRpYWZpcmU6ICJtZWRpYWZpcmUuY29tIiwKICBkcml2ZTogImRyaXZlLmdvb2ds
::B64:agent.js:ZS5jb20iLCBtYXBzOiAibWFwcy5nb29nbGUuY29tIiwgbmV0ZmxpeDogIm5ldGZsaXguY29tIiwgc3BvdGlmeTogIm9wZW4uc3BvdGlmeS5jb20iLAogIGNoYXRncHQ6ICJjaGF0Z3B0LmNvbSIsIGNsYXVkZTogImNsYXVkZS5haSIsIGdlbWluaTogImdlbWluaS5n
::B64:agent.js:b29nbGUuY29tIiwgdG9rb3BlZGlhOiAidG9rb3BlZGlhLmNvbSIsCiAgc2hvcGVlOiAic2hvcGVlLmNvLmlkIiwgdGVsZWdyYW06ICJ3ZWIudGVsZWdyYW0ub3JnIiwgbGlua2VkaW46ICJsaW5rZWRpbi5jb20iLCBwaW50ZXJlc3Q6ICJwaW50ZXJlc3QuY29tIiwK
::B64:agent.js:ICB0d2l0Y2g6ICJ0d2l0Y2gudHYiLCBkaXNjb3JkOiAiZGlzY29yZC5jb20iLCByZWRkaXQ6ICJyZWRkaXQuY29tIiwgd2lraXBlZGlhOiAiaWQud2lraXBlZGlhLm9yZyIsCn07CmNvbnN0IFVQTE9BRF9TSVRFUyA9IHsKICBtZWRpYWZpcmU6ICJodHRwczovL2Fw
::B64:agent.js:cC5tZWRpYWZpcmUuY29tL215ZmlsZXMiLCBnb2ZpbGU6ICJodHRwczovL2dvZmlsZS5pbyIsIHBpeGVsZHJhaW46ICJodHRwczovL3BpeGVsZHJhaW4uY29tIiwKICBjYXRib3g6ICJodHRwczovL2NhdGJveC5tb2UiLCB3ZXRyYW5zZmVyOiAiaHR0cHM6Ly93ZXRy
::B64:agent.js:YW5zZmVyLmNvbSIsIGRyaXZlOiAiaHR0cHM6Ly9kcml2ZS5nb29nbGUuY29tL2RyaXZlL215LWRyaXZlIiwKICB0bXBmaWxlczogImh0dHBzOi8vdG1wZmlsZXMub3JnIiwgZmlsZWJpbjogImh0dHBzOi8vZmlsZWJpbi5uZXQiLAp9Owpjb25zdCBBUFBTID0gewog
::B64:agent.js:IGthbWVyYTogIm1pY3Jvc29mdC53aW5kb3dzLmNhbWVyYToiLCBjYW1lcmE6ICJtaWNyb3NvZnQud2luZG93cy5jYW1lcmE6Iiwgbm90ZXBhZDogIm5vdGVwYWQiLCBrYWxrdWxhdG9yOiAiY2FsYyIsCiAgY2FsY3VsYXRvcjogImNhbGMiLCBwYWludDogIm1zcGFp
::B64:agent.js:bnQiLCBwZW5nYXR1cmFuOiAibXMtc2V0dGluZ3M6Iiwgc2V0dGluZ3M6ICJtcy1zZXR0aW5nczoiLCAiZmlsZSBleHBsb3JlciI6ICJleHBsb3JlciIsCiAgZXhwbG9yZXI6ICJleHBsb3JlciIsIGNtZDogImNtZCIsICJ0YXNrIG1hbmFnZXIiOiAidGFza21nciIs
::B64:agent.js:ICJwZW5nZWxvbGEgdHVnYXMiOiAidGFza21nciIsICJyZWN5Y2xlIGJpbiI6ICJzaGVsbDpSZWN5Y2xlQmluRm9sZGVyIiwKfTsKY29uc3QgRklMRV9LSU5EUyA9IHsKICBmb3RvOiAiLmpwZ3wuanBlZ3wucG5nfC53ZWJwIiwgZ2FtYmFyOiAiLmpwZ3wuanBlZ3wu
::B64:agent.js:cG5nfC53ZWJwIiwgdmlkZW86ICIubXA0fC5ta3Z8LmF2aXwubW92IiwgdmlkaW86ICIubXA0fC5ta3Z8LmF2aXwubW92IiwKICBtdXNpazogIi5tcDN8LndhdnwuZmxhY3wubTRhIiwgbGFndTogIi5tcDN8LndhdnwuZmxhY3wubTRhIiwgZG9rdW1lbjogIi5wZGZ8
::B64:agent.js:LmRvY3wuZG9jeHwudHh0fC54bHN4fC5wcHR4IiwKfTsKY29uc3QgRE9NQUlOX1JFID0gL14oPzpodHRwcz86XC9cLyk/W2EtejAtOS1dKyg/OlwuW2EtejAtOS1dKykqXC4oPzpjb218aWR8bmV0fG9yZ3xpb3xjb3xtZXxhcHB8ZGV2fHR2fGFpfHh5enxpbmZvfGNv
::B64:agent.js:XC5pZHxnb1wuaWR8YWNcLmlkKSg/OlwvXFMqKT8kL2k7Cgpjb25zdCBzaXRlVXJsID0gKHQpID0+IHsKICBjb25zdCBrID0gU3RyaW5nKHQpLnRyaW0oKS50b0xvd2VyQ2FzZSgpOwogIGlmIChLTk9XTl9TSVRFU1trXSkgcmV0dXJuICJodHRwczovLyIgKyBLTk9X
::B64:agent.js:Tl9TSVRFU1trXTsKICBpZiAoRE9NQUlOX1JFLnRlc3QoU3RyaW5nKHQpLnRyaW0oKSkpIHJldHVybiBmaXhVcmwoU3RyaW5nKHQpLnRyaW0oKSk7CiAgcmV0dXJuICIiOwp9Owpjb25zdCB1cGxvYWRVcmwgPSAodCkgPT4gewogIGNvbnN0IGsgPSBTdHJpbmcodCku
::B64:agent.js:dHJpbSgpLnRvTG93ZXJDYXNlKCkucmVwbGFjZSgvXC4oY29tfGlvfG9yZ3xuZXR8bWV8bW9lfGFwcCkkLywgIiIpOwogIGlmIChVUExPQURfU0lURVNba10pIHJldHVybiBVUExPQURfU0lURVNba107CiAgaWYgKERPTUFJTl9SRS50ZXN0KFN0cmluZyh0KS50cmlt
::B64:agent.js:KCkpKSByZXR1cm4gZml4VXJsKFN0cmluZyh0KS50cmltKCkpOwogIHJldHVybiAiIjsKfTsKY29uc3Qgb25Zb3VUdWJlID0gKCkgPT4gL3lvdXR1YmVcLmNvbVwvd2F0Y2gvaS50ZXN0KHBhZ2UudXJsKCkpOwpjb25zdCBvbllvdVR1YmVTaXRlID0gKCkgPT4gL3lv
::B64:agent.js:dXR1YmVcLmNvbS9pLnRlc3QocGFnZS51cmwoKSk7CmNvbnN0IGlzQmxhbmtQYWdlID0gKCkgPT4gewogIGNvbnN0IHUgPSBwYWdlLnVybCgpOwogIHJldHVybiAhdSB8fCAvXihhYm91dDpibGFua3xjaHJvbWU6XC9cL25ldy0/dGFifGVkZ2U6XC9cL25ld3RhYikv
::B64:agent.js:aS50ZXN0KHUpOwp9Owpjb25zdCBrbm93bkRpciA9IChuYW1lKSA9PiB7CiAgY29uc3QgayA9IFN0cmluZyhuYW1lKS50cmltKCkudG9Mb3dlckNhc2UoKTsKICBpZiAoL14oZG93bmxvYWRzP3x1bmR1aGFuKSQvLnRlc3QoaykpIHJldHVybiBwYXRoLmpvaW4oSE9N
::B64:agent.js:RSwgIkRvd25sb2FkcyIpOwogIGlmIChrID09PSAiZGVza3RvcCIpIHJldHVybiBwYXRoLmpvaW4oSE9NRSwgIkRlc2t0b3AiKTsKICBpZiAoL14oZG9jdW1lbnRzP3xkb2t1bWVuKSQvLnRlc3QoaykpIHJldHVybiBwYXRoLmpvaW4oSE9NRSwgIkRvY3VtZW50cyIp
::B64:agent.js:OwogIGlmICgvXihwaWN0dXJlcz98Z2FtYmFyfGZvdG8pJC8udGVzdChrKSkgcmV0dXJuIHBhdGguam9pbihIT01FLCAiUGljdHVyZXMiKTsKICByZXR1cm4gIiI7Cn07CgovLyBQaWxpaCBoYXNpbCBwZW5jYXJpYW4gdGVyYmFpazogbmFtYSBwYWxpbmcgbWlyaXAs
::B64:agent.js:IGxhbHUgbG9rYXNpIHVtdW0sIGxhbHUgcGF0aCB0ZXJwZW5kZWsKZnVuY3Rpb24gYmVzdFBhdGgobGluZXMsIHF1ZXJ5KSB7CiAgY29uc3QgcmF3ID0gU3RyaW5nKHF1ZXJ5KS50b0xvd2VyQ2FzZSgpOwogIGNvbnN0IHEgPSByYXcucmVwbGFjZSgvXC5bYS16MC05
::B64:agent.js:XXsyLDR9JC8sICIiKTsKICBjb25zdCBzY29yZSA9IChwKSA9PiB7CiAgICBjb25zdCBiYXNlID0gcGF0aC5iYXNlbmFtZShwKS50b0xvd2VyQ2FzZSgpOwogICAgY29uc3Qgc3RlbSA9IGJhc2UucmVwbGFjZSgvXC5bYS16MC05XXsyLDR9JC8sICIiKTsKICAgIGxl
::B64:agent.js:dCBzID0gMDsKICAgIGlmIChiYXNlID09PSByYXcgfHwgc3RlbSA9PT0gcSkgcyArPSAxMDsKICAgIGVsc2UgaWYgKHN0ZW0uc3RhcnRzV2l0aChxKSkgcyArPSA0OwogICAgaWYgKC9bXFwvXShkb3dubG9hZHN8ZGVza3RvcHxkb2N1bWVudHN8dW5kdWhhbilbXFwv
::B64:agent.js:XS9pLnRlc3QocCkpIHMgKz0gMzsKICAgIHJldHVybiBzIC0gcC5sZW5ndGggLyAyMDA7CiAgfTsKICByZXR1cm4gWy4uLmxpbmVzXS5zb3J0KChhLCBiKSA9PiBzY29yZShiKSAtIHNjb3JlKGEpKVswXTsKfQpjb25zdCByZXN1bHRMaW5lcyA9IChvdXQpID0+IFN0
::B64:agent.js:cmluZyhvdXQpLnNwbGl0KCJcbiIpLmZpbHRlcigobCkgPT4gbCAmJiBsICE9PSAiVGlkYWsgZGl0ZW11a2FuIik7CgovLyBVYmFoIHVjYXBhbiBzZXBlcnRpICJsYXBvcmFuLnBkZiIsICJmb2xkZXIgUmVpYSIsICJ5YW5nIHRlcmJhcnUgZGkgZG93bmxvYWRzIiBt
::B64:agent.js:ZW5qYWRpIHBhdGggbnlhdGEKYXN5bmMgZnVuY3Rpb24gcmVzb2x2ZVVwbG9hZFNvdXJjZSh3aGF0KSB7CiAgY29uc3QgdyA9IHRpZHkod2hhdCkucmVwbGFjZSgvXlsiJ118WyInXSQvZywgIiIpOwogIGxldCBtbTsKICBpZiAoKG1tID0gdy5tYXRjaCgvXnNlbXVh
::B64:agent.js:XHMrKD86ZmlsZVxzKyk/KC4rPylccysoPzpkaXxkYXJpKVxzKyg/OmZvbGRlclxzKyk/KC4rKSQvaSkpKSB7CiAgICBjb25zdCBraW5kID0gbW1bMV0udHJpbSgpLnRvTG93ZXJDYXNlKCk7CiAgICBjb25zdCBwYXR0ZXJuID0gRklMRV9LSU5EU1traW5kXSB8fCAo
::B64:agent.js:L15bYS16MC05XXsyLDV9JC8udGVzdChraW5kKSA/ICIuIiArIGtpbmQgOiBraW5kKTsKICAgIGxldCBmb2xkZXIgPSBrbm93bkRpcihtbVsyXSk7CiAgICBpZiAoIWZvbGRlcikgewogICAgICBjb25zdCBsaW5lcyA9IHJlc3VsdExpbmVzKHNlYXJjaEV2ZXJ5d2hl
::B64:agent.js:cmUobW1bMl0udHJpbSgpLCBmYWxzZSkpOwogICAgICBpZiAoIWxpbmVzLmxlbmd0aCkgdGhyb3cgbmV3IEVycm9yKGBGb2xkZXIgIiR7bW1bMl19IiB0aWRhayBkaXRlbXVrYW5gKTsKICAgICAgZm9sZGVyID0gYmVzdFBhdGgobGluZXMsIG1tWzJdKTsKICAgIH0K
::B64:agent.js:ICAgIHJldHVybiB7IGZvbGRlciwgcGF0dGVybiwgbGFiZWw6IGBzZW11YSAke2tpbmR9IGRpICR7Zm9sZGVyfWAgfTsKICB9CiAgaWYgKChtbSA9IHcubWF0Y2goL14oPzpmaWxlXHMrKT8oPzp5YW5nXHMrKT8oPzpwYWxpbmdccyspPyg/OnRlcmJhcnV8dGVyYWto
::B64:agent.js:aXJ8YmFydSkoPzpccysoPzpkaXxkYXJpKVxzKyg/OmZvbGRlclxzKyk/KC4rKSk/JC9pKSkpIHsKICAgIGNvbnN0IGRpciA9IG1tWzFdID8ga25vd25EaXIobW1bMV0pIHx8IHBhdGgucmVzb2x2ZShtbVsxXSkgOiBwYXRoLmpvaW4oSE9NRSwgIkRvd25sb2FkcyIp
::B64:agent.js:OwogICAgY29uc3QgbmV3ZXN0ID0gcmVjZW50TGlzdChkaXIsIDEpWzBdOwogICAgaWYgKCFuZXdlc3QpIHRocm93IG5ldyBFcnJvcigiVGlkYWsgYWRhIGZpbGUgZGkgIiArIGRpcik7CiAgICByZXR1cm4geyBmaWxlbmFtZTogbmV3ZXN0LmYsIGxhYmVsOiBgZmls
::B64:agent.js:ZSB0ZXJiYXJ1IGRpICR7ZGlyfWAgfTsKICB9CiAgaWYgKChtbSA9IHcubWF0Y2goL15mb2xkZXJccysoLispJC9pKSkpIHsKICAgIGxldCBmb2xkZXIgPSBrbm93bkRpcihtbVsxXSk7CiAgICBpZiAoIWZvbGRlcikgewogICAgICBjb25zdCBsaW5lcyA9IHJlc3Vs
::B64:agent.js:dExpbmVzKHNlYXJjaEV2ZXJ5d2hlcmUobW1bMV0udHJpbSgpLCBmYWxzZSkpOwogICAgICBpZiAoIWxpbmVzLmxlbmd0aCkgdGhyb3cgbmV3IEVycm9yKGBGb2xkZXIgIiR7bW1bMV19IiB0aWRhayBkaXRlbXVrYW5gKTsKICAgICAgZm9sZGVyID0gYmVzdFBhdGgo
::B64:agent.js:bGluZXMsIG1tWzFdKTsKICAgIH0KICAgIHJldHVybiB7IGZpbGVuYW1lOiBmb2xkZXIsIGxhYmVsOiBgZm9sZGVyICR7Zm9sZGVyfSAoZGlraXJpbSBzZWJhZ2FpIHppcClgIH07CiAgfQogIGNvbnN0IGRpcmVjdCA9IHBhdGgucmVzb2x2ZShTQUZFX0RJUiwgdyk7
::B64:agent.js:CiAgaWYgKGZzLmV4aXN0c1N5bmMoZGlyZWN0KSkgcmV0dXJuIHsgZmlsZW5hbWU6IGRpcmVjdCwgbGFiZWw6IGRpcmVjdCB9OwogIGNvbnN0IGxpbmVzID0gcmVzdWx0TGluZXMoc2VhcmNoRXZlcnl3aGVyZSh3LCB0cnVlKSk7CiAgaWYgKCFsaW5lcy5sZW5ndGgp
::B64:agent.js:IHRocm93IG5ldyBFcnJvcihgRmlsZSAiJHt3fSIgdGlkYWsgZGl0ZW11a2FuYCk7CiAgcmV0dXJuIHsgZmlsZW5hbWU6IGJlc3RQYXRoKGxpbmVzLCB3KSwgbGFiZWw6IHcgfTsKfQoKYXN5bmMgZnVuY3Rpb24gdHJ5RmFzdENvbW1hbmQocmF3KSB7CiAgY29uc3Qg
::B64:agent.js:YyA9IFN0cmluZyhyYXcpLnRyaW0oKS5yZXBsYWNlKC9ccysvZywgIiAiKTsKICBsZXQgbTsKICBjb25zdCB5dCA9IG9uWW91VHViZSgpOwoKICAvLyAtLS0tIFZvbHVtZSAtLS0tCiAgaWYgKChtID0gYy5tYXRjaCgvXig/Oig/OmF0dXJ8c2V0fHViYWgpXHMrKT8o
::B64:agent.js:Pzp2b2x1bWV8c3VhcmEpKD86bnlhKT9ccyooPzpqYWRpfGtlfG1lbmphZGl8PXxkaSk/XHMqKFxkezEsM30pXHMqJT8kL2kpKSB8fAogICAgICAobSA9IGMubWF0Y2goL14oPzpuYWlraW58bmFpa2thbnx0dXJ1bmlufHR1cnVua2FufGtlY2lsaW58a2VjaWxrYW58
::B64:agent.js:YmVzYXJpbnxiZXNhcmthbilccysoPzp2b2x1bWV8c3VhcmEpKD86bnlhKT9ccysoPzpqYWRpfGtlfG1lbmphZGkpXHMqKFxkezEsM30pXHMqJT8kL2kpKSkgewogICAgcmV0dXJuIGF3YWl0IGltcGwuc2V0X3ZvbHVtZSh7IGxldmVsOiBtWzFdIH0pOwogIH0KICBp
::B64:agent.js:ZiAoKG0gPSBjLm1hdGNoKC9eKD86bmFpa2lufG5haWtrYW58YmVzYXJpbnxiZXNhcmthbnxrZXJhc2thbnx0YW1iYWgoPzppbnxrYW4pPylccysoPzp2b2x1bWV8c3VhcmEpKD86bnlhKT8oPzpccysoXGR7MSwzfSlccyolPyk/JC9pKSkpIHsKICAgIGF3YWl0IGlt
::B64:agent.js:cGwubWVkaWFfa2V5KHsga2V5OiAidm9sdXAiLCB0aW1lczogbVsxXSA/IE1hdGgubWF4KDEsIE1hdGgucm91bmQoTnVtYmVyKG1bMV0pIC8gMikpIDogNSB9KTsKICAgIHJldHVybiBgVm9sdW1lIGRpbmFpa2thbiAke21bMV0gPyBtWzFdICsgIiUiIDogInNla2l0
::B64:agent.js:YXIgMTAlIn0uYDsKICB9CiAgaWYgKChtID0gYy5tYXRjaCgvXig/OnR1cnVuaW58dHVydW5rYW58a2VjaWxpbnxrZWNpbGthbnxwZWxhbmlufHBlbGFua2FufGt1cmFuZ2l8a3VyYW5naW4pXHMrKD86dm9sdW1lfHN1YXJhKSg/Om55YSk/KD86XHMrKFxkezEsM30p
::B64:agent.js:XHMqJT8pPyQvaSkpKSB7CiAgICBhd2FpdCBpbXBsLm1lZGlhX2tleSh7IGtleTogInZvbGRvd24iLCB0aW1lczogbVsxXSA/IE1hdGgubWF4KDEsIE1hdGgucm91bmQoTnVtYmVyKG1bMV0pIC8gMikpIDogNSB9KTsKICAgIHJldHVybiBgVm9sdW1lIGRpdHVydW5r
::B64:agent.js:YW4gJHttWzFdID8gbVsxXSArICIlIiA6ICJzZWtpdGFyIDEwJSJ9LmA7CiAgfQogIGlmICgvXig/Om11dGV8dW5tdXRlfGJpc3VrYW58c2VueWFwa2FufG1hdGlrYW4gc3VhcmF8bnlhbGFrYW4gc3VhcmF8YnVueWlrYW4pKD86XHMrKD86c3VhcmF8dm9sdW1lKSk/
::B64:agent.js:JC9pLnRlc3QoYykpIHsKICAgIGF3YWl0IGltcGwubWVkaWFfa2V5KHsga2V5OiAibXV0ZSIgfSk7CiAgICByZXR1cm4gIk11dGUgZGl1YmFoICh0b2dnbGUpLiI7CiAgfQoKICAvLyAtLS0tIEtvbnRyb2wgcGVtdXRhciAtLS0tCiAgaWYgKC9eKD86cGF1c2V8amVk
::B64:agent.js:YSkoPzpccysoPzpkdWx1fHZpZGVvbnlhfG11c2lrbnlhfGxhZ3VueWF8bGFndXx2aWRlb3xtdXNpa3x5b3V0dWJlKSkqJC9pLnRlc3QoYykgfHwKICAgICAgKHl0ICYmIC9eKD86c3RvcHxzZXRvcHxiZXJoZW50aXxoZW50aWthbikoPzpccysoPzpkdWx1fHZpZGVv
::B64:agent.js:bnlhfG11c2lrbnlhfGxhZ3VueWEpKSokL2kudGVzdChjKSkpIHsKICAgIGlmICh5dCkgYXdhaXQgaW1wbC55b3V0dWJlX2NvbnRyb2woeyBhY3Rpb246ICJwYXVzZSIgfSk7CiAgICBlbHNlIGF3YWl0IGltcGwubWVkaWFfa2V5KHsga2V5OiAicGxheXBhdXNlIiB9
::B64:agent.js:KTsKICAgIHJldHVybiAiRGlqZWRhLiI7CiAgfQogIGlmICgvXig/OnBsYXl8cmVzdW1lfHB1dGFyIGxhZ2l8bXVsYWkgbGFnaSkoPzpccysoPzpkdWx1fHZpZGVvbnlhfG11c2lrbnlhfGxhZ3VueWF8bGFndXx2aWRlb3xtdXNpaykpKiQvaS50ZXN0KGMpIHx8CiAg
::B64:agent.js:ICAgICh5dCAmJiAvXig/Omxhbmp1dHxsYW5qdXRrYW58dGVydXNpbikkL2kudGVzdChjKSkpIHsKICAgIGlmICh5dCkgYXdhaXQgaW1wbC55b3V0dWJlX2NvbnRyb2woeyBhY3Rpb246ICJwbGF5IiB9KTsKICAgIGVsc2UgYXdhaXQgaW1wbC5tZWRpYV9rZXkoeyBr
::B64:agent.js:ZXk6ICJwbGF5cGF1c2UiIH0pOwogICAgcmV0dXJuICJEaWxhbmp1dGthbi4iOwogIH0KICBpZiAoL14oPzpuZXh0fHNraXB8c2VsYW5qdXRueWF8YmVyaWt1dG55YXxsYWd1IGJlcmlrdXRueWF8bGFndSBzZWxhbmp1dG55YXxnYW50aSBsYWd1KSQvaS50ZXN0KGMp
::B64:agent.js:KSB7CiAgICBpZiAoeXQpIGF3YWl0IGltcGwueW91dHViZV9jb250cm9sKHsgYWN0aW9uOiAibmV4dCIgfSk7CiAgICBlbHNlIGF3YWl0IGltcGwubWVkaWFfa2V5KHsga2V5OiAibmV4dCIgfSk7CiAgICByZXR1cm4gIkxhZ3UvdmlkZW8gYmVyaWt1dG55YS4iOwog
::B64:agent.js:IH0KICBpZiAoL14oPzpwcmV2aW91c3xwcmV2fHNlYmVsdW1ueWF8bGFndSBzZWJlbHVtbnlhKSQvaS50ZXN0KGMpKSB7CiAgICBpZiAoeXQpIGF3YWl0IGltcGwueW91dHViZV9jb250cm9sKHsgYWN0aW9uOiAicHJldmlvdXMiIH0pOwogICAgZWxzZSBhd2FpdCBp
::B64:agent.js:bXBsLm1lZGlhX2tleSh7IGtleTogInByZXYiIH0pOwogICAgcmV0dXJuICJMYWd1L3ZpZGVvIHNlYmVsdW1ueWEuIjsKICB9CiAgaWYgKHl0ICYmIChtID0gYy5tYXRjaCgvXig/Om1hanV8bWFqdWlufGZvcndhcmQpXHMqKFxkKyk/XHMqKD86ZGV0aWspPyQvaSkp
::B64:agent.js:KSB7CiAgICBhd2FpdCBpbXBsLnlvdXR1YmVfY29udHJvbCh7IGFjdGlvbjogImZvcndhcmQiLCBzZWNvbmRzOiBtWzFdIHx8IDEwIH0pOwogICAgcmV0dXJuIGBNYWp1ICR7bVsxXSB8fCAxMH0gZGV0aWsuYDsKICB9CiAgaWYgKHl0ICYmIChtID0gYy5tYXRjaCgv
::B64:agent.js:Xig/Om11bmR1cnxtdW5kdXJpbnxyZXdpbmQpXHMqKFxkKyk/XHMqKD86ZGV0aWspPyQvaSkpKSB7CiAgICBhd2FpdCBpbXBsLnlvdXR1YmVfY29udHJvbCh7IGFjdGlvbjogImJhY2t3YXJkIiwgc2Vjb25kczogbVsxXSB8fCAxMCB9KTsKICAgIHJldHVybiBgTXVu
::B64:agent.js:ZHVyICR7bVsxXSB8fCAxMH0gZGV0aWsuYDsKICB9CiAgaWYgKHl0ICYmIC9eKD86ZnVsbHNjcmVlbnxsYXlhciBwZW51aCkkL2kudGVzdChjKSkgewogICAgYXdhaXQgaW1wbC55b3V0dWJlX2NvbnRyb2woeyBhY3Rpb246ICJmdWxsc2NyZWVuIiB9KTsKICAgIHJl
::B64:agent.js:dHVybiAiRnVsbHNjcmVlbiBkaXViYWguIjsKICB9CgogIC8vIC0tLS0gWW91VHViZTogcHV0YXIgbGFndS92aWRlbyAtLS0tCiAgaWYgKC9eKD86bm9udG9ufHRvbnRvbnxidWthfHB1dGFyKVxzK3lvdXR1YmUkL2kudGVzdChjKSkgewogICAgYXdhaXQgaW1wbC5v
::B64:agent.js:cGVuX3VybCh7IHVybDogImh0dHBzOi8vd3d3LnlvdXR1YmUuY29tIiwgbmV3X3RhYjogIWlzQmxhbmtQYWdlKCkgfSk7CiAgICByZXR1cm4gIllvdVR1YmUgZGlidWthLiI7CiAgfQogIGlmICgobSA9IGMubWF0Y2goL14oPzpwdXRhcig/Omthbnxpbik/fHNldGVs
::B64:agent.js:KD86aW4pP3xwbGF5fGRlbmdlcmlufGRlbmdhcmthbnxub250b24oPzppbik/fHRvbnRvbnxjYXJpKD86aW58a2FuKT8pXHMrKD86bGFndXxtdXNpa3xtdXNpY3x2aWRlb3x2aWRpb3xmaWxtKVxzKyguKykkL2kpKSB8fAogICAgICAobSA9IGMubWF0Y2goL14oPzpw
::B64:agent.js:dXRhcig/Omthbnxpbik/fHNldGVsKD86aW4pP3xwbGF5fGRlbmdlcmlufGRlbmdhcmthbnxub250b24oPzppbik/fHRvbnRvbilccysoLispJC9pKSkpIHsKICAgIGNvbnN0IHEgPSB0aWR5KG1bMV0pLnJlcGxhY2UoL1xzKyg/OmRpfGRhcml8bGV3YXQpXHMreW91
::B64:agent.js:dHViZSQvaSwgIiIpOwogICAgaWYgKCFxIHx8IC9eKD86ZmlsZXxmb2xkZXJ8ZG9rdW1lbilcYi9pLnRlc3QocSkgfHwgL1thLXpdOlxcfFwuKD86bXAzfG1wNHxta3Z8YXZpfHdhdnxwZGZ8emlwfHR4dClcYi9pLnRlc3QocSkpIHJldHVybiBudWxsOwogICAgY29u
::B64:agent.js:c3Qgb3V0ID0gYXdhaXQgaW1wbC55b3V0dWJlX3BsYXkoeyBxdWVyeTogcSwgbmV3X3RhYjogIW9uWW91VHViZVNpdGUoKSAmJiAhaXNCbGFua1BhZ2UoKSB9KTsKICAgIHJldHVybiBTdHJpbmcob3V0KS5zcGxpdCgiXG4iKVswXTsKICB9CgogIC8vIC0tLS0gVXBs
::B64:agent.js:b2FkIGNlcGF0IC0tLS0KICBpZiAoKG0gPSBjLm1hdGNoKC9eKD86dXBsb2FkfHVuZ2dhaHx1cGxvdWR8a2lyaW0pXHMrKD86ZmlsZVxzKyk/KC4rPylccytrZVxzKyhcUyspJC9pKSkpIHsKICAgIGNvbnN0IHRhcmdldCA9IHVwbG9hZFVybChtWzJdKTsKICAgIGlm
::B64:agent.js:ICghdGFyZ2V0KSByZXR1cm4gbnVsbDsgLy8gdHVqdWFuIHRpZGFrIGRpa2VuYWwgLT4gc2VyYWhrYW4ga2UgQUkKICAgIGNvbnN0IHNyYyA9IGF3YWl0IHJlc29sdmVVcGxvYWRTb3VyY2UobVsxXSk7CiAgICByZXR1cm4gYXdhaXQgaW1wbC5mYXN0X3VwbG9hZCh7
::B64:agent.js:IHVybDogdGFyZ2V0LCBmaWxlbmFtZTogc3JjLmZpbGVuYW1lLCBmb2xkZXI6IHNyYy5mb2xkZXIsIHBhdHRlcm46IHNyYy5wYXR0ZXJuIH0pOwogIH0KCiAgLy8gLS0tLSBCdWthIGZvbGRlciAvIHNpdHVzIC8gYXBsaWthc2kgLS0tLQogIGlmICgobSA9IGMubWF0
::B64:agent.js:Y2goL15idWthKD86aW58a2FuKT9ccytmb2xkZXJccysoLispJC9pKSkpIHsKICAgIGNvbnN0IG5hbWUgPSB0aWR5KG1bMV0pOwogICAgbGV0IGRpciA9IGtub3duRGlyKG5hbWUpOwogICAgbGV0IGV4dHJhID0gIiI7CiAgICBpZiAoIWRpcikgewogICAgICBjb25z
::B64:agent.js:dCBsaW5lcyA9IHJlc3VsdExpbmVzKHNlYXJjaEV2ZXJ5d2hlcmUobmFtZSwgZmFsc2UpKTsKICAgICAgaWYgKCFsaW5lcy5sZW5ndGgpIHJldHVybiBgRm9sZGVyICIke25hbWV9IiB0aWRhayBkaXRlbXVrYW4uYDsKICAgICAgZGlyID0gYmVzdFBhdGgobGluZXMs
::B64:agent.js:IG5hbWUpOwogICAgICBpZiAobGluZXMubGVuZ3RoID4gMSkgZXh0cmEgPSBgXG4oJHtsaW5lcy5sZW5ndGggLSAxfSBmb2xkZXIgbGFpbiBjb2NvazogJHtsaW5lcy5maWx0ZXIoKGwpID0+IGwgIT09IGRpcikuc2xpY2UoMCwgMykuam9pbigiIHwgIil9KWA7CiAg
::B64:agent.js:ICB9CiAgICBjb25zdCByID0gYXdhaXQgaW1wbC5vcGVuX3BhdGgoeyB0YXJnZXQ6IGRpciB9KTsKICAgIHJldHVybiBTdHJpbmcocikuc3RhcnRzV2l0aCgiRGliYXRhbGthbiIpID8gciA6IGBGb2xkZXIgZGlidWthOiAke2Rpcn0ke2V4dHJhfWA7CiAgfQogIGlm
::B64:agent.js:ICgobSA9IGMubWF0Y2goL14oPzpidWthKD86aW58a2FuKT98b3BlbilccysoLis/KSg/OlxzK3Nla2FsaWd1cyk/JC9pKSkpIHsKICAgIGNvbnN0IHRva2VucyA9IG1bMV0KICAgICAgLnNwbGl0KC9ccyooPzosfFxiZGFuXGJ8JnxcKylccyovaSkKICAgICAgLm1h
::B64:agent.js:cCgoeCkgPT4geC5yZXBsYWNlKC9ccysoPzpkaVxzKyk/dGFiXHMrYmFydSQvaSwgIiIpLnRyaW0oKSkKICAgICAgLmZpbHRlcihCb29sZWFuKTsKICAgIGNvbnN0IHVybHMgPSB0b2tlbnMubWFwKHNpdGVVcmwpOwogICAgaWYgKHRva2Vucy5sZW5ndGggJiYgdXJs
::B64:agent.js:cy5ldmVyeShCb29sZWFuKSkgewogICAgICBpZiAodXJscy5sZW5ndGggPT09IDEpIHsKICAgICAgICBhd2FpdCBpbXBsLm9wZW5fdXJsKHsgdXJsOiB1cmxzWzBdLCBuZXdfdGFiOiAhaXNCbGFua1BhZ2UoKSB9KTsKICAgICAgICByZXR1cm4gYERpYnVrYTogJHt1
::B64:agent.js:cmxzWzBdfWA7CiAgICAgIH0KICAgICAgYXdhaXQgaW1wbC5vcGVuX3VybHMoeyB1cmxzIH0pOwogICAgICByZXR1cm4gYCR7dXJscy5sZW5ndGh9IHRhYiBkaWJ1a2E6ICR7dXJscy5qb2luKCIsICIpfWA7CiAgICB9CiAgICBpZiAodG9rZW5zLmxlbmd0aCA9PT0g
::B64:agent.js:MSAmJiBBUFBTW3Rva2Vuc1swXS50b0xvd2VyQ2FzZSgpXSkgewogICAgICBjb25zdCByID0gYXdhaXQgaW1wbC5vcGVuX3BhdGgoeyB0YXJnZXQ6IEFQUFNbdG9rZW5zWzBdLnRvTG93ZXJDYXNlKCldIH0pOwogICAgICByZXR1cm4gU3RyaW5nKHIpLnN0YXJ0c1dp
::B64:agent.js:dGgoIkRpYmF0YWxrYW4iKSA/IHIgOiBgJHt0b2tlbnNbMF19IGRpYnVrYS5gOwogICAgfQogIH0KCiAgLy8gLS0tLSBDYXJpIGZpbGUgLyBmb2xkZXIgLyB3ZWIgLS0tLQogIGlmICgobSA9IGMubWF0Y2goL15jYXJpKD86aW58a2FuKT9ccysoZmlsZXxmb2xkZXIp
::B64:agent.js:XHMrKC4rKSQvaSkpKSB7CiAgICBjb25zdCBvdXQgPSBzZWFyY2hFdmVyeXdoZXJlKHRpZHkobVsyXSksIG1bMV0udG9Mb3dlckNhc2UoKSA9PT0gImZpbGUiKTsKICAgIHJldHVybiBvdXQgPT09ICJUaWRhayBkaXRlbXVrYW4iID8gYCR7bVsxXX0gIiR7dGlkeSht
::B64:agent.js:WzJdKX0iIHRpZGFrIGRpdGVtdWthbi5gIDogb3V0OwogIH0KICBpZiAoKG0gPSBjLm1hdGNoKC9eKD86Y2FyaSg/OmlufGthbik/fGdvb2dsaW5nKVxzKyg/OnRhdVxzKyk/KC4rPylccysoPzpkaVxzKyk/KD86d2VifGdvb2dsZXxpbnRlcm5ldHxicm93c2VyKSQv
::B64:agent.js:aSkpKSB7CiAgICByZXR1cm4gYXdhaXQgaW1wbC53ZWJfc2VhcmNoKHsgcXVlcnk6IHRpZHkobVsxXSksIG5ld190YWI6ICFpc0JsYW5rUGFnZSgpIH0pOwogIH0KICBpZiAoL14oPzpsaWhhdHx0YW1waWxrYW58Y2VrKT9ccyooPzpmaWxlfHVuZHVoYW58ZG93bmxv
::B64:agent.js:YWQoPzphbik/KVxzKyg/OnlhbmdccyspP3RlcmJhcnUoPzpccysoPzpkaVxzKyk/XFMrKT8kL2kudGVzdChjKSkgewogICAgcmV0dXJuIGF3YWl0IGltcGwucmVjZW50X2ZpbGVzKHt9KTsKICB9CgogIC8vIC0tLS0gVGFiIC0tLS0KICBpZiAoL14oPzp0dXR1cClc
::B64:agent.js:cyt0YWIoPzpccytpbmkpPyQvaS50ZXN0KGMpKSByZXR1cm4gKGF3YWl0IGltcGwuY2xvc2VfdGFiKHt9KSkuc3BsaXQoIlxuIilbMF07CiAgaWYgKChtID0gYy5tYXRjaCgvXig/OnBpbmRhaHxrZXxidWthKVxzK3RhYlxzKyh0ZXJiYXJ1fGJhcnV8dGVyYWtoaXJ8
::B64:agent.js:XGQrKSQvaSkpKSB7CiAgICBjb25zdCBpZHggPSAvXlxkKyQvLnRlc3QobVsxXSkgPyBOdW1iZXIobVsxXSkgOiAtMTsKICAgIHJldHVybiBhd2FpdCBpbXBsLnN3aXRjaF90YWIoeyBpbmRleDogaWR4IH0pOwogIH0KICBpZiAoL14oPzpkYWZ0YXJ8bGlzdHxsaWhh
::B64:agent.js:dClccyt0YWIkL2kudGVzdChjKSkgcmV0dXJuIGF3YWl0IGltcGwubGlzdF90YWJzKCk7CgogIC8vIC0tLS0gUEMgLS0tLQogIGlmICgvXig/OmluZm98Y2VrfHN0YXR1c3xsaWhhdClccyooPzpwY3xrb21wdXRlcnxsYXB0b3B8c2lzdGVtfHNwZWt8cmFtfGNwdXxi
::B64:agent.js:YXRlcmFpfGRpc2t8c3RvcmFnZXxtZW1vcmkpXGIvaS50ZXN0KGMpKSByZXR1cm4gYXdhaXQgaW1wbC5zeXN0ZW1faW5mbygpOwogIGlmICgvXig/OmphbSBiZXJhcGF8dGFuZ2dhbCBiZXJhcGF8aGFyaSBhcGF8c2VrYXJhbmcgamFtIGJlcmFwYXxzZWthcmFuZyB0
::B64:agent.js:YW5nZ2FsIGJlcmFwYXxqYW0gYmVyYXBhIHNla2FyYW5nKVw/PyQvaS50ZXN0KGMpKSByZXR1cm4gYXdhaXQgaW1wbC5ub3coKTsKICBpZiAoL14oPzpzY3JlZW5zaG90fHRhbmdrYXAgbGF5YXJ8c3N8Y2FwdHVyZSkoPzpccytsYXlhcik/JC9pLnRlc3QoYykpIHJl
::B64:agent.js:dHVybiBhd2FpdCBpbXBsLnNhdmVfc2NyZWVuc2hvdCh7fSk7CiAgaWYgKChtID0gYy5tYXRjaCgvXig/OmluZ2F0a2FufGluZ2V0aW58aW5nYXRpbnx0aW1lcnxhbGFybXxzZXQgdGltZXIpXHMrKD86YWt1XHMrfHNheWFccyt8Z3VlXHMrKT8oPzpkYWxhbVxzKyk/
::B64:agent.js:KFxkKyg/OlsuLF1cZCspPylccyoobWVuaXR8ZGV0aWt8amFtKVxzKig/OmxhZ2kpP1xzKig/OnVudHVrfGJ1YXR8Oik/XHMqKC4qKSQvaSkpKSB7CiAgICByZXR1cm4gYXdhaXQgaW1wbC5zZXRfdGltZXIoeyBhbW91bnQ6IG1bMV0sIHVuaXQ6IG1bMl0sIG1lc3Nh
::B64:agent.js:Z2U6IHRpZHkobVszXSkgfHwgIldha3R1bnlhISIgfSk7CiAgfQogIGlmICgobSA9IGMubWF0Y2goL14oPzp1Y2Fwa2FufGJpbGFuZ3xrYXRha2FufGJhY2FrYW4pXHMrKC4rKSQvaSkpKSByZXR1cm4gYXdhaXQgaW1wbC5zcGVhayh7IHRleHQ6IHRpZHkobVsxXSkg
::B64:agent.js:fSk7CgogIHJldHVybiBudWxsOyAvLyB0aWRhayBkaWtlbmFsIC0+IEFJCn0KCi8vID09PT09IE1lbW9yaSBwZXJjYWthcGFuID09PT09CmNvbnN0IGhpc3RvcnkgPSBbXTsKY29uc3QgTUFYX0hJU1RPUlkgPSAzMDsKCmZ1bmN0aW9uIHN0cmlwSW1hZ2VzKCkgewog
::B64:agent.js:IGZvciAoY29uc3QgbSBvZiBoaXN0b3J5KSB7CiAgICBpZiAobS5yb2xlID09PSAidXNlciIgJiYgQXJyYXkuaXNBcnJheShtLmNvbnRlbnQpKSB7CiAgICAgIG0uY29udGVudCA9ICJbc2NyZWVuc2hvdCBsYW1hIGRpaGFwdXMgdW50dWsgbWVuZ2hlbWF0IG1lbW9y
::B64:agent.js:aV0iOwogICAgfQogIH0KfQoKZnVuY3Rpb24gdHJpbUhpc3RvcnkoKSB7CiAgd2hpbGUgKGhpc3RvcnkubGVuZ3RoID4gTUFYX0hJU1RPUlkpIHsKICAgIGxldCBpID0gMTsKICAgIHdoaWxlIChpIDwgaGlzdG9yeS5sZW5ndGggJiYgIShoaXN0b3J5W2ldLnJvbGUg
::B64:agent.js:PT09ICJ1c2VyIiAmJiB0eXBlb2YgaGlzdG9yeVtpXS5jb250ZW50ID09PSAic3RyaW5nIikpIGkrKzsKICAgIGlmIChpID49IGhpc3RvcnkubGVuZ3RoKSBicmVhazsKICAgIGhpc3Rvcnkuc3BsaWNlKDAsIGkpOwogIH0KfQoKYXN5bmMgZnVuY3Rpb24gcnVuVGFz
::B64:agent.js:ayhjb21tYW5kKSB7CiAgY29uc3Qgc3RhcnRMZW4gPSBoaXN0b3J5Lmxlbmd0aDsKICBoaXN0b3J5LnB1c2goeyByb2xlOiAidXNlciIsIGNvbnRlbnQ6IGNvbW1hbmQgfSk7CiAgbGV0IG51ZGdlcyA9IDA7CgogIHRyeSB7CiAgICBmb3IgKGxldCBzdGVwID0gMTsg
::B64:agent.js:c3RlcCA8PSBNQVhfU1RFUFM7IHN0ZXArKykgewogICAgICBjb25zdCBtc2cgPSBhd2FpdCBjYWxsTExNKFt7IHJvbGU6ICJzeXN0ZW0iLCBjb250ZW50OiBTWVNURU0gfSwgLi4uaGlzdG9yeV0pOwogICAgICBoaXN0b3J5LnB1c2gobXNnKTsKCiAgICAgIGlmICgh
::B64:agent.js:bXNnLnRvb2xfY2FsbHM/Lmxlbmd0aCkgewogICAgICAgIC8vIE1vZGVsIGN1bWEgbWVudWxpcyB0ZWtzL3JlbmNhbmEgdGFucGEgbWVtYW5nZ2lsIHRvb2wgLT4gcGFrc2EgcGFuZ2dpbCB0b29sCiAgICAgICAgaWYgKG51ZGdlcyA8IDMpIHsKICAgICAgICAgIG51
::B64:agent.js:ZGdlcysrOwogICAgICAgICAgaGlzdG9yeS5wdXNoKHsKICAgICAgICAgICAgcm9sZTogInVzZXIiLAogICAgICAgICAgICBjb250ZW50OiAiS2FtdSBoYXJ1cyBtZW1hbmdnaWwgdG9vbC4gSmFuZ2FuIG1lbnVsaXMgdGVrcyBiaWFzYS4gTGFuZ3N1bmcgcGFuZ2dp
::B64:agent.js:bCB0b29sIHlhbmcgc2VzdWFpLCBhdGF1IHBhbmdnaWwgZG9uZSBqaWthIHR1Z2FzIHN1ZGFoIHNlbGVzYWkuIiwKICAgICAgICAgIH0pOwogICAgICAgICAgY29udGludWU7CiAgICAgICAgfQogICAgICAgIGNvbnNvbGUubG9nKCJcbkFnZW50OiIsIG1zZy5jb250
::B64:agent.js:ZW50IHx8ICIodGlkYWsgYWRhIGphd2FiYW4pIik7CiAgICAgICAgcmV0dXJuOwogICAgICB9CgogICAgICAvLyBUdWdhcyBzZWxlc2FpOiBzZW11YSB0b29sX2NhbGwgd2FqaWIgZGlqYXdhYiBhZ2FyIHJpd2F5YXQgdGV0YXAgdmFsaWQKICAgICAgY29uc3QgZG9u
::B64:agent.js:ZUNhbGwgPSBtc2cudG9vbF9jYWxscy5maW5kKChjKSA9PiBjLmZ1bmN0aW9uLm5hbWUgPT09ICJkb25lIik7CiAgICAgIGlmIChkb25lQ2FsbCkgewogICAgICAgIGxldCBtID0gIiI7CiAgICAgICAgdHJ5IHsKICAgICAgICAgIG0gPSBKU09OLnBhcnNlKGRvbmVD
::B64:agent.js:YWxsLmZ1bmN0aW9uLmFyZ3VtZW50cyB8fCAie30iKS5tZXNzYWdlIHx8ICIiOwogICAgICAgIH0gY2F0Y2gge30KICAgICAgICBmb3IgKGNvbnN0IGNhbGwgb2YgbXNnLnRvb2xfY2FsbHMpIHsKICAgICAgICAgIGhpc3RvcnkucHVzaCh7IHJvbGU6ICJ0b29sIiwg
::B64:agent.js:dG9vbF9jYWxsX2lkOiBjYWxsLmlkLCBjb250ZW50OiBjYWxsID09PSBkb25lQ2FsbCA/ICJvayIgOiAiZGlsZXdhdGkiIH0pOwogICAgICAgIH0KICAgICAgICBjb25zb2xlLmxvZygiXG5BZ2VudDoiLCBtIHx8ICJTZWxlc2FpLiIpOwogICAgICAgIHJldHVybjsK
::B64:agent.js:ICAgICAgfQoKICAgICAgY29uc3QgZXhlY0NhbGwgPSBhc3luYyAoY2FsbCkgPT4gewogICAgICAgIGNvbnN0IG5hbWUgPSBjYWxsLmZ1bmN0aW9uLm5hbWU7CiAgICAgICAgdHJ5IHsKICAgICAgICAgIGNvbnN0IGFyZ3MgPSBKU09OLnBhcnNlKGNhbGwuZnVuY3Rp
::B64:agent.js:b24uYXJndW1lbnRzIHx8ICJ7fSIpOwogICAgICAgICAgY29uc29sZS5sb2coYFske3N0ZXB9XSAke25hbWV9YCwgYXJncyk7CiAgICAgICAgICBpZiAoIWltcGxbbmFtZV0pIHRocm93IG5ldyBFcnJvcigiVG9vbCB0aWRhayBkaWtlbmFsOiAiICsgbmFtZSk7CiAg
::B64:agent.js:ICAgICAgICBhd2FpdCBlbnN1cmVQYWdlKCk7CiAgICAgICAgICByZXR1cm4gYXdhaXQgaW1wbFtuYW1lXShhcmdzKTsKICAgICAgICB9IGNhdGNoIChlKSB7CiAgICAgICAgICByZXR1cm4gIkVSUk9SOiAiICsgZS5tZXNzYWdlOwogICAgICAgIH0KICAgICAgfTsK
::B64:agent.js:ICAgICAgY29uc3QgY2FsbHMgPSBtc2cudG9vbF9jYWxsczsKICAgICAgY29uc3QgcmVzdWx0cyA9IFtdOwogICAgICBpZiAoY2FsbHMubGVuZ3RoID4gMSAmJiBjYWxscy5ldmVyeSgoYykgPT4gU0FGRV9QQVJBTExFTC5oYXMoYy5mdW5jdGlvbi5uYW1lKSkpIHsK
::B64:agent.js:ICAgICAgICByZXN1bHRzLnB1c2goLi4uKGF3YWl0IFByb21pc2UuYWxsKGNhbGxzLm1hcChleGVjQ2FsbCkpKSk7IC8vIGFsYXQgYmFjYS1zYWphIGRpamFsYW5rYW4gYmVyc2FtYWFuCiAgICAgIH0gZWxzZSB7CiAgICAgICAgZm9yIChjb25zdCBjYWxsIG9mIGNh
::B64:agent.js:bGxzKSByZXN1bHRzLnB1c2goYXdhaXQgZXhlY0NhbGwoY2FsbCkpOwogICAgICB9CiAgICAgIGNhbGxzLmZvckVhY2goKGNhbGwsIGkpID0+CiAgICAgICAgaGlzdG9yeS5wdXNoKHsgcm9sZTogInRvb2wiLCB0b29sX2NhbGxfaWQ6IGNhbGwuaWQsIGNvbnRlbnQ6
::B64:agent.js:IFN0cmluZyhyZXN1bHRzW2ldKS5zbGljZSgwLCA0MDAwKSB9KQogICAgICApOwoKICAgICAgLy8gS2lyaW0gc2NyZWVuc2hvdCAoamlrYSBhZGEpIHNlYmFnYWkgZ2FtYmFyOyBnYW1iYXIgbGFtYSBkaWJ1YW5nIGFnYXIgcmluZ2FuCiAgICAgIGlmIChwZW5kaW5n
::B64:agent.js:SW1hZ2VzLmxlbmd0aCkgewogICAgICAgIHN0cmlwSW1hZ2VzKCk7CiAgICAgICAgaGlzdG9yeS5wdXNoKHsKICAgICAgICAgIHJvbGU6ICJ1c2VyIiwKICAgICAgICAgIGNvbnRlbnQ6IFsKICAgICAgICAgICAgeyB0eXBlOiAidGV4dCIsIHRleHQ6ICJJbmkgc2Ny
::B64:agent.js:ZWVuc2hvdCBsYXlhciB0ZXJiYXJ1OiIgfSwKICAgICAgICAgICAgLi4ucGVuZGluZ0ltYWdlcy5zcGxpY2UoMCkubWFwKChiNjQpID0+ICh7CiAgICAgICAgICAgICAgdHlwZTogImltYWdlX3VybCIsCiAgICAgICAgICAgICAgaW1hZ2VfdXJsOiB7IHVybDogYGRh
::B64:agent.js:dGE6aW1hZ2UvcG5nO2Jhc2U2NCwke2I2NH1gIH0sCiAgICAgICAgICAgIH0pKSwKICAgICAgICAgIF0sCiAgICAgICAgfSk7CiAgICAgIH0KICAgIH0KICAgIGNvbnNvbGUubG9nKCJCZXJoZW50aTogbWVsZXdhdGkgYmF0YXMgbGFuZ2thaC4iKTsKICB9IGNhdGNo
::B64:agent.js:IChlKSB7CiAgICBoaXN0b3J5Lmxlbmd0aCA9IHN0YXJ0TGVuOyAvLyBidWFuZyByaXdheWF0IHR1Z2FzIHlhbmcgZ2FnYWwgc3VwYXlhIHRpZGFrIG1lcnVzYWsgcGVyY2FrYXBhbiBiZXJpa3V0bnlhCiAgICB0aHJvdyBlOwogIH0gZmluYWxseSB7CiAgICBzdHJp
::B64:agent.js:cEltYWdlcygpOwogICAgdHJpbUhpc3RvcnkoKTsKICB9Cn0KCmNvbnN0IEJVSUxUSU5fQ0hBTkdFTE9HID0gYFZlcnNpIDcKLSBKQUxVUiBDRVBBVDogcGVyaW50YWggdW11bSAocHV0YXIgbGFndSwgdm9sdW1lLCBidWthIHNpdHVzL2ZvbGRlciwgdXBsb2FkLCBw
::B64:agent.js:YXVzZS9uZXh0LCB0aW1lciwgZGxsKSBsYW5nc3VuZyBkaWphbGFua2FuIFRBTlBBIG1lbnVuZ2d1IEFJLiBIYXNpbCBkYWxhbSBoaXR1bmdhbiBkZXRpay4KLSBVUExPQUQgQ0VQQVQ6IHNhdHUgbGFuZ2thaCwgb3RvbWF0aXMgbWVuZW11a2FuIHRvbWJvbCB1cGxv
::B64:agent.js:YWQsIGJhbnlhayBmaWxlIGF0YXUgc2F0dSBmb2xkZXIgKGRpLXppcCksIG1lbnVuZ2d1IHNlbGVzYWksIGRhbiBtZW5hbXBpbGthbiBsaW5rLgotIFlvdVR1YmUgbGViaWggY2VwYXQ6IHBlbmNhcmlhbiB0YW5wYSBtZW11YXQgaGFsYW1hbiBoYXNpbCBkYW4gamVk
::B64:agent.js:YSBkaXBlcnBlbmRlay4KLSBBSSBsZWJpaCByaW5nYW46IGhhbnlhIGFsYXQgeWFuZyByZWxldmFuIGRpa2lyaW0sIGFsYXQgYmFjYS1zYWphIGJlcmphbGFuIGJlcnNhbWFhbiwgL3RlcyBtZW1pbGloIG1vZGVsIFRFUkNFUEFULgotIEFsYXQgYmFydTogc2V0X3Zv
::B64:agent.js:bHVtZSwgc3BlYWssIHNldF90aW1lciwgc2F2ZV9zY3JlZW5zaG90LCBjb3B5X3BhdGgsIHJlY2VudF9maWxlcywgc2VhcmNoX3RleHQuCi0gU2V0aWFwIHR1Z2FzIG1lbmFtcGlsa2FuIGxhbWEgc2VsZXNhaW55YS4gS2V0aWsgL2Zhc3Qgb2ZmIHVudHVrIG1lbWF0
::B64:agent.js:aWthbiBqYWx1ciBjZXBhdC4KS2V0aWsgL2JhbnR1YW4gdW50dWsgZGFmdGFyIGxlbmdrYXAuYDsKCmNvbnN0IEhFTFAgPSBgCkpBTFVSIENFUEFUICh0YW5wYSBBSSwgbGFuZ3N1bmcgamFsYW4pCiAgcHV0YXIgbGFndSBraXNzIG1lICB8ICB2b2x1bWUgNTAgIHwg
::B64:agent.js:IG5haWtpbiB2b2x1bWUgIHwgIHBhdXNlIC8gbmV4dCAvIG1hanUgMzAgIHwgIGJ1a2EgeW91dHViZSwgZ21haWwKICBidWthIGZvbGRlciBSZWlhICB8ICBidWthIGthbWVyYSAgfCAgY2FyaSBmaWxlIGxhcG9yYW4gIHwgIGNhcmkgY3VhY2EgYmVzb2sgZGkgd2Vi
::B64:agent.js:ICB8ICBzY3JlZW5zaG90CiAgdXBsb2FkIGxhcG9yYW4ucGRmIGtlIG1lZGlhZmlyZSAgfCAgdXBsb2FkIGZpbGUgdGVyYmFydSBrZSBtZWRpYWZpcmUgIHwgIHVwbG9hZCBzZW11YSBwZGYgZGkgZm9sZGVyIExhcG9yYW4ga2UgbWVkaWFmaXJlCiAgaW5nYXRrYW4g
::B64:agent.js:MTAgbWVuaXQgbGFnaSBtaW51bSBvYmF0ICB8ICBpbmZvIHBjICB8ICBqYW0gYmVyYXBhCkZJVFVSIEFHRU5UIChsZXdhdCBBSSB1bnR1ayB0dWdhcyB5YW5nIGxlYmloIHJ1bWl0KQogIEJyb3dzZXIgIDogYnVrYSB3ZWJzaXRlLCBpc2kgZm9ybSwga2xpaywgY2Fy
::B64:agent.js:aSBkaSB3ZWIsIHNjcm9sbCwgYmFueWFrIHRhYgogIFlvdVR1YmUgIDogcHV0YXIgb3RvbWF0aXMgKHNraXAgaWtsYW4pLCBrb250cm9sIHBhdXNlL25leHQvbWFqdS9tdW5kdXIvbXV0ZS9mdWxsc2NyZWVuCiAgVXBsb2FkICAgOiBjZXBhdCwgYmFueWFrIGZpbGUs
::B64:agent.js:IHNhdHUgZm9sZGVyIChkaS16aXApLCBkYXJpIGxva2FzaSBtYW5hIHB1biwgbWVuYW1waWxrYW4gbGluayBoYXNpbAogIExvZ2luICAgIDogL2xvZ2luIGxhbHUgbG9naW4gbWFudWFsIHNla2FsaSwgc2VzaSB0ZXJzaW1wYW4uIEFnZW50IHRpZGFrIHBlcm5haCBt
::B64:agent.js:ZW5nZXRpayBwYXNzd29yZG11CiAgTGF5YXIgICAgOiBzY3JlZW5zaG90LCBrbGlrLCBzY3JvbGwsIGtldGlrLCB0ZWthbiB0b21ib2wsIGplbmRlbGEKICBGaWxlICAgICA6IGNhcmkgZmlsZS9mb2xkZXIgc2VtdWEgZHJpdmUsIGJhY2EvdHVsaXMsIHNhbGluLCBw
::B64:agent.js:aW5kYWgsIHppcCwgaGFwdXMga2UgUmVjeWNsZSBCaW4sIHVuZHVoLCBjYXJpIHRla3MKICBQQyAgICAgICA6IHZvbHVtZSwgdG9tYm9sIG1lZGlhLCBjbGlwYm9hcmQsIGluZm8gc2lzdGVtLCBiaWNhcmEsIHBlbmdpbmdhdApQRVJJTlRBSCBLSFVTVVMKICAvbG9n
::B64:agent.js:aW4gW2FsYW1hdF0gIGxvZ2luIG1hbnVhbCAgICAgICAgICAgIC9iYXJ1ICAgZml0dXIgdGVyYmFydSAgICAgICAgICAvZmFzdCBvbnxvZmYgIGphbHVyIGNlcGF0CiAgL3RlcyAgICAgICAgICAgICB1amkgbW9kZWwsIHBpbGloIFRFUkNFUEFUICAgIC9tb2RlbCBb
::B64:agent.js:bmFtYV0gIGxpaGF0L2dhbnRpIG1vZGVsCiAgL3VwZGF0ZSAgICAgICAgICBwZXJiYXJ1aSBzZWthcmFuZyAgICAgICAvdmVyc2kgIGNlayB2ZXJzaSAgICAgICAgICAgICAgL3Jlc2V0ICBsdXBha2FuIHBlcmNha2FwYW4KICAvYmFudHVhbiAgICAgICAgIHRhbXBp
::B64:agent.js:bGthbiBpbmkgICAgICAgICAgIGV4aXQgICAga2VsdWFyCmA7CgpmdW5jdGlvbiBzaG93V2hhdHNOZXcoZm9yY2UgPSBmYWxzZSkgewogIGNvbnN0IHZlciA9IGxvY2FsVmVyc2lvbigpOwogIGxldCBzZWVuID0gIiI7CiAgdHJ5IHsKICAgIHNlZW4gPSBmcy5yZWFk
::B64:agent.js:RmlsZVN5bmMoIi53aGF0c25ldy1zZWVuIiwgInV0ZjgiKS50cmltKCk7CiAgfSBjYXRjaCB7fQogIGlmICghZm9yY2UgJiYgc2VlbiA9PT0gdmVyKSByZXR1cm47CiAgbGV0IHRleHQgPSAiIjsKICB0cnkgewogICAgdGV4dCA9IGZzLnJlYWRGaWxlU3luYygiY2hh
::B64:agent.js:bmdlbG9nLnR4dCIsICJ1dGY4IikudHJpbSgpOwogIH0gY2F0Y2gge30KICBpZiAoIXRleHQpIHRleHQgPSBCVUlMVElOX0NIQU5HRUxPRzsKICBjb25zb2xlLmxvZygiXG49PT09PT09PT09PT09PT09PT0gWUFORyBCQVJVID09PT09PT09PT09PT09PT09PSIpOwog
::B64:agent.js:IGNvbnNvbGUubG9nKHRleHQuc3BsaXQoL1xyP1xuLykuc2xpY2UoMCwgMzApLmpvaW4oIlxuIikpOwogIGNvbnNvbGUubG9nKCI9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PSIpOwogIHRyeSB7CiAgICBmcy53cml0ZUZpbGVT
::B64:agent.js:eW5jKCIud2hhdHNuZXctc2VlbiIsIHZlcik7CiAgfSBjYXRjaCB7fQp9Cgpjb25zb2xlLmxvZyhgQWdlbnQgc2lhcC4gVmVyc2kgJHtsb2NhbFZlcnNpb24oKX0uIEZvbGRlciB1cGxvYWQ6ICR7U0FGRV9ESVJ9YCk7CmNvbnNvbGUubG9nKGBJemluIHNlYmVsdW0g
::B64:agent.js:YWtzaTogJHtDT05GSVJNID8gIkFLVElGIiA6ICJNQVRJIn0uIFRla2FuIEN0cmwrQyBrYXBhbiBzYWphIHVudHVrIG1lbmdoZW50aWthbi5gKTsKc2hvd1doYXRzTmV3KCk7CmNvbnNvbGUubG9nKCdLZXRpayBwZXJpbnRhaCBkYWxhbSBiYWhhc2EgYmlhc2EuIEtl
::B64:agent.js:dGlrIC9iYW50dWFuIHVudHVrIGRhZnRhciBmaXR1ciwgL2xvZ2luIHVudHVrIGxvZ2luLCBleGl0IHVudHVrIGtlbHVhci4nKTsKY2hlY2tVcGRhdGUoKTsKd2hpbGUgKHRydWUpIHsKICBjb25zdCBjbWQgPSBhd2FpdCBybC5xdWVzdGlvbigiXG5QZXJpbnRhaD4g
::B64:agent.js:Iik7CiAgY29uc3QgYyA9IGNtZC50cmltKCk7CiAgaWYgKGMgPT09ICJleGl0IikgYnJlYWs7CiAgaWYgKCFjKSBjb250aW51ZTsKICBpZiAoYyA9PT0gIi90ZXMiKSB7CiAgICBpZiAoIWZhbGxiYWNrTW9kZWxzKSBmYWxsYmFja01vZGVscyA9IGF3YWl0IGRpc2Nv
::B64:agent.js:dmVyTW9kZWxzKCk7CiAgICBjb25zdCBsaXN0ID0gbW9kZWxQb29sKCkuc2xpY2UoMCwgOSk7CiAgICBjb25zb2xlLmxvZyhgTWVuZ3VqaSAke2xpc3QubGVuZ3RofSBtb2RlbCwgdGlhcCBtb2RlbCBtYWtzaW1hbCA0NSBkZXRpay4uLmApOwogICAgY29uc3QgcmVz
::B64:agent.js:dWx0cyA9IGF3YWl0IFByb21pc2UuYWxsKGxpc3QubWFwKGFzeW5jIChtKSA9PiAoeyBtLCByOiBhd2FpdCB0ZXN0TW9kZWwobSkgfSkpKTsgLy8gZGl1amkgYmVyc2FtYWFuCiAgICBmb3IgKGNvbnN0IHsgbSwgciB9IG9mIHJlc3VsdHMpIGNvbnNvbGUubG9nKGAg
::B64:agent.js:ICR7ci5tYXJrfSAke219ICAgJHtyLm1zfSBtcyAgICR7ci50ZXh0fWApOwogICAgY29uc3QgYmVzdCA9IHJlc3VsdHMuZmlsdGVyKCh4KSA9PiB4LnIubWFyayA9PT0gIltPS10iKS5zb3J0KCh4LCB5KSA9PiB4LnIubXMgLSB5LnIubXMpWzBdPy5tIHx8ICIiOwog
::B64:agent.js:ICAgaWYgKCFiZXN0KSB7CiAgICAgIGNvbnNvbGUubG9nKCJcblRpZGFrIGFkYSBtb2RlbCB5YW5nIGxvbG9zLiBDZWsgZGFzaGJvYXJkIDlSb3V0ZXI6IHByb3ZpZGVyIHRlcmh1YnVuZywga3VvdGEsIGRhbiBtZW51IENvbnNvbGUgTG9nLiIpOwogICAgfSBlbHNl
::B64:agent.js:IGlmIChiZXN0ID09PSBiYXNlTW9kZWwpIHsKICAgICAgY29uc29sZS5sb2coYFxuTW9kZWwgYWt0aWYgKCR7YmFzZU1vZGVsfSkgc3VkYWggeWFuZyB0ZXJjZXBhdCBkYW4gYmVyZnVuZ3NpLmApOwogICAgfSBlbHNlIHsKICAgICAgYmFzZU1vZGVsID0gYmVzdDsK
::B64:agent.js:ICAgICAgcG9vbElkeCA9IDA7CiAgICAgIHRyeSB7CiAgICAgICAgZnMud3JpdGVGaWxlU3luYyhNT0RFTF9GSUxFLCBiZXN0KTsKICAgICAgfSBjYXRjaCB7fQogICAgICBjb25zb2xlLmxvZyhgXG5Nb2RlbCB0ZXJjZXBhdCB5YW5nIGJlcmZ1bmdzaSBkaXBpbGlo
::B64:agent.js:IG90b21hdGlzOiAke2Jlc3R9ICh0ZXJzaW1wYW4sIGtldGlrIC9tb2RlbCByZXNldCB1bnR1ayBrZW1iYWxpIGtlIGJhd2FhbikuYCk7CiAgICB9CiAgICBjb250aW51ZTsKICB9CiAgaWYgKGMgPT09ICIvbW9kZWwiIHx8IGMuc3RhcnRzV2l0aCgiL21vZGVsICIp
::B64:agent.js:KSB7CiAgICBjb25zdCBhcmcgPSBjLnNsaWNlKDYpLnRyaW0oKTsKICAgIGlmICghYXJnKSB7CiAgICAgIGlmICghZmFsbGJhY2tNb2RlbHMpIGZhbGxiYWNrTW9kZWxzID0gYXdhaXQgZGlzY292ZXJNb2RlbHMoKTsKICAgICAgY29uc29sZS5sb2coYE1vZGVsIGFr
::B64:agent.js:dGlmOiAke2Jhc2VNb2RlbH1cbk1vZGVsIGxhaW4geWFuZyB0ZXJzZWRpYTogJHttb2RlbFBvb2woKS5zbGljZSgxKS5qb2luKCIsICIpIHx8ICIodGlkYWsgYWRhKSJ9YCk7CiAgICB9IGVsc2UgaWYgKGFyZyA9PT0gInJlc2V0IikgewogICAgICB0cnkgewogICAg
::B64:agent.js:ICAgIGZzLnVubGlua1N5bmMoTU9ERUxfRklMRSk7CiAgICAgIH0gY2F0Y2gge30KICAgICAgYmFzZU1vZGVsID0gTU9ERUw7CiAgICAgIHBvb2xJZHggPSAwOwogICAgICBjb25zb2xlLmxvZyhgS2VtYmFsaSBrZSBtb2RlbCBiYXdhYW46ICR7TU9ERUx9YCk7CiAg
::B64:agent.js:ICB9IGVsc2UgewogICAgICBiYXNlTW9kZWwgPSBhcmc7CiAgICAgIHBvb2xJZHggPSAwOwogICAgICB0cnkgewogICAgICAgIGZzLndyaXRlRmlsZVN5bmMoTU9ERUxfRklMRSwgYXJnKTsKICAgICAgfSBjYXRjaCB7fQogICAgICBjb25zb2xlLmxvZyhgTW9kZWwg
::B64:agent.js:ZGlnYW50aSBrZTogJHthcmd9YCk7CiAgICB9CiAgICBjb250aW51ZTsKICB9CiAgaWYgKGMgPT09ICIvYmFudHVhbiIpIHsKICAgIGNvbnNvbGUubG9nKEhFTFApOwogICAgY29udGludWU7CiAgfQogIGlmIChjID09PSAiL2JhcnUiKSB7CiAgICBzaG93V2hhdHNO
::B64:agent.js:ZXcodHJ1ZSk7CiAgICBjb250aW51ZTsKICB9CiAgaWYgKGMuc3RhcnRzV2l0aCgiL2xvZ2luIikpIHsKICAgIGxldCB0YXJnZXQgPSBjLnNwbGl0KC9ccysvKVsxXSB8fCAiaHR0cHM6Ly9hY2NvdW50cy5nb29nbGUuY29tL1NlcnZpY2VMb2dpbj9zZXJ2aWNlPXlv
::B64:agent.js:dXR1YmUmY29udGludWU9aHR0cHM6Ly93d3cueW91dHViZS5jb20vIjsKICAgIGlmICghL15odHRwcz86XC9cLy9pLnRlc3QodGFyZ2V0KSkgdGFyZ2V0ID0gImh0dHBzOi8vIiArIHRhcmdldDsKICAgIHRyeSB7CiAgICAgIGF3YWl0IGVuc3VyZVBhZ2UoKTsKICAg
::B64:agent.js:ICAgYXdhaXQgcGFnZS5icmluZ1RvRnJvbnQoKTsKICAgICAgYXdhaXQgcGFnZS5nb3RvKHRhcmdldCwgeyB3YWl0VW50aWw6ICJkb21jb250ZW50bG9hZGVkIiB9KTsKICAgIH0gY2F0Y2ggKGUpIHsKICAgICAgY29uc29sZS5sb2coIkdhZ2FsIG1lbWJ1a2EgaGFs
::B64:agent.js:YW1hbiBsb2dpbjoiLCBlLm1lc3NhZ2UpOwogICAgfQogICAgY29uc29sZS5sb2coIlNpbGFrYW4gbG9naW4gZGkgamVuZGVsYSBicm93c2VyIChrYW11IHlhbmcgbWVuZ2V0aWssIGFnZW50IHRpZGFrIG1lbGloYXQgcGFzc3dvcmQpLiIpOwogICAgYXdhaXQgcmwu
::B64:agent.js:cXVlc3Rpb24oIlNldGVsYWggc2VsZXNhaSwgdGVrYW4gRW50ZXIgZGkgc2luaS4uLiAiKTsKICAgIGNvbnNvbGUubG9nKCJMb2dpbiB0ZXJzaW1wYW4gZGkgcHJvZmlsIGJyb3dzZXIuIEJlcmlrdXRueWEgdGlkYWsgcGVybHUgbG9naW4gbGFnaS4iKTsKICAgIGNv
::B64:agent.js:bnRpbnVlOwogIH0KICBpZiAoYyA9PT0gIi92ZXJzaSIpIHsKICAgIGNvbnNvbGUubG9nKGBWZXJzaSBhZ2VudDogJHtsb2NhbFZlcnNpb24oKX1gKTsKICAgIGF3YWl0IGNoZWNrVXBkYXRlKCk7CiAgICBpZiAoIXBlbmRpbmdWZXJzaW9uKSBjb25zb2xlLmxvZygi
::B64:agent.js:U3VkYWggdmVyc2kgdGVyYmFydSAoYXRhdSB1cGRhdGUgb25saW5lIHRpZGFrIGFrdGlmKS4iKTsKICAgIGNvbnRpbnVlOwogIH0KICBpZiAoYyA9PT0gIi91cGRhdGUiKSB7CiAgICBjb25zb2xlLmxvZygiTWVtcGVyYmFydWkuLi4gYWdlbnQgYWthbiBtZW51dHVw
::B64:agent.js:IGRhbiBtZW55YWxhIGxhZ2kgb3RvbWF0aXMgbGV3YXQgc3RhcnQtYWdlbnQuYmF0LiIpOwogICAgYXdhaXQgc2h1dGRvd25Ccm93c2VyKCk7CiAgICBybC5jbG9zZSgpOwogICAgcHJvY2Vzcy5leGl0KDQyKTsgLy8ga29kZSA0MiA9IHBlcm1pbnRhYW4gcmVzdGFy
::B64:agent.js:dCB1bnR1ayB1cGRhdGU7IGRpdGFuZ2thcCBvbGVoIHN0YXJ0LWFnZW50LmJhdAogIH0KICBpZiAoYyA9PT0gIi9mYXN0IiB8fCBjLnN0YXJ0c1dpdGgoIi9mYXN0ICIpKSB7CiAgICBjb25zdCBhcmcgPSBjLnNsaWNlKDUpLnRyaW0oKS50b0xvd2VyQ2FzZSgpOwog
::B64:agent.js:ICAgaWYgKGFyZyA9PT0gIm9uIikgRkFTVCA9IHRydWU7CiAgICBlbHNlIGlmIChhcmcgPT09ICJvZmYiKSBGQVNUID0gZmFsc2U7CiAgICBjb25zb2xlLmxvZyhgSmFsdXIgY2VwYXQgKHRhbnBhIEFJIHVudHVrIHBlcmludGFoIHVtdW0pOiAke0ZBU1QgPyAiQUtU
::B64:agent.js:SUYiIDogIk1BVEkifS4gS2V0aWsgL2Zhc3Qgb24gYXRhdSAvZmFzdCBvZmYuYCk7CiAgICBjb250aW51ZTsKICB9CiAgaWYgKGMgPT09ICIvcmVzZXQiKSB7CiAgICBoaXN0b3J5Lmxlbmd0aCA9IDA7CiAgICBleHRyYUdyb3Vwcy5jbGVhcigpOwogICAgY29uc29s
::B64:agent.js:ZS5sb2coIlBlcmNha2FwYW4gZGlsdXBha2FuLiIpOwogICAgY29udGludWU7CiAgfQogIGNvbnN0IHQwID0gRGF0ZS5ub3coKTsKICBjb25zdCBkZXRpayA9ICgpID0+ICgoRGF0ZS5ub3coKSAtIHQwKSAvIDEwMDApLnRvRml4ZWQoMSk7CiAgaWYgKEZBU1QpIHsK
::B64:agent.js:ICAgIGxldCByID0gbnVsbDsKICAgIHRyeSB7CiAgICAgIHIgPSBhd2FpdCB0cnlGYXN0Q29tbWFuZChjKTsKICAgIH0gY2F0Y2ggKGUpIHsKICAgICAgY29uc29sZS5sb2coYCAgKGphbHVyIGNlcGF0IGdhZ2FsOiAke1N0cmluZyhlLm1lc3NhZ2UpLnNsaWNlKDAs
::B64:agent.js:IDE2MCl9LiBEaXNlcmFoa2FuIGtlIEFJLi4uKWApOwogICAgfQogICAgaWYgKHIgIT0gbnVsbCkgewogICAgICBjb25zb2xlLmxvZyhgXG5bY2VwYXRdICR7cn1cbigke2RldGlrKCl9IGR0aywgdGFucGEgQUkpYCk7CiAgICAgIGhpc3RvcnkucHVzaCh7IHJvbGU6
::B64:agent.js:ICJ1c2VyIiwgY29udGVudDogYyB9LCB7IHJvbGU6ICJhc3Npc3RhbnQiLCBjb250ZW50OiBgW2phbHVyIGNlcGF0XSAke1N0cmluZyhyKS5zbGljZSgwLCA1MDApfWAgfSk7CiAgICAgIHRyaW1IaXN0b3J5KCk7CiAgICAgIGNvbnRpbnVlOwogICAgfQogIH0KICB0
::B64:agent.js:cnkgewogICAgYXdhaXQgcnVuVGFzayhjKTsKICAgIGNvbnNvbGUubG9nKGAoc2VsZXNhaSBkYWxhbSAke2RldGlrKCl9IGR0aylgKTsKICB9IGNhdGNoIChlKSB7CiAgICBjb25zb2xlLmVycm9yKCJHYWdhbDoiLCBlLm1lc3NhZ2UpOwogIH0KfQphd2FpdCBzaHV0
::B64:agent.js:ZG93bkJyb3dzZXIoKTsKcmwuY2xvc2UoKTsK
::B64:package.json:ewogICJuYW1lIjogImJvdC1hZ2VudCIsCiAgInZlcnNpb24iOiAiMS4wLjAiLAogICJ0eXBlIjogIm1vZHVsZSIsCiAgInNjcmlwdHMiOiB7CiAgICAic3RhcnQiOiAibm9kZSBhZ2VudC5qcyIKICB9LAogICJkZXBlbmRlbmNpZXMiOiB7CiAgICAicGxheXdyaWdo
::B64:package.json:dCI6ICJeMS40OC4wIgogIH0KfQo=
