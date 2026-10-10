@echo off
setlocal EnableExtensions
chcp 65001 >nul
title Agent Automation
set "SELF=%~f0"
set "EMBED_AGENT_VER=9"

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
set "LOCAL_AGENT=0"
if exist "%APPDIR%\version.txt" set /p LOCAL_AGENT=<"%APPDIR%\version.txt"
for /f "tokens=1" %%v in ("%LOCAL_AGENT%") do set "LOCAL_AGENT=%%v"
if %EMBED_AGENT_VER% GTR %LOCAL_AGENT% set "NEED_EXTRACT=1"
:EXTRACT_DECIDED
if not defined NEED_EXTRACT goto EXTRACT_SKIP
powershell -NoProfile -ExecutionPolicy Bypass -Command "$l=Get-Content -LiteralPath $env:SELF; foreach($n in 'agent.js','package.json'){ $t='::B64:'+$n+':'; $b=($l | Where-Object {$_.StartsWith($t)} | ForEach-Object {$_.Substring($t.Length).Trim()}) -join ''; [IO.File]::WriteAllBytes((Join-Path $env:APPDIR $n),[Convert]::FromBase64String($b)) }"
if errorlevel 1 goto FAIL_EXTRACT
> "%APPDIR%\version.txt" echo %EMBED_AGENT_VER%
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
for /f "tokens=1" %%v in ("%LOCALVER%") do set "LOCALVER=%%v"
for /f "tokens=1" %%v in ("%REMOTEVER%") do set "REMOTEVER=%%v"
call :SHOW_NOTICE
if %REMOTEVER% LEQ %LOCALVER% goto UPDATE_SAME
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
set "CONFIRM=0"
if /i "%AUTO_APPROVE%"=="off" set "CONFIRM=1"
if exist "auto.txt" for /f "usebackq delims=" %%A in ("auto.txt") do if /i "%%A"=="off" set "CONFIRM=1"
node agent.js
if %errorlevel% EQU 42 goto STEP_UPDATE
echo.
echo Agent berhenti.
pause
exit /b 0

