@echo off
setlocal EnableExtensions
chcp 65001 >nul
title Agent Automation
set "SELF=%~f0"
set "EMBED_VER=5"

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
curl.exe -fsSL --max-time 15 -o ".remote-version" "%UPD_URL%/version.txt" 2>nul
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
curl.exe -fsSL --max-time 10 -o ".remote-changelog" "%UPD_URL%/changelog.txt" 2>nul
copy /y "package.json" "package.json.bak" >nul
set "UPDATE_FAILED="
curl.exe -fsSL --max-time 15 -o ".remote-files" "%UPD_URL%/files.txt" 2>nul
if errorlevel 1 goto UPDATE_FAIL
for /f "usebackq delims=" %%F in (".remote-files") do call :DL_FILE "%%F"
if defined UPDATE_FAILED goto UPDATE_FAIL
copy /y ".remote-version" "version.txt" >nul
fc "package.json" "package.json.bak" >nul 2>&1
if errorlevel 1 set "NEED_INSTALL=1"
echo     Pembaruan selesai. Sekarang versi %REMOTEVER%.
call :SHOW_CHANGELOG
goto UPDATE_DONE
:UPDATE_SAME
echo     Sudah versi terbaru: %LOCALVER%
goto UPDATE_DONE
:UPDATE_DISABLED
echo     Update otomatis dimatikan ^(AUTO_UPDATE=0^).
goto UPDATE_DONE
:UPDATE_OFFLINE
echo     Tidak bisa cek pembaruan, melanjutkan dengan versi lokal.
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
echo [5/7] Memeriksa browser Chromium...
if exist ".chromium-ok" goto CHROMIUM_OK
echo     Mengunduh Chromium, ini hanya sekali dan agak lama...
call npx playwright install chromium
if errorlevel 1 goto FAIL
echo ok> ".chromium-ok"
:CHROMIUM_OK
echo     Chromium siap.

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
curl.exe -fsSL --max-time 10 -o ".remote-notice" "%UPD_URL%/notice.txt" 2>nul
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
curl.exe -fsSL --max-time 60 -o "%FN%.new" "%UPD_URL%/%FN%" 2>nul
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
::B64:agent.js:ZnMiOwppbXBvcnQgb3MgZnJvbSAib3MiOwppbXBvcnQgcGF0aCBmcm9tICJwYXRoIjsKaW1wb3J0IHJlYWRsaW5lIGZyb20gInJlYWRsaW5lL3Byb21pc2VzIjsKaW1wb3J0IHsgZXhlY0ZpbGUgfSBmcm9tICJjaGlsZF9wcm9jZXNzIjsKCmNvbnN0IEJBU0VfVVJM
::B64:agent.js:ID0gcHJvY2Vzcy5lbnYuUk9VVEVSX1VSTCB8fCAiaHR0cDovL2xvY2FsaG9zdDoyMDEyOC92MSI7CmNvbnN0IEFQSV9LRVkgPSBwcm9jZXNzLmVudi5ST1VURVJfS0VZOwpjb25zdCBNT0RFTCA9IHByb2Nlc3MuZW52LlJPVVRFUl9NT0RFTCB8fCAiYm90LWNvbWJv
::B64:agent.js:IjsKY29uc3QgU0FGRV9ESVIgPSBwYXRoLnJlc29sdmUocHJvY2Vzcy5lbnYuU0FGRV9ESVIgfHwgIi4vdXBsb2FkLWZvbGRlciIpOwpjb25zdCBDT05GSVJNID0gcHJvY2Vzcy5lbnYuQ09ORklSTSAhPT0gIjAiOyAvLyBtaW50YSBpemluIHNlYmVsdW0gYWtzaSBm
::B64:agent.js:aXNpayAoa2xpaywga2V0aWssIGJ1a2EpCmNvbnN0IE1BWF9TVEVQUyA9IDMwOwpjb25zdCBIT01FID0gb3MuaG9tZWRpcigpOwpjb25zdCBTRUFSQ0hfUk9PVFMgPSBbSE9NRSwgLi4uKHByb2Nlc3MuZW52LlNFQVJDSF9ST09UUyA/IHByb2Nlc3MuZW52LlNFQVJD
::B64:agent.js:SF9ST09UUy5zcGxpdCgiOyIpIDogW10pXTsKZm9yIChjb25zdCBMIG9mICJERUZHSElKS0xNTk9QUVJTVFVWV1hZWiIpIHsKICAvLyBEcml2ZSBsYWluIChEOiwgRTosIGZsYXNoZGlzaywgZGxsKSBpa3V0IGRpY2FyaSBvdG9tYXRpcwogIHRyeSB7CiAgICBpZiAo
::B64:agent.js:ZnMuZXhpc3RzU3luYyhgJHtMfTpcXGApKSBTRUFSQ0hfUk9PVFMucHVzaChgJHtMfTpcXGApOwogIH0gY2F0Y2gge30KfQoKaWYgKCFBUElfS0VZKSB7CiAgY29uc29sZS5lcnJvcigiUk9VVEVSX0tFWSBiZWx1bSBkaWlzaS4iKTsKICBwcm9jZXNzLmV4aXQoMSk7
::B64:agent.js:Cn0KZnMubWtkaXJTeW5jKFNBRkVfRElSLCB7IHJlY3Vyc2l2ZTogdHJ1ZSB9KTsKCmNvbnN0IHJsID0gcmVhZGxpbmUuY3JlYXRlSW50ZXJmYWNlKHsgaW5wdXQ6IHByb2Nlc3Muc3RkaW4sIG91dHB1dDogcHJvY2Vzcy5zdGRvdXQgfSk7CmNvbnN0IHNsZWVwID0g
::B64:agent.js:KG1zKSA9PiBuZXcgUHJvbWlzZSgocikgPT4gc2V0VGltZW91dChyLCBtcykpOwoKLy8gPT09PT0gUGVtYmVyaXRhaHVhbiB1cGRhdGUgKFVSTCBkaWJlcmlrYW4gb3RvbWF0aXMgb2xlaCBzdGFydC1hZ2VudC5iYXQpID09PT09CmNvbnN0IFVQRF9VUkwgPSBwcm9j
::B64:agent.js:ZXNzLmVudi5VUERfVVJMIHx8ICIiOwpjb25zdCBsb2NhbFZlcnNpb24gPSAoKSA9PiB7CiAgdHJ5IHsKICAgIHJldHVybiBmcy5yZWFkRmlsZVN5bmMoInZlcnNpb24udHh0IiwgInV0ZjgiKS50cmltKCkgfHwgIjAiOwogIH0gY2F0Y2ggewogICAgcmV0dXJuICIw
::B64:agent.js:IjsKICB9Cn07CmxldCBwZW5kaW5nVmVyc2lvbiA9ICIiOwoKYXN5bmMgZnVuY3Rpb24gY2hlY2tVcGRhdGUoKSB7CiAgaWYgKCFVUERfVVJMIHx8IHByb2Nlc3MuZW52LkFVVE9fVVBEQVRFID09PSAiMCIpIHJldHVybjsKICB0cnkgewogICAgY29uc3QgcmVzID0g
::B64:agent.js:YXdhaXQgZmV0Y2goYCR7VVBEX1VSTH0vdmVyc2lvbi50eHRgLCB7IHNpZ25hbDogQWJvcnRTaWduYWwudGltZW91dCgxMDAwMCkgfSk7CiAgICBpZiAoIXJlcy5vaykgcmV0dXJuOwogICAgY29uc3QgcmVtb3RlID0gKGF3YWl0IHJlcy50ZXh0KCkpLnRyaW0oKTsK
::B64:agent.js:ICAgIGlmIChyZW1vdGUgJiYgcmVtb3RlICE9PSBsb2NhbFZlcnNpb24oKSAmJiByZW1vdGUgIT09IHBlbmRpbmdWZXJzaW9uKSB7CiAgICAgIHBlbmRpbmdWZXJzaW9uID0gcmVtb3RlOwogICAgICBjb25zb2xlLmxvZyhgXG4qKiogVVBEQVRFIFRFUlNFRElBOiB2
::B64:agent.js:ZXJzaSAke3JlbW90ZX0gKHZlcnNpIGthbXU6ICR7bG9jYWxWZXJzaW9uKCl9KSAqKipgKTsKICAgICAgY29uc29sZS5sb2coJyAgICBLZXRpayAiL3VwZGF0ZSIgdW50dWsgbWVtcGVyYmFydWkgb3RvbWF0aXMgc2VrYXJhbmcuJyk7CiAgICB9CiAgfSBjYXRjaCB7
::B64:agent.js:fQp9CnNldEludGVydmFsKGNoZWNrVXBkYXRlLCAxNSAqIDYwICogMTAwMCkudW5yZWYoKTsKCi8vIEJyb3dzZXIgZGVuZ2FuIHByb2ZpbCBwZXJtYW5lbjogbG9naW4gc2VrYWxpLCBzZXNpIHRlcnNpbXBhbgpjb25zdCBjb250ZXh0ID0gYXdhaXQgY2hyb21pdW0u
::B64:agent.js:bGF1bmNoUGVyc2lzdGVudENvbnRleHQoIi4vYnJvd3Nlci1wcm9maWxlIiwgewogIGhlYWRsZXNzOiBmYWxzZSwKICBhcmdzOiBbIi0tYXV0b3BsYXktcG9saWN5PW5vLXVzZXItZ2VzdHVyZS1yZXF1aXJlZCJdLAp9KTsKY29uc3QgcGFnZSA9IGNvbnRleHQucGFn
::B64:agent.js:ZXMoKVswXSB8fCAoYXdhaXQgY29udGV4dC5uZXdQYWdlKCkpOwoKLy8gTmFtYSBmaWxlIHJlbGF0aWYgZGljYXJpIGRpIFNBRkVfRElSOyBwYXRoIGxlbmdrYXAgZGkgbG9rYXNpIG1hbmEgcHVuIGJvbGVoLgovLyBQZW5nYW1hbm55YSBhZGFsYWggaXppbiB5L24g
::B64:agent.js:c2ViZWx1bSBzZXRpYXAgdXBsb2FkLgpmdW5jdGlvbiBzYWZlUGF0aChuYW1lKSB7CiAgY29uc3QgZnVsbCA9IHBhdGgucmVzb2x2ZShTQUZFX0RJUiwgU3RyaW5nKG5hbWUpLnJlcGxhY2UoL14ifCIkL2csICIiKSk7CiAgaWYgKCFmcy5leGlzdHNTeW5jKGZ1bGwp
::B64:agent.js:IHx8ICFmcy5zdGF0U3luYyhmdWxsKS5pc0ZpbGUoKSkgewogICAgdGhyb3cgbmV3IEVycm9yKCJGaWxlIHRpZGFrIGRpdGVtdWthbjogIiArIGZ1bGwpOwogIH0KICByZXR1cm4gZnVsbDsKfQoKYXN5bmMgZnVuY3Rpb24gYXNrKG1zZykgewogIGlmICghQ09ORklS
::B64:agent.js:TSkgcmV0dXJuIHRydWU7CiAgY29uc3QgYSA9IGF3YWl0IHJsLnF1ZXN0aW9uKGBcbltJWklOXSAke21zZ30gKHkvbik6IGApOwogIHJldHVybiBhLnRyaW0oKS50b0xvd2VyQ2FzZSgpID09PSAieSI7Cn0KCi8vID09PT09IEhlbHBlciBQb3dlclNoZWxsIChrb250
::B64:agent.js:cm9sIGRlc2t0b3AgV2luZG93cyB0YW5wYSBsaWJyYXJ5IHRhbWJhaGFuKSA9PT09PQpmdW5jdGlvbiBwcyhzY3JpcHQsIGVudiA9IHt9KSB7CiAgY29uc3QgZW5jb2RlZCA9IEJ1ZmZlci5mcm9tKHNjcmlwdCwgInV0ZjE2bGUiKS50b1N0cmluZygiYmFzZTY0Iik7
::B64:agent.js:CiAgcmV0dXJuIG5ldyBQcm9taXNlKChyZXNvbHZlLCByZWplY3QpID0+IHsKICAgIGV4ZWNGaWxlKAogICAgICAicG93ZXJzaGVsbCIsCiAgICAgIFsiLU5vUHJvZmlsZSIsICItTm9uSW50ZXJhY3RpdmUiLCAiLUVuY29kZWRDb21tYW5kIiwgZW5jb2RlZF0sCiAg
::B64:agent.js:ICAgIHsgZW52OiB7IC4uLnByb2Nlc3MuZW52LCAuLi5lbnYgfSwgdGltZW91dDogMzAwMDAsIG1heEJ1ZmZlcjogMjAgKiAxMDI0ICogMTAyNCB9LAogICAgICAoZXJyLCBzdGRvdXQsIHN0ZGVycikgPT4KICAgICAgICBlcnIgPyByZWplY3QobmV3IEVycm9yKChz
::B64:agent.js:dGRlcnIgfHwgZXJyLm1lc3NhZ2UpLnNsaWNlKDAsIDMwMCkpKSA6IHJlc29sdmUoc3Rkb3V0LnRyaW0oKSkKICAgICk7CiAgfSk7Cn0KCmNvbnN0IFBTX0hFQUQgPSBgCkFkZC1UeXBlIEAiCnVzaW5nIFN5c3RlbTsKdXNpbmcgU3lzdGVtLlJ1bnRpbWUuSW50ZXJv
::B64:agent.js:cFNlcnZpY2VzOwpwdWJsaWMgY2xhc3MgVyB7CiAgW0RsbEltcG9ydCgidXNlcjMyLmRsbCIpXSBwdWJsaWMgc3RhdGljIGV4dGVybiBib29sIFNldFByb2Nlc3NEUElBd2FyZSgpOwogIFtEbGxJbXBvcnQoInVzZXIzMi5kbGwiKV0gcHVibGljIHN0YXRpYyBleHRl
::B64:agent.js:cm4gYm9vbCBTZXRDdXJzb3JQb3MoaW50IHgsIGludCB5KTsKICBbRGxsSW1wb3J0KCJ1c2VyMzIuZGxsIildIHB1YmxpYyBzdGF0aWMgZXh0ZXJuIHZvaWQgbW91c2VfZXZlbnQodWludCBmLCB1aW50IGR4LCB1aW50IGR5LCBpbnQgZCwgVUludFB0ciBlKTsKfQoi
::B64:agent.js:QApbV106OlNldFByb2Nlc3NEUElBd2FyZSgpIHwgT3V0LU51bGwKQWRkLVR5cGUgLUFzc2VtYmx5TmFtZSBTeXN0ZW0uV2luZG93cy5Gb3JtcyxTeXN0ZW0uRHJhd2luZwpgOwoKbGV0IHNjYWxlID0gMTsgLy8gcmFzaW8gbGF5YXIgYXNsaSAvIHNjcmVlbnNob3QK
::B64:agent.js:Y29uc3QgcGVuZGluZ0ltYWdlcyA9IFtdOyAvLyBnYW1iYXIgeWFuZyBkaWtpcmltIGtlIG1vZGVsIHNldGVsYWggdG9vbCBkaWphbGFua2FuCgpjb25zdCBTS0lQX0RJUlMgPSBuZXcgU2V0KFsKICAibm9kZV9tb2R1bGVzIiwgImFwcGRhdGEiLCAiLmdpdCIsICJ3
::B64:agent.js:aW5kb3dzIiwgInByb2dyYW0gZmlsZXMiLCAicHJvZ3JhbSBmaWxlcyAoeDg2KSIsCiAgInByb2dyYW1kYXRhIiwgIiRyZWN5Y2xlLmJpbiIsICJzeXN0ZW0gdm9sdW1lIGluZm9ybWF0aW9uIiwKXSk7CmxldCBzZWFyY2hEZWFkbGluZSA9IDA7CgovLyBDYXJpIGZv
::B64:agent.js:bGRlciAod2FudEZpbGVzPWZhbHNlKSBhdGF1IGZpbGUgKHdhbnRGaWxlcz10cnVlKSBiZXJkYXNhcmthbiBzZWJhZ2lhbiBuYW1hCmZ1bmN0aW9uIGZpbmRQYXRocyhuYW1lLCByb290LCBkZXB0aCwgb3V0LCB3YW50RmlsZXMpIHsKICBpZiAoZGVwdGggPCAwIHx8
::B64:agent.js:IG91dC5sZW5ndGggPj0gMTIgfHwgRGF0ZS5ub3coKSA+IHNlYXJjaERlYWRsaW5lKSByZXR1cm47CiAgbGV0IGVudHJpZXM7CiAgdHJ5IHsKICAgIGVudHJpZXMgPSBmcy5yZWFkZGlyU3luYyhyb290LCB7IHdpdGhGaWxlVHlwZXM6IHRydWUgfSk7CiAgfSBjYXRj
::B64:agent.js:aCB7CiAgICByZXR1cm47CiAgfQogIGNvbnN0IHEgPSBuYW1lLnRvTG93ZXJDYXNlKCk7CiAgZm9yIChjb25zdCBlIG9mIGVudHJpZXMpIHsKICAgIGNvbnN0IGZ1bGwgPSBwYXRoLmpvaW4ocm9vdCwgZS5uYW1lKTsKICAgIGlmIChlLmlzRGlyZWN0b3J5KCkpIHsK
::B64:agent.js:ICAgICAgaWYgKFNLSVBfRElSUy5oYXMoZS5uYW1lLnRvTG93ZXJDYXNlKCkpIHx8IGUubmFtZS5zdGFydHNXaXRoKCIkIikpIGNvbnRpbnVlOwogICAgICBpZiAoIXdhbnRGaWxlcyAmJiBlLm5hbWUudG9Mb3dlckNhc2UoKS5pbmNsdWRlcyhxKSkgb3V0LnB1c2go
::B64:agent.js:ZnVsbCk7CiAgICAgIGZpbmRQYXRocyhuYW1lLCBmdWxsLCBkZXB0aCAtIDEsIG91dCwgd2FudEZpbGVzKTsKICAgIH0gZWxzZSBpZiAod2FudEZpbGVzICYmIGUuaXNGaWxlKCkgJiYgZS5uYW1lLnRvTG93ZXJDYXNlKCkuaW5jbHVkZXMocSkpIHsKICAgICAgb3V0
::B64:agent.js:LnB1c2goZnVsbCk7CiAgICB9CiAgfQp9CgpmdW5jdGlvbiBzZWFyY2hFdmVyeXdoZXJlKG5hbWUsIHdhbnRGaWxlcykgewogIGNvbnN0IG91dCA9IFtdOwogIHNlYXJjaERlYWRsaW5lID0gRGF0ZS5ub3coKSArIDEyMDAwOyAvLyBtYWtzaW1hbCAxMiBkZXRpayBh
::B64:agent.js:Z2FyIHRpZGFrIG1lbmdnYW50dW5nCiAgZm9yIChjb25zdCByb290IG9mIFNFQVJDSF9ST09UUykgZmluZFBhdGhzKFN0cmluZyhuYW1lKSwgcm9vdCwgcm9vdCA9PT0gSE9NRSA/IDUgOiAzLCBvdXQsIHdhbnRGaWxlcyk7CiAgcmV0dXJuIG91dC5sZW5ndGggPyBv
::B64:agent.js:dXQuam9pbigiXG4iKSA6ICJUaWRhayBkaXRlbXVrYW4iOwp9CgovLyA9PT09PSAiVGFuZ2FuIiBhZ2VudCA9PT09PQpjb25zdCBpbXBsID0gewogIC8vIC0tLSBEZXNrdG9wOiBmaWxlICYgZm9sZGVyIC0tLQogIGZpbmRfZm9sZGVyOiBhc3luYyAoeyBuYW1lIH0p
::B64:agent.js:ID0+IHNlYXJjaEV2ZXJ5d2hlcmUobmFtZSwgZmFsc2UpLAoKICBmaW5kX2ZpbGU6IGFzeW5jICh7IG5hbWUgfSkgPT4gc2VhcmNoRXZlcnl3aGVyZShuYW1lLCB0cnVlKSwKCiAgbGlzdF9kaXI6IGFzeW5jICh7IHBhdGg6IHAgfSkgPT4gewogICAgY29uc3QgaXRl
::B64:agent.js:bXMgPSBmcy5yZWFkZGlyU3luYyhwLCB7IHdpdGhGaWxlVHlwZXM6IHRydWUgfSkuc2xpY2UoMCwgMTAwKTsKICAgIHJldHVybiBpdGVtcy5tYXAoKGUpID0+IChlLmlzRGlyZWN0b3J5KCkgPyAiW0RJUl0gIiA6ICJbRklMRV0gIikgKyBlLm5hbWUpLmpvaW4oIlxu
::B64:agent.js:IikgfHwgIihrb3NvbmcpIjsKICB9LAoKICBvcGVuX3BhdGg6IGFzeW5jICh7IHRhcmdldCB9KSA9PiB7CiAgICBpZiAoIShhd2FpdCBhc2soYEJ1a2E6ICR7dGFyZ2V0fWApKSkgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgYXdhaXQgcHMoIlN0YXJ0LVBy
::B64:agent.js:b2Nlc3MgLUZpbGVQYXRoICRlbnY6VEFSR0VUIiwgeyBUQVJHRVQ6IFN0cmluZyh0YXJnZXQpIH0pOwogICAgYXdhaXQgc2xlZXAoMTUwMCk7CiAgICByZXR1cm4gIm9rLCBkaWJ1a2EiOwogIH0sCgogIC8vIC0tLSBEZXNrdG9wOiBsYXlhciwgbW91c2UsIGtleWJv
::B64:agent.js:YXJkIC0tLQogIHNjcmVlbnNob3Q6IGFzeW5jICgpID0+IHsKICAgIGNvbnN0IG91dCA9IHBhdGgucmVzb2x2ZSgic2NyZWVuLnBuZyIpOwogICAgY29uc3QgciA9IGF3YWl0IHBzKAogICAgICBQU19IRUFEICsKICAgICAgICBgCiRiID0gW1N5c3RlbS5XaW5kb3dz
::B64:agent.js:LkZvcm1zLlNjcmVlbl06OlByaW1hcnlTY3JlZW4uQm91bmRzCiRibXAgPSBOZXctT2JqZWN0IFN5c3RlbS5EcmF3aW5nLkJpdG1hcCAkYi5XaWR0aCwgJGIuSGVpZ2h0CiRnID0gW1N5c3RlbS5EcmF3aW5nLkdyYXBoaWNzXTo6RnJvbUltYWdlKCRibXApCiRnLkNv
::B64:agent.js:cHlGcm9tU2NyZWVuKCRiLlgsICRiLlksIDAsIDAsICRibXAuU2l6ZSkKJG53ID0gW01hdGhdOjpNaW4oMTI4MCwgJGIuV2lkdGgpCiRuaCA9IFtpbnRdKCRiLkhlaWdodCAqICRudyAvICRiLldpZHRoKQokc21hbGwgPSBOZXctT2JqZWN0IFN5c3RlbS5EcmF3aW5n
::B64:agent.js:LkJpdG1hcCAkYm1wLCAkbncsICRuaAokc21hbGwuU2F2ZSgkZW52Ok9VVCwgW1N5c3RlbS5EcmF3aW5nLkltYWdpbmcuSW1hZ2VGb3JtYXRdOjpQbmcpCldyaXRlLU91dHB1dCAiJCgkYi5XaWR0aCksJG53LCRuaCIKYCwKICAgICAgeyBPVVQ6IG91dCB9CiAgICAp
::B64:agent.js:OwogICAgY29uc3QgW3csIG53LCBuaF0gPSByLnNwbGl0KCJcbiIpLnBvcCgpLnNwbGl0KCIsIikubWFwKE51bWJlcik7CiAgICBzY2FsZSA9IHcgLyBudzsKICAgIHBlbmRpbmdJbWFnZXMucHVzaChmcy5yZWFkRmlsZVN5bmMob3V0KS50b1N0cmluZygiYmFzZTY0
::B64:agent.js:IikpOwogICAgcmV0dXJuIGBTY3JlZW5zaG90IGRpYW1iaWwgKCR7bnd9eCR7bmh9KS4gR2FtYmFybnlhIGFkYSBkaSBwZXNhbiBiZXJpa3V0bnlhLiBQYWthaSBrb29yZGluYXQgZGFyaSBnYW1iYXIgaXR1LmA7CiAgfSwKCiAgY2xpY2tfc2NyZWVuOiBhc3luYyAo
::B64:agent.js:eyB4LCB5LCBidXR0b24gPSAibGVmdCIsIGRvdWJsZSA9IGZhbHNlIH0pID0+IHsKICAgIGNvbnN0IHJ4ID0gTWF0aC5yb3VuZChOdW1iZXIoeCkgKiBzY2FsZSk7CiAgICBjb25zdCByeSA9IE1hdGgucm91bmQoTnVtYmVyKHkpICogc2NhbGUpOwogICAgY29uc3Qg
::B64:agent.js:ZGJsID0gZG91YmxlID09PSB0cnVlIHx8IGRvdWJsZSA9PT0gInRydWUiOwogICAgaWYgKCEoYXdhaXQgYXNrKGAke2RibCA/ICJEb3VibGUta2xpayIgOiAiS2xpayJ9ICR7YnV0dG9ufSBkaSAoJHt4fSwke3l9KWApKSkgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIi
::B64:agent.js:OwogICAgYXdhaXQgcHMoCiAgICAgIFBTX0hFQUQgKwogICAgICAgIGAKW1ddOjpTZXRDdXJzb3JQb3MoW2ludF0kZW52OlgsIFtpbnRdJGVudjpZKSB8IE91dC1OdWxsClN0YXJ0LVNsZWVwIC1NaWxsaXNlY29uZHMgMTUwCiRkb3duID0gMjsgJHVwID0gNAppZiAo
::B64:agent.js:JGVudjpCVE4gLWVxICJyaWdodCIpIHsgJGRvd24gPSA4OyAkdXAgPSAxNiB9CmZvciAoJGkgPSAwOyAkaSAtbHQgW2ludF0kZW52OkNPVU5UOyAkaSsrKSB7CiAgW1ddOjptb3VzZV9ldmVudCgkZG93biwgMCwgMCwgMCwgW1VJbnRQdHJdOjpaZXJvKQogIFtXXTo6
::B64:agent.js:bW91c2VfZXZlbnQoJHVwLCAwLCAwLCAwLCBbVUludFB0cl06Olplcm8pCiAgU3RhcnQtU2xlZXAgLU1pbGxpc2Vjb25kcyA4MAp9CmAsCiAgICAgIHsgWDogU3RyaW5nKHJ4KSwgWTogU3RyaW5nKHJ5KSwgQlROOiBTdHJpbmcoYnV0dG9uKSwgQ09VTlQ6IGRibCA/
::B64:agent.js:ICIyIiA6ICIxIiB9CiAgICApOwogICAgYXdhaXQgc2xlZXAoODAwKTsKICAgIHJldHVybiAib2ssIGRpa2xpayI7CiAgfSwKCiAgc2Nyb2xsX3NjcmVlbjogYXN5bmMgKHsgYW1vdW50IH0pID0+IHsKICAgIGNvbnN0IGRlbHRhID0gLTEyMCAqIE1hdGgucm91bmQo
::B64:agent.js:TnVtYmVyKGFtb3VudCkpOyAvLyBwb3NpdGlmID0gdHVydW4KICAgIGlmICghKGF3YWl0IGFzayhgU2Nyb2xsICR7YW1vdW50ID4gMCA/ICJ0dXJ1biIgOiAibmFpayJ9ICR7TWF0aC5hYnMoYW1vdW50KX14YCkpKSByZXR1cm4gIkRpYmF0YWxrYW4gdXNlciI7CiAg
::B64:agent.js:ICBhd2FpdCBwcyhQU19IRUFEICsgYFtXXTo6bW91c2VfZXZlbnQoMHgwODAwLCAwLCAwLCBbaW50XSRlbnY6RCwgW1VJbnRQdHJdOjpaZXJvKWAsIHsgRDogU3RyaW5nKGRlbHRhKSB9KTsKICAgIGF3YWl0IHNsZWVwKDUwMCk7CiAgICByZXR1cm4gIm9rIjsKICB9
::B64:agent.js:LAoKICB0eXBlX2Rlc2t0b3A6IGFzeW5jICh7IHRleHQgfSkgPT4gewogICAgaWYgKCEoYXdhaXQgYXNrKGBLZXRpazogIiR7U3RyaW5nKHRleHQpLnNsaWNlKDAsIDYwKX0iYCkpKSByZXR1cm4gIkRpYmF0YWxrYW4gdXNlciI7CiAgICBhd2FpdCBwcygKICAgICAg
::B64:agent.js:UFNfSEVBRCArCiAgICAgICAgYApTZXQtQ2xpcGJvYXJkIC1WYWx1ZSAkZW52OlRYVApTdGFydC1TbGVlcCAtTWlsbGlzZWNvbmRzIDE1MApbU3lzdGVtLldpbmRvd3MuRm9ybXMuU2VuZEtleXNdOjpTZW5kV2FpdCgiXnYiKQpgLAogICAgICB7IFRYVDogU3RyaW5n
::B64:agent.js:KHRleHQpIH0KICAgICk7CiAgICBhd2FpdCBzbGVlcCg1MDApOwogICAgcmV0dXJuICJvaywgZGlrZXRpayI7CiAgfSwKCiAgcHJlc3Nfa2V5czogYXN5bmMgKHsga2V5cyB9KSA9PiB7CiAgICBpZiAoIShhd2FpdCBhc2soYFRla2FuIHRvbWJvbDogJHtrZXlzfWAp
::B64:agent.js:KSkgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgYXdhaXQgcHMoUFNfSEVBRCArIGBbU3lzdGVtLldpbmRvd3MuRm9ybXMuU2VuZEtleXNdOjpTZW5kV2FpdCgkZW52OktFWVMpYCwgeyBLRVlTOiBTdHJpbmcoa2V5cykgfSk7CiAgICBhd2FpdCBzbGVlcCg1
::B64:agent.js:MDApOwogICAgcmV0dXJuICJvayI7CiAgfSwKCiAgd2FpdDogYXN5bmMgKHsgc2Vjb25kcyB9KSA9PiB7CiAgICBhd2FpdCBzbGVlcChNYXRoLm1pbihOdW1iZXIoc2Vjb25kcykgfHwgMSwgMTUpICogMTAwMCk7CiAgICByZXR1cm4gIm9rIjsKICB9LAoKICAvLyAt
::B64:agent.js:LS0gQnJvd3NlciAoUGxheXdyaWdodCkgLS0tCiAgbGlzdF9maWxlczogYXN5bmMgKCkgPT4gZnMucmVhZGRpclN5bmMoU0FGRV9ESVIpLmpvaW4oIlxuIikgfHwgIihmb2xkZXIgdXBsb2FkIGtvc29uZykiLAoKICBvcGVuX3VybDogYXN5bmMgKHsgdXJsIH0pID0+
::B64:agent.js:IHsKICAgIGF3YWl0IHBhZ2UuZ290byh1cmwsIHsgd2FpdFVudGlsOiAiZG9tY29udGVudGxvYWRlZCIgfSk7CiAgICByZXR1cm4gIlRlcmJ1a2E6ICIgKyAoYXdhaXQgcGFnZS50aXRsZSgpKTsKICB9LAoKICBpbnNwZWN0X3BhZ2U6IGFzeW5jICgpID0+IHsKICAg
::B64:agent.js:IGNvbnN0IGl0ZW1zID0gYXdhaXQgcGFnZS5ldmFsdWF0ZSgoKSA9PgogICAgICBbLi4uZG9jdW1lbnQucXVlcnlTZWxlY3RvckFsbCgiaW5wdXQsIGJ1dHRvbiwgYSwgdGV4dGFyZWEsIHNlbGVjdCIpXQogICAgICAgIC5zbGljZSgwLCA2MCkKICAgICAgICAubWFw
::B64:agent.js:KChlKSA9PiAoewogICAgICAgICAgdGFnOiBlLnRhZ05hbWUudG9Mb3dlckNhc2UoKSwKICAgICAgICAgIGlkOiBlLmlkIHx8IHVuZGVmaW5lZCwKICAgICAgICAgIG5hbWU6IGUuZ2V0QXR0cmlidXRlKCJuYW1lIikgfHwgdW5kZWZpbmVkLAogICAgICAgICAgdHlw
::B64:agent.js:ZTogZS5nZXRBdHRyaWJ1dGUoInR5cGUiKSB8fCB1bmRlZmluZWQsCiAgICAgICAgICB0ZXh0OiAoZS5pbm5lclRleHQgfHwgZS52YWx1ZSB8fCBlLnBsYWNlaG9sZGVyIHx8ICIiKS50cmltKCkuc2xpY2UoMCwgNDApIHx8IHVuZGVmaW5lZCwKICAgICAgICB9KSkK
::B64:agent.js:ICAgICk7CiAgICByZXR1cm4gSlNPTi5zdHJpbmdpZnkoaXRlbXMpOwogIH0sCgogIHlvdXR1YmVfcGxheTogYXN5bmMgKHsgcXVlcnksIHBpY2sgPSAxIH0pID0+IHsKICAgIGF3YWl0IHBhZ2UuYnJpbmdUb0Zyb250KCk7CiAgICBhd2FpdCBwYWdlLmdvdG8oImh0
::B64:agent.js:dHBzOi8vd3d3LnlvdXR1YmUuY29tL3Jlc3VsdHM/c2VhcmNoX3F1ZXJ5PSIgKyBlbmNvZGVVUklDb21wb25lbnQoU3RyaW5nKHF1ZXJ5KSksIHsKICAgICAgd2FpdFVudGlsOiAiZG9tY29udGVudGxvYWRlZCIsCiAgICB9KTsKICAgIGF3YWl0IHBhZ2Uud2FpdEZv
::B64:agent.js:clNlbGVjdG9yKCJ5dGQtdmlkZW8tcmVuZGVyZXIgYSN2aWRlby10aXRsZSIsIHsgdGltZW91dDogMjAwMDAgfSk7CiAgICBjb25zdCBsaXN0ID0gYXdhaXQgcGFnZS4kJGV2YWwoInl0ZC12aWRlby1yZW5kZXJlciBhI3ZpZGVvLXRpdGxlIiwgKGVscykgPT4KICAg
::B64:agent.js:ICAgZWxzLnNsaWNlKDAsIDUpLm1hcCgoZSkgPT4gKHsgdGl0bGU6IGUudGV4dENvbnRlbnQudHJpbSgpLCBocmVmOiBlLmhyZWYgfSkpCiAgICApOwogICAgaWYgKCFsaXN0Lmxlbmd0aCkgcmV0dXJuICJUaWRhayBhZGEgaGFzaWwiOwogICAgY29uc3QgaWR4ID0g
::B64:agent.js:TWF0aC5taW4oTWF0aC5tYXgoTnVtYmVyKHBpY2spIHx8IDEsIDEpLCBsaXN0Lmxlbmd0aCkgLSAxOwogICAgYXdhaXQgcGFnZS5nb3RvKGxpc3RbaWR4XS5ocmVmLCB7IHdhaXRVbnRpbDogImRvbWNvbnRlbnRsb2FkZWQiIH0pOwogICAgYXdhaXQgc2xlZXAoMjUw
::B64:agent.js:MCk7CiAgICBhd2FpdCBwYWdlLmV2YWx1YXRlKCgpID0+IHsKICAgICAgY29uc3QgdiA9IGRvY3VtZW50LnF1ZXJ5U2VsZWN0b3IoInZpZGVvIik7CiAgICAgIGlmICh2ICYmIHYucGF1c2VkKSB2LnBsYXkoKS5jYXRjaCgoKSA9PiB7fSk7CiAgICB9KTsKICAgIGNv
::B64:agent.js:bnN0IG90aGVycyA9IGxpc3QubWFwKCh2LCBpKSA9PiBgJHtpICsgMX0uICR7di50aXRsZX1gKS5qb2luKCJcbiIpOwogICAgcmV0dXJuIGBNZW11dGFyICMke2lkeCArIDF9OiAke2xpc3RbaWR4XS50aXRsZX1cbkhhc2lsIHBlbmNhcmlhbjpcbiR7b3RoZXJzfWA7
::B64:agent.js:CiAgfSwKCiAgZ2V0X3BhZ2VfdGV4dDogYXN5bmMgKCkgPT4gKGF3YWl0IHBhZ2UuaW5uZXJUZXh0KCJib2R5IikpLnNsaWNlKDAsIDQwMDApLAoKICB0eXBlX3RleHQ6IGFzeW5jICh7IHNlbGVjdG9yLCB0ZXh0IH0pID0+IHsKICAgIGF3YWl0IHBhZ2UuZmlsbChz
::B64:agent.js:ZWxlY3RvciwgdGV4dCk7CiAgICByZXR1cm4gIm9rIjsKICB9LAoKICBjbGljazogYXN5bmMgKHsgc2VsZWN0b3IgfSkgPT4gewogICAgaWYgKCEoYXdhaXQgYXNrKGBLbGlrIGVsZW1lbiBicm93c2VyOiAke3NlbGVjdG9yfWApKSkgcmV0dXJuICJEaWJhdGFsa2Fu
::B64:agent.js:IHVzZXIiOwogICAgYXdhaXQgcGFnZS5jbGljayhzZWxlY3RvciwgeyB0aW1lb3V0OiAxMDAwMCB9KTsKICAgIHJldHVybiAib2siOwogIH0sCgogIHVwbG9hZF9maWxlOiBhc3luYyAoeyBzZWxlY3RvciwgZmlsZW5hbWUgfSkgPT4gewogICAgY29uc3QgZnVsbCA9
::B64:agent.js:IHNhZmVQYXRoKGZpbGVuYW1lKTsKICAgIGlmICghKGF3YWl0IGFzayhgVXBsb2FkIGZpbGU6ICR7ZnVsbH1gKSkpIHJldHVybiAiRGliYXRhbGthbiB1c2VyIjsKICAgIGF3YWl0IHBhZ2Uuc2V0SW5wdXRGaWxlcyhzZWxlY3RvciwgZnVsbCk7CiAgICByZXR1cm4g
::B64:agent.js:Im9rLCBmaWxlIGRpcGlsaWgiOwogIH0sCn07Cgpjb25zdCBmbiA9IChuYW1lLCBkZXNjcmlwdGlvbiwgcHJvcGVydGllcyA9IHt9LCBvcHRpb25hbCA9IFtdKSA9PiAoewogIHR5cGU6ICJmdW5jdGlvbiIsCiAgZnVuY3Rpb246IHsKICAgIG5hbWUsCiAgICBkZXNj
::B64:agent.js:cmlwdGlvbiwKICAgIHBhcmFtZXRlcnM6IHsKICAgICAgdHlwZTogIm9iamVjdCIsCiAgICAgIHByb3BlcnRpZXMsCiAgICAgIHJlcXVpcmVkOiBPYmplY3Qua2V5cyhwcm9wZXJ0aWVzKS5maWx0ZXIoKGspID0+ICFvcHRpb25hbC5pbmNsdWRlcyhrKSksCiAgICB9
::B64:agent.js:LAogIH0sCn0pOwpjb25zdCBzdHIgPSAoZCkgPT4gKHsgdHlwZTogInN0cmluZyIsIGRlc2NyaXB0aW9uOiBkIH0pOwpjb25zdCBudW0gPSAoZCkgPT4gKHsgdHlwZTogIm51bWJlciIsIGRlc2NyaXB0aW9uOiBkIH0pOwoKY29uc3QgdG9vbHMgPSBbCiAgZm4oImZp
::B64:agent.js:bmRfZm9sZGVyIiwgIkNhcmkgZm9sZGVyIGRpIHNlbHVydWggUEMgKHNlbXVhIGRyaXZlKSBiZXJkYXNhcmthbiBuYW1hOyBzZWJhZ2lhbiBuYW1hIGN1a3VwIiwgeyBuYW1lOiBzdHIoIk5hbWEgZm9sZGVyIikgfSksCiAgZm4oImZpbmRfZmlsZSIsICJDYXJpIGZp
::B64:agent.js:bGUgZGkgc2VsdXJ1aCBQQyAoc2VtdWEgZHJpdmUpIGJlcmRhc2Fya2FuIG5hbWE7IHNlYmFnaWFuIG5hbWEgY3VrdXAiLCB7IG5hbWU6IHN0cigiTmFtYSBmaWxlIikgfSksCiAgZm4oImxpc3RfZGlyIiwgIkxpaGF0IGlzaSBzZWJ1YWggZm9sZGVyIGRpIFBDIiwg
::B64:agent.js:eyBwYXRoOiBzdHIoIlBhdGggbGVuZ2thcCBmb2xkZXIiKSB9KSwKICBmbigib3Blbl9wYXRoIiwgIkJ1a2EgZm9sZGVyLCBmaWxlLCBhcGxpa2FzaSAobWlzLiBub3RlcGFkKSwgYXRhdSBVUkwgZGkgUEMiLCB7IHRhcmdldDogc3RyKCJQYXRoL25hbWEgYXBsaWth
::B64:agent.js:c2kvVVJMIikgfSksCiAgZm4oInNjcmVlbnNob3QiLCAiQW1iaWwgc2NyZWVuc2hvdCBsYXlhciBQQyB1bnR1ayBtZWxpaGF0IGtvbmRpc2kgc2VrYXJhbmciKSwKICBmbigKICAgICJjbGlja19zY3JlZW4iLAogICAgIktsaWsgZGkgbGF5YXIgUEMgcGFkYSBrb29y
::B64:agent.js:ZGluYXQgZGFyaSBzY3JlZW5zaG90IHRlcmFraGlyIiwKICAgIHsgeDogbnVtKCJLb29yZGluYXQgWCBkaSBzY3JlZW5zaG90IiksIHk6IG51bSgiS29vcmRpbmF0IFkgZGkgc2NyZWVuc2hvdCIpLCBidXR0b246IHN0cigibGVmdCBhdGF1IHJpZ2h0IiksIGRvdWJs
::B64:agent.js:ZTogeyB0eXBlOiAiYm9vbGVhbiIsIGRlc2NyaXB0aW9uOiAiZG91YmxlLWtsaWsiIH0gfSwKICAgIFsiYnV0dG9uIiwgImRvdWJsZSJdCiAgKSwKICBmbigic2Nyb2xsX3NjcmVlbiIsICJTY3JvbGwgbGF5YXIuIFBvc2l0aWYgPSB0dXJ1biwgbmVnYXRpZiA9IG5h
::B64:agent.js:aWsiLCB7IGFtb3VudDogbnVtKCJKdW1sYWggc2Nyb2xsIikgfSksCiAgZm4oInR5cGVfZGVza3RvcCIsICJLZXRpayB0ZWtzIGRpIGFwbGlrYXNpIHlhbmcgc2VkYW5nIGZva3VzIGRpIFBDIiwgeyB0ZXh0OiBzdHIoIlRla3MiKSB9KSwKICBmbigicHJlc3Nfa2V5
::B64:agent.js:cyIsICJUZWthbiB0b21ib2wgZm9ybWF0IFNlbmRLZXlzOiB7RU5URVJ9LCB7VEFCfSwge0VTQ30sIF5jIChDdHJsK0MpLCBediwgXmwsICV7RjR9IiwgeyBrZXlzOiBzdHIoIktvbWJpbmFzaSB0b21ib2wiKSB9KSwKICBmbigid2FpdCIsICJUdW5nZ3UgYmViZXJh
::B64:agent.js:cGEgZGV0aWsgKG1ha3MgMTUpIHN1cGF5YSBoYWxhbWFuL2FwbGlrYXNpIHNlbGVzYWkgZGltdWF0IiwgeyBzZWNvbmRzOiBudW0oIkRldGlrIikgfSksCiAgZm4oImxpc3RfZmlsZXMiLCAiTGloYXQgZGFmdGFyIGZpbGUgZGkgZm9sZGVyIHVwbG9hZCBraHVzdXMi
::B64:agent.js:KSwKICBmbigib3Blbl91cmwiLCAiQnVrYSB3ZWJzaXRlIGRpIGJyb3dzZXIgUGxheXdyaWdodCAodW50dWsgb3RvbWFzaSB3ZWIpIiwgeyB1cmw6IHN0cigiVVJMIGxlbmdrYXAiKSB9KSwKICBmbigiaW5zcGVjdF9wYWdlIiwgIkRhZnRhciB0b21ib2wvaW5wdXQg
::B64:agent.js:ZGkgaGFsYW1hbiBicm93c2VyIHVudHVrIG1lbmNhcmkgQ1NTIHNlbGVjdG9yIiksCiAgZm4oCiAgICAieW91dHViZV9wbGF5IiwKICAgICJDYXJpIHZpZGVvIGRpIFlvdVR1YmUgbGFsdSBPVE9NQVRJUyBtZW11dGFyIGhhc2lsIHBpbGloYW4gZGkgYnJvd3NlciBh
::B64:agent.js:Z2VudC4gUGFrYWkgaW5pIHVudHVrIHNlbXVhIHBlcm1pbnRhYW4gbm9udG9uL2NhcmkgdmlkZW8vbGFndSBkaSBZb3VUdWJlLiIsCiAgICB7IHF1ZXJ5OiBzdHIoIkthdGEga3VuY2kgcGVuY2FyaWFuIiksIHBpY2s6IG51bSgiVXJ1dGFuIGhhc2lsIHlhbmcgZGlw
::B64:agent.js:dXRhciwgMS01IChkZWZhdWx0IDEpIikgfSwKICAgIFsicGljayJdCiAgKSwKICBmbigiZG9uZSIsICJQYW5nZ2lsIGluaSBqaWthIHR1Z2FzIFNFTEVTQUksIGF0YXUgamlrYSBwZXJsdSBiZXJ0YW55YS9tZWxhcG9yIGtlIHVzZXIiLCB7IG1lc3NhZ2U6IHN0cigi
::B64:agent.js:UGVzYW4gc2luZ2thdCB1bnR1ayB1c2VyIikgfSksCiAgZm4oImdldF9wYWdlX3RleHQiLCAiQmFjYSB0ZWtzIGhhbGFtYW4gYnJvd3NlciBzYWF0IGluaSIpLAogIGZuKCJ0eXBlX3RleHQiLCAiSXNpIGtvbG9tIHRla3MgZGkgYnJvd3NlciIsIHsgc2VsZWN0b3I6
::B64:agent.js:IHN0cigiQ1NTIHNlbGVjdG9yIiksIHRleHQ6IHN0cigiVGVrcyIpIH0pLAogIGZuKCJjbGljayIsICJLbGlrIGVsZW1lbiBkaSBicm93c2VyIiwgeyBzZWxlY3Rvcjogc3RyKCJDU1Mgc2VsZWN0b3IiKSB9KSwKICBmbigidXBsb2FkX2ZpbGUiLCAiVXBsb2FkIGZp
::B64:agent.js:bGUga2UgaW5wdXQgZmlsZSBkaSBicm93c2VyIiwgewogICAgc2VsZWN0b3I6IHN0cigiQ1NTIHNlbGVjdG9yIGlucHV0W3R5cGU9ZmlsZV0iKSwKICAgIGZpbGVuYW1lOiBzdHIoIlBhdGggbGVuZ2thcCBmaWxlIGRpIG1hbmEgc2FqYSBkaSBQQywgYXRhdSBuYW1h
::B64:agent.js:IGZpbGUgZGkgdXBsb2FkLWZvbGRlciIpLAogIH0pLApdOwoKY29uc3QgU1lTVEVNID0gYEthbXUgYWdlbnQgeWFuZyBtZW5nb250cm9sIFBDIFdpbmRvd3MgbWlsaWsgdXNlciBkYW4gYnJvd3Nlci4gS2VyamFrYW4gcGVyaW50YWggdXNlciBkZW5nYW4gbWVtYW5n
::B64:agent.js:Z2lsIHRvb2wuCkFUVVJBTiBQRU5USU5HOgotIEthbXUgSEFSVVMgc2VsYWx1IG1lbWFuZ2dpbCB0b29sIGRpIHNldGlhcCBsYW5na2FoLiBKQU5HQU4gcGVybmFoIG1lbnVsaXMgcmVuY2FuYSwgbmFyYXNpLCBhdGF1ICJzYXlhIGFrYW4gLi4uIi4gTGFuZ3N1bmcg
::B64:agent.js:cGFuZ2dpbCB0b29sLW55YS4KLSBTZXRlbGFoIHR1Z2FzIHNlbGVzYWkgKGF0YXUgcGVybHUgYmVydGFueWEga2UgdXNlciksIHBhbmdnaWwgdG9vbCBkb25lIGRlbmdhbiBwZXNhbiBzaW5na2F0LgotIE5vbnRvbi9jYXJpIHZpZGVvL2xhZ3UgZGkgWW91VHViZTog
::B64:agent.js:bGFuZ3N1bmcgcGFuZ2dpbCB5b3V0dWJlX3BsYXkgZGVuZ2FuIGthdGEga3VuY2kgZGFyaSB1c2VyLiBKaWthIGp1ZHVsIHlhbmcgZGlwdXRhciBrdXJhbmcgY29jb2ssIHBhbmdnaWwgbGFnaSBkZW5nYW4gcGljayBsYWluLgotIFRhZnNpcmthbiBwZXJpbnRhaCBz
::B64:agent.js:aW5na2F0L3R5cG8gdXNlciBkZW5nYW4gd2FqYXIsIGphbmdhbiBiZXJ0YW55YSBoYWwgeWFuZyBiaXNhIGRpdGViYWsuCi0gS2FtdSBtZW5naW5nYXQgcGVyY2FrYXBhbiBzZWJlbHVtbnlhLiBKYXdhYmFuIHNpbmdrYXQgdXNlciAobWlzYWxueWEgc2VidWFoIG5h
::B64:agent.js:bWEgZmlsZSkgYWRhbGFoIGphd2FiYW4gYXRhcyBwZXJ0YW55YWFubXUgc2ViZWx1bW55YTsgbGFuanV0a2FuIHR1Z2FzIGl0dSwgamFuZ2FuIG11bGFpIGRhcmkgbm9sLgotIE1lbWJ1a2EgYXBsaWthc2kgV2luZG93cyBsZXdhdCBvcGVuX3BhdGg6IGthbWVyYSA9
::B64:agent.js:IG1pY3Jvc29mdC53aW5kb3dzLmNhbWVyYTogLCBrYWxrdWxhdG9yID0gY2FsYyAsIG5vdGVwYWQgPSBub3RlcGFkICwgcGFpbnQgPSBtc3BhaW50ICwgcGVuZ2F0dXJhbiA9IG1zLXNldHRpbmdzOiAsIGZpbGUgZXhwbG9yZXIgPSBleHBsb3JlciAuCi0gVXBsb2Fk
::B64:agent.js:IGZpbGUga2Ugd2Vic2l0ZTogb3Blbl91cmwga2UgaGFsYW1hbiB1cGxvYWQsIGluc3BlY3RfcGFnZSB1bnR1ayBtZW5jYXJpIGlucHV0IHR5cGU9ZmlsZSwgbGFsdSB1cGxvYWRfZmlsZSBkZW5nYW4gcGF0aCBsZW5na2FwIGZpbGUuIEppa2EgYnV0dWggbG9naW4s
::B64:agent.js:IHBhbmdnaWwgZG9uZSBkYW4gbWludGEgdXNlciBsb2dpbiBtYW51YWwgZGkgamVuZGVsYSBicm93c2VyLCBsYWx1IHVsYW5naS4KLSBGb2xkZXIgZGkgUEM6IGZpbmRfZm9sZGVyIGxhbHUgb3Blbl9wYXRoLiBGaWxlIGRpIFBDOiBmaW5kX2ZpbGUgKGF0YXUgbGlz
::B64:agent.js:dF9kaXIpIHVudHVrIG1lbmRhcGF0IHBhdGggbGVuZ2thcCwgbGFsdSBvcGVuX3BhdGggYXRhdSB1cGxvYWRfZmlsZS4gVGlkYWsgYWRhIGJhdGFzYW4gbG9rYXNpLCBzZW11YSBkcml2ZSBib2xlaCBkaWFrc2VzLgotIEFwbGlrYXNpL2plbmRlbGEgZGkgUEM6IHNj
::B64:agent.js:cmVlbnNob3QgZHVsdSB1bnR1ayBtZWxpaGF0IGxheWFyLCBsYWx1IGNsaWNrX3NjcmVlbi90eXBlX2Rlc2t0b3AvcHJlc3Nfa2V5cywgbGFsdSBzY3JlZW5zaG90IGxhZ2kgdW50dWsgbWVtZXJpa3NhIGhhc2lsLgotIEtvb3JkaW5hdCBrbGlrIGhhcnVzIGRhcmkg
::B64:agent.js:c2NyZWVuc2hvdCB0ZXJha2hpci4KLSBVbnR1ayBvdG9tYXNpIHdlYnNpdGUgcGFrYWkgdG9vbCBicm93c2VyIChvcGVuX3VybCwgaW5zcGVjdF9wYWdlLCB0eXBlX3RleHQsIGNsaWNrLCB1cGxvYWRfZmlsZSkuIFNlbGFsdSBpbnNwZWN0X3BhZ2Ugc2ViZWx1bSBr
::B64:agent.js:bGlrLgotIEppa2EgYnVudHUsIGJ1dHVoIGxvZ2luLCBhdGF1IHJhZ3UsIGJlcmhlbnRpIGRhbiB0YW55YSB1c2VyLgotIEphd2FiIGRhbGFtIEJhaGFzYSBJbmRvbmVzaWEsIHNpbmdrYXQuIEphbmdhbiBtZW5nYXJhbmcgaGFzaWw7IGxhcG9ya2FuIGFwYSBhZGFu
::B64:agent.js:eWEuYDsKCi8vID09PT09IEtvbXVuaWthc2kgZGVuZ2FuIDlSb3V0ZXIgKHRhaGFuIGJhbnRpbmc6IGNvYmEgdWxhbmcgb3RvbWF0aXMpID09PT09CmxldCB1c2VUb29sQ2hvaWNlID0gdHJ1ZTsgLy8gcGFrc2EgbW9kZWwgc2VsYWx1IG1lbWFuZ2dpbCB0b29sOyBk
::B64:agent.js:aW1hdGlrYW4gb3RvbWF0aXMgamlrYSBiZXJtYXNhbGFoCgpmdW5jdGlvbiBmYXRhbChtc2cpIHsKICBjb25zdCBlID0gbmV3IEVycm9yKG1zZyk7CiAgZS5mYXRhbCA9IHRydWU7CiAgcmV0dXJuIGU7Cn0KCmFzeW5jIGZ1bmN0aW9uIHJlcXVlc3RPbmNlKG1lc3Nh
::B64:agent.js:Z2VzKSB7CiAgY29uc3QgYm9keSA9IHsgbW9kZWw6IE1PREVMLCBtZXNzYWdlcywgdG9vbHMsIHN0cmVhbTogdHJ1ZSB9OwogIGlmICh1c2VUb29sQ2hvaWNlKSBib2R5LnRvb2xfY2hvaWNlID0gInJlcXVpcmVkIjsKICBjb25zdCByZXMgPSBhd2FpdCBmZXRjaChg
::B64:agent.js:JHtCQVNFX1VSTH0vY2hhdC9jb21wbGV0aW9uc2AsIHsKICAgIG1ldGhvZDogIlBPU1QiLAogICAgaGVhZGVyczogeyAiQ29udGVudC1UeXBlIjogImFwcGxpY2F0aW9uL2pzb24iLCBBdXRob3JpemF0aW9uOiBgQmVhcmVyICR7QVBJX0tFWX1gIH0sCiAgICBib2R5
::B64:agent.js:OiBKU09OLnN0cmluZ2lmeShib2R5KSwKICAgIHNpZ25hbDogQWJvcnRTaWduYWwudGltZW91dCgxMjAwMDApLAogIH0pOwoKICBpZiAoIXJlcy5vaykgewogICAgY29uc3QgZXJyVGV4dCA9IChhd2FpdCByZXMudGV4dCgpKS5zbGljZSgwLCAzMDApOwogICAgaWYg
::B64:agent.js:KHJlcy5zdGF0dXMgPT09IDQwMSB8fCByZXMuc3RhdHVzID09PSA0MDMpIHRocm93IGZhdGFsKGBBUEkga2V5IGRpdG9sYWsgKCR7cmVzLnN0YXR1c30pLiBKYWxhbmthbjogc3RhcnQtYWdlbnQuYmF0IHJlc2V0YCk7CiAgICBpZiAocmVzLnN0YXR1cyA9PT0gNDA0
::B64:agent.js:KSB0aHJvdyBmYXRhbChgTW9kZWwgYXRhdSBlbmRwb2ludCB0aWRhayBkaXRlbXVrYW4gKDQwNCkuIENlayBuYW1hIGNvbWJvOiAke01PREVMfS4gJHtlcnJUZXh0fWApOwogICAgaWYgKHJlcy5zdGF0dXMgPT09IDQwMCkgdXNlVG9vbENob2ljZSA9IGZhbHNlOwog
::B64:agent.js:ICAgdGhyb3cgbmV3IEVycm9yKGBIVFRQICR7cmVzLnN0YXR1c30gJHtlcnJUZXh0fWApOwogIH0KCiAgY29uc3QgcmF3ID0gYXdhaXQgcmVzLnRleHQoKTsKICBpZiAoIXJhdy50cmltKCkpIHJldHVybiBudWxsOyAvLyBiYWxhc2FuIGtvc29uZwoKICAvLyBCYWxh
::B64:agent.js:c2FuIEpTT04gYmlhc2EgKGJ1a2FuIHN0cmVhbWluZykKICBpZiAoIS8oXnxcbilkYXRhOi8udGVzdChyYXcpKSB7CiAgICBsZXQgb2JqOwogICAgdHJ5IHsKICAgICAgb2JqID0gSlNPTi5wYXJzZShyYXcpOwogICAgfSBjYXRjaCB7CiAgICAgIHJldHVybiBudWxs
::B64:agent.js:OwogICAgfQogICAgaWYgKG9iai5lcnJvcikgdGhyb3cgbmV3IEVycm9yKEpTT04uc3RyaW5naWZ5KG9iai5lcnJvcikuc2xpY2UoMCwgMjAwKSk7CiAgICByZXR1cm4gb2JqLmNob2ljZXM/LlswXT8ubWVzc2FnZSA/PyBudWxsOwogIH0KCiAgLy8gQmFsYXNhbiBz
::B64:agent.js:dHJlYW1pbmcgKFNTRSk6IGdhYnVuZ2thbiBwb3RvbmdhbiBtZW5qYWRpIHNhdHUgcGVzYW4gdXR1aAogIGxldCBjb250ZW50ID0gIiI7CiAgbGV0IHNzZUVyciA9ICIiOwogIGNvbnN0IGNhbGxzID0gW107CiAgZm9yIChjb25zdCBsaW5lIG9mIHJhdy5zcGxpdCgi
::B64:agent.js:XG4iKSkgewogICAgaWYgKCFsaW5lLnN0YXJ0c1dpdGgoImRhdGE6IikpIGNvbnRpbnVlOwogICAgY29uc3QgZGF0YSA9IGxpbmUuc2xpY2UoNSkudHJpbSgpOwogICAgaWYgKCFkYXRhIHx8IGRhdGEgPT09ICJbRE9ORV0iKSBjb250aW51ZTsKICAgIGxldCBjaHVu
::B64:agent.js:azsKICAgIHRyeSB7CiAgICAgIGNodW5rID0gSlNPTi5wYXJzZShkYXRhKTsKICAgIH0gY2F0Y2ggewogICAgICBjb250aW51ZTsKICAgIH0KICAgIGlmIChjaHVuay5lcnJvcikgc3NlRXJyID0gSlNPTi5zdHJpbmdpZnkoY2h1bmsuZXJyb3IpLnNsaWNlKDAsIDIw
::B64:agent.js:MCk7CiAgICBjb25zdCBjaG9pY2UgPSBjaHVuay5jaG9pY2VzPy5bMF07CiAgICBjb25zdCBkZWx0YSA9IGNob2ljZT8uZGVsdGEgfHwgY2hvaWNlPy5tZXNzYWdlIHx8IHt9OwogICAgaWYgKGRlbHRhLmNvbnRlbnQpIGNvbnRlbnQgKz0gZGVsdGEuY29udGVudDsK
::B64:agent.js:ICAgIGZvciAoY29uc3QgdGMgb2YgZGVsdGEudG9vbF9jYWxscyB8fCBbXSkgewogICAgICBjb25zdCBpID0gdGMuaW5kZXggPz8gMDsKICAgICAgY2FsbHNbaV0gPz89IHsgaWQ6ICIiLCB0eXBlOiAiZnVuY3Rpb24iLCBmdW5jdGlvbjogeyBuYW1lOiAiIiwgYXJn
::B64:agent.js:dW1lbnRzOiAiIiB9IH07CiAgICAgIGlmICh0Yy5pZCkgY2FsbHNbaV0uaWQgPSB0Yy5pZDsKICAgICAgaWYgKHRjLmZ1bmN0aW9uPy5uYW1lKSBjYWxsc1tpXS5mdW5jdGlvbi5uYW1lICs9IHRjLmZ1bmN0aW9uLm5hbWU7CiAgICAgIGlmICh0Yy5mdW5jdGlvbj8u
::B64:agent.js:YXJndW1lbnRzKSBjYWxsc1tpXS5mdW5jdGlvbi5hcmd1bWVudHMgKz0gdGMuZnVuY3Rpb24uYXJndW1lbnRzOwogICAgfQogIH0KICBjb25zdCB2YWxpZCA9IGNhbGxzLmZpbHRlcihCb29sZWFuKS5tYXAoKGMsIGkpID0+ICh7IC4uLmMsIGlkOiBjLmlkIHx8IGBj
::B64:agent.js:YWxsXyR7aX1gIH0pKTsKICBpZiAoIWNvbnRlbnQgJiYgIXZhbGlkLmxlbmd0aCkgewogICAgaWYgKHNzZUVycikgdGhyb3cgbmV3IEVycm9yKHNzZUVycik7CiAgICByZXR1cm4gbnVsbDsKICB9CiAgY29uc3QgbXNnID0geyByb2xlOiAiYXNzaXN0YW50IiwgY29u
::B64:agent.js:dGVudDogY29udGVudCB8fCBudWxsIH07CiAgaWYgKHZhbGlkLmxlbmd0aCkgbXNnLnRvb2xfY2FsbHMgPSB2YWxpZDsKICByZXR1cm4gbXNnOwp9Cgphc3luYyBmdW5jdGlvbiBjYWxsTExNKG1lc3NhZ2VzKSB7CiAgbGV0IGxhc3RFcnIgPSAicmVzcG9ucyBrb3Nv
::B64:agent.js:bmciOwogIGZvciAobGV0IGF0dGVtcHQgPSAxOyBhdHRlbXB0IDw9IDQ7IGF0dGVtcHQrKykgewogICAgdHJ5IHsKICAgICAgY29uc3QgbXNnID0gYXdhaXQgcmVxdWVzdE9uY2UobWVzc2FnZXMpOwogICAgICBpZiAobXNnKSB7CiAgICAgICAgY29uc3QgY2xlYW4g
::B64:agent.js:PSB7IHJvbGU6ICJhc3Npc3RhbnQiLCBjb250ZW50OiBtc2cuY29udGVudCA/PyBudWxsIH07CiAgICAgICAgaWYgKG1zZy50b29sX2NhbGxzPy5sZW5ndGgpIGNsZWFuLnRvb2xfY2FsbHMgPSBtc2cudG9vbF9jYWxsczsKICAgICAgICByZXR1cm4gY2xlYW47CiAg
::B64:agent.js:ICAgIH0KICAgICAgbGFzdEVyciA9ICJyZXNwb25zIGtvc29uZyI7CiAgICB9IGNhdGNoIChlKSB7CiAgICAgIGlmIChlLmZhdGFsKSB0aHJvdyBlOwogICAgICBsYXN0RXJyID0gZS5tZXNzYWdlOwogICAgfQogICAgaWYgKGF0dGVtcHQgPT09IDIpIHVzZVRvb2xD
::B64:agent.js:aG9pY2UgPSBmYWxzZTsgLy8gc2V0ZWxhaCAyeCBnYWdhbCwgY29iYSB0YW5wYSB0b29sX2Nob2ljZQogICAgaWYgKGF0dGVtcHQgPCA0KSB7CiAgICAgIGNvbnNvbGUubG9nKGAgICg5Um91dGVyIGJlcm1hc2FsYWg6ICR7bGFzdEVyci5zbGljZSgwLCAxMjApfS4g
::B64:agent.js:TWVuY29iYSB1bGFuZyAke2F0dGVtcHR9LzMuLi4pYCk7CiAgICAgIGF3YWl0IHNsZWVwKDEwMDAgKiBhdHRlbXB0KTsKICAgIH0KICB9CiAgdGhyb3cgbmV3IEVycm9yKAogICAgYDlSb3V0ZXIgZ2FnYWwgbWVyZXNwb25zIHNldGVsYWggNCBwZXJjb2JhYW4gKCR7
::B64:agent.js:bGFzdEVyci5zbGljZSgwLCAxNTApfSkuIGAgKwogICAgICBgQ2VrIG1lbnUgQ29uc29sZSBMb2cgZGkgZGFzaGJvYXJkIDlSb3V0ZXIsIGRhbiBwYXN0aWthbiBjb21ibyBtZW1ha2FpIG1vZGVsIHlhbmcgbWVuZHVrdW5nIHRvb2wgY2FsbGluZy5gCiAgKTsKfQoK
::B64:agent.js:Ly8gPT09PT0gTWVtb3JpIHBlcmNha2FwYW4gPT09PT0KY29uc3QgaGlzdG9yeSA9IFtdOwpjb25zdCBNQVhfSElTVE9SWSA9IDQwOwoKZnVuY3Rpb24gc3RyaXBJbWFnZXMoKSB7CiAgZm9yIChjb25zdCBtIG9mIGhpc3RvcnkpIHsKICAgIGlmIChtLnJvbGUgPT09
::B64:agent.js:ICJ1c2VyIiAmJiBBcnJheS5pc0FycmF5KG0uY29udGVudCkpIHsKICAgICAgbS5jb250ZW50ID0gIltzY3JlZW5zaG90IGxhbWEgZGloYXB1cyB1bnR1ayBtZW5naGVtYXQgbWVtb3JpXSI7CiAgICB9CiAgfQp9CgpmdW5jdGlvbiB0cmltSGlzdG9yeSgpIHsKICB3
::B64:agent.js:aGlsZSAoaGlzdG9yeS5sZW5ndGggPiBNQVhfSElTVE9SWSkgewogICAgbGV0IGkgPSAxOwogICAgd2hpbGUgKGkgPCBoaXN0b3J5Lmxlbmd0aCAmJiAhKGhpc3RvcnlbaV0ucm9sZSA9PT0gInVzZXIiICYmIHR5cGVvZiBoaXN0b3J5W2ldLmNvbnRlbnQgPT09ICJz
::B64:agent.js:dHJpbmciKSkgaSsrOwogICAgaWYgKGkgPj0gaGlzdG9yeS5sZW5ndGgpIGJyZWFrOwogICAgaGlzdG9yeS5zcGxpY2UoMCwgaSk7CiAgfQp9Cgphc3luYyBmdW5jdGlvbiBydW5UYXNrKGNvbW1hbmQpIHsKICBjb25zdCBzdGFydExlbiA9IGhpc3RvcnkubGVuZ3Ro
::B64:agent.js:OwogIGhpc3RvcnkucHVzaCh7IHJvbGU6ICJ1c2VyIiwgY29udGVudDogY29tbWFuZCB9KTsKICBsZXQgbnVkZ2VzID0gMDsKCiAgdHJ5IHsKICAgIGZvciAobGV0IHN0ZXAgPSAxOyBzdGVwIDw9IE1BWF9TVEVQUzsgc3RlcCsrKSB7CiAgICAgIGNvbnN0IG1zZyA9
::B64:agent.js:IGF3YWl0IGNhbGxMTE0oW3sgcm9sZTogInN5c3RlbSIsIGNvbnRlbnQ6IFNZU1RFTSB9LCAuLi5oaXN0b3J5XSk7CiAgICAgIGhpc3RvcnkucHVzaChtc2cpOwoKICAgICAgaWYgKCFtc2cudG9vbF9jYWxscz8ubGVuZ3RoKSB7CiAgICAgICAgLy8gTW9kZWwgY3Vt
::B64:agent.js:YSBtZW51bGlzIHRla3MvcmVuY2FuYSB0YW5wYSBtZW1hbmdnaWwgdG9vbCAtPiBwYWtzYSBwYW5nZ2lsIHRvb2wKICAgICAgICBpZiAobnVkZ2VzIDwgMykgewogICAgICAgICAgbnVkZ2VzKys7CiAgICAgICAgICBoaXN0b3J5LnB1c2goewogICAgICAgICAgICBy
::B64:agent.js:b2xlOiAidXNlciIsCiAgICAgICAgICAgIGNvbnRlbnQ6ICJLYW11IGhhcnVzIG1lbWFuZ2dpbCB0b29sLiBKYW5nYW4gbWVudWxpcyB0ZWtzIGJpYXNhLiBMYW5nc3VuZyBwYW5nZ2lsIHRvb2wgeWFuZyBzZXN1YWksIGF0YXUgcGFuZ2dpbCBkb25lIGppa2EgdHVn
::B64:agent.js:YXMgc3VkYWggc2VsZXNhaS4iLAogICAgICAgICAgfSk7CiAgICAgICAgICBjb250aW51ZTsKICAgICAgICB9CiAgICAgICAgY29uc29sZS5sb2coIlxuQWdlbnQ6IiwgbXNnLmNvbnRlbnQgfHwgIih0aWRhayBhZGEgamF3YWJhbikiKTsKICAgICAgICByZXR1cm47
::B64:agent.js:CiAgICAgIH0KCiAgICAgIC8vIFR1Z2FzIHNlbGVzYWk6IHNlbXVhIHRvb2xfY2FsbCB3YWppYiBkaWphd2FiIGFnYXIgcml3YXlhdCB0ZXRhcCB2YWxpZAogICAgICBjb25zdCBkb25lQ2FsbCA9IG1zZy50b29sX2NhbGxzLmZpbmQoKGMpID0+IGMuZnVuY3Rpb24u
::B64:agent.js:bmFtZSA9PT0gImRvbmUiKTsKICAgICAgaWYgKGRvbmVDYWxsKSB7CiAgICAgICAgbGV0IG0gPSAiIjsKICAgICAgICB0cnkgewogICAgICAgICAgbSA9IEpTT04ucGFyc2UoZG9uZUNhbGwuZnVuY3Rpb24uYXJndW1lbnRzIHx8ICJ7fSIpLm1lc3NhZ2UgfHwgIiI7
::B64:agent.js:CiAgICAgICAgfSBjYXRjaCB7fQogICAgICAgIGZvciAoY29uc3QgY2FsbCBvZiBtc2cudG9vbF9jYWxscykgewogICAgICAgICAgaGlzdG9yeS5wdXNoKHsgcm9sZTogInRvb2wiLCB0b29sX2NhbGxfaWQ6IGNhbGwuaWQsIGNvbnRlbnQ6IGNhbGwgPT09IGRvbmVD
::B64:agent.js:YWxsID8gIm9rIiA6ICJkaWxld2F0aSIgfSk7CiAgICAgICAgfQogICAgICAgIGNvbnNvbGUubG9nKCJcbkFnZW50OiIsIG0gfHwgIlNlbGVzYWkuIik7CiAgICAgICAgcmV0dXJuOwogICAgICB9CgogICAgICBmb3IgKGNvbnN0IGNhbGwgb2YgbXNnLnRvb2xfY2Fs
::B64:agent.js:bHMpIHsKICAgICAgICBjb25zdCBuYW1lID0gY2FsbC5mdW5jdGlvbi5uYW1lOwogICAgICAgIGxldCByZXN1bHQ7CiAgICAgICAgdHJ5IHsKICAgICAgICAgIGNvbnN0IGFyZ3MgPSBKU09OLnBhcnNlKGNhbGwuZnVuY3Rpb24uYXJndW1lbnRzIHx8ICJ7fSIpOwog
::B64:agent.js:ICAgICAgICAgY29uc29sZS5sb2coYFske3N0ZXB9XSAke25hbWV9YCwgYXJncyk7CiAgICAgICAgICBpZiAoIWltcGxbbmFtZV0pIHRocm93IG5ldyBFcnJvcigiVG9vbCB0aWRhayBkaWtlbmFsOiAiICsgbmFtZSk7CiAgICAgICAgICByZXN1bHQgPSBhd2FpdCBp
::B64:agent.js:bXBsW25hbWVdKGFyZ3MpOwogICAgICAgIH0gY2F0Y2ggKGUpIHsKICAgICAgICAgIHJlc3VsdCA9ICJFUlJPUjogIiArIGUubWVzc2FnZTsKICAgICAgICB9CiAgICAgICAgaGlzdG9yeS5wdXNoKHsgcm9sZTogInRvb2wiLCB0b29sX2NhbGxfaWQ6IGNhbGwuaWQs
::B64:agent.js:IGNvbnRlbnQ6IFN0cmluZyhyZXN1bHQpLnNsaWNlKDAsIDYwMDApIH0pOwogICAgICB9CgogICAgICAvLyBLaXJpbSBzY3JlZW5zaG90IChqaWthIGFkYSkgc2ViYWdhaSBnYW1iYXI7IGdhbWJhciBsYW1hIGRpYnVhbmcgYWdhciByaW5nYW4KICAgICAgaWYgKHBl
::B64:agent.js:bmRpbmdJbWFnZXMubGVuZ3RoKSB7CiAgICAgICAgc3RyaXBJbWFnZXMoKTsKICAgICAgICBoaXN0b3J5LnB1c2goewogICAgICAgICAgcm9sZTogInVzZXIiLAogICAgICAgICAgY29udGVudDogWwogICAgICAgICAgICB7IHR5cGU6ICJ0ZXh0IiwgdGV4dDogIklu
::B64:agent.js:aSBzY3JlZW5zaG90IGxheWFyIHRlcmJhcnU6IiB9LAogICAgICAgICAgICAuLi5wZW5kaW5nSW1hZ2VzLnNwbGljZSgwKS5tYXAoKGI2NCkgPT4gKHsKICAgICAgICAgICAgICB0eXBlOiAiaW1hZ2VfdXJsIiwKICAgICAgICAgICAgICBpbWFnZV91cmw6IHsgdXJs
::B64:agent.js:OiBgZGF0YTppbWFnZS9wbmc7YmFzZTY0LCR7YjY0fWAgfSwKICAgICAgICAgICAgfSkpLAogICAgICAgICAgXSwKICAgICAgICB9KTsKICAgICAgfQogICAgICBhd2FpdCBzbGVlcCgzMDApOwogICAgfQogICAgY29uc29sZS5sb2coIkJlcmhlbnRpOiBtZWxld2F0
::B64:agent.js:aSBiYXRhcyBsYW5na2FoLiIpOwogIH0gY2F0Y2ggKGUpIHsKICAgIGhpc3RvcnkubGVuZ3RoID0gc3RhcnRMZW47IC8vIGJ1YW5nIHJpd2F5YXQgdHVnYXMgeWFuZyBnYWdhbCBzdXBheWEgdGlkYWsgbWVydXNhayBwZXJjYWthcGFuIGJlcmlrdXRueWEKICAgIHRo
::B64:agent.js:cm93IGU7CiAgfSBmaW5hbGx5IHsKICAgIHN0cmlwSW1hZ2VzKCk7CiAgICB0cmltSGlzdG9yeSgpOwogIH0KfQoKY29uc29sZS5sb2coYEFnZW50IHNpYXAuIFZlcnNpICR7bG9jYWxWZXJzaW9uKCl9LiBGb2xkZXIgdXBsb2FkOiAke1NBRkVfRElSfWApOwpjb25z
::B64:agent.js:b2xlLmxvZyhgSXppbiBzZWJlbHVtIGFrc2k6ICR7Q09ORklSTSA/ICJBS1RJRiIgOiAiTUFUSSJ9LiBUZWthbiBDdHJsK0Mga2FwYW4gc2FqYSB1bnR1ayBtZW5naGVudGlrYW4uYCk7CmNvbnNvbGUubG9nKCdLZXRpayBwZXJpbnRhaCBkYWxhbSBiYWhhc2EgYmlh
::B64:agent.js:c2EuIFBlcmludGFoIGtodXN1czogL3Jlc2V0IChsdXBha2FuIHBlcmNha2FwYW4pLCAvdXBkYXRlIChwZXJiYXJ1aSksIC92ZXJzaSwgZXhpdC4nKTsKY2hlY2tVcGRhdGUoKTsKd2hpbGUgKHRydWUpIHsKICBjb25zdCBjbWQgPSBhd2FpdCBybC5xdWVzdGlvbigi
::B64:agent.js:XG5QZXJpbnRhaD4gIik7CiAgY29uc3QgYyA9IGNtZC50cmltKCk7CiAgaWYgKGMgPT09ICJleGl0IikgYnJlYWs7CiAgaWYgKCFjKSBjb250aW51ZTsKICBpZiAoYyA9PT0gIi92ZXJzaSIpIHsKICAgIGNvbnNvbGUubG9nKGBWZXJzaSBhZ2VudDogJHtsb2NhbFZl
::B64:agent.js:cnNpb24oKX1gKTsKICAgIGF3YWl0IGNoZWNrVXBkYXRlKCk7CiAgICBpZiAoIXBlbmRpbmdWZXJzaW9uKSBjb25zb2xlLmxvZygiU3VkYWggdmVyc2kgdGVyYmFydSAoYXRhdSB1cGRhdGUgb25saW5lIHRpZGFrIGFrdGlmKS4iKTsKICAgIGNvbnRpbnVlOwogIH0K
::B64:agent.js:ICBpZiAoYyA9PT0gIi91cGRhdGUiKSB7CiAgICBjb25zb2xlLmxvZygiTWVtcGVyYmFydWkuLi4gYWdlbnQgYWthbiBtZW51dHVwIGRhbiBtZW55YWxhIGxhZ2kgb3RvbWF0aXMgbGV3YXQgc3RhcnQtYWdlbnQuYmF0LiIpOwogICAgYXdhaXQgY29udGV4dC5jbG9z
::B64:agent.js:ZSgpOwogICAgcmwuY2xvc2UoKTsKICAgIHByb2Nlc3MuZXhpdCg0Mik7IC8vIGtvZGUgNDIgPSBwZXJtaW50YWFuIHJlc3RhcnQgdW50dWsgdXBkYXRlOyBkaXRhbmdrYXAgb2xlaCBzdGFydC1hZ2VudC5iYXQKICB9CiAgaWYgKGMgPT09ICIvcmVzZXQiKSB7CiAg
::B64:agent.js:ICBoaXN0b3J5Lmxlbmd0aCA9IDA7CiAgICBjb25zb2xlLmxvZygiUGVyY2FrYXBhbiBkaWx1cGFrYW4uIik7CiAgICBjb250aW51ZTsKICB9CiAgdHJ5IHsKICAgIGF3YWl0IHJ1blRhc2soYyk7CiAgfSBjYXRjaCAoZSkgewogICAgY29uc29sZS5lcnJvcigiR2Fn
::B64:agent.js:YWw6IiwgZS5tZXNzYWdlKTsKICB9Cn0KYXdhaXQgY29udGV4dC5jbG9zZSgpOwpybC5jbG9zZSgpOwo=
::B64:package.json:ewogICJuYW1lIjogImJvdC1hZ2VudCIsCiAgInZlcnNpb24iOiAiMS4wLjAiLAogICJ0eXBlIjogIm1vZHVsZSIsCiAgInNjcmlwdHMiOiB7CiAgICAic3RhcnQiOiAibm9kZSBhZ2VudC5qcyIKICB9LAogICJkZXBlbmRlbmNpZXMiOiB7CiAgICAicGxheXdyaWdo
::B64:package.json:dCI6ICJeMS40OC4wIgogIH0KfQo=