rem ---------- Subroutine: simpan konfigurasi ----------
:SAVE_CONFIG
if not defined AUTO_UPDATE set "AUTO_UPDATE=1"
if not defined ROUTER_MODEL set "ROUTER_MODEL=bot-combo"
if not defined SAFE_DIR set "SAFE_DIR=%APPDIR%\upload-folder"
> "config.bat" echo set "ROUTER_KEY=%ROUTER_KEY%"
>> "config.bat" echo set "ROUTER_MODEL=%ROUTER_MODEL%"
>> "config.bat" echo set "SAFE_DIR=%SAFE_DIR%"
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
::B64:agent.js:YWQtZm9sZGVyIik7Ci8vID09PT09IEl6aW4gYWtzaSA9PT09PQovLyBvbiAgICA9IHNlbXVhIGl6aW4gb3RvbWF0aXMgInkiICh0aWRhayBtZW51bmdndSBrYW11KQovLyBhbWFuICA9IG90b21hdGlzICJ5IiBrZWN1YWxpIGFrc2kgeWFuZyBtZXJ1c2FrL3N1bGl0
::B64:agent.js:IGRpYmF0YWxrYW4gKG1lbmltcGEgZmlsZSwgaGFwdXMsIHR1dHVwIGplbmRlbGEsIHBpbmRhaCkKLy8gb2ZmICAgPSBzZWxhbHUgYmVydGFueWEgeS9uCi8vIFViYWgga2FwYW4gc2FqYSBkZW5nYW4gcGVyaW50YWggL2F1dG8gb258YW1hbnxvZmYgKHRlcnNpbXBh
::B64:agent.js:biBkaSBhdXRvLnR4dCkuIEJhd2FhbiBhZGEgZGkgREVGQVVMVF9BVVRPLgpjb25zdCBERUZBVUxUX0FVVE8gPSAib24iOwpjb25zdCBBVVRPX0ZJTEUgPSAiYXV0by50eHQiOwpsZXQgYXV0b01vZGUgPSBERUZBVUxUX0FVVE87CnsKICBjb25zdCBlbnYgPSBTdHJp
::B64:agent.js:bmcocHJvY2Vzcy5lbnYuQVVUT19BUFBST1ZFIHx8ICIiKS50b0xvd2VyQ2FzZSgpOwogIGlmIChbIm9uIiwgImFtYW4iLCAib2ZmIl0uaW5jbHVkZXMoZW52KSkgYXV0b01vZGUgPSBlbnY7CiAgdHJ5IHsKICAgIGNvbnN0IHNhdmVkID0gZnMucmVhZEZpbGVTeW5j
::B64:agent.js:KEFVVE9fRklMRSwgInV0ZjgiKS50cmltKCkudG9Mb3dlckNhc2UoKTsKICAgIGlmIChbIm9uIiwgImFtYW4iLCAib2ZmIl0uaW5jbHVkZXMoc2F2ZWQpKSBhdXRvTW9kZSA9IHNhdmVkOwogIH0gY2F0Y2gge30KfQpjb25zdCBSSVNLWV9BU0sgPSAvXihUSU1QQXxQ
::B64:agent.js:aW5kYWhrYW4ga2UgUmVjeWNsZXxUdXR1cCBqZW5kZWxhfFBpbmRhaGthbjp8RWtzdHJha3xNYXRpa2FuIHByb3NlcykvaTsKY29uc3QgTUFYX1NURVBTID0gMzA7CmNvbnN0IEhPTUUgPSBvcy5ob21lZGlyKCk7CmNvbnN0IFNFQVJDSF9ST09UUyA9IFtIT01FLCAu
::B64:agent.js:Li4ocHJvY2Vzcy5lbnYuU0VBUkNIX1JPT1RTID8gcHJvY2Vzcy5lbnYuU0VBUkNIX1JPT1RTLnNwbGl0KCI7IikgOiBbXSldOwpmb3IgKGNvbnN0IEwgb2YgIkRFRkdISUpLTE1OT1BRUlNUVVZXWFlaIikgewogIC8vIERyaXZlIGxhaW4gKEQ6LCBFOiwgZmxhc2hk
::B64:agent.js:aXNrLCBkbGwpIGlrdXQgZGljYXJpIG90b21hdGlzCiAgdHJ5IHsKICAgIGlmIChmcy5leGlzdHNTeW5jKGAke0x9OlxcYCkpIFNFQVJDSF9ST09UUy5wdXNoKGAke0x9OlxcYCk7CiAgfSBjYXRjaCB7fQp9CgppZiAoIUFQSV9LRVkpIHsKICBjb25zb2xlLmVycm9y
::B64:agent.js:KCJST1VURVJfS0VZIGJlbHVtIGRpaXNpLiIpOwogIHByb2Nlc3MuZXhpdCgxKTsKfQpmcy5ta2RpclN5bmMoU0FGRV9ESVIsIHsgcmVjdXJzaXZlOiB0cnVlIH0pOwoKY29uc3QgcmwgPSByZWFkbGluZS5jcmVhdGVJbnRlcmZhY2UoeyBpbnB1dDogcHJvY2Vzcy5z
::B64:agent.js:dGRpbiwgb3V0cHV0OiBwcm9jZXNzLnN0ZG91dCB9KTsKY29uc3Qgc2xlZXAgPSAobXMpID0+IG5ldyBQcm9taXNlKChyKSA9PiBzZXRUaW1lb3V0KHIsIG1zKSk7CgovLyA9PT09PSBQZW1iZXJpdGFodWFuIHVwZGF0ZSAoVVJMIGRpYmVyaWthbiBvdG9tYXRpcyBv
::B64:agent.js:bGVoIHN0YXJ0LWFnZW50LmJhdCkgPT09PT0KY29uc3QgVVBEX1VSTCA9IHByb2Nlc3MuZW52LlVQRF9VUkwgfHwgIiI7CmNvbnN0IGxvY2FsVmVyc2lvbiA9ICgpID0+IHsKICB0cnkgewogICAgcmV0dXJuIGZzLnJlYWRGaWxlU3luYygidmVyc2lvbi50eHQiLCAi
::B64:agent.js:dXRmOCIpLnRyaW0oKSB8fCAiMCI7CiAgfSBjYXRjaCB7CiAgICByZXR1cm4gIjAiOwogIH0KfTsKbGV0IHBlbmRpbmdWZXJzaW9uID0gIiI7Cgphc3luYyBmdW5jdGlvbiBjaGVja1VwZGF0ZSgpIHsKICBpZiAoIVVQRF9VUkwgfHwgcHJvY2Vzcy5lbnYuQVVUT19V
::B64:agent.js:UERBVEUgPT09ICIwIikgcmV0dXJuOwogIHRyeSB7CiAgICBjb25zdCByZXMgPSBhd2FpdCBmZXRjaChgJHtVUERfVVJMfS92ZXJzaW9uLnR4dGAsIHsgc2lnbmFsOiBBYm9ydFNpZ25hbC50aW1lb3V0KDEwMDAwKSB9KTsKICAgIGlmICghcmVzLm9rKSByZXR1cm47
::B64:agent.js:CiAgICBjb25zdCByZW1vdGUgPSAoYXdhaXQgcmVzLnRleHQoKSkudHJpbSgpOwogICAgY29uc3QgbG9jID0gbG9jYWxWZXJzaW9uKCk7CiAgICBjb25zdCBuZXdlciA9IC9eXGQrJC8udGVzdChyZW1vdGUpICYmIC9eXGQrJC8udGVzdChsb2MpID8gTnVtYmVyKHJl
::B64:agent.js:bW90ZSkgPiBOdW1iZXIobG9jKSA6IHJlbW90ZSAhPT0gbG9jOwogICAgaWYgKHJlbW90ZSAmJiBuZXdlciAmJiByZW1vdGUgIT09IHBlbmRpbmdWZXJzaW9uKSB7CiAgICAgIHBlbmRpbmdWZXJzaW9uID0gcmVtb3RlOwogICAgICBjb25zb2xlLmxvZyhgXG4qKiog
::B64:agent.js:VVBEQVRFIFRFUlNFRElBOiB2ZXJzaSAke3JlbW90ZX0gKHZlcnNpIGthbXU6ICR7bG9jYWxWZXJzaW9uKCl9KSAqKipgKTsKICAgICAgY29uc29sZS5sb2coJyAgICBLZXRpayAiL3VwZGF0ZSIgdW50dWsgbWVtcGVyYmFydWkgb3RvbWF0aXMgc2VrYXJhbmcuJyk7
::B64:agent.js:CiAgICB9CiAgfSBjYXRjaCB7fQp9CnNldEludGVydmFsKGNoZWNrVXBkYXRlLCAxNSAqIDYwICogMTAwMCkudW5yZWYoKTsKCi8vID09PT09IEJyb3dzZXI6IHBha2FpIENocm9tZS9FZGdlIEFTTEkgKGJ1a2FuIENocm9taXVtIGJhd2FhbiBQbGF5d3JpZ2h0KSA9
::B64:agent.js:PT09PQovLyBBbGFzYW46IHZpZGVvIFlvdVR1YmUgYnV0dWggY29kZWMgbGVuZ2thcCwgZGFuIEdvb2dsZSBtZW1ibG9raXIgbG9naW4gZGkgYnJvd3NlciAib3RvbWF0aXMiLgovLyBDaHJvbWUgZGlqYWxhbmthbiBiaWFzYSBkZW5nYW4gcG9ydCBkZWJ1ZywgbGFs
::B64:agent.js:dSBQbGF5d3JpZ2h0IG1lbnlhbWJ1bmcga2Ugc2l0dS4KLy8gTG9naW4gdGVyc2ltcGFuIHBlcm1hbmVuIGRpIGZvbGRlciAuL2Nocm9tZS1wcm9maWxlLgpjb25zdCBERUJVR19QT1JUID0gTnVtYmVyKHByb2Nlc3MuZW52LkRFQlVHX1BPUlQgfHwgOTIyMik7CmNv
::B64:agent.js:bnN0IFBST0ZJTEVfRElSID0gcGF0aC5yZXNvbHZlKCIuL2Nocm9tZS1wcm9maWxlIik7CgpmdW5jdGlvbiBmaW5kQnJvd3NlckV4ZSgpIHsKICBjb25zdCBsb2NhbCA9IHByb2Nlc3MuZW52LkxPQ0FMQVBQREFUQSB8fCAiIjsKICBjb25zdCBwZiA9IHByb2Nlc3Mu
::B64:agent.js:ZW52LlByb2dyYW1GaWxlcyB8fCAiQzpcXFByb2dyYW0gRmlsZXMiOwogIGNvbnN0IHBmODYgPSBwcm9jZXNzLmVudlsiUHJvZ3JhbUZpbGVzKHg4NikiXSB8fCAiQzpcXFByb2dyYW0gRmlsZXMgKHg4NikiOwogIHJldHVybiBbCiAgICBwcm9jZXNzLmVudi5DSFJP
::B64:agent.js:TUVfUEFUSCwKICAgIHBhdGguam9pbihwZiwgIkdvb2dsZSIsICJDaHJvbWUiLCAiQXBwbGljYXRpb24iLCAiY2hyb21lLmV4ZSIpLAogICAgcGF0aC5qb2luKHBmODYsICJHb29nbGUiLCAiQ2hyb21lIiwgIkFwcGxpY2F0aW9uIiwgImNocm9tZS5leGUiKSwKICAg
::B64:agent.js:IHBhdGguam9pbihsb2NhbCwgIkdvb2dsZSIsICJDaHJvbWUiLCAiQXBwbGljYXRpb24iLCAiY2hyb21lLmV4ZSIpLAogICAgcGF0aC5qb2luKHBmODYsICJNaWNyb3NvZnQiLCAiRWRnZSIsICJBcHBsaWNhdGlvbiIsICJtc2VkZ2UuZXhlIiksCiAgICBwYXRoLmpv
::B64:agent.js:aW4ocGYsICJNaWNyb3NvZnQiLCAiRWRnZSIsICJBcHBsaWNhdGlvbiIsICJtc2VkZ2UuZXhlIiksCiAgXQogICAgLmZpbHRlcihCb29sZWFuKQogICAgLmZpbmQoKHgpID0+IGZzLmV4aXN0c1N5bmMoeCkpOwp9Cgphc3luYyBmdW5jdGlvbiBkZWJ1Z1BvcnRVcCgp
::B64:agent.js:IHsKICB0cnkgewogICAgY29uc3QgciA9IGF3YWl0IGZldGNoKGBodHRwOi8vMTI3LjAuMC4xOiR7REVCVUdfUE9SVH0vanNvbi92ZXJzaW9uYCwgeyBzaWduYWw6IEFib3J0U2lnbmFsLnRpbWVvdXQoMTUwMCkgfSk7CiAgICByZXR1cm4gci5vazsKICB9IGNhdGNo
::B64:agent.js:IHsKICAgIHJldHVybiBmYWxzZTsKICB9Cn0KCmxldCBicm93c2VySGFuZGxlID0gbnVsbDsKYXN5bmMgZnVuY3Rpb24gb3BlbkJyb3dzZXIoKSB7CiAgY29uc3QgZXhlID0gZmluZEJyb3dzZXJFeGUoKTsKICBpZiAoZXhlKSB7CiAgICBpZiAoIShhd2FpdCBkZWJ1
::B64:agent.js:Z1BvcnRVcCgpKSkgewogICAgICBzcGF3bigKICAgICAgICBleGUsCiAgICAgICAgWwogICAgICAgICAgYC0tcmVtb3RlLWRlYnVnZ2luZy1wb3J0PSR7REVCVUdfUE9SVH1gLAogICAgICAgICAgYC0tdXNlci1kYXRhLWRpcj0ke1BST0ZJTEVfRElSfWAsCiAgICAg
::B64:agent.js:ICAgICAiLS1uby1maXJzdC1ydW4iLAogICAgICAgICAgIi0tbm8tZGVmYXVsdC1icm93c2VyLWNoZWNrIiwKICAgICAgICAgICItLWF1dG9wbGF5LXBvbGljeT1uby11c2VyLWdlc3R1cmUtcmVxdWlyZWQiLAogICAgICAgICAgImFib3V0OmJsYW5rIiwKICAgICAg
::B64:agent.js:ICBdLAogICAgICAgIHsgZGV0YWNoZWQ6IHRydWUsIHN0ZGlvOiAiaWdub3JlIiB9CiAgICAgICkudW5yZWYoKTsKICAgICAgZm9yIChsZXQgaSA9IDA7IGkgPCAzMCAmJiAhKGF3YWl0IGRlYnVnUG9ydFVwKCkpOyBpKyspIGF3YWl0IHNsZWVwKDUwMCk7CiAgICB9
::B64:agent.js:CiAgICBpZiAoYXdhaXQgZGVidWdQb3J0VXAoKSkgewogICAgICBicm93c2VySGFuZGxlID0gYXdhaXQgY2hyb21pdW0uY29ubmVjdE92ZXJDRFAoYGh0dHA6Ly8xMjcuMC4wLjE6JHtERUJVR19QT1JUfWApOwogICAgICBjb25zb2xlLmxvZyhgQnJvd3NlcjogJHtw
::B64:agent.js:YXRoLmJhc2VuYW1lKGV4ZSl9IChsb2dpbiB0ZXJzaW1wYW4gZGkgJHtQUk9GSUxFX0RJUn0pYCk7CiAgICAgIHJldHVybiBicm93c2VySGFuZGxlLmNvbnRleHRzKClbMF0gfHwgKGF3YWl0IGJyb3dzZXJIYW5kbGUubmV3Q29udGV4dCgpKTsKICAgIH0KICB9CiAg
::B64:agent.js:Y29uc29sZS5sb2coIkNocm9tZS9FZGdlIHRpZGFrIGRpdGVtdWthbiwgbWVtYWthaSBDaHJvbWl1bSBiYXdhYW4gKHZpZGVvIGRhbiBsb2dpbiBHb29nbGUgbXVuZ2tpbiBiZXJtYXNhbGFoKS4iKTsKICByZXR1cm4gY2hyb21pdW0ubGF1bmNoUGVyc2lzdGVudENv
::B64:agent.js:bnRleHQoIi4vYnJvd3Nlci1wcm9maWxlIiwgewogICAgaGVhZGxlc3M6IGZhbHNlLAogICAgYXJnczogWyItLWF1dG9wbGF5LXBvbGljeT1uby11c2VyLWdlc3R1cmUtcmVxdWlyZWQiXSwKICAgIGlnbm9yZURlZmF1bHRBcmdzOiBbIi0tZW5hYmxlLWF1dG9tYXRp
::B64:agent.js:b24iXSwKICB9KTsKfQoKY29uc3QgY29udGV4dCA9IGF3YWl0IG9wZW5Ccm93c2VyKCk7CmxldCBwYWdlID0gY29udGV4dC5wYWdlcygpLmZpbmQoKHgpID0+ICF4LmlzQ2xvc2VkKCkpIHx8IChhd2FpdCBjb250ZXh0Lm5ld1BhZ2UoKSk7Cgphc3luYyBmdW5jdGlv
::B64:agent.js:biBlbnN1cmVQYWdlKCkgewogIGlmICghcGFnZS5pc0Nsb3NlZCgpKSByZXR1cm47CiAgcGFnZSA9IGNvbnRleHQucGFnZXMoKS5maW5kKCh4KSA9PiAheC5pc0Nsb3NlZCgpKSB8fCAoYXdhaXQgY29udGV4dC5uZXdQYWdlKCkpOwp9Cgphc3luYyBmdW5jdGlvbiBz
::B64:agent.js:aHV0ZG93bkJyb3dzZXIoKSB7CiAgLy8gQ2hyb21lIHNlbmdhamEgZGliaWFya2FuIHRlcmJ1a2EgYWdhciBsb2dpbiBkYW4gdGFiIHRldGFwIGFkYQogIHRyeSB7CiAgICBpZiAoYnJvd3NlckhhbmRsZSkgYXdhaXQgYnJvd3NlckhhbmRsZS5jbG9zZSgpOwogICAg
::B64:agent.js:ZWxzZSBhd2FpdCBjb250ZXh0LmNsb3NlKCk7CiAgfSBjYXRjaCB7fQp9CgovLyBOYW1hIGZpbGUgcmVsYXRpZiBkaWNhcmkgZGkgU0FGRV9ESVI7IHBhdGggbGVuZ2thcCBkaSBsb2thc2kgbWFuYSBwdW4gYm9sZWguCi8vIFBlbmdhbWFubnlhIGFkYWxhaCBpemlu
::B64:agent.js:IHkvbiBzZWJlbHVtIHNldGlhcCB1cGxvYWQuCmZ1bmN0aW9uIHNhZmVQYXRoKG5hbWUpIHsKICBjb25zdCBmdWxsID0gcGF0aC5yZXNvbHZlKFNBRkVfRElSLCBTdHJpbmcobmFtZSkucmVwbGFjZSgvXiJ8IiQvZywgIiIpKTsKICBpZiAoIWZzLmV4aXN0c1N5bmMo
::B64:agent.js:ZnVsbCkgfHwgIWZzLnN0YXRTeW5jKGZ1bGwpLmlzRmlsZSgpKSB7CiAgICB0aHJvdyBuZXcgRXJyb3IoIkZpbGUgdGlkYWsgZGl0ZW11a2FuOiAiICsgZnVsbCk7CiAgfQogIHJldHVybiBmdWxsOwp9Cgphc3luYyBmdW5jdGlvbiBhc2sobXNnKSB7CiAgY29uc3Qg
::B64:agent.js:Zmlyc3QgPSBTdHJpbmcobXNnKS5zcGxpdCgiXG4iKVswXTsKICBpZiAoYXV0b01vZGUgPT09ICJvbiIgfHwgKGF1dG9Nb2RlID09PSAiYW1hbiIgJiYgIVJJU0tZX0FTSy50ZXN0KGZpcnN0KSkpIHsKICAgIGNvbnNvbGUubG9nKGAgIFtpemluIG90b21hdGlzOiB5
::B64:agent.js:YV0gJHtmaXJzdC5zbGljZSgwLCAxNDApfWApOwogICAgcmV0dXJuIHRydWU7CiAgfQogIGNvbnN0IGEgPSBhd2FpdCBybC5xdWVzdGlvbihgXG5bSVpJTl0gJHttc2d9ICh5L24pOiBgKTsKICByZXR1cm4gYS50cmltKCkudG9Mb3dlckNhc2UoKSA9PT0gInkiOwp9
::B64:agent.js:CgovLyA9PT09PSBIZWxwZXIgUG93ZXJTaGVsbCAoa29udHJvbCBkZXNrdG9wIFdpbmRvd3MgdGFucGEgbGlicmFyeSB0YW1iYWhhbikgPT09PT0KZnVuY3Rpb24gcHMoc2NyaXB0LCBlbnYgPSB7fSwgdGltZW91dCA9IDMwMDAwKSB7CiAgY29uc3QgZW5jb2RlZCA9
::B64:agent.js:IEJ1ZmZlci5mcm9tKHNjcmlwdCwgInV0ZjE2bGUiKS50b1N0cmluZygiYmFzZTY0Iik7CiAgcmV0dXJuIG5ldyBQcm9taXNlKChyZXNvbHZlLCByZWplY3QpID0+IHsKICAgIGV4ZWNGaWxlKAogICAgICAicG93ZXJzaGVsbCIsCiAgICAgIFsiLU5vUHJvZmlsZSIs
::B64:agent.js:ICItTm9uSW50ZXJhY3RpdmUiLCAiLUVuY29kZWRDb21tYW5kIiwgZW5jb2RlZF0sCiAgICAgIHsgZW52OiB7IC4uLnByb2Nlc3MuZW52LCAuLi5lbnYgfSwgdGltZW91dCwgbWF4QnVmZmVyOiAyMCAqIDEwMjQgKiAxMDI0IH0sCiAgICAgIChlcnIsIHN0ZG91dCwg
::B64:agent.js:c3RkZXJyKSA9PgogICAgICAgIGVyciA/IHJlamVjdChuZXcgRXJyb3IoKHN0ZGVyciB8fCBlcnIubWVzc2FnZSkuc2xpY2UoMCwgMzAwKSkpIDogcmVzb2x2ZShzdGRvdXQudHJpbSgpKQogICAgKTsKICB9KTsKfQoKY29uc3QgUFNfSEVBRCA9IGAKQWRkLVR5cGUg
::B64:agent.js:QCIKdXNpbmcgU3lzdGVtOwp1c2luZyBTeXN0ZW0uUnVudGltZS5JbnRlcm9wU2VydmljZXM7CnB1YmxpYyBjbGFzcyBXIHsKICBbRGxsSW1wb3J0KCJ1c2VyMzIuZGxsIildIHB1YmxpYyBzdGF0aWMgZXh0ZXJuIGJvb2wgU2V0UHJvY2Vzc0RQSUF3YXJlKCk7CiAg
::B64:agent.js:W0RsbEltcG9ydCgidXNlcjMyLmRsbCIpXSBwdWJsaWMgc3RhdGljIGV4dGVybiBib29sIFNldEN1cnNvclBvcyhpbnQgeCwgaW50IHkpOwogIFtEbGxJbXBvcnQoInVzZXIzMi5kbGwiKV0gcHVibGljIHN0YXRpYyBleHRlcm4gdm9pZCBtb3VzZV9ldmVudCh1aW50
::B64:agent.js:IGYsIHVpbnQgZHgsIHVpbnQgZHksIGludCBkLCBVSW50UHRyIGUpOwp9CiJACltXXTo6U2V0UHJvY2Vzc0RQSUF3YXJlKCkgfCBPdXQtTnVsbApBZGQtVHlwZSAtQXNzZW1ibHlOYW1lIFN5c3RlbS5XaW5kb3dzLkZvcm1zLFN5c3RlbS5EcmF3aW5nCmA7CgpsZXQg
::B64:agent.js:c2NhbGUgPSAxOyAvLyByYXNpbyBsYXlhciBhc2xpIC8gc2NyZWVuc2hvdApjb25zdCBwZW5kaW5nSW1hZ2VzID0gW107IC8vIGdhbWJhciB5YW5nIGRpa2lyaW0ga2UgbW9kZWwgc2V0ZWxhaCB0b29sIGRpamFsYW5rYW4KCmNvbnN0IFNLSVBfRElSUyA9IG5ldyBT
::B64:agent.js:ZXQoWwogICJub2RlX21vZHVsZXMiLCAiYXBwZGF0YSIsICIuZ2l0IiwgIndpbmRvd3MiLCAicHJvZ3JhbSBmaWxlcyIsICJwcm9ncmFtIGZpbGVzICh4ODYpIiwKICAicHJvZ3JhbWRhdGEiLCAiJHJlY3ljbGUuYmluIiwgInN5c3RlbSB2b2x1bWUgaW5mb3JtYXRp
::B64:agent.js:b24iLApdKTsKbGV0IHNlYXJjaERlYWRsaW5lID0gMDsKCi8vIENhcmkgZm9sZGVyICh3YW50RmlsZXM9ZmFsc2UpIGF0YXUgZmlsZSAod2FudEZpbGVzPXRydWUpIGJlcmRhc2Fya2FuIHNlYmFnaWFuIG5hbWEKZnVuY3Rpb24gZmluZFBhdGhzKG5hbWUsIHJvb3Qs
::B64:agent.js:IGRlcHRoLCBvdXQsIHdhbnRGaWxlcykgewogIGlmIChkZXB0aCA8IDAgfHwgb3V0Lmxlbmd0aCA+PSAxMiB8fCBEYXRlLm5vdygpID4gc2VhcmNoRGVhZGxpbmUpIHJldHVybjsKICBsZXQgZW50cmllczsKICB0cnkgewogICAgZW50cmllcyA9IGZzLnJlYWRkaXJT
::B64:agent.js:eW5jKHJvb3QsIHsgd2l0aEZpbGVUeXBlczogdHJ1ZSB9KTsKICB9IGNhdGNoIHsKICAgIHJldHVybjsKICB9CiAgY29uc3QgcSA9IG5hbWUudG9Mb3dlckNhc2UoKTsKICBmb3IgKGNvbnN0IGUgb2YgZW50cmllcykgewogICAgY29uc3QgZnVsbCA9IHBhdGguam9p
::B64:agent.js:bihyb290LCBlLm5hbWUpOwogICAgaWYgKGUuaXNEaXJlY3RvcnkoKSkgewogICAgICBpZiAoU0tJUF9ESVJTLmhhcyhlLm5hbWUudG9Mb3dlckNhc2UoKSkgfHwgZS5uYW1lLnN0YXJ0c1dpdGgoIiQiKSkgY29udGludWU7CiAgICAgIGlmICghd2FudEZpbGVzICYm
::B64:agent.js:IGUubmFtZS50b0xvd2VyQ2FzZSgpLmluY2x1ZGVzKHEpKSBvdXQucHVzaChmdWxsKTsKICAgICAgZmluZFBhdGhzKG5hbWUsIGZ1bGwsIGRlcHRoIC0gMSwgb3V0LCB3YW50RmlsZXMpOwogICAgfSBlbHNlIGlmICh3YW50RmlsZXMgJiYgZS5pc0ZpbGUoKSAmJiBl
::B64:agent.js:Lm5hbWUudG9Mb3dlckNhc2UoKS5pbmNsdWRlcyhxKSkgewogICAgICBvdXQucHVzaChmdWxsKTsKICAgIH0KICB9Cn0KCmZ1bmN0aW9uIHNlYXJjaEV2ZXJ5d2hlcmUobmFtZSwgd2FudEZpbGVzKSB7CiAgY29uc3Qgb3V0ID0gW107CiAgc2VhcmNoRGVhZGxpbmUg
::B64:agent.js:PSBEYXRlLm5vdygpICsgMTIwMDA7IC8vIG1ha3NpbWFsIDEyIGRldGlrIGFnYXIgdGlkYWsgbWVuZ2dhbnR1bmcKICBmb3IgKGNvbnN0IHJvb3Qgb2YgU0VBUkNIX1JPT1RTKSBmaW5kUGF0aHMoU3RyaW5nKG5hbWUpLCByb290LCByb290ID09PSBIT01FID8gNSA6
::B64:agent.js:IDMsIG91dCwgd2FudEZpbGVzKTsKICByZXR1cm4gb3V0Lmxlbmd0aCA/IG91dC5qb2luKCJcbiIpIDogIlRpZGFrIGRpdGVtdWthbiI7Cn0KCi8vID09PT09ICJUYW5nYW4iIGFnZW50ID09PT09Ci8vID09PT09IEhlbHBlciB0YWIgYnJvd3NlciA9PT09PQpjb25z
::B64:agent.js:dCBmaXhVcmwgPSAodSkgPT4gKC9eW2Etel1bYS16MC05Ky4tXSo6XC9cLy9pLnRlc3QoU3RyaW5nKHUpKSA/IFN0cmluZyh1KSA6ICJodHRwczovLyIgKyBTdHJpbmcodSkpOwpjb25zdCBpc1RydWUgPSAodikgPT4gdiA9PT0gdHJ1ZSB8fCB2ID09PSAidHJ1ZSI7
::B64:agent.js:CmNvbnN0IGxpdmVQYWdlcyA9ICgpID0+IGNvbnRleHQucGFnZXMoKS5maWx0ZXIoKHgpID0+ICF4LmlzQ2xvc2VkKCkpOwoKYXN5bmMgZnVuY3Rpb24gdGFic1N1bW1hcnkoKSB7CiAgY29uc3QgYWxsID0gbGl2ZVBhZ2VzKCk7CiAgY29uc3QgbGluZXMgPSBbXTsK
::B64:agent.js:ICBmb3IgKGxldCBpID0gMDsgaSA8IGFsbC5sZW5ndGg7IGkrKykgewogICAgbGV0IHRpdGxlID0gIiI7CiAgICB0cnkgewogICAgICB0aXRsZSA9IGF3YWl0IGFsbFtpXS50aXRsZSgpOwogICAgfSBjYXRjaCB7fQogICAgbGluZXMucHVzaChgJHtpICsgMX0ke2Fs
::B64:agent.js:bFtpXSA9PT0gcGFnZSA/ICIqIiA6ICIgIn0gJHt0aXRsZS5zbGljZSgwLCA2MCl9IHwgJHthbGxbaV0udXJsKCkuc2xpY2UoMCwgMTAwKX1gKTsKICB9CiAgcmV0dXJuIChsaW5lcy5qb2luKCJcbiIpIHx8ICIodGlkYWsgYWRhIHRhYikiKSArICJcbigqID0gdGFi
::B64:agent.js:IGFrdGlmIHlhbmcgZGlwYWthaSBhZ2VudCkiOwp9CgpmdW5jdGlvbiBwaWNrVGFiKGFsbCwgaW5kZXgpIHsKICBjb25zdCBuID0gTnVtYmVyKGluZGV4KTsKICBpZiAoIU51bWJlci5pc0Zpbml0ZShuKSB8fCBuID09PSAwKSByZXR1cm4gdW5kZWZpbmVkOwogIHJl
::B64:agent.js:dHVybiBuIDwgMCA/IGFsbC5hdChuKSA6IGFsbFtuIC0gMV07Cn0KCi8vID09PT09IEhlbHBlciBZb3VUdWJlID09PT09CmFzeW5jIGZ1bmN0aW9uIHNraXBBZHMoKSB7CiAgZm9yIChsZXQgaSA9IDA7IGkgPCAxMDsgaSsrKSB7CiAgICBjb25zdCBidG4gPSBhd2Fp
::B64:agent.js:dCBwYWdlLiQoIi55dHAtc2tpcC1hZC1idXR0b24sIC55dHAtYWQtc2tpcC1idXR0b24sIC55dHAtYWQtc2tpcC1idXR0b24tbW9kZXJuIik7CiAgICBpZiAoYnRuKSB7CiAgICAgIGF3YWl0IGJ0bi5jbGljaygpLmNhdGNoKCgpID0+IHt9KTsKICAgICAgcmV0dXJu
::B64:agent.js:OwogICAgfQogICAgaWYgKCEoYXdhaXQgcGFnZS4kKCIuYWQtc2hvd2luZyIpKSkgcmV0dXJuOwogICAgYXdhaXQgc2xlZXAoMTAwMCk7CiAgfQp9Cgphc3luYyBmdW5jdGlvbiByZWFkUGxheWVyU3RhdGUoKSB7CiAgcmV0dXJuIHBhZ2UuZXZhbHVhdGUoKCkgPT4g
::B64:agent.js:ewogICAgY29uc3QgdiA9IGRvY3VtZW50LnF1ZXJ5U2VsZWN0b3IoInZpZGVvIik7CiAgICBjb25zdCBlcnIgPSAhIWRvY3VtZW50LnF1ZXJ5U2VsZWN0b3IoIi55dHAtZXJyb3IiKTsKICAgIGlmICh2ICYmIHYucGF1c2VkICYmICFlcnIpIHYucGxheSgpLmNhdGNo
::B64:agent.js:KCgpID0+IHt9KTsKICAgIHJldHVybiB7IGVyciwgcGxheWluZzogISF2ICYmICF2LnBhdXNlZCAmJiB2LnJlYWR5U3RhdGUgPiAyIH07CiAgfSk7Cn0KCmFzeW5jIGZ1bmN0aW9uIGVuc3VyZVBsYXlpbmcoKSB7CiAgZm9yIChsZXQgYXR0ZW1wdCA9IDA7IGF0dGVt
::B64:agent.js:cHQgPCAyOyBhdHRlbXB0KyspIHsKICAgIGF3YWl0IHNsZWVwKDE4MDApOwogICAgYXdhaXQgc2tpcEFkcygpOwogICAgYXdhaXQgcmVhZFBsYXllclN0YXRlKCk7IC8vIG1lbWljdSBwbGF5KCkKICAgIGF3YWl0IHNsZWVwKDcwMCk7CiAgICBjb25zdCBzdCA9IGF3
::B64:agent.js:YWl0IHJlYWRQbGF5ZXJTdGF0ZSgpOwogICAgaWYgKHN0LnBsYXlpbmcpIHJldHVybiB0cnVlOwogICAgaWYgKHN0LmVycikgYXdhaXQgcGFnZS5yZWxvYWQoeyB3YWl0VW50aWw6ICJkb21jb250ZW50bG9hZGVkIiB9KTsKICB9CiAgcmV0dXJuIGZhbHNlOwp9Cgov
::B64:agent.js:LyA9PT09PSBQZW5jYXJpYW4gWW91VHViZSBjZXBhdCAodGFucGEgbWVtdWF0IGhhbGFtYW4gaGFzaWwgZGkgYnJvd3NlcikgPT09PT0KYXN5bmMgZnVuY3Rpb24geXRTZWFyY2hGYXN0KHF1ZXJ5KSB7CiAgY29uc3QgcmVzID0gYXdhaXQgZmV0Y2goImh0dHBzOi8v
::B64:agent.js:d3d3LnlvdXR1YmUuY29tL3Jlc3VsdHM/aGw9aWQmc2VhcmNoX3F1ZXJ5PSIgKyBlbmNvZGVVUklDb21wb25lbnQocXVlcnkpLCB7CiAgICBoZWFkZXJzOiB7CiAgICAgICJVc2VyLUFnZW50IjogIk1vemlsbGEvNS4wIChXaW5kb3dzIE5UIDEwLjA7IFdpbjY0OyB4
::B64:agent.js:NjQpIEFwcGxlV2ViS2l0LzUzNy4zNiAoS0hUTUwsIGxpa2UgR2Vja28pIENocm9tZS8xMjQuMCBTYWZhcmkvNTM3LjM2IiwKICAgICAgIkFjY2VwdC1MYW5ndWFnZSI6ICJpZC1JRCxpZDtxPTAuOSxlbjtxPTAuOCIsCiAgICB9LAogICAgc2lnbmFsOiBBYm9ydFNp
::B64:agent.js:Z25hbC50aW1lb3V0KDgwMDApLAogIH0pOwogIGlmICghcmVzLm9rKSB0aHJvdyBuZXcgRXJyb3IoIkhUVFAgIiArIHJlcy5zdGF0dXMpOwogIGNvbnN0IGh0bWwgPSBhd2FpdCByZXMudGV4dCgpOwogIGNvbnN0IG0gPSBodG1sLm1hdGNoKC95dEluaXRpYWxEYXRh
::B64:agent.js:XHMqPVxzKihcey4rP1x9KTtccyo8XC9zY3JpcHQ+L3MpOwogIGlmICghbSkgdGhyb3cgbmV3IEVycm9yKCJkYXRhIFlvdVR1YmUgdGlkYWsgZGl0ZW11a2FuIik7CiAgY29uc3QgZGF0YSA9IEpTT04ucGFyc2UobVsxXSk7CiAgY29uc3Qgb3V0ID0gW107CiAgY29u
::B64:agent.js:c3Qgd2FsayA9IChvKSA9PiB7CiAgICBpZiAoIW8gfHwgdHlwZW9mIG8gIT09ICJvYmplY3QiIHx8IG91dC5sZW5ndGggPj0gOCkgcmV0dXJuOwogICAgY29uc3QgdiA9IG8udmlkZW9SZW5kZXJlcjsKICAgIGlmICh2ICYmIHYudmlkZW9JZCkgewogICAgICBvdXQu
::B64:agent.js:cHVzaCh7CiAgICAgICAgaWQ6IHYudmlkZW9JZCwKICAgICAgICB0aXRsZTogKHYudGl0bGU/LnJ1bnMgfHwgW10pLm1hcCgocikgPT4gci50ZXh0KS5qb2luKCIiKSB8fCAiKHRhbnBhIGp1ZHVsKSIsCiAgICAgICAgY2hhbm5lbDogdi5vd25lclRleHQ/LnJ1bnM/
::B64:agent.js:LlswXT8udGV4dCB8fCAiIiwKICAgICAgfSk7CiAgICAgIHJldHVybjsKICAgIH0KICAgIGZvciAoY29uc3QgayBvZiBPYmplY3Qua2V5cyhvKSkgd2FsayhvW2tdKTsKICB9OwogIHdhbGsoZGF0YSk7CiAgcmV0dXJuIG91dDsKfQoKLy8gPT09PT0gVXBsb2FkIGNl
::B64:agent.js:cGF0ID09PT09CmNvbnN0IFVQTE9BRF9USU1FT1VUX01TID0gTnVtYmVyKHByb2Nlc3MuZW52LlVQTE9BRF9USU1FT1VUX01JTiB8fCAxNSkgKiA2MDAwMDsKY29uc3QgSE9TVFNfUkUgPSAvbWVkaWFmaXJlXC5jb21cLyhmaWxlfHZpZXd8ZG93bmxvYWR8Zm9sZGVy
::B64:agent.js:KXxkcml2ZVwuZ29vZ2xlXC5jb21cLyhmaWxlfGRyaXZlXC9mb2xkZXJzKXx3ZXRyYW5zZmVyXC5jb21cL2Rvd25sb2Fkc3x3ZVwudGxcL3xnb2ZpbGVcLmlvXC9kXC98cGl4ZWxkcmFpblwuY29tXC91XC98ZmlsZXNcLmNhdGJveFwubW9lfGNhdGJveFwubW9lXC98
::B64:agent.js:ZmlsZVwuaW9cL3xzZW5kc3BhY2VcLmNvbVwvZmlsZXx0cmFuc2Zlclwuc2hcL3x0bXBmaWxlc1wub3JnXC9cZHxkcm9wYm94XC5jb21cL3N8bWVnYVwubnpcLyhmaWxlfGZvbGRlcil8MWRydlwubXN8ZmlsZWJpblwubmV0XC9cd3x1cGxvYWRoYXZlbnxiYXlmaWxl
::B64:agent.js:cy9pOwpjb25zdCBVUExPQURfQlROID0gL15ccyoodXBsb2FkfHVuZ2dhaHxtZW5ndW5nZ2FofHRhbWJhaChrYW4pPyBmaWxlfGFkZCBmaWxlcz98c2VsZWN0IGZpbGVzP3xjaG9vc2UgZmlsZXM/fHBpbGloIGZpbGV8YnJvd3NlfHRlbHVzdXJpKVxiL2k7CmNvbnN0
::B64:agent.js:IFNVQk1JVF9CVE4gPSAvXlxzKihiZWdpbiB1cGxvYWR8c3RhcnQgdXBsb2FkfHVwbG9hZCggbm93fCBmaWxlcz8pP3x1bmdnYWgoIHNla2FyYW5nKT98bXVsYWkoIHVwbG9hZHwgdW5nZ2FoKT98a2lyaW18c2VuZHxzdWJtaXR8c2VsZXNhaXxkb25lfGxhbmp1dHxj
::B64:agent.js:b250aW51ZSlccyokL2k7Cgphc3luYyBmdW5jdGlvbiBmaW5kRmlsZUlucHV0QW55KHRpbWVvdXRNcyA9IDApIHsKICBjb25zdCBkZWFkbGluZSA9IERhdGUubm93KCkgKyB0aW1lb3V0TXM7CiAgZG8gewogICAgZm9yIChjb25zdCBmciBvZiBwYWdlLmZyYW1lcygp
::B64:agent.js:KSB7CiAgICAgIGNvbnN0IGggPSBhd2FpdCBmci4kKCJpbnB1dFt0eXBlPWZpbGVdIikuY2F0Y2goKCkgPT4gbnVsbCk7CiAgICAgIGlmIChoKSByZXR1cm4gaDsKICAgIH0KICAgIGlmICh0aW1lb3V0TXMpIGF3YWl0IHNsZWVwKDIwMCk7CiAgfSB3aGlsZSAoRGF0
::B64:agent.js:ZS5ub3coKSA8IGRlYWRsaW5lKTsKICByZXR1cm4gbnVsbDsKfQoKYXN5bmMgZnVuY3Rpb24gaGFzTG9naW5Gb3JtKCkgewogIGZvciAoY29uc3QgZnIgb2YgcGFnZS5mcmFtZXMoKSkgewogICAgY29uc3QgcHcgPSBhd2FpdCBmci4kKCJpbnB1dFt0eXBlPXBhc3N3
::B64:agent.js:b3JkXSIpLmNhdGNoKCgpID0+IG51bGwpOwogICAgaWYgKHB3ICYmIChhd2FpdCBwdy5pc1Zpc2libGUoKS5jYXRjaCgoKSA9PiBmYWxzZSkpKSByZXR1cm4gdHJ1ZTsKICB9CiAgcmV0dXJuIGZhbHNlOwp9Cgphc3luYyBmdW5jdGlvbiBjbGlja0J5VGV4dChyZSwg
::B64:agent.js:dGltZW91dCA9IDE1MDApIHsKICBjb25zdCBncm91cHMgPSBbcGFnZS5nZXRCeVJvbGUoImJ1dHRvbiIsIHsgbmFtZTogcmUgfSksIHBhZ2UuZ2V0QnlSb2xlKCJsaW5rIiwgeyBuYW1lOiByZSB9KSwgcGFnZS5nZXRCeVRleHQocmUpXTsKICBmb3IgKGNvbnN0IGcg
::B64:agent.js:b2YgZ3JvdXBzKSB7CiAgICBjb25zdCBuID0gTWF0aC5taW4oYXdhaXQgZy5jb3VudCgpLmNhdGNoKCgpID0+IDApLCA1KTsKICAgIGZvciAobGV0IGkgPSAwOyBpIDwgbjsgaSsrKSB7CiAgICAgIGNvbnN0IGVsID0gZy5udGgoaSk7CiAgICAgIGlmICghKGF3YWl0
::B64:agent.js:IGVsLmlzVmlzaWJsZSgpLmNhdGNoKCgpID0+IGZhbHNlKSkpIGNvbnRpbnVlOwogICAgICB0cnkgewogICAgICAgIGNvbnN0IGxhYmVsID0gKChhd2FpdCBlbC5pbm5lclRleHQoeyB0aW1lb3V0OiA0MDAgfSkuY2F0Y2goKCkgPT4gIiIpKSB8fCAiIikudHJpbSgp
::B64:agent.js:LnNsaWNlKDAsIDQwKTsKICAgICAgICBhd2FpdCBlbC5jbGljayh7IHRpbWVvdXQgfSk7CiAgICAgICAgcmV0dXJuIGxhYmVsIHx8ICIodG9tYm9sKSI7CiAgICAgIH0gY2F0Y2gge30KICAgIH0KICB9CiAgcmV0dXJuICIiOwp9CgovLyBLbGlrIHRvbWJvbCAiVXBs
::B64:agent.js:b2FkIiBsYWx1IHRhbmdrYXAgZGlhbG9nIHBpbGloIGZpbGUgQVRBVSBpbnB1dCBmaWxlIHlhbmcgbXVuY3VsCmFzeW5jIGZ1bmN0aW9uIG9wZW5VcGxvYWRlcihxdWV1ZSkgewogIGNvbnN0IGdyb3VwcyA9IFtwYWdlLmdldEJ5Um9sZSgiYnV0dG9uIiwgeyBuYW1l
::B64:agent.js:OiBVUExPQURfQlROIH0pLCBwYWdlLmdldEJ5Um9sZSgibGluayIsIHsgbmFtZTogVVBMT0FEX0JUTiB9KSwgcGFnZS5nZXRCeVRleHQoVVBMT0FEX0JUTildOwogIGZvciAoY29uc3QgZyBvZiBncm91cHMpIHsKICAgIGNvbnN0IG4gPSBNYXRoLm1pbihhd2FpdCBn
::B64:agent.js:LmNvdW50KCkuY2F0Y2goKCkgPT4gMCksIDQpOwogICAgZm9yIChsZXQgaSA9IDA7IGkgPCBuOyBpKyspIHsKICAgICAgY29uc3QgZWwgPSBnLm50aChpKTsKICAgICAgaWYgKCEoYXdhaXQgZWwuaXNWaXNpYmxlKCkuY2F0Y2goKCkgPT4gZmFsc2UpKSkgY29udGlu
::B64:agent.js:dWU7CiAgICAgIGNvbnN0IGNob29zZXJQID0gcGFnZS53YWl0Rm9yRXZlbnQoImZpbGVjaG9vc2VyIiwgeyB0aW1lb3V0OiAyMDAwIH0pLmNhdGNoKCgpID0+IG51bGwpOwogICAgICB0cnkgewogICAgICAgIGF3YWl0IGVsLmNsaWNrKHsgdGltZW91dDogMTUwMCB9
::B64:agent.js:KTsKICAgICAgfSBjYXRjaCB7CiAgICAgICAgY29udGludWU7CiAgICAgIH0KICAgICAgY29uc3QgY2hvb3NlciA9IGF3YWl0IGNob29zZXJQOwogICAgICBpZiAoY2hvb3NlcikgewogICAgICAgIGNvbnN0IGJhdGNoID0gY2hvb3Nlci5pc011bHRpcGxlKCkgPyBx
::B64:agent.js:dWV1ZSA6IFtxdWV1ZVswXV07CiAgICAgICAgYXdhaXQgY2hvb3Nlci5zZXRGaWxlcyhiYXRjaCk7CiAgICAgICAgcmV0dXJuIHsgdXNlZDogYmF0Y2gubGVuZ3RoIH07CiAgICAgIH0KICAgICAgY29uc3QgaW5wdXQgPSBhd2FpdCBmaW5kRmlsZUlucHV0QW55KDEy
::B64:agent.js:MDApOwogICAgICBpZiAoaW5wdXQpIHJldHVybiB7IGlucHV0IH07CiAgICB9CiAgfQogIHJldHVybiBudWxsOwp9CgovLyBNYXN1a2thbiBmaWxlIGtlIGhhbGFtYW4uIE1lbmdlbWJhbGlrYW4ganVtbGFoIGZpbGUgeWFuZyBkaXBha2FpICgwID0gZ2FnYWwpCmFz
::B64:agent.js:eW5jIGZ1bmN0aW9uIHByb3ZpZGVGaWxlcyhxdWV1ZSkgewogIGxldCBpbnB1dCA9IGF3YWl0IGZpbmRGaWxlSW5wdXRBbnkoMTIwMCk7CiAgaWYgKCFpbnB1dCkgewogICAgY29uc3QgciA9IGF3YWl0IG9wZW5VcGxvYWRlcihxdWV1ZSk7CiAgICBpZiAociAmJiBy
::B64:agent.js:LnVzZWQpIHJldHVybiByLnVzZWQ7CiAgICBpbnB1dCA9IHIgJiYgci5pbnB1dDsKICB9CiAgaWYgKCFpbnB1dCkgcmV0dXJuIDA7CiAgY29uc3QgbXVsdGlwbGUgPSBhd2FpdCBpbnB1dC5ldmFsdWF0ZSgoZWwpID0+ICEhZWwubXVsdGlwbGUpLmNhdGNoKCgpID0+
::B64:agent.js:IGZhbHNlKTsKICBjb25zdCBiYXRjaCA9IG11bHRpcGxlID8gcXVldWUgOiBbcXVldWVbMF1dOwogIGF3YWl0IGlucHV0LnNldElucHV0RmlsZXMoYmF0Y2gpOwogIHJldHVybiBiYXRjaC5sZW5ndGg7Cn0KCmZ1bmN0aW9uIHRyYWNrVXBsb2FkcygpIHsKICBsZXQg
::B64:agent.js:cGVuZGluZyA9IDA7CiAgbGV0IHNlZW4gPSAwOwogIGNvbnN0IGlzVXAgPSAocikgPT4gWyJQT1NUIiwgIlBVVCIsICJQQVRDSCJdLmluY2x1ZGVzKHIubWV0aG9kKCkpOwogIGNvbnN0IG9uUmVxID0gKHIpID0+IHsKICAgIGlmIChpc1VwKHIpKSB7CiAgICAgIHBl
::B64:agent.js:bmRpbmcrKzsKICAgICAgc2VlbisrOwogICAgfQogIH07CiAgY29uc3Qgb25Eb25lID0gKHIpID0+IHsKICAgIGlmIChpc1VwKHIpKSBwZW5kaW5nID0gTWF0aC5tYXgoMCwgcGVuZGluZyAtIDEpOwogIH07CiAgY29udGV4dC5vbigicmVxdWVzdCIsIG9uUmVxKTsK
::B64:agent.js:ICBjb250ZXh0Lm9uKCJyZXF1ZXN0ZmluaXNoZWQiLCBvbkRvbmUpOwogIGNvbnRleHQub24oInJlcXVlc3RmYWlsZWQiLCBvbkRvbmUpOwogIHJldHVybiB7CiAgICBnZXQgcGVuZGluZygpIHsKICAgICAgcmV0dXJuIHBlbmRpbmc7CiAgICB9LAogICAgZ2V0IHNl
::B64:agent.js:ZW4oKSB7CiAgICAgIHJldHVybiBzZWVuOwogICAgfSwKICAgIHN0b3AoKSB7CiAgICAgIGNvbnRleHQub2ZmKCJyZXF1ZXN0Iiwgb25SZXEpOwogICAgICBjb250ZXh0Lm9mZigicmVxdWVzdGZpbmlzaGVkIiwgb25Eb25lKTsKICAgICAgY29udGV4dC5vZmYoInJl
::B64:agent.js:cXVlc3RmYWlsZWQiLCBvbkRvbmUpOwogICAgfSwKICB9Owp9CgovLyB0cnVlID0gc2VsZXNhaSwgc3RyaW5nID0gc2VsZXNhaSBkZW5nYW4gY2F0YXRhbiwgZmFsc2UgPSB3YWt0dSBoYWJpcwphc3luYyBmdW5jdGlvbiB3YWl0VXBsb2FkRG9uZSh0ciwgbWF4TXMp
::B64:agent.js:IHsKICBjb25zdCB0MCA9IERhdGUubm93KCk7CiAgbGV0IHF1aWV0ID0gMDsKICB3aGlsZSAoRGF0ZS5ub3coKSAtIHQwIDwgbWF4TXMpIHsKICAgIGF3YWl0IHNsZWVwKDYwMCk7CiAgICBjb25zdCBidXN5ID0gYXdhaXQgcGFnZQogICAgICAuZXZhbHVhdGUoKCkg
::B64:agent.js:PT4gewogICAgICAgIGNvbnN0IHZpcyA9IChlKSA9PiBlLm9mZnNldFBhcmVudCAhPT0gbnVsbDsKICAgICAgICBjb25zdCBiYXJzID0gWy4uLmRvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoInByb2dyZXNzLCBbcm9sZT1wcm9ncmVzc2Jhcl0iKV0uZmlsdGVyKHZp
::B64:agent.js:cyk7CiAgICAgICAgY29uc3QgdCA9IGRvY3VtZW50LmJvZHkgPyBkb2N1bWVudC5ib2R5LmlubmVyVGV4dCA6ICIiOwogICAgICAgIGNvbnN0IGluUHJvZ3Jlc3MgPSAvXGIodXBsb2FkaW5nfG1lbmd1bmdnYWh8c2VkYW5nIG1lbmd1bmdnYWh8dXBsb2FkIGluIHBy
::B64:agent.js:b2dyZXNzfG1lbXByb3Nlc3xwcm9jZXNzaW5nKVxiL2kudGVzdCh0KTsKICAgICAgICBjb25zdCB1bmZpbmlzaGVkID0gYmFycy5zb21lKChiKSA9PiB7CiAgICAgICAgICBjb25zdCB2ID0gYi5nZXRBdHRyaWJ1dGUoImFyaWEtdmFsdWVub3ciKSA/PyBiLnZhbHVl
::B64:agent.js:OwogICAgICAgICAgY29uc3QgbXggPSBiLmdldEF0dHJpYnV0ZSgiYXJpYS12YWx1ZW1heCIpID8/IGIubWF4ID8/IDEwMDsKICAgICAgICAgIHJldHVybiB2ID09IG51bGwgfHwgTnVtYmVyKHYpIDwgTnVtYmVyKG14KTsKICAgICAgICB9KTsKICAgICAgICByZXR1
::B64:agent.js:cm4gdW5maW5pc2hlZCB8fCBpblByb2dyZXNzOwogICAgICB9KQogICAgICAuY2F0Y2goKCkgPT4gZmFsc2UpOwogICAgaWYgKHRyLnBlbmRpbmcgPT09IDAgJiYgIWJ1c3kpIHsKICAgICAgcXVpZXQrKzsKICAgICAgaWYgKHF1aWV0ID49IDMgJiYgdHIuc2VlbiA+
::B64:agent.js:IDApIHJldHVybiB0cnVlOwogICAgICBpZiAocXVpZXQgPj0gOCkgcmV0dXJuIHRyLnNlZW4gPiAwID8gdHJ1ZSA6ICJ0aWRhayBhZGEgYWt0aXZpdGFzIHVwbG9hZCB0ZXJkZXRla3NpLCBwZXJpa3NhIGhhbGFtYW4iOwogICAgfSBlbHNlIHsKICAgICAgcXVpZXQg
::B64:agent.js:PSAwOwogICAgfQogIH0KICByZXR1cm4gZmFsc2U7Cn0KCi8vIEZvbGRlciBkaWtpcmltIHNlYmFnYWkgemlwLiBQYWthaSB0YXIgYmF3YWFuIFdpbmRvd3MgKGNlcGF0KTsgY2FkYW5nYW46IENvbXByZXNzLUFyY2hpdmUKYXN5bmMgZnVuY3Rpb24gemlwRm9yVXBs
::B64:agent.js:b2FkKGRpcikgewogIGNvbnN0IHppcCA9IHBhdGguam9pbihvcy50bXBkaXIoKSwgcGF0aC5iYXNlbmFtZShkaXIpICsgIi56aXAiKTsKICB0cnkgewogICAgZnMucm1TeW5jKHppcCwgeyBmb3JjZTogdHJ1ZSB9KTsKICB9IGNhdGNoIHt9CiAgY29uc3QgdmlhVGFy
::B64:agent.js:ID0gYXdhaXQgbmV3IFByb21pc2UoKHJlc29sdmUpID0+IHsKICAgIGV4ZWNGaWxlKCJ0YXIiLCBbIi1hIiwgIi1jIiwgIi1mIiwgemlwLCAiLUMiLCBwYXRoLmRpcm5hbWUoZGlyKSwgcGF0aC5iYXNlbmFtZShkaXIpXSwgeyB0aW1lb3V0OiA5MDAwMDAgfSwgKGVy
::B64:agent.js:cikgPT4gcmVzb2x2ZSghZXJyKSk7CiAgfSk7CiAgaWYgKCF2aWFUYXIpIHsKICAgIGF3YWl0IHBzKCJDb21wcmVzcy1BcmNoaXZlIC1MaXRlcmFsUGF0aCAkZW52OlNSQyAtRGVzdGluYXRpb25QYXRoICRlbnY6REVTVCAtRm9yY2UiLCB7IFNSQzogZGlyLCBERVNU
::B64:agent.js:OiB6aXAgfSwgOTAwMDAwKTsKICB9CiAgcmV0dXJuIHppcDsKfQoKZnVuY3Rpb24gcmVjZW50TGlzdChkaXIsIGNvdW50ID0gMTApIHsKICBjb25zdCBiYWQgPSAvXC4oY3Jkb3dubG9hZHx0bXB8cGFydHxkb3dubG9hZHxwYXJ0aWFsKSQvaTsKICBjb25zdCBpdGVt
::B64:agent.js:cyA9IFtdOwogIGZvciAoY29uc3QgZSBvZiBmcy5yZWFkZGlyU3luYyhkaXIsIHsgd2l0aEZpbGVUeXBlczogdHJ1ZSB9KSkgewogICAgaWYgKCFlLmlzRmlsZSgpIHx8IGJhZC50ZXN0KGUubmFtZSkpIGNvbnRpbnVlOwogICAgY29uc3QgZiA9IHBhdGguam9pbihk
::B64:agent.js:aXIsIGUubmFtZSk7CiAgICB0cnkgewogICAgICBjb25zdCBzdCA9IGZzLnN0YXRTeW5jKGYpOwogICAgICBpdGVtcy5wdXNoKHsgZiwgdDogc3QubXRpbWVNcywgczogc3Quc2l6ZSB9KTsKICAgIH0gY2F0Y2gge30KICB9CiAgcmV0dXJuIGl0ZW1zLnNvcnQoKGEs
::B64:agent.js:IGIpID0+IGIudCAtIGEudCkuc2xpY2UoMCwgTWF0aC5taW4oTWF0aC5tYXgoTnVtYmVyKGNvdW50KSB8fCAxMCwgMSksIDUwKSk7Cn0KCmNvbnN0IHRpbWVycyA9IFtdOwpjb25zdCBTQUZFX1BBUkFMTEVMID0gbmV3IFNldChbCiAgImZpbmRfZm9sZGVyIiwgImZp
::B64:agent.js:bmRfZmlsZSIsICJsaXN0X2RpciIsICJyZWFkX3RleHRfZmlsZSIsICJzeXN0ZW1faW5mbyIsICJub3ciLCAiY2xpcGJvYXJkX2dldCIsCiAgImxpc3RfdGFicyIsICJsaXN0X3dpbmRvd3MiLCAicmVjZW50X2ZpbGVzIiwgInNlYXJjaF90ZXh0IiwgImxpc3RfZmls
::B64:agent.js:ZXMiLCAibGlzdF9wcm9jZXNzZXMiLApdKTsKCmNvbnN0IGltcGwgPSB7CiAgLy8gLS0tIERlc2t0b3A6IGZpbGUgJiBmb2xkZXIgLS0tCiAgZmluZF9mb2xkZXI6IGFzeW5jICh7IG5hbWUgfSkgPT4gc2VhcmNoRXZlcnl3aGVyZShuYW1lLCBmYWxzZSksCgogIGZp
::B64:agent.js:bmRfZmlsZTogYXN5bmMgKHsgbmFtZSB9KSA9PiBzZWFyY2hFdmVyeXdoZXJlKG5hbWUsIHRydWUpLAoKICBsaXN0X2RpcjogYXN5bmMgKHsgcGF0aDogcCB9KSA9PiB7CiAgICBjb25zdCBpdGVtcyA9IGZzLnJlYWRkaXJTeW5jKHAsIHsgd2l0aEZpbGVUeXBlczog
::B64:agent.js:dHJ1ZSB9KS5zbGljZSgwLCAxMDApOwogICAgcmV0dXJuIGl0ZW1zLm1hcCgoZSkgPT4gKGUuaXNEaXJlY3RvcnkoKSA/ICJbRElSXSAiIDogIltGSUxFXSAiKSArIGUubmFtZSkuam9pbigiXG4iKSB8fCAiKGtvc29uZykiOwogIH0sCgogIG9wZW5fcGF0aDogYXN5
::B64:agent.js:bmMgKHsgdGFyZ2V0IH0pID0+IHsKICAgIGlmICgvXlxzKih0YXNra2lsbHxzaHV0ZG93bnxkZWx8ZXJhc2V8cmR8cm1kaXJ8Zm9ybWF0fHJlZ3xuZXR8c2N8d21pY3xwb3dlcnNoZWxsfGNtZFxzK1wvYylcYi9pLnRlc3QoU3RyaW5nKHRhcmdldCkpKSB7CiAgICAg
::B64:agent.js:IHRocm93IG5ldyBFcnJvcigib3Blbl9wYXRoIGhhbnlhIHVudHVrIG1lbWJ1a2EgZm9sZGVyL2ZpbGUvYXBsaWthc2kvVVJMLiBVbnR1ayBtZW51dHVwIGFwbGlrYXNpIGF0YXUgZ2FtZSBndW5ha2FuIGtpbGxfcHJvY2Vzcy4iKTsKICAgIH0KICAgIGlmICghKGF3
::B64:agent.js:YWl0IGFzayhgQnVrYTogJHt0YXJnZXR9YCkpKSByZXR1cm4gIkRpYmF0YWxrYW4gdXNlciI7CiAgICBhd2FpdCBwcygiU3RhcnQtUHJvY2VzcyAtRmlsZVBhdGggJGVudjpUQVJHRVQiLCB7IFRBUkdFVDogU3RyaW5nKHRhcmdldCkgfSk7CiAgICBhd2FpdCBzbGVl
::B64:agent.js:cCg4MDApOwogICAgcmV0dXJuICJvaywgZGlidWthIjsKICB9LAoKICAvLyAtLS0gRGVza3RvcDogbGF5YXIsIG1vdXNlLCBrZXlib2FyZCAtLS0KICBzY3JlZW5zaG90OiBhc3luYyAoKSA9PiB7CiAgICBjb25zdCBvdXQgPSBwYXRoLnJlc29sdmUoInNjcmVlbi5w
::B64:agent.js:bmciKTsKICAgIGNvbnN0IHIgPSBhd2FpdCBwcygKICAgICAgUFNfSEVBRCArCiAgICAgICAgYAokYiA9IFtTeXN0ZW0uV2luZG93cy5Gb3Jtcy5TY3JlZW5dOjpQcmltYXJ5U2NyZWVuLkJvdW5kcwokYm1wID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5CaXRt
::B64:agent.js:YXAgJGIuV2lkdGgsICRiLkhlaWdodAokZyA9IFtTeXN0ZW0uRHJhd2luZy5HcmFwaGljc106OkZyb21JbWFnZSgkYm1wKQokZy5Db3B5RnJvbVNjcmVlbigkYi5YLCAkYi5ZLCAwLCAwLCAkYm1wLlNpemUpCiRudyA9IFtNYXRoXTo6TWluKDEyODAsICRiLldpZHRo
::B64:agent.js:KQokbmggPSBbaW50XSgkYi5IZWlnaHQgKiAkbncgLyAkYi5XaWR0aCkKJHNtYWxsID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5CaXRtYXAgJGJtcCwgJG53LCAkbmgKJHNtYWxsLlNhdmUoJGVudjpPVVQsIFtTeXN0ZW0uRHJhd2luZy5JbWFnaW5nLkltYWdl
::B64:agent.js:Rm9ybWF0XTo6UG5nKQpXcml0ZS1PdXRwdXQgIiQoJGIuV2lkdGgpLCRudywkbmgiCmAsCiAgICAgIHsgT1VUOiBvdXQgfQogICAgKTsKICAgIGNvbnN0IFt3LCBudywgbmhdID0gci5zcGxpdCgiXG4iKS5wb3AoKS5zcGxpdCgiLCIpLm1hcChOdW1iZXIpOwogICAg
::B64:agent.js:c2NhbGUgPSB3IC8gbnc7CiAgICBwZW5kaW5nSW1hZ2VzLnB1c2goZnMucmVhZEZpbGVTeW5jKG91dCkudG9TdHJpbmcoImJhc2U2NCIpKTsKICAgIHJldHVybiBgU2NyZWVuc2hvdCBkaWFtYmlsICgke253fXgke25ofSkuIEdhbWJhcm55YSBhZGEgZGkgcGVzYW4g
::B64:agent.js:YmVyaWt1dG55YS4gUGFrYWkga29vcmRpbmF0IGRhcmkgZ2FtYmFyIGl0dS5gOwogIH0sCgogIGNsaWNrX3NjcmVlbjogYXN5bmMgKHsgeCwgeSwgYnV0dG9uID0gImxlZnQiLCBkb3VibGUgPSBmYWxzZSB9KSA9PiB7CiAgICBjb25zdCByeCA9IE1hdGgucm91bmQo
::B64:agent.js:TnVtYmVyKHgpICogc2NhbGUpOwogICAgY29uc3QgcnkgPSBNYXRoLnJvdW5kKE51bWJlcih5KSAqIHNjYWxlKTsKICAgIGNvbnN0IGRibCA9IGRvdWJsZSA9PT0gdHJ1ZSB8fCBkb3VibGUgPT09ICJ0cnVlIjsKICAgIGlmICghKGF3YWl0IGFzayhgJHtkYmwgPyAi
::B64:agent.js:RG91YmxlLWtsaWsiIDogIktsaWsifSAke2J1dHRvbn0gZGkgKCR7eH0sJHt5fSlgKSkpIHJldHVybiAiRGliYXRhbGthbiB1c2VyIjsKICAgIGF3YWl0IHBzKAogICAgICBQU19IRUFEICsKICAgICAgICBgCltXXTo6U2V0Q3Vyc29yUG9zKFtpbnRdJGVudjpYLCBb
::B64:agent.js:aW50XSRlbnY6WSkgfCBPdXQtTnVsbApTdGFydC1TbGVlcCAtTWlsbGlzZWNvbmRzIDE1MAokZG93biA9IDI7ICR1cCA9IDQKaWYgKCRlbnY6QlROIC1lcSAicmlnaHQiKSB7ICRkb3duID0gODsgJHVwID0gMTYgfQpmb3IgKCRpID0gMDsgJGkgLWx0IFtpbnRdJGVu
::B64:agent.js:djpDT1VOVDsgJGkrKykgewogIFtXXTo6bW91c2VfZXZlbnQoJGRvd24sIDAsIDAsIDAsIFtVSW50UHRyXTo6WmVybykKICBbV106Om1vdXNlX2V2ZW50KCR1cCwgMCwgMCwgMCwgW1VJbnRQdHJdOjpaZXJvKQogIFN0YXJ0LVNsZWVwIC1NaWxsaXNlY29uZHMgODAK
::B64:agent.js:fQpgLAogICAgICB7IFg6IFN0cmluZyhyeCksIFk6IFN0cmluZyhyeSksIEJUTjogU3RyaW5nKGJ1dHRvbiksIENPVU5UOiBkYmwgPyAiMiIgOiAiMSIgfQogICAgKTsKICAgIGF3YWl0IHNsZWVwKDM1MCk7CiAgICByZXR1cm4gIm9rLCBkaWtsaWsiOwogIH0sCgog
::B64:agent.js:IHNjcm9sbF9zY3JlZW46IGFzeW5jICh7IGFtb3VudCB9KSA9PiB7CiAgICBjb25zdCBkZWx0YSA9IC0xMjAgKiBNYXRoLnJvdW5kKE51bWJlcihhbW91bnQpKTsgLy8gcG9zaXRpZiA9IHR1cnVuCiAgICBpZiAoIShhd2FpdCBhc2soYFNjcm9sbCAke2Ftb3VudCA+
::B64:agent.js:IDAgPyAidHVydW4iIDogIm5haWsifSAke01hdGguYWJzKGFtb3VudCl9eGApKSkgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgYXdhaXQgcHMoUFNfSEVBRCArIGBbV106Om1vdXNlX2V2ZW50KDB4MDgwMCwgMCwgMCwgW2ludF0kZW52OkQsIFtVSW50UHRy
::B64:agent.js:XTo6WmVybylgLCB7IEQ6IFN0cmluZyhkZWx0YSkgfSk7CiAgICBhd2FpdCBzbGVlcCgyNTApOwogICAgcmV0dXJuICJvayI7CiAgfSwKCiAgdHlwZV9kZXNrdG9wOiBhc3luYyAoeyB0ZXh0IH0pID0+IHsKICAgIGlmICghKGF3YWl0IGFzayhgS2V0aWs6ICIke1N0
::B64:agent.js:cmluZyh0ZXh0KS5zbGljZSgwLCA2MCl9ImApKSkgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgYXdhaXQgcHMoCiAgICAgIFBTX0hFQUQgKwogICAgICAgIGAKU2V0LUNsaXBib2FyZCAtVmFsdWUgJGVudjpUWFQKU3RhcnQtU2xlZXAgLU1pbGxpc2Vjb25k
::B64:agent.js:cyAxNTAKW1N5c3RlbS5XaW5kb3dzLkZvcm1zLlNlbmRLZXlzXTo6U2VuZFdhaXQoIl52IikKYCwKICAgICAgeyBUWFQ6IFN0cmluZyh0ZXh0KSB9CiAgICApOwogICAgYXdhaXQgc2xlZXAoMjUwKTsKICAgIHJldHVybiAib2ssIGRpa2V0aWsiOwogIH0sCgogIHBy
::B64:agent.js:ZXNzX2tleXM6IGFzeW5jICh7IGtleXMgfSkgPT4gewogICAgaWYgKCEoYXdhaXQgYXNrKGBUZWthbiB0b21ib2w6ICR7a2V5c31gKSkpIHJldHVybiAiRGliYXRhbGthbiB1c2VyIjsKICAgIGF3YWl0IHBzKFBTX0hFQUQgKyBgW1N5c3RlbS5XaW5kb3dzLkZvcm1z
::B64:agent.js:LlNlbmRLZXlzXTo6U2VuZFdhaXQoJGVudjpLRVlTKWAsIHsgS0VZUzogU3RyaW5nKGtleXMpIH0pOwogICAgYXdhaXQgc2xlZXAoMjUwKTsKICAgIHJldHVybiAib2siOwogIH0sCgogIHdhaXQ6IGFzeW5jICh7IHNlY29uZHMgfSkgPT4gewogICAgYXdhaXQgc2xl
::B64:agent.js:ZXAoTWF0aC5taW4oTnVtYmVyKHNlY29uZHMpIHx8IDEsIDE1KSAqIDEwMDApOwogICAgcmV0dXJuICJvayI7CiAgfSwKCiAgLy8gLS0tIEJyb3dzZXIgKFBsYXl3cmlnaHQpIC0tLQogIGxpc3RfZmlsZXM6IGFzeW5jICgpID0+IGZzLnJlYWRkaXJTeW5jKFNBRkVf
::B64:agent.js:RElSKS5qb2luKCJcbiIpIHx8ICIoZm9sZGVyIHVwbG9hZCBrb3NvbmcpIiwKCiAgb3Blbl91cmw6IGFzeW5jICh7IHVybCwgbmV3X3RhYiA9IGZhbHNlIH0pID0+IHsKICAgIGlmIChpc1RydWUobmV3X3RhYikpIHBhZ2UgPSBhd2FpdCBjb250ZXh0Lm5ld1BhZ2Uo
::B64:agent.js:KTsKICAgIGF3YWl0IHBhZ2UuYnJpbmdUb0Zyb250KCk7CiAgICBhd2FpdCBwYWdlLmdvdG8oZml4VXJsKHVybCksIHsgd2FpdFVudGlsOiAiZG9tY29udGVudGxvYWRlZCIgfSk7CiAgICByZXR1cm4gIlRlcmJ1a2E6ICIgKyAoYXdhaXQgcGFnZS50aXRsZSgpKSAr
::B64:agent.js:IChpc1RydWUobmV3X3RhYikgPyAiIChkaSB0YWIgYmFydSkiIDogIiIpOwogIH0sCgogIC8vIC0tLSBUYWIgLS0tCiAgbGlzdF90YWJzOiBhc3luYyAoKSA9PiB0YWJzU3VtbWFyeSgpLAoKICBuZXdfdGFiOiBhc3luYyAoeyB1cmwgfSkgPT4gewogICAgcGFnZSA9
::B64:agent.js:IGF3YWl0IGNvbnRleHQubmV3UGFnZSgpOwogICAgYXdhaXQgcGFnZS5icmluZ1RvRnJvbnQoKTsKICAgIGlmICh1cmwpIGF3YWl0IHBhZ2UuZ290byhmaXhVcmwodXJsKSwgeyB3YWl0VW50aWw6ICJkb21jb250ZW50bG9hZGVkIiB9KTsKICAgIHJldHVybiAiVGFi
::B64:agent.js:IGJhcnUgZGlidWthIGRhbiBqYWRpIHRhYiBha3RpZi5cbiIgKyAoYXdhaXQgdGFic1N1bW1hcnkoKSk7CiAgfSwKCiAgb3Blbl91cmxzOiBhc3luYyAoeyB1cmxzIH0pID0+IHsKICAgIGNvbnN0IGxpc3QgPSAoQXJyYXkuaXNBcnJheSh1cmxzKSA/IHVybHMgOiBT
::B64:agent.js:dHJpbmcodXJscykuc3BsaXQoL1tcbiw7fF0rLykpCiAgICAgIC5tYXAoKHgpID0+IFN0cmluZyh4KS50cmltKCkpCiAgICAgIC5maWx0ZXIoQm9vbGVhbikKICAgICAgLnNsaWNlKDAsIDEwKTsKICAgIGlmICghbGlzdC5sZW5ndGgpIHRocm93IG5ldyBFcnJvcigi
::B64:agent.js:VGlkYWsgYWRhIFVSTCIpOwogICAgY29uc3QgZ2FnYWwgPSBbXTsKICAgIGZvciAoY29uc3QgdSBvZiBsaXN0KSB7CiAgICAgIHBhZ2UgPSBhd2FpdCBjb250ZXh0Lm5ld1BhZ2UoKTsKICAgICAgdHJ5IHsKICAgICAgICBhd2FpdCBwYWdlLmdvdG8oZml4VXJsKHUp
::B64:agent.js:LCB7IHdhaXRVbnRpbDogImRvbWNvbnRlbnRsb2FkZWQiLCB0aW1lb3V0OiAzMDAwMCB9KTsKICAgICAgfSBjYXRjaCAoZSkgewogICAgICAgIGdhZ2FsLnB1c2godSk7CiAgICAgIH0KICAgIH0KICAgIHJldHVybiBgJHtsaXN0Lmxlbmd0aCAtIGdhZ2FsLmxlbmd0
::B64:agent.js:aH0gdGFiIGRpYnVrYSR7Z2FnYWwubGVuZ3RoID8gYCwgZ2FnYWw6ICR7Z2FnYWwuam9pbigiLCAiKX1gIDogIiJ9LlxuYCArIChhd2FpdCB0YWJzU3VtbWFyeSgpKTsKICB9LAoKICBzd2l0Y2hfdGFiOiBhc3luYyAoeyBpbmRleCwgbWF0Y2ggfSkgPT4gewogICAg
::B64:agent.js:Y29uc3QgYWxsID0gbGl2ZVBhZ2VzKCk7CiAgICBsZXQgdGFyZ2V0OwogICAgaWYgKG1hdGNoKSB7CiAgICAgIGNvbnN0IHEgPSBTdHJpbmcobWF0Y2gpLnRvTG93ZXJDYXNlKCk7CiAgICAgIGZvciAoY29uc3QgeCBvZiBhbGwpIHsKICAgICAgICBjb25zdCB0ID0g
::B64:agent.js:KChhd2FpdCB4LnRpdGxlKCkuY2F0Y2goKCkgPT4gIiIpKSArICIgIiArIHgudXJsKCkpLnRvTG93ZXJDYXNlKCk7CiAgICAgICAgaWYgKHQuaW5jbHVkZXMocSkpIHsKICAgICAgICAgIHRhcmdldCA9IHg7CiAgICAgICAgICBicmVhazsKICAgICAgICB9CiAgICAg
::B64:agent.js:IH0KICAgIH0gZWxzZSB7CiAgICAgIHRhcmdldCA9IHBpY2tUYWIoYWxsLCBpbmRleCk7CiAgICB9CiAgICBpZiAoIXRhcmdldCkgdGhyb3cgbmV3IEVycm9yKCJUYWIgdGlkYWsgZGl0ZW11a2FuLlxuIiArIChhd2FpdCB0YWJzU3VtbWFyeSgpKSk7CiAgICBwYWdl
::B64:agent.js:ID0gdGFyZ2V0OwogICAgYXdhaXQgcGFnZS5icmluZ1RvRnJvbnQoKTsKICAgIHJldHVybiAiVGFiIGFrdGlmIHNla2FyYW5nOiAiICsgKGF3YWl0IHBhZ2UudGl0bGUoKS5jYXRjaCgoKSA9PiAiIikpICsgIiB8ICIgKyBwYWdlLnVybCgpOwogIH0sCgogIGNsb3Nl
::B64:agent.js:X3RhYjogYXN5bmMgKHsgaW5kZXggfSkgPT4gewogICAgY29uc3QgYWxsID0gbGl2ZVBhZ2VzKCk7CiAgICBjb25zdCB0YXJnZXQgPSBpbmRleCA/IHBpY2tUYWIoYWxsLCBpbmRleCkgOiBwYWdlOwogICAgaWYgKCF0YXJnZXQpIHRocm93IG5ldyBFcnJvcigiVGFi
::B64:agent.js:IHRpZGFrIGRpdGVtdWthbi5cbiIgKyAoYXdhaXQgdGFic1N1bW1hcnkoKSkpOwogICAgaWYgKGFsbC5sZW5ndGggPT09IDEpIHRocm93IG5ldyBFcnJvcigiSW5pIHRhYiB0ZXJha2hpciwgdGlkYWsgZGl0dXR1cCBhZ2FyIGJyb3dzZXIgdGV0YXAgdGVyYnVrYSIp
::B64:agent.js:OwogICAgY29uc3QganVkdWwgPSBhd2FpdCB0YXJnZXQudGl0bGUoKS5jYXRjaCgoKSA9PiAiIik7CiAgICBpZiAoIShhd2FpdCBhc2soYFR1dHVwIHRhYjogJHtqdWR1bH1gKSkpIHJldHVybiAiRGliYXRhbGthbiB1c2VyIjsKICAgIGNvbnN0IHdhc0FjdGl2ZSA9
::B64:agent.js:IHRhcmdldCA9PT0gcGFnZTsKICAgIGF3YWl0IHRhcmdldC5jbG9zZSgpOwogICAgaWYgKHdhc0FjdGl2ZSkgewogICAgICBwYWdlID0gbGl2ZVBhZ2VzKCkuYXQoLTEpOwogICAgICBhd2FpdCBwYWdlLmJyaW5nVG9Gcm9udCgpOwogICAgfQogICAgcmV0dXJuICJv
::B64:agent.js:ay5cbiIgKyAoYXdhaXQgdGFic1N1bW1hcnkoKSk7CiAgfSwKCiAgaW5zcGVjdF9wYWdlOiBhc3luYyAoKSA9PiB7CiAgICBjb25zdCBpdGVtcyA9IGF3YWl0IHBhZ2UuZXZhbHVhdGUoKCkgPT4KICAgICAgWy4uLmRvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoImlu
::B64:agent.js:cHV0LCBidXR0b24sIGEsIHRleHRhcmVhLCBzZWxlY3QiKV0KICAgICAgICAuc2xpY2UoMCwgNjApCiAgICAgICAgLm1hcCgoZSkgPT4gKHsKICAgICAgICAgIHRhZzogZS50YWdOYW1lLnRvTG93ZXJDYXNlKCksCiAgICAgICAgICBpZDogZS5pZCB8fCB1bmRlZmlu
::B64:agent.js:ZWQsCiAgICAgICAgICBuYW1lOiBlLmdldEF0dHJpYnV0ZSgibmFtZSIpIHx8IHVuZGVmaW5lZCwKICAgICAgICAgIHR5cGU6IGUuZ2V0QXR0cmlidXRlKCJ0eXBlIikgfHwgdW5kZWZpbmVkLAogICAgICAgICAgdGV4dDogKGUuaW5uZXJUZXh0IHx8IGUudmFsdWUg
::B64:agent.js:fHwgZS5wbGFjZWhvbGRlciB8fCAiIikudHJpbSgpLnNsaWNlKDAsIDQwKSB8fCB1bmRlZmluZWQsCiAgICAgICAgfSkpCiAgICApOwogICAgcmV0dXJuIEpTT04uc3RyaW5naWZ5KGl0ZW1zKTsKICB9LAoKICB5b3V0dWJlX3BsYXk6IGFzeW5jICh7IHF1ZXJ5LCBw
::B64:agent.js:aWNrID0gMSwgbmV3X3RhYiA9IGZhbHNlIH0pID0+IHsKICAgIGlmIChpc1RydWUobmV3X3RhYikpIHBhZ2UgPSBhd2FpdCBjb250ZXh0Lm5ld1BhZ2UoKTsKICAgIGF3YWl0IHBhZ2UuYnJpbmdUb0Zyb250KCk7CiAgICBsZXQgbGlzdCA9IFtdOwogICAgdHJ5IHsK
::B64:agent.js:ICAgICAgbGlzdCA9IChhd2FpdCB5dFNlYXJjaEZhc3QoU3RyaW5nKHF1ZXJ5KSkpLnNsaWNlKDAsIDUpLm1hcCgodikgPT4gKHsKICAgICAgICB0aXRsZTogdi50aXRsZSArICh2LmNoYW5uZWwgPyAiIHwgIiArIHYuY2hhbm5lbCA6ICIiKSwKICAgICAgICBocmVm
::B64:agent.js:OiAiaHR0cHM6Ly93d3cueW91dHViZS5jb20vd2F0Y2g/dj0iICsgdi5pZCwKICAgICAgfSkpOwogICAgfSBjYXRjaCB7fQogICAgaWYgKCFsaXN0Lmxlbmd0aCkgewogICAgICBhd2FpdCBwYWdlLmdvdG8oImh0dHBzOi8vd3d3LnlvdXR1YmUuY29tL3Jlc3VsdHM/
::B64:agent.js:c2VhcmNoX3F1ZXJ5PSIgKyBlbmNvZGVVUklDb21wb25lbnQoU3RyaW5nKHF1ZXJ5KSksIHsKICAgICAgICB3YWl0VW50aWw6ICJkb21jb250ZW50bG9hZGVkIiwKICAgICAgfSk7CiAgICAgIGF3YWl0IHBhZ2Uud2FpdEZvclNlbGVjdG9yKCJ5dGQtdmlkZW8tcmVu
::B64:agent.js:ZGVyZXIgYSN2aWRlby10aXRsZSIsIHsgdGltZW91dDogMjAwMDAgfSk7CiAgICAgIGxpc3QgPSBhd2FpdCBwYWdlLiQkZXZhbCgieXRkLXZpZGVvLXJlbmRlcmVyIGEjdmlkZW8tdGl0bGUiLCAoZWxzKSA9PgogICAgICAgIGVscy5zbGljZSgwLCA1KS5tYXAoKGUp
::B64:agent.js:ID0+ICh7IHRpdGxlOiBlLnRleHRDb250ZW50LnRyaW0oKSwgaHJlZjogZS5ocmVmIH0pKQogICAgICApOwogICAgfQogICAgaWYgKCFsaXN0Lmxlbmd0aCkgcmV0dXJuICJUaWRhayBhZGEgaGFzaWwiOwogICAgY29uc3Qgc3RhcnQgPSBNYXRoLm1pbihNYXRoLm1h
::B64:agent.js:eChOdW1iZXIocGljaykgfHwgMSwgMSksIGxpc3QubGVuZ3RoKSAtIDE7CiAgICBjb25zdCBvcmRlciA9IFtzdGFydCwgLi4ubGlzdC5tYXAoKF8sIGkpID0+IGkpLmZpbHRlcigoaSkgPT4gaSAhPT0gc3RhcnQpXS5zbGljZSgwLCAzKTsKICAgIGNvbnN0IG90aGVy
::B64:agent.js:cyA9IGxpc3QubWFwKCh2LCBpKSA9PiBgJHtpICsgMX0uICR7di50aXRsZX1gKS5qb2luKCJcbiIpOwogICAgZm9yIChjb25zdCBpZHggb2Ygb3JkZXIpIHsKICAgICAgYXdhaXQgcGFnZS5nb3RvKGxpc3RbaWR4XS5ocmVmLCB7IHdhaXRVbnRpbDogImRvbWNvbnRl
::B64:agent.js:bnRsb2FkZWQiIH0pOwogICAgICBpZiAoYXdhaXQgZW5zdXJlUGxheWluZygpKSB7CiAgICAgICAgcmV0dXJuIGBNZW11dGFyICMke2lkeCArIDF9OiAke2xpc3RbaWR4XS50aXRsZX1cbkhhc2lsIHBlbmNhcmlhbjpcbiR7b3RoZXJzfWA7CiAgICAgIH0KICAgIH0K
::B64:agent.js:ICAgIHJldHVybiAiVmlkZW8gZ2FnYWwgZGlwdXRhciAoWW91VHViZSBtZW5hbXBpbGthbiBlcnJvcikuIENvYmEgL2xvZ2luIGF0YXUganVkdWwgbGFpbi5cbkhhc2lsIHBlbmNhcmlhbjpcbiIgKyBvdGhlcnM7CiAgfSwKCiAgeW91dHViZV9jb250cm9sOiBhc3lu
::B64:agent.js:YyAoeyBhY3Rpb24sIHNlY29uZHMgPSAxMCB9KSA9PiB7CiAgICBhd2FpdCBwYWdlLmJyaW5nVG9Gcm9udCgpOwogICAgcmV0dXJuIHBhZ2UuZXZhbHVhdGUoCiAgICAgICh7IGEsIHMgfSkgPT4gewogICAgICAgIGNvbnN0IHYgPSBkb2N1bWVudC5xdWVyeVNlbGVj
::B64:agent.js:dG9yKCJ2aWRlbyIpOwogICAgICAgIGlmICghdikgcmV0dXJuICJUaWRhayBhZGEgdmlkZW8gZGkgaGFsYW1hbiBpbmkiOwogICAgICAgIGlmIChhID09PSAicGF1c2UiKSB2LnBhdXNlKCk7CiAgICAgICAgZWxzZSBpZiAoYSA9PT0gInBsYXkiKSB2LnBsYXkoKTsK
::B64:agent.js:ICAgICAgICBlbHNlIGlmIChhID09PSAidG9nZ2xlIikgKHYucGF1c2VkID8gdi5wbGF5KCkgOiB2LnBhdXNlKCkpOwogICAgICAgIGVsc2UgaWYgKGEgPT09ICJtdXRlIikgdi5tdXRlZCA9IHRydWU7CiAgICAgICAgZWxzZSBpZiAoYSA9PT0gInVubXV0ZSIpIHYu
::B64:agent.js:bXV0ZWQgPSBmYWxzZTsKICAgICAgICBlbHNlIGlmIChhID09PSAiZm9yd2FyZCIpIHYuY3VycmVudFRpbWUgKz0gczsKICAgICAgICBlbHNlIGlmIChhID09PSAiYmFja3dhcmQiKSB2LmN1cnJlbnRUaW1lIC09IHM7CiAgICAgICAgZWxzZSBpZiAoYSA9PT0gIm5l
::B64:agent.js:eHQiKSB7CiAgICAgICAgICBjb25zdCBiID0gZG9jdW1lbnQucXVlcnlTZWxlY3RvcigiLnl0cC1uZXh0LWJ1dHRvbiIpOwogICAgICAgICAgaWYgKCFiKSByZXR1cm4gIlRvbWJvbCBuZXh0IHRpZGFrIGFkYSI7CiAgICAgICAgICBiLmNsaWNrKCk7CiAgICAgICAg
::B64:agent.js:fSBlbHNlIGlmIChhID09PSAicHJldmlvdXMiKSB7CiAgICAgICAgICBjb25zdCBiID0gZG9jdW1lbnQucXVlcnlTZWxlY3RvcigiLnl0cC1wcmV2LWJ1dHRvbiIpOwogICAgICAgICAgaWYgKGIgJiYgZ2V0Q29tcHV0ZWRTdHlsZShiKS5kaXNwbGF5ICE9PSAibm9u
::B64:agent.js:ZSIpIGIuY2xpY2soKTsKICAgICAgICAgIGVsc2UgaGlzdG9yeS5iYWNrKCk7CiAgICAgICAgfSBlbHNlIGlmIChhID09PSAiZnVsbHNjcmVlbiIpIHsKICAgICAgICAgIGNvbnN0IGIgPSBkb2N1bWVudC5xdWVyeVNlbGVjdG9yKCIueXRwLWZ1bGxzY3JlZW4tYnV0
::B64:agent.js:dG9uIik7CiAgICAgICAgICBpZiAoYikgYi5jbGljaygpOwogICAgICAgIH0gZWxzZSByZXR1cm4gIkFrc2kgdGlkYWsgZGlrZW5hbC4gUGlsaWg6IHBsYXksIHBhdXNlLCB0b2dnbGUsIG11dGUsIHVubXV0ZSwgZm9yd2FyZCwgYmFja3dhcmQsIG5leHQsIHByZXZp
::B64:agent.js:b3VzLCBmdWxsc2NyZWVuIjsKICAgICAgICByZXR1cm4gIm9rIjsKICAgICAgfSwKICAgICAgeyBhOiBTdHJpbmcoYWN0aW9uKS50b0xvd2VyQ2FzZSgpLCBzOiBOdW1iZXIoc2Vjb25kcykgfHwgMTAgfQogICAgKTsKICB9LAoKICAvLyAtLS0gV2ViIC0tLQogIHdl
::B64:agent.js:Yl9zZWFyY2g6IGFzeW5jICh7IHF1ZXJ5LCBuZXdfdGFiID0gZmFsc2UgfSkgPT4gewogICAgaWYgKGlzVHJ1ZShuZXdfdGFiKSkgcGFnZSA9IGF3YWl0IGNvbnRleHQubmV3UGFnZSgpOwogICAgYXdhaXQgcGFnZS5icmluZ1RvRnJvbnQoKTsKICAgIGF3YWl0IHBh
::B64:agent.js:Z2UuZ290bygiaHR0cHM6Ly9odG1sLmR1Y2tkdWNrZ28uY29tL2h0bWwvP3E9IiArIGVuY29kZVVSSUNvbXBvbmVudChTdHJpbmcocXVlcnkpKSwgewogICAgICB3YWl0VW50aWw6ICJkb21jb250ZW50bG9hZGVkIiwKICAgIH0pOwogICAgY29uc3Qgcm93cyA9IGF3
::B64:agent.js:YWl0IHBhZ2UuJCRldmFsKCIucmVzdWx0IiwgKGVscykgPT4KICAgICAgZWxzLnNsaWNlKDAsIDgpLm1hcCgoZSkgPT4gKHsKICAgICAgICB0aXRsZTogZS5xdWVyeVNlbGVjdG9yKCIucmVzdWx0X19hIik/LnRleHRDb250ZW50LnRyaW0oKSwKICAgICAgICB1cmw6
::B64:agent.js:IGUucXVlcnlTZWxlY3RvcigiLnJlc3VsdF9fYSIpPy5ocmVmLAogICAgICAgIHNuaXBwZXQ6IGUucXVlcnlTZWxlY3RvcigiLnJlc3VsdF9fc25pcHBldCIpPy50ZXh0Q29udGVudC50cmltKCksCiAgICAgIH0pKQogICAgKTsKICAgIGNvbnN0IHJlYWwgPSAodSkg
::B64:agent.js:PT4gewogICAgICB0cnkgewogICAgICAgIGNvbnN0IHggPSBuZXcgVVJMKHUpOwogICAgICAgIHJldHVybiB4LnNlYXJjaFBhcmFtcy5nZXQoInVkZGciKSB8fCB1OwogICAgICB9IGNhdGNoIHsKICAgICAgICByZXR1cm4gdTsKICAgICAgfQogICAgfTsKICAgIGNv
::B64:agent.js:bnN0IG9rID0gcm93cy5maWx0ZXIoKHIpID0+IHIudGl0bGUpOwogICAgcmV0dXJuIG9rLmxlbmd0aCA/IG9rLm1hcCgociwgaSkgPT4gYCR7aSArIDF9LiAke3IudGl0bGV9XG4gICAke3JlYWwoci51cmwpfVxuICAgJHtyLnNuaXBwZXQgfHwgIiJ9YCkuam9pbigi
::B64:agent.js:XG4iKSA6ICJUaWRhayBhZGEgaGFzaWwiOwogIH0sCgogIHNjcm9sbF9wYWdlOiBhc3luYyAoeyBhbW91bnQgfSkgPT4gewogICAgYXdhaXQgcGFnZS5tb3VzZS53aGVlbCgwLCBNYXRoLnJvdW5kKE51bWJlcihhbW91bnQpIHx8IDEpICogNzAwKTsKICAgIGF3YWl0
::B64:agent.js:IHNsZWVwKDIwMCk7CiAgICByZXR1cm4gIm9rIjsKICB9LAoKICB3YWl0X2Zvcl91c2VyOiBhc3luYyAoeyBtZXNzYWdlIH0pID0+IHsKICAgIGF3YWl0IHBhZ2UuYnJpbmdUb0Zyb250KCkuY2F0Y2goKCkgPT4ge30pOwogICAgY29uc29sZS5sb2coYFxuW0JVVFVI
::B64:agent.js:IEJBTlRVQU4gS0FNVV0gJHttZXNzYWdlfWApOwogICAgYXdhaXQgcmwucXVlc3Rpb24oIlRla2FuIEVudGVyIGppa2Egc3VkYWggc2VsZXNhaS4uLiAiKTsKICAgIHJldHVybiAiVXNlciBzdWRhaCBzZWxlc2FpIjsKICB9LAoKICBkb3dubG9hZF9maWxlOiBhc3lu
::B64:agent.js:YyAoeyB1cmwsIGZpbGVuYW1lIH0pID0+IHsKICAgIGlmICghL15odHRwcz86XC9cLy9pLnRlc3QoU3RyaW5nKHVybCkpKSB0aHJvdyBuZXcgRXJyb3IoIlVSTCBoYXJ1cyBkaWF3YWxpIGh0dHA6Ly8gYXRhdSBodHRwczovLyIpOwogICAgY29uc3QgZ3Vlc3MgPSBk
::B64:agent.js:ZWNvZGVVUklDb21wb25lbnQobmV3IFVSTCh1cmwpLnBhdGhuYW1lLnNwbGl0KCIvIikucG9wKCkgfHwgIiIpIHx8ICJkb3dubG9hZC5iaW4iOwogICAgY29uc3QgZGVzdCA9IHBhdGguam9pbihIT01FLCAiRG93bmxvYWRzIiwgcGF0aC5iYXNlbmFtZShTdHJpbmco
::B64:agent.js:ZmlsZW5hbWUgfHwgZ3Vlc3MpKSk7CiAgICBpZiAoIShhd2FpdCBhc2soYFVuZHVoICR7dXJsfSAga2UgICR7ZGVzdH1gKSkpIHJldHVybiAiRGliYXRhbGthbiB1c2VyIjsKICAgIGNvbnN0IHJlcyA9IGF3YWl0IGZldGNoKHVybCwgeyByZWRpcmVjdDogImZvbGxv
::B64:agent.js:dyIsIHNpZ25hbDogQWJvcnRTaWduYWwudGltZW91dCgxMCAqIDYwICogMTAwMCkgfSk7CiAgICBpZiAoIXJlcy5vaykgdGhyb3cgbmV3IEVycm9yKCJIVFRQICIgKyByZXMuc3RhdHVzKTsKICAgIGF3YWl0IHBpcGVsaW5lKFJlYWRhYmxlLmZyb21XZWIocmVzLmJv
::B64:agent.js:ZHkpLCBmcy5jcmVhdGVXcml0ZVN0cmVhbShkZXN0KSk7CiAgICByZXR1cm4gYG9rLCB0ZXJzaW1wYW46ICR7ZGVzdH0gKCR7ZnMuc3RhdFN5bmMoZGVzdCkuc2l6ZX0gYnl0ZSlgOwogIH0sCgogIC8vIC0tLSBQQzogaW5mbywgbWVkaWEsIGNsaXBib2FyZCwgamVu
::B64:agent.js:ZGVsYSAtLS0KICBub3c6IGFzeW5jICgpID0+IG5ldyBEYXRlKCkudG9Mb2NhbGVTdHJpbmcoImlkLUlEIiwgeyBkYXRlU3R5bGU6ICJmdWxsIiwgdGltZVN0eWxlOiAibG9uZyIgfSksCgogIHN5c3RlbV9pbmZvOiBhc3luYyAoKSA9PgogICAgcHMoYAokb3MgPSBH
::B64:agent.js:ZXQtQ2ltSW5zdGFuY2UgV2luMzJfT3BlcmF0aW5nU3lzdGVtCiRjcHUgPSBHZXQtQ2ltSW5zdGFuY2UgV2luMzJfUHJvY2Vzc29yIHwgU2VsZWN0LU9iamVjdCAtRmlyc3QgMQokYmF0ID0gR2V0LUNpbUluc3RhbmNlIFdpbjMyX0JhdHRlcnkgfCBTZWxlY3QtT2Jq
::B64:agent.js:ZWN0IC1GaXJzdCAxCiRsID0gQCgpCiRsICs9ICJPUzogIiArICRvcy5DYXB0aW9uCiRsICs9ICJDUFU6ICIgKyAkY3B1Lk5hbWUgKyAiIChiZWJhbiAiICsgJGNwdS5Mb2FkUGVyY2VudGFnZSArICIlKSIKJGwgKz0gIlJBTTogYmViYXMgIiArIFttYXRoXTo6Um91
::B64:agent.js:bmQoJG9zLkZyZWVQaHlzaWNhbE1lbW9yeSAvIDFNQiwgMSkgKyAiIEdCIGRhcmkgIiArIFttYXRoXTo6Um91bmQoJG9zLlRvdGFsVmlzaWJsZU1lbW9yeVNpemUgLyAxTUIsIDEpICsgIiBHQiIKaWYgKCRiYXQpIHsgJGwgKz0gIkJhdGVyYWk6ICIgKyAkYmF0LkVz
::B64:agent.js:dGltYXRlZENoYXJnZVJlbWFpbmluZyArICIlIiB9IGVsc2UgeyAkbCArPSAiQmF0ZXJhaTogdGlkYWsgYWRhIChQQyBkZXNrdG9wKSIgfQpHZXQtQ2ltSW5zdGFuY2UgV2luMzJfTG9naWNhbERpc2sgLUZpbHRlciAiRHJpdmVUeXBlPTMiIHwgRm9yRWFjaC1PYmpl
::B64:agent.js:Y3QgeyAkbCArPSAiRGlzayAiICsgJF8uRGV2aWNlSUQgKyAiIGJlYmFzICIgKyBbbWF0aF06OlJvdW5kKCRfLkZyZWVTcGFjZSAvIDFHQiwgMSkgKyAiIEdCIGRhcmkgIiArIFttYXRoXTo6Um91bmQoJF8uU2l6ZSAvIDFHQiwgMSkgKyAiIEdCIiB9CiRsIC1qb2lu
::B64:agent.js:IFtFbnZpcm9ubWVudF06Ok5ld0xpbmUKYCksCgogIG1lZGlhX2tleTogYXN5bmMgKHsga2V5LCB0aW1lcyA9IDEgfSkgPT4gewogICAgY29uc3QgdmFsaWQgPSBbInZvbHVwIiwgInZvbGRvd24iLCAibXV0ZSIsICJwbGF5cGF1c2UiLCAibmV4dCIsICJwcmV2Il07
::B64:agent.js:CiAgICBpZiAoIXZhbGlkLmluY2x1ZGVzKFN0cmluZyhrZXkpKSkgcmV0dXJuICJrZXkgaGFydXMgc2FsYWggc2F0dSBkYXJpOiAiICsgdmFsaWQuam9pbigiLCAiKTsKICAgIGF3YWl0IHBzKAogICAgICBgCkFkZC1UeXBlIEAiCnVzaW5nIFN5c3RlbS5SdW50aW1l
::B64:agent.js:LkludGVyb3BTZXJ2aWNlczsKcHVibGljIGNsYXNzIEsgeyBbRGxsSW1wb3J0KCJ1c2VyMzIuZGxsIildIHB1YmxpYyBzdGF0aWMgZXh0ZXJuIHZvaWQga2V5YmRfZXZlbnQoYnl0ZSBiLCBieXRlIHMsIHVpbnQgZiwgaW50IGUpOyB9CiJACiRtYXAgPSBAeyB2b2x1
::B64:agent.js:cCA9IDB4QUY7IHZvbGRvd24gPSAweEFFOyBtdXRlID0gMHhBRDsgcGxheXBhdXNlID0gMHhCMzsgbmV4dCA9IDB4QjA7IHByZXYgPSAweEIxIH0KJGsgPSBbYnl0ZV0kbWFwWyRlbnY6S0VZXQpmb3IgKCRpID0gMDsgJGkgLWx0IFtpbnRdJGVudjpOOyAkaSsrKSB7
::B64:agent.js:IFtLXTo6a2V5YmRfZXZlbnQoJGssIDAsIDAsIDApOyBbS106OmtleWJkX2V2ZW50KCRrLCAwLCAyLCAwKTsgU3RhcnQtU2xlZXAgLU1pbGxpc2Vjb25kcyA2MCB9CmAsCiAgICAgIHsgS0VZOiBTdHJpbmcoa2V5KSwgTjogU3RyaW5nKE1hdGgubWluKE1hdGgubWF4
::B64:agent.js:KE51bWJlcih0aW1lcykgfHwgMSwgMSksIDUwKSkgfQogICAgKTsKICAgIHJldHVybiAib2siOwogIH0sCgogIGNsaXBib2FyZF9nZXQ6IGFzeW5jICgpID0+IChhd2FpdCBwcygiR2V0LUNsaXBib2FyZCAtUmF3IikpLnNsaWNlKDAsIDQwMDApIHx8ICIoa29zb25n
::B64:agent.js:KSIsCgogIGNsaXBib2FyZF9zZXQ6IGFzeW5jICh7IHRleHQgfSkgPT4gewogICAgYXdhaXQgcHMoIlNldC1DbGlwYm9hcmQgLVZhbHVlICRlbnY6VFhUIiwgeyBUWFQ6IFN0cmluZyh0ZXh0KSB9KTsKICAgIHJldHVybiAib2siOwogIH0sCgogIGxpc3Rfd2luZG93
::B64:agent.js:czogYXN5bmMgKCkgPT4KICAgIChhd2FpdCBwcyhgR2V0LVByb2Nlc3MgfCBXaGVyZS1PYmplY3QgeyAkXy5NYWluV2luZG93VGl0bGUgfSB8IEZvckVhY2gtT2JqZWN0IHsgJF8uUHJvY2Vzc05hbWUgKyAiIHwgIiArICRfLk1haW5XaW5kb3dUaXRsZSB9YCkpIHx8
::B64:agent.js:CiAgICAiKHRpZGFrIGFkYSBqZW5kZWxhKSIsCgogIGZvY3VzX3dpbmRvdzogYXN5bmMgKHsgdGl0bGUgfSkgPT4KICAgIHBzKGBpZiAoKE5ldy1PYmplY3QgLUNvbU9iamVjdCBXU2NyaXB0LlNoZWxsKS5BcHBBY3RpdmF0ZSgkZW52OlRJVExFKSkgeyAib2siIH0g
::B64:agent.js:ZWxzZSB7ICJqZW5kZWxhIHRpZGFrIGRpdGVtdWthbiIgfWAsIHsKICAgICAgVElUTEU6IFN0cmluZyh0aXRsZSksCiAgICB9KSwKCiAgY2xvc2Vfd2luZG93OiBhc3luYyAoeyB0aXRsZSB9KSA9PiB7CiAgICBpZiAoIShhd2FpdCBhc2soYFR1dHVwIGplbmRlbGE6
::B64:agent.js:ICR7dGl0bGV9YCkpKSByZXR1cm4gIkRpYmF0YWxrYW4gdXNlciI7CiAgICByZXR1cm4gcHMoCiAgICAgIGAkcCA9IEdldC1Qcm9jZXNzIHwgV2hlcmUtT2JqZWN0IHsgJF8uTWFpbldpbmRvd1RpdGxlIC1saWtlICgiKiIgKyAkZW52OlRJVExFICsgIioiKSB9IHwg
::B64:agent.js:U2VsZWN0LU9iamVjdCAtRmlyc3QgMQppZiAoJHApIHsgJHAuQ2xvc2VNYWluV2luZG93KCkgfCBPdXQtTnVsbDsgIm9rOiAiICsgJHAuTWFpbldpbmRvd1RpdGxlIH0gZWxzZSB7ICJqZW5kZWxhIHRpZGFrIGRpdGVtdWthbiIgfWAsCiAgICAgIHsgVElUTEU6IFN0
::B64:agent.js:cmluZyh0aXRsZSkgfQogICAgKTsKICB9LAoKICAvLyAtLS0gRmlsZSAtLS0KICByZWFkX3RleHRfZmlsZTogYXN5bmMgKHsgcGF0aDogcCB9KSA9PiB7CiAgICBjb25zdCBmdWxsID0gcGF0aC5yZXNvbHZlKFN0cmluZyhwKSk7CiAgICBjb25zdCBzdCA9IGZzLnN0
::B64:agent.js:YXRTeW5jKGZ1bGwpOwogICAgaWYgKCFzdC5pc0ZpbGUoKSkgdGhyb3cgbmV3IEVycm9yKCJCdWthbiBmaWxlOiAiICsgZnVsbCk7CiAgICBpZiAoc3Quc2l6ZSA+IDJfMDAwXzAwMCkgdGhyb3cgbmV3IEVycm9yKCJGaWxlIHRlcmxhbHUgYmVzYXIgdW50dWsgZGli
::B64:agent.js:YWNhICgiICsgc3Quc2l6ZSArICIgYnl0ZSkiKTsKICAgIHJldHVybiBmcy5yZWFkRmlsZVN5bmMoZnVsbCwgInV0ZjgiKS5zbGljZSgwLCA4MDAwKTsKICB9LAoKICB3cml0ZV90ZXh0X2ZpbGU6IGFzeW5jICh7IHBhdGg6IHAsIGNvbnRlbnQsIGFwcGVuZCA9IGZh
::B64:agent.js:bHNlIH0pID0+IHsKICAgIGNvbnN0IGZ1bGwgPSBwYXRoLnJlc29sdmUoU3RyaW5nKHApKTsKICAgIGNvbnN0IGFkZCA9IGFwcGVuZCA9PT0gdHJ1ZSB8fCBhcHBlbmQgPT09ICJ0cnVlIjsKICAgIGNvbnN0IHZlcmIgPSBhZGQgPyAiVGFtYmFoIGtlIiA6IGZzLmV4
::B64:agent.js:aXN0c1N5bmMoZnVsbCkgPyAiVElNUEEiIDogIkJ1YXQiOwogICAgaWYgKCEoYXdhaXQgYXNrKGAke3ZlcmJ9IGZpbGU6ICR7ZnVsbH1gKSkpIHJldHVybiAiRGliYXRhbGthbiB1c2VyIjsKICAgIGZzLm1rZGlyU3luYyhwYXRoLmRpcm5hbWUoZnVsbCksIHsgcmVj
::B64:agent.js:dXJzaXZlOiB0cnVlIH0pOwogICAgaWYgKGFkZCkgZnMuYXBwZW5kRmlsZVN5bmMoZnVsbCwgU3RyaW5nKGNvbnRlbnQpKTsKICAgIGVsc2UgZnMud3JpdGVGaWxlU3luYyhmdWxsLCBTdHJpbmcoY29udGVudCkpOwogICAgcmV0dXJuICJvazogIiArIGZ1bGw7CiAg
::B64:agent.js:fSwKCiAgbWFrZV9mb2xkZXI6IGFzeW5jICh7IHBhdGg6IHAgfSkgPT4gewogICAgY29uc3QgZnVsbCA9IHBhdGgucmVzb2x2ZShTdHJpbmcocCkpOwogICAgaWYgKCEoYXdhaXQgYXNrKGBCdWF0IGZvbGRlcjogJHtmdWxsfWApKSkgcmV0dXJuICJEaWJhdGFsa2Fu
::B64:agent.js:IHVzZXIiOwogICAgZnMubWtkaXJTeW5jKGZ1bGwsIHsgcmVjdXJzaXZlOiB0cnVlIH0pOwogICAgcmV0dXJuICJvazogIiArIGZ1bGw7CiAgfSwKCiAgbW92ZV9wYXRoOiBhc3luYyAoeyBmcm9tLCB0byB9KSA9PiB7CiAgICBpZiAoIShhd2FpdCBhc2soYFBpbmRh
::B64:agent.js:aGthbjogJHtmcm9tfSAga2UgICR7dG99YCkpKSByZXR1cm4gIkRpYmF0YWxrYW4gdXNlciI7CiAgICBhd2FpdCBwcygiTW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkZW52OlNSQyAtRGVzdGluYXRpb24gJGVudjpERVNUIiwgewogICAgICBTUkM6IHBhdGgucmVzb2x2
::B64:agent.js:ZShTdHJpbmcoZnJvbSkpLAogICAgICBERVNUOiBwYXRoLnJlc29sdmUoU3RyaW5nKHRvKSksCiAgICB9KTsKICAgIHJldHVybiAib2siOwogIH0sCgogIHJlY3ljbGVfcGF0aDogYXN5bmMgKHsgcGF0aDogcCB9KSA9PiB7CiAgICBjb25zdCBmdWxsID0gcGF0aC5y
::B64:agent.js:ZXNvbHZlKFN0cmluZyhwKSk7CiAgICBpZiAoIShhd2FpdCBhc2soYFBpbmRhaGthbiBrZSBSZWN5Y2xlIEJpbjogJHtmdWxsfWApKSkgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgYXdhaXQgcHMoCiAgICAgIGBBZGQtVHlwZSAtQXNzZW1ibHlOYW1lIE1p
::B64:agent.js:Y3Jvc29mdC5WaXN1YWxCYXNpYwokcCA9ICRlbnY6VEFSR0VUCmlmIChUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRwIC1QYXRoVHlwZSBDb250YWluZXIpIHsgW01pY3Jvc29mdC5WaXN1YWxCYXNpYy5GaWxlSU8uRmlsZVN5c3RlbV06OkRlbGV0ZURpcmVjdG9yeSgk
::B64:agent.js:cCwgJ09ubHlFcnJvckRpYWxvZ3MnLCAnU2VuZFRvUmVjeWNsZUJpbicpIH0KZWxzZSB7IFtNaWNyb3NvZnQuVmlzdWFsQmFzaWMuRmlsZUlPLkZpbGVTeXN0ZW1dOjpEZWxldGVGaWxlKCRwLCAnT25seUVycm9yRGlhbG9ncycsICdTZW5kVG9SZWN5Y2xlQmluJykg
::B64:agent.js:fWAsCiAgICAgIHsgVEFSR0VUOiBmdWxsIH0KICAgICk7CiAgICByZXR1cm4gIm9rLCBkaXBpbmRhaCBrZSBSZWN5Y2xlIEJpbiAobWFzaWggYmlzYSBkaXB1bGloa2FuKSI7CiAgfSwKCiAgemlwX3BhdGg6IGFzeW5jICh7IHNvdXJjZSwgemlwIH0pID0+IHsKICAg
::B64:agent.js:IGNvbnN0IHNyYyA9IHBhdGgucmVzb2x2ZShTdHJpbmcoc291cmNlKSk7CiAgICBjb25zdCBkZXN0ID0gcGF0aC5yZXNvbHZlKFN0cmluZyh6aXApKTsKICAgIGlmICghKGF3YWl0IGFzayhgWmlwICR7c3JjfSAgbWVuamFkaSAgJHtkZXN0fWApKSkgcmV0dXJuICJE
::B64:agent.js:aWJhdGFsa2FuIHVzZXIiOwogICAgYXdhaXQgcHMoIkNvbXByZXNzLUFyY2hpdmUgLUxpdGVyYWxQYXRoICRlbnY6U1JDIC1EZXN0aW5hdGlvblBhdGggJGVudjpERVNUIC1Gb3JjZSIsIHsgU1JDOiBzcmMsIERFU1Q6IGRlc3QgfSwgNjAwMDAwKTsKICAgIHJldHVy
::B64:agent.js:biAib2s6ICIgKyBkZXN0OwogIH0sCgogIHVuemlwX3BhdGg6IGFzeW5jICh7IHppcCwgZm9sZGVyIH0pID0+IHsKICAgIGNvbnN0IHNyYyA9IHBhdGgucmVzb2x2ZShTdHJpbmcoemlwKSk7CiAgICBjb25zdCBkZXN0ID0gcGF0aC5yZXNvbHZlKFN0cmluZyhmb2xk
::B64:agent.js:ZXIpKTsKICAgIGlmICghKGF3YWl0IGFzayhgRWtzdHJhayAke3NyY30gIGtlICAke2Rlc3R9YCkpKSByZXR1cm4gIkRpYmF0YWxrYW4gdXNlciI7CiAgICBhd2FpdCBwcygiRXhwYW5kLUFyY2hpdmUgLUxpdGVyYWxQYXRoICRlbnY6U1JDIC1EZXN0aW5hdGlvblBh
::B64:agent.js:dGggJGVudjpERVNUIC1Gb3JjZSIsIHsgU1JDOiBzcmMsIERFU1Q6IGRlc3QgfSwgNjAwMDAwKTsKICAgIHJldHVybiAib2s6ICIgKyBkZXN0OwogIH0sCgogIC8vIC0tLSBVcGxvYWQgY2VwYXQ6IHNhdHUgcGFuZ2dpbGFuIG1lbmdnYW50aWthbiBiYW55YWsgbGFu
::B64:agent.js:Z2thaCBBSSAtLS0KICBmYXN0X3VwbG9hZDogYXN5bmMgKHsgdXJsLCBmaWxlbmFtZSwgZm9sZGVyLCBwYXR0ZXJuLCBzdWJtaXQgPSB0cnVlLCBuZXdfdGFiID0gdHJ1ZSB9KSA9PiB7CiAgICBjb25zdCB0MCA9IERhdGUubm93KCk7CiAgICBjb25zdCBkb1N1Ym1p
::B64:agent.js:dCA9ICEoc3VibWl0ID09PSBmYWxzZSB8fCBzdWJtaXQgPT09ICJmYWxzZSIpOwogICAgbGV0IGZpbGVzID0gW107CiAgICBpZiAoZmlsZW5hbWUpIHsKICAgICAgZm9yIChjb25zdCB0b2sgb2YgU3RyaW5nKGZpbGVuYW1lKS5zcGxpdCgifCIpLm1hcCgoeCkgPT4g
::B64:agent.js:eC50cmltKCkpLmZpbHRlcihCb29sZWFuKSkgewogICAgICAgIGNvbnN0IGFicyA9IHBhdGgucmVzb2x2ZShTQUZFX0RJUiwgdG9rLnJlcGxhY2UoL14ifCIkL2csICIiKSk7CiAgICAgICAgaWYgKGZzLmV4aXN0c1N5bmMoYWJzKSAmJiBmcy5zdGF0U3luYyhhYnMp
::B64:agent.js:LmlzRGlyZWN0b3J5KCkpIGZpbGVzLnB1c2goYXdhaXQgemlwRm9yVXBsb2FkKGFicykpOwogICAgICAgIGVsc2UgZmlsZXMucHVzaChzYWZlUGF0aCh0b2spKTsKICAgICAgfQogICAgfQogICAgaWYgKGZvbGRlcikgewogICAgICBjb25zdCBkaXIgPSBwYXRoLnJl
::B64:agent.js:c29sdmUoU3RyaW5nKGZvbGRlcikpOwogICAgICBjb25zdCBwYXRzID0gcGF0dGVybiA/IFN0cmluZyhwYXR0ZXJuKS50b0xvd2VyQ2FzZSgpLnNwbGl0KCJ8IikubWFwKCh4KSA9PiB4LnRyaW0oKS5yZXBsYWNlKC9eXCovLCAiIikpLmZpbHRlcihCb29sZWFuKSA6
::B64:agent.js:IFtdOwogICAgICBmb3IgKGNvbnN0IGUgb2YgZnMucmVhZGRpclN5bmMoZGlyLCB7IHdpdGhGaWxlVHlwZXM6IHRydWUgfSkpIHsKICAgICAgICBpZiAoZS5pc0ZpbGUoKSAmJiAoIXBhdHMubGVuZ3RoIHx8IHBhdHMuc29tZSgocCkgPT4gZS5uYW1lLnRvTG93ZXJD
::B64:agent.js:YXNlKCkuaW5jbHVkZXMocCkpKSkgZmlsZXMucHVzaChwYXRoLmpvaW4oZGlyLCBlLm5hbWUpKTsKICAgICAgfQogICAgfQogICAgZmlsZXMgPSBbLi4ubmV3IFNldChmaWxlcyldLnNsaWNlKDAsIDUwKTsKICAgIGlmICghZmlsZXMubGVuZ3RoKSB0aHJvdyBuZXcg
::B64:agent.js:RXJyb3IoIlRpZGFrIGFkYSBmaWxlIHlhbmcgY29jb2sgdW50dWsgZGl1cGxvYWQiKTsKICAgIGNvbnN0IHNpemVNQiA9IGZpbGVzLnJlZHVjZSgoYSwgZikgPT4gYSArIGZzLnN0YXRTeW5jKGYpLnNpemUsIDApIC8gMTA0ODU3NjsKICAgIGNvbnN0IGRhZnRhciA9
::B64:agent.js:IGZpbGVzLnNsaWNlKDAsIDE1KS5qb2luKCJcbiAgICIpICsgKGZpbGVzLmxlbmd0aCA+IDE1ID8gYFxuICAgLi4uICske2ZpbGVzLmxlbmd0aCAtIDE1fSBsYWdpYCA6ICIiKTsKICAgIGlmICghKGF3YWl0IGFzayhgVVBMT0FEIENFUEFUICR7ZmlsZXMubGVuZ3Ro
::B64:agent.js:fSBmaWxlICgke3NpemVNQi50b0ZpeGVkKDEpfSBNQikke3VybCA/ICIga2UgIiArIHVybCA6ICIifTpcbiAgICR7ZGFmdGFyfVxuICBgKSkpIHsKICAgICAgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgfQogICAgaWYgKHVybCkgewogICAgICBpZiAoaXNU
::B64:agent.js:cnVlKG5ld190YWIpICYmICFpc0JsYW5rUGFnZSgpKSBwYWdlID0gYXdhaXQgY29udGV4dC5uZXdQYWdlKCk7CiAgICAgIGF3YWl0IHBhZ2UuYnJpbmdUb0Zyb250KCk7CiAgICAgIGF3YWl0IHBhZ2UuZ290byhmaXhVcmwodXJsKSwgeyB3YWl0VW50aWw6ICJkb21j
::B64:agent.js:b250ZW50bG9hZGVkIiB9KTsKICAgICAgYXdhaXQgc2xlZXAoNDAwKTsKICAgIH0KICAgIGNvbnN0IHRyID0gdHJhY2tVcGxvYWRzKCk7CiAgICB0cnkgewogICAgICBjb25zdCBxdWV1ZSA9IFsuLi5maWxlc107CiAgICAgIGxldCByb3VuZHMgPSAwOwogICAgICBs
::B64:agent.js:ZXQgbG9naW5Bc2tlZCA9IGZhbHNlOwogICAgICBsZXQgbm90ZSA9ICIiOwogICAgICB3aGlsZSAocXVldWUubGVuZ3RoICYmIHJvdW5kcyA8IDYwKSB7CiAgICAgICAgcm91bmRzKys7CiAgICAgICAgbGV0IHVzZWQgPSBhd2FpdCBwcm92aWRlRmlsZXMocXVldWUp
::B64:agent.js:OwogICAgICAgIGlmICghdXNlZCAmJiAhbG9naW5Bc2tlZCAmJiAoYXdhaXQgaGFzTG9naW5Gb3JtKCkpKSB7CiAgICAgICAgICBsb2dpbkFza2VkID0gdHJ1ZTsKICAgICAgICAgIGF3YWl0IGltcGwud2FpdF9mb3JfdXNlcih7IG1lc3NhZ2U6ICJIYWxhbWFuIGlu
::B64:agent.js:aSBtZW1pbnRhIGxvZ2luLiBMb2dpbiBkdWx1IGRpIGplbmRlbGEgYnJvd3NlciwgbGFsdSB0ZWthbiBFbnRlci4iIH0pOwogICAgICAgICAgdXNlZCA9IGF3YWl0IHByb3ZpZGVGaWxlcyhxdWV1ZSk7CiAgICAgICAgfQogICAgICAgIGlmICghdXNlZCkgewogICAg
::B64:agent.js:ICAgICAgdGhyb3cgbmV3IEVycm9yKCJUb21ib2wgYXRhdSBpbnB1dCB1cGxvYWQgdGlkYWsgZGl0ZW11a2FuIGRpIGhhbGFtYW4gaW5pLiBQYXN0aWthbiBzdWRhaCBsb2dpbiBkYW4gYmVyYWRhIGRpIGhhbGFtYW4geWFuZyBiZW5hciAoY29iYSAvbG9naW4pLiIp
::B64:agent.js:OwogICAgICAgIH0KICAgICAgICBxdWV1ZS5zcGxpY2UoMCwgdXNlZCk7CiAgICAgICAgaWYgKGRvU3VibWl0KSB7CiAgICAgICAgICBhd2FpdCBzbGVlcCg0MDApOwogICAgICAgICAgYXdhaXQgY2xpY2tCeVRleHQoU1VCTUlUX0JUTiwgMTUwMCk7CiAgICAgICAg
::B64:agent.js:fQogICAgICAgIGNvbnN0IHIgPSBhd2FpdCB3YWl0VXBsb2FkRG9uZSh0ciwgVVBMT0FEX1RJTUVPVVRfTVMpOwogICAgICAgIGlmIChyID09PSBmYWxzZSkgewogICAgICAgICAgbm90ZSA9ICJCYXRhcyB3YWt0dSBtZW51bmdndSBoYWJpczsgdXBsb2FkIG11bmdr
::B64:agent.js:aW4gbWFzaWggYmVyamFsYW4gZGkgaGFsYW1hbi4iOwogICAgICAgICAgYnJlYWs7CiAgICAgICAgfQogICAgICAgIGlmICh0eXBlb2YgciA9PT0gInN0cmluZyIpIG5vdGUgPSByOwogICAgICB9CiAgICAgIGNvbnN0IGxpbmtzID0gYXdhaXQgcGFnZQogICAgICAg
::B64:agent.js:IC5ldmFsdWF0ZSgoc3JjKSA9PiB7CiAgICAgICAgICBjb25zdCByZSA9IG5ldyBSZWdFeHAoc3JjLCAiaSIpOwogICAgICAgICAgY29uc3Qgb3V0ID0gbmV3IFNldCgpOwogICAgICAgICAgZG9jdW1lbnQucXVlcnlTZWxlY3RvckFsbCgiYVtocmVmXSwgaW5wdXQs
::B64:agent.js:IHRleHRhcmVhIikuZm9yRWFjaCgoZSkgPT4gewogICAgICAgICAgICBjb25zdCB2ID0gZS5ocmVmIHx8IGUudmFsdWUgfHwgIiI7CiAgICAgICAgICAgIGlmIChyZS50ZXN0KHYpKSBvdXQuYWRkKHYpOwogICAgICAgICAgfSk7CiAgICAgICAgICAoKGRvY3VtZW50
::B64:agent.js:LmJvZHkgJiYgZG9jdW1lbnQuYm9keS5pbm5lclRleHQubWF0Y2goL2h0dHBzPzpcL1wvW15ccyInPD5dKy9nKSkgfHwgW10pLmZvckVhY2goKHUpID0+IHsKICAgICAgICAgICAgaWYgKHJlLnRlc3QodSkpIG91dC5hZGQodSk7CiAgICAgICAgICB9KTsKICAgICAg
::B64:agent.js:ICAgIHJldHVybiBbLi4ub3V0XS5zbGljZSgwLCAxMCk7CiAgICAgICAgfSwgSE9TVFNfUkUuc291cmNlKQogICAgICAgIC5jYXRjaCgoKSA9PiBbXSk7CiAgICAgIGNvbnN0IHNlY3MgPSAoKERhdGUubm93KCkgLSB0MCkgLyAxMDAwKS50b0ZpeGVkKDEpOwogICAg
::B64:agent.js:ICByZXR1cm4gKAogICAgICAgIGBVcGxvYWQgJHtmaWxlcy5sZW5ndGggLSBxdWV1ZS5sZW5ndGh9LyR7ZmlsZXMubGVuZ3RofSBmaWxlIHNlbGVzYWkgZGFsYW0gJHtzZWNzfSBkdGsuYCArCiAgICAgICAgKG5vdGUgPyBgIENhdGF0YW46ICR7bm90ZX1gIDogIiIp
::B64:agent.js:ICsKICAgICAgICAobGlua3MubGVuZ3RoID8gYFxuTGluayB0ZXJkZXRla3NpOlxuJHtsaW5rcy5qb2luKCJcbiIpfWAgOiAiXG5MaW5rIGJlbHVtIHRlcmRldGVrc2kgb3RvbWF0aXM7IGxpaGF0IGhhbGFtYW4gZGkgYnJvd3Nlci4iKQogICAgICApOwogICAgfSBm
::B64:agent.js:aW5hbGx5IHsKICAgICAgdHIuc3RvcCgpOwogICAgfQogIH0sCgogIHJlY2VudF9maWxlczogYXN5bmMgKHsgZm9sZGVyLCBjb3VudCA9IDEwIH0pID0+IHsKICAgIGNvbnN0IGRpciA9IHBhdGgucmVzb2x2ZShTdHJpbmcoZm9sZGVyIHx8IHBhdGguam9pbihIT01F
::B64:agent.js:LCAiRG93bmxvYWRzIikpKTsKICAgIGNvbnN0IGl0ZW1zID0gcmVjZW50TGlzdChkaXIsIGNvdW50KTsKICAgIHJldHVybiBpdGVtcy5sZW5ndGgKICAgICAgPyBpdGVtcy5tYXAoKHgsIGkpID0+IGAke2kgKyAxfS4gJHt4LmZ9ICgke25ldyBEYXRlKHgudCkudG9M
::B64:agent.js:b2NhbGVTdHJpbmcoImlkLUlEIil9LCAkeyh4LnMgLyAxMDQ4NTc2KS50b0ZpeGVkKDEpfSBNQilgKS5qb2luKCJcbiIpCiAgICAgIDogIih0aWRhayBhZGEgZmlsZSkiOwogIH0sCgogIHNlYXJjaF90ZXh0OiBhc3luYyAoeyBmb2xkZXIsIHRleHQgfSkgPT4gewog
::B64:agent.js:ICAgY29uc3Qgcm9vdCA9IHBhdGgucmVzb2x2ZShTdHJpbmcoZm9sZGVyKSk7CiAgICBjb25zdCBxID0gU3RyaW5nKHRleHQpLnRvTG93ZXJDYXNlKCk7CiAgICBjb25zdCBva0V4dCA9IC9cLih0eHR8bWR8anN8dHN8anNvbnxjc3Z8bG9nfGh0bWx8Y3NzfHB5fGph
::B64:agent.js:dmF8eG1sfGluaXx5bWx8eWFtbHxjZmd8YmF0fHBocHxzcWwpJC9pOwogICAgY29uc3QgaGl0cyA9IFtdOwogICAgY29uc3QgZGVhZGxpbmUgPSBEYXRlLm5vdygpICsgMTUwMDA7CiAgICBjb25zdCB3YWxrID0gKGRpciwgZGVwdGgpID0+IHsKICAgICAgaWYgKGRl
::B64:agent.js:cHRoIDwgMCB8fCBoaXRzLmxlbmd0aCA+PSAyMCB8fCBEYXRlLm5vdygpID4gZGVhZGxpbmUpIHJldHVybjsKICAgICAgbGV0IGVudHJpZXM7CiAgICAgIHRyeSB7CiAgICAgICAgZW50cmllcyA9IGZzLnJlYWRkaXJTeW5jKGRpciwgeyB3aXRoRmlsZVR5cGVzOiB0
::B64:agent.js:cnVlIH0pOwogICAgICB9IGNhdGNoIHsKICAgICAgICByZXR1cm47CiAgICAgIH0KICAgICAgZm9yIChjb25zdCBlIG9mIGVudHJpZXMpIHsKICAgICAgICBjb25zdCBmdWxsID0gcGF0aC5qb2luKGRpciwgZS5uYW1lKTsKICAgICAgICBpZiAoZS5pc0RpcmVjdG9y
::B64:agent.js:eSgpKSB7CiAgICAgICAgICBpZiAoIVNLSVBfRElSUy5oYXMoZS5uYW1lLnRvTG93ZXJDYXNlKCkpICYmICFlLm5hbWUuc3RhcnRzV2l0aCgiJCIpKSB3YWxrKGZ1bGwsIGRlcHRoIC0gMSk7CiAgICAgICAgfSBlbHNlIGlmIChva0V4dC50ZXN0KGUubmFtZSkpIHsK
::B64:agent.js:ICAgICAgICAgIHRyeSB7CiAgICAgICAgICAgIGlmIChmcy5zdGF0U3luYyhmdWxsKS5zaXplID4gMl8wMDBfMDAwKSBjb250aW51ZTsKICAgICAgICAgICAgY29uc3QgbGluZXMgPSBmcy5yZWFkRmlsZVN5bmMoZnVsbCwgInV0ZjgiKS5zcGxpdCgvXHI/XG4vKTsK
::B64:agent.js:ICAgICAgICAgICAgZm9yIChsZXQgaSA9IDA7IGkgPCBsaW5lcy5sZW5ndGggJiYgaGl0cy5sZW5ndGggPCAyMDsgaSsrKSB7CiAgICAgICAgICAgICAgaWYgKGxpbmVzW2ldLnRvTG93ZXJDYXNlKCkuaW5jbHVkZXMocSkpIGhpdHMucHVzaChgJHtmdWxsfToke2kg
::B64:agent.js:KyAxfTogJHtsaW5lc1tpXS50cmltKCkuc2xpY2UoMCwgMTIwKX1gKTsKICAgICAgICAgICAgfQogICAgICAgICAgfSBjYXRjaCB7fQogICAgICAgIH0KICAgICAgfQogICAgfTsKICAgIHdhbGsocm9vdCwgNSk7CiAgICByZXR1cm4gaGl0cy5sZW5ndGggPyBoaXRz
::B64:agent.js:LmpvaW4oIlxuIikgOiAiVGlkYWsgZGl0ZW11a2FuIjsKICB9LAoKICBjb3B5X3BhdGg6IGFzeW5jICh7IGZyb20sIHRvIH0pID0+IHsKICAgIGlmICghKGF3YWl0IGFzayhgU2FsaW46ICR7ZnJvbX0gIGtlICAke3RvfWApKSkgcmV0dXJuICJEaWJhdGFsa2FuIHVz
::B64:agent.js:ZXIiOwogICAgYXdhaXQgcHMoIkNvcHktSXRlbSAtTGl0ZXJhbFBhdGggJGVudjpTUkMgLURlc3RpbmF0aW9uICRlbnY6REVTVCAtUmVjdXJzZSAtRm9yY2UiLCB7CiAgICAgIFNSQzogcGF0aC5yZXNvbHZlKFN0cmluZyhmcm9tKSksCiAgICAgIERFU1Q6IHBhdGgu
::B64:agent.js:cmVzb2x2ZShTdHJpbmcodG8pKSwKICAgIH0sIDYwMDAwMCk7CiAgICByZXR1cm4gIm9rIjsKICB9LAoKICBzYXZlX3NjcmVlbnNob3Q6IGFzeW5jICh7IHBhdGg6IHAgfSkgPT4gewogICAgY29uc3Qgc3RhbXAgPSBuZXcgRGF0ZSgpLnRvSVNPU3RyaW5nKCkucmVw
::B64:agent.js:bGFjZSgvWzouXS9nLCAiLSIpLnNsaWNlKDAsIDE5KTsKICAgIGNvbnN0IGRlc3QgPSBwID8gcGF0aC5yZXNvbHZlKFN0cmluZyhwKSkgOiBwYXRoLmpvaW4oSE9NRSwgIlBpY3R1cmVzIiwgIlNjcmVlbnNob3RzIiwgYGxheWFyLSR7c3RhbXB9LnBuZ2ApOwogICAg
::B64:agent.js:ZnMubWtkaXJTeW5jKHBhdGguZGlybmFtZShkZXN0KSwgeyByZWN1cnNpdmU6IHRydWUgfSk7CiAgICBhd2FpdCBwcygKICAgICAgUFNfSEVBRCArCiAgICAgICAgYAokYiA9IFtTeXN0ZW0uV2luZG93cy5Gb3Jtcy5TY3JlZW5dOjpQcmltYXJ5U2NyZWVuLkJvdW5k
::B64:agent.js:cwokYm1wID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5CaXRtYXAgJGIuV2lkdGgsICRiLkhlaWdodAokZyA9IFtTeXN0ZW0uRHJhd2luZy5HcmFwaGljc106OkZyb21JbWFnZSgkYm1wKQokZy5Db3B5RnJvbVNjcmVlbigkYi5YLCAkYi5ZLCAwLCAwLCAkYm1w
::B64:agent.js:LlNpemUpCiRibXAuU2F2ZSgkZW52Ok9VVCwgW1N5c3RlbS5EcmF3aW5nLkltYWdpbmcuSW1hZ2VGb3JtYXRdOjpQbmcpCmAsCiAgICAgIHsgT1VUOiBkZXN0IH0KICAgICk7CiAgICByZXR1cm4gIlRlcnNpbXBhbjogIiArIGRlc3Q7CiAgfSwKCiAgc2V0X3ZvbHVt
::B64:agent.js:ZTogYXN5bmMgKHsgbGV2ZWwgfSkgPT4gewogICAgY29uc3QgbiA9IE1hdGgubWluKE1hdGgubWF4KE1hdGgucm91bmQoTnVtYmVyKGxldmVsKSksIDApLCAxMDApOwogICAgYXdhaXQgcHMoCiAgICAgIGAKQWRkLVR5cGUgQCIKdXNpbmcgU3lzdGVtLlJ1bnRpbWUu
::B64:agent.js:SW50ZXJvcFNlcnZpY2VzOwpwdWJsaWMgY2xhc3MgSyB7IFtEbGxJbXBvcnQoInVzZXIzMi5kbGwiKV0gcHVibGljIHN0YXRpYyBleHRlcm4gdm9pZCBrZXliZF9ldmVudChieXRlIGIsIGJ5dGUgcywgdWludCBmLCBpbnQgZSk7IH0KIkAKZm9yICgkaSA9IDA7ICRp
::B64:agent.js:IC1sdCA1MDsgJGkrKykgeyBbS106OmtleWJkX2V2ZW50KDB4QUUsIDAsIDAsIDApOyBbS106OmtleWJkX2V2ZW50KDB4QUUsIDAsIDIsIDApOyBTdGFydC1TbGVlcCAtTWlsbGlzZWNvbmRzIDEyIH0KZm9yICgkaSA9IDA7ICRpIC1sdCBbaW50XSRlbnY6VVA7ICRp
::B64:agent.js:KyspIHsgW0tdOjprZXliZF9ldmVudCgweEFGLCAwLCAwLCAwKTsgW0tdOjprZXliZF9ldmVudCgweEFGLCAwLCAyLCAwKTsgU3RhcnQtU2xlZXAgLU1pbGxpc2Vjb25kcyAxMiB9CmAsCiAgICAgIHsgVVA6IFN0cmluZyhNYXRoLnJvdW5kKG4gLyAyKSkgfQogICAg
::B64:agent.js:KTsKICAgIHJldHVybiBgVm9sdW1lIGRpYXR1ciBzZWtpdGFyICR7bn0lYDsKICB9LAoKICBzcGVhazogYXN5bmMgKHsgdGV4dCB9KSA9PiB7CiAgICBhd2FpdCBwcygiQWRkLVR5cGUgLUFzc2VtYmx5TmFtZSBTeXN0ZW0uU3BlZWNoOyAkcyA9IE5ldy1PYmplY3Qg
::B64:agent.js:U3lzdGVtLlNwZWVjaC5TeW50aGVzaXMuU3BlZWNoU3ludGhlc2l6ZXI7ICRzLlNwZWFrKCRlbnY6VFhUKSIsIHsgVFhUOiBTdHJpbmcodGV4dCkuc2xpY2UoMCwgNTAwKSB9LCA2MDAwMCk7CiAgICByZXR1cm4gIm9rLCBkaXVjYXBrYW4iOwogIH0sCgogIHNldF90
::B64:agent.js:aW1lcjogYXN5bmMgKHsgYW1vdW50LCB1bml0ID0gIm1lbml0IiwgbWVzc2FnZSA9ICJXYWt0dW55YSEiIH0pID0+IHsKICAgIGNvbnN0IG11bHQgPSAvZGV0aWsvaS50ZXN0KFN0cmluZyh1bml0KSkgPyAxMDAwIDogL2phbS9pLnRlc3QoU3RyaW5nKHVuaXQpKSA/
::B64:agent.js:IDM2MDAwMDAgOiA2MDAwMDsKICAgIGNvbnN0IG1zID0gTWF0aC5yb3VuZChOdW1iZXIoU3RyaW5nKGFtb3VudCkucmVwbGFjZSgiLCIsICIuIikpICogbXVsdCk7CiAgICBpZiAoIShtcyA+IDApIHx8IG1zID4gMjQgKiAzNjAwMDAwKSB0aHJvdyBuZXcgRXJyb3Io
::B64:agent.js:IkR1cmFzaSB0aWRhayB2YWxpZCAobWFrc2ltYWwgMjQgamFtKSIpOwogICAgdGltZXJzLnB1c2goCiAgICAgIHNldFRpbWVvdXQoYXN5bmMgKCkgPT4gewogICAgICAgIGNvbnNvbGUubG9nKGBcbioqKiBQRU5HSU5HQVQ6ICR7bWVzc2FnZX0gKioqYCk7CiAgICAg
::B64:agent.js:ICAgdHJ5IHsKICAgICAgICAgIGF3YWl0IHBzKCJbY29uc29sZV06OkJlZXAoODgwLDMwMCk7IFtjb25zb2xlXTo6QmVlcCgxMTc1LDQwMCk7IEFkZC1UeXBlIC1Bc3NlbWJseU5hbWUgU3lzdGVtLlNwZWVjaDsgKE5ldy1PYmplY3QgU3lzdGVtLlNwZWVjaC5TeW50
::B64:agent.js:aGVzaXMuU3BlZWNoU3ludGhlc2l6ZXIpLlNwZWFrKCRlbnY6VFhUKSIsIHsgVFhUOiBTdHJpbmcobWVzc2FnZSkgfSwgNjAwMDApOwogICAgICAgIH0gY2F0Y2gge30KICAgICAgfSwgbXMpCiAgICApOwogICAgcmV0dXJuIGBQZW5naW5nYXQgZGlhdHVyICR7YW1v
::B64:agent.js:dW50fSAke3VuaXR9IGxhZ2k6ICIke21lc3NhZ2V9IiAoYWt0aWYgc2VsYW1hIGFnZW50IHRlcmJ1a2EpYDsKICB9LAoKICBsaXN0X3Byb2Nlc3NlczogYXN5bmMgKHsgZmlsdGVyIH0pID0+IHsKICAgIGNvbnN0IG91dCA9IGF3YWl0IHBzKAogICAgICBgJGYgPSAk
::B64:agent.js:ZW52OkYKR2V0LVByb2Nlc3MgfCBXaGVyZS1PYmplY3QgeyAkXy5Qcm9jZXNzTmFtZSAtbGlrZSAoIioiICsgJGYgKyAiKiIpIH0gfCBTb3J0LU9iamVjdCBXb3JraW5nU2V0NjQgLURlc2NlbmRpbmcgfCBTZWxlY3QtT2JqZWN0IC1GaXJzdCAxNSB8IEZvckVhY2gt
::B64:agent.js:T2JqZWN0IHsgJF8uUHJvY2Vzc05hbWUgKyAiIHwgUElEICIgKyAkXy5JZCArICIgfCAiICsgW21hdGhdOjpSb3VuZCgkXy5Xb3JraW5nU2V0NjQgLyAxTUIpICsgIiBNQiIgKyAkKGlmICgkXy5NYWluV2luZG93VGl0bGUpIHsgIiB8ICIgKyAkXy5NYWluV2luZG93
::B64:agent.js:VGl0bGUgfSBlbHNlIHsgIiIgfSkgfWAsCiAgICAgIHsgRjogU3RyaW5nKGZpbHRlciB8fCAiIikgfQogICAgKTsKICAgIHJldHVybiBvdXQgfHwgIlRpZGFrIGFkYSBwcm9zZXMgeWFuZyBjb2NvayI7CiAgfSwKCiAga2lsbF9wcm9jZXNzOiBhc3luYyAoeyBuYW1l
::B64:agent.js:IH0pID0+IHsKICAgIGNvbnN0IG4gPSBTdHJpbmcobmFtZSkudHJpbSgpLnJlcGxhY2UoL1wuZXhlJC9pLCAiIik7CiAgICBpZiAoIS9eW1x3XVtcdyAuKCktXXswLDU5fSQvLnRlc3QobikpIHRocm93IG5ldyBFcnJvcigiTmFtYSBwcm9zZXMgdGlkYWsgdmFsaWQi
::B64:agent.js:KTsKICAgIGlmICgvXihzeXN0ZW18aWRsZXxyZWdpc3RyeXxzbXNzfGNzcnNzfHdpbmluaXR8d2lubG9nb258c2VydmljZXN8bHNhc3N8c3ZjaG9zdHxkd218Zm9udGRydmhvc3R8ZXhwbG9yZXJ8c2lob3N0fGN0Zm1vbnxub2RlfGNocm9tZXxtc2VkZ2UpJC9pLnRl
::B64:agent.js:c3QobikpIHsKICAgICAgdGhyb3cgbmV3IEVycm9yKGBQcm9zZXMgIiR7bn0iIGRpbGluZHVuZ2kgKHBlbnRpbmcgdW50dWsgV2luZG93cyBhdGF1IGRpcGFrYWkgYWdlbnQpLiBVbnR1ayB0YWIgYXRhdSBqZW5kZWxhIGJyb3dzZXIgZ3VuYWthbiBjbG9zZV90YWIg
::B64:agent.js:YXRhdSBjbG9zZV93aW5kb3cuYCk7CiAgICB9CiAgICBpZiAoIShhd2FpdCBhc2soYE1hdGlrYW4gcHJvc2VzOiAke259YCkpKSByZXR1cm4gIkRpYmF0YWxrYW4gdXNlciI7CiAgICByZXR1cm4gcHMoCiAgICAgIGAkcCA9IEAoR2V0LVByb2Nlc3MgLU5hbWUgJGVu
::B64:agent.js:djpOIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlKQppZiAoJHAuQ291bnQgLWVxIDApIHsgIlByb3NlcyB0aWRhayBkaXRlbXVrYW4gKHNlZGFuZyB0aWRhayBiZXJqYWxhbik6ICIgKyAkZW52Ok4gfSBlbHNlIHsgJHAgfCBTdG9wLVByb2Nlc3MgLUZvcmNl
::B64:agent.js:OyAib2ssIGRpaGVudGlrYW4gIiArICRwLkNvdW50ICsgIiBwcm9zZXMgIiArICRlbnY6TiB9YCwKICAgICAgeyBOOiBuIH0KICAgICk7CiAgfSwKCiAgbW9yZV90b29sczogYXN5bmMgKHsgZ3JvdXAgfSkgPT4gewogICAgY29uc3QgZyA9IFN0cmluZyhncm91cCku
::B64:agent.js:dG9Mb3dlckNhc2UoKTsKICAgIGlmICghVE9PTF9HUk9VUFNbZ10pIHJldHVybiAiR3J1cCB0aWRhayBkaWtlbmFsLiBQaWxpaDogIiArIE9iamVjdC5rZXlzKFRPT0xfR1JPVVBTKS5qb2luKCIsICIpOwogICAgZXh0cmFHcm91cHMuYWRkKGcpOwogICAgcmV0dXJu
::B64:agent.js:IGBBbGF0IGdydXAgJHtnfSBzZWthcmFuZyB0ZXJzZWRpYTogJHtUT09MX0dST1VQU1tnXS5qb2luKCIsICIpfWA7CiAgfSwKCiAgZ2V0X3BhZ2VfdGV4dDogYXN5bmMgKCkgPT4gKGF3YWl0IHBhZ2UuaW5uZXJUZXh0KCJib2R5IikpLnNsaWNlKDAsIDQwMDApLAoK
::B64:agent.js:ICB0eXBlX3RleHQ6IGFzeW5jICh7IHNlbGVjdG9yLCB0ZXh0IH0pID0+IHsKICAgIGF3YWl0IHBhZ2UuZmlsbChzZWxlY3RvciwgdGV4dCk7CiAgICByZXR1cm4gIm9rIjsKICB9LAoKICBjbGljazogYXN5bmMgKHsgc2VsZWN0b3IgfSkgPT4gewogICAgaWYgKCEo
::B64:agent.js:YXdhaXQgYXNrKGBLbGlrIGVsZW1lbiBicm93c2VyOiAke3NlbGVjdG9yfWApKSkgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgYXdhaXQgcGFnZS5jbGljayhzZWxlY3RvciwgeyB0aW1lb3V0OiAxMDAwMCB9KTsKICAgIHJldHVybiAib2siOwogIH0sCgog
::B64:agent.js:IHVwbG9hZF9maWxlOiBhc3luYyAoeyBzZWxlY3RvciwgZmlsZW5hbWUsIGZvbGRlciwgcGF0dGVybiB9KSA9PiB7CiAgICBsZXQgZmlsZXMgPSBbXTsKICAgIGlmIChmaWxlbmFtZSkgewogICAgICBmaWxlcyA9IFN0cmluZyhmaWxlbmFtZSkKICAgICAgICAuc3Bs
::B64:agent.js:aXQoInwiKQogICAgICAgIC5tYXAoKHgpID0+IHgudHJpbSgpKQogICAgICAgIC5maWx0ZXIoQm9vbGVhbikKICAgICAgICAubWFwKHNhZmVQYXRoKTsKICAgIH0KICAgIGlmIChmb2xkZXIpIHsKICAgICAgY29uc3QgZGlyID0gcGF0aC5yZXNvbHZlKFN0cmluZyhm
::B64:agent.js:b2xkZXIpKTsKICAgICAgY29uc3QgcSA9IHBhdHRlcm4gPyBTdHJpbmcocGF0dGVybikudG9Mb3dlckNhc2UoKS5yZXBsYWNlKC9eXCovLCAiIikgOiAiIjsKICAgICAgZm9yIChjb25zdCBlIG9mIGZzLnJlYWRkaXJTeW5jKGRpciwgeyB3aXRoRmlsZVR5cGVzOiB0
::B64:agent.js:cnVlIH0pKSB7CiAgICAgICAgaWYgKGUuaXNGaWxlKCkgJiYgKCFxIHx8IGUubmFtZS50b0xvd2VyQ2FzZSgpLmluY2x1ZGVzKHEpKSkgZmlsZXMucHVzaChwYXRoLmpvaW4oZGlyLCBlLm5hbWUpKTsKICAgICAgfQogICAgfQogICAgaWYgKCFmaWxlcy5sZW5ndGgp
::B64:agent.js:IHRocm93IG5ldyBFcnJvcigiVGlkYWsgYWRhIGZpbGUgeWFuZyBjb2NvayB1bnR1ayBkaXVwbG9hZCIpOwogICAgZmlsZXMgPSBmaWxlcy5zbGljZSgwLCA1MCk7CiAgICBpZiAoIShhd2FpdCBhc2soYFVwbG9hZCAke2ZpbGVzLmxlbmd0aH0gZmlsZTpcbiAgICR7
::B64:agent.js:ZmlsZXMuam9pbigiXG4gICAiKX1cbiAgYCkpKSByZXR1cm4gIkRpYmF0YWxrYW4gdXNlciI7CiAgICBjb25zdCBtdWx0aXBsZSA9IGF3YWl0IHBhZ2UuJGV2YWwoc2VsZWN0b3IsIChlbCkgPT4gISFlbC5tdWx0aXBsZSkuY2F0Y2goKCkgPT4gZmFsc2UpOwogICAg
::B64:agent.js:aWYgKGZpbGVzLmxlbmd0aCA+IDEgJiYgIW11bHRpcGxlKSB7CiAgICAgIGF3YWl0IHBhZ2Uuc2V0SW5wdXRGaWxlcyhzZWxlY3RvciwgZmlsZXNbMF0pOwogICAgICByZXR1cm4gKAogICAgICAgIGBJbnB1dCBpbmkgaGFueWEgbWVuZXJpbWEgMSBmaWxlLiBUZXJw
::B64:agent.js:aWxpaDogJHtmaWxlc1swXX0uIFNpc2EgJHtmaWxlcy5sZW5ndGggLSAxfSBmaWxlOiBgICsKICAgICAgICBgJHtmaWxlcy5zbGljZSgxKS5qb2luKCIgfCAiKX0uIFNlbGVzYWlrYW4gdXBsb2FkIGluaSwgbGFsdSB1bGFuZ2kgdXBsb2FkX2ZpbGUgdW50dWsgc2lz
::B64:agent.js:YW55YS5gCiAgICAgICk7CiAgICB9CiAgICBhd2FpdCBwYWdlLnNldElucHV0RmlsZXMoc2VsZWN0b3IsIGZpbGVzKTsKICAgIHJldHVybiBgb2ssICR7ZmlsZXMubGVuZ3RofSBmaWxlIGRpcGlsaWhgOwogIH0sCn07Cgpjb25zdCBmbiA9IChuYW1lLCBkZXNjcmlw
::B64:agent.js:dGlvbiwgcHJvcGVydGllcyA9IHt9LCBvcHRpb25hbCA9IFtdKSA9PiAoewogIHR5cGU6ICJmdW5jdGlvbiIsCiAgZnVuY3Rpb246IHsKICAgIG5hbWUsCiAgICBkZXNjcmlwdGlvbiwKICAgIHBhcmFtZXRlcnM6IHsKICAgICAgdHlwZTogIm9iamVjdCIsCiAgICAg
::B64:agent.js:IHByb3BlcnRpZXMsCiAgICAgIHJlcXVpcmVkOiBPYmplY3Qua2V5cyhwcm9wZXJ0aWVzKS5maWx0ZXIoKGspID0+ICFvcHRpb25hbC5pbmNsdWRlcyhrKSksCiAgICB9LAogIH0sCn0pOwpjb25zdCBzdHIgPSAoZCkgPT4gKHsgdHlwZTogInN0cmluZyIsIGRlc2Ny
::B64:agent.js:aXB0aW9uOiBkIH0pOwpjb25zdCBudW0gPSAoZCkgPT4gKHsgdHlwZTogIm51bWJlciIsIGRlc2NyaXB0aW9uOiBkIH0pOwpjb25zdCBib29sID0gKGQpID0+ICh7IHR5cGU6ICJib29sZWFuIiwgZGVzY3JpcHRpb246IGQgfSk7Cgpjb25zdCB0b29scyA9IFsKICBm
::B64:agent.js:bigiZmluZF9mb2xkZXIiLCAiQ2FyaSBmb2xkZXIgZGkgc2VsdXJ1aCBQQyAoc2VtdWEgZHJpdmUpIGJlcmRhc2Fya2FuIG5hbWE7IHNlYmFnaWFuIG5hbWEgY3VrdXAiLCB7IG5hbWU6IHN0cigiTmFtYSBmb2xkZXIiKSB9KSwKICBmbigiZmluZF9maWxlIiwgIkNh
::B64:agent.js:cmkgZmlsZSBkaSBzZWx1cnVoIFBDIChzZW11YSBkcml2ZSkgYmVyZGFzYXJrYW4gbmFtYTsgc2ViYWdpYW4gbmFtYSBjdWt1cCIsIHsgbmFtZTogc3RyKCJOYW1hIGZpbGUiKSB9KSwKICBmbigibGlzdF9kaXIiLCAiTGloYXQgaXNpIHNlYnVhaCBmb2xkZXIgZGkg
::B64:agent.js:UEMiLCB7IHBhdGg6IHN0cigiUGF0aCBsZW5na2FwIGZvbGRlciIpIH0pLAogIGZuKCJvcGVuX3BhdGgiLCAiQnVrYSBmb2xkZXIsIGZpbGUsIGFwbGlrYXNpIChtaXMuIG5vdGVwYWQpLCBhdGF1IFVSTCBkaSBQQyIsIHsgdGFyZ2V0OiBzdHIoIlBhdGgvbmFtYSBh
::B64:agent.js:cGxpa2FzaS9VUkwiKSB9KSwKICBmbigic2NyZWVuc2hvdCIsICJBbWJpbCBzY3JlZW5zaG90IGxheWFyIFBDIHVudHVrIG1lbGloYXQga29uZGlzaSBzZWthcmFuZyIpLAogIGZuKAogICAgImNsaWNrX3NjcmVlbiIsCiAgICAiS2xpayBkaSBsYXlhciBQQyBwYWRh
::B64:agent.js:IGtvb3JkaW5hdCBkYXJpIHNjcmVlbnNob3QgdGVyYWtoaXIiLAogICAgeyB4OiBudW0oIktvb3JkaW5hdCBYIGRpIHNjcmVlbnNob3QiKSwgeTogbnVtKCJLb29yZGluYXQgWSBkaSBzY3JlZW5zaG90IiksIGJ1dHRvbjogc3RyKCJsZWZ0IGF0YXUgcmlnaHQiKSwg
::B64:agent.js:ZG91YmxlOiB7IHR5cGU6ICJib29sZWFuIiwgZGVzY3JpcHRpb246ICJkb3VibGUta2xpayIgfSB9LAogICAgWyJidXR0b24iLCAiZG91YmxlIl0KICApLAogIGZuKCJzY3JvbGxfc2NyZWVuIiwgIlNjcm9sbCBsYXlhci4gUG9zaXRpZiA9IHR1cnVuLCBuZWdhdGlm
::B64:agent.js:ID0gbmFpayIsIHsgYW1vdW50OiBudW0oIkp1bWxhaCBzY3JvbGwiKSB9KSwKICBmbigidHlwZV9kZXNrdG9wIiwgIktldGlrIHRla3MgZGkgYXBsaWthc2kgeWFuZyBzZWRhbmcgZm9rdXMgZGkgUEMiLCB7IHRleHQ6IHN0cigiVGVrcyIpIH0pLAogIGZuKCJwcmVz
::B64:agent.js:c19rZXlzIiwgIlRla2FuIHRvbWJvbCBmb3JtYXQgU2VuZEtleXM6IHtFTlRFUn0sIHtUQUJ9LCB7RVNDfSwgXmMgKEN0cmwrQyksIF52LCBebCwgJXtGNH0iLCB7IGtleXM6IHN0cigiS29tYmluYXNpIHRvbWJvbCIpIH0pLAogIGZuKCJ3YWl0IiwgIlR1bmdndSBi
::B64:agent.js:ZWJlcmFwYSBkZXRpayAobWFrcyAxNSkgc3VwYXlhIGhhbGFtYW4vYXBsaWthc2kgc2VsZXNhaSBkaW11YXQiLCB7IHNlY29uZHM6IG51bSgiRGV0aWsiKSB9KSwKICBmbigibGlzdF9maWxlcyIsICJMaWhhdCBkYWZ0YXIgZmlsZSBkaSBmb2xkZXIgdXBsb2FkIGto
::B64:agent.js:dXN1cyIpLAogIGZuKAogICAgIm9wZW5fdXJsIiwKICAgICJCdWthIHdlYnNpdGUgZGkgYnJvd3Nlci4gU2VjYXJhIGJhd2FhbiBtZW5pbXBhIHRhYiBha3RpZjsgcGFrYWkgbmV3X3RhYj10cnVlIGFnYXIgaGFsYW1hbi92aWRlbyB5YW5nIHNlZGFuZyB0ZXJidWth
::B64:agent.js:IHRpZGFrIHRlcnRpbXBhIiwKICAgIHsgdXJsOiBzdHIoIlVSTCBsZW5na2FwIiksIG5ld190YWI6IGJvb2woInRydWUgPSBidWthIGRpIHRhYiBiYXJ1IikgfSwKICAgIFsibmV3X3RhYiJdCiAgKSwKICBmbigibGlzdF90YWJzIiwgIkRhZnRhciBzZW11YSB0YWIg
::B64:agent.js:YnJvd3NlciAodGFuZGEgKiA9IHRhYiBha3RpZikiKSwKICBmbigibmV3X3RhYiIsICJCdWthIHRhYiBiYXJ1IChrb3NvbmcsIGF0YXUgbGFuZ3N1bmcga2UgVVJMKSBkYW4gamFkaWthbiB0YWIgYWt0aWYiLCB7IHVybDogc3RyKCJVUkwgKG9wc2lvbmFsKSIpIH0s
::B64:agent.js:IFsidXJsIl0pLAogIGZuKCJvcGVuX3VybHMiLCAiQnVrYSBCQU5ZQUsgd2Vic2l0ZSBzZWthbGlndXMsIG1hc2luZy1tYXNpbmcgZGkgdGFiIGJhcnUiLCB7CiAgICB1cmxzOiB7IHR5cGU6ICJhcnJheSIsIGl0ZW1zOiB7IHR5cGU6ICJzdHJpbmciIH0sIGRlc2Ny
::B64:agent.js:aXB0aW9uOiAiRGFmdGFyIFVSTCAobWFrc2ltYWwgMTApIiB9LAogIH0pLAogIGZuKAogICAgInN3aXRjaF90YWIiLAogICAgIlBpbmRhaCB0YWIgYWt0aWYuIFBha2FpIGluZGV4ICgxID0gdGFiIHBlcnRhbWEsIC0xID0gdGFiIHRlcmJhcnUpIEFUQVUgbWF0Y2gg
::B64:agent.js:KHNlYmFnaWFuIGp1ZHVsL1VSTCkiLAogICAgeyBpbmRleDogbnVtKCJOb21vciB0YWIsIC0xID0gdGVyYmFydSIpLCBtYXRjaDogc3RyKCJTZWJhZ2lhbiBqdWR1bCBhdGF1IFVSTCB0YWIiKSB9LAogICAgWyJpbmRleCIsICJtYXRjaCJdCiAgKSwKICBmbigiY2xv
::B64:agent.js:c2VfdGFiIiwgIlR1dHVwIHRhYiAoYmF3YWFuOiB0YWIgYWt0aWYpLCBhdGF1IHRhYiBkZW5nYW4gbm9tb3IgdGVydGVudHUiLCB7IGluZGV4OiBudW0oIk5vbW9yIHRhYiwgLTEgPSB0ZXJiYXJ1IikgfSwgWyJpbmRleCJdKSwKICBmbigiaW5zcGVjdF9wYWdlIiwg
::B64:agent.js:IkRhZnRhciB0b21ib2wvaW5wdXQgZGkgaGFsYW1hbiBicm93c2VyIHVudHVrIG1lbmNhcmkgQ1NTIHNlbGVjdG9yIiksCiAgZm4oCiAgICAieW91dHViZV9wbGF5IiwKICAgICJDYXJpIHZpZGVvIGRpIFlvdVR1YmUgbGFsdSBPVE9NQVRJUyBtZW11dGFyIGhhc2ls
::B64:agent.js:IHBpbGloYW4gZGkgYnJvd3NlciBhZ2VudC4gUGFrYWkgaW5pIHVudHVrIHNlbXVhIHBlcm1pbnRhYW4gbm9udG9uL2NhcmkgdmlkZW8vbGFndSBkaSBZb3VUdWJlLiIsCiAgICB7CiAgICAgIHF1ZXJ5OiBzdHIoIkthdGEga3VuY2kgcGVuY2FyaWFuIiksCiAgICAg
::B64:agent.js:IHBpY2s6IG51bSgiVXJ1dGFuIGhhc2lsIHlhbmcgZGlwdXRhciwgMS01IChkZWZhdWx0IDEpIiksCiAgICAgIG5ld190YWI6IGJvb2woInRydWUgPSBwdXRhciBkaSB0YWIgYmFydSBzdXBheWEgdGFiIGFrdGlmIHRpZGFrIHRlcnRpbXBhIiksCiAgICB9LAogICAg
::B64:agent.js:WyJwaWNrIiwgIm5ld190YWIiXQogICksCiAgZm4oImRvbmUiLCAiUGFuZ2dpbCBpbmkgamlrYSB0dWdhcyBTRUxFU0FJLCBhdGF1IGppa2EgcGVybHUgYmVydGFueWEvbWVsYXBvciBrZSB1c2VyIiwgeyBtZXNzYWdlOiBzdHIoIlBlc2FuIHNpbmdrYXQgdW50dWsg
::B64:agent.js:dXNlciIpIH0pLAogIGZuKAogICAgInlvdXR1YmVfY29udHJvbCIsCiAgICAiS29udHJvbCB2aWRlbyBZb3VUdWJlIHlhbmcgc2VkYW5nIHRlcmJ1a2EiLAogICAgeyBhY3Rpb246IHN0cigicGxheSwgcGF1c2UsIHRvZ2dsZSwgbXV0ZSwgdW5tdXRlLCBmb3J3YXJk
::B64:agent.js:LCBiYWNrd2FyZCwgbmV4dCwgcHJldmlvdXMsIGZ1bGxzY3JlZW4iKSwgc2Vjb25kczogbnVtKCJEZXRpayB1bnR1ayBmb3J3YXJkL2JhY2t3YXJkIChkZWZhdWx0IDEwKSIpIH0sCiAgICBbInNlY29uZHMiXQogICksCiAgZm4oIndlYl9zZWFyY2giLCAiQ2FyaSBp
::B64:agent.js:bmZvcm1hc2kgZGkgaW50ZXJuZXQsIG1lbmdlbWJhbGlrYW4ganVkdWwsIGxpbmssIGRhbiBjdXBsaWthbiBoYXNpbCIsIHsKICAgIHF1ZXJ5OiBzdHIoIkthdGEga3VuY2kiKSwKICAgIG5ld190YWI6IGJvb2woInRydWUgPSBjYXJpIGRpIHRhYiBiYXJ1IHN1cGF5
::B64:agent.js:YSB0YWIgYWt0aWYgdGlkYWsgdGVydGltcGEiKSwKICB9LCBbIm5ld190YWIiXSksCiAgZm4oInNjcm9sbF9wYWdlIiwgIlNjcm9sbCBoYWxhbWFuIGJyb3dzZXIuIFBvc2l0aWYgPSB0dXJ1biwgbmVnYXRpZiA9IG5haWsiLCB7IGFtb3VudDogbnVtKCJKdW1sYWgg
::B64:agent.js:c2Nyb2xsIikgfSksCiAgZm4oIndhaXRfZm9yX3VzZXIiLCAiQmVyaGVudGkgZGFuIG1pbnRhIHVzZXIgbWVsYWt1a2FuIHNlc3VhdHUgc2VuZGlyaSAobG9naW4sIGNhcHRjaGEsIHZlcmlmaWthc2kpLCBsYWx1IHR1bmdndSBFbnRlciIsIHsgbWVzc2FnZTogc3Ry
::B64:agent.js:KCJJbnN0cnVrc2kgdW50dWsgdXNlciIpIH0pLAogIGZuKCJkb3dubG9hZF9maWxlIiwgIlVuZHVoIGZpbGUgZGFyaSBpbnRlcm5ldCBrZSBmb2xkZXIgRG93bmxvYWRzIiwgeyB1cmw6IHN0cigiVVJMIGh0dHAocykiKSwgZmlsZW5hbWU6IHN0cigiTmFtYSBmaWxl
::B64:agent.js:IChvcHNpb25hbCkiKSB9LCBbImZpbGVuYW1lIl0pLAogIGZuKCJub3ciLCAiVGFuZ2dhbCBkYW4gamFtIHNla2FyYW5nIiksCiAgZm4oInN5c3RlbV9pbmZvIiwgIkluZm8gUEM6IE9TLCBDUFUsIFJBTSwgYmF0ZXJhaSwgcnVhbmcgZGlzayIpLAogIGZuKAogICAg
::B64:agent.js:Im1lZGlhX2tleSIsCiAgICAiVG9tYm9sIG1lZGlhIGRhbiB2b2x1bWUgZ2xvYmFsIFdpbmRvd3MiLAogICAgeyBrZXk6IHN0cigidm9sdXAsIHZvbGRvd24sIG11dGUsIHBsYXlwYXVzZSwgbmV4dCwgcHJldiIpLCB0aW1lczogbnVtKCJKdW1sYWggdGVrYW4gKHZv
::B64:agent.js:bHVtZSBiZXJ1YmFoIDIlIHBlciB0ZWthbikiKSB9LAogICAgWyJ0aW1lcyJdCiAgKSwKICBmbigiY2xpcGJvYXJkX2dldCIsICJCYWNhIGlzaSBjbGlwYm9hcmQiKSwKICBmbigiY2xpcGJvYXJkX3NldCIsICJJc2kgY2xpcGJvYXJkIiwgeyB0ZXh0OiBzdHIoIlRl
::B64:agent.js:a3MiKSB9KSwKICBmbigibGlzdF93aW5kb3dzIiwgIkRhZnRhciBqZW5kZWxhIGF0YXUgYXBsaWthc2kgeWFuZyBzZWRhbmcgdGVyYnVrYSIpLAogIGZuKCJmb2N1c193aW5kb3ciLCAiUGluZGFoa2FuIGZva3VzIGtlIHNlYnVhaCBqZW5kZWxhIiwgeyB0aXRsZTog
::B64:agent.js:c3RyKCJTZWJhZ2lhbiBqdWR1bCBqZW5kZWxhIikgfSksCiAgZm4oImNsb3NlX3dpbmRvdyIsICJUdXR1cCBzZWJ1YWggamVuZGVsYSBkZW5nYW4gYmFpay1iYWlrIiwgeyB0aXRsZTogc3RyKCJTZWJhZ2lhbiBqdWR1bCBqZW5kZWxhIikgfSksCiAgZm4oInJlYWRf
::B64:agent.js:dGV4dF9maWxlIiwgIkJhY2EgaXNpIGZpbGUgdGVrcyIsIHsgcGF0aDogc3RyKCJQYXRoIGxlbmdrYXAgZmlsZSIpIH0pLAogIGZuKCJ3cml0ZV90ZXh0X2ZpbGUiLCAiVHVsaXMgYXRhdSB0YW1iYWggaXNpIGZpbGUgdGVrcyIsIHsgcGF0aDogc3RyKCJQYXRoIGxl
::B64:agent.js:bmdrYXAgZmlsZSIpLCBjb250ZW50OiBzdHIoIklzaSIpLCBhcHBlbmQ6IHsgdHlwZTogImJvb2xlYW4iLCBkZXNjcmlwdGlvbjogInRydWUgPSB0YW1iYWhrYW4sIGJ1a2FuIG1lbmltcGEiIH0gfSwgWyJhcHBlbmQiXSksCiAgZm4oIm1ha2VfZm9sZGVyIiwgIkJ1
::B64:agent.js:YXQgZm9sZGVyIGJhcnUiLCB7IHBhdGg6IHN0cigiUGF0aCBsZW5na2FwIGZvbGRlciIpIH0pLAogIGZuKCJtb3ZlX3BhdGgiLCAiUGluZGFoa2FuIGF0YXUgZ2FudGkgbmFtYSBmaWxlL2ZvbGRlciIsIHsgZnJvbTogc3RyKCJQYXRoIGFzYWwiKSwgdG86IHN0cigi
::B64:agent.js:UGF0aCB0dWp1YW4iKSB9KSwKICBmbigicmVjeWNsZV9wYXRoIiwgIkhhcHVzIGZpbGUvZm9sZGVyIGRlbmdhbiBtZW1pbmRhaGthbm55YSBrZSBSZWN5Y2xlIEJpbiIsIHsgcGF0aDogc3RyKCJQYXRoIGxlbmdrYXAiKSB9KSwKICBmbigiemlwX3BhdGgiLCAiS29t
::B64:agent.js:cHJlcyBmaWxlIGF0YXUgZm9sZGVyIG1lbmphZGkgLnppcCIsIHsgc291cmNlOiBzdHIoIlBhdGggZmlsZS9mb2xkZXIiKSwgemlwOiBzdHIoIlBhdGggZmlsZSAuemlwIGhhc2lsIikgfSksCiAgZm4oInVuemlwX3BhdGgiLCAiRWtzdHJhayBmaWxlIC56aXAiLCB7
::B64:agent.js:IHppcDogc3RyKCJQYXRoIGZpbGUgLnppcCIpLCBmb2xkZXI6IHN0cigiRm9sZGVyIHR1anVhbiIpIH0pLAogIGZuKAogICAgImZhc3RfdXBsb2FkIiwKICAgICJVUExPQUQgQ0VQQVQgZGFsYW0gc2F0dSBsYW5na2FoIChkYWh1bHVrYW4gYWxhdCBpbmkgdW50dWsg
::B64:agent.js:c2VtdWEgcGVybWludGFhbiB1cGxvYWQpOiBidWthIFVSTCBkaSB0YWIgYmFydSwgdGVtdWthbiB0b21ib2wvaW5wdXQgdXBsb2FkIG90b21hdGlzLCBwaWxpaCBzYXR1L2JhbnlhayBmaWxlIGF0YXUgaXNpIGZvbGRlciAoZm9sZGVyIHR1bmdnYWwgZGlraXJpbSBz
::B64:agent.js:ZWJhZ2FpIHppcCksIGtsaWsgdG9tYm9sIGtpcmltLCB0dW5nZ3Ugc2VsZXNhaSwga2VtYmFsaWthbiBsaW5rIGppa2EgdGVyZGV0ZWtzaS4gSmlrYSBoYWxhbWFuIHN1ZGFoIHRlcmJ1a2EsIHVybCBib2xlaCBrb3NvbmcuIiwKICAgIHsKICAgICAgdXJsOiBzdHIo
::B64:agent.js:IkFsYW1hdCBzaXR1cyB1cGxvYWQgKG9wc2lvbmFsIGppa2EgaGFsYW1hbiBzdWRhaCB0ZXJidWthKSIpLAogICAgICBmaWxlbmFtZTogc3RyKCJQYXRoIGZpbGUgKGJhbnlhayBkaXBpc2FoIHwpIGF0YXUgcGF0aCBmb2xkZXIgKGFrYW4gZGktemlwKSIpLAogICAg
::B64:agent.js:ICBmb2xkZXI6IHN0cigiRm9sZGVyIGJlcmlzaSBmaWxlIHlhbmcgZGl1cGxvYWQgc2VtdWFueWEgKG9wc2lvbmFsKSIpLAogICAgICBwYXR0ZXJuOiBzdHIoIkZpbHRlciBuYW1hIGZpbGUgZGkgZm9sZGVyLCBtaXNhbCAucGRmIGF0YXUgLmpwZ3wucG5nIChvcHNp
::B64:agent.js:b25hbCkiKSwKICAgICAgc3VibWl0OiBib29sKCJmYWxzZSA9IGphbmdhbiBrbGlrIHRvbWJvbCBraXJpbSBvdG9tYXRpcyAoZGVmYXVsdCB0cnVlKSIpLAogICAgICBuZXdfdGFiOiBib29sKCJmYWxzZSA9IHBha2FpIHRhYiBha3RpZiAoZGVmYXVsdCB0cnVlKSIp
::B64:agent.js:LAogICAgfSwKICAgIFsidXJsIiwgImZpbGVuYW1lIiwgImZvbGRlciIsICJwYXR0ZXJuIiwgInN1Ym1pdCIsICJuZXdfdGFiIl0KICApLAogIGZuKCJyZWNlbnRfZmlsZXMiLCAiRGFmdGFyIGZpbGUgdGVyYmFydSBkaSBzZWJ1YWggZm9sZGVyIChiYXdhYW46IERv
::B64:agent.js:d25sb2FkcykiLCB7IGZvbGRlcjogc3RyKCJQYXRoIGZvbGRlciAob3BzaW9uYWwpIiksIGNvdW50OiBudW0oIkp1bWxhaCAoZGVmYXVsdCAxMCkiKSB9LCBbImZvbGRlciIsICJjb3VudCJdKSwKICBmbigic2VhcmNoX3RleHQiLCAiQ2FyaSB0ZWtzIGRpIGRhbGFt
::B64:agent.js:IGZpbGUgdGVrcy9rb2RlIHBhZGEgc2VidWFoIGZvbGRlciIsIHsgZm9sZGVyOiBzdHIoIlBhdGggZm9sZGVyIiksIHRleHQ6IHN0cigiVGVrcyB5YW5nIGRpY2FyaSIpIH0pLAogIGZuKCJjb3B5X3BhdGgiLCAiU2FsaW4gZmlsZSBhdGF1IGZvbGRlciIsIHsgZnJv
::B64:agent.js:bTogc3RyKCJQYXRoIGFzYWwiKSwgdG86IHN0cigiUGF0aCB0dWp1YW4iKSB9KSwKICBmbigic2F2ZV9zY3JlZW5zaG90IiwgIlNpbXBhbiBzY3JlZW5zaG90IGxheWFyIHBlbnVoIGtlIGZpbGUgKGJhd2FhbjogUGljdHVyZXNcXFNjcmVlbnNob3RzKSIsIHsgcGF0
::B64:agent.js:aDogc3RyKCJQYXRoIGZpbGUgLnBuZyAob3BzaW9uYWwpIikgfSwgWyJwYXRoIl0pLAogIGZuKCJzZXRfdm9sdW1lIiwgIkF0dXIgdm9sdW1lIFdpbmRvd3Mga2UgYW5na2EgdGVydGVudHUgKDAtMTAwKSIsIHsgbGV2ZWw6IG51bSgiUGVyc2VuIHZvbHVtZSIpIH0p
::B64:agent.js:LAogIGZuKCJzcGVhayIsICJVY2Fwa2FuIHRla3MgZGVuZ2FuIHN1YXJhIGtvbXB1dGVyIiwgeyB0ZXh0OiBzdHIoIlRla3MgeWFuZyBkaXVjYXBrYW4iKSB9KSwKICBmbigKICAgICJzZXRfdGltZXIiLAogICAgIkF0dXIgcGVuZ2luZ2F0OiBzZXRlbGFoIHdha3R1
::B64:agent.js:IHRlcnRlbnR1IG11bmN1bCBwZXNhbiwgYnVueWksIGRhbiBzdWFyYSAoYWt0aWYgc2VsYW1hIGFnZW50IHRlcmJ1a2EpIiwKICAgIHsgYW1vdW50OiBudW0oIkp1bWxhaCB3YWt0dSIpLCB1bml0OiBzdHIoImRldGlrLCBtZW5pdCwgYXRhdSBqYW0iKSwgbWVzc2Fn
::B64:agent.js:ZTogc3RyKCJQZXNhbiBwZW5naW5nYXQiKSB9LAogICAgWyJ1bml0IiwgIm1lc3NhZ2UiXQogICksCiAgZm4oImxpc3RfcHJvY2Vzc2VzIiwgIkRhZnRhciBwcm9zZXMgeWFuZyBzZWRhbmcgYmVyamFsYW4gKDE1IHRlcmJlc2FyKSwgYmlzYSBkaWZpbHRlciBuYW1h
::B64:agent.js:IiwgeyBmaWx0ZXI6IHN0cigiU2ViYWdpYW4gbmFtYSBwcm9zZXMgKG9wc2lvbmFsKSIpIH0sIFsiZmlsdGVyIl0pLAogIGZuKCJraWxsX3Byb2Nlc3MiLCAiTWF0aWthbiBwYWtzYSBzZWJ1YWggYXBsaWthc2kvZ2FtZS9wcm9zZXMgYmVyZGFzYXJrYW4gbmFtYSBw
::B64:agent.js:cm9zZXMsIG1pc2FsbnlhIGNzMiBhdGF1IG5vdGVwYWQgKHRhbnBhIC5leGUpLiBQYWthaSBpbmkgdW50dWsgbWVudXR1cCBhcGxpa2FzaSwgQlVLQU4gb3Blbl9wYXRoIiwgeyBuYW1lOiBzdHIoIk5hbWEgcHJvc2VzLCBjb250b2g6IGNzMiIpIH0pLAogIGZuKCJt
::B64:agent.js:b3JlX3Rvb2xzIiwgIkFrdGlma2FuIGtlbG9tcG9rIGFsYXQgdGFtYmFoYW4gamlrYSBhbGF0IHlhbmcga2FtdSBidXR1aGthbiBiZWx1bSB0ZXJzZWRpYSIsIHsKICAgIGdyb3VwOiBzdHIoInlvdXR1YmUsIHRhYnMsIGRlc2t0b3AsIGZpbGVzLCBhdGF1IHBjIiks
::B64:agent.js:CiAgfSksCiAgZm4oImdldF9wYWdlX3RleHQiLCAiQmFjYSB0ZWtzIGhhbGFtYW4gYnJvd3NlciBzYWF0IGluaSIpLAogIGZuKCJ0eXBlX3RleHQiLCAiSXNpIGtvbG9tIHRla3MgZGkgYnJvd3NlciIsIHsgc2VsZWN0b3I6IHN0cigiQ1NTIHNlbGVjdG9yIiksIHRl
::B64:agent.js:eHQ6IHN0cigiVGVrcyIpIH0pLAogIGZuKCJjbGljayIsICJLbGlrIGVsZW1lbiBkaSBicm93c2VyIiwgeyBzZWxlY3Rvcjogc3RyKCJDU1Mgc2VsZWN0b3IiKSB9KSwKICBmbigKICAgICJ1cGxvYWRfZmlsZSIsCiAgICAiVXBsb2FkIFNBVFUgYXRhdSBCQU5ZQUsg
::B64:agent.js:ZmlsZSBrZSBpbnB1dCBmaWxlIGRpIGJyb3dzZXIuIEJlYmVyYXBhIGZpbGUgZGkgZmlsZW5hbWUgZGlwaXNhaCB0YW5kYSB8LiBBdGF1IHBha2FpIGZvbGRlciAoKyBwYXR0ZXJuKSB1bnR1ayBtZW5ndW5nZ2FoIHNlbXVhIGZpbGUgZGkgZm9sZGVyIGl0dSIsCiAg
::B64:agent.js:ICB7CiAgICAgIHNlbGVjdG9yOiBzdHIoIkNTUyBzZWxlY3RvciBpbnB1dFt0eXBlPWZpbGVdIiksCiAgICAgIGZpbGVuYW1lOiBzdHIoIlBhdGggbGVuZ2thcCBmaWxlIChib2xlaCBiYW55YWssIGRpcGlzYWggfCksIGF0YXUgbmFtYSBmaWxlIGRpIHVwbG9hZC1m
::B64:agent.js:b2xkZXIiKSwKICAgICAgZm9sZGVyOiBzdHIoIkZvbGRlciBiZXJpc2kgZmlsZSB5YW5nIG1hdSBkaXVwbG9hZCBzZW11YW55YSAob3BzaW9uYWwpIiksCiAgICAgIHBhdHRlcm46IHN0cigiRmlsdGVyIG5hbWEgZmlsZSBkaSBmb2xkZXIsIG1pc2FsbnlhIC5wZGYg
::B64:agent.js:KG9wc2lvbmFsKSIpLAogICAgfSwKICAgIFsiZmlsZW5hbWUiLCAiZm9sZGVyIiwgInBhdHRlcm4iXQogICksCl07Cgpjb25zdCBTWVNURU0gPSBgS2FtdSBhZ2VudCB5YW5nIG1lbmdvbnRyb2wgUEMgV2luZG93cyBtaWxpayB1c2VyIGRhbiBicm93c2VyLiBLZXJq
::B64:agent.js:YWthbiBwZXJpbnRhaCB1c2VyIGRlbmdhbiBtZW1hbmdnaWwgdG9vbC4KQVRVUkFOIFBFTlRJTkc6Ci0gS2FtdSBIQVJVUyBzZWxhbHUgbWVtYW5nZ2lsIHRvb2wgZGkgc2V0aWFwIGxhbmdrYWguIEpBTkdBTiBwZXJuYWggbWVudWxpcyByZW5jYW5hLCBuYXJhc2ks
::B64:agent.js:IGF0YXUgInNheWEgYWthbiAuLi4iLiBMYW5nc3VuZyBwYW5nZ2lsIHRvb2wtbnlhLgotIFNldGVsYWggdHVnYXMgc2VsZXNhaSAoYXRhdSBwZXJsdSBiZXJ0YW55YSBrZSB1c2VyKSwgcGFuZ2dpbCB0b29sIGRvbmUgZGVuZ2FuIHBlc2FuIHNpbmdrYXQuCi0gTm9u
::B64:agent.js:dG9uL2NhcmkgdmlkZW8vbGFndSBkaSBZb3VUdWJlOiBsYW5nc3VuZyBwYW5nZ2lsIHlvdXR1YmVfcGxheSBkZW5nYW4ga2F0YSBrdW5jaSBkYXJpIHVzZXIuIEppa2EganVkdWwgeWFuZyBkaXB1dGFyIGt1cmFuZyBjb2NvaywgcGFuZ2dpbCBsYWdpIGRlbmdhbiBw
::B64:agent.js:aWNrIGxhaW4uCi0gVGFmc2lya2FuIHBlcmludGFoIHNpbmdrYXQvdHlwbyB1c2VyIGRlbmdhbiB3YWphciwgamFuZ2FuIGJlcnRhbnlhIGhhbCB5YW5nIGJpc2EgZGl0ZWJhay4KLSBLYW11IG1lbmdpbmdhdCBwZXJjYWthcGFuIHNlYmVsdW1ueWEuIEphd2FiYW4g
::B64:agent.js:c2luZ2thdCB1c2VyIChtaXNhbG55YSBzZWJ1YWggbmFtYSBmaWxlKSBhZGFsYWggamF3YWJhbiBhdGFzIHBlcnRhbnlhYW5tdSBzZWJlbHVtbnlhOyBsYW5qdXRrYW4gdHVnYXMgaXR1LCBqYW5nYW4gbXVsYWkgZGFyaSBub2wuCi0gTWVtYnVrYSBhcGxpa2FzaSBX
::B64:agent.js:aW5kb3dzIGxld2F0IG9wZW5fcGF0aDoga2FtZXJhID0gbWljcm9zb2Z0LndpbmRvd3MuY2FtZXJhOiAsIGthbGt1bGF0b3IgPSBjYWxjICwgbm90ZXBhZCA9IG5vdGVwYWQgLCBwYWludCA9IG1zcGFpbnQgLCBwZW5nYXR1cmFuID0gbXMtc2V0dGluZ3M6ICwgZmls
::B64:agent.js:ZSBleHBsb3JlciA9IGV4cGxvcmVyIC4KLSBVcGxvYWQgZmlsZSBrZSB3ZWJzaXRlOiBvcGVuX3VybCBrZSBoYWxhbWFuIHVwbG9hZCwgaW5zcGVjdF9wYWdlIHVudHVrIG1lbmNhcmkgaW5wdXQgdHlwZT1maWxlLCBsYWx1IHVwbG9hZF9maWxlIGRlbmdhbiBwYXRo
::B64:agent.js:IGxlbmdrYXAgZmlsZS4gSmlrYSBidXR1aCBsb2dpbiwgcGFuZ2dpbCBkb25lIGRhbiBtaW50YSB1c2VyIGxvZ2luIG1hbnVhbCBkaSBqZW5kZWxhIGJyb3dzZXIsIGxhbHUgdWxhbmdpLgotIEZvbGRlciBkaSBQQzogZmluZF9mb2xkZXIgbGFsdSBvcGVuX3BhdGgu
::B64:agent.js:IEZpbGUgZGkgUEM6IGZpbmRfZmlsZSAoYXRhdSBsaXN0X2RpcikgdW50dWsgbWVuZGFwYXQgcGF0aCBsZW5na2FwLCBsYWx1IG9wZW5fcGF0aCBhdGF1IHVwbG9hZF9maWxlLiBUaWRhayBhZGEgYmF0YXNhbiBsb2thc2ksIHNlbXVhIGRyaXZlIGJvbGVoIGRpYWtz
::B64:agent.js:ZXMuCi0gQXBsaWthc2kvamVuZGVsYSBkaSBQQzogc2NyZWVuc2hvdCBkdWx1IHVudHVrIG1lbGloYXQgbGF5YXIsIGxhbHUgY2xpY2tfc2NyZWVuL3R5cGVfZGVza3RvcC9wcmVzc19rZXlzLCBsYWx1IHNjcmVlbnNob3QgbGFnaSB1bnR1ayBtZW1lcmlrc2EgaGFz
::B64:agent.js:aWwuCi0gS29vcmRpbmF0IGtsaWsgaGFydXMgZGFyaSBzY3JlZW5zaG90IHRlcmFraGlyLgotIFVudHVrIG90b21hc2kgd2Vic2l0ZSBwYWthaSB0b29sIGJyb3dzZXIgKG9wZW5fdXJsLCBpbnNwZWN0X3BhZ2UsIHR5cGVfdGV4dCwgY2xpY2ssIHVwbG9hZF9maWxl
::B64:agent.js:KS4gU2VsYWx1IGluc3BlY3RfcGFnZSBzZWJlbHVtIGtsaWsuCi0gQnV0dWggbG9naW4sIGNhcHRjaGEsIGF0YXUgdmVyaWZpa2FzaTogcGFuZ2dpbCB3YWl0X2Zvcl91c2VyIGRhbiBtaW50YSB1c2VyIG1lbmdlcmpha2FubnlhIHNlbmRpcmkgZGkgamVuZGVsYSBi
::B64:agent.js:cm93c2VyLiBKQU5HQU4gcGVybmFoIG1lbWludGEgYXRhdSBtZW5nZXRpa2thbiBwYXNzd29yZCB1c2VyLgotIFBlcnRhbnlhYW4geWFuZyBidXR1aCBpbmZvIHRlcmJhcnU6IHdlYl9zZWFyY2gsIGxhbHUgb3Blbl91cmwgZGFuIGdldF9wYWdlX3RleHQgdW50dWsg
::B64:agent.js:bWVtYmFjYSBzdW1iZXJueWEuCi0gS29udHJvbCBtdXNpay92aWRlbzogeW91dHViZV9jb250cm9sIHVudHVrIHZpZGVvIFlvdVR1YmUsIG1lZGlhX2tleSB1bnR1ayB2b2x1bWUgZGFuIHRvbWJvbCBtZWRpYSBzZWx1cnVoIFBDLgotIFRBQjogSmFuZ2FuIG1lbmlt
::B64:agent.js:cGEgaGFsYW1hbiB5YW5nIG1hc2loIGRpcGFrYWkuIEppa2EgdXNlciBtZW55ZWJ1dCAidGFiIGJhcnUiLCBhdGF1IGFkYSB2aWRlby9oYWxhbWFuIGxhaW4geWFuZyBzZWRhbmcgdGVyYnVrYSAobWlzYWxueWEgbXVzaWspLCBwYWthaSBuZXdfdGFiPXRydWUgcGFk
::B64:agent.js:YSBvcGVuX3VybCwgd2ViX3NlYXJjaCwgYXRhdSB5b3V0dWJlX3BsYXkuIEJlYmVyYXBhIHNpdHVzIHNla2FsaWd1czogb3Blbl91cmxzLiBQaW5kYWggdGFiOiBsaXN0X3RhYnMgbGFsdSBzd2l0Y2hfdGFiIChpbmRleCAtMSA9IHRhYiB0ZXJiYXJ1LCBhdGF1IG1h
::B64:agent.js:dGNoIGp1ZHVsKS4gVHV0dXA6IGNsb3NlX3RhYi4KLSBVcGxvYWQgYmFueWFrIGZpbGU6IHVwbG9hZF9maWxlIGRlbmdhbiBiZWJlcmFwYSBwYXRoIGRpcGlzYWggfCwgYXRhdSBmb2xkZXIgKGRhbiBwYXR0ZXJuKS4gSmlrYSBpbnB1dCBoYW55YSBtZW5lcmltYSBz
::B64:agent.js:YXR1IGZpbGUsIHVsYW5naSBwZXIgZmlsZSBzYW1wYWkgc2VtdWEgc2VsZXNhaS4KLSBIRU1BVCBMQU5HS0FIOiBqaWthIGJlYmVyYXBhIGxhbmdrYWggdGlkYWsgc2FsaW5nIGJlcmdhbnR1bmcsIHBhbmdnaWwgYmViZXJhcGEgdG9vbCBzZWthbGlndXMgZGFsYW0g
::B64:agent.js:c2F0dSBqYXdhYmFuLgotIFVQTE9BRDogc2VsYWx1IHBha2FpIGZhc3RfdXBsb2FkIChzYXR1IHBhbmdnaWxhbiwgb3RvbWF0aXMgbWVuZW11a2FuIHRvbWJvbCB1cGxvYWQsIG1lbmR1a3VuZyBiYW55YWsgZmlsZSwgZm9sZGVyLCBkYW4gemlwKS4gUGFrYWkgdXBs
::B64:agent.js:b2FkX2ZpbGUgaGFueWEgamlrYSBmYXN0X3VwbG9hZCBnYWdhbC4KLSBWb2x1bWUga2UgYW5na2EgdGVydGVudHU6IHNldF92b2x1bWUuIEZpbGUgdGVyYmFydTogcmVjZW50X2ZpbGVzLgotIE1lbnV0dXAvbWVtYXRpa2FuIGFwbGlrYXNpIGF0YXUgZ2FtZSAobWlz
::B64:agent.js:YWxueWEgY3MyKTogcGFrYWkga2lsbF9wcm9jZXNzIGRlbmdhbiBuYW1hIHByb3NlcyB0YW5wYSAuZXhlLiBKQU5HQU4gcGFrYWkgb3Blbl9wYXRoIHVudHVrIHRhc2traWxsLgotIE1lbmdoYXB1cyBmaWxlOiBwYWthaSByZWN5Y2xlX3BhdGggKG1hc3VrIFJlY3lj
::B64:agent.js:bGUgQmluKSwgamFuZ2FuIG1lbmdoYXB1cyBwZXJtYW5lbi4KLSBKaWthIGFsYXQgeWFuZyBrYW11IGJ1dHVoa2FuIHRpZGFrIGFkYSBkaSBkYWZ0YXIsIHBhbmdnaWwgbW9yZV90b29scyBkZW5nYW4gZ3J1cDogeW91dHViZSwgdGFicywgZGVza3RvcCwgZmlsZXMs
::B64:agent.js:IGF0YXUgcGMuCi0gSmlrYSBidW50dSBhdGF1IHJhZ3UsIGJlcmhlbnRpIGRhbiB0YW55YSB1c2VyLgotIEphd2FiIGRhbGFtIEJhaGFzYSBJbmRvbmVzaWEsIHNpbmdrYXQuIEphbmdhbiBtZW5nYXJhbmcgaGFzaWw7IGxhcG9ya2FuIGFwYSBhZGFueWEuYDsKCi8v
::B64:agent.js:ID09PT09IEtvbXVuaWthc2kgZGVuZ2FuIDlSb3V0ZXIgKHRhaGFuIGJhbnRpbmcpID09PT09Ci8vIEppa2EgYmFsYXNhbiBrb3NvbmcvZ2FnYWwsIGFnZW50IG90b21hdGlzOiAoMSkgY29iYSB0YW5wYSB0b29sX2Nob2ljZSwgKDIpIGtlY2lsa2FuIGRhZnRhciBh
::B64:agent.js:bGF0IGRhbgovLyBwYWthaSBiYWxhc2FuIG5vbi1zdHJlYW1pbmcsICgzKSBwaW5kYWgga2UgbW9kZWwgbGFpbiB5YW5nIGRpdGVtdWthbiBsZXdhdCAvbW9kZWxzLgovLyBNb2RlbCB5YW5nIGJlcmhhc2lsIGRpaW5nYXQgc2VsYW1hIHNlc2kuIFBlcmludGFoIC90
::B64:agent.js:ZXMgZGFuIC9tb2RlbCBtZW1iYW50dSBtZW1pbGloIG1vZGVsIHBhbGluZyBzdGFiaWwuCmNvbnN0IE1PREVMX0ZJTEUgPSAibW9kZWwudHh0IjsKbGV0IGJhc2VNb2RlbCA9IE1PREVMOwp0cnkgewogIGNvbnN0IHNhdmVkID0gZnMucmVhZEZpbGVTeW5jKE1PREVM
::B64:agent.js:X0ZJTEUsICJ1dGY4IikudHJpbSgpOwogIGlmIChzYXZlZCkgYmFzZU1vZGVsID0gc2F2ZWQ7Cn0gY2F0Y2gge30KCmxldCB1c2VUb29sQ2hvaWNlID0gdHJ1ZTsgLy8gcGFrc2EgbW9kZWwgc2VsYWx1IG1lbWFuZ2dpbCB0b29sOyBkaW1hdGlrYW4gb3RvbWF0aXMg
::B64:agent.js:amlrYSBiZXJtYXNhbGFoCmxldCBzbGltTW9kZSA9IHByb2Nlc3MuZW52LlNMSU0gIT09ICIwIjsgLy8gdHJ1ZSA9IGtpcmltIGhhbnlhIGFsYXQgeWFuZyByZWxldmFuIChtdWF0YW4ga2VjaWwgPSBsZWJpaCBjZXBhdCkKbGV0IGZhbGxiYWNrTW9kZWxzID0gbnVs
::B64:agent.js:bDsgLy8gZGlpc2kgc2FhdCBwZXJ0YW1hIGthbGkgZGlidXR1aGthbgpsZXQgcG9vbElkeCA9IDA7CmNvbnN0IGV4dHJhR3JvdXBzID0gbmV3IFNldCgpOwpjb25zdCBCQUNLT0ZGID0gTnVtYmVyKHByb2Nlc3MuZW52LkJBQ0tPRkZfTVMgfHwgMTAwMCk7Cgpjb25z
::B64:agent.js:dCBUT09MX0dST1VQUyA9IHsKICB5b3V0dWJlOiBbInlvdXR1YmVfcGxheSIsICJ5b3V0dWJlX2NvbnRyb2wiXSwKICB0YWJzOiBbIm5ld190YWIiLCAib3Blbl91cmxzIiwgImxpc3RfdGFicyIsICJzd2l0Y2hfdGFiIiwgImNsb3NlX3RhYiIsICJzY3JvbGxfcGFn
::B64:agent.js:ZSIsICJ3ZWJfc2VhcmNoIl0sCiAgZGVza3RvcDogWyJjbGlja19zY3JlZW4iLCAic2Nyb2xsX3NjcmVlbiIsICJ0eXBlX2Rlc2t0b3AiLCAicHJlc3Nfa2V5cyIsICJ3YWl0IiwgImxpc3Rfd2luZG93cyIsICJmb2N1c193aW5kb3ciLCAiY2xvc2Vfd2luZG93Il0s
::B64:agent.js:CiAgZmlsZXM6IFsicmVhZF90ZXh0X2ZpbGUiLCAid3JpdGVfdGV4dF9maWxlIiwgIm1ha2VfZm9sZGVyIiwgIm1vdmVfcGF0aCIsICJjb3B5X3BhdGgiLCAicmVjeWNsZV9wYXRoIiwgInppcF9wYXRoIiwgInVuemlwX3BhdGgiLCAiZG93bmxvYWRfZmlsZSIsICJy
::B64:agent.js:ZWNlbnRfZmlsZXMiLCAic2VhcmNoX3RleHQiXSwKICBwYzogWyJtZWRpYV9rZXkiLCAic2V0X3ZvbHVtZSIsICJjbGlwYm9hcmRfZ2V0IiwgImNsaXBib2FyZF9zZXQiLCAic3lzdGVtX2luZm8iLCAic2F2ZV9zY3JlZW5zaG90IiwgInNwZWFrIiwgInNldF90aW1l
::B64:agent.js:ciIsICJraWxsX3Byb2Nlc3MiLCAibGlzdF9wcm9jZXNzZXMiXSwKfTsKY29uc3QgQ09SRV9UT09MUyA9IFsKICAiZG9uZSIsICJ3YWl0X2Zvcl91c2VyIiwgIm1vcmVfdG9vbHMiLCAibm93IiwgIm9wZW5fdXJsIiwgImdldF9wYWdlX3RleHQiLCAiaW5zcGVjdF9w
::B64:agent.js:YWdlIiwgInR5cGVfdGV4dCIsICJjbGljayIsCiAgInVwbG9hZF9maWxlIiwgImZhc3RfdXBsb2FkIiwgImxpc3RfZmlsZXMiLCAiZmluZF9mb2xkZXIiLCAiZmluZF9maWxlIiwgImxpc3RfZGlyIiwgIm9wZW5fcGF0aCIsICJzY3JlZW5zaG90IiwKXTsKY29uc3Qg
::B64:agent.js:R1JPVVBfS0VZV09SRFMgPSB7CiAgeW91dHViZTogL3lvdXR1YmV8dmlkZW98bGFndXxtdXNpa3xtdXNpY3xwdXRhcnxub250b258ZGVuZ2FyfHBhdXNlfG5leHQvaSwKICB0YWJzOiAvXGJ0YWJcYnxjYXJpfHNlYXJjaHxnb29nbGV8d2VifGludGVybmV0fHNpdHVz
::B64:agent.js:fHdlYnNpdGV8c2VrYWxpZ3VzL2ksCiAgZGVza3RvcDogL2tsaWt8bGF5YXJ8bW91c2V8a2V0aWt8amVuZGVsYXx3aW5kb3d8YXBsaWthc2l8c2NyZWVuc2hvdHxzY3JvbGx8dG9tYm9sL2ksCiAgZmlsZXM6IC9maWxlfGZvbGRlcnx6aXB8aGFwdXN8cGluZGFofHR1
::B64:agent.js:bGlzfGJhY2F8dW5kdWh8ZG93bmxvYWR8YnVhdHxnYW50aSBuYW1hfHNhbGlufGNvcHl8dGVyYmFydXxjYXJpIHRla3MvaSwKICBwYzogL3ZvbHVtZXxzdWFyYXxjbGlwYm9hcmR8c2FsaW58XGJyYW1cYnxjcHV8YmF0ZXJhaXxzaXN0ZW18bWVkaWF8bXV0ZXx0aW1l
::B64:agent.js:cnxpbmdhdGthbnxwZW5naW5nYXR8dWNhcHxiaWNhcmF8c2NyZWVuc2hvdHx0YW5na2FwfG1hdGlrYW58aGVudGlrYW58a2lsbHxwcm9zZXN8XC5leGV8Z2FtZXxhcGxpa2FzaXx0YXNra2lsbHxwYWtzYS9pLAp9OwoKLy8gUGlsaWggYWxhdCB5YW5nIHJlbGV2YW4g
::B64:agent.js:c2FqYSAoZGlwYWthaSBzYWF0IG11YXRhbiBwZXJsdSBkaWtlY2lsa2FuKQpmdW5jdGlvbiBzZWxlY3RUb29scyhtZXNzYWdlcykgewogIGNvbnN0IG5hbWVzID0gbmV3IFNldChDT1JFX1RPT0xTKTsKICBjb25zdCB1c2VyVGV4dCA9IG1lc3NhZ2VzCiAgICAuZmls
::B64:agent.js:dGVyKChtKSA9PiBtLnJvbGUgPT09ICJ1c2VyIiAmJiB0eXBlb2YgbS5jb250ZW50ID09PSAic3RyaW5nIiAmJiAhbS5jb250ZW50LnN0YXJ0c1dpdGgoIkthbXUgaGFydXMgbWVtYW5nZ2lsIHRvb2wiKSkKICAgIC5zbGljZSgtNCkKICAgIC5tYXAoKG0pID0+IG0u
::B64:agent.js:Y29udGVudCkKICAgIC5qb2luKCIgIik7CiAgZm9yIChjb25zdCBbZywgcmVdIG9mIE9iamVjdC5lbnRyaWVzKEdST1VQX0tFWVdPUkRTKSkgewogICAgaWYgKHJlLnRlc3QodXNlclRleHQpIHx8IGV4dHJhR3JvdXBzLmhhcyhnKSkgVE9PTF9HUk9VUFNbZ10uZm9y
::B64:agent.js:RWFjaCgobikgPT4gbmFtZXMuYWRkKG4pKTsKICB9CiAgZm9yIChjb25zdCBtIG9mIG1lc3NhZ2VzKSBmb3IgKGNvbnN0IGMgb2YgbS50b29sX2NhbGxzIHx8IFtdKSBuYW1lcy5hZGQoYy5mdW5jdGlvbi5uYW1lKTsgLy8gYWxhdCB5YW5nIHN1ZGFoIGRpcGFrYWkg
::B64:agent.js:dGV0YXAgYWRhCiAgcmV0dXJuIHRvb2xzLmZpbHRlcigodCkgPT4gbmFtZXMuaGFzKHQuZnVuY3Rpb24ubmFtZSkpOwp9Cgpjb25zdCBtb2RlbFBvb2wgPSAoKSA9PiBbYmFzZU1vZGVsLCAuLi4oZmFsbGJhY2tNb2RlbHMgfHwgW10pLmZpbHRlcigobSkgPT4gbSAh
::B64:agent.js:PT0gYmFzZU1vZGVsKV07Cgphc3luYyBmdW5jdGlvbiBkaXNjb3Zlck1vZGVscygpIHsKICBpZiAocHJvY2Vzcy5lbnYuUk9VVEVSX0ZBTExCQUNLX01PREVMUykgewogICAgcmV0dXJuIHByb2Nlc3MuZW52LlJPVVRFUl9GQUxMQkFDS19NT0RFTFMuc3BsaXQoIiwi
::B64:agent.js:KS5tYXAoKHgpID0+IHgudHJpbSgpKS5maWx0ZXIoQm9vbGVhbik7CiAgfQogIHRyeSB7CiAgICBjb25zdCByZXMgPSBhd2FpdCBmZXRjaChgJHtCQVNFX1VSTH0vbW9kZWxzYCwgewogICAgICBoZWFkZXJzOiB7IEF1dGhvcml6YXRpb246IGBCZWFyZXIgJHtBUElf
::B64:agent.js:S0VZfWAgfSwKICAgICAgc2lnbmFsOiBBYm9ydFNpZ25hbC50aW1lb3V0KDEwMDAwKSwKICAgIH0pOwogICAgaWYgKCFyZXMub2spIHJldHVybiBbXTsKICAgIGNvbnN0IGRhdGEgPSAoYXdhaXQgcmVzLmpzb24oKSkuZGF0YSB8fCBbXTsKICAgIGNvbnN0IGJhZCA9
::B64:agent.js:IC9lbWJlZHx3aGlzcGVyfHR0c3xpbWFnZXxhdWRpb3xyZXJhbmt8bW9kZXJhdHxkYWxsfGZsdXh8c2R4bHx2aWRlb3xzcGVlY2h8dHJhbnNjcmkvaTsKICAgIGNvbnN0IHNjb3JlID0gKGlkKSA9PgogICAgICAoL2NsYXVkZS9pLnRlc3QoaWQpID8gMyA6IDApICsg
::B64:agent.js:KC9nZW1pbmkvaS50ZXN0KGlkKSA/IDMgOiAwKSArICgvZ3B0fGdsbXxxd2VufGtpbWl8ZGVlcHNlZWsvaS50ZXN0KGlkKSA/IDIgOiAwKSArCiAgICAgICgvaGFpa3V8Zmxhc2h8c29ubmV0L2kudGVzdChpZCkgPyAxIDogMCkgLSAoL3RoaW5raW5nfGFnZW50aWMv
::B64:agent.js:aS50ZXN0KGlkKSA/IDIgOiAwKTsKICAgIHJldHVybiBkYXRhCiAgICAgIC5tYXAoKG0pID0+IG0uaWQpCiAgICAgIC5maWx0ZXIoKGlkKSA9PiBpZCAmJiBpZCAhPT0gYmFzZU1vZGVsICYmICFiYWQudGVzdChpZCkpCiAgICAgIC5zb3J0KCh4LCB5KSA9PiBzY29y
::B64:agent.js:ZSh5KSAtIHNjb3JlKHgpKQogICAgICAuc2xpY2UoMCwgOCk7CiAgfSBjYXRjaCB7CiAgICByZXR1cm4gW107CiAgfQp9CgpmdW5jdGlvbiBmYXRhbChtc2cpIHsKICBjb25zdCBlID0gbmV3IEVycm9yKG1zZyk7CiAgZS5mYXRhbCA9IHRydWU7CiAgcmV0dXJuIGU7
::B64:agent.js:Cn0KCi8vIEJhY2EgYmFsYXNhbiA5Um91dGVyIChKU09OIGJpYXNhIGF0YXUgc3RyZWFtaW5nIFNTRSkgbWVuamFkaSBzYXR1IHBlc2FuCmZ1bmN0aW9uIHBhcnNlQ2hhdChyYXcpIHsKICBpZiAoIXJhdy50cmltKCkpIHJldHVybiB7IG1zZzogbnVsbCwgZXJyOiAi
::B64:agent.js:a29zb25nIiB9OwogIGlmICghLyhefFxuKWRhdGE6Ly50ZXN0KHJhdykpIHsKICAgIGxldCBvYmo7CiAgICB0cnkgewogICAgICBvYmogPSBKU09OLnBhcnNlKHJhdyk7CiAgICB9IGNhdGNoIHsKICAgICAgcmV0dXJuIHsgbXNnOiBudWxsLCBlcnI6ICJidWthbiBK
::B64:agent.js:U09OIiB9OwogICAgfQogICAgaWYgKG9iai5lcnJvcikgcmV0dXJuIHsgbXNnOiBudWxsLCBlcnI6IEpTT04uc3RyaW5naWZ5KG9iai5lcnJvcikuc2xpY2UoMCwgMTUwKSB9OwogICAgY29uc3QgbSA9IG9iai5jaG9pY2VzPy5bMF0/Lm1lc3NhZ2U7CiAgICBpZiAo
::B64:agent.js:IW0gfHwgKCFtLmNvbnRlbnQgJiYgIW0udG9vbF9jYWxscz8ubGVuZ3RoKSkgcmV0dXJuIHsgbXNnOiBudWxsLCBlcnI6ICJ0YW5wYSBpc2kiIH07CiAgICByZXR1cm4geyBtc2c6IG0sIGVycjogIiIgfTsKICB9CiAgbGV0IGNvbnRlbnQgPSAiIjsKICBsZXQgc3Nl
::B64:agent.js:RXJyID0gIiI7CiAgY29uc3QgY2FsbHMgPSBbXTsKICBmb3IgKGNvbnN0IGxpbmUgb2YgcmF3LnNwbGl0KCJcbiIpKSB7CiAgICBpZiAoIWxpbmUuc3RhcnRzV2l0aCgiZGF0YToiKSkgY29udGludWU7CiAgICBjb25zdCBkYXRhID0gbGluZS5zbGljZSg1KS50cmlt
::B64:agent.js:KCk7CiAgICBpZiAoIWRhdGEgfHwgZGF0YSA9PT0gIltET05FXSIpIGNvbnRpbnVlOwogICAgbGV0IGNodW5rOwogICAgdHJ5IHsKICAgICAgY2h1bmsgPSBKU09OLnBhcnNlKGRhdGEpOwogICAgfSBjYXRjaCB7CiAgICAgIGNvbnRpbnVlOwogICAgfQogICAgaWYg
::B64:agent.js:KGNodW5rLmVycm9yKSBzc2VFcnIgPSBKU09OLnN0cmluZ2lmeShjaHVuay5lcnJvcikuc2xpY2UoMCwgMTUwKTsKICAgIGNvbnN0IGNob2ljZSA9IGNodW5rLmNob2ljZXM/LlswXTsKICAgIGNvbnN0IGRlbHRhID0gY2hvaWNlPy5kZWx0YSB8fCBjaG9pY2U/Lm1l
::B64:agent.js:c3NhZ2UgfHwge307CiAgICBpZiAoZGVsdGEuY29udGVudCkgY29udGVudCArPSBkZWx0YS5jb250ZW50OwogICAgZm9yIChjb25zdCB0YyBvZiBkZWx0YS50b29sX2NhbGxzIHx8IFtdKSB7CiAgICAgIGNvbnN0IGkgPSB0Yy5pbmRleCA/PyAwOwogICAgICBjYWxs
::B64:agent.js:c1tpXSA/Pz0geyBpZDogIiIsIHR5cGU6ICJmdW5jdGlvbiIsIGZ1bmN0aW9uOiB7IG5hbWU6ICIiLCBhcmd1bWVudHM6ICIiIH0gfTsKICAgICAgaWYgKHRjLmlkKSBjYWxsc1tpXS5pZCA9IHRjLmlkOwogICAgICBpZiAodGMuZnVuY3Rpb24/Lm5hbWUpIGNhbGxz
::B64:agent.js:W2ldLmZ1bmN0aW9uLm5hbWUgKz0gdGMuZnVuY3Rpb24ubmFtZTsKICAgICAgaWYgKHRjLmZ1bmN0aW9uPy5hcmd1bWVudHMpIGNhbGxzW2ldLmZ1bmN0aW9uLmFyZ3VtZW50cyArPSB0Yy5mdW5jdGlvbi5hcmd1bWVudHM7CiAgICB9CiAgfQogIGNvbnN0IHZhbGlk
::B64:agent.js:ID0gY2FsbHMuZmlsdGVyKEJvb2xlYW4pLm1hcCgoYywgaSkgPT4gKHsgLi4uYywgaWQ6IGMuaWQgfHwgYGNhbGxfJHtpfWAgfSkpOwogIGlmICghY29udGVudCAmJiAhdmFsaWQubGVuZ3RoKSByZXR1cm4geyBtc2c6IG51bGwsIGVycjogc3NlRXJyIHx8ICJ0YW5w
::B64:agent.js:YSBpc2kiIH07CiAgY29uc3QgbXNnID0geyByb2xlOiAiYXNzaXN0YW50IiwgY29udGVudDogY29udGVudCB8fCBudWxsIH07CiAgaWYgKHZhbGlkLmxlbmd0aCkgbXNnLnRvb2xfY2FsbHMgPSB2YWxpZDsKICByZXR1cm4geyBtc2csIGVycjogIiIgfTsKfQoKYXN5
::B64:agent.js:bmMgZnVuY3Rpb24gcmVxdWVzdE9uY2UobWVzc2FnZXMsIHsgbW9kZWwsIHRvb2xDaG9pY2UsIHN0cmVhbSwgc2xpbSB9KSB7CiAgY29uc3QgdG9vbExpc3QgPSBzbGltID8gc2VsZWN0VG9vbHMobWVzc2FnZXMpIDogdG9vbHMuZmlsdGVyKCh0KSA9PiB0LmZ1bmN0
::B64:agent.js:aW9uLm5hbWUgIT09ICJtb3JlX3Rvb2xzIik7CiAgY29uc3QgYm9keSA9IHsgbW9kZWwsIG1lc3NhZ2VzLCB0b29sczogdG9vbExpc3QsIHN0cmVhbSB9OwogIGlmICh0b29sQ2hvaWNlKSBib2R5LnRvb2xfY2hvaWNlID0gInJlcXVpcmVkIjsKICBjb25zdCByZXMg
::B64:agent.js:PSBhd2FpdCBmZXRjaChgJHtCQVNFX1VSTH0vY2hhdC9jb21wbGV0aW9uc2AsIHsKICAgIG1ldGhvZDogIlBPU1QiLAogICAgaGVhZGVyczogeyAiQ29udGVudC1UeXBlIjogImFwcGxpY2F0aW9uL2pzb24iLCBBdXRob3JpemF0aW9uOiBgQmVhcmVyICR7QVBJX0tF
::B64:agent.js:WX1gIH0sCiAgICBib2R5OiBKU09OLnN0cmluZ2lmeShib2R5KSwKICAgIHNpZ25hbDogQWJvcnRTaWduYWwudGltZW91dCgxMjAwMDApLAogIH0pOwogIGlmICghcmVzLm9rKSB7CiAgICBjb25zdCBlcnJUZXh0ID0gKGF3YWl0IHJlcy50ZXh0KCkpLnJlcGxhY2Uo
::B64:agent.js:L1xzKy9nLCAiICIpLnNsaWNlKDAsIDIwMCk7CiAgICBpZiAocmVzLnN0YXR1cyA9PT0gNDAxIHx8IHJlcy5zdGF0dXMgPT09IDQwMykgdGhyb3cgZmF0YWwoYEFQSSBrZXkgZGl0b2xhayAoJHtyZXMuc3RhdHVzfSkuIEphbGFua2FuOiBzdGFydC1hZ2VudC5iYXQg
::B64:agent.js:cmVzZXRgKTsKICAgIGNvbnN0IGUgPSBuZXcgRXJyb3IoYEhUVFAgJHtyZXMuc3RhdHVzfSAke2VyclRleHR9YCk7CiAgICBpZiAocmVzLnN0YXR1cyA9PT0gNDI5KSBlLndhaXQgPSBNYXRoLm1pbihOdW1iZXIocmVzLmhlYWRlcnMuZ2V0KCJyZXRyeS1hZnRlciIp
::B64:agent.js:KSB8fCA1LCAxNSkgKiAxMDAwOwogICAgdGhyb3cgZTsKICB9CiAgY29uc3QgcmF3ID0gYXdhaXQgcmVzLnRleHQoKTsKICBjb25zdCB7IG1zZywgZXJyIH0gPSBwYXJzZUNoYXQocmF3KTsKICBpZiAoIW1zZykgewogICAgY29uc3QgcGVlayA9IGBbSFRUUCAke3Jl
::B64:agent.js:cy5zdGF0dXN9LCAke3Jhdy5sZW5ndGh9IGJ5dGUke3Jhdy50cmltKCkgPyAiOiAiICsgcmF3LnJlcGxhY2UoL1xzKy9nLCAiICIpLnNsaWNlKDAsIDEwMCkgOiAiIn1dYDsKICAgIHRocm93IG5ldyBFcnJvcihgcmVzcG9ucyAke2Vycn0gJHtwZWVrfWApOwogIH0K
::B64:agent.js:ICByZXR1cm4gbXNnOwp9Cgphc3luYyBmdW5jdGlvbiBjYWxsTExNKG1lc3NhZ2VzKSB7CiAgY29uc3QgQVRURU1QVFMgPSA3OwogIGxldCBsYXN0RXJyID0gIiI7CiAgZm9yIChsZXQgYXR0ZW1wdCA9IDE7IGF0dGVtcHQgPD0gQVRURU1QVFM7IGF0dGVtcHQrKykg
::B64:agent.js:ewogICAgaWYgKGF0dGVtcHQgPj0gMykgc2xpbU1vZGUgPSB0cnVlOyAvLyBrZWNpbGthbiBtdWF0YW4gYWxhdAogICAgaWYgKGF0dGVtcHQgPj0gNCkgewogICAgICAvLyBQaW5kYWgga2UgbW9kZWwgbGFpbgogICAgICBpZiAoIWZhbGxiYWNrTW9kZWxzKSBmYWxs
::B64:agent.js:YmFja01vZGVscyA9IGF3YWl0IGRpc2NvdmVyTW9kZWxzKCk7CiAgICAgIGNvbnN0IHBvb2wgPSBtb2RlbFBvb2woKTsKICAgICAgaWYgKHBvb2wubGVuZ3RoID4gMSkgewogICAgICAgIHBvb2xJZHggPSAocG9vbElkeCArIDEpICUgcG9vbC5sZW5ndGg7CiAgICAg
::B64:agent.js:ICAgY29uc29sZS5sb2coYCAgKG1lbmNvYmEgbW9kZWwgbGFpbjogJHtwb29sW3Bvb2xJZHhdfSlgKTsKICAgICAgfQogICAgfQogICAgY29uc3QgcG9vbCA9IG1vZGVsUG9vbCgpOwogICAgY29uc3QgbW9kZWwgPSBwb29sW3Bvb2xJZHggJSBwb29sLmxlbmd0aF07
::B64:agent.js:CiAgICB0cnkgewogICAgICBjb25zdCBtc2cgPSBhd2FpdCByZXF1ZXN0T25jZShtZXNzYWdlcywgewogICAgICAgIG1vZGVsLAogICAgICAgIHRvb2xDaG9pY2U6IGF0dGVtcHQgPT09IDEgJiYgdXNlVG9vbENob2ljZSwKICAgICAgICBzdHJlYW06IGF0dGVtcHQg
::B64:agent.js:PCAzIHx8IGF0dGVtcHQgJSAyID09PSAwLAogICAgICAgIHNsaW06IHNsaW1Nb2RlLAogICAgICB9KTsKICAgICAgY29uc3QgY2xlYW4gPSB7IHJvbGU6ICJhc3Npc3RhbnQiLCBjb250ZW50OiBtc2cuY29udGVudCA/PyBudWxsIH07CiAgICAgIGlmIChtc2cudG9v
::B64:agent.js:bF9jYWxscz8ubGVuZ3RoKSBjbGVhbi50b29sX2NhbGxzID0gbXNnLnRvb2xfY2FsbHM7CiAgICAgIHJldHVybiBjbGVhbjsKICAgIH0gY2F0Y2ggKGUpIHsKICAgICAgaWYgKGUuZmF0YWwpIHRocm93IGU7CiAgICAgIGxhc3RFcnIgPSBlLm1lc3NhZ2U7CiAgICAg
::B64:agent.js:IGlmIChhdHRlbXB0ID09PSAxKSB1c2VUb29sQ2hvaWNlID0gZmFsc2U7CiAgICB9CiAgICBpZiAoYXR0ZW1wdCA8IEFUVEVNUFRTKSB7CiAgICAgIGNvbnNvbGUubG9nKGAgICg5Um91dGVyIGJlcm1hc2FsYWg6ICR7bGFzdEVyci5zbGljZSgwLCAxNDApfS4gTWVu
::B64:agent.js:Y29iYSB1bGFuZyAke2F0dGVtcHR9LyR7QVRURU1QVFMgLSAxfS4uLilgKTsKICAgICAgYXdhaXQgc2xlZXAoTWF0aC5taW4oQkFDS09GRiAqIGF0dGVtcHQsIDQwMDApKTsKICAgIH0KICB9CiAgdGhyb3cgbmV3IEVycm9yKAogICAgYDlSb3V0ZXIgZ2FnYWwgbWVy
::B64:agent.js:ZXNwb25zIHNldGVsYWggJHtBVFRFTVBUU30gcGVyY29iYWFuICgke2xhc3RFcnIuc2xpY2UoMCwgMTYwKX0pLiBgICsKICAgICAgYEtldGlrIC90ZXMgdW50dWsgbWVuZ3VqaSBtb2RlbCBkYW4gbWVtaWxpaCB5YW5nIHN0YWJpbC4gQ2VrIGp1Z2EgZGFzaGJvYXJk
::B64:agent.js:IDlSb3V0ZXIsIG1lbnUgQ29uc29sZSBMb2cuYAogICk7Cn0KCi8vIFVqaSBzYXR1IG1vZGVsIGRlbmdhbiBwZXJtaW50YWFuIGtlY2lsIHlhbmcgbWVtaW50YSBwZW1hbmdnaWxhbiB0b29sCmFzeW5jIGZ1bmN0aW9uIHRlc3RNb2RlbChtb2RlbCkgewogIGNvbnN0
::B64:agent.js:IHQwID0gRGF0ZS5ub3coKTsKICBjb25zdCBwaW5nVG9vbCA9IFsKICAgIHsKICAgICAgdHlwZTogImZ1bmN0aW9uIiwKICAgICAgZnVuY3Rpb246IHsKICAgICAgICBuYW1lOiAicGluZyIsCiAgICAgICAgZGVzY3JpcHRpb246ICJUZXMga29uZWtzaSIsCiAgICAg
::B64:agent.js:ICAgcGFyYW1ldGVyczogeyB0eXBlOiAib2JqZWN0IiwgcHJvcGVydGllczogeyBwZXNhbjogeyB0eXBlOiAic3RyaW5nIiB9IH0sIHJlcXVpcmVkOiBbInBlc2FuIl0gfSwKICAgICAgfSwKICAgIH0sCiAgXTsKICB0cnkgewogICAgY29uc3QgcmVzID0gYXdhaXQg
::B64:agent.js:ZmV0Y2goYCR7QkFTRV9VUkx9L2NoYXQvY29tcGxldGlvbnNgLCB7CiAgICAgIG1ldGhvZDogIlBPU1QiLAogICAgICBoZWFkZXJzOiB7ICJDb250ZW50LVR5cGUiOiAiYXBwbGljYXRpb24vanNvbiIsIEF1dGhvcml6YXRpb246IGBCZWFyZXIgJHtBUElfS0VZfWAg
::B64:agent.js:fSwKICAgICAgYm9keTogSlNPTi5zdHJpbmdpZnkoewogICAgICAgIG1vZGVsLAogICAgICAgIG1lc3NhZ2VzOiBbeyByb2xlOiAidXNlciIsIGNvbnRlbnQ6ICJQYW5nZ2lsIHRvb2wgcGluZyBkZW5nYW4gcGVzYW4gb2suIiB9XSwKICAgICAgICB0b29sczogcGlu
::B64:agent.js:Z1Rvb2wsCiAgICAgICAgc3RyZWFtOiBmYWxzZSwKICAgICAgfSksCiAgICAgIHNpZ25hbDogQWJvcnRTaWduYWwudGltZW91dCg0NTAwMCksCiAgICB9KTsKICAgIGNvbnN0IHJhdyA9IGF3YWl0IHJlcy50ZXh0KCk7CiAgICBjb25zdCBtcyA9IERhdGUubm93KCkg
::B64:agent.js:LSB0MDsKICAgIGlmICghcmVzLm9rKSByZXR1cm4geyBtYXJrOiAiW1hdICIsIG1zLCB0ZXh0OiBgSFRUUCAke3Jlcy5zdGF0dXN9ICR7cmF3LnJlcGxhY2UoL1xzKy9nLCAiICIpLnNsaWNlKDAsIDcwKX1gIH07CiAgICBjb25zdCB7IG1zZywgZXJyIH0gPSBwYXJz
::B64:agent.js:ZUNoYXQocmF3KTsKICAgIGlmICghbXNnKSByZXR1cm4geyBtYXJrOiAiW1hdICIsIG1zLCB0ZXh0OiBgcmVzcG9ucyAke2Vycn1gIH07CiAgICBpZiAobXNnLnRvb2xfY2FsbHM/Lmxlbmd0aCkgcmV0dXJuIHsgbWFyazogIltPS10iLCBtcywgdGV4dDogInRvb2wg
::B64:agent.js:Y2FsbGluZyBiZXJmdW5nc2kiIH07CiAgICByZXR1cm4geyBtYXJrOiAiW35dICIsIG1zLCB0ZXh0OiAibWVuamF3YWIgdGFwaSB0aWRhayBtZW1hbmdnaWwgdG9vbCAoa3VyYW5nIGNvY29rIHVudHVrIGFnZW50KSIgfTsKICB9IGNhdGNoIChlKSB7CiAgICByZXR1
::B64:agent.js:cm4geyBtYXJrOiAiW1hdICIsIG1zOiBEYXRlLm5vdygpIC0gdDAsIHRleHQ6IGUubmFtZSA9PT0gIlRpbWVvdXRFcnJvciIgPyAidGltZW91dCIgOiBlLm1lc3NhZ2Uuc2xpY2UoMCwgNzApIH07CiAgfQp9CgovLyA9PT09PSBKYWx1ciBjZXBhdDogcGVyaW50YWgg
::B64:agent.js:dW11bSBsYW5nc3VuZyBkaWphbGFua2FuIFRBTlBBIEFJIChoYXNpbCBkYWxhbSBoaXR1bmdhbiBkZXRpaykgPT09PT0KLy8gSmlrYSBwZXJpbnRhaCB0aWRhayBkaWtlbmFsaSBhdGF1IGphbHVyIGNlcGF0IGdhZ2FsLCBvdG9tYXRpcyBkaXNlcmFoa2FuIGtlIEFJ
::B64:agent.js:LgpsZXQgRkFTVCA9IHByb2Nlc3MuZW52LkZBU1QgIT09ICIwIjsKCmNvbnN0IHRpZHkgPSAocykgPT4KICBTdHJpbmcocykKICAgIC5yZXBsYWNlKC9ccysoZG9uZ3x5YXx5YWh8ZGVofGFqYXxkb25rfHNpaHxuaWh8cGxlYXNlfHBsc3xwbGlzfGR1bHUpXHMqJC9p
::B64:agent.js:LCAiIikKICAgIC5yZXBsYWNlKC9bLiE/XSskLywgIiIpCiAgICAudHJpbSgpOwoKY29uc3QgS05PV05fU0lURVMgPSB7CiAgeW91dHViZTogInlvdXR1YmUuY29tIiwgeXQ6ICJ5b3V0dWJlLmNvbSIsIGdvb2dsZTogImdvb2dsZS5jb20iLCBnbWFpbDogIm1haWwu
::B64:agent.js:Z29vZ2xlLmNvbSIsIGdpdGh1YjogImdpdGh1Yi5jb20iLAogIHRpa3RvazogInRpa3Rvay5jb20iLCBmYWNlYm9vazogImZhY2Vib29rLmNvbSIsIGZiOiAiZmFjZWJvb2suY29tIiwgaW5zdGFncmFtOiAiaW5zdGFncmFtLmNvbSIsIGlnOiAiaW5zdGFncmFtLmNv
::B64:agent.js:bSIsCiAgdHdpdHRlcjogInguY29tIiwgeDogInguY29tIiwgd2hhdHNhcHA6ICJ3ZWIud2hhdHNhcHAuY29tIiwgd2E6ICJ3ZWIud2hhdHNhcHAuY29tIiwgbWVkaWFmaXJlOiAibWVkaWFmaXJlLmNvbSIsCiAgZHJpdmU6ICJkcml2ZS5nb29nbGUuY29tIiwgbWFw
::B64:agent.js:czogIm1hcHMuZ29vZ2xlLmNvbSIsIG5ldGZsaXg6ICJuZXRmbGl4LmNvbSIsIHNwb3RpZnk6ICJvcGVuLnNwb3RpZnkuY29tIiwKICBjaGF0Z3B0OiAiY2hhdGdwdC5jb20iLCBjbGF1ZGU6ICJjbGF1ZGUuYWkiLCBnZW1pbmk6ICJnZW1pbmkuZ29vZ2xlLmNvbSIs
::B64:agent.js:IHRva29wZWRpYTogInRva29wZWRpYS5jb20iLAogIHNob3BlZTogInNob3BlZS5jby5pZCIsIHRlbGVncmFtOiAid2ViLnRlbGVncmFtLm9yZyIsIGxpbmtlZGluOiAibGlua2VkaW4uY29tIiwgcGludGVyZXN0OiAicGludGVyZXN0LmNvbSIsCiAgdHdpdGNoOiAi
::B64:agent.js:dHdpdGNoLnR2IiwgZGlzY29yZDogImRpc2NvcmQuY29tIiwgcmVkZGl0OiAicmVkZGl0LmNvbSIsIHdpa2lwZWRpYTogImlkLndpa2lwZWRpYS5vcmciLAp9Owpjb25zdCBVUExPQURfU0lURVMgPSB7CiAgbWVkaWFmaXJlOiAiaHR0cHM6Ly9hcHAubWVkaWFmaXJl
::B64:agent.js:LmNvbS9teWZpbGVzIiwgZ29maWxlOiAiaHR0cHM6Ly9nb2ZpbGUuaW8iLCBwaXhlbGRyYWluOiAiaHR0cHM6Ly9waXhlbGRyYWluLmNvbSIsCiAgY2F0Ym94OiAiaHR0cHM6Ly9jYXRib3gubW9lIiwgd2V0cmFuc2ZlcjogImh0dHBzOi8vd2V0cmFuc2Zlci5jb20i
::B64:agent.js:LCBkcml2ZTogImh0dHBzOi8vZHJpdmUuZ29vZ2xlLmNvbS9kcml2ZS9teS1kcml2ZSIsCiAgdG1wZmlsZXM6ICJodHRwczovL3RtcGZpbGVzLm9yZyIsIGZpbGViaW46ICJodHRwczovL2ZpbGViaW4ubmV0IiwKfTsKY29uc3QgQVBQUyA9IHsKICBrYW1lcmE6ICJt
::B64:agent.js:aWNyb3NvZnQud2luZG93cy5jYW1lcmE6IiwgY2FtZXJhOiAibWljcm9zb2Z0LndpbmRvd3MuY2FtZXJhOiIsIG5vdGVwYWQ6ICJub3RlcGFkIiwga2Fsa3VsYXRvcjogImNhbGMiLAogIGNhbGN1bGF0b3I6ICJjYWxjIiwgcGFpbnQ6ICJtc3BhaW50IiwgcGVuZ2F0
::B64:agent.js:dXJhbjogIm1zLXNldHRpbmdzOiIsIHNldHRpbmdzOiAibXMtc2V0dGluZ3M6IiwgImZpbGUgZXhwbG9yZXIiOiAiZXhwbG9yZXIiLAogIGV4cGxvcmVyOiAiZXhwbG9yZXIiLCBjbWQ6ICJjbWQiLCAidGFzayBtYW5hZ2VyIjogInRhc2ttZ3IiLCAicGVuZ2Vsb2xh
::B64:agent.js:IHR1Z2FzIjogInRhc2ttZ3IiLCAicmVjeWNsZSBiaW4iOiAic2hlbGw6UmVjeWNsZUJpbkZvbGRlciIsCn07CmNvbnN0IEZJTEVfS0lORFMgPSB7CiAgZm90bzogIi5qcGd8LmpwZWd8LnBuZ3wud2VicCIsIGdhbWJhcjogIi5qcGd8LmpwZWd8LnBuZ3wud2VicCIs
::B64:agent.js:IHZpZGVvOiAiLm1wNHwubWt2fC5hdml8Lm1vdiIsIHZpZGlvOiAiLm1wNHwubWt2fC5hdml8Lm1vdiIsCiAgbXVzaWs6ICIubXAzfC53YXZ8LmZsYWN8Lm00YSIsIGxhZ3U6ICIubXAzfC53YXZ8LmZsYWN8Lm00YSIsIGRva3VtZW46ICIucGRmfC5kb2N8LmRvY3h8
::B64:agent.js:LnR4dHwueGxzeHwucHB0eCIsCn07CmNvbnN0IERPTUFJTl9SRSA9IC9eKD86aHR0cHM/OlwvXC8pP1thLXowLTktXSsoPzpcLlthLXowLTktXSspKlwuKD86Y29tfGlkfG5ldHxvcmd8aW98Y298bWV8YXBwfGRldnx0dnxhaXx4eXp8aW5mb3xjb1wuaWR8Z29cLmlk
::B64:agent.js:fGFjXC5pZCkoPzpcL1xTKik/JC9pOwoKY29uc3Qgc2l0ZVVybCA9ICh0KSA9PiB7CiAgY29uc3QgayA9IFN0cmluZyh0KS50cmltKCkudG9Mb3dlckNhc2UoKTsKICBpZiAoS05PV05fU0lURVNba10pIHJldHVybiAiaHR0cHM6Ly8iICsgS05PV05fU0lURVNba107
::B64:agent.js:CiAgaWYgKERPTUFJTl9SRS50ZXN0KFN0cmluZyh0KS50cmltKCkpKSByZXR1cm4gZml4VXJsKFN0cmluZyh0KS50cmltKCkpOwogIHJldHVybiAiIjsKfTsKY29uc3QgdXBsb2FkVXJsID0gKHQpID0+IHsKICBjb25zdCBrID0gU3RyaW5nKHQpLnRyaW0oKS50b0xv
::B64:agent.js:d2VyQ2FzZSgpLnJlcGxhY2UoL1wuKGNvbXxpb3xvcmd8bmV0fG1lfG1vZXxhcHApJC8sICIiKTsKICBpZiAoVVBMT0FEX1NJVEVTW2tdKSByZXR1cm4gVVBMT0FEX1NJVEVTW2tdOwogIGlmIChET01BSU5fUkUudGVzdChTdHJpbmcodCkudHJpbSgpKSkgcmV0dXJu
::B64:agent.js:IGZpeFVybChTdHJpbmcodCkudHJpbSgpKTsKICByZXR1cm4gIiI7Cn07CmNvbnN0IG9uWW91VHViZSA9ICgpID0+IC95b3V0dWJlXC5jb21cL3dhdGNoL2kudGVzdChwYWdlLnVybCgpKTsKY29uc3Qgb25Zb3VUdWJlU2l0ZSA9ICgpID0+IC95b3V0dWJlXC5jb20v
::B64:agent.js:aS50ZXN0KHBhZ2UudXJsKCkpOwpjb25zdCBpc0JsYW5rUGFnZSA9ICgpID0+IHsKICBjb25zdCB1ID0gcGFnZS51cmwoKTsKICByZXR1cm4gIXUgfHwgL14oYWJvdXQ6Ymxhbmt8Y2hyb21lOlwvXC9uZXctP3RhYnxlZGdlOlwvXC9uZXd0YWIpL2kudGVzdCh1KTsK
::B64:agent.js:fTsKY29uc3Qga25vd25EaXIgPSAobmFtZSkgPT4gewogIGNvbnN0IGsgPSBTdHJpbmcobmFtZSkudHJpbSgpLnRvTG93ZXJDYXNlKCk7CiAgaWYgKC9eKGRvd25sb2Fkcz98dW5kdWhhbikkLy50ZXN0KGspKSByZXR1cm4gcGF0aC5qb2luKEhPTUUsICJEb3dubG9h
::B64:agent.js:ZHMiKTsKICBpZiAoayA9PT0gImRlc2t0b3AiKSByZXR1cm4gcGF0aC5qb2luKEhPTUUsICJEZXNrdG9wIik7CiAgaWYgKC9eKGRvY3VtZW50cz98ZG9rdW1lbikkLy50ZXN0KGspKSByZXR1cm4gcGF0aC5qb2luKEhPTUUsICJEb2N1bWVudHMiKTsKICBpZiAoL14o
::B64:agent.js:cGljdHVyZXM/fGdhbWJhcnxmb3RvKSQvLnRlc3QoaykpIHJldHVybiBwYXRoLmpvaW4oSE9NRSwgIlBpY3R1cmVzIik7CiAgcmV0dXJuICIiOwp9OwoKLy8gUGlsaWggaGFzaWwgcGVuY2FyaWFuIHRlcmJhaWs6IG5hbWEgcGFsaW5nIG1pcmlwLCBsYWx1IGxva2Fz
::B64:agent.js:aSB1bXVtLCBsYWx1IHBhdGggdGVycGVuZGVrCmZ1bmN0aW9uIGJlc3RQYXRoKGxpbmVzLCBxdWVyeSkgewogIGNvbnN0IHJhdyA9IFN0cmluZyhxdWVyeSkudG9Mb3dlckNhc2UoKTsKICBjb25zdCBxID0gcmF3LnJlcGxhY2UoL1wuW2EtejAtOV17Miw0fSQvLCAi
::B64:agent.js:Iik7CiAgY29uc3Qgc2NvcmUgPSAocCkgPT4gewogICAgY29uc3QgYmFzZSA9IHBhdGguYmFzZW5hbWUocCkudG9Mb3dlckNhc2UoKTsKICAgIGNvbnN0IHN0ZW0gPSBiYXNlLnJlcGxhY2UoL1wuW2EtejAtOV17Miw0fSQvLCAiIik7CiAgICBsZXQgcyA9IDA7CiAg
::B64:agent.js:ICBpZiAoYmFzZSA9PT0gcmF3IHx8IHN0ZW0gPT09IHEpIHMgKz0gMTA7CiAgICBlbHNlIGlmIChzdGVtLnN0YXJ0c1dpdGgocSkpIHMgKz0gNDsKICAgIGlmICgvW1xcL10oZG93bmxvYWRzfGRlc2t0b3B8ZG9jdW1lbnRzfHVuZHVoYW4pW1xcL10vaS50ZXN0KHAp
::B64:agent.js:KSBzICs9IDM7CiAgICByZXR1cm4gcyAtIHAubGVuZ3RoIC8gMjAwOwogIH07CiAgcmV0dXJuIFsuLi5saW5lc10uc29ydCgoYSwgYikgPT4gc2NvcmUoYikgLSBzY29yZShhKSlbMF07Cn0KY29uc3QgcmVzdWx0TGluZXMgPSAob3V0KSA9PiBTdHJpbmcob3V0KS5z
::B64:agent.js:cGxpdCgiXG4iKS5maWx0ZXIoKGwpID0+IGwgJiYgbCAhPT0gIlRpZGFrIGRpdGVtdWthbiIpOwoKLy8gVWJhaCB1Y2FwYW4gc2VwZXJ0aSAibGFwb3Jhbi5wZGYiLCAiZm9sZGVyIFJlaWEiLCAieWFuZyB0ZXJiYXJ1IGRpIGRvd25sb2FkcyIgbWVuamFkaSBwYXRo
::B64:agent.js:IG55YXRhCmFzeW5jIGZ1bmN0aW9uIHJlc29sdmVVcGxvYWRTb3VyY2Uod2hhdCkgewogIGNvbnN0IHcgPSB0aWR5KHdoYXQpLnJlcGxhY2UoL15bIiddfFsiJ10kL2csICIiKTsKICBsZXQgbW07CiAgaWYgKChtbSA9IHcubWF0Y2goL15zZW11YVxzKyg/OmZpbGVc
::B64:agent.js:cyspPyguKz8pXHMrKD86ZGl8ZGFyaSlccysoPzpmb2xkZXJccyspPyguKykkL2kpKSkgewogICAgY29uc3Qga2luZCA9IG1tWzFdLnRyaW0oKS50b0xvd2VyQ2FzZSgpOwogICAgY29uc3QgcGF0dGVybiA9IEZJTEVfS0lORFNba2luZF0gfHwgKC9eW2EtejAtOV17
::B64:agent.js:Miw1fSQvLnRlc3Qoa2luZCkgPyAiLiIgKyBraW5kIDoga2luZCk7CiAgICBsZXQgZm9sZGVyID0ga25vd25EaXIobW1bMl0pOwogICAgaWYgKCFmb2xkZXIpIHsKICAgICAgY29uc3QgbGluZXMgPSByZXN1bHRMaW5lcyhzZWFyY2hFdmVyeXdoZXJlKG1tWzJdLnRy
::B64:agent.js:aW0oKSwgZmFsc2UpKTsKICAgICAgaWYgKCFsaW5lcy5sZW5ndGgpIHRocm93IG5ldyBFcnJvcihgRm9sZGVyICIke21tWzJdfSIgdGlkYWsgZGl0ZW11a2FuYCk7CiAgICAgIGZvbGRlciA9IGJlc3RQYXRoKGxpbmVzLCBtbVsyXSk7CiAgICB9CiAgICByZXR1cm4g
::B64:agent.js:eyBmb2xkZXIsIHBhdHRlcm4sIGxhYmVsOiBgc2VtdWEgJHtraW5kfSBkaSAke2ZvbGRlcn1gIH07CiAgfQogIGlmICgobW0gPSB3Lm1hdGNoKC9eKD86ZmlsZVxzKyk/KD86eWFuZ1xzKyk/KD86cGFsaW5nXHMrKT8oPzp0ZXJiYXJ1fHRlcmFraGlyfGJhcnUpKD86
::B64:agent.js:XHMrKD86ZGl8ZGFyaSlccysoPzpmb2xkZXJccyspPyguKykpPyQvaSkpKSB7CiAgICBjb25zdCBkaXIgPSBtbVsxXSA/IGtub3duRGlyKG1tWzFdKSB8fCBwYXRoLnJlc29sdmUobW1bMV0pIDogcGF0aC5qb2luKEhPTUUsICJEb3dubG9hZHMiKTsKICAgIGNvbnN0
::B64:agent.js:IG5ld2VzdCA9IHJlY2VudExpc3QoZGlyLCAxKVswXTsKICAgIGlmICghbmV3ZXN0KSB0aHJvdyBuZXcgRXJyb3IoIlRpZGFrIGFkYSBmaWxlIGRpICIgKyBkaXIpOwogICAgcmV0dXJuIHsgZmlsZW5hbWU6IG5ld2VzdC5mLCBsYWJlbDogYGZpbGUgdGVyYmFydSBk
::B64:agent.js:aSAke2Rpcn1gIH07CiAgfQogIGlmICgobW0gPSB3Lm1hdGNoKC9eZm9sZGVyXHMrKC4rKSQvaSkpKSB7CiAgICBsZXQgZm9sZGVyID0ga25vd25EaXIobW1bMV0pOwogICAgaWYgKCFmb2xkZXIpIHsKICAgICAgY29uc3QgbGluZXMgPSByZXN1bHRMaW5lcyhzZWFy
::B64:agent.js:Y2hFdmVyeXdoZXJlKG1tWzFdLnRyaW0oKSwgZmFsc2UpKTsKICAgICAgaWYgKCFsaW5lcy5sZW5ndGgpIHRocm93IG5ldyBFcnJvcihgRm9sZGVyICIke21tWzFdfSIgdGlkYWsgZGl0ZW11a2FuYCk7CiAgICAgIGZvbGRlciA9IGJlc3RQYXRoKGxpbmVzLCBtbVsx
::B64:agent.js:XSk7CiAgICB9CiAgICByZXR1cm4geyBmaWxlbmFtZTogZm9sZGVyLCBsYWJlbDogYGZvbGRlciAke2ZvbGRlcn0gKGRpa2lyaW0gc2ViYWdhaSB6aXApYCB9OwogIH0KICBjb25zdCBkaXJlY3QgPSBwYXRoLnJlc29sdmUoU0FGRV9ESVIsIHcpOwogIGlmIChmcy5l
::B64:agent.js:eGlzdHNTeW5jKGRpcmVjdCkpIHJldHVybiB7IGZpbGVuYW1lOiBkaXJlY3QsIGxhYmVsOiBkaXJlY3QgfTsKICBjb25zdCBsaW5lcyA9IHJlc3VsdExpbmVzKHNlYXJjaEV2ZXJ5d2hlcmUodywgdHJ1ZSkpOwogIGlmICghbGluZXMubGVuZ3RoKSB0aHJvdyBuZXcg
::B64:agent.js:RXJyb3IoYEZpbGUgIiR7d30iIHRpZGFrIGRpdGVtdWthbmApOwogIHJldHVybiB7IGZpbGVuYW1lOiBiZXN0UGF0aChsaW5lcywgdyksIGxhYmVsOiB3IH07Cn0KCmFzeW5jIGZ1bmN0aW9uIHRyeUZhc3RDb21tYW5kKHJhdykgewogIGNvbnN0IGMgPSBTdHJpbmco
::B64:agent.js:cmF3KS50cmltKCkucmVwbGFjZSgvXHMrL2csICIgIik7CiAgbGV0IG07CiAgY29uc3QgeXQgPSBvbllvdVR1YmUoKTsKCiAgLy8gLS0tLSBWb2x1bWUgLS0tLQogIGlmICgobSA9IGMubWF0Y2goL14oPzooPzphdHVyfHNldHx1YmFoKVxzKyk/KD86dm9sdW1lfHN1
::B64:agent.js:YXJhKSg/Om55YSk/XHMqKD86amFkaXxrZXxtZW5qYWRpfD18ZGkpP1xzKihcZHsxLDN9KVxzKiU/JC9pKSkgfHwKICAgICAgKG0gPSBjLm1hdGNoKC9eKD86bmFpa2lufG5haWtrYW58dHVydW5pbnx0dXJ1bmthbnxrZWNpbGlufGtlY2lsa2FufGJlc2FyaW58YmVz
::B64:agent.js:YXJrYW4pXHMrKD86dm9sdW1lfHN1YXJhKSg/Om55YSk/XHMrKD86amFkaXxrZXxtZW5qYWRpKVxzKihcZHsxLDN9KVxzKiU/JC9pKSkpIHsKICAgIHJldHVybiBhd2FpdCBpbXBsLnNldF92b2x1bWUoeyBsZXZlbDogbVsxXSB9KTsKICB9CiAgaWYgKChtID0gYy5t
::B64:agent.js:YXRjaCgvXig/Om5haWtpbnxuYWlra2FufGJlc2FyaW58YmVzYXJrYW58a2VyYXNrYW58dGFtYmFoKD86aW58a2FuKT8pXHMrKD86dm9sdW1lfHN1YXJhKSg/Om55YSk/KD86XHMrKFxkezEsM30pXHMqJT8pPyQvaSkpKSB7CiAgICBhd2FpdCBpbXBsLm1lZGlhX2tl
::B64:agent.js:eSh7IGtleTogInZvbHVwIiwgdGltZXM6IG1bMV0gPyBNYXRoLm1heCgxLCBNYXRoLnJvdW5kKE51bWJlcihtWzFdKSAvIDIpKSA6IDUgfSk7CiAgICByZXR1cm4gYFZvbHVtZSBkaW5haWtrYW4gJHttWzFdID8gbVsxXSArICIlIiA6ICJzZWtpdGFyIDEwJSJ9LmA7
::B64:agent.js:CiAgfQogIGlmICgobSA9IGMubWF0Y2goL14oPzp0dXJ1bmlufHR1cnVua2FufGtlY2lsaW58a2VjaWxrYW58cGVsYW5pbnxwZWxhbmthbnxrdXJhbmdpfGt1cmFuZ2luKVxzKyg/OnZvbHVtZXxzdWFyYSkoPzpueWEpPyg/OlxzKyhcZHsxLDN9KVxzKiU/KT8kL2kp
::B64:agent.js:KSkgewogICAgYXdhaXQgaW1wbC5tZWRpYV9rZXkoeyBrZXk6ICJ2b2xkb3duIiwgdGltZXM6IG1bMV0gPyBNYXRoLm1heCgxLCBNYXRoLnJvdW5kKE51bWJlcihtWzFdKSAvIDIpKSA6IDUgfSk7CiAgICByZXR1cm4gYFZvbHVtZSBkaXR1cnVua2FuICR7bVsxXSA/
::B64:agent.js:IG1bMV0gKyAiJSIgOiAic2VraXRhciAxMCUifS5gOwogIH0KICBpZiAoL14oPzptdXRlfHVubXV0ZXxiaXN1a2FufHNlbnlhcGthbnxtYXRpa2FuIHN1YXJhfG55YWxha2FuIHN1YXJhfGJ1bnlpa2FuKSg/OlxzKyg/OnN1YXJhfHZvbHVtZSkpPyQvaS50ZXN0KGMp
::B64:agent.js:KSB7CiAgICBhd2FpdCBpbXBsLm1lZGlhX2tleSh7IGtleTogIm11dGUiIH0pOwogICAgcmV0dXJuICJNdXRlIGRpdWJhaCAodG9nZ2xlKS4iOwogIH0KCiAgLy8gLS0tLSBLb250cm9sIHBlbXV0YXIgLS0tLQogIGlmICgvXig/OnBhdXNlfGplZGEpKD86XHMrKD86
::B64:agent.js:ZHVsdXx2aWRlb255YXxtdXNpa255YXxsYWd1bnlhfGxhZ3V8dmlkZW98bXVzaWt8eW91dHViZSkpKiQvaS50ZXN0KGMpIHx8CiAgICAgICh5dCAmJiAvXig/OnN0b3B8c2V0b3B8YmVyaGVudGl8aGVudGlrYW4pKD86XHMrKD86ZHVsdXx2aWRlb255YXxtdXNpa255
::B64:agent.js:YXxsYWd1bnlhKSkqJC9pLnRlc3QoYykpKSB7CiAgICBpZiAoeXQpIGF3YWl0IGltcGwueW91dHViZV9jb250cm9sKHsgYWN0aW9uOiAicGF1c2UiIH0pOwogICAgZWxzZSBhd2FpdCBpbXBsLm1lZGlhX2tleSh7IGtleTogInBsYXlwYXVzZSIgfSk7CiAgICByZXR1
::B64:agent.js:cm4gIkRpamVkYS4iOwogIH0KICBpZiAoL14oPzpwbGF5fHJlc3VtZXxwdXRhciBsYWdpfG11bGFpIGxhZ2kpKD86XHMrKD86ZHVsdXx2aWRlb255YXxtdXNpa255YXxsYWd1bnlhfGxhZ3V8dmlkZW98bXVzaWspKSokL2kudGVzdChjKSB8fAogICAgICAoeXQgJiYg
::B64:agent.js:L14oPzpsYW5qdXR8bGFuanV0a2FufHRlcnVzaW4pJC9pLnRlc3QoYykpKSB7CiAgICBpZiAoeXQpIGF3YWl0IGltcGwueW91dHViZV9jb250cm9sKHsgYWN0aW9uOiAicGxheSIgfSk7CiAgICBlbHNlIGF3YWl0IGltcGwubWVkaWFfa2V5KHsga2V5OiAicGxheXBh
::B64:agent.js:dXNlIiB9KTsKICAgIHJldHVybiAiRGlsYW5qdXRrYW4uIjsKICB9CiAgaWYgKC9eKD86bmV4dHxza2lwfHNlbGFuanV0bnlhfGJlcmlrdXRueWF8bGFndSBiZXJpa3V0bnlhfGxhZ3Ugc2VsYW5qdXRueWF8Z2FudGkgbGFndSkkL2kudGVzdChjKSkgewogICAgaWYg
::B64:agent.js:KHl0KSBhd2FpdCBpbXBsLnlvdXR1YmVfY29udHJvbCh7IGFjdGlvbjogIm5leHQiIH0pOwogICAgZWxzZSBhd2FpdCBpbXBsLm1lZGlhX2tleSh7IGtleTogIm5leHQiIH0pOwogICAgcmV0dXJuICJMYWd1L3ZpZGVvIGJlcmlrdXRueWEuIjsKICB9CiAgaWYgKC9e
::B64:agent.js:KD86cHJldmlvdXN8cHJldnxzZWJlbHVtbnlhfGxhZ3Ugc2ViZWx1bW55YSkkL2kudGVzdChjKSkgewogICAgaWYgKHl0KSBhd2FpdCBpbXBsLnlvdXR1YmVfY29udHJvbCh7IGFjdGlvbjogInByZXZpb3VzIiB9KTsKICAgIGVsc2UgYXdhaXQgaW1wbC5tZWRpYV9r
::B64:agent.js:ZXkoeyBrZXk6ICJwcmV2IiB9KTsKICAgIHJldHVybiAiTGFndS92aWRlbyBzZWJlbHVtbnlhLiI7CiAgfQogIGlmICh5dCAmJiAobSA9IGMubWF0Y2goL14oPzptYWp1fG1hanVpbnxmb3J3YXJkKVxzKihcZCspP1xzKig/OmRldGlrKT8kL2kpKSkgewogICAgYXdh
::B64:agent.js:aXQgaW1wbC55b3V0dWJlX2NvbnRyb2woeyBhY3Rpb246ICJmb3J3YXJkIiwgc2Vjb25kczogbVsxXSB8fCAxMCB9KTsKICAgIHJldHVybiBgTWFqdSAke21bMV0gfHwgMTB9IGRldGlrLmA7CiAgfQogIGlmICh5dCAmJiAobSA9IGMubWF0Y2goL14oPzptdW5kdXJ8
::B64:agent.js:bXVuZHVyaW58cmV3aW5kKVxzKihcZCspP1xzKig/OmRldGlrKT8kL2kpKSkgewogICAgYXdhaXQgaW1wbC55b3V0dWJlX2NvbnRyb2woeyBhY3Rpb246ICJiYWNrd2FyZCIsIHNlY29uZHM6IG1bMV0gfHwgMTAgfSk7CiAgICByZXR1cm4gYE11bmR1ciAke21bMV0g
::B64:agent.js:fHwgMTB9IGRldGlrLmA7CiAgfQogIGlmICh5dCAmJiAvXig/OmZ1bGxzY3JlZW58bGF5YXIgcGVudWgpJC9pLnRlc3QoYykpIHsKICAgIGF3YWl0IGltcGwueW91dHViZV9jb250cm9sKHsgYWN0aW9uOiAiZnVsbHNjcmVlbiIgfSk7CiAgICByZXR1cm4gIkZ1bGxz
::B64:agent.js:Y3JlZW4gZGl1YmFoLiI7CiAgfQoKICAvLyAtLS0tIFlvdVR1YmU6IHB1dGFyIGxhZ3UvdmlkZW8gLS0tLQogIGlmICgvXig/Om5vbnRvbnx0b250b258YnVrYXxwdXRhcilccyt5b3V0dWJlJC9pLnRlc3QoYykpIHsKICAgIGF3YWl0IGltcGwub3Blbl91cmwoeyB1
::B64:agent.js:cmw6ICJodHRwczovL3d3dy55b3V0dWJlLmNvbSIsIG5ld190YWI6ICFpc0JsYW5rUGFnZSgpIH0pOwogICAgcmV0dXJuICJZb3VUdWJlIGRpYnVrYS4iOwogIH0KICBpZiAoKG0gPSBjLm1hdGNoKC9eKD86cHV0YXIoPzprYW58aW4pP3xzZXRlbCg/OmluKT98cGxh
::B64:agent.js:eXxkZW5nZXJpbnxkZW5nYXJrYW58bm9udG9uKD86aW4pP3x0b250b258Y2FyaSg/OmlufGthbik/KVxzKyg/OmxhZ3V8bXVzaWt8bXVzaWN8dmlkZW98dmlkaW98ZmlsbSlccysoLispJC9pKSkgfHwKICAgICAgKG0gPSBjLm1hdGNoKC9eKD86cHV0YXIoPzprYW58
::B64:agent.js:aW4pP3xzZXRlbCg/OmluKT98cGxheXxkZW5nZXJpbnxkZW5nYXJrYW58bm9udG9uKD86aW4pP3x0b250b24pXHMrKC4rKSQvaSkpKSB7CiAgICBjb25zdCBxID0gdGlkeShtWzFdKS5yZXBsYWNlKC9ccysoPzpkaXxkYXJpfGxld2F0KVxzK3lvdXR1YmUkL2ksICIi
::B64:agent.js:KTsKICAgIGlmICghcSB8fCAvXig/OmZpbGV8Zm9sZGVyfGRva3VtZW4pXGIvaS50ZXN0KHEpIHx8IC9bYS16XTpcXHxcLig/Om1wM3xtcDR8bWt2fGF2aXx3YXZ8cGRmfHppcHx0eHQpXGIvaS50ZXN0KHEpKSByZXR1cm4gbnVsbDsKICAgIGNvbnN0IG91dCA9IGF3
::B64:agent.js:YWl0IGltcGwueW91dHViZV9wbGF5KHsgcXVlcnk6IHEsIG5ld190YWI6ICFvbllvdVR1YmVTaXRlKCkgJiYgIWlzQmxhbmtQYWdlKCkgfSk7CiAgICByZXR1cm4gU3RyaW5nKG91dCkuc3BsaXQoIlxuIilbMF07CiAgfQoKICAvLyAtLS0tIFVwbG9hZCBjZXBhdCAt
::B64:agent.js:LS0tCiAgaWYgKChtID0gYy5tYXRjaCgvXig/OnVwbG9hZHx1bmdnYWh8dXBsb3VkfGtpcmltKVxzKyg/OmZpbGVccyspPyguKz8pXHMra2VccysoXFMrKSQvaSkpKSB7CiAgICBjb25zdCB0YXJnZXQgPSB1cGxvYWRVcmwobVsyXSk7CiAgICBpZiAoIXRhcmdldCkg
::B64:agent.js:cmV0dXJuIG51bGw7IC8vIHR1anVhbiB0aWRhayBkaWtlbmFsIC0+IHNlcmFoa2FuIGtlIEFJCiAgICBjb25zdCBzcmMgPSBhd2FpdCByZXNvbHZlVXBsb2FkU291cmNlKG1bMV0pOwogICAgcmV0dXJuIGF3YWl0IGltcGwuZmFzdF91cGxvYWQoeyB1cmw6IHRhcmdl
::B64:agent.js:dCwgZmlsZW5hbWU6IHNyYy5maWxlbmFtZSwgZm9sZGVyOiBzcmMuZm9sZGVyLCBwYXR0ZXJuOiBzcmMucGF0dGVybiB9KTsKICB9CgogIC8vIC0tLS0gQnVrYSBmb2xkZXIgLyBzaXR1cyAvIGFwbGlrYXNpIC0tLS0KICBpZiAoKG0gPSBjLm1hdGNoKC9eYnVrYSg/
::B64:agent.js:OmlufGthbik/XHMrZm9sZGVyXHMrKC4rKSQvaSkpKSB7CiAgICBjb25zdCBuYW1lID0gdGlkeShtWzFdKTsKICAgIGxldCBkaXIgPSBrbm93bkRpcihuYW1lKTsKICAgIGxldCBleHRyYSA9ICIiOwogICAgaWYgKCFkaXIpIHsKICAgICAgY29uc3QgbGluZXMgPSBy
::B64:agent.js:ZXN1bHRMaW5lcyhzZWFyY2hFdmVyeXdoZXJlKG5hbWUsIGZhbHNlKSk7CiAgICAgIGlmICghbGluZXMubGVuZ3RoKSByZXR1cm4gYEZvbGRlciAiJHtuYW1lfSIgdGlkYWsgZGl0ZW11a2FuLmA7CiAgICAgIGRpciA9IGJlc3RQYXRoKGxpbmVzLCBuYW1lKTsKICAg
::B64:agent.js:ICAgaWYgKGxpbmVzLmxlbmd0aCA+IDEpIGV4dHJhID0gYFxuKCR7bGluZXMubGVuZ3RoIC0gMX0gZm9sZGVyIGxhaW4gY29jb2s6ICR7bGluZXMuZmlsdGVyKChsKSA9PiBsICE9PSBkaXIpLnNsaWNlKDAsIDMpLmpvaW4oIiB8ICIpfSlgOwogICAgfQogICAgY29u
::B64:agent.js:c3QgciA9IGF3YWl0IGltcGwub3Blbl9wYXRoKHsgdGFyZ2V0OiBkaXIgfSk7CiAgICByZXR1cm4gU3RyaW5nKHIpLnN0YXJ0c1dpdGgoIkRpYmF0YWxrYW4iKSA/IHIgOiBgRm9sZGVyIGRpYnVrYTogJHtkaXJ9JHtleHRyYX1gOwogIH0KICBpZiAoKG0gPSBjLm1h
::B64:agent.js:dGNoKC9eKD86YnVrYSg/OmlufGthbik/fG9wZW4pXHMrKC4rPykoPzpccytzZWthbGlndXMpPyQvaSkpKSB7CiAgICBjb25zdCB0b2tlbnMgPSBtWzFdCiAgICAgIC5zcGxpdCgvXHMqKD86LHxcYmRhblxifCZ8XCspXHMqL2kpCiAgICAgIC5tYXAoKHgpID0+IHgu
::B64:agent.js:cmVwbGFjZSgvXHMrKD86ZGlccyspP3RhYlxzK2JhcnUkL2ksICIiKS50cmltKCkpCiAgICAgIC5maWx0ZXIoQm9vbGVhbik7CiAgICBjb25zdCB1cmxzID0gdG9rZW5zLm1hcChzaXRlVXJsKTsKICAgIGlmICh0b2tlbnMubGVuZ3RoICYmIHVybHMuZXZlcnkoQm9v
::B64:agent.js:bGVhbikpIHsKICAgICAgaWYgKHVybHMubGVuZ3RoID09PSAxKSB7CiAgICAgICAgYXdhaXQgaW1wbC5vcGVuX3VybCh7IHVybDogdXJsc1swXSwgbmV3X3RhYjogIWlzQmxhbmtQYWdlKCkgfSk7CiAgICAgICAgcmV0dXJuIGBEaWJ1a2E6ICR7dXJsc1swXX1gOwog
::B64:agent.js:ICAgICB9CiAgICAgIGF3YWl0IGltcGwub3Blbl91cmxzKHsgdXJscyB9KTsKICAgICAgcmV0dXJuIGAke3VybHMubGVuZ3RofSB0YWIgZGlidWthOiAke3VybHMuam9pbigiLCAiKX1gOwogICAgfQogICAgaWYgKHRva2Vucy5sZW5ndGggPT09IDEgJiYgQVBQU1t0
::B64:agent.js:b2tlbnNbMF0udG9Mb3dlckNhc2UoKV0pIHsKICAgICAgY29uc3QgciA9IGF3YWl0IGltcGwub3Blbl9wYXRoKHsgdGFyZ2V0OiBBUFBTW3Rva2Vuc1swXS50b0xvd2VyQ2FzZSgpXSB9KTsKICAgICAgcmV0dXJuIFN0cmluZyhyKS5zdGFydHNXaXRoKCJEaWJhdGFs
::B64:agent.js:a2FuIikgPyByIDogYCR7dG9rZW5zWzBdfSBkaWJ1a2EuYDsKICAgIH0KICB9CgogIC8vIC0tLS0gQ2FyaSBmaWxlIC8gZm9sZGVyIC8gd2ViIC0tLS0KICBpZiAoKG0gPSBjLm1hdGNoKC9eY2FyaSg/OmlufGthbik/XHMrKGZpbGV8Zm9sZGVyKVxzKyguKykkL2kp
::B64:agent.js:KSkgewogICAgY29uc3Qgb3V0ID0gc2VhcmNoRXZlcnl3aGVyZSh0aWR5KG1bMl0pLCBtWzFdLnRvTG93ZXJDYXNlKCkgPT09ICJmaWxlIik7CiAgICByZXR1cm4gb3V0ID09PSAiVGlkYWsgZGl0ZW11a2FuIiA/IGAke21bMV19ICIke3RpZHkobVsyXSl9IiB0aWRh
::B64:agent.js:ayBkaXRlbXVrYW4uYCA6IG91dDsKICB9CiAgaWYgKChtID0gYy5tYXRjaCgvXig/OmNhcmkoPzppbnxrYW4pP3xnb29nbGluZylccysoPzp0YXVccyspPyguKz8pXHMrKD86ZGlccyspPyg/OndlYnxnb29nbGV8aW50ZXJuZXR8YnJvd3NlcikkL2kpKSkgewogICAg
::B64:agent.js:cmV0dXJuIGF3YWl0IGltcGwud2ViX3NlYXJjaCh7IHF1ZXJ5OiB0aWR5KG1bMV0pLCBuZXdfdGFiOiAhaXNCbGFua1BhZ2UoKSB9KTsKICB9CiAgaWYgKC9eKD86bGloYXR8dGFtcGlsa2FufGNlayk/XHMqKD86ZmlsZXx1bmR1aGFufGRvd25sb2FkKD86YW4pPylc
::B64:agent.js:cysoPzp5YW5nXHMrKT90ZXJiYXJ1KD86XHMrKD86ZGlccyspP1xTKyk/JC9pLnRlc3QoYykpIHsKICAgIHJldHVybiBhd2FpdCBpbXBsLnJlY2VudF9maWxlcyh7fSk7CiAgfQoKICAvLyAtLS0tIFRhYiAtLS0tCiAgaWYgKC9eKD86dHV0dXApXHMrdGFiKD86XHMr
::B64:agent.js:aW5pKT8kL2kudGVzdChjKSkgcmV0dXJuIChhd2FpdCBpbXBsLmNsb3NlX3RhYih7fSkpLnNwbGl0KCJcbiIpWzBdOwogIGlmICgobSA9IGMubWF0Y2goL14oPzpwaW5kYWh8a2V8YnVrYSlccyt0YWJccysodGVyYmFydXxiYXJ1fHRlcmFraGlyfFxkKykkL2kpKSkg
::B64:agent.js:ewogICAgY29uc3QgaWR4ID0gL15cZCskLy50ZXN0KG1bMV0pID8gTnVtYmVyKG1bMV0pIDogLTE7CiAgICByZXR1cm4gYXdhaXQgaW1wbC5zd2l0Y2hfdGFiKHsgaW5kZXg6IGlkeCB9KTsKICB9CiAgaWYgKC9eKD86ZGFmdGFyfGxpc3R8bGloYXQpXHMrdGFiJC9p
::B64:agent.js:LnRlc3QoYykpIHJldHVybiBhd2FpdCBpbXBsLmxpc3RfdGFicygpOwoKICAvLyAtLS0tIE1hdGlrYW4gYXBsaWthc2kgLyBnYW1lIC0tLS0KICBpZiAoKG0gPSBjLm1hdGNoKC9edGFza2tpbGxccysuKj9cL2ltXHMrKFtcdy4tXSspL2kpKSB8fAogICAgICAobSA9
::B64:agent.js:IGMubWF0Y2goL14oPzptYXRpa2FufHR1dHVwfGtpbGx8c3RvcHxoZW50aWthbnxwYWtzYSB0dXR1cHxmb3JjZSBjbG9zZSlccysoPzphcGxpa2FzaSB8YXBwIHxwcm9ncmFtIHxnYW1lIHxwcm9zZXMgKT8oW1x3Li1dKyg/OiBbXHcuLV0rKT8pJC9pKSkpIHsKICAg
::B64:agent.js:IGNvbnN0IHRhcmdldCA9IG1bMV0udHJpbSgpOwogICAgaWYgKC9eKD86c3VhcmF8dm9sdW1lfGtvbXB1dGVyfGxhcHRvcHxwY3x3aWZpfGJsdWV0b290aHxsYXlhcnxsYW1wdXx0YWJ8amVuZGVsYXx3aW5kb3d8bXVzaWt8bGFndXx2aWRlb3x0aW1lcnxhbGFybXx5
::B64:agent.js:b3V0dWJlfHNlbXVhfGluaXxpdHV8Y2hyb21lfGJyb3dzZXIpXGIvaS50ZXN0KHRhcmdldCkpIHJldHVybiBudWxsOwogICAgcmV0dXJuIGF3YWl0IGltcGwua2lsbF9wcm9jZXNzKHsgbmFtZTogdGFyZ2V0IH0pOwogIH0KCiAgLy8gLS0tLSBQQyAtLS0tCiAgaWYg
::B64:agent.js:KC9eKD86aW5mb3xjZWt8c3RhdHVzfGxpaGF0KVxzKig/OnBjfGtvbXB1dGVyfGxhcHRvcHxzaXN0ZW18c3Bla3xyYW18Y3B1fGJhdGVyYWl8ZGlza3xzdG9yYWdlfG1lbW9yaSlcYi9pLnRlc3QoYykpIHJldHVybiBhd2FpdCBpbXBsLnN5c3RlbV9pbmZvKCk7CiAg
::B64:agent.js:aWYgKC9eKD86amFtIGJlcmFwYXx0YW5nZ2FsIGJlcmFwYXxoYXJpIGFwYXxzZWthcmFuZyBqYW0gYmVyYXBhfHNla2FyYW5nIHRhbmdnYWwgYmVyYXBhfGphbSBiZXJhcGEgc2VrYXJhbmcpXD8/JC9pLnRlc3QoYykpIHJldHVybiBhd2FpdCBpbXBsLm5vdygpOwog
::B64:agent.js:IGlmICgvXig/OnNjcmVlbnNob3R8dGFuZ2thcCBsYXlhcnxzc3xjYXB0dXJlKSg/OlxzK2xheWFyKT8kL2kudGVzdChjKSkgcmV0dXJuIGF3YWl0IGltcGwuc2F2ZV9zY3JlZW5zaG90KHt9KTsKICBpZiAoKG0gPSBjLm1hdGNoKC9eKD86aW5nYXRrYW58aW5nZXRp
::B64:agent.js:bnxpbmdhdGlufHRpbWVyfGFsYXJtfHNldCB0aW1lcilccysoPzpha3Vccyt8c2F5YVxzK3xndWVccyspPyg/OmRhbGFtXHMrKT8oXGQrKD86Wy4sXVxkKyk/KVxzKihtZW5pdHxkZXRpa3xqYW0pXHMqKD86bGFnaSk/XHMqKD86dW50dWt8YnVhdHw6KT9ccyooLiop
::B64:agent.js:JC9pKSkpIHsKICAgIHJldHVybiBhd2FpdCBpbXBsLnNldF90aW1lcih7IGFtb3VudDogbVsxXSwgdW5pdDogbVsyXSwgbWVzc2FnZTogdGlkeShtWzNdKSB8fCAiV2FrdHVueWEhIiB9KTsKICB9CiAgaWYgKChtID0gYy5tYXRjaCgvXig/OnVjYXBrYW58YmlsYW5n
::B64:agent.js:fGthdGFrYW58YmFjYWthbilccysoLispJC9pKSkpIHJldHVybiBhd2FpdCBpbXBsLnNwZWFrKHsgdGV4dDogdGlkeShtWzFdKSB9KTsKCiAgcmV0dXJuIG51bGw7IC8vIHRpZGFrIGRpa2VuYWwgLT4gQUkKfQoKLy8gPT09PT0gTWVtb3JpIHBlcmNha2FwYW4gPT09
::B64:agent.js:PT0KY29uc3QgaGlzdG9yeSA9IFtdOwpjb25zdCBNQVhfSElTVE9SWSA9IDMwOwoKZnVuY3Rpb24gc3RyaXBJbWFnZXMoKSB7CiAgZm9yIChjb25zdCBtIG9mIGhpc3RvcnkpIHsKICAgIGlmIChtLnJvbGUgPT09ICJ1c2VyIiAmJiBBcnJheS5pc0FycmF5KG0uY29u
::B64:agent.js:dGVudCkpIHsKICAgICAgbS5jb250ZW50ID0gIltzY3JlZW5zaG90IGxhbWEgZGloYXB1cyB1bnR1ayBtZW5naGVtYXQgbWVtb3JpXSI7CiAgICB9CiAgfQp9CgpmdW5jdGlvbiB0cmltSGlzdG9yeSgpIHsKICB3aGlsZSAoaGlzdG9yeS5sZW5ndGggPiBNQVhfSElT
::B64:agent.js:VE9SWSkgewogICAgbGV0IGkgPSAxOwogICAgd2hpbGUgKGkgPCBoaXN0b3J5Lmxlbmd0aCAmJiAhKGhpc3RvcnlbaV0ucm9sZSA9PT0gInVzZXIiICYmIHR5cGVvZiBoaXN0b3J5W2ldLmNvbnRlbnQgPT09ICJzdHJpbmciKSkgaSsrOwogICAgaWYgKGkgPj0gaGlz
::B64:agent.js:dG9yeS5sZW5ndGgpIGJyZWFrOwogICAgaGlzdG9yeS5zcGxpY2UoMCwgaSk7CiAgfQp9Cgphc3luYyBmdW5jdGlvbiBydW5UYXNrKGNvbW1hbmQpIHsKICBjb25zdCBzdGFydExlbiA9IGhpc3RvcnkubGVuZ3RoOwogIGhpc3RvcnkucHVzaCh7IHJvbGU6ICJ1c2Vy
::B64:agent.js:IiwgY29udGVudDogY29tbWFuZCB9KTsKICBsZXQgbnVkZ2VzID0gMDsKCiAgdHJ5IHsKICAgIGZvciAobGV0IHN0ZXAgPSAxOyBzdGVwIDw9IE1BWF9TVEVQUzsgc3RlcCsrKSB7CiAgICAgIGNvbnN0IG1zZyA9IGF3YWl0IGNhbGxMTE0oW3sgcm9sZTogInN5c3Rl
::B64:agent.js:bSIsIGNvbnRlbnQ6IFNZU1RFTSB9LCAuLi5oaXN0b3J5XSk7CiAgICAgIGhpc3RvcnkucHVzaChtc2cpOwoKICAgICAgaWYgKCFtc2cudG9vbF9jYWxscz8ubGVuZ3RoKSB7CiAgICAgICAgLy8gTW9kZWwgY3VtYSBtZW51bGlzIHRla3MvcmVuY2FuYSB0YW5wYSBt
::B64:agent.js:ZW1hbmdnaWwgdG9vbCAtPiBwYWtzYSBwYW5nZ2lsIHRvb2wKICAgICAgICBpZiAobnVkZ2VzIDwgMykgewogICAgICAgICAgbnVkZ2VzKys7CiAgICAgICAgICBoaXN0b3J5LnB1c2goewogICAgICAgICAgICByb2xlOiAidXNlciIsCiAgICAgICAgICAgIGNvbnRl
::B64:agent.js:bnQ6ICJLYW11IGhhcnVzIG1lbWFuZ2dpbCB0b29sLiBKYW5nYW4gbWVudWxpcyB0ZWtzIGJpYXNhLiBMYW5nc3VuZyBwYW5nZ2lsIHRvb2wgeWFuZyBzZXN1YWksIGF0YXUgcGFuZ2dpbCBkb25lIGppa2EgdHVnYXMgc3VkYWggc2VsZXNhaS4iLAogICAgICAgICAg
::B64:agent.js:fSk7CiAgICAgICAgICBjb250aW51ZTsKICAgICAgICB9CiAgICAgICAgY29uc29sZS5sb2coIlxuQWdlbnQ6IiwgbXNnLmNvbnRlbnQgfHwgIih0aWRhayBhZGEgamF3YWJhbikiKTsKICAgICAgICByZXR1cm47CiAgICAgIH0KCiAgICAgIC8vIFR1Z2FzIHNlbGVz
::B64:agent.js:YWk6IHNlbXVhIHRvb2xfY2FsbCB3YWppYiBkaWphd2FiIGFnYXIgcml3YXlhdCB0ZXRhcCB2YWxpZAogICAgICBjb25zdCBkb25lQ2FsbCA9IG1zZy50b29sX2NhbGxzLmZpbmQoKGMpID0+IGMuZnVuY3Rpb24ubmFtZSA9PT0gImRvbmUiKTsKICAgICAgaWYgKGRv
::B64:agent.js:bmVDYWxsKSB7CiAgICAgICAgbGV0IG0gPSAiIjsKICAgICAgICB0cnkgewogICAgICAgICAgbSA9IEpTT04ucGFyc2UoZG9uZUNhbGwuZnVuY3Rpb24uYXJndW1lbnRzIHx8ICJ7fSIpLm1lc3NhZ2UgfHwgIiI7CiAgICAgICAgfSBjYXRjaCB7fQogICAgICAgIGZv
::B64:agent.js:ciAoY29uc3QgY2FsbCBvZiBtc2cudG9vbF9jYWxscykgewogICAgICAgICAgaGlzdG9yeS5wdXNoKHsgcm9sZTogInRvb2wiLCB0b29sX2NhbGxfaWQ6IGNhbGwuaWQsIGNvbnRlbnQ6IGNhbGwgPT09IGRvbmVDYWxsID8gIm9rIiA6ICJkaWxld2F0aSIgfSk7CiAg
::B64:agent.js:ICAgICAgfQogICAgICAgIGNvbnNvbGUubG9nKCJcbkFnZW50OiIsIG0gfHwgIlNlbGVzYWkuIik7CiAgICAgICAgcmV0dXJuOwogICAgICB9CgogICAgICBjb25zdCBleGVjQ2FsbCA9IGFzeW5jIChjYWxsKSA9PiB7CiAgICAgICAgY29uc3QgbmFtZSA9IGNhbGwu
::B64:agent.js:ZnVuY3Rpb24ubmFtZTsKICAgICAgICB0cnkgewogICAgICAgICAgY29uc3QgYXJncyA9IEpTT04ucGFyc2UoY2FsbC5mdW5jdGlvbi5hcmd1bWVudHMgfHwgInt9Iik7CiAgICAgICAgICBjb25zb2xlLmxvZyhgWyR7c3RlcH1dICR7bmFtZX1gLCBhcmdzKTsKICAg
::B64:agent.js:ICAgICAgIGlmICghaW1wbFtuYW1lXSkgdGhyb3cgbmV3IEVycm9yKCJUb29sIHRpZGFrIGRpa2VuYWw6ICIgKyBuYW1lKTsKICAgICAgICAgIGF3YWl0IGVuc3VyZVBhZ2UoKTsKICAgICAgICAgIHJldHVybiBhd2FpdCBpbXBsW25hbWVdKGFyZ3MpOwogICAgICAg
::B64:agent.js:IH0gY2F0Y2ggKGUpIHsKICAgICAgICAgIHJldHVybiAiRVJST1I6ICIgKyBlLm1lc3NhZ2U7CiAgICAgICAgfQogICAgICB9OwogICAgICBjb25zdCBjYWxscyA9IG1zZy50b29sX2NhbGxzOwogICAgICBjb25zdCByZXN1bHRzID0gW107CiAgICAgIGlmIChjYWxs
::B64:agent.js:cy5sZW5ndGggPiAxICYmIGNhbGxzLmV2ZXJ5KChjKSA9PiBTQUZFX1BBUkFMTEVMLmhhcyhjLmZ1bmN0aW9uLm5hbWUpKSkgewogICAgICAgIHJlc3VsdHMucHVzaCguLi4oYXdhaXQgUHJvbWlzZS5hbGwoY2FsbHMubWFwKGV4ZWNDYWxsKSkpKTsgLy8gYWxhdCBi
::B64:agent.js:YWNhLXNhamEgZGlqYWxhbmthbiBiZXJzYW1hYW4KICAgICAgfSBlbHNlIHsKICAgICAgICBmb3IgKGNvbnN0IGNhbGwgb2YgY2FsbHMpIHJlc3VsdHMucHVzaChhd2FpdCBleGVjQ2FsbChjYWxsKSk7CiAgICAgIH0KICAgICAgY2FsbHMuZm9yRWFjaCgoY2FsbCwg
::B64:agent.js:aSkgPT4KICAgICAgICBoaXN0b3J5LnB1c2goeyByb2xlOiAidG9vbCIsIHRvb2xfY2FsbF9pZDogY2FsbC5pZCwgY29udGVudDogU3RyaW5nKHJlc3VsdHNbaV0pLnNsaWNlKDAsIDQwMDApIH0pCiAgICAgICk7CgogICAgICAvLyBLaXJpbSBzY3JlZW5zaG90IChq
::B64:agent.js:aWthIGFkYSkgc2ViYWdhaSBnYW1iYXI7IGdhbWJhciBsYW1hIGRpYnVhbmcgYWdhciByaW5nYW4KICAgICAgaWYgKHBlbmRpbmdJbWFnZXMubGVuZ3RoKSB7CiAgICAgICAgc3RyaXBJbWFnZXMoKTsKICAgICAgICBoaXN0b3J5LnB1c2goewogICAgICAgICAgcm9s
::B64:agent.js:ZTogInVzZXIiLAogICAgICAgICAgY29udGVudDogWwogICAgICAgICAgICB7IHR5cGU6ICJ0ZXh0IiwgdGV4dDogIkluaSBzY3JlZW5zaG90IGxheWFyIHRlcmJhcnU6IiB9LAogICAgICAgICAgICAuLi5wZW5kaW5nSW1hZ2VzLnNwbGljZSgwKS5tYXAoKGI2NCkg
::B64:agent.js:PT4gKHsKICAgICAgICAgICAgICB0eXBlOiAiaW1hZ2VfdXJsIiwKICAgICAgICAgICAgICBpbWFnZV91cmw6IHsgdXJsOiBgZGF0YTppbWFnZS9wbmc7YmFzZTY0LCR7YjY0fWAgfSwKICAgICAgICAgICAgfSkpLAogICAgICAgICAgXSwKICAgICAgICB9KTsKICAg
::B64:agent.js:ICAgfQogICAgfQogICAgY29uc29sZS5sb2coIkJlcmhlbnRpOiBtZWxld2F0aSBiYXRhcyBsYW5na2FoLiIpOwogIH0gY2F0Y2ggKGUpIHsKICAgIGhpc3RvcnkubGVuZ3RoID0gc3RhcnRMZW47IC8vIGJ1YW5nIHJpd2F5YXQgdHVnYXMgeWFuZyBnYWdhbCBzdXBh
::B64:agent.js:eWEgdGlkYWsgbWVydXNhayBwZXJjYWthcGFuIGJlcmlrdXRueWEKICAgIHRocm93IGU7CiAgfSBmaW5hbGx5IHsKICAgIHN0cmlwSW1hZ2VzKCk7CiAgICB0cmltSGlzdG9yeSgpOwogIH0KfQoKY29uc3QgQlVJTFRJTl9DSEFOR0VMT0cgPSBgVmVyc2kgOQotIEJp
::B64:agent.js:c2EgbWVtYXRpa2FuIGFwbGlrYXNpL2dhbWU6IGtldGlrICJtYXRpa2FuIGNzMiIgYXRhdSAidHV0dXAgbm90ZXBhZCIuIFByb3NlcyBwZW50aW5nIFdpbmRvd3MgZGlsaW5kdW5naS4KLSBQZXJiYWlrYW4gdXBkYXRlOiB2ZXJzaSBsYW1hIGRpIEdpdEh1YiB0aWRh
::B64:agent.js:ayBiaXNhIGxhZ2kgbWVuaW1wYSBhZ2VudCB5YW5nIGxlYmloIGJhcnUuIFVwZGF0ZSBoYW55YSBqaWthIHZlcnNpIEdpdEh1YiBMRUJJSCBCQVJVLgotIEl6aW4gb3RvbWF0aXMgdGV0YXAgYmVybGFrdSBwYWRhIHNlbXVhIHZlcnNpIChrZWN1YWxpIGthbXUgbWVt
::B64:agent.js:aWxpaCAvYXV0byBvZmYpLgotIFZlcnNpIDg6IGl6aW4gb3RvbWF0aXMuIFZlcnNpIDc6IGphbHVyIGNlcGF0IHRhbnBhIEFJIGRhbiB1cGxvYWQgY2VwYXQuCktldGlrIC9iYW50dWFuIHVudHVrIGRhZnRhciBsZW5na2FwLmA7Cgpjb25zdCBIRUxQID0gYApKQUxV
::B64:agent.js:UiBDRVBBVCAodGFucGEgQUksIGxhbmdzdW5nIGphbGFuKQogIHB1dGFyIGxhZ3Uga2lzcyBtZSAgfCAgdm9sdW1lIDUwICB8ICBuYWlraW4gdm9sdW1lICB8ICBwYXVzZSAvIG5leHQgLyBtYWp1IDMwICB8ICBidWthIHlvdXR1YmUsIGdtYWlsCiAgYnVrYSBmb2xk
::B64:agent.js:ZXIgUmVpYSAgfCAgYnVrYSBrYW1lcmEgIHwgIGNhcmkgZmlsZSBsYXBvcmFuICB8ICBjYXJpIGN1YWNhIGJlc29rIGRpIHdlYiAgfCAgc2NyZWVuc2hvdAogIHVwbG9hZCBsYXBvcmFuLnBkZiBrZSBtZWRpYWZpcmUgIHwgIHVwbG9hZCBmaWxlIHRlcmJhcnUga2Ug
::B64:agent.js:bWVkaWFmaXJlICB8ICB1cGxvYWQgc2VtdWEgcGRmIGRpIGZvbGRlciBMYXBvcmFuIGtlIG1lZGlhZmlyZQogIGluZ2F0a2FuIDEwIG1lbml0IGxhZ2kgbWludW0gb2JhdCAgfCAgaW5mbyBwYyAgfCAgamFtIGJlcmFwYSAgfCAgbWF0aWthbiBjczIgIHwgIHR1dHVw
::B64:agent.js:IG5vdGVwYWQKRklUVVIgQUdFTlQgKGxld2F0IEFJIHVudHVrIHR1Z2FzIHlhbmcgbGViaWggcnVtaXQpCiAgQnJvd3NlciAgOiBidWthIHdlYnNpdGUsIGlzaSBmb3JtLCBrbGlrLCBjYXJpIGRpIHdlYiwgc2Nyb2xsLCBiYW55YWsgdGFiCiAgWW91VHViZSAgOiBw
::B64:agent.js:dXRhciBvdG9tYXRpcyAoc2tpcCBpa2xhbiksIGtvbnRyb2wgcGF1c2UvbmV4dC9tYWp1L211bmR1ci9tdXRlL2Z1bGxzY3JlZW4KICBVcGxvYWQgICA6IGNlcGF0LCBiYW55YWsgZmlsZSwgc2F0dSBmb2xkZXIgKGRpLXppcCksIGRhcmkgbG9rYXNpIG1hbmEgcHVu
::B64:agent.js:LCBtZW5hbXBpbGthbiBsaW5rIGhhc2lsCiAgTG9naW4gICAgOiAvbG9naW4gbGFsdSBsb2dpbiBtYW51YWwgc2VrYWxpLCBzZXNpIHRlcnNpbXBhbi4gQWdlbnQgdGlkYWsgcGVybmFoIG1lbmdldGlrIHBhc3N3b3JkbXUKICBMYXlhciAgICA6IHNjcmVlbnNob3Qs
::B64:agent.js:IGtsaWssIHNjcm9sbCwga2V0aWssIHRla2FuIHRvbWJvbCwgamVuZGVsYQogIEZpbGUgICAgIDogY2FyaSBmaWxlL2ZvbGRlciBzZW11YSBkcml2ZSwgYmFjYS90dWxpcywgc2FsaW4sIHBpbmRhaCwgemlwLCBoYXB1cyBrZSBSZWN5Y2xlIEJpbiwgdW5kdWgsIGNh
::B64:agent.js:cmkgdGVrcwogIFBDICAgICAgIDogdm9sdW1lLCB0b21ib2wgbWVkaWEsIGNsaXBib2FyZCwgaW5mbyBzaXN0ZW0sIGJpY2FyYSwgcGVuZ2luZ2F0ClBFUklOVEFIIEtIVVNVUwogIC9sb2dpbiBbYWxhbWF0XSAgbG9naW4gbWFudWFsICAgICAgICAgICAgL2JhcnUg
::B64:agent.js:ICBmaXR1ciB0ZXJiYXJ1ICAgICAgICAgIC9mYXN0IG9ufG9mZiAgamFsdXIgY2VwYXQKICAvdGVzICAgICAgICAgICAgIHVqaSBtb2RlbCwgcGlsaWggVEVSQ0VQQVQgICAgL21vZGVsIFtuYW1hXSAgbGloYXQvZ2FudGkgbW9kZWwKICAvdXBkYXRlICAgICAgICAg
::B64:agent.js:IHBlcmJhcnVpIHNla2FyYW5nICAgICAgIC92ZXJzaSAgY2VrIHZlcnNpICAgICAgICAgICAgICAvcmVzZXQgIGx1cGFrYW4gcGVyY2FrYXBhbgogIC9hdXRvIG9ufGFtYW58b2ZmICBpemluIG90b21hdGlzIHlhIC8gb3RvbWF0aXMga2VjdWFsaSBha3NpIG1lcnVz
::B64:agent.js:YWsgLyBzZWxhbHUgdGFueWEKICAvYmFudHVhbiAgICAgICAgIHRhbXBpbGthbiBpbmkgICAgICAgICAgIGV4aXQgICAga2VsdWFyCmA7CgpmdW5jdGlvbiBzaG93V2hhdHNOZXcoZm9yY2UgPSBmYWxzZSkgewogIGNvbnN0IHZlciA9IGxvY2FsVmVyc2lvbigpOwog
::B64:agent.js:IGxldCBzZWVuID0gIiI7CiAgdHJ5IHsKICAgIHNlZW4gPSBmcy5yZWFkRmlsZVN5bmMoIi53aGF0c25ldy1zZWVuIiwgInV0ZjgiKS50cmltKCk7CiAgfSBjYXRjaCB7fQogIGlmICghZm9yY2UgJiYgc2VlbiA9PT0gdmVyKSByZXR1cm47CiAgbGV0IHRleHQgPSAi
::B64:agent.js:IjsKICB0cnkgewogICAgdGV4dCA9IGZzLnJlYWRGaWxlU3luYygiY2hhbmdlbG9nLnR4dCIsICJ1dGY4IikudHJpbSgpOwogIH0gY2F0Y2gge30KICBpZiAoIXRleHQpIHRleHQgPSBCVUlMVElOX0NIQU5HRUxPRzsKICBjb25zb2xlLmxvZygiXG49PT09PT09PT09
::B64:agent.js:PT09PT09PT0gWUFORyBCQVJVID09PT09PT09PT09PT09PT09PSIpOwogIGNvbnNvbGUubG9nKHRleHQuc3BsaXQoL1xyP1xuLykuc2xpY2UoMCwgMzApLmpvaW4oIlxuIikpOwogIGNvbnNvbGUubG9nKCI9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09
::B64:agent.js:PT09PT09PT09PT09PSIpOwogIHRyeSB7CiAgICBmcy53cml0ZUZpbGVTeW5jKCIud2hhdHNuZXctc2VlbiIsIHZlcik7CiAgfSBjYXRjaCB7fQp9Cgpjb25zb2xlLmxvZyhgQWdlbnQgc2lhcC4gVmVyc2kgJHtsb2NhbFZlcnNpb24oKX0uIEZvbGRlciB1cGxvYWQ6
::B64:agent.js:ICR7U0FGRV9ESVJ9YCk7CmNvbnNvbGUubG9nKGBJemluIGFrc2k6ICR7eyBvbjogIk9UT01BVElTIChzZW11YSBsYW5nc3VuZyB5YSkiLCBhbWFuOiAiT1RPTUFUSVMga2VjdWFsaSBha3NpIG1lcnVzYWsiLCBvZmY6ICJTRUxBTFUgVEFOWUEiIH1bYXV0b01vZGVd
::B64:agent.js:fS4gVWJhaCBkZW5nYW4gL2F1dG8uIEN0cmwrQyB1bnR1ayBtZW5naGVudGlrYW4uYCk7CnNob3dXaGF0c05ldygpOwpjb25zb2xlLmxvZygnS2V0aWsgcGVyaW50YWggZGFsYW0gYmFoYXNhIGJpYXNhLiBLZXRpayAvYmFudHVhbiB1bnR1ayBkYWZ0YXIgZml0dXIs
::B64:agent.js:IC9sb2dpbiB1bnR1ayBsb2dpbiwgZXhpdCB1bnR1ayBrZWx1YXIuJyk7CmNoZWNrVXBkYXRlKCk7CndoaWxlICh0cnVlKSB7CiAgY29uc3QgY21kID0gYXdhaXQgcmwucXVlc3Rpb24oIlxuUGVyaW50YWg+ICIpOwogIGNvbnN0IGMgPSBjbWQudHJpbSgpOwogIGlm
::B64:agent.js:IChjID09PSAiZXhpdCIpIGJyZWFrOwogIGlmICghYykgY29udGludWU7CiAgaWYgKGMgPT09ICIvdGVzIikgewogICAgaWYgKCFmYWxsYmFja01vZGVscykgZmFsbGJhY2tNb2RlbHMgPSBhd2FpdCBkaXNjb3Zlck1vZGVscygpOwogICAgY29uc3QgbGlzdCA9IG1v
::B64:agent.js:ZGVsUG9vbCgpLnNsaWNlKDAsIDkpOwogICAgY29uc29sZS5sb2coYE1lbmd1amkgJHtsaXN0Lmxlbmd0aH0gbW9kZWwsIHRpYXAgbW9kZWwgbWFrc2ltYWwgNDUgZGV0aWsuLi5gKTsKICAgIGNvbnN0IHJlc3VsdHMgPSBhd2FpdCBQcm9taXNlLmFsbChsaXN0Lm1h
::B64:agent.js:cChhc3luYyAobSkgPT4gKHsgbSwgcjogYXdhaXQgdGVzdE1vZGVsKG0pIH0pKSk7IC8vIGRpdWppIGJlcnNhbWFhbgogICAgZm9yIChjb25zdCB7IG0sIHIgfSBvZiByZXN1bHRzKSBjb25zb2xlLmxvZyhgICAke3IubWFya30gJHttfSAgICR7ci5tc30gbXMgICAk
::B64:agent.js:e3IudGV4dH1gKTsKICAgIGNvbnN0IGJlc3QgPSByZXN1bHRzLmZpbHRlcigoeCkgPT4geC5yLm1hcmsgPT09ICJbT0tdIikuc29ydCgoeCwgeSkgPT4geC5yLm1zIC0geS5yLm1zKVswXT8ubSB8fCAiIjsKICAgIGlmICghYmVzdCkgewogICAgICBjb25zb2xlLmxv
::B64:agent.js:ZygiXG5UaWRhayBhZGEgbW9kZWwgeWFuZyBsb2xvcy4gQ2VrIGRhc2hib2FyZCA5Um91dGVyOiBwcm92aWRlciB0ZXJodWJ1bmcsIGt1b3RhLCBkYW4gbWVudSBDb25zb2xlIExvZy4iKTsKICAgIH0gZWxzZSBpZiAoYmVzdCA9PT0gYmFzZU1vZGVsKSB7CiAgICAg
::B64:agent.js:IGNvbnNvbGUubG9nKGBcbk1vZGVsIGFrdGlmICgke2Jhc2VNb2RlbH0pIHN1ZGFoIHlhbmcgdGVyY2VwYXQgZGFuIGJlcmZ1bmdzaS5gKTsKICAgIH0gZWxzZSB7CiAgICAgIGJhc2VNb2RlbCA9IGJlc3Q7CiAgICAgIHBvb2xJZHggPSAwOwogICAgICB0cnkgewog
::B64:agent.js:ICAgICAgIGZzLndyaXRlRmlsZVN5bmMoTU9ERUxfRklMRSwgYmVzdCk7CiAgICAgIH0gY2F0Y2gge30KICAgICAgY29uc29sZS5sb2coYFxuTW9kZWwgdGVyY2VwYXQgeWFuZyBiZXJmdW5nc2kgZGlwaWxpaCBvdG9tYXRpczogJHtiZXN0fSAodGVyc2ltcGFuLCBr
::B64:agent.js:ZXRpayAvbW9kZWwgcmVzZXQgdW50dWsga2VtYmFsaSBrZSBiYXdhYW4pLmApOwogICAgfQogICAgY29udGludWU7CiAgfQogIGlmIChjID09PSAiL21vZGVsIiB8fCBjLnN0YXJ0c1dpdGgoIi9tb2RlbCAiKSkgewogICAgY29uc3QgYXJnID0gYy5zbGljZSg2KS50
::B64:agent.js:cmltKCk7CiAgICBpZiAoIWFyZykgewogICAgICBpZiAoIWZhbGxiYWNrTW9kZWxzKSBmYWxsYmFja01vZGVscyA9IGF3YWl0IGRpc2NvdmVyTW9kZWxzKCk7CiAgICAgIGNvbnNvbGUubG9nKGBNb2RlbCBha3RpZjogJHtiYXNlTW9kZWx9XG5Nb2RlbCBsYWluIHlh
::B64:agent.js:bmcgdGVyc2VkaWE6ICR7bW9kZWxQb29sKCkuc2xpY2UoMSkuam9pbigiLCAiKSB8fCAiKHRpZGFrIGFkYSkifWApOwogICAgfSBlbHNlIGlmIChhcmcgPT09ICJyZXNldCIpIHsKICAgICAgdHJ5IHsKICAgICAgICBmcy51bmxpbmtTeW5jKE1PREVMX0ZJTEUpOwog
::B64:agent.js:ICAgICB9IGNhdGNoIHt9CiAgICAgIGJhc2VNb2RlbCA9IE1PREVMOwogICAgICBwb29sSWR4ID0gMDsKICAgICAgY29uc29sZS5sb2coYEtlbWJhbGkga2UgbW9kZWwgYmF3YWFuOiAke01PREVMfWApOwogICAgfSBlbHNlIHsKICAgICAgYmFzZU1vZGVsID0gYXJn
::B64:agent.js:OwogICAgICBwb29sSWR4ID0gMDsKICAgICAgdHJ5IHsKICAgICAgICBmcy53cml0ZUZpbGVTeW5jKE1PREVMX0ZJTEUsIGFyZyk7CiAgICAgIH0gY2F0Y2gge30KICAgICAgY29uc29sZS5sb2coYE1vZGVsIGRpZ2FudGkga2U6ICR7YXJnfWApOwogICAgfQogICAg
::B64:agent.js:Y29udGludWU7CiAgfQogIGlmIChjID09PSAiL2JhbnR1YW4iKSB7CiAgICBjb25zb2xlLmxvZyhIRUxQKTsKICAgIGNvbnRpbnVlOwogIH0KICBpZiAoYyA9PT0gIi9iYXJ1IikgewogICAgc2hvd1doYXRzTmV3KHRydWUpOwogICAgY29udGludWU7CiAgfQogIGlm
::B64:agent.js:IChjLnN0YXJ0c1dpdGgoIi9sb2dpbiIpKSB7CiAgICBsZXQgdGFyZ2V0ID0gYy5zcGxpdCgvXHMrLylbMV0gfHwgImh0dHBzOi8vYWNjb3VudHMuZ29vZ2xlLmNvbS9TZXJ2aWNlTG9naW4/c2VydmljZT15b3V0dWJlJmNvbnRpbnVlPWh0dHBzOi8vd3d3LnlvdXR1
::B64:agent.js:YmUuY29tLyI7CiAgICBpZiAoIS9eaHR0cHM/OlwvXC8vaS50ZXN0KHRhcmdldCkpIHRhcmdldCA9ICJodHRwczovLyIgKyB0YXJnZXQ7CiAgICB0cnkgewogICAgICBhd2FpdCBlbnN1cmVQYWdlKCk7CiAgICAgIGF3YWl0IHBhZ2UuYnJpbmdUb0Zyb250KCk7CiAg
::B64:agent.js:ICAgIGF3YWl0IHBhZ2UuZ290byh0YXJnZXQsIHsgd2FpdFVudGlsOiAiZG9tY29udGVudGxvYWRlZCIgfSk7CiAgICB9IGNhdGNoIChlKSB7CiAgICAgIGNvbnNvbGUubG9nKCJHYWdhbCBtZW1idWthIGhhbGFtYW4gbG9naW46IiwgZS5tZXNzYWdlKTsKICAgIH0K
::B64:agent.js:ICAgIGNvbnNvbGUubG9nKCJTaWxha2FuIGxvZ2luIGRpIGplbmRlbGEgYnJvd3NlciAoa2FtdSB5YW5nIG1lbmdldGlrLCBhZ2VudCB0aWRhayBtZWxpaGF0IHBhc3N3b3JkKS4iKTsKICAgIGF3YWl0IHJsLnF1ZXN0aW9uKCJTZXRlbGFoIHNlbGVzYWksIHRla2Fu
::B64:agent.js:IEVudGVyIGRpIHNpbmkuLi4gIik7CiAgICBjb25zb2xlLmxvZygiTG9naW4gdGVyc2ltcGFuIGRpIHByb2ZpbCBicm93c2VyLiBCZXJpa3V0bnlhIHRpZGFrIHBlcmx1IGxvZ2luIGxhZ2kuIik7CiAgICBjb250aW51ZTsKICB9CiAgaWYgKGMgPT09ICIvdmVyc2ki
::B64:agent.js:KSB7CiAgICBjb25zb2xlLmxvZyhgVmVyc2kgYWdlbnQ6ICR7bG9jYWxWZXJzaW9uKCl9YCk7CiAgICBhd2FpdCBjaGVja1VwZGF0ZSgpOwogICAgaWYgKCFwZW5kaW5nVmVyc2lvbikgY29uc29sZS5sb2coIlN1ZGFoIHZlcnNpIHRlcmJhcnUgKGF0YXUgdXBkYXRl
::B64:agent.js:IG9ubGluZSB0aWRhayBha3RpZikuIik7CiAgICBjb250aW51ZTsKICB9CiAgaWYgKGMgPT09ICIvdXBkYXRlIikgewogICAgY29uc29sZS5sb2coIk1lbXBlcmJhcnVpLi4uIGFnZW50IGFrYW4gbWVudXR1cCBkYW4gbWVueWFsYSBsYWdpIG90b21hdGlzIGxld2F0
::B64:agent.js:IHN0YXJ0LWFnZW50LmJhdC4iKTsKICAgIGF3YWl0IHNodXRkb3duQnJvd3NlcigpOwogICAgcmwuY2xvc2UoKTsKICAgIHByb2Nlc3MuZXhpdCg0Mik7IC8vIGtvZGUgNDIgPSBwZXJtaW50YWFuIHJlc3RhcnQgdW50dWsgdXBkYXRlOyBkaXRhbmdrYXAgb2xlaCBz
::B64:agent.js:dGFydC1hZ2VudC5iYXQKICB9CiAgaWYgKGMgPT09ICIvYXV0byIgfHwgYy5zdGFydHNXaXRoKCIvYXV0byAiKSkgewogICAgY29uc3QgYXJnID0gYy5zbGljZSg1KS50cmltKCkudG9Mb3dlckNhc2UoKTsKICAgIGNvbnN0IGFsaWFzID0geyB5YTogIm9uIiwgb3Rv
::B64:agent.js:bWF0aXM6ICJvbiIsIHRydWU6ICJvbiIsIHRhbnlhOiAib2ZmIiwgbWFudWFsOiAib2ZmIiwgbWF0aTogIm9mZiIgfTsKICAgIGNvbnN0IG1vZGUgPSBhbGlhc1thcmddIHx8IGFyZzsKICAgIGlmIChbIm9uIiwgImFtYW4iLCAib2ZmIl0uaW5jbHVkZXMobW9kZSkp
::B64:agent.js:IHsKICAgICAgYXV0b01vZGUgPSBtb2RlOwogICAgICB0cnkgewogICAgICAgIGZzLndyaXRlRmlsZVN5bmMoQVVUT19GSUxFLCBtb2RlKTsKICAgICAgfSBjYXRjaCB7fQogICAgfSBlbHNlIGlmIChhcmcpIHsKICAgICAgY29uc29sZS5sb2coIlBpbGloYW46IC9h
::B64:agent.js:dXRvIG9uLCAvYXV0byBhbWFuLCAvYXV0byBvZmYiKTsKICAgICAgY29udGludWU7CiAgICB9CiAgICBjb25zb2xlLmxvZygKICAgICAgYEl6aW4gYWtzaSBzZWthcmFuZzogJHt7IG9uOiAiT1RPTUFUSVMsIHNlbXVhIGxhbmdzdW5nIHlhIChrYW11IHRpZGFrIHBl
::B64:agent.js:cmx1IG1lbnVuZ2d1KSIsIGFtYW46ICJPVE9NQVRJUyBrZWN1YWxpIGFrc2kgbWVydXNhayAodGltcGEgZmlsZSwgaGFwdXMsIHR1dHVwIGplbmRlbGEsIHBpbmRhaCkgeWFuZyB0ZXRhcCBiZXJ0YW55YSIsIG9mZjogIlNFTEFMVSBUQU5ZQSB5L24iIH1bYXV0b01v
::B64:agent.js:ZGVdfWAKICAgICk7CiAgICBjb250aW51ZTsKICB9CiAgaWYgKGMgPT09ICIvZmFzdCIgfHwgYy5zdGFydHNXaXRoKCIvZmFzdCAiKSkgewogICAgY29uc3QgYXJnID0gYy5zbGljZSg1KS50cmltKCkudG9Mb3dlckNhc2UoKTsKICAgIGlmIChhcmcgPT09ICJvbiIp
::B64:agent.js:IEZBU1QgPSB0cnVlOwogICAgZWxzZSBpZiAoYXJnID09PSAib2ZmIikgRkFTVCA9IGZhbHNlOwogICAgY29uc29sZS5sb2coYEphbHVyIGNlcGF0ICh0YW5wYSBBSSB1bnR1ayBwZXJpbnRhaCB1bXVtKTogJHtGQVNUID8gIkFLVElGIiA6ICJNQVRJIn0uIEtldGlr
::B64:agent.js:IC9mYXN0IG9uIGF0YXUgL2Zhc3Qgb2ZmLmApOwogICAgY29udGludWU7CiAgfQogIGlmIChjID09PSAiL3Jlc2V0IikgewogICAgaGlzdG9yeS5sZW5ndGggPSAwOwogICAgZXh0cmFHcm91cHMuY2xlYXIoKTsKICAgIGNvbnNvbGUubG9nKCJQZXJjYWthcGFuIGRp
::B64:agent.js:bHVwYWthbi4iKTsKICAgIGNvbnRpbnVlOwogIH0KICBjb25zdCB0MCA9IERhdGUubm93KCk7CiAgY29uc3QgZGV0aWsgPSAoKSA9PiAoKERhdGUubm93KCkgLSB0MCkgLyAxMDAwKS50b0ZpeGVkKDEpOwogIGlmIChGQVNUKSB7CiAgICBsZXQgciA9IG51bGw7CiAg
::B64:agent.js:ICB0cnkgewogICAgICByID0gYXdhaXQgdHJ5RmFzdENvbW1hbmQoYyk7CiAgICB9IGNhdGNoIChlKSB7CiAgICAgIGNvbnNvbGUubG9nKGAgIChqYWx1ciBjZXBhdCBnYWdhbDogJHtTdHJpbmcoZS5tZXNzYWdlKS5zbGljZSgwLCAxNjApfS4gRGlzZXJhaGthbiBr
::B64:agent.js:ZSBBSS4uLilgKTsKICAgIH0KICAgIGlmIChyICE9IG51bGwpIHsKICAgICAgY29uc29sZS5sb2coYFxuW2NlcGF0XSAke3J9XG4oJHtkZXRpaygpfSBkdGssIHRhbnBhIEFJKWApOwogICAgICBoaXN0b3J5LnB1c2goeyByb2xlOiAidXNlciIsIGNvbnRlbnQ6IGMg
::B64:agent.js:fSwgeyByb2xlOiAiYXNzaXN0YW50IiwgY29udGVudDogYFtqYWx1ciBjZXBhdF0gJHtTdHJpbmcocikuc2xpY2UoMCwgNTAwKX1gIH0pOwogICAgICB0cmltSGlzdG9yeSgpOwogICAgICBjb250aW51ZTsKICAgIH0KICB9CiAgdHJ5IHsKICAgIGF3YWl0IHJ1blRh
::B64:agent.js:c2soYyk7CiAgICBjb25zb2xlLmxvZyhgKHNlbGVzYWkgZGFsYW0gJHtkZXRpaygpfSBkdGspYCk7CiAgfSBjYXRjaCAoZSkgewogICAgY29uc29sZS5lcnJvcigiR2FnYWw6IiwgZS5tZXNzYWdlKTsKICB9Cn0KYXdhaXQgc2h1dGRvd25Ccm93c2VyKCk7CnJsLmNs
::B64:agent.js:b3NlKCk7Cg==
::B64:package.json:ewogICJuYW1lIjogImJvdC1hZ2VudCIsCiAgInZlcnNpb24iOiAiMS4wLjAiLAogICJ0eXBlIjogIm1vZHVsZSIsCiAgInNjcmlwdHMiOiB7CiAgICAic3RhcnQiOiAibm9kZSBhZ2VudC5qcyIKICB9LAogICJkZXBlbmRlbmNpZXMiOiB7CiAgICAicGxheXdyaWdo
::B64:package.json:dCI6ICJeMS40OC4wIgogIH0KfQo=
