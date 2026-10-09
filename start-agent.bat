@echo off
setlocal EnableExtensions
chcp 65001 >nul
title Agent Automation
set "SELF=%~f0"
set "EMBED_VER=10"

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
::B64:agent.js:aW5kYWhrYW4ga2UgUmVjeWNsZXxUdXR1cCBqZW5kZWxhfFBpbmRhaGthbjp8RWtzdHJhaykvaTsKY29uc3QgTUFYX1NURVBTID0gMzA7CmNvbnN0IEhPTUUgPSBvcy5ob21lZGlyKCk7CmNvbnN0IFNFQVJDSF9ST09UUyA9IFtIT01FLCAuLi4ocHJvY2Vzcy5lbnYu
::B64:agent.js:U0VBUkNIX1JPT1RTID8gcHJvY2Vzcy5lbnYuU0VBUkNIX1JPT1RTLnNwbGl0KCI7IikgOiBbXSldOwpmb3IgKGNvbnN0IEwgb2YgIkRFRkdISUpLTE1OT1BRUlNUVVZXWFlaIikgewogIC8vIERyaXZlIGxhaW4gKEQ6LCBFOiwgZmxhc2hkaXNrLCBkbGwpIGlrdXQg
::B64:agent.js:ZGljYXJpIG90b21hdGlzCiAgdHJ5IHsKICAgIGlmIChmcy5leGlzdHNTeW5jKGAke0x9OlxcYCkpIFNFQVJDSF9ST09UUy5wdXNoKGAke0x9OlxcYCk7CiAgfSBjYXRjaCB7fQp9CgppZiAoIUFQSV9LRVkpIHsKICBjb25zb2xlLmVycm9yKCJST1VURVJfS0VZIGJl
::B64:agent.js:bHVtIGRpaXNpLiIpOwogIHByb2Nlc3MuZXhpdCgxKTsKfQpmcy5ta2RpclN5bmMoU0FGRV9ESVIsIHsgcmVjdXJzaXZlOiB0cnVlIH0pOwoKY29uc3QgcmwgPSByZWFkbGluZS5jcmVhdGVJbnRlcmZhY2UoeyBpbnB1dDogcHJvY2Vzcy5zdGRpbiwgb3V0cHV0OiBw
::B64:agent.js:cm9jZXNzLnN0ZG91dCB9KTsKY29uc3Qgc2xlZXAgPSAobXMpID0+IG5ldyBQcm9taXNlKChyKSA9PiBzZXRUaW1lb3V0KHIsIG1zKSk7CgovLyA9PT09PSBQZW1iZXJpdGFodWFuIHVwZGF0ZSAoVVJMIGRpYmVyaWthbiBvdG9tYXRpcyBvbGVoIHN0YXJ0LWFnZW50
::B64:agent.js:LmJhdCkgPT09PT0KY29uc3QgVVBEX1VSTCA9IHByb2Nlc3MuZW52LlVQRF9VUkwgfHwgIiI7CmNvbnN0IGxvY2FsVmVyc2lvbiA9ICgpID0+IHsKICB0cnkgewogICAgcmV0dXJuIGZzLnJlYWRGaWxlU3luYygidmVyc2lvbi50eHQiLCAidXRmOCIpLnRyaW0oKSB8
::B64:agent.js:fCAiMCI7CiAgfSBjYXRjaCB7CiAgICByZXR1cm4gIjAiOwogIH0KfTsKbGV0IHBlbmRpbmdWZXJzaW9uID0gIiI7Cgphc3luYyBmdW5jdGlvbiBjaGVja1VwZGF0ZSgpIHsKICBpZiAoIVVQRF9VUkwgfHwgcHJvY2Vzcy5lbnYuQVVUT19VUERBVEUgPT09ICIwIikg
::B64:agent.js:cmV0dXJuOwogIHRyeSB7CiAgICBjb25zdCByZXMgPSBhd2FpdCBmZXRjaChgJHtVUERfVVJMfS92ZXJzaW9uLnR4dGAsIHsgc2lnbmFsOiBBYm9ydFNpZ25hbC50aW1lb3V0KDEwMDAwKSB9KTsKICAgIGlmICghcmVzLm9rKSByZXR1cm47CiAgICBjb25zdCByZW1v
::B64:agent.js:dGUgPSAoYXdhaXQgcmVzLnRleHQoKSkudHJpbSgpOwogICAgaWYgKHJlbW90ZSAmJiByZW1vdGUgIT09IGxvY2FsVmVyc2lvbigpICYmIHJlbW90ZSAhPT0gcGVuZGluZ1ZlcnNpb24pIHsKICAgICAgcGVuZGluZ1ZlcnNpb24gPSByZW1vdGU7CiAgICAgIGNvbnNv
::B64:agent.js:bGUubG9nKGBcbioqKiBVUERBVEUgVEVSU0VESUE6IHZlcnNpICR7cmVtb3RlfSAodmVyc2kga2FtdTogJHtsb2NhbFZlcnNpb24oKX0pICoqKmApOwogICAgICBjb25zb2xlLmxvZygnICAgIEtldGlrICIvdXBkYXRlIiB1bnR1ayBtZW1wZXJiYXJ1aSBvdG9tYXRp
::B64:agent.js:cyBzZWthcmFuZy4nKTsKICAgIH0KICB9IGNhdGNoIHt9Cn0Kc2V0SW50ZXJ2YWwoY2hlY2tVcGRhdGUsIDE1ICogNjAgKiAxMDAwKS51bnJlZigpOwoKLy8gPT09PT0gQnJvd3NlcjogcGFrYWkgQ2hyb21lL0VkZ2UgQVNMSSAoYnVrYW4gQ2hyb21pdW0gYmF3YWFu
::B64:agent.js:IFBsYXl3cmlnaHQpID09PT09Ci8vIEFsYXNhbjogdmlkZW8gWW91VHViZSBidXR1aCBjb2RlYyBsZW5na2FwLCBkYW4gR29vZ2xlIG1lbWJsb2tpciBsb2dpbiBkaSBicm93c2VyICJvdG9tYXRpcyIuCi8vIENocm9tZSBkaWphbGFua2FuIGJpYXNhIGRlbmdhbiBw
::B64:agent.js:b3J0IGRlYnVnLCBsYWx1IFBsYXl3cmlnaHQgbWVueWFtYnVuZyBrZSBzaXR1LgovLyBMb2dpbiB0ZXJzaW1wYW4gcGVybWFuZW4gZGkgZm9sZGVyIC4vY2hyb21lLXByb2ZpbGUuCmNvbnN0IERFQlVHX1BPUlQgPSBOdW1iZXIocHJvY2Vzcy5lbnYuREVCVUdfUE9S
::B64:agent.js:VCB8fCA5MjIyKTsKY29uc3QgUFJPRklMRV9ESVIgPSBwYXRoLnJlc29sdmUoIi4vY2hyb21lLXByb2ZpbGUiKTsKCmZ1bmN0aW9uIGZpbmRCcm93c2VyRXhlKCkgewogIGNvbnN0IGxvY2FsID0gcHJvY2Vzcy5lbnYuTE9DQUxBUFBEQVRBIHx8ICIiOwogIGNvbnN0
::B64:agent.js:IHBmID0gcHJvY2Vzcy5lbnYuUHJvZ3JhbUZpbGVzIHx8ICJDOlxcUHJvZ3JhbSBGaWxlcyI7CiAgY29uc3QgcGY4NiA9IHByb2Nlc3MuZW52WyJQcm9ncmFtRmlsZXMoeDg2KSJdIHx8ICJDOlxcUHJvZ3JhbSBGaWxlcyAoeDg2KSI7CiAgcmV0dXJuIFsKICAgIHBy
::B64:agent.js:b2Nlc3MuZW52LkNIUk9NRV9QQVRILAogICAgcGF0aC5qb2luKHBmLCAiR29vZ2xlIiwgIkNocm9tZSIsICJBcHBsaWNhdGlvbiIsICJjaHJvbWUuZXhlIiksCiAgICBwYXRoLmpvaW4ocGY4NiwgIkdvb2dsZSIsICJDaHJvbWUiLCAiQXBwbGljYXRpb24iLCAiY2hy
::B64:agent.js:b21lLmV4ZSIpLAogICAgcGF0aC5qb2luKGxvY2FsLCAiR29vZ2xlIiwgIkNocm9tZSIsICJBcHBsaWNhdGlvbiIsICJjaHJvbWUuZXhlIiksCiAgICBwYXRoLmpvaW4ocGY4NiwgIk1pY3Jvc29mdCIsICJFZGdlIiwgIkFwcGxpY2F0aW9uIiwgIm1zZWRnZS5leGUi
::B64:agent.js:KSwKICAgIHBhdGguam9pbihwZiwgIk1pY3Jvc29mdCIsICJFZGdlIiwgIkFwcGxpY2F0aW9uIiwgIm1zZWRnZS5leGUiKSwKICBdCiAgICAuZmlsdGVyKEJvb2xlYW4pCiAgICAuZmluZCgoeCkgPT4gZnMuZXhpc3RzU3luYyh4KSk7Cn0KCmFzeW5jIGZ1bmN0aW9u
::B64:agent.js:IGRlYnVnUG9ydFVwKCkgewogIHRyeSB7CiAgICBjb25zdCByID0gYXdhaXQgZmV0Y2goYGh0dHA6Ly8xMjcuMC4wLjE6JHtERUJVR19QT1JUfS9qc29uL3ZlcnNpb25gLCB7IHNpZ25hbDogQWJvcnRTaWduYWwudGltZW91dCgxNTAwKSB9KTsKICAgIHJldHVybiBy
::B64:agent.js:Lm9rOwogIH0gY2F0Y2ggewogICAgcmV0dXJuIGZhbHNlOwogIH0KfQoKbGV0IGJyb3dzZXJIYW5kbGUgPSBudWxsOwphc3luYyBmdW5jdGlvbiBvcGVuQnJvd3NlcigpIHsKICBjb25zdCBleGUgPSBmaW5kQnJvd3NlckV4ZSgpOwogIGlmIChleGUpIHsKICAgIGlm
::B64:agent.js:ICghKGF3YWl0IGRlYnVnUG9ydFVwKCkpKSB7CiAgICAgIHNwYXduKAogICAgICAgIGV4ZSwKICAgICAgICBbCiAgICAgICAgICBgLS1yZW1vdGUtZGVidWdnaW5nLXBvcnQ9JHtERUJVR19QT1JUfWAsCiAgICAgICAgICBgLS11c2VyLWRhdGEtZGlyPSR7UFJPRklM
::B64:agent.js:RV9ESVJ9YCwKICAgICAgICAgICItLW5vLWZpcnN0LXJ1biIsCiAgICAgICAgICAiLS1uby1kZWZhdWx0LWJyb3dzZXItY2hlY2siLAogICAgICAgICAgIi0tYXV0b3BsYXktcG9saWN5PW5vLXVzZXItZ2VzdHVyZS1yZXF1aXJlZCIsCiAgICAgICAgICAiYWJvdXQ6
::B64:agent.js:YmxhbmsiLAogICAgICAgIF0sCiAgICAgICAgeyBkZXRhY2hlZDogdHJ1ZSwgc3RkaW86ICJpZ25vcmUiIH0KICAgICAgKS51bnJlZigpOwogICAgICBmb3IgKGxldCBpID0gMDsgaSA8IDMwICYmICEoYXdhaXQgZGVidWdQb3J0VXAoKSk7IGkrKykgYXdhaXQgc2xl
::B64:agent.js:ZXAoNTAwKTsKICAgIH0KICAgIGlmIChhd2FpdCBkZWJ1Z1BvcnRVcCgpKSB7CiAgICAgIGJyb3dzZXJIYW5kbGUgPSBhd2FpdCBjaHJvbWl1bS5jb25uZWN0T3ZlckNEUChgaHR0cDovLzEyNy4wLjAuMToke0RFQlVHX1BPUlR9YCk7CiAgICAgIGNvbnNvbGUubG9n
::B64:agent.js:KGBCcm93c2VyOiAke3BhdGguYmFzZW5hbWUoZXhlKX0gKGxvZ2luIHRlcnNpbXBhbiBkaSAke1BST0ZJTEVfRElSfSlgKTsKICAgICAgcmV0dXJuIGJyb3dzZXJIYW5kbGUuY29udGV4dHMoKVswXSB8fCAoYXdhaXQgYnJvd3NlckhhbmRsZS5uZXdDb250ZXh0KCkp
::B64:agent.js:OwogICAgfQogIH0KICBjb25zb2xlLmxvZygiQ2hyb21lL0VkZ2UgdGlkYWsgZGl0ZW11a2FuLCBtZW1ha2FpIENocm9taXVtIGJhd2FhbiAodmlkZW8gZGFuIGxvZ2luIEdvb2dsZSBtdW5na2luIGJlcm1hc2FsYWgpLiIpOwogIHJldHVybiBjaHJvbWl1bS5sYXVu
::B64:agent.js:Y2hQZXJzaXN0ZW50Q29udGV4dCgiLi9icm93c2VyLXByb2ZpbGUiLCB7CiAgICBoZWFkbGVzczogZmFsc2UsCiAgICBhcmdzOiBbIi0tYXV0b3BsYXktcG9saWN5PW5vLXVzZXItZ2VzdHVyZS1yZXF1aXJlZCJdLAogICAgaWdub3JlRGVmYXVsdEFyZ3M6IFsiLS1l
::B64:agent.js:bmFibGUtYXV0b21hdGlvbiJdLAogIH0pOwp9Cgpjb25zdCBjb250ZXh0ID0gYXdhaXQgb3BlbkJyb3dzZXIoKTsKbGV0IHBhZ2UgPSBjb250ZXh0LnBhZ2VzKCkuZmluZCgoeCkgPT4gIXguaXNDbG9zZWQoKSkgfHwgKGF3YWl0IGNvbnRleHQubmV3UGFnZSgpKTsK
::B64:agent.js:CmFzeW5jIGZ1bmN0aW9uIGVuc3VyZVBhZ2UoKSB7CiAgaWYgKCFwYWdlLmlzQ2xvc2VkKCkpIHJldHVybjsKICBwYWdlID0gY29udGV4dC5wYWdlcygpLmZpbmQoKHgpID0+ICF4LmlzQ2xvc2VkKCkpIHx8IChhd2FpdCBjb250ZXh0Lm5ld1BhZ2UoKSk7Cn0KCmFz
::B64:agent.js:eW5jIGZ1bmN0aW9uIHNodXRkb3duQnJvd3NlcigpIHsKICAvLyBDaHJvbWUgc2VuZ2FqYSBkaWJpYXJrYW4gdGVyYnVrYSBhZ2FyIGxvZ2luIGRhbiB0YWIgdGV0YXAgYWRhCiAgdHJ5IHsKICAgIGlmIChicm93c2VySGFuZGxlKSBhd2FpdCBicm93c2VySGFuZGxl
::B64:agent.js:LmNsb3NlKCk7CiAgICBlbHNlIGF3YWl0IGNvbnRleHQuY2xvc2UoKTsKICB9IGNhdGNoIHt9Cn0KCi8vIE5hbWEgZmlsZSByZWxhdGlmIGRpY2FyaSBkaSBTQUZFX0RJUjsgcGF0aCBsZW5na2FwIGRpIGxva2FzaSBtYW5hIHB1biBib2xlaC4KLy8gUGVuZ2FtYW5u
::B64:agent.js:eWEgYWRhbGFoIGl6aW4geS9uIHNlYmVsdW0gc2V0aWFwIHVwbG9hZC4KZnVuY3Rpb24gc2FmZVBhdGgobmFtZSkgewogIGNvbnN0IGZ1bGwgPSBwYXRoLnJlc29sdmUoU0FGRV9ESVIsIFN0cmluZyhuYW1lKS5yZXBsYWNlKC9eInwiJC9nLCAiIikpOwogIGlmICgh
::B64:agent.js:ZnMuZXhpc3RzU3luYyhmdWxsKSB8fCAhZnMuc3RhdFN5bmMoZnVsbCkuaXNGaWxlKCkpIHsKICAgIHRocm93IG5ldyBFcnJvcigiRmlsZSB0aWRhayBkaXRlbXVrYW46ICIgKyBmdWxsKTsKICB9CiAgcmV0dXJuIGZ1bGw7Cn0KCmFzeW5jIGZ1bmN0aW9uIGFzayht
::B64:agent.js:c2cpIHsKICBjb25zdCBmaXJzdCA9IFN0cmluZyhtc2cpLnNwbGl0KCJcbiIpWzBdOwogIGlmIChhdXRvTW9kZSA9PT0gIm9uIiB8fCAoYXV0b01vZGUgPT09ICJhbWFuIiAmJiAhUklTS1lfQVNLLnRlc3QoZmlyc3QpKSkgewogICAgY29uc29sZS5sb2coYCAgW2l6
::B64:agent.js:aW4gb3RvbWF0aXM6IHlhXSAke2ZpcnN0LnNsaWNlKDAsIDE0MCl9YCk7CiAgICByZXR1cm4gdHJ1ZTsKICB9CiAgY29uc3QgYSA9IGF3YWl0IHJsLnF1ZXN0aW9uKGBcbltJWklOXSAke21zZ30gKHkvbik6IGApOwogIHJldHVybiBhLnRyaW0oKS50b0xvd2VyQ2Fz
::B64:agent.js:ZSgpID09PSAieSI7Cn0KCi8vID09PT09IEhlbHBlciBQb3dlclNoZWxsIChrb250cm9sIGRlc2t0b3AgV2luZG93cyB0YW5wYSBsaWJyYXJ5IHRhbWJhaGFuKSA9PT09PQpmdW5jdGlvbiBwcyhzY3JpcHQsIGVudiA9IHt9LCB0aW1lb3V0ID0gMzAwMDApIHsKICBj
::B64:agent.js:b25zdCBlbmNvZGVkID0gQnVmZmVyLmZyb20oc2NyaXB0LCAidXRmMTZsZSIpLnRvU3RyaW5nKCJiYXNlNjQiKTsKICByZXR1cm4gbmV3IFByb21pc2UoKHJlc29sdmUsIHJlamVjdCkgPT4gewogICAgZXhlY0ZpbGUoCiAgICAgICJwb3dlcnNoZWxsIiwKICAgICAg
::B64:agent.js:WyItTm9Qcm9maWxlIiwgIi1Ob25JbnRlcmFjdGl2ZSIsICItRW5jb2RlZENvbW1hbmQiLCBlbmNvZGVkXSwKICAgICAgeyBlbnY6IHsgLi4ucHJvY2Vzcy5lbnYsIC4uLmVudiB9LCB0aW1lb3V0LCBtYXhCdWZmZXI6IDIwICogMTAyNCAqIDEwMjQgfSwKICAgICAg
::B64:agent.js:KGVyciwgc3Rkb3V0LCBzdGRlcnIpID0+CiAgICAgICAgZXJyID8gcmVqZWN0KG5ldyBFcnJvcigoc3RkZXJyIHx8IGVyci5tZXNzYWdlKS5zbGljZSgwLCAzMDApKSkgOiByZXNvbHZlKHN0ZG91dC50cmltKCkpCiAgICApOwogIH0pOwp9Cgpjb25zdCBQU19IRUFE
::B64:agent.js:ID0gYApBZGQtVHlwZSBAIgp1c2luZyBTeXN0ZW07CnVzaW5nIFN5c3RlbS5SdW50aW1lLkludGVyb3BTZXJ2aWNlczsKcHVibGljIGNsYXNzIFcgewogIFtEbGxJbXBvcnQoInVzZXIzMi5kbGwiKV0gcHVibGljIHN0YXRpYyBleHRlcm4gYm9vbCBTZXRQcm9jZXNz
::B64:agent.js:RFBJQXdhcmUoKTsKICBbRGxsSW1wb3J0KCJ1c2VyMzIuZGxsIildIHB1YmxpYyBzdGF0aWMgZXh0ZXJuIGJvb2wgU2V0Q3Vyc29yUG9zKGludCB4LCBpbnQgeSk7CiAgW0RsbEltcG9ydCgidXNlcjMyLmRsbCIpXSBwdWJsaWMgc3RhdGljIGV4dGVybiB2b2lkIG1v
::B64:agent.js:dXNlX2V2ZW50KHVpbnQgZiwgdWludCBkeCwgdWludCBkeSwgaW50IGQsIFVJbnRQdHIgZSk7Cn0KIkAKW1ddOjpTZXRQcm9jZXNzRFBJQXdhcmUoKSB8IE91dC1OdWxsCkFkZC1UeXBlIC1Bc3NlbWJseU5hbWUgU3lzdGVtLldpbmRvd3MuRm9ybXMsU3lzdGVtLkRy
::B64:agent.js:YXdpbmcKYDsKCmxldCBzY2FsZSA9IDE7IC8vIHJhc2lvIGxheWFyIGFzbGkgLyBzY3JlZW5zaG90CmNvbnN0IHBlbmRpbmdJbWFnZXMgPSBbXTsgLy8gZ2FtYmFyIHlhbmcgZGlraXJpbSBrZSBtb2RlbCBzZXRlbGFoIHRvb2wgZGlqYWxhbmthbgoKY29uc3QgU0tJ
::B64:agent.js:UF9ESVJTID0gbmV3IFNldChbCiAgIm5vZGVfbW9kdWxlcyIsICJhcHBkYXRhIiwgIi5naXQiLCAid2luZG93cyIsICJwcm9ncmFtIGZpbGVzIiwgInByb2dyYW0gZmlsZXMgKHg4NikiLAogICJwcm9ncmFtZGF0YSIsICIkcmVjeWNsZS5iaW4iLCAic3lzdGVtIHZv
::B64:agent.js:bHVtZSBpbmZvcm1hdGlvbiIsCl0pOwpsZXQgc2VhcmNoRGVhZGxpbmUgPSAwOwoKLy8gQ2FyaSBmb2xkZXIgKHdhbnRGaWxlcz1mYWxzZSkgYXRhdSBmaWxlICh3YW50RmlsZXM9dHJ1ZSkgYmVyZGFzYXJrYW4gc2ViYWdpYW4gbmFtYQpmdW5jdGlvbiBmaW5kUGF0
::B64:agent.js:aHMobmFtZSwgcm9vdCwgZGVwdGgsIG91dCwgd2FudEZpbGVzKSB7CiAgaWYgKGRlcHRoIDwgMCB8fCBvdXQubGVuZ3RoID49IDEyIHx8IERhdGUubm93KCkgPiBzZWFyY2hEZWFkbGluZSkgcmV0dXJuOwogIGxldCBlbnRyaWVzOwogIHRyeSB7CiAgICBlbnRyaWVz
::B64:agent.js:ID0gZnMucmVhZGRpclN5bmMocm9vdCwgeyB3aXRoRmlsZVR5cGVzOiB0cnVlIH0pOwogIH0gY2F0Y2ggewogICAgcmV0dXJuOwogIH0KICBjb25zdCBxID0gbmFtZS50b0xvd2VyQ2FzZSgpOwogIGZvciAoY29uc3QgZSBvZiBlbnRyaWVzKSB7CiAgICBjb25zdCBm
::B64:agent.js:dWxsID0gcGF0aC5qb2luKHJvb3QsIGUubmFtZSk7CiAgICBpZiAoZS5pc0RpcmVjdG9yeSgpKSB7CiAgICAgIGlmIChTS0lQX0RJUlMuaGFzKGUubmFtZS50b0xvd2VyQ2FzZSgpKSB8fCBlLm5hbWUuc3RhcnRzV2l0aCgiJCIpKSBjb250aW51ZTsKICAgICAgaWYg
::B64:agent.js:KCF3YW50RmlsZXMgJiYgZS5uYW1lLnRvTG93ZXJDYXNlKCkuaW5jbHVkZXMocSkpIG91dC5wdXNoKGZ1bGwpOwogICAgICBmaW5kUGF0aHMobmFtZSwgZnVsbCwgZGVwdGggLSAxLCBvdXQsIHdhbnRGaWxlcyk7CiAgICB9IGVsc2UgaWYgKHdhbnRGaWxlcyAmJiBl
::B64:agent.js:LmlzRmlsZSgpICYmIGUubmFtZS50b0xvd2VyQ2FzZSgpLmluY2x1ZGVzKHEpKSB7CiAgICAgIG91dC5wdXNoKGZ1bGwpOwogICAgfQogIH0KfQoKZnVuY3Rpb24gc2VhcmNoRXZlcnl3aGVyZShuYW1lLCB3YW50RmlsZXMpIHsKICBjb25zdCBvdXQgPSBbXTsKICBz
::B64:agent.js:ZWFyY2hEZWFkbGluZSA9IERhdGUubm93KCkgKyAxMjAwMDsgLy8gbWFrc2ltYWwgMTIgZGV0aWsgYWdhciB0aWRhayBtZW5nZ2FudHVuZwogIGZvciAoY29uc3Qgcm9vdCBvZiBTRUFSQ0hfUk9PVFMpIGZpbmRQYXRocyhTdHJpbmcobmFtZSksIHJvb3QsIHJvb3Qg
::B64:agent.js:PT09IEhPTUUgPyA1IDogMywgb3V0LCB3YW50RmlsZXMpOwogIHJldHVybiBvdXQubGVuZ3RoID8gb3V0LmpvaW4oIlxuIikgOiAiVGlkYWsgZGl0ZW11a2FuIjsKfQoKLy8gPT09PT0gIlRhbmdhbiIgYWdlbnQgPT09PT0KLy8gPT09PT0gSGVscGVyIHRhYiBicm93
::B64:agent.js:c2VyID09PT09CmNvbnN0IGZpeFVybCA9ICh1KSA9PiAoL15bYS16XVthLXowLTkrLi1dKjpcL1wvL2kudGVzdChTdHJpbmcodSkpID8gU3RyaW5nKHUpIDogImh0dHBzOi8vIiArIFN0cmluZyh1KSk7CmNvbnN0IGlzVHJ1ZSA9ICh2KSA9PiB2ID09PSB0cnVlIHx8
::B64:agent.js:IHYgPT09ICJ0cnVlIjsKY29uc3QgbGl2ZVBhZ2VzID0gKCkgPT4gY29udGV4dC5wYWdlcygpLmZpbHRlcigoeCkgPT4gIXguaXNDbG9zZWQoKSk7Cgphc3luYyBmdW5jdGlvbiB0YWJzU3VtbWFyeSgpIHsKICBjb25zdCBhbGwgPSBsaXZlUGFnZXMoKTsKICBjb25z
::B64:agent.js:dCBsaW5lcyA9IFtdOwogIGZvciAobGV0IGkgPSAwOyBpIDwgYWxsLmxlbmd0aDsgaSsrKSB7CiAgICBsZXQgdGl0bGUgPSAiIjsKICAgIHRyeSB7CiAgICAgIHRpdGxlID0gYXdhaXQgYWxsW2ldLnRpdGxlKCk7CiAgICB9IGNhdGNoIHt9CiAgICBsaW5lcy5wdXNo
::B64:agent.js:KGAke2kgKyAxfSR7YWxsW2ldID09PSBwYWdlID8gIioiIDogIiAifSAke3RpdGxlLnNsaWNlKDAsIDYwKX0gfCAke2FsbFtpXS51cmwoKS5zbGljZSgwLCAxMDApfWApOwogIH0KICByZXR1cm4gKGxpbmVzLmpvaW4oIlxuIikgfHwgIih0aWRhayBhZGEgdGFiKSIp
::B64:agent.js:ICsgIlxuKCogPSB0YWIgYWt0aWYgeWFuZyBkaXBha2FpIGFnZW50KSI7Cn0KCmZ1bmN0aW9uIHBpY2tUYWIoYWxsLCBpbmRleCkgewogIGNvbnN0IG4gPSBOdW1iZXIoaW5kZXgpOwogIGlmICghTnVtYmVyLmlzRmluaXRlKG4pIHx8IG4gPT09IDApIHJldHVybiB1
::B64:agent.js:bmRlZmluZWQ7CiAgcmV0dXJuIG4gPCAwID8gYWxsLmF0KG4pIDogYWxsW24gLSAxXTsKfQoKLy8gPT09PT0gSGVscGVyIFlvdVR1YmUgPT09PT0KYXN5bmMgZnVuY3Rpb24gc2tpcEFkcygpIHsKICBmb3IgKGxldCBpID0gMDsgaSA8IDEwOyBpKyspIHsKICAgIGNv
::B64:agent.js:bnN0IGJ0biA9IGF3YWl0IHBhZ2UuJCgiLnl0cC1za2lwLWFkLWJ1dHRvbiwgLnl0cC1hZC1za2lwLWJ1dHRvbiwgLnl0cC1hZC1za2lwLWJ1dHRvbi1tb2Rlcm4iKTsKICAgIGlmIChidG4pIHsKICAgICAgYXdhaXQgYnRuLmNsaWNrKCkuY2F0Y2goKCkgPT4ge30p
::B64:agent.js:OwogICAgICByZXR1cm47CiAgICB9CiAgICBpZiAoIShhd2FpdCBwYWdlLiQoIi5hZC1zaG93aW5nIikpKSByZXR1cm47CiAgICBhd2FpdCBzbGVlcCgxMDAwKTsKICB9Cn0KCmFzeW5jIGZ1bmN0aW9uIHJlYWRQbGF5ZXJTdGF0ZSgpIHsKICByZXR1cm4gcGFnZS5l
::B64:agent.js:dmFsdWF0ZSgoKSA9PiB7CiAgICBjb25zdCB2ID0gZG9jdW1lbnQucXVlcnlTZWxlY3RvcigidmlkZW8iKTsKICAgIGNvbnN0IGVyciA9ICEhZG9jdW1lbnQucXVlcnlTZWxlY3RvcigiLnl0cC1lcnJvciIpOwogICAgaWYgKHYgJiYgdi5wYXVzZWQgJiYgIWVycikg
::B64:agent.js:di5wbGF5KCkuY2F0Y2goKCkgPT4ge30pOwogICAgcmV0dXJuIHsgZXJyLCBwbGF5aW5nOiAhIXYgJiYgIXYucGF1c2VkICYmIHYucmVhZHlTdGF0ZSA+IDIgfTsKICB9KTsKfQoKYXN5bmMgZnVuY3Rpb24gZW5zdXJlUGxheWluZygpIHsKICBmb3IgKGxldCBhdHRl
::B64:agent.js:bXB0ID0gMDsgYXR0ZW1wdCA8IDI7IGF0dGVtcHQrKykgewogICAgYXdhaXQgc2xlZXAoMTgwMCk7CiAgICBhd2FpdCBza2lwQWRzKCk7CiAgICBhd2FpdCByZWFkUGxheWVyU3RhdGUoKTsgLy8gbWVtaWN1IHBsYXkoKQogICAgYXdhaXQgc2xlZXAoNzAwKTsKICAg
::B64:agent.js:IGNvbnN0IHN0ID0gYXdhaXQgcmVhZFBsYXllclN0YXRlKCk7CiAgICBpZiAoc3QucGxheWluZykgcmV0dXJuIHRydWU7CiAgICBpZiAoc3QuZXJyKSBhd2FpdCBwYWdlLnJlbG9hZCh7IHdhaXRVbnRpbDogImRvbWNvbnRlbnRsb2FkZWQiIH0pOwogIH0KICByZXR1
::B64:agent.js:cm4gZmFsc2U7Cn0KCi8vID09PT09IFBlbmNhcmlhbiBZb3VUdWJlIGNlcGF0ICh0YW5wYSBtZW11YXQgaGFsYW1hbiBoYXNpbCBkaSBicm93c2VyKSA9PT09PQphc3luYyBmdW5jdGlvbiB5dFNlYXJjaEZhc3QocXVlcnkpIHsKICBjb25zdCByZXMgPSBhd2FpdCBm
::B64:agent.js:ZXRjaCgiaHR0cHM6Ly93d3cueW91dHViZS5jb20vcmVzdWx0cz9obD1pZCZzZWFyY2hfcXVlcnk9IiArIGVuY29kZVVSSUNvbXBvbmVudChxdWVyeSksIHsKICAgIGhlYWRlcnM6IHsKICAgICAgIlVzZXItQWdlbnQiOiAiTW96aWxsYS81LjAgKFdpbmRvd3MgTlQg
::B64:agent.js:MTAuMDsgV2luNjQ7IHg2NCkgQXBwbGVXZWJLaXQvNTM3LjM2IChLSFRNTCwgbGlrZSBHZWNrbykgQ2hyb21lLzEyNC4wIFNhZmFyaS81MzcuMzYiLAogICAgICAiQWNjZXB0LUxhbmd1YWdlIjogImlkLUlELGlkO3E9MC45LGVuO3E9MC44IiwKICAgIH0sCiAgICBz
::B64:agent.js:aWduYWw6IEFib3J0U2lnbmFsLnRpbWVvdXQoODAwMCksCiAgfSk7CiAgaWYgKCFyZXMub2spIHRocm93IG5ldyBFcnJvcigiSFRUUCAiICsgcmVzLnN0YXR1cyk7CiAgY29uc3QgaHRtbCA9IGF3YWl0IHJlcy50ZXh0KCk7CiAgY29uc3QgbSA9IGh0bWwubWF0Y2go
::B64:agent.js:L3l0SW5pdGlhbERhdGFccyo9XHMqKFx7Lis/XH0pO1xzKjxcL3NjcmlwdD4vcyk7CiAgaWYgKCFtKSB0aHJvdyBuZXcgRXJyb3IoImRhdGEgWW91VHViZSB0aWRhayBkaXRlbXVrYW4iKTsKICBjb25zdCBkYXRhID0gSlNPTi5wYXJzZShtWzFdKTsKICBjb25zdCBv
::B64:agent.js:dXQgPSBbXTsKICBjb25zdCB3YWxrID0gKG8pID0+IHsKICAgIGlmICghbyB8fCB0eXBlb2YgbyAhPT0gIm9iamVjdCIgfHwgb3V0Lmxlbmd0aCA+PSA4KSByZXR1cm47CiAgICBjb25zdCB2ID0gby52aWRlb1JlbmRlcmVyOwogICAgaWYgKHYgJiYgdi52aWRlb0lk
::B64:agent.js:KSB7CiAgICAgIG91dC5wdXNoKHsKICAgICAgICBpZDogdi52aWRlb0lkLAogICAgICAgIHRpdGxlOiAodi50aXRsZT8ucnVucyB8fCBbXSkubWFwKChyKSA9PiByLnRleHQpLmpvaW4oIiIpIHx8ICIodGFucGEganVkdWwpIiwKICAgICAgICBjaGFubmVsOiB2Lm93
::B64:agent.js:bmVyVGV4dD8ucnVucz8uWzBdPy50ZXh0IHx8ICIiLAogICAgICB9KTsKICAgICAgcmV0dXJuOwogICAgfQogICAgZm9yIChjb25zdCBrIG9mIE9iamVjdC5rZXlzKG8pKSB3YWxrKG9ba10pOwogIH07CiAgd2FsayhkYXRhKTsKICByZXR1cm4gb3V0Owp9CgovLyA9
::B64:agent.js:PT09PSBVcGxvYWQgY2VwYXQgPT09PT0KY29uc3QgVVBMT0FEX1RJTUVPVVRfTVMgPSBOdW1iZXIocHJvY2Vzcy5lbnYuVVBMT0FEX1RJTUVPVVRfTUlOIHx8IDE1KSAqIDYwMDAwOwpjb25zdCBIT1NUU19SRSA9IC9tZWRpYWZpcmVcLmNvbVwvKGZpbGV8dmlld3xk
::B64:agent.js:b3dubG9hZHxmb2xkZXIpfGRyaXZlXC5nb29nbGVcLmNvbVwvKGZpbGV8ZHJpdmVcL2ZvbGRlcnMpfHdldHJhbnNmZXJcLmNvbVwvZG93bmxvYWRzfHdlXC50bFwvfGdvZmlsZVwuaW9cL2RcL3xwaXhlbGRyYWluXC5jb21cL3VcL3xmaWxlc1wuY2F0Ym94XC5tb2V8
::B64:agent.js:Y2F0Ym94XC5tb2VcL3xmaWxlXC5pb1wvfHNlbmRzcGFjZVwuY29tXC9maWxlfHRyYW5zZmVyXC5zaFwvfHRtcGZpbGVzXC5vcmdcL1xkfGRyb3Bib3hcLmNvbVwvc3xtZWdhXC5uelwvKGZpbGV8Zm9sZGVyKXwxZHJ2XC5tc3xmaWxlYmluXC5uZXRcL1x3fHVwbG9h
::B64:agent.js:ZGhhdmVufGJheWZpbGVzL2k7CmNvbnN0IFVQTE9BRF9CVE4gPSAvXlxzKih1cGxvYWR8dW5nZ2FofG1lbmd1bmdnYWh8dGFtYmFoKGthbik/IGZpbGV8YWRkIGZpbGVzP3xzZWxlY3QgZmlsZXM/fGNob29zZSBmaWxlcz98cGlsaWggZmlsZXxicm93c2V8dGVsdXN1
::B64:agent.js:cmkpXGIvaTsKY29uc3QgU1VCTUlUX0JUTiA9IC9eXHMqKGJlZ2luIHVwbG9hZHxzdGFydCB1cGxvYWR8dXBsb2FkKCBub3d8IGZpbGVzPyk/fHVuZ2dhaCggc2VrYXJhbmcpP3xtdWxhaSggdXBsb2FkfCB1bmdnYWgpP3xraXJpbXxzZW5kfHN1Ym1pdHxzZWxlc2Fp
::B64:agent.js:fGRvbmV8bGFuanV0fGNvbnRpbnVlKVxzKiQvaTsKCmFzeW5jIGZ1bmN0aW9uIGZpbmRGaWxlSW5wdXRBbnkodGltZW91dE1zID0gMCkgewogIGNvbnN0IGRlYWRsaW5lID0gRGF0ZS5ub3coKSArIHRpbWVvdXRNczsKICBkbyB7CiAgICBmb3IgKGNvbnN0IGZyIG9m
::B64:agent.js:IHBhZ2UuZnJhbWVzKCkpIHsKICAgICAgY29uc3QgaCA9IGF3YWl0IGZyLiQoImlucHV0W3R5cGU9ZmlsZV0iKS5jYXRjaCgoKSA9PiBudWxsKTsKICAgICAgaWYgKGgpIHJldHVybiBoOwogICAgfQogICAgaWYgKHRpbWVvdXRNcykgYXdhaXQgc2xlZXAoMjAwKTsK
::B64:agent.js:ICB9IHdoaWxlIChEYXRlLm5vdygpIDwgZGVhZGxpbmUpOwogIHJldHVybiBudWxsOwp9Cgphc3luYyBmdW5jdGlvbiBoYXNMb2dpbkZvcm0oKSB7CiAgZm9yIChjb25zdCBmciBvZiBwYWdlLmZyYW1lcygpKSB7CiAgICBjb25zdCBwdyA9IGF3YWl0IGZyLiQoImlu
::B64:agent.js:cHV0W3R5cGU9cGFzc3dvcmRdIikuY2F0Y2goKCkgPT4gbnVsbCk7CiAgICBpZiAocHcgJiYgKGF3YWl0IHB3LmlzVmlzaWJsZSgpLmNhdGNoKCgpID0+IGZhbHNlKSkpIHJldHVybiB0cnVlOwogIH0KICByZXR1cm4gZmFsc2U7Cn0KCmFzeW5jIGZ1bmN0aW9uIGNs
::B64:agent.js:aWNrQnlUZXh0KHJlLCB0aW1lb3V0ID0gMTUwMCkgewogIGNvbnN0IGdyb3VwcyA9IFtwYWdlLmdldEJ5Um9sZSgiYnV0dG9uIiwgeyBuYW1lOiByZSB9KSwgcGFnZS5nZXRCeVJvbGUoImxpbmsiLCB7IG5hbWU6IHJlIH0pLCBwYWdlLmdldEJ5VGV4dChyZSldOwog
::B64:agent.js:IGZvciAoY29uc3QgZyBvZiBncm91cHMpIHsKICAgIGNvbnN0IG4gPSBNYXRoLm1pbihhd2FpdCBnLmNvdW50KCkuY2F0Y2goKCkgPT4gMCksIDUpOwogICAgZm9yIChsZXQgaSA9IDA7IGkgPCBuOyBpKyspIHsKICAgICAgY29uc3QgZWwgPSBnLm50aChpKTsKICAg
::B64:agent.js:ICAgaWYgKCEoYXdhaXQgZWwuaXNWaXNpYmxlKCkuY2F0Y2goKCkgPT4gZmFsc2UpKSkgY29udGludWU7CiAgICAgIHRyeSB7CiAgICAgICAgY29uc3QgbGFiZWwgPSAoKGF3YWl0IGVsLmlubmVyVGV4dCh7IHRpbWVvdXQ6IDQwMCB9KS5jYXRjaCgoKSA9PiAiIikp
::B64:agent.js:IHx8ICIiKS50cmltKCkuc2xpY2UoMCwgNDApOwogICAgICAgIGF3YWl0IGVsLmNsaWNrKHsgdGltZW91dCB9KTsKICAgICAgICByZXR1cm4gbGFiZWwgfHwgIih0b21ib2wpIjsKICAgICAgfSBjYXRjaCB7fQogICAgfQogIH0KICByZXR1cm4gIiI7Cn0KCi8vIEts
::B64:agent.js:aWsgdG9tYm9sICJVcGxvYWQiIGxhbHUgdGFuZ2thcCBkaWFsb2cgcGlsaWggZmlsZSBBVEFVIGlucHV0IGZpbGUgeWFuZyBtdW5jdWwKYXN5bmMgZnVuY3Rpb24gb3BlblVwbG9hZGVyKHF1ZXVlKSB7CiAgY29uc3QgZ3JvdXBzID0gW3BhZ2UuZ2V0QnlSb2xlKCJi
::B64:agent.js:dXR0b24iLCB7IG5hbWU6IFVQTE9BRF9CVE4gfSksIHBhZ2UuZ2V0QnlSb2xlKCJsaW5rIiwgeyBuYW1lOiBVUExPQURfQlROIH0pLCBwYWdlLmdldEJ5VGV4dChVUExPQURfQlROKV07CiAgZm9yIChjb25zdCBnIG9mIGdyb3VwcykgewogICAgY29uc3QgbiA9IE1h
::B64:agent.js:dGgubWluKGF3YWl0IGcuY291bnQoKS5jYXRjaCgoKSA9PiAwKSwgNCk7CiAgICBmb3IgKGxldCBpID0gMDsgaSA8IG47IGkrKykgewogICAgICBjb25zdCBlbCA9IGcubnRoKGkpOwogICAgICBpZiAoIShhd2FpdCBlbC5pc1Zpc2libGUoKS5jYXRjaCgoKSA9PiBm
::B64:agent.js:YWxzZSkpKSBjb250aW51ZTsKICAgICAgY29uc3QgY2hvb3NlclAgPSBwYWdlLndhaXRGb3JFdmVudCgiZmlsZWNob29zZXIiLCB7IHRpbWVvdXQ6IDIwMDAgfSkuY2F0Y2goKCkgPT4gbnVsbCk7CiAgICAgIHRyeSB7CiAgICAgICAgYXdhaXQgZWwuY2xpY2soeyB0
::B64:agent.js:aW1lb3V0OiAxNTAwIH0pOwogICAgICB9IGNhdGNoIHsKICAgICAgICBjb250aW51ZTsKICAgICAgfQogICAgICBjb25zdCBjaG9vc2VyID0gYXdhaXQgY2hvb3NlclA7CiAgICAgIGlmIChjaG9vc2VyKSB7CiAgICAgICAgY29uc3QgYmF0Y2ggPSBjaG9vc2VyLmlz
::B64:agent.js:TXVsdGlwbGUoKSA/IHF1ZXVlIDogW3F1ZXVlWzBdXTsKICAgICAgICBhd2FpdCBjaG9vc2VyLnNldEZpbGVzKGJhdGNoKTsKICAgICAgICByZXR1cm4geyB1c2VkOiBiYXRjaC5sZW5ndGggfTsKICAgICAgfQogICAgICBjb25zdCBpbnB1dCA9IGF3YWl0IGZpbmRG
::B64:agent.js:aWxlSW5wdXRBbnkoMTIwMCk7CiAgICAgIGlmIChpbnB1dCkgcmV0dXJuIHsgaW5wdXQgfTsKICAgIH0KICB9CiAgcmV0dXJuIG51bGw7Cn0KCi8vIE1hc3Vra2FuIGZpbGUga2UgaGFsYW1hbi4gTWVuZ2VtYmFsaWthbiBqdW1sYWggZmlsZSB5YW5nIGRpcGFrYWkg
::B64:agent.js:KDAgPSBnYWdhbCkKYXN5bmMgZnVuY3Rpb24gcHJvdmlkZUZpbGVzKHF1ZXVlKSB7CiAgbGV0IGlucHV0ID0gYXdhaXQgZmluZEZpbGVJbnB1dEFueSgxMjAwKTsKICBpZiAoIWlucHV0KSB7CiAgICBjb25zdCByID0gYXdhaXQgb3BlblVwbG9hZGVyKHF1ZXVlKTsK
::B64:agent.js:ICAgIGlmIChyICYmIHIudXNlZCkgcmV0dXJuIHIudXNlZDsKICAgIGlucHV0ID0gciAmJiByLmlucHV0OwogIH0KICBpZiAoIWlucHV0KSByZXR1cm4gMDsKICBjb25zdCBtdWx0aXBsZSA9IGF3YWl0IGlucHV0LmV2YWx1YXRlKChlbCkgPT4gISFlbC5tdWx0aXBs
::B64:agent.js:ZSkuY2F0Y2goKCkgPT4gZmFsc2UpOwogIGNvbnN0IGJhdGNoID0gbXVsdGlwbGUgPyBxdWV1ZSA6IFtxdWV1ZVswXV07CiAgYXdhaXQgaW5wdXQuc2V0SW5wdXRGaWxlcyhiYXRjaCk7CiAgcmV0dXJuIGJhdGNoLmxlbmd0aDsKfQoKZnVuY3Rpb24gdHJhY2tVcGxv
::B64:agent.js:YWRzKCkgewogIGxldCBwZW5kaW5nID0gMDsKICBsZXQgc2VlbiA9IDA7CiAgY29uc3QgaXNVcCA9IChyKSA9PiBbIlBPU1QiLCAiUFVUIiwgIlBBVENIIl0uaW5jbHVkZXMoci5tZXRob2QoKSk7CiAgY29uc3Qgb25SZXEgPSAocikgPT4gewogICAgaWYgKGlzVXAo
::B64:agent.js:cikpIHsKICAgICAgcGVuZGluZysrOwogICAgICBzZWVuKys7CiAgICB9CiAgfTsKICBjb25zdCBvbkRvbmUgPSAocikgPT4gewogICAgaWYgKGlzVXAocikpIHBlbmRpbmcgPSBNYXRoLm1heCgwLCBwZW5kaW5nIC0gMSk7CiAgfTsKICBjb250ZXh0Lm9uKCJyZXF1
::B64:agent.js:ZXN0Iiwgb25SZXEpOwogIGNvbnRleHQub24oInJlcXVlc3RmaW5pc2hlZCIsIG9uRG9uZSk7CiAgY29udGV4dC5vbigicmVxdWVzdGZhaWxlZCIsIG9uRG9uZSk7CiAgcmV0dXJuIHsKICAgIGdldCBwZW5kaW5nKCkgewogICAgICByZXR1cm4gcGVuZGluZzsKICAg
::B64:agent.js:IH0sCiAgICBnZXQgc2VlbigpIHsKICAgICAgcmV0dXJuIHNlZW47CiAgICB9LAogICAgc3RvcCgpIHsKICAgICAgY29udGV4dC5vZmYoInJlcXVlc3QiLCBvblJlcSk7CiAgICAgIGNvbnRleHQub2ZmKCJyZXF1ZXN0ZmluaXNoZWQiLCBvbkRvbmUpOwogICAgICBj
::B64:agent.js:b250ZXh0Lm9mZigicmVxdWVzdGZhaWxlZCIsIG9uRG9uZSk7CiAgICB9LAogIH07Cn0KCi8vIHRydWUgPSBzZWxlc2FpLCBzdHJpbmcgPSBzZWxlc2FpIGRlbmdhbiBjYXRhdGFuLCBmYWxzZSA9IHdha3R1IGhhYmlzCmFzeW5jIGZ1bmN0aW9uIHdhaXRVcGxvYWRE
::B64:agent.js:b25lKHRyLCBtYXhNcykgewogIGNvbnN0IHQwID0gRGF0ZS5ub3coKTsKICBsZXQgcXVpZXQgPSAwOwogIHdoaWxlIChEYXRlLm5vdygpIC0gdDAgPCBtYXhNcykgewogICAgYXdhaXQgc2xlZXAoNjAwKTsKICAgIGNvbnN0IGJ1c3kgPSBhd2FpdCBwYWdlCiAgICAg
::B64:agent.js:IC5ldmFsdWF0ZSgoKSA9PiB7CiAgICAgICAgY29uc3QgdmlzID0gKGUpID0+IGUub2Zmc2V0UGFyZW50ICE9PSBudWxsOwogICAgICAgIGNvbnN0IGJhcnMgPSBbLi4uZG9jdW1lbnQucXVlcnlTZWxlY3RvckFsbCgicHJvZ3Jlc3MsIFtyb2xlPXByb2dyZXNzYmFy
::B64:agent.js:XSIpXS5maWx0ZXIodmlzKTsKICAgICAgICBjb25zdCB0ID0gZG9jdW1lbnQuYm9keSA/IGRvY3VtZW50LmJvZHkuaW5uZXJUZXh0IDogIiI7CiAgICAgICAgY29uc3QgaW5Qcm9ncmVzcyA9IC9cYih1cGxvYWRpbmd8bWVuZ3VuZ2dhaHxzZWRhbmcgbWVuZ3VuZ2dh
::B64:agent.js:aHx1cGxvYWQgaW4gcHJvZ3Jlc3N8bWVtcHJvc2VzfHByb2Nlc3NpbmcpXGIvaS50ZXN0KHQpOwogICAgICAgIGNvbnN0IHVuZmluaXNoZWQgPSBiYXJzLnNvbWUoKGIpID0+IHsKICAgICAgICAgIGNvbnN0IHYgPSBiLmdldEF0dHJpYnV0ZSgiYXJpYS12YWx1ZW5v
::B64:agent.js:dyIpID8/IGIudmFsdWU7CiAgICAgICAgICBjb25zdCBteCA9IGIuZ2V0QXR0cmlidXRlKCJhcmlhLXZhbHVlbWF4IikgPz8gYi5tYXggPz8gMTAwOwogICAgICAgICAgcmV0dXJuIHYgPT0gbnVsbCB8fCBOdW1iZXIodikgPCBOdW1iZXIobXgpOwogICAgICAgIH0p
::B64:agent.js:OwogICAgICAgIHJldHVybiB1bmZpbmlzaGVkIHx8IGluUHJvZ3Jlc3M7CiAgICAgIH0pCiAgICAgIC5jYXRjaCgoKSA9PiBmYWxzZSk7CiAgICBpZiAodHIucGVuZGluZyA9PT0gMCAmJiAhYnVzeSkgewogICAgICBxdWlldCsrOwogICAgICBpZiAocXVpZXQgPj0g
::B64:agent.js:MyAmJiB0ci5zZWVuID4gMCkgcmV0dXJuIHRydWU7CiAgICAgIGlmIChxdWlldCA+PSA4KSByZXR1cm4gdHIuc2VlbiA+IDAgPyB0cnVlIDogInRpZGFrIGFkYSBha3Rpdml0YXMgdXBsb2FkIHRlcmRldGVrc2ksIHBlcmlrc2EgaGFsYW1hbiI7CiAgICB9IGVsc2Ug
::B64:agent.js:ewogICAgICBxdWlldCA9IDA7CiAgICB9CiAgfQogIHJldHVybiBmYWxzZTsKfQoKLy8gRm9sZGVyIGRpa2lyaW0gc2ViYWdhaSB6aXAuIFBha2FpIHRhciBiYXdhYW4gV2luZG93cyAoY2VwYXQpOyBjYWRhbmdhbjogQ29tcHJlc3MtQXJjaGl2ZQphc3luYyBmdW5j
::B64:agent.js:dGlvbiB6aXBGb3JVcGxvYWQoZGlyKSB7CiAgY29uc3QgemlwID0gcGF0aC5qb2luKG9zLnRtcGRpcigpLCBwYXRoLmJhc2VuYW1lKGRpcikgKyAiLnppcCIpOwogIHRyeSB7CiAgICBmcy5ybVN5bmMoemlwLCB7IGZvcmNlOiB0cnVlIH0pOwogIH0gY2F0Y2gge30K
::B64:agent.js:ICBjb25zdCB2aWFUYXIgPSBhd2FpdCBuZXcgUHJvbWlzZSgocmVzb2x2ZSkgPT4gewogICAgZXhlY0ZpbGUoInRhciIsIFsiLWEiLCAiLWMiLCAiLWYiLCB6aXAsICItQyIsIHBhdGguZGlybmFtZShkaXIpLCBwYXRoLmJhc2VuYW1lKGRpcildLCB7IHRpbWVvdXQ6
::B64:agent.js:IDkwMDAwMCB9LCAoZXJyKSA9PiByZXNvbHZlKCFlcnIpKTsKICB9KTsKICBpZiAoIXZpYVRhcikgewogICAgYXdhaXQgcHMoIkNvbXByZXNzLUFyY2hpdmUgLUxpdGVyYWxQYXRoICRlbnY6U1JDIC1EZXN0aW5hdGlvblBhdGggJGVudjpERVNUIC1Gb3JjZSIsIHsg
::B64:agent.js:U1JDOiBkaXIsIERFU1Q6IHppcCB9LCA5MDAwMDApOwogIH0KICByZXR1cm4gemlwOwp9CgpmdW5jdGlvbiByZWNlbnRMaXN0KGRpciwgY291bnQgPSAxMCkgewogIGNvbnN0IGJhZCA9IC9cLihjcmRvd25sb2FkfHRtcHxwYXJ0fGRvd25sb2FkfHBhcnRpYWwpJC9p
::B64:agent.js:OwogIGNvbnN0IGl0ZW1zID0gW107CiAgZm9yIChjb25zdCBlIG9mIGZzLnJlYWRkaXJTeW5jKGRpciwgeyB3aXRoRmlsZVR5cGVzOiB0cnVlIH0pKSB7CiAgICBpZiAoIWUuaXNGaWxlKCkgfHwgYmFkLnRlc3QoZS5uYW1lKSkgY29udGludWU7CiAgICBjb25zdCBm
::B64:agent.js:ID0gcGF0aC5qb2luKGRpciwgZS5uYW1lKTsKICAgIHRyeSB7CiAgICAgIGNvbnN0IHN0ID0gZnMuc3RhdFN5bmMoZik7CiAgICAgIGl0ZW1zLnB1c2goeyBmLCB0OiBzdC5tdGltZU1zLCBzOiBzdC5zaXplIH0pOwogICAgfSBjYXRjaCB7fQogIH0KICByZXR1cm4g
::B64:agent.js:aXRlbXMuc29ydCgoYSwgYikgPT4gYi50IC0gYS50KS5zbGljZSgwLCBNYXRoLm1pbihNYXRoLm1heChOdW1iZXIoY291bnQpIHx8IDEwLCAxKSwgNTApKTsKfQoKY29uc3QgdGltZXJzID0gW107CmNvbnN0IFNBRkVfUEFSQUxMRUwgPSBuZXcgU2V0KFsKICAiZmlu
::B64:agent.js:ZF9mb2xkZXIiLCAiZmluZF9maWxlIiwgImxpc3RfZGlyIiwgInJlYWRfdGV4dF9maWxlIiwgInN5c3RlbV9pbmZvIiwgIm5vdyIsICJjbGlwYm9hcmRfZ2V0IiwKICAibGlzdF90YWJzIiwgImxpc3Rfd2luZG93cyIsICJyZWNlbnRfZmlsZXMiLCAic2VhcmNoX3Rl
::B64:agent.js:eHQiLCAibGlzdF9maWxlcyIsCl0pOwoKY29uc3QgaW1wbCA9IHsKICAvLyAtLS0gRGVza3RvcDogZmlsZSAmIGZvbGRlciAtLS0KICBmaW5kX2ZvbGRlcjogYXN5bmMgKHsgbmFtZSB9KSA9PiBzZWFyY2hFdmVyeXdoZXJlKG5hbWUsIGZhbHNlKSwKCiAgZmluZF9m
::B64:agent.js:aWxlOiBhc3luYyAoeyBuYW1lIH0pID0+IHNlYXJjaEV2ZXJ5d2hlcmUobmFtZSwgdHJ1ZSksCgogIGxpc3RfZGlyOiBhc3luYyAoeyBwYXRoOiBwIH0pID0+IHsKICAgIGNvbnN0IGl0ZW1zID0gZnMucmVhZGRpclN5bmMocCwgeyB3aXRoRmlsZVR5cGVzOiB0cnVl
::B64:agent.js:IH0pLnNsaWNlKDAsIDEwMCk7CiAgICByZXR1cm4gaXRlbXMubWFwKChlKSA9PiAoZS5pc0RpcmVjdG9yeSgpID8gIltESVJdICIgOiAiW0ZJTEVdICIpICsgZS5uYW1lKS5qb2luKCJcbiIpIHx8ICIoa29zb25nKSI7CiAgfSwKCiAgb3Blbl9wYXRoOiBhc3luYyAo
::B64:agent.js:eyB0YXJnZXQgfSkgPT4gewogICAgaWYgKCEoYXdhaXQgYXNrKGBCdWthOiAke3RhcmdldH1gKSkpIHJldHVybiAiRGliYXRhbGthbiB1c2VyIjsKICAgIGF3YWl0IHBzKCJTdGFydC1Qcm9jZXNzIC1GaWxlUGF0aCAkZW52OlRBUkdFVCIsIHsgVEFSR0VUOiBTdHJp
::B64:agent.js:bmcodGFyZ2V0KSB9KTsKICAgIGF3YWl0IHNsZWVwKDgwMCk7CiAgICByZXR1cm4gIm9rLCBkaWJ1a2EiOwogIH0sCgogIC8vIC0tLSBEZXNrdG9wOiBsYXlhciwgbW91c2UsIGtleWJvYXJkIC0tLQogIHNjcmVlbnNob3Q6IGFzeW5jICgpID0+IHsKICAgIGNvbnN0
::B64:agent.js:IG91dCA9IHBhdGgucmVzb2x2ZSgic2NyZWVuLnBuZyIpOwogICAgY29uc3QgciA9IGF3YWl0IHBzKAogICAgICBQU19IRUFEICsKICAgICAgICBgCiRiID0gW1N5c3RlbS5XaW5kb3dzLkZvcm1zLlNjcmVlbl06OlByaW1hcnlTY3JlZW4uQm91bmRzCiRibXAgPSBO
::B64:agent.js:ZXctT2JqZWN0IFN5c3RlbS5EcmF3aW5nLkJpdG1hcCAkYi5XaWR0aCwgJGIuSGVpZ2h0CiRnID0gW1N5c3RlbS5EcmF3aW5nLkdyYXBoaWNzXTo6RnJvbUltYWdlKCRibXApCiRnLkNvcHlGcm9tU2NyZWVuKCRiLlgsICRiLlksIDAsIDAsICRibXAuU2l6ZSkKJG53
::B64:agent.js:ID0gW01hdGhdOjpNaW4oMTI4MCwgJGIuV2lkdGgpCiRuaCA9IFtpbnRdKCRiLkhlaWdodCAqICRudyAvICRiLldpZHRoKQokc21hbGwgPSBOZXctT2JqZWN0IFN5c3RlbS5EcmF3aW5nLkJpdG1hcCAkYm1wLCAkbncsICRuaAokc21hbGwuU2F2ZSgkZW52Ok9VVCwg
::B64:agent.js:W1N5c3RlbS5EcmF3aW5nLkltYWdpbmcuSW1hZ2VGb3JtYXRdOjpQbmcpCldyaXRlLU91dHB1dCAiJCgkYi5XaWR0aCksJG53LCRuaCIKYCwKICAgICAgeyBPVVQ6IG91dCB9CiAgICApOwogICAgY29uc3QgW3csIG53LCBuaF0gPSByLnNwbGl0KCJcbiIpLnBvcCgp
::B64:agent.js:LnNwbGl0KCIsIikubWFwKE51bWJlcik7CiAgICBzY2FsZSA9IHcgLyBudzsKICAgIHBlbmRpbmdJbWFnZXMucHVzaChmcy5yZWFkRmlsZVN5bmMob3V0KS50b1N0cmluZygiYmFzZTY0IikpOwogICAgcmV0dXJuIGBTY3JlZW5zaG90IGRpYW1iaWwgKCR7bnd9eCR7
::B64:agent.js:bmh9KS4gR2FtYmFybnlhIGFkYSBkaSBwZXNhbiBiZXJpa3V0bnlhLiBQYWthaSBrb29yZGluYXQgZGFyaSBnYW1iYXIgaXR1LmA7CiAgfSwKCiAgY2xpY2tfc2NyZWVuOiBhc3luYyAoeyB4LCB5LCBidXR0b24gPSAibGVmdCIsIGRvdWJsZSA9IGZhbHNlIH0pID0+
::B64:agent.js:IHsKICAgIGNvbnN0IHJ4ID0gTWF0aC5yb3VuZChOdW1iZXIoeCkgKiBzY2FsZSk7CiAgICBjb25zdCByeSA9IE1hdGgucm91bmQoTnVtYmVyKHkpICogc2NhbGUpOwogICAgY29uc3QgZGJsID0gZG91YmxlID09PSB0cnVlIHx8IGRvdWJsZSA9PT0gInRydWUiOwog
::B64:agent.js:ICAgaWYgKCEoYXdhaXQgYXNrKGAke2RibCA/ICJEb3VibGUta2xpayIgOiAiS2xpayJ9ICR7YnV0dG9ufSBkaSAoJHt4fSwke3l9KWApKSkgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgYXdhaXQgcHMoCiAgICAgIFBTX0hFQUQgKwogICAgICAgIGAKW1dd
::B64:agent.js:OjpTZXRDdXJzb3JQb3MoW2ludF0kZW52OlgsIFtpbnRdJGVudjpZKSB8IE91dC1OdWxsClN0YXJ0LVNsZWVwIC1NaWxsaXNlY29uZHMgMTUwCiRkb3duID0gMjsgJHVwID0gNAppZiAoJGVudjpCVE4gLWVxICJyaWdodCIpIHsgJGRvd24gPSA4OyAkdXAgPSAxNiB9
::B64:agent.js:CmZvciAoJGkgPSAwOyAkaSAtbHQgW2ludF0kZW52OkNPVU5UOyAkaSsrKSB7CiAgW1ddOjptb3VzZV9ldmVudCgkZG93biwgMCwgMCwgMCwgW1VJbnRQdHJdOjpaZXJvKQogIFtXXTo6bW91c2VfZXZlbnQoJHVwLCAwLCAwLCAwLCBbVUludFB0cl06Olplcm8pCiAg
::B64:agent.js:U3RhcnQtU2xlZXAgLU1pbGxpc2Vjb25kcyA4MAp9CmAsCiAgICAgIHsgWDogU3RyaW5nKHJ4KSwgWTogU3RyaW5nKHJ5KSwgQlROOiBTdHJpbmcoYnV0dG9uKSwgQ09VTlQ6IGRibCA/ICIyIiA6ICIxIiB9CiAgICApOwogICAgYXdhaXQgc2xlZXAoMzUwKTsKICAg
::B64:agent.js:IHJldHVybiAib2ssIGRpa2xpayI7CiAgfSwKCiAgc2Nyb2xsX3NjcmVlbjogYXN5bmMgKHsgYW1vdW50IH0pID0+IHsKICAgIGNvbnN0IGRlbHRhID0gLTEyMCAqIE1hdGgucm91bmQoTnVtYmVyKGFtb3VudCkpOyAvLyBwb3NpdGlmID0gdHVydW4KICAgIGlmICgh
::B64:agent.js:KGF3YWl0IGFzayhgU2Nyb2xsICR7YW1vdW50ID4gMCA/ICJ0dXJ1biIgOiAibmFpayJ9ICR7TWF0aC5hYnMoYW1vdW50KX14YCkpKSByZXR1cm4gIkRpYmF0YWxrYW4gdXNlciI7CiAgICBhd2FpdCBwcyhQU19IRUFEICsgYFtXXTo6bW91c2VfZXZlbnQoMHgwODAw
::B64:agent.js:LCAwLCAwLCBbaW50XSRlbnY6RCwgW1VJbnRQdHJdOjpaZXJvKWAsIHsgRDogU3RyaW5nKGRlbHRhKSB9KTsKICAgIGF3YWl0IHNsZWVwKDI1MCk7CiAgICByZXR1cm4gIm9rIjsKICB9LAoKICB0eXBlX2Rlc2t0b3A6IGFzeW5jICh7IHRleHQgfSkgPT4gewogICAg
::B64:agent.js:aWYgKCEoYXdhaXQgYXNrKGBLZXRpazogIiR7U3RyaW5nKHRleHQpLnNsaWNlKDAsIDYwKX0iYCkpKSByZXR1cm4gIkRpYmF0YWxrYW4gdXNlciI7CiAgICBhd2FpdCBwcygKICAgICAgUFNfSEVBRCArCiAgICAgICAgYApTZXQtQ2xpcGJvYXJkIC1WYWx1ZSAkZW52
::B64:agent.js:OlRYVApTdGFydC1TbGVlcCAtTWlsbGlzZWNvbmRzIDE1MApbU3lzdGVtLldpbmRvd3MuRm9ybXMuU2VuZEtleXNdOjpTZW5kV2FpdCgiXnYiKQpgLAogICAgICB7IFRYVDogU3RyaW5nKHRleHQpIH0KICAgICk7CiAgICBhd2FpdCBzbGVlcCgyNTApOwogICAgcmV0
::B64:agent.js:dXJuICJvaywgZGlrZXRpayI7CiAgfSwKCiAgcHJlc3Nfa2V5czogYXN5bmMgKHsga2V5cyB9KSA9PiB7CiAgICBpZiAoIShhd2FpdCBhc2soYFRla2FuIHRvbWJvbDogJHtrZXlzfWApKSkgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgYXdhaXQgcHMoUFNf
::B64:agent.js:SEVBRCArIGBbU3lzdGVtLldpbmRvd3MuRm9ybXMuU2VuZEtleXNdOjpTZW5kV2FpdCgkZW52OktFWVMpYCwgeyBLRVlTOiBTdHJpbmcoa2V5cykgfSk7CiAgICBhd2FpdCBzbGVlcCgyNTApOwogICAgcmV0dXJuICJvayI7CiAgfSwKCiAgd2FpdDogYXN5bmMgKHsg
::B64:agent.js:c2Vjb25kcyB9KSA9PiB7CiAgICBhd2FpdCBzbGVlcChNYXRoLm1pbihOdW1iZXIoc2Vjb25kcykgfHwgMSwgMTUpICogMTAwMCk7CiAgICByZXR1cm4gIm9rIjsKICB9LAoKICAvLyAtLS0gQnJvd3NlciAoUGxheXdyaWdodCkgLS0tCiAgbGlzdF9maWxlczogYXN5
::B64:agent.js:bmMgKCkgPT4gZnMucmVhZGRpclN5bmMoU0FGRV9ESVIpLmpvaW4oIlxuIikgfHwgIihmb2xkZXIgdXBsb2FkIGtvc29uZykiLAoKICBvcGVuX3VybDogYXN5bmMgKHsgdXJsLCBuZXdfdGFiID0gZmFsc2UgfSkgPT4gewogICAgaWYgKGlzVHJ1ZShuZXdfdGFiKSkg
::B64:agent.js:cGFnZSA9IGF3YWl0IGNvbnRleHQubmV3UGFnZSgpOwogICAgYXdhaXQgcGFnZS5icmluZ1RvRnJvbnQoKTsKICAgIGF3YWl0IHBhZ2UuZ290byhmaXhVcmwodXJsKSwgeyB3YWl0VW50aWw6ICJkb21jb250ZW50bG9hZGVkIiB9KTsKICAgIHJldHVybiAiVGVyYnVr
::B64:agent.js:YTogIiArIChhd2FpdCBwYWdlLnRpdGxlKCkpICsgKGlzVHJ1ZShuZXdfdGFiKSA/ICIgKGRpIHRhYiBiYXJ1KSIgOiAiIik7CiAgfSwKCiAgLy8gLS0tIFRhYiAtLS0KICBsaXN0X3RhYnM6IGFzeW5jICgpID0+IHRhYnNTdW1tYXJ5KCksCgogIG5ld190YWI6IGFz
::B64:agent.js:eW5jICh7IHVybCB9KSA9PiB7CiAgICBwYWdlID0gYXdhaXQgY29udGV4dC5uZXdQYWdlKCk7CiAgICBhd2FpdCBwYWdlLmJyaW5nVG9Gcm9udCgpOwogICAgaWYgKHVybCkgYXdhaXQgcGFnZS5nb3RvKGZpeFVybCh1cmwpLCB7IHdhaXRVbnRpbDogImRvbWNvbnRl
::B64:agent.js:bnRsb2FkZWQiIH0pOwogICAgcmV0dXJuICJUYWIgYmFydSBkaWJ1a2EgZGFuIGphZGkgdGFiIGFrdGlmLlxuIiArIChhd2FpdCB0YWJzU3VtbWFyeSgpKTsKICB9LAoKICBvcGVuX3VybHM6IGFzeW5jICh7IHVybHMgfSkgPT4gewogICAgY29uc3QgbGlzdCA9IChB
::B64:agent.js:cnJheS5pc0FycmF5KHVybHMpID8gdXJscyA6IFN0cmluZyh1cmxzKS5zcGxpdCgvW1xuLDt8XSsvKSkKICAgICAgLm1hcCgoeCkgPT4gU3RyaW5nKHgpLnRyaW0oKSkKICAgICAgLmZpbHRlcihCb29sZWFuKQogICAgICAuc2xpY2UoMCwgMTApOwogICAgaWYgKCFs
::B64:agent.js:aXN0Lmxlbmd0aCkgdGhyb3cgbmV3IEVycm9yKCJUaWRhayBhZGEgVVJMIik7CiAgICBjb25zdCBnYWdhbCA9IFtdOwogICAgZm9yIChjb25zdCB1IG9mIGxpc3QpIHsKICAgICAgcGFnZSA9IGF3YWl0IGNvbnRleHQubmV3UGFnZSgpOwogICAgICB0cnkgewogICAg
::B64:agent.js:ICAgIGF3YWl0IHBhZ2UuZ290byhmaXhVcmwodSksIHsgd2FpdFVudGlsOiAiZG9tY29udGVudGxvYWRlZCIsIHRpbWVvdXQ6IDMwMDAwIH0pOwogICAgICB9IGNhdGNoIChlKSB7CiAgICAgICAgZ2FnYWwucHVzaCh1KTsKICAgICAgfQogICAgfQogICAgcmV0dXJu
::B64:agent.js:IGAke2xpc3QubGVuZ3RoIC0gZ2FnYWwubGVuZ3RofSB0YWIgZGlidWthJHtnYWdhbC5sZW5ndGggPyBgLCBnYWdhbDogJHtnYWdhbC5qb2luKCIsICIpfWAgOiAiIn0uXG5gICsgKGF3YWl0IHRhYnNTdW1tYXJ5KCkpOwogIH0sCgogIHN3aXRjaF90YWI6IGFzeW5j
::B64:agent.js:ICh7IGluZGV4LCBtYXRjaCB9KSA9PiB7CiAgICBjb25zdCBhbGwgPSBsaXZlUGFnZXMoKTsKICAgIGxldCB0YXJnZXQ7CiAgICBpZiAobWF0Y2gpIHsKICAgICAgY29uc3QgcSA9IFN0cmluZyhtYXRjaCkudG9Mb3dlckNhc2UoKTsKICAgICAgZm9yIChjb25zdCB4
::B64:agent.js:IG9mIGFsbCkgewogICAgICAgIGNvbnN0IHQgPSAoKGF3YWl0IHgudGl0bGUoKS5jYXRjaCgoKSA9PiAiIikpICsgIiAiICsgeC51cmwoKSkudG9Mb3dlckNhc2UoKTsKICAgICAgICBpZiAodC5pbmNsdWRlcyhxKSkgewogICAgICAgICAgdGFyZ2V0ID0geDsKICAg
::B64:agent.js:ICAgICAgIGJyZWFrOwogICAgICAgIH0KICAgICAgfQogICAgfSBlbHNlIHsKICAgICAgdGFyZ2V0ID0gcGlja1RhYihhbGwsIGluZGV4KTsKICAgIH0KICAgIGlmICghdGFyZ2V0KSB0aHJvdyBuZXcgRXJyb3IoIlRhYiB0aWRhayBkaXRlbXVrYW4uXG4iICsgKGF3
::B64:agent.js:YWl0IHRhYnNTdW1tYXJ5KCkpKTsKICAgIHBhZ2UgPSB0YXJnZXQ7CiAgICBhd2FpdCBwYWdlLmJyaW5nVG9Gcm9udCgpOwogICAgcmV0dXJuICJUYWIgYWt0aWYgc2VrYXJhbmc6ICIgKyAoYXdhaXQgcGFnZS50aXRsZSgpLmNhdGNoKCgpID0+ICIiKSkgKyAiIHwg
::B64:agent.js:IiArIHBhZ2UudXJsKCk7CiAgfSwKCiAgY2xvc2VfdGFiOiBhc3luYyAoeyBpbmRleCB9KSA9PiB7CiAgICBjb25zdCBhbGwgPSBsaXZlUGFnZXMoKTsKICAgIGNvbnN0IHRhcmdldCA9IGluZGV4ID8gcGlja1RhYihhbGwsIGluZGV4KSA6IHBhZ2U7CiAgICBpZiAo
::B64:agent.js:IXRhcmdldCkgdGhyb3cgbmV3IEVycm9yKCJUYWIgdGlkYWsgZGl0ZW11a2FuLlxuIiArIChhd2FpdCB0YWJzU3VtbWFyeSgpKSk7CiAgICBpZiAoYWxsLmxlbmd0aCA9PT0gMSkgdGhyb3cgbmV3IEVycm9yKCJJbmkgdGFiIHRlcmFraGlyLCB0aWRhayBkaXR1dHVw
::B64:agent.js:IGFnYXIgYnJvd3NlciB0ZXRhcCB0ZXJidWthIik7CiAgICBjb25zdCBqdWR1bCA9IGF3YWl0IHRhcmdldC50aXRsZSgpLmNhdGNoKCgpID0+ICIiKTsKICAgIGlmICghKGF3YWl0IGFzayhgVHV0dXAgdGFiOiAke2p1ZHVsfWApKSkgcmV0dXJuICJEaWJhdGFsa2Fu
::B64:agent.js:IHVzZXIiOwogICAgY29uc3Qgd2FzQWN0aXZlID0gdGFyZ2V0ID09PSBwYWdlOwogICAgYXdhaXQgdGFyZ2V0LmNsb3NlKCk7CiAgICBpZiAod2FzQWN0aXZlKSB7CiAgICAgIHBhZ2UgPSBsaXZlUGFnZXMoKS5hdCgtMSk7CiAgICAgIGF3YWl0IHBhZ2UuYnJpbmdU
::B64:agent.js:b0Zyb250KCk7CiAgICB9CiAgICByZXR1cm4gIm9rLlxuIiArIChhd2FpdCB0YWJzU3VtbWFyeSgpKTsKICB9LAoKICBpbnNwZWN0X3BhZ2U6IGFzeW5jICgpID0+IHsKICAgIGNvbnN0IGl0ZW1zID0gYXdhaXQgcGFnZS5ldmFsdWF0ZSgoKSA9PgogICAgICBbLi4u
::B64:agent.js:ZG9jdW1lbnQucXVlcnlTZWxlY3RvckFsbCgiaW5wdXQsIGJ1dHRvbiwgYSwgdGV4dGFyZWEsIHNlbGVjdCIpXQogICAgICAgIC5zbGljZSgwLCA2MCkKICAgICAgICAubWFwKChlKSA9PiAoewogICAgICAgICAgdGFnOiBlLnRhZ05hbWUudG9Mb3dlckNhc2UoKSwK
::B64:agent.js:ICAgICAgICAgIGlkOiBlLmlkIHx8IHVuZGVmaW5lZCwKICAgICAgICAgIG5hbWU6IGUuZ2V0QXR0cmlidXRlKCJuYW1lIikgfHwgdW5kZWZpbmVkLAogICAgICAgICAgdHlwZTogZS5nZXRBdHRyaWJ1dGUoInR5cGUiKSB8fCB1bmRlZmluZWQsCiAgICAgICAgICB0
::B64:agent.js:ZXh0OiAoZS5pbm5lclRleHQgfHwgZS52YWx1ZSB8fCBlLnBsYWNlaG9sZGVyIHx8ICIiKS50cmltKCkuc2xpY2UoMCwgNDApIHx8IHVuZGVmaW5lZCwKICAgICAgICB9KSkKICAgICk7CiAgICByZXR1cm4gSlNPTi5zdHJpbmdpZnkoaXRlbXMpOwogIH0sCgogIHlv
::B64:agent.js:dXR1YmVfcGxheTogYXN5bmMgKHsgcXVlcnksIHBpY2sgPSAxLCBuZXdfdGFiID0gZmFsc2UgfSkgPT4gewogICAgaWYgKGlzVHJ1ZShuZXdfdGFiKSkgcGFnZSA9IGF3YWl0IGNvbnRleHQubmV3UGFnZSgpOwogICAgYXdhaXQgcGFnZS5icmluZ1RvRnJvbnQoKTsK
::B64:agent.js:ICAgIGxldCBsaXN0ID0gW107CiAgICB0cnkgewogICAgICBsaXN0ID0gKGF3YWl0IHl0U2VhcmNoRmFzdChTdHJpbmcocXVlcnkpKSkuc2xpY2UoMCwgNSkubWFwKCh2KSA9PiAoewogICAgICAgIHRpdGxlOiB2LnRpdGxlICsgKHYuY2hhbm5lbCA/ICIgfCAiICsg
::B64:agent.js:di5jaGFubmVsIDogIiIpLAogICAgICAgIGhyZWY6ICJodHRwczovL3d3dy55b3V0dWJlLmNvbS93YXRjaD92PSIgKyB2LmlkLAogICAgICB9KSk7CiAgICB9IGNhdGNoIHt9CiAgICBpZiAoIWxpc3QubGVuZ3RoKSB7CiAgICAgIGF3YWl0IHBhZ2UuZ290bygiaHR0
::B64:agent.js:cHM6Ly93d3cueW91dHViZS5jb20vcmVzdWx0cz9zZWFyY2hfcXVlcnk9IiArIGVuY29kZVVSSUNvbXBvbmVudChTdHJpbmcocXVlcnkpKSwgewogICAgICAgIHdhaXRVbnRpbDogImRvbWNvbnRlbnRsb2FkZWQiLAogICAgICB9KTsKICAgICAgYXdhaXQgcGFnZS53
::B64:agent.js:YWl0Rm9yU2VsZWN0b3IoInl0ZC12aWRlby1yZW5kZXJlciBhI3ZpZGVvLXRpdGxlIiwgeyB0aW1lb3V0OiAyMDAwMCB9KTsKICAgICAgbGlzdCA9IGF3YWl0IHBhZ2UuJCRldmFsKCJ5dGQtdmlkZW8tcmVuZGVyZXIgYSN2aWRlby10aXRsZSIsIChlbHMpID0+CiAg
::B64:agent.js:ICAgICAgZWxzLnNsaWNlKDAsIDUpLm1hcCgoZSkgPT4gKHsgdGl0bGU6IGUudGV4dENvbnRlbnQudHJpbSgpLCBocmVmOiBlLmhyZWYgfSkpCiAgICAgICk7CiAgICB9CiAgICBpZiAoIWxpc3QubGVuZ3RoKSByZXR1cm4gIlRpZGFrIGFkYSBoYXNpbCI7CiAgICBj
::B64:agent.js:b25zdCBzdGFydCA9IE1hdGgubWluKE1hdGgubWF4KE51bWJlcihwaWNrKSB8fCAxLCAxKSwgbGlzdC5sZW5ndGgpIC0gMTsKICAgIGNvbnN0IG9yZGVyID0gW3N0YXJ0LCAuLi5saXN0Lm1hcCgoXywgaSkgPT4gaSkuZmlsdGVyKChpKSA9PiBpICE9PSBzdGFydCld
::B64:agent.js:LnNsaWNlKDAsIDMpOwogICAgY29uc3Qgb3RoZXJzID0gbGlzdC5tYXAoKHYsIGkpID0+IGAke2kgKyAxfS4gJHt2LnRpdGxlfWApLmpvaW4oIlxuIik7CiAgICBmb3IgKGNvbnN0IGlkeCBvZiBvcmRlcikgewogICAgICBhd2FpdCBwYWdlLmdvdG8obGlzdFtpZHhd
::B64:agent.js:LmhyZWYsIHsgd2FpdFVudGlsOiAiZG9tY29udGVudGxvYWRlZCIgfSk7CiAgICAgIGlmIChhd2FpdCBlbnN1cmVQbGF5aW5nKCkpIHsKICAgICAgICByZXR1cm4gYE1lbXV0YXIgIyR7aWR4ICsgMX06ICR7bGlzdFtpZHhdLnRpdGxlfVxuSGFzaWwgcGVuY2FyaWFu
::B64:agent.js:OlxuJHtvdGhlcnN9YDsKICAgICAgfQogICAgfQogICAgcmV0dXJuICJWaWRlbyBnYWdhbCBkaXB1dGFyIChZb3VUdWJlIG1lbmFtcGlsa2FuIGVycm9yKS4gQ29iYSAvbG9naW4gYXRhdSBqdWR1bCBsYWluLlxuSGFzaWwgcGVuY2FyaWFuOlxuIiArIG90aGVyczsK
::B64:agent.js:ICB9LAoKICB5b3V0dWJlX2NvbnRyb2w6IGFzeW5jICh7IGFjdGlvbiwgc2Vjb25kcyA9IDEwIH0pID0+IHsKICAgIGF3YWl0IHBhZ2UuYnJpbmdUb0Zyb250KCk7CiAgICByZXR1cm4gcGFnZS5ldmFsdWF0ZSgKICAgICAgKHsgYSwgcyB9KSA9PiB7CiAgICAgICAg
::B64:agent.js:Y29uc3QgdiA9IGRvY3VtZW50LnF1ZXJ5U2VsZWN0b3IoInZpZGVvIik7CiAgICAgICAgaWYgKCF2KSByZXR1cm4gIlRpZGFrIGFkYSB2aWRlbyBkaSBoYWxhbWFuIGluaSI7CiAgICAgICAgaWYgKGEgPT09ICJwYXVzZSIpIHYucGF1c2UoKTsKICAgICAgICBlbHNl
::B64:agent.js:IGlmIChhID09PSAicGxheSIpIHYucGxheSgpOwogICAgICAgIGVsc2UgaWYgKGEgPT09ICJ0b2dnbGUiKSAodi5wYXVzZWQgPyB2LnBsYXkoKSA6IHYucGF1c2UoKSk7CiAgICAgICAgZWxzZSBpZiAoYSA9PT0gIm11dGUiKSB2Lm11dGVkID0gdHJ1ZTsKICAgICAg
::B64:agent.js:ICBlbHNlIGlmIChhID09PSAidW5tdXRlIikgdi5tdXRlZCA9IGZhbHNlOwogICAgICAgIGVsc2UgaWYgKGEgPT09ICJmb3J3YXJkIikgdi5jdXJyZW50VGltZSArPSBzOwogICAgICAgIGVsc2UgaWYgKGEgPT09ICJiYWNrd2FyZCIpIHYuY3VycmVudFRpbWUgLT0g
::B64:agent.js:czsKICAgICAgICBlbHNlIGlmIChhID09PSAibmV4dCIpIHsKICAgICAgICAgIGNvbnN0IGIgPSBkb2N1bWVudC5xdWVyeVNlbGVjdG9yKCIueXRwLW5leHQtYnV0dG9uIik7CiAgICAgICAgICBpZiAoIWIpIHJldHVybiAiVG9tYm9sIG5leHQgdGlkYWsgYWRhIjsK
::B64:agent.js:ICAgICAgICAgIGIuY2xpY2soKTsKICAgICAgICB9IGVsc2UgaWYgKGEgPT09ICJwcmV2aW91cyIpIHsKICAgICAgICAgIGNvbnN0IGIgPSBkb2N1bWVudC5xdWVyeVNlbGVjdG9yKCIueXRwLXByZXYtYnV0dG9uIik7CiAgICAgICAgICBpZiAoYiAmJiBnZXRDb21w
::B64:agent.js:dXRlZFN0eWxlKGIpLmRpc3BsYXkgIT09ICJub25lIikgYi5jbGljaygpOwogICAgICAgICAgZWxzZSBoaXN0b3J5LmJhY2soKTsKICAgICAgICB9IGVsc2UgaWYgKGEgPT09ICJmdWxsc2NyZWVuIikgewogICAgICAgICAgY29uc3QgYiA9IGRvY3VtZW50LnF1ZXJ5
::B64:agent.js:U2VsZWN0b3IoIi55dHAtZnVsbHNjcmVlbi1idXR0b24iKTsKICAgICAgICAgIGlmIChiKSBiLmNsaWNrKCk7CiAgICAgICAgfSBlbHNlIHJldHVybiAiQWtzaSB0aWRhayBkaWtlbmFsLiBQaWxpaDogcGxheSwgcGF1c2UsIHRvZ2dsZSwgbXV0ZSwgdW5tdXRlLCBm
::B64:agent.js:b3J3YXJkLCBiYWNrd2FyZCwgbmV4dCwgcHJldmlvdXMsIGZ1bGxzY3JlZW4iOwogICAgICAgIHJldHVybiAib2siOwogICAgICB9LAogICAgICB7IGE6IFN0cmluZyhhY3Rpb24pLnRvTG93ZXJDYXNlKCksIHM6IE51bWJlcihzZWNvbmRzKSB8fCAxMCB9CiAgICAp
::B64:agent.js:OwogIH0sCgogIC8vIC0tLSBXZWIgLS0tCiAgd2ViX3NlYXJjaDogYXN5bmMgKHsgcXVlcnksIG5ld190YWIgPSBmYWxzZSB9KSA9PiB7CiAgICBpZiAoaXNUcnVlKG5ld190YWIpKSBwYWdlID0gYXdhaXQgY29udGV4dC5uZXdQYWdlKCk7CiAgICBhd2FpdCBwYWdl
::B64:agent.js:LmJyaW5nVG9Gcm9udCgpOwogICAgYXdhaXQgcGFnZS5nb3RvKCJodHRwczovL2h0bWwuZHVja2R1Y2tnby5jb20vaHRtbC8/cT0iICsgZW5jb2RlVVJJQ29tcG9uZW50KFN0cmluZyhxdWVyeSkpLCB7CiAgICAgIHdhaXRVbnRpbDogImRvbWNvbnRlbnRsb2FkZWQi
::B64:agent.js:LAogICAgfSk7CiAgICBjb25zdCByb3dzID0gYXdhaXQgcGFnZS4kJGV2YWwoIi5yZXN1bHQiLCAoZWxzKSA9PgogICAgICBlbHMuc2xpY2UoMCwgOCkubWFwKChlKSA9PiAoewogICAgICAgIHRpdGxlOiBlLnF1ZXJ5U2VsZWN0b3IoIi5yZXN1bHRfX2EiKT8udGV4
::B64:agent.js:dENvbnRlbnQudHJpbSgpLAogICAgICAgIHVybDogZS5xdWVyeVNlbGVjdG9yKCIucmVzdWx0X19hIik/LmhyZWYsCiAgICAgICAgc25pcHBldDogZS5xdWVyeVNlbGVjdG9yKCIucmVzdWx0X19zbmlwcGV0Iik/LnRleHRDb250ZW50LnRyaW0oKSwKICAgICAgfSkp
::B64:agent.js:CiAgICApOwogICAgY29uc3QgcmVhbCA9ICh1KSA9PiB7CiAgICAgIHRyeSB7CiAgICAgICAgY29uc3QgeCA9IG5ldyBVUkwodSk7CiAgICAgICAgcmV0dXJuIHguc2VhcmNoUGFyYW1zLmdldCgidWRkZyIpIHx8IHU7CiAgICAgIH0gY2F0Y2ggewogICAgICAgIHJl
::B64:agent.js:dHVybiB1OwogICAgICB9CiAgICB9OwogICAgY29uc3Qgb2sgPSByb3dzLmZpbHRlcigocikgPT4gci50aXRsZSk7CiAgICByZXR1cm4gb2subGVuZ3RoID8gb2subWFwKChyLCBpKSA9PiBgJHtpICsgMX0uICR7ci50aXRsZX1cbiAgICR7cmVhbChyLnVybCl9XG4g
::B64:agent.js:ICAke3Iuc25pcHBldCB8fCAiIn1gKS5qb2luKCJcbiIpIDogIlRpZGFrIGFkYSBoYXNpbCI7CiAgfSwKCiAgc2Nyb2xsX3BhZ2U6IGFzeW5jICh7IGFtb3VudCB9KSA9PiB7CiAgICBhd2FpdCBwYWdlLm1vdXNlLndoZWVsKDAsIE1hdGgucm91bmQoTnVtYmVyKGFt
::B64:agent.js:b3VudCkgfHwgMSkgKiA3MDApOwogICAgYXdhaXQgc2xlZXAoMjAwKTsKICAgIHJldHVybiAib2siOwogIH0sCgogIHdhaXRfZm9yX3VzZXI6IGFzeW5jICh7IG1lc3NhZ2UgfSkgPT4gewogICAgYXdhaXQgcGFnZS5icmluZ1RvRnJvbnQoKS5jYXRjaCgoKSA9PiB7
::B64:agent.js:fSk7CiAgICBjb25zb2xlLmxvZyhgXG5bQlVUVUggQkFOVFVBTiBLQU1VXSAke21lc3NhZ2V9YCk7CiAgICBhd2FpdCBybC5xdWVzdGlvbigiVGVrYW4gRW50ZXIgamlrYSBzdWRhaCBzZWxlc2FpLi4uICIpOwogICAgcmV0dXJuICJVc2VyIHN1ZGFoIHNlbGVzYWki
::B64:agent.js:OwogIH0sCgogIGRvd25sb2FkX2ZpbGU6IGFzeW5jICh7IHVybCwgZmlsZW5hbWUgfSkgPT4gewogICAgaWYgKCEvXmh0dHBzPzpcL1wvL2kudGVzdChTdHJpbmcodXJsKSkpIHRocm93IG5ldyBFcnJvcigiVVJMIGhhcnVzIGRpYXdhbGkgaHR0cDovLyBhdGF1IGh0
::B64:agent.js:dHBzOi8vIik7CiAgICBjb25zdCBndWVzcyA9IGRlY29kZVVSSUNvbXBvbmVudChuZXcgVVJMKHVybCkucGF0aG5hbWUuc3BsaXQoIi8iKS5wb3AoKSB8fCAiIikgfHwgImRvd25sb2FkLmJpbiI7CiAgICBjb25zdCBkZXN0ID0gcGF0aC5qb2luKEhPTUUsICJEb3du
::B64:agent.js:bG9hZHMiLCBwYXRoLmJhc2VuYW1lKFN0cmluZyhmaWxlbmFtZSB8fCBndWVzcykpKTsKICAgIGlmICghKGF3YWl0IGFzayhgVW5kdWggJHt1cmx9ICBrZSAgJHtkZXN0fWApKSkgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgY29uc3QgcmVzID0gYXdhaXQg
::B64:agent.js:ZmV0Y2godXJsLCB7IHJlZGlyZWN0OiAiZm9sbG93Iiwgc2lnbmFsOiBBYm9ydFNpZ25hbC50aW1lb3V0KDEwICogNjAgKiAxMDAwKSB9KTsKICAgIGlmICghcmVzLm9rKSB0aHJvdyBuZXcgRXJyb3IoIkhUVFAgIiArIHJlcy5zdGF0dXMpOwogICAgYXdhaXQgcGlw
::B64:agent.js:ZWxpbmUoUmVhZGFibGUuZnJvbVdlYihyZXMuYm9keSksIGZzLmNyZWF0ZVdyaXRlU3RyZWFtKGRlc3QpKTsKICAgIHJldHVybiBgb2ssIHRlcnNpbXBhbjogJHtkZXN0fSAoJHtmcy5zdGF0U3luYyhkZXN0KS5zaXplfSBieXRlKWA7CiAgfSwKCiAgLy8gLS0tIFBD
::B64:agent.js:OiBpbmZvLCBtZWRpYSwgY2xpcGJvYXJkLCBqZW5kZWxhIC0tLQogIG5vdzogYXN5bmMgKCkgPT4gbmV3IERhdGUoKS50b0xvY2FsZVN0cmluZygiaWQtSUQiLCB7IGRhdGVTdHlsZTogImZ1bGwiLCB0aW1lU3R5bGU6ICJsb25nIiB9KSwKCiAgc3lzdGVtX2luZm86
::B64:agent.js:IGFzeW5jICgpID0+CiAgICBwcyhgCiRvcyA9IEdldC1DaW1JbnN0YW5jZSBXaW4zMl9PcGVyYXRpbmdTeXN0ZW0KJGNwdSA9IEdldC1DaW1JbnN0YW5jZSBXaW4zMl9Qcm9jZXNzb3IgfCBTZWxlY3QtT2JqZWN0IC1GaXJzdCAxCiRiYXQgPSBHZXQtQ2ltSW5zdGFu
::B64:agent.js:Y2UgV2luMzJfQmF0dGVyeSB8IFNlbGVjdC1PYmplY3QgLUZpcnN0IDEKJGwgPSBAKCkKJGwgKz0gIk9TOiAiICsgJG9zLkNhcHRpb24KJGwgKz0gIkNQVTogIiArICRjcHUuTmFtZSArICIgKGJlYmFuICIgKyAkY3B1LkxvYWRQZXJjZW50YWdlICsgIiUpIgokbCAr
::B64:agent.js:PSAiUkFNOiBiZWJhcyAiICsgW21hdGhdOjpSb3VuZCgkb3MuRnJlZVBoeXNpY2FsTWVtb3J5IC8gMU1CLCAxKSArICIgR0IgZGFyaSAiICsgW21hdGhdOjpSb3VuZCgkb3MuVG90YWxWaXNpYmxlTWVtb3J5U2l6ZSAvIDFNQiwgMSkgKyAiIEdCIgppZiAoJGJhdCkg
::B64:agent.js:eyAkbCArPSAiQmF0ZXJhaTogIiArICRiYXQuRXN0aW1hdGVkQ2hhcmdlUmVtYWluaW5nICsgIiUiIH0gZWxzZSB7ICRsICs9ICJCYXRlcmFpOiB0aWRhayBhZGEgKFBDIGRlc2t0b3ApIiB9CkdldC1DaW1JbnN0YW5jZSBXaW4zMl9Mb2dpY2FsRGlzayAtRmlsdGVy
::B64:agent.js:ICJEcml2ZVR5cGU9MyIgfCBGb3JFYWNoLU9iamVjdCB7ICRsICs9ICJEaXNrICIgKyAkXy5EZXZpY2VJRCArICIgYmViYXMgIiArIFttYXRoXTo6Um91bmQoJF8uRnJlZVNwYWNlIC8gMUdCLCAxKSArICIgR0IgZGFyaSAiICsgW21hdGhdOjpSb3VuZCgkXy5TaXpl
::B64:agent.js:IC8gMUdCLCAxKSArICIgR0IiIH0KJGwgLWpvaW4gW0Vudmlyb25tZW50XTo6TmV3TGluZQpgKSwKCiAgbWVkaWFfa2V5OiBhc3luYyAoeyBrZXksIHRpbWVzID0gMSB9KSA9PiB7CiAgICBjb25zdCB2YWxpZCA9IFsidm9sdXAiLCAidm9sZG93biIsICJtdXRlIiwg
::B64:agent.js:InBsYXlwYXVzZSIsICJuZXh0IiwgInByZXYiXTsKICAgIGlmICghdmFsaWQuaW5jbHVkZXMoU3RyaW5nKGtleSkpKSByZXR1cm4gImtleSBoYXJ1cyBzYWxhaCBzYXR1IGRhcmk6ICIgKyB2YWxpZC5qb2luKCIsICIpOwogICAgYXdhaXQgcHMoCiAgICAgIGAKQWRk
::B64:agent.js:LVR5cGUgQCIKdXNpbmcgU3lzdGVtLlJ1bnRpbWUuSW50ZXJvcFNlcnZpY2VzOwpwdWJsaWMgY2xhc3MgSyB7IFtEbGxJbXBvcnQoInVzZXIzMi5kbGwiKV0gcHVibGljIHN0YXRpYyBleHRlcm4gdm9pZCBrZXliZF9ldmVudChieXRlIGIsIGJ5dGUgcywgdWludCBm
::B64:agent.js:LCBpbnQgZSk7IH0KIkAKJG1hcCA9IEB7IHZvbHVwID0gMHhBRjsgdm9sZG93biA9IDB4QUU7IG11dGUgPSAweEFEOyBwbGF5cGF1c2UgPSAweEIzOyBuZXh0ID0gMHhCMDsgcHJldiA9IDB4QjEgfQokayA9IFtieXRlXSRtYXBbJGVudjpLRVldCmZvciAoJGkgPSAw
::B64:agent.js:OyAkaSAtbHQgW2ludF0kZW52Ok47ICRpKyspIHsgW0tdOjprZXliZF9ldmVudCgkaywgMCwgMCwgMCk7IFtLXTo6a2V5YmRfZXZlbnQoJGssIDAsIDIsIDApOyBTdGFydC1TbGVlcCAtTWlsbGlzZWNvbmRzIDYwIH0KYCwKICAgICAgeyBLRVk6IFN0cmluZyhrZXkp
::B64:agent.js:LCBOOiBTdHJpbmcoTWF0aC5taW4oTWF0aC5tYXgoTnVtYmVyKHRpbWVzKSB8fCAxLCAxKSwgNTApKSB9CiAgICApOwogICAgcmV0dXJuICJvayI7CiAgfSwKCiAgY2xpcGJvYXJkX2dldDogYXN5bmMgKCkgPT4gKGF3YWl0IHBzKCJHZXQtQ2xpcGJvYXJkIC1SYXci
::B64:agent.js:KSkuc2xpY2UoMCwgNDAwMCkgfHwgIihrb3NvbmcpIiwKCiAgY2xpcGJvYXJkX3NldDogYXN5bmMgKHsgdGV4dCB9KSA9PiB7CiAgICBhd2FpdCBwcygiU2V0LUNsaXBib2FyZCAtVmFsdWUgJGVudjpUWFQiLCB7IFRYVDogU3RyaW5nKHRleHQpIH0pOwogICAgcmV0
::B64:agent.js:dXJuICJvayI7CiAgfSwKCiAgbGlzdF93aW5kb3dzOiBhc3luYyAoKSA9PgogICAgKGF3YWl0IHBzKGBHZXQtUHJvY2VzcyB8IFdoZXJlLU9iamVjdCB7ICRfLk1haW5XaW5kb3dUaXRsZSB9IHwgRm9yRWFjaC1PYmplY3QgeyAkXy5Qcm9jZXNzTmFtZSArICIgfCAi
::B64:agent.js:ICsgJF8uTWFpbldpbmRvd1RpdGxlIH1gKSkgfHwKICAgICIodGlkYWsgYWRhIGplbmRlbGEpIiwKCiAgZm9jdXNfd2luZG93OiBhc3luYyAoeyB0aXRsZSB9KSA9PgogICAgcHMoYGlmICgoTmV3LU9iamVjdCAtQ29tT2JqZWN0IFdTY3JpcHQuU2hlbGwpLkFwcEFj
::B64:agent.js:dGl2YXRlKCRlbnY6VElUTEUpKSB7ICJvayIgfSBlbHNlIHsgImplbmRlbGEgdGlkYWsgZGl0ZW11a2FuIiB9YCwgewogICAgICBUSVRMRTogU3RyaW5nKHRpdGxlKSwKICAgIH0pLAoKICBjbG9zZV93aW5kb3c6IGFzeW5jICh7IHRpdGxlIH0pID0+IHsKICAgIGlm
::B64:agent.js:ICghKGF3YWl0IGFzayhgVHV0dXAgamVuZGVsYTogJHt0aXRsZX1gKSkpIHJldHVybiAiRGliYXRhbGthbiB1c2VyIjsKICAgIHJldHVybiBwcygKICAgICAgYCRwID0gR2V0LVByb2Nlc3MgfCBXaGVyZS1PYmplY3QgeyAkXy5NYWluV2luZG93VGl0bGUgLWxpa2Ug
::B64:agent.js:KCIqIiArICRlbnY6VElUTEUgKyAiKiIpIH0gfCBTZWxlY3QtT2JqZWN0IC1GaXJzdCAxCmlmICgkcCkgeyAkcC5DbG9zZU1haW5XaW5kb3coKSB8IE91dC1OdWxsOyAib2s6ICIgKyAkcC5NYWluV2luZG93VGl0bGUgfSBlbHNlIHsgImplbmRlbGEgdGlkYWsgZGl0
::B64:agent.js:ZW11a2FuIiB9YCwKICAgICAgeyBUSVRMRTogU3RyaW5nKHRpdGxlKSB9CiAgICApOwogIH0sCgogIC8vIC0tLSBGaWxlIC0tLQogIHJlYWRfdGV4dF9maWxlOiBhc3luYyAoeyBwYXRoOiBwIH0pID0+IHsKICAgIGNvbnN0IGZ1bGwgPSBwYXRoLnJlc29sdmUoU3Ry
::B64:agent.js:aW5nKHApKTsKICAgIGNvbnN0IHN0ID0gZnMuc3RhdFN5bmMoZnVsbCk7CiAgICBpZiAoIXN0LmlzRmlsZSgpKSB0aHJvdyBuZXcgRXJyb3IoIkJ1a2FuIGZpbGU6ICIgKyBmdWxsKTsKICAgIGlmIChzdC5zaXplID4gMl8wMDBfMDAwKSB0aHJvdyBuZXcgRXJyb3Io
::B64:agent.js:IkZpbGUgdGVybGFsdSBiZXNhciB1bnR1ayBkaWJhY2EgKCIgKyBzdC5zaXplICsgIiBieXRlKSIpOwogICAgcmV0dXJuIGZzLnJlYWRGaWxlU3luYyhmdWxsLCAidXRmOCIpLnNsaWNlKDAsIDgwMDApOwogIH0sCgogIHdyaXRlX3RleHRfZmlsZTogYXN5bmMgKHsg
::B64:agent.js:cGF0aDogcCwgY29udGVudCwgYXBwZW5kID0gZmFsc2UgfSkgPT4gewogICAgY29uc3QgZnVsbCA9IHBhdGgucmVzb2x2ZShTdHJpbmcocCkpOwogICAgY29uc3QgYWRkID0gYXBwZW5kID09PSB0cnVlIHx8IGFwcGVuZCA9PT0gInRydWUiOwogICAgY29uc3QgdmVy
::B64:agent.js:YiA9IGFkZCA/ICJUYW1iYWgga2UiIDogZnMuZXhpc3RzU3luYyhmdWxsKSA/ICJUSU1QQSIgOiAiQnVhdCI7CiAgICBpZiAoIShhd2FpdCBhc2soYCR7dmVyYn0gZmlsZTogJHtmdWxsfWApKSkgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgZnMubWtkaXJT
::B64:agent.js:eW5jKHBhdGguZGlybmFtZShmdWxsKSwgeyByZWN1cnNpdmU6IHRydWUgfSk7CiAgICBpZiAoYWRkKSBmcy5hcHBlbmRGaWxlU3luYyhmdWxsLCBTdHJpbmcoY29udGVudCkpOwogICAgZWxzZSBmcy53cml0ZUZpbGVTeW5jKGZ1bGwsIFN0cmluZyhjb250ZW50KSk7
::B64:agent.js:CiAgICByZXR1cm4gIm9rOiAiICsgZnVsbDsKICB9LAoKICBtYWtlX2ZvbGRlcjogYXN5bmMgKHsgcGF0aDogcCB9KSA9PiB7CiAgICBjb25zdCBmdWxsID0gcGF0aC5yZXNvbHZlKFN0cmluZyhwKSk7CiAgICBpZiAoIShhd2FpdCBhc2soYEJ1YXQgZm9sZGVyOiAk
::B64:agent.js:e2Z1bGx9YCkpKSByZXR1cm4gIkRpYmF0YWxrYW4gdXNlciI7CiAgICBmcy5ta2RpclN5bmMoZnVsbCwgeyByZWN1cnNpdmU6IHRydWUgfSk7CiAgICByZXR1cm4gIm9rOiAiICsgZnVsbDsKICB9LAoKICBtb3ZlX3BhdGg6IGFzeW5jICh7IGZyb20sIHRvIH0pID0+
::B64:agent.js:IHsKICAgIGlmICghKGF3YWl0IGFzayhgUGluZGFoa2FuOiAke2Zyb219ICBrZSAgJHt0b31gKSkpIHJldHVybiAiRGliYXRhbGthbiB1c2VyIjsKICAgIGF3YWl0IHBzKCJNb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRlbnY6U1JDIC1EZXN0aW5hdGlvbiAkZW52OkRF
::B64:agent.js:U1QiLCB7CiAgICAgIFNSQzogcGF0aC5yZXNvbHZlKFN0cmluZyhmcm9tKSksCiAgICAgIERFU1Q6IHBhdGgucmVzb2x2ZShTdHJpbmcodG8pKSwKICAgIH0pOwogICAgcmV0dXJuICJvayI7CiAgfSwKCiAgcmVjeWNsZV9wYXRoOiBhc3luYyAoeyBwYXRoOiBwIH0p
::B64:agent.js:ID0+IHsKICAgIGNvbnN0IGZ1bGwgPSBwYXRoLnJlc29sdmUoU3RyaW5nKHApKTsKICAgIGlmICghKGF3YWl0IGFzayhgUGluZGFoa2FuIGtlIFJlY3ljbGUgQmluOiAke2Z1bGx9YCkpKSByZXR1cm4gIkRpYmF0YWxrYW4gdXNlciI7CiAgICBhd2FpdCBwcygKICAg
::B64:agent.js:ICAgYEFkZC1UeXBlIC1Bc3NlbWJseU5hbWUgTWljcm9zb2Z0LlZpc3VhbEJhc2ljCiRwID0gJGVudjpUQVJHRVQKaWYgKFRlc3QtUGF0aCAtTGl0ZXJhbFBhdGggJHAgLVBhdGhUeXBlIENvbnRhaW5lcikgeyBbTWljcm9zb2Z0LlZpc3VhbEJhc2ljLkZpbGVJTy5G
::B64:agent.js:aWxlU3lzdGVtXTo6RGVsZXRlRGlyZWN0b3J5KCRwLCAnT25seUVycm9yRGlhbG9ncycsICdTZW5kVG9SZWN5Y2xlQmluJykgfQplbHNlIHsgW01pY3Jvc29mdC5WaXN1YWxCYXNpYy5GaWxlSU8uRmlsZVN5c3RlbV06OkRlbGV0ZUZpbGUoJHAsICdPbmx5RXJyb3JE
::B64:agent.js:aWFsb2dzJywgJ1NlbmRUb1JlY3ljbGVCaW4nKSB9YCwKICAgICAgeyBUQVJHRVQ6IGZ1bGwgfQogICAgKTsKICAgIHJldHVybiAib2ssIGRpcGluZGFoIGtlIFJlY3ljbGUgQmluIChtYXNpaCBiaXNhIGRpcHVsaWhrYW4pIjsKICB9LAoKICB6aXBfcGF0aDogYXN5
::B64:agent.js:bmMgKHsgc291cmNlLCB6aXAgfSkgPT4gewogICAgY29uc3Qgc3JjID0gcGF0aC5yZXNvbHZlKFN0cmluZyhzb3VyY2UpKTsKICAgIGNvbnN0IGRlc3QgPSBwYXRoLnJlc29sdmUoU3RyaW5nKHppcCkpOwogICAgaWYgKCEoYXdhaXQgYXNrKGBaaXAgJHtzcmN9ICBt
::B64:agent.js:ZW5qYWRpICAke2Rlc3R9YCkpKSByZXR1cm4gIkRpYmF0YWxrYW4gdXNlciI7CiAgICBhd2FpdCBwcygiQ29tcHJlc3MtQXJjaGl2ZSAtTGl0ZXJhbFBhdGggJGVudjpTUkMgLURlc3RpbmF0aW9uUGF0aCAkZW52OkRFU1QgLUZvcmNlIiwgeyBTUkM6IHNyYywgREVT
::B64:agent.js:VDogZGVzdCB9LCA2MDAwMDApOwogICAgcmV0dXJuICJvazogIiArIGRlc3Q7CiAgfSwKCiAgdW56aXBfcGF0aDogYXN5bmMgKHsgemlwLCBmb2xkZXIgfSkgPT4gewogICAgY29uc3Qgc3JjID0gcGF0aC5yZXNvbHZlKFN0cmluZyh6aXApKTsKICAgIGNvbnN0IGRl
::B64:agent.js:c3QgPSBwYXRoLnJlc29sdmUoU3RyaW5nKGZvbGRlcikpOwogICAgaWYgKCEoYXdhaXQgYXNrKGBFa3N0cmFrICR7c3JjfSAga2UgICR7ZGVzdH1gKSkpIHJldHVybiAiRGliYXRhbGthbiB1c2VyIjsKICAgIGF3YWl0IHBzKCJFeHBhbmQtQXJjaGl2ZSAtTGl0ZXJh
::B64:agent.js:bFBhdGggJGVudjpTUkMgLURlc3RpbmF0aW9uUGF0aCAkZW52OkRFU1QgLUZvcmNlIiwgeyBTUkM6IHNyYywgREVTVDogZGVzdCB9LCA2MDAwMDApOwogICAgcmV0dXJuICJvazogIiArIGRlc3Q7CiAgfSwKCiAgLy8gLS0tIFVwbG9hZCBjZXBhdDogc2F0dSBwYW5n
::B64:agent.js:Z2lsYW4gbWVuZ2dhbnRpa2FuIGJhbnlhayBsYW5na2FoIEFJIC0tLQogIGZhc3RfdXBsb2FkOiBhc3luYyAoeyB1cmwsIGZpbGVuYW1lLCBmb2xkZXIsIHBhdHRlcm4sIHN1Ym1pdCA9IHRydWUsIG5ld190YWIgPSB0cnVlIH0pID0+IHsKICAgIGNvbnN0IHQwID0g
::B64:agent.js:RGF0ZS5ub3coKTsKICAgIGNvbnN0IGRvU3VibWl0ID0gIShzdWJtaXQgPT09IGZhbHNlIHx8IHN1Ym1pdCA9PT0gImZhbHNlIik7CiAgICBsZXQgZmlsZXMgPSBbXTsKICAgIGlmIChmaWxlbmFtZSkgewogICAgICBmb3IgKGNvbnN0IHRvayBvZiBTdHJpbmcoZmls
::B64:agent.js:ZW5hbWUpLnNwbGl0KCJ8IikubWFwKCh4KSA9PiB4LnRyaW0oKSkuZmlsdGVyKEJvb2xlYW4pKSB7CiAgICAgICAgY29uc3QgYWJzID0gcGF0aC5yZXNvbHZlKFNBRkVfRElSLCB0b2sucmVwbGFjZSgvXiJ8IiQvZywgIiIpKTsKICAgICAgICBpZiAoZnMuZXhpc3Rz
::B64:agent.js:U3luYyhhYnMpICYmIGZzLnN0YXRTeW5jKGFicykuaXNEaXJlY3RvcnkoKSkgZmlsZXMucHVzaChhd2FpdCB6aXBGb3JVcGxvYWQoYWJzKSk7CiAgICAgICAgZWxzZSBmaWxlcy5wdXNoKHNhZmVQYXRoKHRvaykpOwogICAgICB9CiAgICB9CiAgICBpZiAoZm9sZGVy
::B64:agent.js:KSB7CiAgICAgIGNvbnN0IGRpciA9IHBhdGgucmVzb2x2ZShTdHJpbmcoZm9sZGVyKSk7CiAgICAgIGNvbnN0IHBhdHMgPSBwYXR0ZXJuID8gU3RyaW5nKHBhdHRlcm4pLnRvTG93ZXJDYXNlKCkuc3BsaXQoInwiKS5tYXAoKHgpID0+IHgudHJpbSgpLnJlcGxhY2Uo
::B64:agent.js:L15cKi8sICIiKSkuZmlsdGVyKEJvb2xlYW4pIDogW107CiAgICAgIGZvciAoY29uc3QgZSBvZiBmcy5yZWFkZGlyU3luYyhkaXIsIHsgd2l0aEZpbGVUeXBlczogdHJ1ZSB9KSkgewogICAgICAgIGlmIChlLmlzRmlsZSgpICYmICghcGF0cy5sZW5ndGggfHwgcGF0
::B64:agent.js:cy5zb21lKChwKSA9PiBlLm5hbWUudG9Mb3dlckNhc2UoKS5pbmNsdWRlcyhwKSkpKSBmaWxlcy5wdXNoKHBhdGguam9pbihkaXIsIGUubmFtZSkpOwogICAgICB9CiAgICB9CiAgICBmaWxlcyA9IFsuLi5uZXcgU2V0KGZpbGVzKV0uc2xpY2UoMCwgNTApOwogICAg
::B64:agent.js:aWYgKCFmaWxlcy5sZW5ndGgpIHRocm93IG5ldyBFcnJvcigiVGlkYWsgYWRhIGZpbGUgeWFuZyBjb2NvayB1bnR1ayBkaXVwbG9hZCIpOwogICAgY29uc3Qgc2l6ZU1CID0gZmlsZXMucmVkdWNlKChhLCBmKSA9PiBhICsgZnMuc3RhdFN5bmMoZikuc2l6ZSwgMCkg
::B64:agent.js:LyAxMDQ4NTc2OwogICAgY29uc3QgZGFmdGFyID0gZmlsZXMuc2xpY2UoMCwgMTUpLmpvaW4oIlxuICAgIikgKyAoZmlsZXMubGVuZ3RoID4gMTUgPyBgXG4gICAuLi4gKyR7ZmlsZXMubGVuZ3RoIC0gMTV9IGxhZ2lgIDogIiIpOwogICAgaWYgKCEoYXdhaXQgYXNr
::B64:agent.js:KGBVUExPQUQgQ0VQQVQgJHtmaWxlcy5sZW5ndGh9IGZpbGUgKCR7c2l6ZU1CLnRvRml4ZWQoMSl9IE1CKSR7dXJsID8gIiBrZSAiICsgdXJsIDogIiJ9OlxuICAgJHtkYWZ0YXJ9XG4gIGApKSkgewogICAgICByZXR1cm4gIkRpYmF0YWxrYW4gdXNlciI7CiAgICB9
::B64:agent.js:CiAgICBpZiAodXJsKSB7CiAgICAgIGlmIChpc1RydWUobmV3X3RhYikgJiYgIWlzQmxhbmtQYWdlKCkpIHBhZ2UgPSBhd2FpdCBjb250ZXh0Lm5ld1BhZ2UoKTsKICAgICAgYXdhaXQgcGFnZS5icmluZ1RvRnJvbnQoKTsKICAgICAgYXdhaXQgcGFnZS5nb3RvKGZp
::B64:agent.js:eFVybCh1cmwpLCB7IHdhaXRVbnRpbDogImRvbWNvbnRlbnRsb2FkZWQiIH0pOwogICAgICBhd2FpdCBzbGVlcCg0MDApOwogICAgfQogICAgY29uc3QgdHIgPSB0cmFja1VwbG9hZHMoKTsKICAgIHRyeSB7CiAgICAgIGNvbnN0IHF1ZXVlID0gWy4uLmZpbGVzXTsK
::B64:agent.js:ICAgICAgbGV0IHJvdW5kcyA9IDA7CiAgICAgIGxldCBsb2dpbkFza2VkID0gZmFsc2U7CiAgICAgIGxldCBub3RlID0gIiI7CiAgICAgIHdoaWxlIChxdWV1ZS5sZW5ndGggJiYgcm91bmRzIDwgNjApIHsKICAgICAgICByb3VuZHMrKzsKICAgICAgICBsZXQgdXNl
::B64:agent.js:ZCA9IGF3YWl0IHByb3ZpZGVGaWxlcyhxdWV1ZSk7CiAgICAgICAgaWYgKCF1c2VkICYmICFsb2dpbkFza2VkICYmIChhd2FpdCBoYXNMb2dpbkZvcm0oKSkpIHsKICAgICAgICAgIGxvZ2luQXNrZWQgPSB0cnVlOwogICAgICAgICAgYXdhaXQgaW1wbC53YWl0X2Zv
::B64:agent.js:cl91c2VyKHsgbWVzc2FnZTogIkhhbGFtYW4gaW5pIG1lbWludGEgbG9naW4uIExvZ2luIGR1bHUgZGkgamVuZGVsYSBicm93c2VyLCBsYWx1IHRla2FuIEVudGVyLiIgfSk7CiAgICAgICAgICB1c2VkID0gYXdhaXQgcHJvdmlkZUZpbGVzKHF1ZXVlKTsKICAgICAg
::B64:agent.js:ICB9CiAgICAgICAgaWYgKCF1c2VkKSB7CiAgICAgICAgICB0aHJvdyBuZXcgRXJyb3IoIlRvbWJvbCBhdGF1IGlucHV0IHVwbG9hZCB0aWRhayBkaXRlbXVrYW4gZGkgaGFsYW1hbiBpbmkuIFBhc3Rpa2FuIHN1ZGFoIGxvZ2luIGRhbiBiZXJhZGEgZGkgaGFsYW1h
::B64:agent.js:biB5YW5nIGJlbmFyIChjb2JhIC9sb2dpbikuIik7CiAgICAgICAgfQogICAgICAgIHF1ZXVlLnNwbGljZSgwLCB1c2VkKTsKICAgICAgICBpZiAoZG9TdWJtaXQpIHsKICAgICAgICAgIGF3YWl0IHNsZWVwKDQwMCk7CiAgICAgICAgICBhd2FpdCBjbGlja0J5VGV4
::B64:agent.js:dChTVUJNSVRfQlROLCAxNTAwKTsKICAgICAgICB9CiAgICAgICAgY29uc3QgciA9IGF3YWl0IHdhaXRVcGxvYWREb25lKHRyLCBVUExPQURfVElNRU9VVF9NUyk7CiAgICAgICAgaWYgKHIgPT09IGZhbHNlKSB7CiAgICAgICAgICBub3RlID0gIkJhdGFzIHdha3R1
::B64:agent.js:IG1lbnVuZ2d1IGhhYmlzOyB1cGxvYWQgbXVuZ2tpbiBtYXNpaCBiZXJqYWxhbiBkaSBoYWxhbWFuLiI7CiAgICAgICAgICBicmVhazsKICAgICAgICB9CiAgICAgICAgaWYgKHR5cGVvZiByID09PSAic3RyaW5nIikgbm90ZSA9IHI7CiAgICAgIH0KICAgICAgY29u
::B64:agent.js:c3QgbGlua3MgPSBhd2FpdCBwYWdlCiAgICAgICAgLmV2YWx1YXRlKChzcmMpID0+IHsKICAgICAgICAgIGNvbnN0IHJlID0gbmV3IFJlZ0V4cChzcmMsICJpIik7CiAgICAgICAgICBjb25zdCBvdXQgPSBuZXcgU2V0KCk7CiAgICAgICAgICBkb2N1bWVudC5xdWVy
::B64:agent.js:eVNlbGVjdG9yQWxsKCJhW2hyZWZdLCBpbnB1dCwgdGV4dGFyZWEiKS5mb3JFYWNoKChlKSA9PiB7CiAgICAgICAgICAgIGNvbnN0IHYgPSBlLmhyZWYgfHwgZS52YWx1ZSB8fCAiIjsKICAgICAgICAgICAgaWYgKHJlLnRlc3QodikpIG91dC5hZGQodik7CiAgICAg
::B64:agent.js:ICAgICB9KTsKICAgICAgICAgICgoZG9jdW1lbnQuYm9keSAmJiBkb2N1bWVudC5ib2R5LmlubmVyVGV4dC5tYXRjaCgvaHR0cHM/OlwvXC9bXlxzIic8Pl0rL2cpKSB8fCBbXSkuZm9yRWFjaCgodSkgPT4gewogICAgICAgICAgICBpZiAocmUudGVzdCh1KSkgb3V0
::B64:agent.js:LmFkZCh1KTsKICAgICAgICAgIH0pOwogICAgICAgICAgcmV0dXJuIFsuLi5vdXRdLnNsaWNlKDAsIDEwKTsKICAgICAgICB9LCBIT1NUU19SRS5zb3VyY2UpCiAgICAgICAgLmNhdGNoKCgpID0+IFtdKTsKICAgICAgY29uc3Qgc2VjcyA9ICgoRGF0ZS5ub3coKSAt
::B64:agent.js:IHQwKSAvIDEwMDApLnRvRml4ZWQoMSk7CiAgICAgIHJldHVybiAoCiAgICAgICAgYFVwbG9hZCAke2ZpbGVzLmxlbmd0aCAtIHF1ZXVlLmxlbmd0aH0vJHtmaWxlcy5sZW5ndGh9IGZpbGUgc2VsZXNhaSBkYWxhbSAke3NlY3N9IGR0ay5gICsKICAgICAgICAobm90
::B64:agent.js:ZSA/IGAgQ2F0YXRhbjogJHtub3RlfWAgOiAiIikgKwogICAgICAgIChsaW5rcy5sZW5ndGggPyBgXG5MaW5rIHRlcmRldGVrc2k6XG4ke2xpbmtzLmpvaW4oIlxuIil9YCA6ICJcbkxpbmsgYmVsdW0gdGVyZGV0ZWtzaSBvdG9tYXRpczsgbGloYXQgaGFsYW1hbiBk
::B64:agent.js:aSBicm93c2VyLiIpCiAgICAgICk7CiAgICB9IGZpbmFsbHkgewogICAgICB0ci5zdG9wKCk7CiAgICB9CiAgfSwKCiAgcmVjZW50X2ZpbGVzOiBhc3luYyAoeyBmb2xkZXIsIGNvdW50ID0gMTAgfSkgPT4gewogICAgY29uc3QgZGlyID0gcGF0aC5yZXNvbHZlKFN0
::B64:agent.js:cmluZyhmb2xkZXIgfHwgcGF0aC5qb2luKEhPTUUsICJEb3dubG9hZHMiKSkpOwogICAgY29uc3QgaXRlbXMgPSByZWNlbnRMaXN0KGRpciwgY291bnQpOwogICAgcmV0dXJuIGl0ZW1zLmxlbmd0aAogICAgICA/IGl0ZW1zLm1hcCgoeCwgaSkgPT4gYCR7aSArIDF9
::B64:agent.js:LiAke3guZn0gKCR7bmV3IERhdGUoeC50KS50b0xvY2FsZVN0cmluZygiaWQtSUQiKX0sICR7KHgucyAvIDEwNDg1NzYpLnRvRml4ZWQoMSl9IE1CKWApLmpvaW4oIlxuIikKICAgICAgOiAiKHRpZGFrIGFkYSBmaWxlKSI7CiAgfSwKCiAgc2VhcmNoX3RleHQ6IGFz
::B64:agent.js:eW5jICh7IGZvbGRlciwgdGV4dCB9KSA9PiB7CiAgICBjb25zdCByb290ID0gcGF0aC5yZXNvbHZlKFN0cmluZyhmb2xkZXIpKTsKICAgIGNvbnN0IHEgPSBTdHJpbmcodGV4dCkudG9Mb3dlckNhc2UoKTsKICAgIGNvbnN0IG9rRXh0ID0gL1wuKHR4dHxtZHxqc3x0
::B64:agent.js:c3xqc29ufGNzdnxsb2d8aHRtbHxjc3N8cHl8amF2YXx4bWx8aW5pfHltbHx5YW1sfGNmZ3xiYXR8cGhwfHNxbCkkL2k7CiAgICBjb25zdCBoaXRzID0gW107CiAgICBjb25zdCBkZWFkbGluZSA9IERhdGUubm93KCkgKyAxNTAwMDsKICAgIGNvbnN0IHdhbGsgPSAo
::B64:agent.js:ZGlyLCBkZXB0aCkgPT4gewogICAgICBpZiAoZGVwdGggPCAwIHx8IGhpdHMubGVuZ3RoID49IDIwIHx8IERhdGUubm93KCkgPiBkZWFkbGluZSkgcmV0dXJuOwogICAgICBsZXQgZW50cmllczsKICAgICAgdHJ5IHsKICAgICAgICBlbnRyaWVzID0gZnMucmVhZGRp
::B64:agent.js:clN5bmMoZGlyLCB7IHdpdGhGaWxlVHlwZXM6IHRydWUgfSk7CiAgICAgIH0gY2F0Y2ggewogICAgICAgIHJldHVybjsKICAgICAgfQogICAgICBmb3IgKGNvbnN0IGUgb2YgZW50cmllcykgewogICAgICAgIGNvbnN0IGZ1bGwgPSBwYXRoLmpvaW4oZGlyLCBlLm5h
::B64:agent.js:bWUpOwogICAgICAgIGlmIChlLmlzRGlyZWN0b3J5KCkpIHsKICAgICAgICAgIGlmICghU0tJUF9ESVJTLmhhcyhlLm5hbWUudG9Mb3dlckNhc2UoKSkgJiYgIWUubmFtZS5zdGFydHNXaXRoKCIkIikpIHdhbGsoZnVsbCwgZGVwdGggLSAxKTsKICAgICAgICB9IGVs
::B64:agent.js:c2UgaWYgKG9rRXh0LnRlc3QoZS5uYW1lKSkgewogICAgICAgICAgdHJ5IHsKICAgICAgICAgICAgaWYgKGZzLnN0YXRTeW5jKGZ1bGwpLnNpemUgPiAyXzAwMF8wMDApIGNvbnRpbnVlOwogICAgICAgICAgICBjb25zdCBsaW5lcyA9IGZzLnJlYWRGaWxlU3luYyhm
::B64:agent.js:dWxsLCAidXRmOCIpLnNwbGl0KC9ccj9cbi8pOwogICAgICAgICAgICBmb3IgKGxldCBpID0gMDsgaSA8IGxpbmVzLmxlbmd0aCAmJiBoaXRzLmxlbmd0aCA8IDIwOyBpKyspIHsKICAgICAgICAgICAgICBpZiAobGluZXNbaV0udG9Mb3dlckNhc2UoKS5pbmNsdWRl
::B64:agent.js:cyhxKSkgaGl0cy5wdXNoKGAke2Z1bGx9OiR7aSArIDF9OiAke2xpbmVzW2ldLnRyaW0oKS5zbGljZSgwLCAxMjApfWApOwogICAgICAgICAgICB9CiAgICAgICAgICB9IGNhdGNoIHt9CiAgICAgICAgfQogICAgICB9CiAgICB9OwogICAgd2Fsayhyb290LCA1KTsK
::B64:agent.js:ICAgIHJldHVybiBoaXRzLmxlbmd0aCA/IGhpdHMuam9pbigiXG4iKSA6ICJUaWRhayBkaXRlbXVrYW4iOwogIH0sCgogIGNvcHlfcGF0aDogYXN5bmMgKHsgZnJvbSwgdG8gfSkgPT4gewogICAgaWYgKCEoYXdhaXQgYXNrKGBTYWxpbjogJHtmcm9tfSAga2UgICR7
::B64:agent.js:dG99YCkpKSByZXR1cm4gIkRpYmF0YWxrYW4gdXNlciI7CiAgICBhd2FpdCBwcygiQ29weS1JdGVtIC1MaXRlcmFsUGF0aCAkZW52OlNSQyAtRGVzdGluYXRpb24gJGVudjpERVNUIC1SZWN1cnNlIC1Gb3JjZSIsIHsKICAgICAgU1JDOiBwYXRoLnJlc29sdmUoU3Ry
::B64:agent.js:aW5nKGZyb20pKSwKICAgICAgREVTVDogcGF0aC5yZXNvbHZlKFN0cmluZyh0bykpLAogICAgfSwgNjAwMDAwKTsKICAgIHJldHVybiAib2siOwogIH0sCgogIHNhdmVfc2NyZWVuc2hvdDogYXN5bmMgKHsgcGF0aDogcCB9KSA9PiB7CiAgICBjb25zdCBzdGFtcCA9
::B64:agent.js:IG5ldyBEYXRlKCkudG9JU09TdHJpbmcoKS5yZXBsYWNlKC9bOi5dL2csICItIikuc2xpY2UoMCwgMTkpOwogICAgY29uc3QgZGVzdCA9IHAgPyBwYXRoLnJlc29sdmUoU3RyaW5nKHApKSA6IHBhdGguam9pbihIT01FLCAiUGljdHVyZXMiLCAiU2NyZWVuc2hvdHMi
::B64:agent.js:LCBgbGF5YXItJHtzdGFtcH0ucG5nYCk7CiAgICBmcy5ta2RpclN5bmMocGF0aC5kaXJuYW1lKGRlc3QpLCB7IHJlY3Vyc2l2ZTogdHJ1ZSB9KTsKICAgIGF3YWl0IHBzKAogICAgICBQU19IRUFEICsKICAgICAgICBgCiRiID0gW1N5c3RlbS5XaW5kb3dzLkZvcm1z
::B64:agent.js:LlNjcmVlbl06OlByaW1hcnlTY3JlZW4uQm91bmRzCiRibXAgPSBOZXctT2JqZWN0IFN5c3RlbS5EcmF3aW5nLkJpdG1hcCAkYi5XaWR0aCwgJGIuSGVpZ2h0CiRnID0gW1N5c3RlbS5EcmF3aW5nLkdyYXBoaWNzXTo6RnJvbUltYWdlKCRibXApCiRnLkNvcHlGcm9t
::B64:agent.js:U2NyZWVuKCRiLlgsICRiLlksIDAsIDAsICRibXAuU2l6ZSkKJGJtcC5TYXZlKCRlbnY6T1VULCBbU3lzdGVtLkRyYXdpbmcuSW1hZ2luZy5JbWFnZUZvcm1hdF06OlBuZykKYCwKICAgICAgeyBPVVQ6IGRlc3QgfQogICAgKTsKICAgIHJldHVybiAiVGVyc2ltcGFu
::B64:agent.js:OiAiICsgZGVzdDsKICB9LAoKICBzZXRfdm9sdW1lOiBhc3luYyAoeyBsZXZlbCB9KSA9PiB7CiAgICBjb25zdCBuID0gTWF0aC5taW4oTWF0aC5tYXgoTWF0aC5yb3VuZChOdW1iZXIobGV2ZWwpKSwgMCksIDEwMCk7CiAgICBhd2FpdCBwcygKICAgICAgYApBZGQt
::B64:agent.js:VHlwZSBAIgp1c2luZyBTeXN0ZW0uUnVudGltZS5JbnRlcm9wU2VydmljZXM7CnB1YmxpYyBjbGFzcyBLIHsgW0RsbEltcG9ydCgidXNlcjMyLmRsbCIpXSBwdWJsaWMgc3RhdGljIGV4dGVybiB2b2lkIGtleWJkX2V2ZW50KGJ5dGUgYiwgYnl0ZSBzLCB1aW50IGYs
::B64:agent.js:IGludCBlKTsgfQoiQApmb3IgKCRpID0gMDsgJGkgLWx0IDUwOyAkaSsrKSB7IFtLXTo6a2V5YmRfZXZlbnQoMHhBRSwgMCwgMCwgMCk7IFtLXTo6a2V5YmRfZXZlbnQoMHhBRSwgMCwgMiwgMCk7IFN0YXJ0LVNsZWVwIC1NaWxsaXNlY29uZHMgMTIgfQpmb3IgKCRp
::B64:agent.js:ID0gMDsgJGkgLWx0IFtpbnRdJGVudjpVUDsgJGkrKykgeyBbS106OmtleWJkX2V2ZW50KDB4QUYsIDAsIDAsIDApOyBbS106OmtleWJkX2V2ZW50KDB4QUYsIDAsIDIsIDApOyBTdGFydC1TbGVlcCAtTWlsbGlzZWNvbmRzIDEyIH0KYCwKICAgICAgeyBVUDogU3Ry
::B64:agent.js:aW5nKE1hdGgucm91bmQobiAvIDIpKSB9CiAgICApOwogICAgcmV0dXJuIGBWb2x1bWUgZGlhdHVyIHNla2l0YXIgJHtufSVgOwogIH0sCgogIHNwZWFrOiBhc3luYyAoeyB0ZXh0IH0pID0+IHsKICAgIGF3YWl0IHBzKCJBZGQtVHlwZSAtQXNzZW1ibHlOYW1lIFN5
::B64:agent.js:c3RlbS5TcGVlY2g7ICRzID0gTmV3LU9iamVjdCBTeXN0ZW0uU3BlZWNoLlN5bnRoZXNpcy5TcGVlY2hTeW50aGVzaXplcjsgJHMuU3BlYWsoJGVudjpUWFQpIiwgeyBUWFQ6IFN0cmluZyh0ZXh0KS5zbGljZSgwLCA1MDApIH0sIDYwMDAwKTsKICAgIHJldHVybiAi
::B64:agent.js:b2ssIGRpdWNhcGthbiI7CiAgfSwKCiAgc2V0X3RpbWVyOiBhc3luYyAoeyBhbW91bnQsIHVuaXQgPSAibWVuaXQiLCBtZXNzYWdlID0gIldha3R1bnlhISIgfSkgPT4gewogICAgY29uc3QgbXVsdCA9IC9kZXRpay9pLnRlc3QoU3RyaW5nKHVuaXQpKSA/IDEwMDAg
::B64:agent.js:OiAvamFtL2kudGVzdChTdHJpbmcodW5pdCkpID8gMzYwMDAwMCA6IDYwMDAwOwogICAgY29uc3QgbXMgPSBNYXRoLnJvdW5kKE51bWJlcihTdHJpbmcoYW1vdW50KS5yZXBsYWNlKCIsIiwgIi4iKSkgKiBtdWx0KTsKICAgIGlmICghKG1zID4gMCkgfHwgbXMgPiAy
::B64:agent.js:NCAqIDM2MDAwMDApIHRocm93IG5ldyBFcnJvcigiRHVyYXNpIHRpZGFrIHZhbGlkIChtYWtzaW1hbCAyNCBqYW0pIik7CiAgICB0aW1lcnMucHVzaCgKICAgICAgc2V0VGltZW91dChhc3luYyAoKSA9PiB7CiAgICAgICAgY29uc29sZS5sb2coYFxuKioqIFBFTkdJ
::B64:agent.js:TkdBVDogJHttZXNzYWdlfSAqKipgKTsKICAgICAgICB0cnkgewogICAgICAgICAgYXdhaXQgcHMoIltjb25zb2xlXTo6QmVlcCg4ODAsMzAwKTsgW2NvbnNvbGVdOjpCZWVwKDExNzUsNDAwKTsgQWRkLVR5cGUgLUFzc2VtYmx5TmFtZSBTeXN0ZW0uU3BlZWNoOyAo
::B64:agent.js:TmV3LU9iamVjdCBTeXN0ZW0uU3BlZWNoLlN5bnRoZXNpcy5TcGVlY2hTeW50aGVzaXplcikuU3BlYWsoJGVudjpUWFQpIiwgeyBUWFQ6IFN0cmluZyhtZXNzYWdlKSB9LCA2MDAwMCk7CiAgICAgICAgfSBjYXRjaCB7fQogICAgICB9LCBtcykKICAgICk7CiAgICBy
::B64:agent.js:ZXR1cm4gYFBlbmdpbmdhdCBkaWF0dXIgJHthbW91bnR9ICR7dW5pdH0gbGFnaTogIiR7bWVzc2FnZX0iIChha3RpZiBzZWxhbWEgYWdlbnQgdGVyYnVrYSlgOwogIH0sCgogIG1vcmVfdG9vbHM6IGFzeW5jICh7IGdyb3VwIH0pID0+IHsKICAgIGNvbnN0IGcgPSBT
::B64:agent.js:dHJpbmcoZ3JvdXApLnRvTG93ZXJDYXNlKCk7CiAgICBpZiAoIVRPT0xfR1JPVVBTW2ddKSByZXR1cm4gIkdydXAgdGlkYWsgZGlrZW5hbC4gUGlsaWg6ICIgKyBPYmplY3Qua2V5cyhUT09MX0dST1VQUykuam9pbigiLCAiKTsKICAgIGV4dHJhR3JvdXBzLmFkZChn
::B64:agent.js:KTsKICAgIHJldHVybiBgQWxhdCBncnVwICR7Z30gc2VrYXJhbmcgdGVyc2VkaWE6ICR7VE9PTF9HUk9VUFNbZ10uam9pbigiLCAiKX1gOwogIH0sCgogIGdldF9wYWdlX3RleHQ6IGFzeW5jICgpID0+IChhd2FpdCBwYWdlLmlubmVyVGV4dCgiYm9keSIpKS5zbGlj
::B64:agent.js:ZSgwLCA0MDAwKSwKCiAgdHlwZV90ZXh0OiBhc3luYyAoeyBzZWxlY3RvciwgdGV4dCB9KSA9PiB7CiAgICBhd2FpdCBwYWdlLmZpbGwoc2VsZWN0b3IsIHRleHQpOwogICAgcmV0dXJuICJvayI7CiAgfSwKCiAgY2xpY2s6IGFzeW5jICh7IHNlbGVjdG9yIH0pID0+
::B64:agent.js:IHsKICAgIGlmICghKGF3YWl0IGFzayhgS2xpayBlbGVtZW4gYnJvd3NlcjogJHtzZWxlY3Rvcn1gKSkpIHJldHVybiAiRGliYXRhbGthbiB1c2VyIjsKICAgIGF3YWl0IHBhZ2UuY2xpY2soc2VsZWN0b3IsIHsgdGltZW91dDogMTAwMDAgfSk7CiAgICByZXR1cm4g
::B64:agent.js:Im9rIjsKICB9LAoKICB1cGxvYWRfZmlsZTogYXN5bmMgKHsgc2VsZWN0b3IsIGZpbGVuYW1lLCBmb2xkZXIsIHBhdHRlcm4gfSkgPT4gewogICAgbGV0IGZpbGVzID0gW107CiAgICBpZiAoZmlsZW5hbWUpIHsKICAgICAgZmlsZXMgPSBTdHJpbmcoZmlsZW5hbWUp
::B64:agent.js:CiAgICAgICAgLnNwbGl0KCJ8IikKICAgICAgICAubWFwKCh4KSA9PiB4LnRyaW0oKSkKICAgICAgICAuZmlsdGVyKEJvb2xlYW4pCiAgICAgICAgLm1hcChzYWZlUGF0aCk7CiAgICB9CiAgICBpZiAoZm9sZGVyKSB7CiAgICAgIGNvbnN0IGRpciA9IHBhdGgucmVz
::B64:agent.js:b2x2ZShTdHJpbmcoZm9sZGVyKSk7CiAgICAgIGNvbnN0IHEgPSBwYXR0ZXJuID8gU3RyaW5nKHBhdHRlcm4pLnRvTG93ZXJDYXNlKCkucmVwbGFjZSgvXlwqLywgIiIpIDogIiI7CiAgICAgIGZvciAoY29uc3QgZSBvZiBmcy5yZWFkZGlyU3luYyhkaXIsIHsgd2l0
::B64:agent.js:aEZpbGVUeXBlczogdHJ1ZSB9KSkgewogICAgICAgIGlmIChlLmlzRmlsZSgpICYmICghcSB8fCBlLm5hbWUudG9Mb3dlckNhc2UoKS5pbmNsdWRlcyhxKSkpIGZpbGVzLnB1c2gocGF0aC5qb2luKGRpciwgZS5uYW1lKSk7CiAgICAgIH0KICAgIH0KICAgIGlmICgh
::B64:agent.js:ZmlsZXMubGVuZ3RoKSB0aHJvdyBuZXcgRXJyb3IoIlRpZGFrIGFkYSBmaWxlIHlhbmcgY29jb2sgdW50dWsgZGl1cGxvYWQiKTsKICAgIGZpbGVzID0gZmlsZXMuc2xpY2UoMCwgNTApOwogICAgaWYgKCEoYXdhaXQgYXNrKGBVcGxvYWQgJHtmaWxlcy5sZW5ndGh9
::B64:agent.js:IGZpbGU6XG4gICAke2ZpbGVzLmpvaW4oIlxuICAgIil9XG4gIGApKSkgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgY29uc3QgbXVsdGlwbGUgPSBhd2FpdCBwYWdlLiRldmFsKHNlbGVjdG9yLCAoZWwpID0+ICEhZWwubXVsdGlwbGUpLmNhdGNoKCgpID0+
::B64:agent.js:IGZhbHNlKTsKICAgIGlmIChmaWxlcy5sZW5ndGggPiAxICYmICFtdWx0aXBsZSkgewogICAgICBhd2FpdCBwYWdlLnNldElucHV0RmlsZXMoc2VsZWN0b3IsIGZpbGVzWzBdKTsKICAgICAgcmV0dXJuICgKICAgICAgICBgSW5wdXQgaW5pIGhhbnlhIG1lbmVyaW1h
::B64:agent.js:IDEgZmlsZS4gVGVycGlsaWg6ICR7ZmlsZXNbMF19LiBTaXNhICR7ZmlsZXMubGVuZ3RoIC0gMX0gZmlsZTogYCArCiAgICAgICAgYCR7ZmlsZXMuc2xpY2UoMSkuam9pbigiIHwgIil9LiBTZWxlc2Fpa2FuIHVwbG9hZCBpbmksIGxhbHUgdWxhbmdpIHVwbG9hZF9m
::B64:agent.js:aWxlIHVudHVrIHNpc2FueWEuYAogICAgICApOwogICAgfQogICAgYXdhaXQgcGFnZS5zZXRJbnB1dEZpbGVzKHNlbGVjdG9yLCBmaWxlcyk7CiAgICByZXR1cm4gYG9rLCAke2ZpbGVzLmxlbmd0aH0gZmlsZSBkaXBpbGloYDsKICB9LAp9OwoKY29uc3QgZm4gPSAo
::B64:agent.js:bmFtZSwgZGVzY3JpcHRpb24sIHByb3BlcnRpZXMgPSB7fSwgb3B0aW9uYWwgPSBbXSkgPT4gKHsKICB0eXBlOiAiZnVuY3Rpb24iLAogIGZ1bmN0aW9uOiB7CiAgICBuYW1lLAogICAgZGVzY3JpcHRpb24sCiAgICBwYXJhbWV0ZXJzOiB7CiAgICAgIHR5cGU6ICJv
::B64:agent.js:YmplY3QiLAogICAgICBwcm9wZXJ0aWVzLAogICAgICByZXF1aXJlZDogT2JqZWN0LmtleXMocHJvcGVydGllcykuZmlsdGVyKChrKSA9PiAhb3B0aW9uYWwuaW5jbHVkZXMoaykpLAogICAgfSwKICB9LAp9KTsKY29uc3Qgc3RyID0gKGQpID0+ICh7IHR5cGU6ICJz
::B64:agent.js:dHJpbmciLCBkZXNjcmlwdGlvbjogZCB9KTsKY29uc3QgbnVtID0gKGQpID0+ICh7IHR5cGU6ICJudW1iZXIiLCBkZXNjcmlwdGlvbjogZCB9KTsKY29uc3QgYm9vbCA9IChkKSA9PiAoeyB0eXBlOiAiYm9vbGVhbiIsIGRlc2NyaXB0aW9uOiBkIH0pOwoKY29uc3Qg
::B64:agent.js:dG9vbHMgPSBbCiAgZm4oImZpbmRfZm9sZGVyIiwgIkNhcmkgZm9sZGVyIGRpIHNlbHVydWggUEMgKHNlbXVhIGRyaXZlKSBiZXJkYXNhcmthbiBuYW1hOyBzZWJhZ2lhbiBuYW1hIGN1a3VwIiwgeyBuYW1lOiBzdHIoIk5hbWEgZm9sZGVyIikgfSksCiAgZm4oImZp
::B64:agent.js:bmRfZmlsZSIsICJDYXJpIGZpbGUgZGkgc2VsdXJ1aCBQQyAoc2VtdWEgZHJpdmUpIGJlcmRhc2Fya2FuIG5hbWE7IHNlYmFnaWFuIG5hbWEgY3VrdXAiLCB7IG5hbWU6IHN0cigiTmFtYSBmaWxlIikgfSksCiAgZm4oImxpc3RfZGlyIiwgIkxpaGF0IGlzaSBzZWJ1
::B64:agent.js:YWggZm9sZGVyIGRpIFBDIiwgeyBwYXRoOiBzdHIoIlBhdGggbGVuZ2thcCBmb2xkZXIiKSB9KSwKICBmbigib3Blbl9wYXRoIiwgIkJ1a2EgZm9sZGVyLCBmaWxlLCBhcGxpa2FzaSAobWlzLiBub3RlcGFkKSwgYXRhdSBVUkwgZGkgUEMiLCB7IHRhcmdldDogc3Ry
::B64:agent.js:KCJQYXRoL25hbWEgYXBsaWthc2kvVVJMIikgfSksCiAgZm4oInNjcmVlbnNob3QiLCAiQW1iaWwgc2NyZWVuc2hvdCBsYXlhciBQQyB1bnR1ayBtZWxpaGF0IGtvbmRpc2kgc2VrYXJhbmciKSwKICBmbigKICAgICJjbGlja19zY3JlZW4iLAogICAgIktsaWsgZGkg
::B64:agent.js:bGF5YXIgUEMgcGFkYSBrb29yZGluYXQgZGFyaSBzY3JlZW5zaG90IHRlcmFraGlyIiwKICAgIHsgeDogbnVtKCJLb29yZGluYXQgWCBkaSBzY3JlZW5zaG90IiksIHk6IG51bSgiS29vcmRpbmF0IFkgZGkgc2NyZWVuc2hvdCIpLCBidXR0b246IHN0cigibGVmdCBh
::B64:agent.js:dGF1IHJpZ2h0IiksIGRvdWJsZTogeyB0eXBlOiAiYm9vbGVhbiIsIGRlc2NyaXB0aW9uOiAiZG91YmxlLWtsaWsiIH0gfSwKICAgIFsiYnV0dG9uIiwgImRvdWJsZSJdCiAgKSwKICBmbigic2Nyb2xsX3NjcmVlbiIsICJTY3JvbGwgbGF5YXIuIFBvc2l0aWYgPSB0
::B64:agent.js:dXJ1biwgbmVnYXRpZiA9IG5haWsiLCB7IGFtb3VudDogbnVtKCJKdW1sYWggc2Nyb2xsIikgfSksCiAgZm4oInR5cGVfZGVza3RvcCIsICJLZXRpayB0ZWtzIGRpIGFwbGlrYXNpIHlhbmcgc2VkYW5nIGZva3VzIGRpIFBDIiwgeyB0ZXh0OiBzdHIoIlRla3MiKSB9
::B64:agent.js:KSwKICBmbigicHJlc3Nfa2V5cyIsICJUZWthbiB0b21ib2wgZm9ybWF0IFNlbmRLZXlzOiB7RU5URVJ9LCB7VEFCfSwge0VTQ30sIF5jIChDdHJsK0MpLCBediwgXmwsICV7RjR9IiwgeyBrZXlzOiBzdHIoIktvbWJpbmFzaSB0b21ib2wiKSB9KSwKICBmbigid2Fp
::B64:agent.js:dCIsICJUdW5nZ3UgYmViZXJhcGEgZGV0aWsgKG1ha3MgMTUpIHN1cGF5YSBoYWxhbWFuL2FwbGlrYXNpIHNlbGVzYWkgZGltdWF0IiwgeyBzZWNvbmRzOiBudW0oIkRldGlrIikgfSksCiAgZm4oImxpc3RfZmlsZXMiLCAiTGloYXQgZGFmdGFyIGZpbGUgZGkgZm9s
::B64:agent.js:ZGVyIHVwbG9hZCBraHVzdXMiKSwKICBmbigKICAgICJvcGVuX3VybCIsCiAgICAiQnVrYSB3ZWJzaXRlIGRpIGJyb3dzZXIuIFNlY2FyYSBiYXdhYW4gbWVuaW1wYSB0YWIgYWt0aWY7IHBha2FpIG5ld190YWI9dHJ1ZSBhZ2FyIGhhbGFtYW4vdmlkZW8geWFuZyBz
::B64:agent.js:ZWRhbmcgdGVyYnVrYSB0aWRhayB0ZXJ0aW1wYSIsCiAgICB7IHVybDogc3RyKCJVUkwgbGVuZ2thcCIpLCBuZXdfdGFiOiBib29sKCJ0cnVlID0gYnVrYSBkaSB0YWIgYmFydSIpIH0sCiAgICBbIm5ld190YWIiXQogICksCiAgZm4oImxpc3RfdGFicyIsICJEYWZ0
::B64:agent.js:YXIgc2VtdWEgdGFiIGJyb3dzZXIgKHRhbmRhICogPSB0YWIgYWt0aWYpIiksCiAgZm4oIm5ld190YWIiLCAiQnVrYSB0YWIgYmFydSAoa29zb25nLCBhdGF1IGxhbmdzdW5nIGtlIFVSTCkgZGFuIGphZGlrYW4gdGFiIGFrdGlmIiwgeyB1cmw6IHN0cigiVVJMIChv
::B64:agent.js:cHNpb25hbCkiKSB9LCBbInVybCJdKSwKICBmbigib3Blbl91cmxzIiwgIkJ1a2EgQkFOWUFLIHdlYnNpdGUgc2VrYWxpZ3VzLCBtYXNpbmctbWFzaW5nIGRpIHRhYiBiYXJ1IiwgewogICAgdXJsczogeyB0eXBlOiAiYXJyYXkiLCBpdGVtczogeyB0eXBlOiAic3Ry
::B64:agent.js:aW5nIiB9LCBkZXNjcmlwdGlvbjogIkRhZnRhciBVUkwgKG1ha3NpbWFsIDEwKSIgfSwKICB9KSwKICBmbigKICAgICJzd2l0Y2hfdGFiIiwKICAgICJQaW5kYWggdGFiIGFrdGlmLiBQYWthaSBpbmRleCAoMSA9IHRhYiBwZXJ0YW1hLCAtMSA9IHRhYiB0ZXJiYXJ1
::B64:agent.js:KSBBVEFVIG1hdGNoIChzZWJhZ2lhbiBqdWR1bC9VUkwpIiwKICAgIHsgaW5kZXg6IG51bSgiTm9tb3IgdGFiLCAtMSA9IHRlcmJhcnUiKSwgbWF0Y2g6IHN0cigiU2ViYWdpYW4ganVkdWwgYXRhdSBVUkwgdGFiIikgfSwKICAgIFsiaW5kZXgiLCAibWF0Y2giXQog
::B64:agent.js:ICksCiAgZm4oImNsb3NlX3RhYiIsICJUdXR1cCB0YWIgKGJhd2FhbjogdGFiIGFrdGlmKSwgYXRhdSB0YWIgZGVuZ2FuIG5vbW9yIHRlcnRlbnR1IiwgeyBpbmRleDogbnVtKCJOb21vciB0YWIsIC0xID0gdGVyYmFydSIpIH0sIFsiaW5kZXgiXSksCiAgZm4oImlu
::B64:agent.js:c3BlY3RfcGFnZSIsICJEYWZ0YXIgdG9tYm9sL2lucHV0IGRpIGhhbGFtYW4gYnJvd3NlciB1bnR1ayBtZW5jYXJpIENTUyBzZWxlY3RvciIpLAogIGZuKAogICAgInlvdXR1YmVfcGxheSIsCiAgICAiQ2FyaSB2aWRlbyBkaSBZb3VUdWJlIGxhbHUgT1RPTUFUSVMg
::B64:agent.js:bWVtdXRhciBoYXNpbCBwaWxpaGFuIGRpIGJyb3dzZXIgYWdlbnQuIFBha2FpIGluaSB1bnR1ayBzZW11YSBwZXJtaW50YWFuIG5vbnRvbi9jYXJpIHZpZGVvL2xhZ3UgZGkgWW91VHViZS4iLAogICAgewogICAgICBxdWVyeTogc3RyKCJLYXRhIGt1bmNpIHBlbmNh
::B64:agent.js:cmlhbiIpLAogICAgICBwaWNrOiBudW0oIlVydXRhbiBoYXNpbCB5YW5nIGRpcHV0YXIsIDEtNSAoZGVmYXVsdCAxKSIpLAogICAgICBuZXdfdGFiOiBib29sKCJ0cnVlID0gcHV0YXIgZGkgdGFiIGJhcnUgc3VwYXlhIHRhYiBha3RpZiB0aWRhayB0ZXJ0aW1wYSIp
::B64:agent.js:LAogICAgfSwKICAgIFsicGljayIsICJuZXdfdGFiIl0KICApLAogIGZuKCJkb25lIiwgIlBhbmdnaWwgaW5pIGppa2EgdHVnYXMgU0VMRVNBSSwgYXRhdSBqaWthIHBlcmx1IGJlcnRhbnlhL21lbGFwb3Iga2UgdXNlciIsIHsgbWVzc2FnZTogc3RyKCJQZXNhbiBz
::B64:agent.js:aW5na2F0IHVudHVrIHVzZXIiKSB9KSwKICBmbigKICAgICJ5b3V0dWJlX2NvbnRyb2wiLAogICAgIktvbnRyb2wgdmlkZW8gWW91VHViZSB5YW5nIHNlZGFuZyB0ZXJidWthIiwKICAgIHsgYWN0aW9uOiBzdHIoInBsYXksIHBhdXNlLCB0b2dnbGUsIG11dGUsIHVu
::B64:agent.js:bXV0ZSwgZm9yd2FyZCwgYmFja3dhcmQsIG5leHQsIHByZXZpb3VzLCBmdWxsc2NyZWVuIiksIHNlY29uZHM6IG51bSgiRGV0aWsgdW50dWsgZm9yd2FyZC9iYWNrd2FyZCAoZGVmYXVsdCAxMCkiKSB9LAogICAgWyJzZWNvbmRzIl0KICApLAogIGZuKCJ3ZWJfc2Vh
::B64:agent.js:cmNoIiwgIkNhcmkgaW5mb3JtYXNpIGRpIGludGVybmV0LCBtZW5nZW1iYWxpa2FuIGp1ZHVsLCBsaW5rLCBkYW4gY3VwbGlrYW4gaGFzaWwiLCB7CiAgICBxdWVyeTogc3RyKCJLYXRhIGt1bmNpIiksCiAgICBuZXdfdGFiOiBib29sKCJ0cnVlID0gY2FyaSBkaSB0
::B64:agent.js:YWIgYmFydSBzdXBheWEgdGFiIGFrdGlmIHRpZGFrIHRlcnRpbXBhIiksCiAgfSwgWyJuZXdfdGFiIl0pLAogIGZuKCJzY3JvbGxfcGFnZSIsICJTY3JvbGwgaGFsYW1hbiBicm93c2VyLiBQb3NpdGlmID0gdHVydW4sIG5lZ2F0aWYgPSBuYWlrIiwgeyBhbW91bnQ6
::B64:agent.js:IG51bSgiSnVtbGFoIHNjcm9sbCIpIH0pLAogIGZuKCJ3YWl0X2Zvcl91c2VyIiwgIkJlcmhlbnRpIGRhbiBtaW50YSB1c2VyIG1lbGFrdWthbiBzZXN1YXR1IHNlbmRpcmkgKGxvZ2luLCBjYXB0Y2hhLCB2ZXJpZmlrYXNpKSwgbGFsdSB0dW5nZ3UgRW50ZXIiLCB7
::B64:agent.js:IG1lc3NhZ2U6IHN0cigiSW5zdHJ1a3NpIHVudHVrIHVzZXIiKSB9KSwKICBmbigiZG93bmxvYWRfZmlsZSIsICJVbmR1aCBmaWxlIGRhcmkgaW50ZXJuZXQga2UgZm9sZGVyIERvd25sb2FkcyIsIHsgdXJsOiBzdHIoIlVSTCBodHRwKHMpIiksIGZpbGVuYW1lOiBz
::B64:agent.js:dHIoIk5hbWEgZmlsZSAob3BzaW9uYWwpIikgfSwgWyJmaWxlbmFtZSJdKSwKICBmbigibm93IiwgIlRhbmdnYWwgZGFuIGphbSBzZWthcmFuZyIpLAogIGZuKCJzeXN0ZW1faW5mbyIsICJJbmZvIFBDOiBPUywgQ1BVLCBSQU0sIGJhdGVyYWksIHJ1YW5nIGRpc2si
::B64:agent.js:KSwKICBmbigKICAgICJtZWRpYV9rZXkiLAogICAgIlRvbWJvbCBtZWRpYSBkYW4gdm9sdW1lIGdsb2JhbCBXaW5kb3dzIiwKICAgIHsga2V5OiBzdHIoInZvbHVwLCB2b2xkb3duLCBtdXRlLCBwbGF5cGF1c2UsIG5leHQsIHByZXYiKSwgdGltZXM6IG51bSgiSnVt
::B64:agent.js:bGFoIHRla2FuICh2b2x1bWUgYmVydWJhaCAyJSBwZXIgdGVrYW4pIikgfSwKICAgIFsidGltZXMiXQogICksCiAgZm4oImNsaXBib2FyZF9nZXQiLCAiQmFjYSBpc2kgY2xpcGJvYXJkIiksCiAgZm4oImNsaXBib2FyZF9zZXQiLCAiSXNpIGNsaXBib2FyZCIsIHsg
::B64:agent.js:dGV4dDogc3RyKCJUZWtzIikgfSksCiAgZm4oImxpc3Rfd2luZG93cyIsICJEYWZ0YXIgamVuZGVsYSBhdGF1IGFwbGlrYXNpIHlhbmcgc2VkYW5nIHRlcmJ1a2EiKSwKICBmbigiZm9jdXNfd2luZG93IiwgIlBpbmRhaGthbiBmb2t1cyBrZSBzZWJ1YWggamVuZGVs
::B64:agent.js:YSIsIHsgdGl0bGU6IHN0cigiU2ViYWdpYW4ganVkdWwgamVuZGVsYSIpIH0pLAogIGZuKCJjbG9zZV93aW5kb3ciLCAiVHV0dXAgc2VidWFoIGplbmRlbGEgZGVuZ2FuIGJhaWstYmFpayIsIHsgdGl0bGU6IHN0cigiU2ViYWdpYW4ganVkdWwgamVuZGVsYSIpIH0p
::B64:agent.js:LAogIGZuKCJyZWFkX3RleHRfZmlsZSIsICJCYWNhIGlzaSBmaWxlIHRla3MiLCB7IHBhdGg6IHN0cigiUGF0aCBsZW5na2FwIGZpbGUiKSB9KSwKICBmbigid3JpdGVfdGV4dF9maWxlIiwgIlR1bGlzIGF0YXUgdGFtYmFoIGlzaSBmaWxlIHRla3MiLCB7IHBhdGg6
::B64:agent.js:IHN0cigiUGF0aCBsZW5na2FwIGZpbGUiKSwgY29udGVudDogc3RyKCJJc2kiKSwgYXBwZW5kOiB7IHR5cGU6ICJib29sZWFuIiwgZGVzY3JpcHRpb246ICJ0cnVlID0gdGFtYmFoa2FuLCBidWthbiBtZW5pbXBhIiB9IH0sIFsiYXBwZW5kIl0pLAogIGZuKCJtYWtl
::B64:agent.js:X2ZvbGRlciIsICJCdWF0IGZvbGRlciBiYXJ1IiwgeyBwYXRoOiBzdHIoIlBhdGggbGVuZ2thcCBmb2xkZXIiKSB9KSwKICBmbigibW92ZV9wYXRoIiwgIlBpbmRhaGthbiBhdGF1IGdhbnRpIG5hbWEgZmlsZS9mb2xkZXIiLCB7IGZyb206IHN0cigiUGF0aCBhc2Fs
::B64:agent.js:IiksIHRvOiBzdHIoIlBhdGggdHVqdWFuIikgfSksCiAgZm4oInJlY3ljbGVfcGF0aCIsICJIYXB1cyBmaWxlL2ZvbGRlciBkZW5nYW4gbWVtaW5kYWhrYW5ueWEga2UgUmVjeWNsZSBCaW4iLCB7IHBhdGg6IHN0cigiUGF0aCBsZW5na2FwIikgfSksCiAgZm4oInpp
::B64:agent.js:cF9wYXRoIiwgIktvbXByZXMgZmlsZSBhdGF1IGZvbGRlciBtZW5qYWRpIC56aXAiLCB7IHNvdXJjZTogc3RyKCJQYXRoIGZpbGUvZm9sZGVyIiksIHppcDogc3RyKCJQYXRoIGZpbGUgLnppcCBoYXNpbCIpIH0pLAogIGZuKCJ1bnppcF9wYXRoIiwgIkVrc3RyYWsg
::B64:agent.js:ZmlsZSAuemlwIiwgeyB6aXA6IHN0cigiUGF0aCBmaWxlIC56aXAiKSwgZm9sZGVyOiBzdHIoIkZvbGRlciB0dWp1YW4iKSB9KSwKICBmbigKICAgICJmYXN0X3VwbG9hZCIsCiAgICAiVVBMT0FEIENFUEFUIGRhbGFtIHNhdHUgbGFuZ2thaCAoZGFodWx1a2FuIGFs
::B64:agent.js:YXQgaW5pIHVudHVrIHNlbXVhIHBlcm1pbnRhYW4gdXBsb2FkKTogYnVrYSBVUkwgZGkgdGFiIGJhcnUsIHRlbXVrYW4gdG9tYm9sL2lucHV0IHVwbG9hZCBvdG9tYXRpcywgcGlsaWggc2F0dS9iYW55YWsgZmlsZSBhdGF1IGlzaSBmb2xkZXIgKGZvbGRlciB0dW5n
::B64:agent.js:Z2FsIGRpa2lyaW0gc2ViYWdhaSB6aXApLCBrbGlrIHRvbWJvbCBraXJpbSwgdHVuZ2d1IHNlbGVzYWksIGtlbWJhbGlrYW4gbGluayBqaWthIHRlcmRldGVrc2kuIEppa2EgaGFsYW1hbiBzdWRhaCB0ZXJidWthLCB1cmwgYm9sZWgga29zb25nLiIsCiAgICB7CiAg
::B64:agent.js:ICAgIHVybDogc3RyKCJBbGFtYXQgc2l0dXMgdXBsb2FkIChvcHNpb25hbCBqaWthIGhhbGFtYW4gc3VkYWggdGVyYnVrYSkiKSwKICAgICAgZmlsZW5hbWU6IHN0cigiUGF0aCBmaWxlIChiYW55YWsgZGlwaXNhaCB8KSBhdGF1IHBhdGggZm9sZGVyIChha2FuIGRp
::B64:agent.js:LXppcCkiKSwKICAgICAgZm9sZGVyOiBzdHIoIkZvbGRlciBiZXJpc2kgZmlsZSB5YW5nIGRpdXBsb2FkIHNlbXVhbnlhIChvcHNpb25hbCkiKSwKICAgICAgcGF0dGVybjogc3RyKCJGaWx0ZXIgbmFtYSBmaWxlIGRpIGZvbGRlciwgbWlzYWwgLnBkZiBhdGF1IC5q
::B64:agent.js:cGd8LnBuZyAob3BzaW9uYWwpIiksCiAgICAgIHN1Ym1pdDogYm9vbCgiZmFsc2UgPSBqYW5nYW4ga2xpayB0b21ib2wga2lyaW0gb3RvbWF0aXMgKGRlZmF1bHQgdHJ1ZSkiKSwKICAgICAgbmV3X3RhYjogYm9vbCgiZmFsc2UgPSBwYWthaSB0YWIgYWt0aWYgKGRl
::B64:agent.js:ZmF1bHQgdHJ1ZSkiKSwKICAgIH0sCiAgICBbInVybCIsICJmaWxlbmFtZSIsICJmb2xkZXIiLCAicGF0dGVybiIsICJzdWJtaXQiLCAibmV3X3RhYiJdCiAgKSwKICBmbigicmVjZW50X2ZpbGVzIiwgIkRhZnRhciBmaWxlIHRlcmJhcnUgZGkgc2VidWFoIGZvbGRl
::B64:agent.js:ciAoYmF3YWFuOiBEb3dubG9hZHMpIiwgeyBmb2xkZXI6IHN0cigiUGF0aCBmb2xkZXIgKG9wc2lvbmFsKSIpLCBjb3VudDogbnVtKCJKdW1sYWggKGRlZmF1bHQgMTApIikgfSwgWyJmb2xkZXIiLCAiY291bnQiXSksCiAgZm4oInNlYXJjaF90ZXh0IiwgIkNhcmkg
::B64:agent.js:dGVrcyBkaSBkYWxhbSBmaWxlIHRla3Mva29kZSBwYWRhIHNlYnVhaCBmb2xkZXIiLCB7IGZvbGRlcjogc3RyKCJQYXRoIGZvbGRlciIpLCB0ZXh0OiBzdHIoIlRla3MgeWFuZyBkaWNhcmkiKSB9KSwKICBmbigiY29weV9wYXRoIiwgIlNhbGluIGZpbGUgYXRhdSBm
::B64:agent.js:b2xkZXIiLCB7IGZyb206IHN0cigiUGF0aCBhc2FsIiksIHRvOiBzdHIoIlBhdGggdHVqdWFuIikgfSksCiAgZm4oInNhdmVfc2NyZWVuc2hvdCIsICJTaW1wYW4gc2NyZWVuc2hvdCBsYXlhciBwZW51aCBrZSBmaWxlIChiYXdhYW46IFBpY3R1cmVzXFxTY3JlZW5z
::B64:agent.js:aG90cykiLCB7IHBhdGg6IHN0cigiUGF0aCBmaWxlIC5wbmcgKG9wc2lvbmFsKSIpIH0sIFsicGF0aCJdKSwKICBmbigic2V0X3ZvbHVtZSIsICJBdHVyIHZvbHVtZSBXaW5kb3dzIGtlIGFuZ2thIHRlcnRlbnR1ICgwLTEwMCkiLCB7IGxldmVsOiBudW0oIlBlcnNl
::B64:agent.js:biB2b2x1bWUiKSB9KSwKICBmbigic3BlYWsiLCAiVWNhcGthbiB0ZWtzIGRlbmdhbiBzdWFyYSBrb21wdXRlciIsIHsgdGV4dDogc3RyKCJUZWtzIHlhbmcgZGl1Y2Fwa2FuIikgfSksCiAgZm4oCiAgICAic2V0X3RpbWVyIiwKICAgICJBdHVyIHBlbmdpbmdhdDog
::B64:agent.js:c2V0ZWxhaCB3YWt0dSB0ZXJ0ZW50dSBtdW5jdWwgcGVzYW4sIGJ1bnlpLCBkYW4gc3VhcmEgKGFrdGlmIHNlbGFtYSBhZ2VudCB0ZXJidWthKSIsCiAgICB7IGFtb3VudDogbnVtKCJKdW1sYWggd2FrdHUiKSwgdW5pdDogc3RyKCJkZXRpaywgbWVuaXQsIGF0YXUg
::B64:agent.js:amFtIiksIG1lc3NhZ2U6IHN0cigiUGVzYW4gcGVuZ2luZ2F0IikgfSwKICAgIFsidW5pdCIsICJtZXNzYWdlIl0KICApLAogIGZuKCJtb3JlX3Rvb2xzIiwgIkFrdGlma2FuIGtlbG9tcG9rIGFsYXQgdGFtYmFoYW4gamlrYSBhbGF0IHlhbmcga2FtdSBidXR1aGth
::B64:agent.js:biBiZWx1bSB0ZXJzZWRpYSIsIHsKICAgIGdyb3VwOiBzdHIoInlvdXR1YmUsIHRhYnMsIGRlc2t0b3AsIGZpbGVzLCBhdGF1IHBjIiksCiAgfSksCiAgZm4oImdldF9wYWdlX3RleHQiLCAiQmFjYSB0ZWtzIGhhbGFtYW4gYnJvd3NlciBzYWF0IGluaSIpLAogIGZu
::B64:agent.js:KCJ0eXBlX3RleHQiLCAiSXNpIGtvbG9tIHRla3MgZGkgYnJvd3NlciIsIHsgc2VsZWN0b3I6IHN0cigiQ1NTIHNlbGVjdG9yIiksIHRleHQ6IHN0cigiVGVrcyIpIH0pLAogIGZuKCJjbGljayIsICJLbGlrIGVsZW1lbiBkaSBicm93c2VyIiwgeyBzZWxlY3Rvcjog
::B64:agent.js:c3RyKCJDU1Mgc2VsZWN0b3IiKSB9KSwKICBmbigKICAgICJ1cGxvYWRfZmlsZSIsCiAgICAiVXBsb2FkIFNBVFUgYXRhdSBCQU5ZQUsgZmlsZSBrZSBpbnB1dCBmaWxlIGRpIGJyb3dzZXIuIEJlYmVyYXBhIGZpbGUgZGkgZmlsZW5hbWUgZGlwaXNhaCB0YW5kYSB8
::B64:agent.js:LiBBdGF1IHBha2FpIGZvbGRlciAoKyBwYXR0ZXJuKSB1bnR1ayBtZW5ndW5nZ2FoIHNlbXVhIGZpbGUgZGkgZm9sZGVyIGl0dSIsCiAgICB7CiAgICAgIHNlbGVjdG9yOiBzdHIoIkNTUyBzZWxlY3RvciBpbnB1dFt0eXBlPWZpbGVdIiksCiAgICAgIGZpbGVuYW1l
::B64:agent.js:OiBzdHIoIlBhdGggbGVuZ2thcCBmaWxlIChib2xlaCBiYW55YWssIGRpcGlzYWggfCksIGF0YXUgbmFtYSBmaWxlIGRpIHVwbG9hZC1mb2xkZXIiKSwKICAgICAgZm9sZGVyOiBzdHIoIkZvbGRlciBiZXJpc2kgZmlsZSB5YW5nIG1hdSBkaXVwbG9hZCBzZW11YW55
::B64:agent.js:YSAob3BzaW9uYWwpIiksCiAgICAgIHBhdHRlcm46IHN0cigiRmlsdGVyIG5hbWEgZmlsZSBkaSBmb2xkZXIsIG1pc2FsbnlhIC5wZGYgKG9wc2lvbmFsKSIpLAogICAgfSwKICAgIFsiZmlsZW5hbWUiLCAiZm9sZGVyIiwgInBhdHRlcm4iXQogICksCl07Cgpjb25z
::B64:agent.js:dCBTWVNURU0gPSBgS2FtdSBhZ2VudCB5YW5nIG1lbmdvbnRyb2wgUEMgV2luZG93cyBtaWxpayB1c2VyIGRhbiBicm93c2VyLiBLZXJqYWthbiBwZXJpbnRhaCB1c2VyIGRlbmdhbiBtZW1hbmdnaWwgdG9vbC4KQVRVUkFOIFBFTlRJTkc6Ci0gS2FtdSBIQVJVUyBz
::B64:agent.js:ZWxhbHUgbWVtYW5nZ2lsIHRvb2wgZGkgc2V0aWFwIGxhbmdrYWguIEpBTkdBTiBwZXJuYWggbWVudWxpcyByZW5jYW5hLCBuYXJhc2ksIGF0YXUgInNheWEgYWthbiAuLi4iLiBMYW5nc3VuZyBwYW5nZ2lsIHRvb2wtbnlhLgotIFNldGVsYWggdHVnYXMgc2VsZXNh
::B64:agent.js:aSAoYXRhdSBwZXJsdSBiZXJ0YW55YSBrZSB1c2VyKSwgcGFuZ2dpbCB0b29sIGRvbmUgZGVuZ2FuIHBlc2FuIHNpbmdrYXQuCi0gTm9udG9uL2NhcmkgdmlkZW8vbGFndSBkaSBZb3VUdWJlOiBsYW5nc3VuZyBwYW5nZ2lsIHlvdXR1YmVfcGxheSBkZW5nYW4ga2F0
::B64:agent.js:YSBrdW5jaSBkYXJpIHVzZXIuIEppa2EganVkdWwgeWFuZyBkaXB1dGFyIGt1cmFuZyBjb2NvaywgcGFuZ2dpbCBsYWdpIGRlbmdhbiBwaWNrIGxhaW4uCi0gVGFmc2lya2FuIHBlcmludGFoIHNpbmdrYXQvdHlwbyB1c2VyIGRlbmdhbiB3YWphciwgamFuZ2FuIGJl
::B64:agent.js:cnRhbnlhIGhhbCB5YW5nIGJpc2EgZGl0ZWJhay4KLSBLYW11IG1lbmdpbmdhdCBwZXJjYWthcGFuIHNlYmVsdW1ueWEuIEphd2FiYW4gc2luZ2thdCB1c2VyIChtaXNhbG55YSBzZWJ1YWggbmFtYSBmaWxlKSBhZGFsYWggamF3YWJhbiBhdGFzIHBlcnRhbnlhYW5t
::B64:agent.js:dSBzZWJlbHVtbnlhOyBsYW5qdXRrYW4gdHVnYXMgaXR1LCBqYW5nYW4gbXVsYWkgZGFyaSBub2wuCi0gTWVtYnVrYSBhcGxpa2FzaSBXaW5kb3dzIGxld2F0IG9wZW5fcGF0aDoga2FtZXJhID0gbWljcm9zb2Z0LndpbmRvd3MuY2FtZXJhOiAsIGthbGt1bGF0b3Ig
::B64:agent.js:PSBjYWxjICwgbm90ZXBhZCA9IG5vdGVwYWQgLCBwYWludCA9IG1zcGFpbnQgLCBwZW5nYXR1cmFuID0gbXMtc2V0dGluZ3M6ICwgZmlsZSBleHBsb3JlciA9IGV4cGxvcmVyIC4KLSBVcGxvYWQgZmlsZSBrZSB3ZWJzaXRlOiBvcGVuX3VybCBrZSBoYWxhbWFuIHVw
::B64:agent.js:bG9hZCwgaW5zcGVjdF9wYWdlIHVudHVrIG1lbmNhcmkgaW5wdXQgdHlwZT1maWxlLCBsYWx1IHVwbG9hZF9maWxlIGRlbmdhbiBwYXRoIGxlbmdrYXAgZmlsZS4gSmlrYSBidXR1aCBsb2dpbiwgcGFuZ2dpbCBkb25lIGRhbiBtaW50YSB1c2VyIGxvZ2luIG1hbnVh
::B64:agent.js:bCBkaSBqZW5kZWxhIGJyb3dzZXIsIGxhbHUgdWxhbmdpLgotIEZvbGRlciBkaSBQQzogZmluZF9mb2xkZXIgbGFsdSBvcGVuX3BhdGguIEZpbGUgZGkgUEM6IGZpbmRfZmlsZSAoYXRhdSBsaXN0X2RpcikgdW50dWsgbWVuZGFwYXQgcGF0aCBsZW5na2FwLCBsYWx1
::B64:agent.js:IG9wZW5fcGF0aCBhdGF1IHVwbG9hZF9maWxlLiBUaWRhayBhZGEgYmF0YXNhbiBsb2thc2ksIHNlbXVhIGRyaXZlIGJvbGVoIGRpYWtzZXMuCi0gQXBsaWthc2kvamVuZGVsYSBkaSBQQzogc2NyZWVuc2hvdCBkdWx1IHVudHVrIG1lbGloYXQgbGF5YXIsIGxhbHUg
::B64:agent.js:Y2xpY2tfc2NyZWVuL3R5cGVfZGVza3RvcC9wcmVzc19rZXlzLCBsYWx1IHNjcmVlbnNob3QgbGFnaSB1bnR1ayBtZW1lcmlrc2EgaGFzaWwuCi0gS29vcmRpbmF0IGtsaWsgaGFydXMgZGFyaSBzY3JlZW5zaG90IHRlcmFraGlyLgotIFVudHVrIG90b21hc2kgd2Vi
::B64:agent.js:c2l0ZSBwYWthaSB0b29sIGJyb3dzZXIgKG9wZW5fdXJsLCBpbnNwZWN0X3BhZ2UsIHR5cGVfdGV4dCwgY2xpY2ssIHVwbG9hZF9maWxlKS4gU2VsYWx1IGluc3BlY3RfcGFnZSBzZWJlbHVtIGtsaWsuCi0gQnV0dWggbG9naW4sIGNhcHRjaGEsIGF0YXUgdmVyaWZp
::B64:agent.js:a2FzaTogcGFuZ2dpbCB3YWl0X2Zvcl91c2VyIGRhbiBtaW50YSB1c2VyIG1lbmdlcmpha2FubnlhIHNlbmRpcmkgZGkgamVuZGVsYSBicm93c2VyLiBKQU5HQU4gcGVybmFoIG1lbWludGEgYXRhdSBtZW5nZXRpa2thbiBwYXNzd29yZCB1c2VyLgotIFBlcnRhbnlh
::B64:agent.js:YW4geWFuZyBidXR1aCBpbmZvIHRlcmJhcnU6IHdlYl9zZWFyY2gsIGxhbHUgb3Blbl91cmwgZGFuIGdldF9wYWdlX3RleHQgdW50dWsgbWVtYmFjYSBzdW1iZXJueWEuCi0gS29udHJvbCBtdXNpay92aWRlbzogeW91dHViZV9jb250cm9sIHVudHVrIHZpZGVvIFlv
::B64:agent.js:dVR1YmUsIG1lZGlhX2tleSB1bnR1ayB2b2x1bWUgZGFuIHRvbWJvbCBtZWRpYSBzZWx1cnVoIFBDLgotIFRBQjogSmFuZ2FuIG1lbmltcGEgaGFsYW1hbiB5YW5nIG1hc2loIGRpcGFrYWkuIEppa2EgdXNlciBtZW55ZWJ1dCAidGFiIGJhcnUiLCBhdGF1IGFkYSB2
::B64:agent.js:aWRlby9oYWxhbWFuIGxhaW4geWFuZyBzZWRhbmcgdGVyYnVrYSAobWlzYWxueWEgbXVzaWspLCBwYWthaSBuZXdfdGFiPXRydWUgcGFkYSBvcGVuX3VybCwgd2ViX3NlYXJjaCwgYXRhdSB5b3V0dWJlX3BsYXkuIEJlYmVyYXBhIHNpdHVzIHNla2FsaWd1czogb3Bl
::B64:agent.js:bl91cmxzLiBQaW5kYWggdGFiOiBsaXN0X3RhYnMgbGFsdSBzd2l0Y2hfdGFiIChpbmRleCAtMSA9IHRhYiB0ZXJiYXJ1LCBhdGF1IG1hdGNoIGp1ZHVsKS4gVHV0dXA6IGNsb3NlX3RhYi4KLSBVcGxvYWQgYmFueWFrIGZpbGU6IHVwbG9hZF9maWxlIGRlbmdhbiBi
::B64:agent.js:ZWJlcmFwYSBwYXRoIGRpcGlzYWggfCwgYXRhdSBmb2xkZXIgKGRhbiBwYXR0ZXJuKS4gSmlrYSBpbnB1dCBoYW55YSBtZW5lcmltYSBzYXR1IGZpbGUsIHVsYW5naSBwZXIgZmlsZSBzYW1wYWkgc2VtdWEgc2VsZXNhaS4KLSBIRU1BVCBMQU5HS0FIOiBqaWthIGJl
::B64:agent.js:YmVyYXBhIGxhbmdrYWggdGlkYWsgc2FsaW5nIGJlcmdhbnR1bmcsIHBhbmdnaWwgYmViZXJhcGEgdG9vbCBzZWthbGlndXMgZGFsYW0gc2F0dSBqYXdhYmFuLgotIFVQTE9BRDogc2VsYWx1IHBha2FpIGZhc3RfdXBsb2FkIChzYXR1IHBhbmdnaWxhbiwgb3RvbWF0
::B64:agent.js:aXMgbWVuZW11a2FuIHRvbWJvbCB1cGxvYWQsIG1lbmR1a3VuZyBiYW55YWsgZmlsZSwgZm9sZGVyLCBkYW4gemlwKS4gUGFrYWkgdXBsb2FkX2ZpbGUgaGFueWEgamlrYSBmYXN0X3VwbG9hZCBnYWdhbC4KLSBWb2x1bWUga2UgYW5na2EgdGVydGVudHU6IHNldF92
::B64:agent.js:b2x1bWUuIEZpbGUgdGVyYmFydTogcmVjZW50X2ZpbGVzLgotIE1lbmdoYXB1cyBmaWxlOiBwYWthaSByZWN5Y2xlX3BhdGggKG1hc3VrIFJlY3ljbGUgQmluKSwgamFuZ2FuIG1lbmdoYXB1cyBwZXJtYW5lbi4KLSBKaWthIGFsYXQgeWFuZyBrYW11IGJ1dHVoa2Fu
::B64:agent.js:IHRpZGFrIGFkYSBkaSBkYWZ0YXIsIHBhbmdnaWwgbW9yZV90b29scyBkZW5nYW4gZ3J1cDogeW91dHViZSwgdGFicywgZGVza3RvcCwgZmlsZXMsIGF0YXUgcGMuCi0gSmlrYSBidW50dSBhdGF1IHJhZ3UsIGJlcmhlbnRpIGRhbiB0YW55YSB1c2VyLgotIEphd2Fi
::B64:agent.js:IGRhbGFtIEJhaGFzYSBJbmRvbmVzaWEsIHNpbmdrYXQuIEphbmdhbiBtZW5nYXJhbmcgaGFzaWw7IGxhcG9ya2FuIGFwYSBhZGFueWEuYDsKCi8vID09PT09IEtvbXVuaWthc2kgZGVuZ2FuIDlSb3V0ZXIgKHRhaGFuIGJhbnRpbmcpID09PT09Ci8vIEppa2EgYmFs
::B64:agent.js:YXNhbiBrb3NvbmcvZ2FnYWwsIGFnZW50IG90b21hdGlzOiAoMSkgY29iYSB0YW5wYSB0b29sX2Nob2ljZSwgKDIpIGtlY2lsa2FuIGRhZnRhciBhbGF0IGRhbgovLyBwYWthaSBiYWxhc2FuIG5vbi1zdHJlYW1pbmcsICgzKSBwaW5kYWgga2UgbW9kZWwgbGFpbiB5
::B64:agent.js:YW5nIGRpdGVtdWthbiBsZXdhdCAvbW9kZWxzLgovLyBNb2RlbCB5YW5nIGJlcmhhc2lsIGRpaW5nYXQgc2VsYW1hIHNlc2kuIFBlcmludGFoIC90ZXMgZGFuIC9tb2RlbCBtZW1iYW50dSBtZW1pbGloIG1vZGVsIHBhbGluZyBzdGFiaWwuCmNvbnN0IE1PREVMX0ZJ
::B64:agent.js:TEUgPSAibW9kZWwudHh0IjsKbGV0IGJhc2VNb2RlbCA9IE1PREVMOwp0cnkgewogIGNvbnN0IHNhdmVkID0gZnMucmVhZEZpbGVTeW5jKE1PREVMX0ZJTEUsICJ1dGY4IikudHJpbSgpOwogIGlmIChzYXZlZCkgYmFzZU1vZGVsID0gc2F2ZWQ7Cn0gY2F0Y2gge30K
::B64:agent.js:CmxldCB1c2VUb29sQ2hvaWNlID0gdHJ1ZTsgLy8gcGFrc2EgbW9kZWwgc2VsYWx1IG1lbWFuZ2dpbCB0b29sOyBkaW1hdGlrYW4gb3RvbWF0aXMgamlrYSBiZXJtYXNhbGFoCmxldCBzbGltTW9kZSA9IHByb2Nlc3MuZW52LlNMSU0gIT09ICIwIjsgLy8gdHJ1ZSA9
::B64:agent.js:IGtpcmltIGhhbnlhIGFsYXQgeWFuZyByZWxldmFuIChtdWF0YW4ga2VjaWwgPSBsZWJpaCBjZXBhdCkKbGV0IGZhbGxiYWNrTW9kZWxzID0gbnVsbDsgLy8gZGlpc2kgc2FhdCBwZXJ0YW1hIGthbGkgZGlidXR1aGthbgpsZXQgcG9vbElkeCA9IDA7CmNvbnN0IGV4
::B64:agent.js:dHJhR3JvdXBzID0gbmV3IFNldCgpOwpjb25zdCBCQUNLT0ZGID0gTnVtYmVyKHByb2Nlc3MuZW52LkJBQ0tPRkZfTVMgfHwgMTAwMCk7Cgpjb25zdCBUT09MX0dST1VQUyA9IHsKICB5b3V0dWJlOiBbInlvdXR1YmVfcGxheSIsICJ5b3V0dWJlX2NvbnRyb2wiXSwK
::B64:agent.js:ICB0YWJzOiBbIm5ld190YWIiLCAib3Blbl91cmxzIiwgImxpc3RfdGFicyIsICJzd2l0Y2hfdGFiIiwgImNsb3NlX3RhYiIsICJzY3JvbGxfcGFnZSIsICJ3ZWJfc2VhcmNoIl0sCiAgZGVza3RvcDogWyJjbGlja19zY3JlZW4iLCAic2Nyb2xsX3NjcmVlbiIsICJ0
::B64:agent.js:eXBlX2Rlc2t0b3AiLCAicHJlc3Nfa2V5cyIsICJ3YWl0IiwgImxpc3Rfd2luZG93cyIsICJmb2N1c193aW5kb3ciLCAiY2xvc2Vfd2luZG93Il0sCiAgZmlsZXM6IFsicmVhZF90ZXh0X2ZpbGUiLCAid3JpdGVfdGV4dF9maWxlIiwgIm1ha2VfZm9sZGVyIiwgIm1v
::B64:agent.js:dmVfcGF0aCIsICJjb3B5X3BhdGgiLCAicmVjeWNsZV9wYXRoIiwgInppcF9wYXRoIiwgInVuemlwX3BhdGgiLCAiZG93bmxvYWRfZmlsZSIsICJyZWNlbnRfZmlsZXMiLCAic2VhcmNoX3RleHQiXSwKICBwYzogWyJtZWRpYV9rZXkiLCAic2V0X3ZvbHVtZSIsICJj
::B64:agent.js:bGlwYm9hcmRfZ2V0IiwgImNsaXBib2FyZF9zZXQiLCAic3lzdGVtX2luZm8iLCAic2F2ZV9zY3JlZW5zaG90IiwgInNwZWFrIiwgInNldF90aW1lciJdLAp9Owpjb25zdCBDT1JFX1RPT0xTID0gWwogICJkb25lIiwgIndhaXRfZm9yX3VzZXIiLCAibW9yZV90b29s
::B64:agent.js:cyIsICJub3ciLCAib3Blbl91cmwiLCAiZ2V0X3BhZ2VfdGV4dCIsICJpbnNwZWN0X3BhZ2UiLCAidHlwZV90ZXh0IiwgImNsaWNrIiwKICAidXBsb2FkX2ZpbGUiLCAiZmFzdF91cGxvYWQiLCAibGlzdF9maWxlcyIsICJmaW5kX2ZvbGRlciIsICJmaW5kX2ZpbGUi
::B64:agent.js:LCAibGlzdF9kaXIiLCAib3Blbl9wYXRoIiwgInNjcmVlbnNob3QiLApdOwpjb25zdCBHUk9VUF9LRVlXT1JEUyA9IHsKICB5b3V0dWJlOiAveW91dHViZXx2aWRlb3xsYWd1fG11c2lrfG11c2ljfHB1dGFyfG5vbnRvbnxkZW5nYXJ8cGF1c2V8bmV4dC9pLAogIHRh
::B64:agent.js:YnM6IC9cYnRhYlxifGNhcml8c2VhcmNofGdvb2dsZXx3ZWJ8aW50ZXJuZXR8c2l0dXN8d2Vic2l0ZXxzZWthbGlndXMvaSwKICBkZXNrdG9wOiAva2xpa3xsYXlhcnxtb3VzZXxrZXRpa3xqZW5kZWxhfHdpbmRvd3xhcGxpa2FzaXxzY3JlZW5zaG90fHNjcm9sbHx0
::B64:agent.js:b21ib2wvaSwKICBmaWxlczogL2ZpbGV8Zm9sZGVyfHppcHxoYXB1c3xwaW5kYWh8dHVsaXN8YmFjYXx1bmR1aHxkb3dubG9hZHxidWF0fGdhbnRpIG5hbWF8c2FsaW58Y29weXx0ZXJiYXJ1fGNhcmkgdGVrcy9pLAogIHBjOiAvdm9sdW1lfHN1YXJhfGNsaXBib2Fy
::B64:agent.js:ZHxzYWxpbnxcYnJhbVxifGNwdXxiYXRlcmFpfHNpc3RlbXxtZWRpYXxtdXRlfHRpbWVyfGluZ2F0a2FufHBlbmdpbmdhdHx1Y2FwfGJpY2FyYXxzY3JlZW5zaG90fHRhbmdrYXAvaSwKfTsKCi8vIFBpbGloIGFsYXQgeWFuZyByZWxldmFuIHNhamEgKGRpcGFrYWkg
::B64:agent.js:c2FhdCBtdWF0YW4gcGVybHUgZGlrZWNpbGthbikKZnVuY3Rpb24gc2VsZWN0VG9vbHMobWVzc2FnZXMpIHsKICBjb25zdCBuYW1lcyA9IG5ldyBTZXQoQ09SRV9UT09MUyk7CiAgY29uc3QgdXNlclRleHQgPSBtZXNzYWdlcwogICAgLmZpbHRlcigobSkgPT4gbS5y
::B64:agent.js:b2xlID09PSAidXNlciIgJiYgdHlwZW9mIG0uY29udGVudCA9PT0gInN0cmluZyIgJiYgIW0uY29udGVudC5zdGFydHNXaXRoKCJLYW11IGhhcnVzIG1lbWFuZ2dpbCB0b29sIikpCiAgICAuc2xpY2UoLTQpCiAgICAubWFwKChtKSA9PiBtLmNvbnRlbnQpCiAgICAu
::B64:agent.js:am9pbigiICIpOwogIGZvciAoY29uc3QgW2csIHJlXSBvZiBPYmplY3QuZW50cmllcyhHUk9VUF9LRVlXT1JEUykpIHsKICAgIGlmIChyZS50ZXN0KHVzZXJUZXh0KSB8fCBleHRyYUdyb3Vwcy5oYXMoZykpIFRPT0xfR1JPVVBTW2ddLmZvckVhY2goKG4pID0+IG5h
::B64:agent.js:bWVzLmFkZChuKSk7CiAgfQogIGZvciAoY29uc3QgbSBvZiBtZXNzYWdlcykgZm9yIChjb25zdCBjIG9mIG0udG9vbF9jYWxscyB8fCBbXSkgbmFtZXMuYWRkKGMuZnVuY3Rpb24ubmFtZSk7IC8vIGFsYXQgeWFuZyBzdWRhaCBkaXBha2FpIHRldGFwIGFkYQogIHJl
::B64:agent.js:dHVybiB0b29scy5maWx0ZXIoKHQpID0+IG5hbWVzLmhhcyh0LmZ1bmN0aW9uLm5hbWUpKTsKfQoKY29uc3QgbW9kZWxQb29sID0gKCkgPT4gW2Jhc2VNb2RlbCwgLi4uKGZhbGxiYWNrTW9kZWxzIHx8IFtdKS5maWx0ZXIoKG0pID0+IG0gIT09IGJhc2VNb2RlbCld
::B64:agent.js:OwoKYXN5bmMgZnVuY3Rpb24gZGlzY292ZXJNb2RlbHMoKSB7CiAgaWYgKHByb2Nlc3MuZW52LlJPVVRFUl9GQUxMQkFDS19NT0RFTFMpIHsKICAgIHJldHVybiBwcm9jZXNzLmVudi5ST1VURVJfRkFMTEJBQ0tfTU9ERUxTLnNwbGl0KCIsIikubWFwKCh4KSA9PiB4
::B64:agent.js:LnRyaW0oKSkuZmlsdGVyKEJvb2xlYW4pOwogIH0KICB0cnkgewogICAgY29uc3QgcmVzID0gYXdhaXQgZmV0Y2goYCR7QkFTRV9VUkx9L21vZGVsc2AsIHsKICAgICAgaGVhZGVyczogeyBBdXRob3JpemF0aW9uOiBgQmVhcmVyICR7QVBJX0tFWX1gIH0sCiAgICAg
::B64:agent.js:IHNpZ25hbDogQWJvcnRTaWduYWwudGltZW91dCgxMDAwMCksCiAgICB9KTsKICAgIGlmICghcmVzLm9rKSByZXR1cm4gW107CiAgICBjb25zdCBkYXRhID0gKGF3YWl0IHJlcy5qc29uKCkpLmRhdGEgfHwgW107CiAgICBjb25zdCBiYWQgPSAvZW1iZWR8d2hpc3Bl
::B64:agent.js:cnx0dHN8aW1hZ2V8YXVkaW98cmVyYW5rfG1vZGVyYXR8ZGFsbHxmbHV4fHNkeGx8dmlkZW98c3BlZWNofHRyYW5zY3JpL2k7CiAgICBjb25zdCBzY29yZSA9IChpZCkgPT4KICAgICAgKC9jbGF1ZGUvaS50ZXN0KGlkKSA/IDMgOiAwKSArICgvZ2VtaW5pL2kudGVz
::B64:agent.js:dChpZCkgPyAzIDogMCkgKyAoL2dwdHxnbG18cXdlbnxraW1pfGRlZXBzZWVrL2kudGVzdChpZCkgPyAyIDogMCkgKwogICAgICAoL2hhaWt1fGZsYXNofHNvbm5ldC9pLnRlc3QoaWQpID8gMSA6IDApIC0gKC90aGlua2luZ3xhZ2VudGljL2kudGVzdChpZCkgPyAy
::B64:agent.js:IDogMCk7CiAgICByZXR1cm4gZGF0YQogICAgICAubWFwKChtKSA9PiBtLmlkKQogICAgICAuZmlsdGVyKChpZCkgPT4gaWQgJiYgaWQgIT09IGJhc2VNb2RlbCAmJiAhYmFkLnRlc3QoaWQpKQogICAgICAuc29ydCgoeCwgeSkgPT4gc2NvcmUoeSkgLSBzY29yZSh4
::B64:agent.js:KSkKICAgICAgLnNsaWNlKDAsIDgpOwogIH0gY2F0Y2ggewogICAgcmV0dXJuIFtdOwogIH0KfQoKZnVuY3Rpb24gZmF0YWwobXNnKSB7CiAgY29uc3QgZSA9IG5ldyBFcnJvcihtc2cpOwogIGUuZmF0YWwgPSB0cnVlOwogIHJldHVybiBlOwp9CgovLyBCYWNhIGJh
::B64:agent.js:bGFzYW4gOVJvdXRlciAoSlNPTiBiaWFzYSBhdGF1IHN0cmVhbWluZyBTU0UpIG1lbmphZGkgc2F0dSBwZXNhbgpmdW5jdGlvbiBwYXJzZUNoYXQocmF3KSB7CiAgaWYgKCFyYXcudHJpbSgpKSByZXR1cm4geyBtc2c6IG51bGwsIGVycjogImtvc29uZyIgfTsKICBp
::B64:agent.js:ZiAoIS8oXnxcbilkYXRhOi8udGVzdChyYXcpKSB7CiAgICBsZXQgb2JqOwogICAgdHJ5IHsKICAgICAgb2JqID0gSlNPTi5wYXJzZShyYXcpOwogICAgfSBjYXRjaCB7CiAgICAgIHJldHVybiB7IG1zZzogbnVsbCwgZXJyOiAiYnVrYW4gSlNPTiIgfTsKICAgIH0K
::B64:agent.js:ICAgIGlmIChvYmouZXJyb3IpIHJldHVybiB7IG1zZzogbnVsbCwgZXJyOiBKU09OLnN0cmluZ2lmeShvYmouZXJyb3IpLnNsaWNlKDAsIDE1MCkgfTsKICAgIGNvbnN0IG0gPSBvYmouY2hvaWNlcz8uWzBdPy5tZXNzYWdlOwogICAgaWYgKCFtIHx8ICghbS5jb250
::B64:agent.js:ZW50ICYmICFtLnRvb2xfY2FsbHM/Lmxlbmd0aCkpIHJldHVybiB7IG1zZzogbnVsbCwgZXJyOiAidGFucGEgaXNpIiB9OwogICAgcmV0dXJuIHsgbXNnOiBtLCBlcnI6ICIiIH07CiAgfQogIGxldCBjb250ZW50ID0gIiI7CiAgbGV0IHNzZUVyciA9ICIiOwogIGNv
::B64:agent.js:bnN0IGNhbGxzID0gW107CiAgZm9yIChjb25zdCBsaW5lIG9mIHJhdy5zcGxpdCgiXG4iKSkgewogICAgaWYgKCFsaW5lLnN0YXJ0c1dpdGgoImRhdGE6IikpIGNvbnRpbnVlOwogICAgY29uc3QgZGF0YSA9IGxpbmUuc2xpY2UoNSkudHJpbSgpOwogICAgaWYgKCFk
::B64:agent.js:YXRhIHx8IGRhdGEgPT09ICJbRE9ORV0iKSBjb250aW51ZTsKICAgIGxldCBjaHVuazsKICAgIHRyeSB7CiAgICAgIGNodW5rID0gSlNPTi5wYXJzZShkYXRhKTsKICAgIH0gY2F0Y2ggewogICAgICBjb250aW51ZTsKICAgIH0KICAgIGlmIChjaHVuay5lcnJvcikg
::B64:agent.js:c3NlRXJyID0gSlNPTi5zdHJpbmdpZnkoY2h1bmsuZXJyb3IpLnNsaWNlKDAsIDE1MCk7CiAgICBjb25zdCBjaG9pY2UgPSBjaHVuay5jaG9pY2VzPy5bMF07CiAgICBjb25zdCBkZWx0YSA9IGNob2ljZT8uZGVsdGEgfHwgY2hvaWNlPy5tZXNzYWdlIHx8IHt9Owog
::B64:agent.js:ICAgaWYgKGRlbHRhLmNvbnRlbnQpIGNvbnRlbnQgKz0gZGVsdGEuY29udGVudDsKICAgIGZvciAoY29uc3QgdGMgb2YgZGVsdGEudG9vbF9jYWxscyB8fCBbXSkgewogICAgICBjb25zdCBpID0gdGMuaW5kZXggPz8gMDsKICAgICAgY2FsbHNbaV0gPz89IHsgaWQ6
::B64:agent.js:ICIiLCB0eXBlOiAiZnVuY3Rpb24iLCBmdW5jdGlvbjogeyBuYW1lOiAiIiwgYXJndW1lbnRzOiAiIiB9IH07CiAgICAgIGlmICh0Yy5pZCkgY2FsbHNbaV0uaWQgPSB0Yy5pZDsKICAgICAgaWYgKHRjLmZ1bmN0aW9uPy5uYW1lKSBjYWxsc1tpXS5mdW5jdGlvbi5u
::B64:agent.js:YW1lICs9IHRjLmZ1bmN0aW9uLm5hbWU7CiAgICAgIGlmICh0Yy5mdW5jdGlvbj8uYXJndW1lbnRzKSBjYWxsc1tpXS5mdW5jdGlvbi5hcmd1bWVudHMgKz0gdGMuZnVuY3Rpb24uYXJndW1lbnRzOwogICAgfQogIH0KICBjb25zdCB2YWxpZCA9IGNhbGxzLmZpbHRl
::B64:agent.js:cihCb29sZWFuKS5tYXAoKGMsIGkpID0+ICh7IC4uLmMsIGlkOiBjLmlkIHx8IGBjYWxsXyR7aX1gIH0pKTsKICBpZiAoIWNvbnRlbnQgJiYgIXZhbGlkLmxlbmd0aCkgcmV0dXJuIHsgbXNnOiBudWxsLCBlcnI6IHNzZUVyciB8fCAidGFucGEgaXNpIiB9OwogIGNv
::B64:agent.js:bnN0IG1zZyA9IHsgcm9sZTogImFzc2lzdGFudCIsIGNvbnRlbnQ6IGNvbnRlbnQgfHwgbnVsbCB9OwogIGlmICh2YWxpZC5sZW5ndGgpIG1zZy50b29sX2NhbGxzID0gdmFsaWQ7CiAgcmV0dXJuIHsgbXNnLCBlcnI6ICIiIH07Cn0KCmFzeW5jIGZ1bmN0aW9uIHJl
::B64:agent.js:cXVlc3RPbmNlKG1lc3NhZ2VzLCB7IG1vZGVsLCB0b29sQ2hvaWNlLCBzdHJlYW0sIHNsaW0gfSkgewogIGNvbnN0IHRvb2xMaXN0ID0gc2xpbSA/IHNlbGVjdFRvb2xzKG1lc3NhZ2VzKSA6IHRvb2xzLmZpbHRlcigodCkgPT4gdC5mdW5jdGlvbi5uYW1lICE9PSAi
::B64:agent.js:bW9yZV90b29scyIpOwogIGNvbnN0IGJvZHkgPSB7IG1vZGVsLCBtZXNzYWdlcywgdG9vbHM6IHRvb2xMaXN0LCBzdHJlYW0gfTsKICBpZiAodG9vbENob2ljZSkgYm9keS50b29sX2Nob2ljZSA9ICJyZXF1aXJlZCI7CiAgY29uc3QgcmVzID0gYXdhaXQgZmV0Y2go
::B64:agent.js:YCR7QkFTRV9VUkx9L2NoYXQvY29tcGxldGlvbnNgLCB7CiAgICBtZXRob2Q6ICJQT1NUIiwKICAgIGhlYWRlcnM6IHsgIkNvbnRlbnQtVHlwZSI6ICJhcHBsaWNhdGlvbi9qc29uIiwgQXV0aG9yaXphdGlvbjogYEJlYXJlciAke0FQSV9LRVl9YCB9LAogICAgYm9k
::B64:agent.js:eTogSlNPTi5zdHJpbmdpZnkoYm9keSksCiAgICBzaWduYWw6IEFib3J0U2lnbmFsLnRpbWVvdXQoMTIwMDAwKSwKICB9KTsKICBpZiAoIXJlcy5vaykgewogICAgY29uc3QgZXJyVGV4dCA9IChhd2FpdCByZXMudGV4dCgpKS5yZXBsYWNlKC9ccysvZywgIiAiKS5z
::B64:agent.js:bGljZSgwLCAyMDApOwogICAgaWYgKHJlcy5zdGF0dXMgPT09IDQwMSB8fCByZXMuc3RhdHVzID09PSA0MDMpIHRocm93IGZhdGFsKGBBUEkga2V5IGRpdG9sYWsgKCR7cmVzLnN0YXR1c30pLiBKYWxhbmthbjogc3RhcnQtYWdlbnQuYmF0IHJlc2V0YCk7CiAgICBj
::B64:agent.js:b25zdCBlID0gbmV3IEVycm9yKGBIVFRQICR7cmVzLnN0YXR1c30gJHtlcnJUZXh0fWApOwogICAgaWYgKHJlcy5zdGF0dXMgPT09IDQyOSkgZS53YWl0ID0gTWF0aC5taW4oTnVtYmVyKHJlcy5oZWFkZXJzLmdldCgicmV0cnktYWZ0ZXIiKSkgfHwgNSwgMTUpICog
::B64:agent.js:MTAwMDsKICAgIHRocm93IGU7CiAgfQogIGNvbnN0IHJhdyA9IGF3YWl0IHJlcy50ZXh0KCk7CiAgY29uc3QgeyBtc2csIGVyciB9ID0gcGFyc2VDaGF0KHJhdyk7CiAgaWYgKCFtc2cpIHsKICAgIGNvbnN0IHBlZWsgPSBgW0hUVFAgJHtyZXMuc3RhdHVzfSwgJHty
::B64:agent.js:YXcubGVuZ3RofSBieXRlJHtyYXcudHJpbSgpID8gIjogIiArIHJhdy5yZXBsYWNlKC9ccysvZywgIiAiKS5zbGljZSgwLCAxMDApIDogIiJ9XWA7CiAgICB0aHJvdyBuZXcgRXJyb3IoYHJlc3BvbnMgJHtlcnJ9ICR7cGVla31gKTsKICB9CiAgcmV0dXJuIG1zZzsK
::B64:agent.js:fQoKYXN5bmMgZnVuY3Rpb24gY2FsbExMTShtZXNzYWdlcykgewogIGNvbnN0IEFUVEVNUFRTID0gNzsKICBsZXQgbGFzdEVyciA9ICIiOwogIGZvciAobGV0IGF0dGVtcHQgPSAxOyBhdHRlbXB0IDw9IEFUVEVNUFRTOyBhdHRlbXB0KyspIHsKICAgIGlmIChhdHRl
::B64:agent.js:bXB0ID49IDMpIHNsaW1Nb2RlID0gdHJ1ZTsgLy8ga2VjaWxrYW4gbXVhdGFuIGFsYXQKICAgIGlmIChhdHRlbXB0ID49IDQpIHsKICAgICAgLy8gUGluZGFoIGtlIG1vZGVsIGxhaW4KICAgICAgaWYgKCFmYWxsYmFja01vZGVscykgZmFsbGJhY2tNb2RlbHMgPSBh
::B64:agent.js:d2FpdCBkaXNjb3Zlck1vZGVscygpOwogICAgICBjb25zdCBwb29sID0gbW9kZWxQb29sKCk7CiAgICAgIGlmIChwb29sLmxlbmd0aCA+IDEpIHsKICAgICAgICBwb29sSWR4ID0gKHBvb2xJZHggKyAxKSAlIHBvb2wubGVuZ3RoOwogICAgICAgIGNvbnNvbGUubG9n
::B64:agent.js:KGAgIChtZW5jb2JhIG1vZGVsIGxhaW46ICR7cG9vbFtwb29sSWR4XX0pYCk7CiAgICAgIH0KICAgIH0KICAgIGNvbnN0IHBvb2wgPSBtb2RlbFBvb2woKTsKICAgIGNvbnN0IG1vZGVsID0gcG9vbFtwb29sSWR4ICUgcG9vbC5sZW5ndGhdOwogICAgdHJ5IHsKICAg
::B64:agent.js:ICAgY29uc3QgbXNnID0gYXdhaXQgcmVxdWVzdE9uY2UobWVzc2FnZXMsIHsKICAgICAgICBtb2RlbCwKICAgICAgICB0b29sQ2hvaWNlOiBhdHRlbXB0ID09PSAxICYmIHVzZVRvb2xDaG9pY2UsCiAgICAgICAgc3RyZWFtOiBhdHRlbXB0IDwgMyB8fCBhdHRlbXB0
::B64:agent.js:ICUgMiA9PT0gMCwKICAgICAgICBzbGltOiBzbGltTW9kZSwKICAgICAgfSk7CiAgICAgIGNvbnN0IGNsZWFuID0geyByb2xlOiAiYXNzaXN0YW50IiwgY29udGVudDogbXNnLmNvbnRlbnQgPz8gbnVsbCB9OwogICAgICBpZiAobXNnLnRvb2xfY2FsbHM/Lmxlbmd0
::B64:agent.js:aCkgY2xlYW4udG9vbF9jYWxscyA9IG1zZy50b29sX2NhbGxzOwogICAgICByZXR1cm4gY2xlYW47CiAgICB9IGNhdGNoIChlKSB7CiAgICAgIGlmIChlLmZhdGFsKSB0aHJvdyBlOwogICAgICBsYXN0RXJyID0gZS5tZXNzYWdlOwogICAgICBpZiAoYXR0ZW1wdCA9
::B64:agent.js:PT0gMSkgdXNlVG9vbENob2ljZSA9IGZhbHNlOwogICAgfQogICAgaWYgKGF0dGVtcHQgPCBBVFRFTVBUUykgewogICAgICBjb25zb2xlLmxvZyhgICAoOVJvdXRlciBiZXJtYXNhbGFoOiAke2xhc3RFcnIuc2xpY2UoMCwgMTQwKX0uIE1lbmNvYmEgdWxhbmcgJHth
::B64:agent.js:dHRlbXB0fS8ke0FUVEVNUFRTIC0gMX0uLi4pYCk7CiAgICAgIGF3YWl0IHNsZWVwKE1hdGgubWluKEJBQ0tPRkYgKiBhdHRlbXB0LCA0MDAwKSk7CiAgICB9CiAgfQogIHRocm93IG5ldyBFcnJvcigKICAgIGA5Um91dGVyIGdhZ2FsIG1lcmVzcG9ucyBzZXRlbGFo
::B64:agent.js:ICR7QVRURU1QVFN9IHBlcmNvYmFhbiAoJHtsYXN0RXJyLnNsaWNlKDAsIDE2MCl9KS4gYCArCiAgICAgIGBLZXRpayAvdGVzIHVudHVrIG1lbmd1amkgbW9kZWwgZGFuIG1lbWlsaWggeWFuZyBzdGFiaWwuIENlayBqdWdhIGRhc2hib2FyZCA5Um91dGVyLCBtZW51
::B64:agent.js:IENvbnNvbGUgTG9nLmAKICApOwp9CgovLyBVamkgc2F0dSBtb2RlbCBkZW5nYW4gcGVybWludGFhbiBrZWNpbCB5YW5nIG1lbWludGEgcGVtYW5nZ2lsYW4gdG9vbAphc3luYyBmdW5jdGlvbiB0ZXN0TW9kZWwobW9kZWwpIHsKICBjb25zdCB0MCA9IERhdGUubm93
::B64:agent.js:KCk7CiAgY29uc3QgcGluZ1Rvb2wgPSBbCiAgICB7CiAgICAgIHR5cGU6ICJmdW5jdGlvbiIsCiAgICAgIGZ1bmN0aW9uOiB7CiAgICAgICAgbmFtZTogInBpbmciLAogICAgICAgIGRlc2NyaXB0aW9uOiAiVGVzIGtvbmVrc2kiLAogICAgICAgIHBhcmFtZXRlcnM6
::B64:agent.js:IHsgdHlwZTogIm9iamVjdCIsIHByb3BlcnRpZXM6IHsgcGVzYW46IHsgdHlwZTogInN0cmluZyIgfSB9LCByZXF1aXJlZDogWyJwZXNhbiJdIH0sCiAgICAgIH0sCiAgICB9LAogIF07CiAgdHJ5IHsKICAgIGNvbnN0IHJlcyA9IGF3YWl0IGZldGNoKGAke0JBU0Vf
::B64:agent.js:VVJMfS9jaGF0L2NvbXBsZXRpb25zYCwgewogICAgICBtZXRob2Q6ICJQT1NUIiwKICAgICAgaGVhZGVyczogeyAiQ29udGVudC1UeXBlIjogImFwcGxpY2F0aW9uL2pzb24iLCBBdXRob3JpemF0aW9uOiBgQmVhcmVyICR7QVBJX0tFWX1gIH0sCiAgICAgIGJvZHk6
::B64:agent.js:IEpTT04uc3RyaW5naWZ5KHsKICAgICAgICBtb2RlbCwKICAgICAgICBtZXNzYWdlczogW3sgcm9sZTogInVzZXIiLCBjb250ZW50OiAiUGFuZ2dpbCB0b29sIHBpbmcgZGVuZ2FuIHBlc2FuIG9rLiIgfV0sCiAgICAgICAgdG9vbHM6IHBpbmdUb29sLAogICAgICAg
::B64:agent.js:IHN0cmVhbTogZmFsc2UsCiAgICAgIH0pLAogICAgICBzaWduYWw6IEFib3J0U2lnbmFsLnRpbWVvdXQoNDUwMDApLAogICAgfSk7CiAgICBjb25zdCByYXcgPSBhd2FpdCByZXMudGV4dCgpOwogICAgY29uc3QgbXMgPSBEYXRlLm5vdygpIC0gdDA7CiAgICBpZiAo
::B64:agent.js:IXJlcy5vaykgcmV0dXJuIHsgbWFyazogIltYXSAiLCBtcywgdGV4dDogYEhUVFAgJHtyZXMuc3RhdHVzfSAke3Jhdy5yZXBsYWNlKC9ccysvZywgIiAiKS5zbGljZSgwLCA3MCl9YCB9OwogICAgY29uc3QgeyBtc2csIGVyciB9ID0gcGFyc2VDaGF0KHJhdyk7CiAg
::B64:agent.js:ICBpZiAoIW1zZykgcmV0dXJuIHsgbWFyazogIltYXSAiLCBtcywgdGV4dDogYHJlc3BvbnMgJHtlcnJ9YCB9OwogICAgaWYgKG1zZy50b29sX2NhbGxzPy5sZW5ndGgpIHJldHVybiB7IG1hcms6ICJbT0tdIiwgbXMsIHRleHQ6ICJ0b29sIGNhbGxpbmcgYmVyZnVu
::B64:agent.js:Z3NpIiB9OwogICAgcmV0dXJuIHsgbWFyazogIlt+XSAiLCBtcywgdGV4dDogIm1lbmphd2FiIHRhcGkgdGlkYWsgbWVtYW5nZ2lsIHRvb2wgKGt1cmFuZyBjb2NvayB1bnR1ayBhZ2VudCkiIH07CiAgfSBjYXRjaCAoZSkgewogICAgcmV0dXJuIHsgbWFyazogIltY
::B64:agent.js:XSAiLCBtczogRGF0ZS5ub3coKSAtIHQwLCB0ZXh0OiBlLm5hbWUgPT09ICJUaW1lb3V0RXJyb3IiID8gInRpbWVvdXQiIDogZS5tZXNzYWdlLnNsaWNlKDAsIDcwKSB9OwogIH0KfQoKLy8gPT09PT0gSmFsdXIgY2VwYXQ6IHBlcmludGFoIHVtdW0gbGFuZ3N1bmcg
::B64:agent.js:ZGlqYWxhbmthbiBUQU5QQSBBSSAoaGFzaWwgZGFsYW0gaGl0dW5nYW4gZGV0aWspID09PT09Ci8vIEppa2EgcGVyaW50YWggdGlkYWsgZGlrZW5hbGkgYXRhdSBqYWx1ciBjZXBhdCBnYWdhbCwgb3RvbWF0aXMgZGlzZXJhaGthbiBrZSBBSS4KbGV0IEZBU1QgPSBw
::B64:agent.js:cm9jZXNzLmVudi5GQVNUICE9PSAiMCI7Cgpjb25zdCB0aWR5ID0gKHMpID0+CiAgU3RyaW5nKHMpCiAgICAucmVwbGFjZSgvXHMrKGRvbmd8eWF8eWFofGRlaHxhamF8ZG9ua3xzaWh8bmlofHBsZWFzZXxwbHN8cGxpc3xkdWx1KVxzKiQvaSwgIiIpCiAgICAucmVw
::B64:agent.js:bGFjZSgvWy4hP10rJC8sICIiKQogICAgLnRyaW0oKTsKCmNvbnN0IEtOT1dOX1NJVEVTID0gewogIHlvdXR1YmU6ICJ5b3V0dWJlLmNvbSIsIHl0OiAieW91dHViZS5jb20iLCBnb29nbGU6ICJnb29nbGUuY29tIiwgZ21haWw6ICJtYWlsLmdvb2dsZS5jb20iLCBn
::B64:agent.js:aXRodWI6ICJnaXRodWIuY29tIiwKICB0aWt0b2s6ICJ0aWt0b2suY29tIiwgZmFjZWJvb2s6ICJmYWNlYm9vay5jb20iLCBmYjogImZhY2Vib29rLmNvbSIsIGluc3RhZ3JhbTogImluc3RhZ3JhbS5jb20iLCBpZzogImluc3RhZ3JhbS5jb20iLAogIHR3aXR0ZXI6
::B64:agent.js:ICJ4LmNvbSIsIHg6ICJ4LmNvbSIsIHdoYXRzYXBwOiAid2ViLndoYXRzYXBwLmNvbSIsIHdhOiAid2ViLndoYXRzYXBwLmNvbSIsIG1lZGlhZmlyZTogIm1lZGlhZmlyZS5jb20iLAogIGRyaXZlOiAiZHJpdmUuZ29vZ2xlLmNvbSIsIG1hcHM6ICJtYXBzLmdvb2ds
::B64:agent.js:ZS5jb20iLCBuZXRmbGl4OiAibmV0ZmxpeC5jb20iLCBzcG90aWZ5OiAib3Blbi5zcG90aWZ5LmNvbSIsCiAgY2hhdGdwdDogImNoYXRncHQuY29tIiwgY2xhdWRlOiAiY2xhdWRlLmFpIiwgZ2VtaW5pOiAiZ2VtaW5pLmdvb2dsZS5jb20iLCB0b2tvcGVkaWE6ICJ0
::B64:agent.js:b2tvcGVkaWEuY29tIiwKICBzaG9wZWU6ICJzaG9wZWUuY28uaWQiLCB0ZWxlZ3JhbTogIndlYi50ZWxlZ3JhbS5vcmciLCBsaW5rZWRpbjogImxpbmtlZGluLmNvbSIsIHBpbnRlcmVzdDogInBpbnRlcmVzdC5jb20iLAogIHR3aXRjaDogInR3aXRjaC50diIsIGRp
::B64:agent.js:c2NvcmQ6ICJkaXNjb3JkLmNvbSIsIHJlZGRpdDogInJlZGRpdC5jb20iLCB3aWtpcGVkaWE6ICJpZC53aWtpcGVkaWEub3JnIiwKfTsKY29uc3QgVVBMT0FEX1NJVEVTID0gewogIG1lZGlhZmlyZTogImh0dHBzOi8vYXBwLm1lZGlhZmlyZS5jb20vbXlmaWxlcyIs
::B64:agent.js:IGdvZmlsZTogImh0dHBzOi8vZ29maWxlLmlvIiwgcGl4ZWxkcmFpbjogImh0dHBzOi8vcGl4ZWxkcmFpbi5jb20iLAogIGNhdGJveDogImh0dHBzOi8vY2F0Ym94Lm1vZSIsIHdldHJhbnNmZXI6ICJodHRwczovL3dldHJhbnNmZXIuY29tIiwgZHJpdmU6ICJodHRw
::B64:agent.js:czovL2RyaXZlLmdvb2dsZS5jb20vZHJpdmUvbXktZHJpdmUiLAogIHRtcGZpbGVzOiAiaHR0cHM6Ly90bXBmaWxlcy5vcmciLCBmaWxlYmluOiAiaHR0cHM6Ly9maWxlYmluLm5ldCIsCn07CmNvbnN0IEFQUFMgPSB7CiAga2FtZXJhOiAibWljcm9zb2Z0LndpbmRv
::B64:agent.js:d3MuY2FtZXJhOiIsIGNhbWVyYTogIm1pY3Jvc29mdC53aW5kb3dzLmNhbWVyYToiLCBub3RlcGFkOiAibm90ZXBhZCIsIGthbGt1bGF0b3I6ICJjYWxjIiwKICBjYWxjdWxhdG9yOiAiY2FsYyIsIHBhaW50OiAibXNwYWludCIsIHBlbmdhdHVyYW46ICJtcy1zZXR0
::B64:agent.js:aW5nczoiLCBzZXR0aW5nczogIm1zLXNldHRpbmdzOiIsICJmaWxlIGV4cGxvcmVyIjogImV4cGxvcmVyIiwKICBleHBsb3JlcjogImV4cGxvcmVyIiwgY21kOiAiY21kIiwgInRhc2sgbWFuYWdlciI6ICJ0YXNrbWdyIiwgInBlbmdlbG9sYSB0dWdhcyI6ICJ0YXNr
::B64:agent.js:bWdyIiwgInJlY3ljbGUgYmluIjogInNoZWxsOlJlY3ljbGVCaW5Gb2xkZXIiLAp9Owpjb25zdCBGSUxFX0tJTkRTID0gewogIGZvdG86ICIuanBnfC5qcGVnfC5wbmd8LndlYnAiLCBnYW1iYXI6ICIuanBnfC5qcGVnfC5wbmd8LndlYnAiLCB2aWRlbzogIi5tcDR8
::B64:agent.js:Lm1rdnwuYXZpfC5tb3YiLCB2aWRpbzogIi5tcDR8Lm1rdnwuYXZpfC5tb3YiLAogIG11c2lrOiAiLm1wM3wud2F2fC5mbGFjfC5tNGEiLCBsYWd1OiAiLm1wM3wud2F2fC5mbGFjfC5tNGEiLCBkb2t1bWVuOiAiLnBkZnwuZG9jfC5kb2N4fC50eHR8Lnhsc3h8LnBw
::B64:agent.js:dHgiLAp9Owpjb25zdCBET01BSU5fUkUgPSAvXig/Omh0dHBzPzpcL1wvKT9bYS16MC05LV0rKD86XC5bYS16MC05LV0rKSpcLig/OmNvbXxpZHxuZXR8b3JnfGlvfGNvfG1lfGFwcHxkZXZ8dHZ8YWl8eHl6fGluZm98Y29cLmlkfGdvXC5pZHxhY1wuaWQpKD86XC9c
::B64:agent.js:UyopPyQvaTsKCmNvbnN0IHNpdGVVcmwgPSAodCkgPT4gewogIGNvbnN0IGsgPSBTdHJpbmcodCkudHJpbSgpLnRvTG93ZXJDYXNlKCk7CiAgaWYgKEtOT1dOX1NJVEVTW2tdKSByZXR1cm4gImh0dHBzOi8vIiArIEtOT1dOX1NJVEVTW2tdOwogIGlmIChET01BSU5f
::B64:agent.js:UkUudGVzdChTdHJpbmcodCkudHJpbSgpKSkgcmV0dXJuIGZpeFVybChTdHJpbmcodCkudHJpbSgpKTsKICByZXR1cm4gIiI7Cn07CmNvbnN0IHVwbG9hZFVybCA9ICh0KSA9PiB7CiAgY29uc3QgayA9IFN0cmluZyh0KS50cmltKCkudG9Mb3dlckNhc2UoKS5yZXBs
::B64:agent.js:YWNlKC9cLihjb218aW98b3JnfG5ldHxtZXxtb2V8YXBwKSQvLCAiIik7CiAgaWYgKFVQTE9BRF9TSVRFU1trXSkgcmV0dXJuIFVQTE9BRF9TSVRFU1trXTsKICBpZiAoRE9NQUlOX1JFLnRlc3QoU3RyaW5nKHQpLnRyaW0oKSkpIHJldHVybiBmaXhVcmwoU3RyaW5n
::B64:agent.js:KHQpLnRyaW0oKSk7CiAgcmV0dXJuICIiOwp9Owpjb25zdCBvbllvdVR1YmUgPSAoKSA9PiAveW91dHViZVwuY29tXC93YXRjaC9pLnRlc3QocGFnZS51cmwoKSk7CmNvbnN0IG9uWW91VHViZVNpdGUgPSAoKSA9PiAveW91dHViZVwuY29tL2kudGVzdChwYWdlLnVy
::B64:agent.js:bCgpKTsKY29uc3QgaXNCbGFua1BhZ2UgPSAoKSA9PiB7CiAgY29uc3QgdSA9IHBhZ2UudXJsKCk7CiAgcmV0dXJuICF1IHx8IC9eKGFib3V0OmJsYW5rfGNocm9tZTpcL1wvbmV3LT90YWJ8ZWRnZTpcL1wvbmV3dGFiKS9pLnRlc3QodSk7Cn07CmNvbnN0IGtub3du
::B64:agent.js:RGlyID0gKG5hbWUpID0+IHsKICBjb25zdCBrID0gU3RyaW5nKG5hbWUpLnRyaW0oKS50b0xvd2VyQ2FzZSgpOwogIGlmICgvXihkb3dubG9hZHM/fHVuZHVoYW4pJC8udGVzdChrKSkgcmV0dXJuIHBhdGguam9pbihIT01FLCAiRG93bmxvYWRzIik7CiAgaWYgKGsg
::B64:agent.js:PT09ICJkZXNrdG9wIikgcmV0dXJuIHBhdGguam9pbihIT01FLCAiRGVza3RvcCIpOwogIGlmICgvXihkb2N1bWVudHM/fGRva3VtZW4pJC8udGVzdChrKSkgcmV0dXJuIHBhdGguam9pbihIT01FLCAiRG9jdW1lbnRzIik7CiAgaWYgKC9eKHBpY3R1cmVzP3xnYW1i
::B64:agent.js:YXJ8Zm90bykkLy50ZXN0KGspKSByZXR1cm4gcGF0aC5qb2luKEhPTUUsICJQaWN0dXJlcyIpOwogIHJldHVybiAiIjsKfTsKCi8vIFBpbGloIGhhc2lsIHBlbmNhcmlhbiB0ZXJiYWlrOiBuYW1hIHBhbGluZyBtaXJpcCwgbGFsdSBsb2thc2kgdW11bSwgbGFsdSBw
::B64:agent.js:YXRoIHRlcnBlbmRlawpmdW5jdGlvbiBiZXN0UGF0aChsaW5lcywgcXVlcnkpIHsKICBjb25zdCByYXcgPSBTdHJpbmcocXVlcnkpLnRvTG93ZXJDYXNlKCk7CiAgY29uc3QgcSA9IHJhdy5yZXBsYWNlKC9cLlthLXowLTldezIsNH0kLywgIiIpOwogIGNvbnN0IHNj
::B64:agent.js:b3JlID0gKHApID0+IHsKICAgIGNvbnN0IGJhc2UgPSBwYXRoLmJhc2VuYW1lKHApLnRvTG93ZXJDYXNlKCk7CiAgICBjb25zdCBzdGVtID0gYmFzZS5yZXBsYWNlKC9cLlthLXowLTldezIsNH0kLywgIiIpOwogICAgbGV0IHMgPSAwOwogICAgaWYgKGJhc2UgPT09
::B64:agent.js:IHJhdyB8fCBzdGVtID09PSBxKSBzICs9IDEwOwogICAgZWxzZSBpZiAoc3RlbS5zdGFydHNXaXRoKHEpKSBzICs9IDQ7CiAgICBpZiAoL1tcXC9dKGRvd25sb2Fkc3xkZXNrdG9wfGRvY3VtZW50c3x1bmR1aGFuKVtcXC9dL2kudGVzdChwKSkgcyArPSAzOwogICAg
::B64:agent.js:cmV0dXJuIHMgLSBwLmxlbmd0aCAvIDIwMDsKICB9OwogIHJldHVybiBbLi4ubGluZXNdLnNvcnQoKGEsIGIpID0+IHNjb3JlKGIpIC0gc2NvcmUoYSkpWzBdOwp9CmNvbnN0IHJlc3VsdExpbmVzID0gKG91dCkgPT4gU3RyaW5nKG91dCkuc3BsaXQoIlxuIikuZmls
::B64:agent.js:dGVyKChsKSA9PiBsICYmIGwgIT09ICJUaWRhayBkaXRlbXVrYW4iKTsKCi8vIFViYWggdWNhcGFuIHNlcGVydGkgImxhcG9yYW4ucGRmIiwgImZvbGRlciBSZWlhIiwgInlhbmcgdGVyYmFydSBkaSBkb3dubG9hZHMiIG1lbmphZGkgcGF0aCBueWF0YQphc3luYyBm
::B64:agent.js:dW5jdGlvbiByZXNvbHZlVXBsb2FkU291cmNlKHdoYXQpIHsKICBjb25zdCB3ID0gdGlkeSh3aGF0KS5yZXBsYWNlKC9eWyInXXxbIiddJC9nLCAiIik7CiAgbGV0IG1tOwogIGlmICgobW0gPSB3Lm1hdGNoKC9ec2VtdWFccysoPzpmaWxlXHMrKT8oLis/KVxzKyg/
::B64:agent.js:OmRpfGRhcmkpXHMrKD86Zm9sZGVyXHMrKT8oLispJC9pKSkpIHsKICAgIGNvbnN0IGtpbmQgPSBtbVsxXS50cmltKCkudG9Mb3dlckNhc2UoKTsKICAgIGNvbnN0IHBhdHRlcm4gPSBGSUxFX0tJTkRTW2tpbmRdIHx8ICgvXlthLXowLTldezIsNX0kLy50ZXN0KGtp
::B64:agent.js:bmQpID8gIi4iICsga2luZCA6IGtpbmQpOwogICAgbGV0IGZvbGRlciA9IGtub3duRGlyKG1tWzJdKTsKICAgIGlmICghZm9sZGVyKSB7CiAgICAgIGNvbnN0IGxpbmVzID0gcmVzdWx0TGluZXMoc2VhcmNoRXZlcnl3aGVyZShtbVsyXS50cmltKCksIGZhbHNlKSk7
::B64:agent.js:CiAgICAgIGlmICghbGluZXMubGVuZ3RoKSB0aHJvdyBuZXcgRXJyb3IoYEZvbGRlciAiJHttbVsyXX0iIHRpZGFrIGRpdGVtdWthbmApOwogICAgICBmb2xkZXIgPSBiZXN0UGF0aChsaW5lcywgbW1bMl0pOwogICAgfQogICAgcmV0dXJuIHsgZm9sZGVyLCBwYXR0
::B64:agent.js:ZXJuLCBsYWJlbDogYHNlbXVhICR7a2luZH0gZGkgJHtmb2xkZXJ9YCB9OwogIH0KICBpZiAoKG1tID0gdy5tYXRjaCgvXig/OmZpbGVccyspPyg/OnlhbmdccyspPyg/OnBhbGluZ1xzKyk/KD86dGVyYmFydXx0ZXJha2hpcnxiYXJ1KSg/OlxzKyg/OmRpfGRhcmkp
::B64:agent.js:XHMrKD86Zm9sZGVyXHMrKT8oLispKT8kL2kpKSkgewogICAgY29uc3QgZGlyID0gbW1bMV0gPyBrbm93bkRpcihtbVsxXSkgfHwgcGF0aC5yZXNvbHZlKG1tWzFdKSA6IHBhdGguam9pbihIT01FLCAiRG93bmxvYWRzIik7CiAgICBjb25zdCBuZXdlc3QgPSByZWNl
::B64:agent.js:bnRMaXN0KGRpciwgMSlbMF07CiAgICBpZiAoIW5ld2VzdCkgdGhyb3cgbmV3IEVycm9yKCJUaWRhayBhZGEgZmlsZSBkaSAiICsgZGlyKTsKICAgIHJldHVybiB7IGZpbGVuYW1lOiBuZXdlc3QuZiwgbGFiZWw6IGBmaWxlIHRlcmJhcnUgZGkgJHtkaXJ9YCB9Owog
::B64:agent.js:IH0KICBpZiAoKG1tID0gdy5tYXRjaCgvXmZvbGRlclxzKyguKykkL2kpKSkgewogICAgbGV0IGZvbGRlciA9IGtub3duRGlyKG1tWzFdKTsKICAgIGlmICghZm9sZGVyKSB7CiAgICAgIGNvbnN0IGxpbmVzID0gcmVzdWx0TGluZXMoc2VhcmNoRXZlcnl3aGVyZSht
::B64:agent.js:bVsxXS50cmltKCksIGZhbHNlKSk7CiAgICAgIGlmICghbGluZXMubGVuZ3RoKSB0aHJvdyBuZXcgRXJyb3IoYEZvbGRlciAiJHttbVsxXX0iIHRpZGFrIGRpdGVtdWthbmApOwogICAgICBmb2xkZXIgPSBiZXN0UGF0aChsaW5lcywgbW1bMV0pOwogICAgfQogICAg
::B64:agent.js:cmV0dXJuIHsgZmlsZW5hbWU6IGZvbGRlciwgbGFiZWw6IGBmb2xkZXIgJHtmb2xkZXJ9IChkaWtpcmltIHNlYmFnYWkgemlwKWAgfTsKICB9CiAgY29uc3QgZGlyZWN0ID0gcGF0aC5yZXNvbHZlKFNBRkVfRElSLCB3KTsKICBpZiAoZnMuZXhpc3RzU3luYyhkaXJl
::B64:agent.js:Y3QpKSByZXR1cm4geyBmaWxlbmFtZTogZGlyZWN0LCBsYWJlbDogZGlyZWN0IH07CiAgY29uc3QgbGluZXMgPSByZXN1bHRMaW5lcyhzZWFyY2hFdmVyeXdoZXJlKHcsIHRydWUpKTsKICBpZiAoIWxpbmVzLmxlbmd0aCkgdGhyb3cgbmV3IEVycm9yKGBGaWxlICIk
::B64:agent.js:e3d9IiB0aWRhayBkaXRlbXVrYW5gKTsKICByZXR1cm4geyBmaWxlbmFtZTogYmVzdFBhdGgobGluZXMsIHcpLCBsYWJlbDogdyB9Owp9Cgphc3luYyBmdW5jdGlvbiB0cnlGYXN0Q29tbWFuZChyYXcpIHsKICBjb25zdCBjID0gU3RyaW5nKHJhdykudHJpbSgpLnJl
::B64:agent.js:cGxhY2UoL1xzKy9nLCAiICIpOwogIGxldCBtOwogIGNvbnN0IHl0ID0gb25Zb3VUdWJlKCk7CgogIC8vIC0tLS0gVm9sdW1lIC0tLS0KICBpZiAoKG0gPSBjLm1hdGNoKC9eKD86KD86YXR1cnxzZXR8dWJhaClccyspPyg/OnZvbHVtZXxzdWFyYSkoPzpueWEpP1xz
::B64:agent.js:Kig/OmphZGl8a2V8bWVuamFkaXw9fGRpKT9ccyooXGR7MSwzfSlccyolPyQvaSkpIHx8CiAgICAgIChtID0gYy5tYXRjaCgvXig/Om5haWtpbnxuYWlra2FufHR1cnVuaW58dHVydW5rYW58a2VjaWxpbnxrZWNpbGthbnxiZXNhcmlufGJlc2Fya2FuKVxzKyg/OnZv
::B64:agent.js:bHVtZXxzdWFyYSkoPzpueWEpP1xzKyg/OmphZGl8a2V8bWVuamFkaSlccyooXGR7MSwzfSlccyolPyQvaSkpKSB7CiAgICByZXR1cm4gYXdhaXQgaW1wbC5zZXRfdm9sdW1lKHsgbGV2ZWw6IG1bMV0gfSk7CiAgfQogIGlmICgobSA9IGMubWF0Y2goL14oPzpuYWlr
::B64:agent.js:aW58bmFpa2thbnxiZXNhcmlufGJlc2Fya2FufGtlcmFza2FufHRhbWJhaCg/OmlufGthbik/KVxzKyg/OnZvbHVtZXxzdWFyYSkoPzpueWEpPyg/OlxzKyhcZHsxLDN9KVxzKiU/KT8kL2kpKSkgewogICAgYXdhaXQgaW1wbC5tZWRpYV9rZXkoeyBrZXk6ICJ2b2x1
::B64:agent.js:cCIsIHRpbWVzOiBtWzFdID8gTWF0aC5tYXgoMSwgTWF0aC5yb3VuZChOdW1iZXIobVsxXSkgLyAyKSkgOiA1IH0pOwogICAgcmV0dXJuIGBWb2x1bWUgZGluYWlra2FuICR7bVsxXSA/IG1bMV0gKyAiJSIgOiAic2VraXRhciAxMCUifS5gOwogIH0KICBpZiAoKG0g
::B64:agent.js:PSBjLm1hdGNoKC9eKD86dHVydW5pbnx0dXJ1bmthbnxrZWNpbGlufGtlY2lsa2FufHBlbGFuaW58cGVsYW5rYW58a3VyYW5naXxrdXJhbmdpbilccysoPzp2b2x1bWV8c3VhcmEpKD86bnlhKT8oPzpccysoXGR7MSwzfSlccyolPyk/JC9pKSkpIHsKICAgIGF3YWl0
::B64:agent.js:IGltcGwubWVkaWFfa2V5KHsga2V5OiAidm9sZG93biIsIHRpbWVzOiBtWzFdID8gTWF0aC5tYXgoMSwgTWF0aC5yb3VuZChOdW1iZXIobVsxXSkgLyAyKSkgOiA1IH0pOwogICAgcmV0dXJuIGBWb2x1bWUgZGl0dXJ1bmthbiAke21bMV0gPyBtWzFdICsgIiUiIDog
::B64:agent.js:InNla2l0YXIgMTAlIn0uYDsKICB9CiAgaWYgKC9eKD86bXV0ZXx1bm11dGV8YmlzdWthbnxzZW55YXBrYW58bWF0aWthbiBzdWFyYXxueWFsYWthbiBzdWFyYXxidW55aWthbikoPzpccysoPzpzdWFyYXx2b2x1bWUpKT8kL2kudGVzdChjKSkgewogICAgYXdhaXQg
::B64:agent.js:aW1wbC5tZWRpYV9rZXkoeyBrZXk6ICJtdXRlIiB9KTsKICAgIHJldHVybiAiTXV0ZSBkaXViYWggKHRvZ2dsZSkuIjsKICB9CgogIC8vIC0tLS0gS29udHJvbCBwZW11dGFyIC0tLS0KICBpZiAoL14oPzpwYXVzZXxqZWRhKSg/OlxzKyg/OmR1bHV8dmlkZW9ueWF8
::B64:agent.js:bXVzaWtueWF8bGFndW55YXxsYWd1fHZpZGVvfG11c2lrfHlvdXR1YmUpKSokL2kudGVzdChjKSB8fAogICAgICAoeXQgJiYgL14oPzpzdG9wfHNldG9wfGJlcmhlbnRpfGhlbnRpa2FuKSg/OlxzKyg/OmR1bHV8dmlkZW9ueWF8bXVzaWtueWF8bGFndW55YSkpKiQv
::B64:agent.js:aS50ZXN0KGMpKSkgewogICAgaWYgKHl0KSBhd2FpdCBpbXBsLnlvdXR1YmVfY29udHJvbCh7IGFjdGlvbjogInBhdXNlIiB9KTsKICAgIGVsc2UgYXdhaXQgaW1wbC5tZWRpYV9rZXkoeyBrZXk6ICJwbGF5cGF1c2UiIH0pOwogICAgcmV0dXJuICJEaWplZGEuIjsK
::B64:agent.js:ICB9CiAgaWYgKC9eKD86cGxheXxyZXN1bWV8cHV0YXIgbGFnaXxtdWxhaSBsYWdpKSg/OlxzKyg/OmR1bHV8dmlkZW9ueWF8bXVzaWtueWF8bGFndW55YXxsYWd1fHZpZGVvfG11c2lrKSkqJC9pLnRlc3QoYykgfHwKICAgICAgKHl0ICYmIC9eKD86bGFuanV0fGxh
::B64:agent.js:bmp1dGthbnx0ZXJ1c2luKSQvaS50ZXN0KGMpKSkgewogICAgaWYgKHl0KSBhd2FpdCBpbXBsLnlvdXR1YmVfY29udHJvbCh7IGFjdGlvbjogInBsYXkiIH0pOwogICAgZWxzZSBhd2FpdCBpbXBsLm1lZGlhX2tleSh7IGtleTogInBsYXlwYXVzZSIgfSk7CiAgICBy
::B64:agent.js:ZXR1cm4gIkRpbGFuanV0a2FuLiI7CiAgfQogIGlmICgvXig/Om5leHR8c2tpcHxzZWxhbmp1dG55YXxiZXJpa3V0bnlhfGxhZ3UgYmVyaWt1dG55YXxsYWd1IHNlbGFuanV0bnlhfGdhbnRpIGxhZ3UpJC9pLnRlc3QoYykpIHsKICAgIGlmICh5dCkgYXdhaXQgaW1w
::B64:agent.js:bC55b3V0dWJlX2NvbnRyb2woeyBhY3Rpb246ICJuZXh0IiB9KTsKICAgIGVsc2UgYXdhaXQgaW1wbC5tZWRpYV9rZXkoeyBrZXk6ICJuZXh0IiB9KTsKICAgIHJldHVybiAiTGFndS92aWRlbyBiZXJpa3V0bnlhLiI7CiAgfQogIGlmICgvXig/OnByZXZpb3VzfHBy
::B64:agent.js:ZXZ8c2ViZWx1bW55YXxsYWd1IHNlYmVsdW1ueWEpJC9pLnRlc3QoYykpIHsKICAgIGlmICh5dCkgYXdhaXQgaW1wbC55b3V0dWJlX2NvbnRyb2woeyBhY3Rpb246ICJwcmV2aW91cyIgfSk7CiAgICBlbHNlIGF3YWl0IGltcGwubWVkaWFfa2V5KHsga2V5OiAicHJl
::B64:agent.js:diIgfSk7CiAgICByZXR1cm4gIkxhZ3UvdmlkZW8gc2ViZWx1bW55YS4iOwogIH0KICBpZiAoeXQgJiYgKG0gPSBjLm1hdGNoKC9eKD86bWFqdXxtYWp1aW58Zm9yd2FyZClccyooXGQrKT9ccyooPzpkZXRpayk/JC9pKSkpIHsKICAgIGF3YWl0IGltcGwueW91dHVi
::B64:agent.js:ZV9jb250cm9sKHsgYWN0aW9uOiAiZm9yd2FyZCIsIHNlY29uZHM6IG1bMV0gfHwgMTAgfSk7CiAgICByZXR1cm4gYE1hanUgJHttWzFdIHx8IDEwfSBkZXRpay5gOwogIH0KICBpZiAoeXQgJiYgKG0gPSBjLm1hdGNoKC9eKD86bXVuZHVyfG11bmR1cmlufHJld2lu
::B64:agent.js:ZClccyooXGQrKT9ccyooPzpkZXRpayk/JC9pKSkpIHsKICAgIGF3YWl0IGltcGwueW91dHViZV9jb250cm9sKHsgYWN0aW9uOiAiYmFja3dhcmQiLCBzZWNvbmRzOiBtWzFdIHx8IDEwIH0pOwogICAgcmV0dXJuIGBNdW5kdXIgJHttWzFdIHx8IDEwfSBkZXRpay5g
::B64:agent.js:OwogIH0KICBpZiAoeXQgJiYgL14oPzpmdWxsc2NyZWVufGxheWFyIHBlbnVoKSQvaS50ZXN0KGMpKSB7CiAgICBhd2FpdCBpbXBsLnlvdXR1YmVfY29udHJvbCh7IGFjdGlvbjogImZ1bGxzY3JlZW4iIH0pOwogICAgcmV0dXJuICJGdWxsc2NyZWVuIGRpdWJhaC4i
::B64:agent.js:OwogIH0KCiAgLy8gLS0tLSBZb3VUdWJlOiBwdXRhciBsYWd1L3ZpZGVvIC0tLS0KICBpZiAoL14oPzpub250b258dG9udG9ufGJ1a2F8cHV0YXIpXHMreW91dHViZSQvaS50ZXN0KGMpKSB7CiAgICBhd2FpdCBpbXBsLm9wZW5fdXJsKHsgdXJsOiAiaHR0cHM6Ly93
::B64:agent.js:d3cueW91dHViZS5jb20iLCBuZXdfdGFiOiAhaXNCbGFua1BhZ2UoKSB9KTsKICAgIHJldHVybiAiWW91VHViZSBkaWJ1a2EuIjsKICB9CiAgaWYgKChtID0gYy5tYXRjaCgvXig/OnB1dGFyKD86a2FufGluKT98c2V0ZWwoPzppbik/fHBsYXl8ZGVuZ2VyaW58ZGVu
::B64:agent.js:Z2Fya2FufG5vbnRvbig/OmluKT98dG9udG9ufGNhcmkoPzppbnxrYW4pPylccysoPzpsYWd1fG11c2lrfG11c2ljfHZpZGVvfHZpZGlvfGZpbG0pXHMrKC4rKSQvaSkpIHx8CiAgICAgIChtID0gYy5tYXRjaCgvXig/OnB1dGFyKD86a2FufGluKT98c2V0ZWwoPzpp
::B64:agent.js:bik/fHBsYXl8ZGVuZ2VyaW58ZGVuZ2Fya2FufG5vbnRvbig/OmluKT98dG9udG9uKVxzKyguKykkL2kpKSkgewogICAgY29uc3QgcSA9IHRpZHkobVsxXSkucmVwbGFjZSgvXHMrKD86ZGl8ZGFyaXxsZXdhdClccyt5b3V0dWJlJC9pLCAiIik7CiAgICBpZiAoIXEg
::B64:agent.js:fHwgL14oPzpmaWxlfGZvbGRlcnxkb2t1bWVuKVxiL2kudGVzdChxKSB8fCAvW2Etel06XFx8XC4oPzptcDN8bXA0fG1rdnxhdml8d2F2fHBkZnx6aXB8dHh0KVxiL2kudGVzdChxKSkgcmV0dXJuIG51bGw7CiAgICBjb25zdCBvdXQgPSBhd2FpdCBpbXBsLnlvdXR1
::B64:agent.js:YmVfcGxheSh7IHF1ZXJ5OiBxLCBuZXdfdGFiOiAhb25Zb3VUdWJlU2l0ZSgpICYmICFpc0JsYW5rUGFnZSgpIH0pOwogICAgcmV0dXJuIFN0cmluZyhvdXQpLnNwbGl0KCJcbiIpWzBdOwogIH0KCiAgLy8gLS0tLSBVcGxvYWQgY2VwYXQgLS0tLQogIGlmICgobSA9
::B64:agent.js:IGMubWF0Y2goL14oPzp1cGxvYWR8dW5nZ2FofHVwbG91ZHxraXJpbSlccysoPzpmaWxlXHMrKT8oLis/KVxzK2tlXHMrKFxTKykkL2kpKSkgewogICAgY29uc3QgdGFyZ2V0ID0gdXBsb2FkVXJsKG1bMl0pOwogICAgaWYgKCF0YXJnZXQpIHJldHVybiBudWxsOyAv
::B64:agent.js:LyB0dWp1YW4gdGlkYWsgZGlrZW5hbCAtPiBzZXJhaGthbiBrZSBBSQogICAgY29uc3Qgc3JjID0gYXdhaXQgcmVzb2x2ZVVwbG9hZFNvdXJjZShtWzFdKTsKICAgIHJldHVybiBhd2FpdCBpbXBsLmZhc3RfdXBsb2FkKHsgdXJsOiB0YXJnZXQsIGZpbGVuYW1lOiBz
::B64:agent.js:cmMuZmlsZW5hbWUsIGZvbGRlcjogc3JjLmZvbGRlciwgcGF0dGVybjogc3JjLnBhdHRlcm4gfSk7CiAgfQoKICAvLyAtLS0tIEJ1a2EgZm9sZGVyIC8gc2l0dXMgLyBhcGxpa2FzaSAtLS0tCiAgaWYgKChtID0gYy5tYXRjaCgvXmJ1a2EoPzppbnxrYW4pP1xzK2Zv
::B64:agent.js:bGRlclxzKyguKykkL2kpKSkgewogICAgY29uc3QgbmFtZSA9IHRpZHkobVsxXSk7CiAgICBsZXQgZGlyID0ga25vd25EaXIobmFtZSk7CiAgICBsZXQgZXh0cmEgPSAiIjsKICAgIGlmICghZGlyKSB7CiAgICAgIGNvbnN0IGxpbmVzID0gcmVzdWx0TGluZXMoc2Vh
::B64:agent.js:cmNoRXZlcnl3aGVyZShuYW1lLCBmYWxzZSkpOwogICAgICBpZiAoIWxpbmVzLmxlbmd0aCkgcmV0dXJuIGBGb2xkZXIgIiR7bmFtZX0iIHRpZGFrIGRpdGVtdWthbi5gOwogICAgICBkaXIgPSBiZXN0UGF0aChsaW5lcywgbmFtZSk7CiAgICAgIGlmIChsaW5lcy5s
::B64:agent.js:ZW5ndGggPiAxKSBleHRyYSA9IGBcbigke2xpbmVzLmxlbmd0aCAtIDF9IGZvbGRlciBsYWluIGNvY29rOiAke2xpbmVzLmZpbHRlcigobCkgPT4gbCAhPT0gZGlyKS5zbGljZSgwLCAzKS5qb2luKCIgfCAiKX0pYDsKICAgIH0KICAgIGNvbnN0IHIgPSBhd2FpdCBp
::B64:agent.js:bXBsLm9wZW5fcGF0aCh7IHRhcmdldDogZGlyIH0pOwogICAgcmV0dXJuIFN0cmluZyhyKS5zdGFydHNXaXRoKCJEaWJhdGFsa2FuIikgPyByIDogYEZvbGRlciBkaWJ1a2E6ICR7ZGlyfSR7ZXh0cmF9YDsKICB9CiAgaWYgKChtID0gYy5tYXRjaCgvXig/OmJ1a2Eo
::B64:agent.js:PzppbnxrYW4pP3xvcGVuKVxzKyguKz8pKD86XHMrc2VrYWxpZ3VzKT8kL2kpKSkgewogICAgY29uc3QgdG9rZW5zID0gbVsxXQogICAgICAuc3BsaXQoL1xzKig/Oix8XGJkYW5cYnwmfFwrKVxzKi9pKQogICAgICAubWFwKCh4KSA9PiB4LnJlcGxhY2UoL1xzKyg/
::B64:agent.js:OmRpXHMrKT90YWJccytiYXJ1JC9pLCAiIikudHJpbSgpKQogICAgICAuZmlsdGVyKEJvb2xlYW4pOwogICAgY29uc3QgdXJscyA9IHRva2Vucy5tYXAoc2l0ZVVybCk7CiAgICBpZiAodG9rZW5zLmxlbmd0aCAmJiB1cmxzLmV2ZXJ5KEJvb2xlYW4pKSB7CiAgICAg
::B64:agent.js:IGlmICh1cmxzLmxlbmd0aCA9PT0gMSkgewogICAgICAgIGF3YWl0IGltcGwub3Blbl91cmwoeyB1cmw6IHVybHNbMF0sIG5ld190YWI6ICFpc0JsYW5rUGFnZSgpIH0pOwogICAgICAgIHJldHVybiBgRGlidWthOiAke3VybHNbMF19YDsKICAgICAgfQogICAgICBh
::B64:agent.js:d2FpdCBpbXBsLm9wZW5fdXJscyh7IHVybHMgfSk7CiAgICAgIHJldHVybiBgJHt1cmxzLmxlbmd0aH0gdGFiIGRpYnVrYTogJHt1cmxzLmpvaW4oIiwgIil9YDsKICAgIH0KICAgIGlmICh0b2tlbnMubGVuZ3RoID09PSAxICYmIEFQUFNbdG9rZW5zWzBdLnRvTG93
::B64:agent.js:ZXJDYXNlKCldKSB7CiAgICAgIGNvbnN0IHIgPSBhd2FpdCBpbXBsLm9wZW5fcGF0aCh7IHRhcmdldDogQVBQU1t0b2tlbnNbMF0udG9Mb3dlckNhc2UoKV0gfSk7CiAgICAgIHJldHVybiBTdHJpbmcocikuc3RhcnRzV2l0aCgiRGliYXRhbGthbiIpID8gciA6IGAk
::B64:agent.js:e3Rva2Vuc1swXX0gZGlidWthLmA7CiAgICB9CiAgfQoKICAvLyAtLS0tIENhcmkgZmlsZSAvIGZvbGRlciAvIHdlYiAtLS0tCiAgaWYgKChtID0gYy5tYXRjaCgvXmNhcmkoPzppbnxrYW4pP1xzKyhmaWxlfGZvbGRlcilccysoLispJC9pKSkpIHsKICAgIGNvbnN0
::B64:agent.js:IG91dCA9IHNlYXJjaEV2ZXJ5d2hlcmUodGlkeShtWzJdKSwgbVsxXS50b0xvd2VyQ2FzZSgpID09PSAiZmlsZSIpOwogICAgcmV0dXJuIG91dCA9PT0gIlRpZGFrIGRpdGVtdWthbiIgPyBgJHttWzFdfSAiJHt0aWR5KG1bMl0pfSIgdGlkYWsgZGl0ZW11a2FuLmAg
::B64:agent.js:OiBvdXQ7CiAgfQogIGlmICgobSA9IGMubWF0Y2goL14oPzpjYXJpKD86aW58a2FuKT98Z29vZ2xpbmcpXHMrKD86dGF1XHMrKT8oLis/KVxzKyg/OmRpXHMrKT8oPzp3ZWJ8Z29vZ2xlfGludGVybmV0fGJyb3dzZXIpJC9pKSkpIHsKICAgIHJldHVybiBhd2FpdCBp
::B64:agent.js:bXBsLndlYl9zZWFyY2goeyBxdWVyeTogdGlkeShtWzFdKSwgbmV3X3RhYjogIWlzQmxhbmtQYWdlKCkgfSk7CiAgfQogIGlmICgvXig/OmxpaGF0fHRhbXBpbGthbnxjZWspP1xzKig/OmZpbGV8dW5kdWhhbnxkb3dubG9hZCg/OmFuKT8pXHMrKD86eWFuZ1xzKyk/
::B64:agent.js:dGVyYmFydSg/OlxzKyg/OmRpXHMrKT9cUyspPyQvaS50ZXN0KGMpKSB7CiAgICByZXR1cm4gYXdhaXQgaW1wbC5yZWNlbnRfZmlsZXMoe30pOwogIH0KCiAgLy8gLS0tLSBUYWIgLS0tLQogIGlmICgvXig/OnR1dHVwKVxzK3RhYig/OlxzK2luaSk/JC9pLnRlc3Qo
::B64:agent.js:YykpIHJldHVybiAoYXdhaXQgaW1wbC5jbG9zZV90YWIoe30pKS5zcGxpdCgiXG4iKVswXTsKICBpZiAoKG0gPSBjLm1hdGNoKC9eKD86cGluZGFofGtlfGJ1a2EpXHMrdGFiXHMrKHRlcmJhcnV8YmFydXx0ZXJha2hpcnxcZCspJC9pKSkpIHsKICAgIGNvbnN0IGlk
::B64:agent.js:eCA9IC9eXGQrJC8udGVzdChtWzFdKSA/IE51bWJlcihtWzFdKSA6IC0xOwogICAgcmV0dXJuIGF3YWl0IGltcGwuc3dpdGNoX3RhYih7IGluZGV4OiBpZHggfSk7CiAgfQogIGlmICgvXig/OmRhZnRhcnxsaXN0fGxpaGF0KVxzK3RhYiQvaS50ZXN0KGMpKSByZXR1
::B64:agent.js:cm4gYXdhaXQgaW1wbC5saXN0X3RhYnMoKTsKCiAgLy8gLS0tLSBQQyAtLS0tCiAgaWYgKC9eKD86aW5mb3xjZWt8c3RhdHVzfGxpaGF0KVxzKig/OnBjfGtvbXB1dGVyfGxhcHRvcHxzaXN0ZW18c3Bla3xyYW18Y3B1fGJhdGVyYWl8ZGlza3xzdG9yYWdlfG1lbW9y
::B64:agent.js:aSlcYi9pLnRlc3QoYykpIHJldHVybiBhd2FpdCBpbXBsLnN5c3RlbV9pbmZvKCk7CiAgaWYgKC9eKD86amFtIGJlcmFwYXx0YW5nZ2FsIGJlcmFwYXxoYXJpIGFwYXxzZWthcmFuZyBqYW0gYmVyYXBhfHNla2FyYW5nIHRhbmdnYWwgYmVyYXBhfGphbSBiZXJhcGEg
::B64:agent.js:c2VrYXJhbmcpXD8/JC9pLnRlc3QoYykpIHJldHVybiBhd2FpdCBpbXBsLm5vdygpOwogIGlmICgvXig/OnNjcmVlbnNob3R8dGFuZ2thcCBsYXlhcnxzc3xjYXB0dXJlKSg/OlxzK2xheWFyKT8kL2kudGVzdChjKSkgcmV0dXJuIGF3YWl0IGltcGwuc2F2ZV9zY3Jl
::B64:agent.js:ZW5zaG90KHt9KTsKICBpZiAoKG0gPSBjLm1hdGNoKC9eKD86aW5nYXRrYW58aW5nZXRpbnxpbmdhdGlufHRpbWVyfGFsYXJtfHNldCB0aW1lcilccysoPzpha3Vccyt8c2F5YVxzK3xndWVccyspPyg/OmRhbGFtXHMrKT8oXGQrKD86Wy4sXVxkKyk/KVxzKihtZW5p
::B64:agent.js:dHxkZXRpa3xqYW0pXHMqKD86bGFnaSk/XHMqKD86dW50dWt8YnVhdHw6KT9ccyooLiopJC9pKSkpIHsKICAgIHJldHVybiBhd2FpdCBpbXBsLnNldF90aW1lcih7IGFtb3VudDogbVsxXSwgdW5pdDogbVsyXSwgbWVzc2FnZTogdGlkeShtWzNdKSB8fCAiV2FrdHVu
::B64:agent.js:eWEhIiB9KTsKICB9CiAgaWYgKChtID0gYy5tYXRjaCgvXig/OnVjYXBrYW58YmlsYW5nfGthdGFrYW58YmFjYWthbilccysoLispJC9pKSkpIHJldHVybiBhd2FpdCBpbXBsLnNwZWFrKHsgdGV4dDogdGlkeShtWzFdKSB9KTsKCiAgcmV0dXJuIG51bGw7IC8vIHRp
::B64:agent.js:ZGFrIGRpa2VuYWwgLT4gQUkKfQoKLy8gPT09PT0gTWVtb3JpIHBlcmNha2FwYW4gPT09PT0KY29uc3QgaGlzdG9yeSA9IFtdOwpjb25zdCBNQVhfSElTVE9SWSA9IDMwOwoKZnVuY3Rpb24gc3RyaXBJbWFnZXMoKSB7CiAgZm9yIChjb25zdCBtIG9mIGhpc3Rvcnkp
::B64:agent.js:IHsKICAgIGlmIChtLnJvbGUgPT09ICJ1c2VyIiAmJiBBcnJheS5pc0FycmF5KG0uY29udGVudCkpIHsKICAgICAgbS5jb250ZW50ID0gIltzY3JlZW5zaG90IGxhbWEgZGloYXB1cyB1bnR1ayBtZW5naGVtYXQgbWVtb3JpXSI7CiAgICB9CiAgfQp9CgpmdW5jdGlv
::B64:agent.js:biB0cmltSGlzdG9yeSgpIHsKICB3aGlsZSAoaGlzdG9yeS5sZW5ndGggPiBNQVhfSElTVE9SWSkgewogICAgbGV0IGkgPSAxOwogICAgd2hpbGUgKGkgPCBoaXN0b3J5Lmxlbmd0aCAmJiAhKGhpc3RvcnlbaV0ucm9sZSA9PT0gInVzZXIiICYmIHR5cGVvZiBoaXN0
::B64:agent.js:b3J5W2ldLmNvbnRlbnQgPT09ICJzdHJpbmciKSkgaSsrOwogICAgaWYgKGkgPj0gaGlzdG9yeS5sZW5ndGgpIGJyZWFrOwogICAgaGlzdG9yeS5zcGxpY2UoMCwgaSk7CiAgfQp9Cgphc3luYyBmdW5jdGlvbiBydW5UYXNrKGNvbW1hbmQpIHsKICBjb25zdCBzdGFy
::B64:agent.js:dExlbiA9IGhpc3RvcnkubGVuZ3RoOwogIGhpc3RvcnkucHVzaCh7IHJvbGU6ICJ1c2VyIiwgY29udGVudDogY29tbWFuZCB9KTsKICBsZXQgbnVkZ2VzID0gMDsKCiAgdHJ5IHsKICAgIGZvciAobGV0IHN0ZXAgPSAxOyBzdGVwIDw9IE1BWF9TVEVQUzsgc3RlcCsr
::B64:agent.js:KSB7CiAgICAgIGNvbnN0IG1zZyA9IGF3YWl0IGNhbGxMTE0oW3sgcm9sZTogInN5c3RlbSIsIGNvbnRlbnQ6IFNZU1RFTSB9LCAuLi5oaXN0b3J5XSk7CiAgICAgIGhpc3RvcnkucHVzaChtc2cpOwoKICAgICAgaWYgKCFtc2cudG9vbF9jYWxscz8ubGVuZ3RoKSB7
::B64:agent.js:CiAgICAgICAgLy8gTW9kZWwgY3VtYSBtZW51bGlzIHRla3MvcmVuY2FuYSB0YW5wYSBtZW1hbmdnaWwgdG9vbCAtPiBwYWtzYSBwYW5nZ2lsIHRvb2wKICAgICAgICBpZiAobnVkZ2VzIDwgMykgewogICAgICAgICAgbnVkZ2VzKys7CiAgICAgICAgICBoaXN0b3J5
::B64:agent.js:LnB1c2goewogICAgICAgICAgICByb2xlOiAidXNlciIsCiAgICAgICAgICAgIGNvbnRlbnQ6ICJLYW11IGhhcnVzIG1lbWFuZ2dpbCB0b29sLiBKYW5nYW4gbWVudWxpcyB0ZWtzIGJpYXNhLiBMYW5nc3VuZyBwYW5nZ2lsIHRvb2wgeWFuZyBzZXN1YWksIGF0YXUg
::B64:agent.js:cGFuZ2dpbCBkb25lIGppa2EgdHVnYXMgc3VkYWggc2VsZXNhaS4iLAogICAgICAgICAgfSk7CiAgICAgICAgICBjb250aW51ZTsKICAgICAgICB9CiAgICAgICAgY29uc29sZS5sb2coIlxuQWdlbnQ6IiwgbXNnLmNvbnRlbnQgfHwgIih0aWRhayBhZGEgamF3YWJh
::B64:agent.js:bikiKTsKICAgICAgICByZXR1cm47CiAgICAgIH0KCiAgICAgIC8vIFR1Z2FzIHNlbGVzYWk6IHNlbXVhIHRvb2xfY2FsbCB3YWppYiBkaWphd2FiIGFnYXIgcml3YXlhdCB0ZXRhcCB2YWxpZAogICAgICBjb25zdCBkb25lQ2FsbCA9IG1zZy50b29sX2NhbGxzLmZp
::B64:agent.js:bmQoKGMpID0+IGMuZnVuY3Rpb24ubmFtZSA9PT0gImRvbmUiKTsKICAgICAgaWYgKGRvbmVDYWxsKSB7CiAgICAgICAgbGV0IG0gPSAiIjsKICAgICAgICB0cnkgewogICAgICAgICAgbSA9IEpTT04ucGFyc2UoZG9uZUNhbGwuZnVuY3Rpb24uYXJndW1lbnRzIHx8
::B64:agent.js:ICJ7fSIpLm1lc3NhZ2UgfHwgIiI7CiAgICAgICAgfSBjYXRjaCB7fQogICAgICAgIGZvciAoY29uc3QgY2FsbCBvZiBtc2cudG9vbF9jYWxscykgewogICAgICAgICAgaGlzdG9yeS5wdXNoKHsgcm9sZTogInRvb2wiLCB0b29sX2NhbGxfaWQ6IGNhbGwuaWQsIGNv
::B64:agent.js:bnRlbnQ6IGNhbGwgPT09IGRvbmVDYWxsID8gIm9rIiA6ICJkaWxld2F0aSIgfSk7CiAgICAgICAgfQogICAgICAgIGNvbnNvbGUubG9nKCJcbkFnZW50OiIsIG0gfHwgIlNlbGVzYWkuIik7CiAgICAgICAgcmV0dXJuOwogICAgICB9CgogICAgICBjb25zdCBleGVj
::B64:agent.js:Q2FsbCA9IGFzeW5jIChjYWxsKSA9PiB7CiAgICAgICAgY29uc3QgbmFtZSA9IGNhbGwuZnVuY3Rpb24ubmFtZTsKICAgICAgICB0cnkgewogICAgICAgICAgY29uc3QgYXJncyA9IEpTT04ucGFyc2UoY2FsbC5mdW5jdGlvbi5hcmd1bWVudHMgfHwgInt9Iik7CiAg
::B64:agent.js:ICAgICAgICBjb25zb2xlLmxvZyhgWyR7c3RlcH1dICR7bmFtZX1gLCBhcmdzKTsKICAgICAgICAgIGlmICghaW1wbFtuYW1lXSkgdGhyb3cgbmV3IEVycm9yKCJUb29sIHRpZGFrIGRpa2VuYWw6ICIgKyBuYW1lKTsKICAgICAgICAgIGF3YWl0IGVuc3VyZVBhZ2Uo
::B64:agent.js:KTsKICAgICAgICAgIHJldHVybiBhd2FpdCBpbXBsW25hbWVdKGFyZ3MpOwogICAgICAgIH0gY2F0Y2ggKGUpIHsKICAgICAgICAgIHJldHVybiAiRVJST1I6ICIgKyBlLm1lc3NhZ2U7CiAgICAgICAgfQogICAgICB9OwogICAgICBjb25zdCBjYWxscyA9IG1zZy50
::B64:agent.js:b29sX2NhbGxzOwogICAgICBjb25zdCByZXN1bHRzID0gW107CiAgICAgIGlmIChjYWxscy5sZW5ndGggPiAxICYmIGNhbGxzLmV2ZXJ5KChjKSA9PiBTQUZFX1BBUkFMTEVMLmhhcyhjLmZ1bmN0aW9uLm5hbWUpKSkgewogICAgICAgIHJlc3VsdHMucHVzaCguLi4o
::B64:agent.js:YXdhaXQgUHJvbWlzZS5hbGwoY2FsbHMubWFwKGV4ZWNDYWxsKSkpKTsgLy8gYWxhdCBiYWNhLXNhamEgZGlqYWxhbmthbiBiZXJzYW1hYW4KICAgICAgfSBlbHNlIHsKICAgICAgICBmb3IgKGNvbnN0IGNhbGwgb2YgY2FsbHMpIHJlc3VsdHMucHVzaChhd2FpdCBl
::B64:agent.js:eGVjQ2FsbChjYWxsKSk7CiAgICAgIH0KICAgICAgY2FsbHMuZm9yRWFjaCgoY2FsbCwgaSkgPT4KICAgICAgICBoaXN0b3J5LnB1c2goeyByb2xlOiAidG9vbCIsIHRvb2xfY2FsbF9pZDogY2FsbC5pZCwgY29udGVudDogU3RyaW5nKHJlc3VsdHNbaV0pLnNsaWNl
::B64:agent.js:KDAsIDQwMDApIH0pCiAgICAgICk7CgogICAgICAvLyBLaXJpbSBzY3JlZW5zaG90IChqaWthIGFkYSkgc2ViYWdhaSBnYW1iYXI7IGdhbWJhciBsYW1hIGRpYnVhbmcgYWdhciByaW5nYW4KICAgICAgaWYgKHBlbmRpbmdJbWFnZXMubGVuZ3RoKSB7CiAgICAgICAg
::B64:agent.js:c3RyaXBJbWFnZXMoKTsKICAgICAgICBoaXN0b3J5LnB1c2goewogICAgICAgICAgcm9sZTogInVzZXIiLAogICAgICAgICAgY29udGVudDogWwogICAgICAgICAgICB7IHR5cGU6ICJ0ZXh0IiwgdGV4dDogIkluaSBzY3JlZW5zaG90IGxheWFyIHRlcmJhcnU6IiB9
::B64:agent.js:LAogICAgICAgICAgICAuLi5wZW5kaW5nSW1hZ2VzLnNwbGljZSgwKS5tYXAoKGI2NCkgPT4gKHsKICAgICAgICAgICAgICB0eXBlOiAiaW1hZ2VfdXJsIiwKICAgICAgICAgICAgICBpbWFnZV91cmw6IHsgdXJsOiBgZGF0YTppbWFnZS9wbmc7YmFzZTY0LCR7YjY0
::B64:agent.js:fWAgfSwKICAgICAgICAgICAgfSkpLAogICAgICAgICAgXSwKICAgICAgICB9KTsKICAgICAgfQogICAgfQogICAgY29uc29sZS5sb2coIkJlcmhlbnRpOiBtZWxld2F0aSBiYXRhcyBsYW5na2FoLiIpOwogIH0gY2F0Y2ggKGUpIHsKICAgIGhpc3RvcnkubGVuZ3Ro
::B64:agent.js:ID0gc3RhcnRMZW47IC8vIGJ1YW5nIHJpd2F5YXQgdHVnYXMgeWFuZyBnYWdhbCBzdXBheWEgdGlkYWsgbWVydXNhayBwZXJjYWthcGFuIGJlcmlrdXRueWEKICAgIHRocm93IGU7CiAgfSBmaW5hbGx5IHsKICAgIHN0cmlwSW1hZ2VzKCk7CiAgICB0cmltSGlzdG9y
::B64:agent.js:eSgpOwogIH0KfQoKY29uc3QgQlVJTFRJTl9DSEFOR0VMT0cgPSBgVmVyc2kgOAotIElaSU4gT1RPTUFUSVM6IGFnZW50IHRpZGFrIGxhZ2kgbWVudW5nZ3UgeS9uLiBTZW11YSBpemluIGxhbmdzdW5nIGRpamF3YWIgInlhIiAodGV0YXAgdGVyY2F0YXQgZGkgbGF5
::B64:agent.js:YXIpLiBLYW11IHRpbmdnYWwgbWVudW5nZ3UuCi0gQXR1ciBrYXBhbiBzYWphOiAvYXV0byBvbiAoc2VtdWEgb3RvbWF0aXMpLCAvYXV0byBhbWFuIChvdG9tYXRpcyBrZWN1YWxpIHRpbXBhIGZpbGUsIGhhcHVzLCB0dXR1cCBqZW5kZWxhLCBwaW5kYWgpLCAvYXV0
::B64:agent.js:byBvZmYgKHNlbGFsdSB0YW55YSkuCi0gVmVyc2kgNzogamFsdXIgY2VwYXQgdGFucGEgQUksIHVwbG9hZCBjZXBhdCwgQUkgbGViaWggcmluZ2FuLCBhbGF0IGJhcnUuCktldGlrIC9iYW50dWFuIHVudHVrIGRhZnRhciBsZW5na2FwLmA7Cgpjb25zdCBIRUxQID0g
::B64:agent.js:YApKQUxVUiBDRVBBVCAodGFucGEgQUksIGxhbmdzdW5nIGphbGFuKQogIHB1dGFyIGxhZ3Uga2lzcyBtZSAgfCAgdm9sdW1lIDUwICB8ICBuYWlraW4gdm9sdW1lICB8ICBwYXVzZSAvIG5leHQgLyBtYWp1IDMwICB8ICBidWthIHlvdXR1YmUsIGdtYWlsCiAgYnVr
::B64:agent.js:YSBmb2xkZXIgUmVpYSAgfCAgYnVrYSBrYW1lcmEgIHwgIGNhcmkgZmlsZSBsYXBvcmFuICB8ICBjYXJpIGN1YWNhIGJlc29rIGRpIHdlYiAgfCAgc2NyZWVuc2hvdAogIHVwbG9hZCBsYXBvcmFuLnBkZiBrZSBtZWRpYWZpcmUgIHwgIHVwbG9hZCBmaWxlIHRlcmJh
::B64:agent.js:cnUga2UgbWVkaWFmaXJlICB8ICB1cGxvYWQgc2VtdWEgcGRmIGRpIGZvbGRlciBMYXBvcmFuIGtlIG1lZGlhZmlyZQogIGluZ2F0a2FuIDEwIG1lbml0IGxhZ2kgbWludW0gb2JhdCAgfCAgaW5mbyBwYyAgfCAgamFtIGJlcmFwYQpGSVRVUiBBR0VOVCAobGV3YXQg
::B64:agent.js:QUkgdW50dWsgdHVnYXMgeWFuZyBsZWJpaCBydW1pdCkKICBCcm93c2VyICA6IGJ1a2Egd2Vic2l0ZSwgaXNpIGZvcm0sIGtsaWssIGNhcmkgZGkgd2ViLCBzY3JvbGwsIGJhbnlhayB0YWIKICBZb3VUdWJlICA6IHB1dGFyIG90b21hdGlzIChza2lwIGlrbGFuKSwg
::B64:agent.js:a29udHJvbCBwYXVzZS9uZXh0L21hanUvbXVuZHVyL211dGUvZnVsbHNjcmVlbgogIFVwbG9hZCAgIDogY2VwYXQsIGJhbnlhayBmaWxlLCBzYXR1IGZvbGRlciAoZGktemlwKSwgZGFyaSBsb2thc2kgbWFuYSBwdW4sIG1lbmFtcGlsa2FuIGxpbmsgaGFzaWwKICBM
::B64:agent.js:b2dpbiAgICA6IC9sb2dpbiBsYWx1IGxvZ2luIG1hbnVhbCBzZWthbGksIHNlc2kgdGVyc2ltcGFuLiBBZ2VudCB0aWRhayBwZXJuYWggbWVuZ2V0aWsgcGFzc3dvcmRtdQogIExheWFyICAgIDogc2NyZWVuc2hvdCwga2xpaywgc2Nyb2xsLCBrZXRpaywgdGVrYW4g
::B64:agent.js:dG9tYm9sLCBqZW5kZWxhCiAgRmlsZSAgICAgOiBjYXJpIGZpbGUvZm9sZGVyIHNlbXVhIGRyaXZlLCBiYWNhL3R1bGlzLCBzYWxpbiwgcGluZGFoLCB6aXAsIGhhcHVzIGtlIFJlY3ljbGUgQmluLCB1bmR1aCwgY2FyaSB0ZWtzCiAgUEMgICAgICAgOiB2b2x1bWUs
::B64:agent.js:IHRvbWJvbCBtZWRpYSwgY2xpcGJvYXJkLCBpbmZvIHNpc3RlbSwgYmljYXJhLCBwZW5naW5nYXQKUEVSSU5UQUggS0hVU1VTCiAgL2xvZ2luIFthbGFtYXRdICBsb2dpbiBtYW51YWwgICAgICAgICAgICAvYmFydSAgIGZpdHVyIHRlcmJhcnUgICAgICAgICAgL2Zh
::B64:agent.js:c3Qgb258b2ZmICBqYWx1ciBjZXBhdAogIC90ZXMgICAgICAgICAgICAgdWppIG1vZGVsLCBwaWxpaCBURVJDRVBBVCAgICAvbW9kZWwgW25hbWFdICBsaWhhdC9nYW50aSBtb2RlbAogIC91cGRhdGUgICAgICAgICAgcGVyYmFydWkgc2VrYXJhbmcgICAgICAgL3Zl
::B64:agent.js:cnNpICBjZWsgdmVyc2kgICAgICAgICAgICAgIC9yZXNldCAgbHVwYWthbiBwZXJjYWthcGFuCiAgL2F1dG8gb258YW1hbnxvZmYgIGl6aW4gb3RvbWF0aXMgeWEgLyBvdG9tYXRpcyBrZWN1YWxpIGFrc2kgbWVydXNhayAvIHNlbGFsdSB0YW55YQogIC9iYW50dWFu
::B64:agent.js:ICAgICAgICAgdGFtcGlsa2FuIGluaSAgICAgICAgICAgZXhpdCAgICBrZWx1YXIKYDsKCmZ1bmN0aW9uIHNob3dXaGF0c05ldyhmb3JjZSA9IGZhbHNlKSB7CiAgY29uc3QgdmVyID0gbG9jYWxWZXJzaW9uKCk7CiAgbGV0IHNlZW4gPSAiIjsKICB0cnkgewogICAg
::B64:agent.js:c2VlbiA9IGZzLnJlYWRGaWxlU3luYygiLndoYXRzbmV3LXNlZW4iLCAidXRmOCIpLnRyaW0oKTsKICB9IGNhdGNoIHt9CiAgaWYgKCFmb3JjZSAmJiBzZWVuID09PSB2ZXIpIHJldHVybjsKICBsZXQgdGV4dCA9ICIiOwogIHRyeSB7CiAgICB0ZXh0ID0gZnMucmVh
::B64:agent.js:ZEZpbGVTeW5jKCJjaGFuZ2Vsb2cudHh0IiwgInV0ZjgiKS50cmltKCk7CiAgfSBjYXRjaCB7fQogIGlmICghdGV4dCkgdGV4dCA9IEJVSUxUSU5fQ0hBTkdFTE9HOwogIGNvbnNvbGUubG9nKCJcbj09PT09PT09PT09PT09PT09PSBZQU5HIEJBUlUgPT09PT09PT09
::B64:agent.js:PT09PT09PT09Iik7CiAgY29uc29sZS5sb2codGV4dC5zcGxpdCgvXHI/XG4vKS5zbGljZSgwLCAzMCkuam9pbigiXG4iKSk7CiAgY29uc29sZS5sb2coIj09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09Iik7CiAgdHJ5IHsKICAg
::B64:agent.js:IGZzLndyaXRlRmlsZVN5bmMoIi53aGF0c25ldy1zZWVuIiwgdmVyKTsKICB9IGNhdGNoIHt9Cn0KCmNvbnNvbGUubG9nKGBBZ2VudCBzaWFwLiBWZXJzaSAke2xvY2FsVmVyc2lvbigpfS4gRm9sZGVyIHVwbG9hZDogJHtTQUZFX0RJUn1gKTsKY29uc29sZS5sb2co
::B64:agent.js:YEl6aW4gYWtzaTogJHt7IG9uOiAiT1RPTUFUSVMgKHNlbXVhIGxhbmdzdW5nIHlhKSIsIGFtYW46ICJPVE9NQVRJUyBrZWN1YWxpIGFrc2kgbWVydXNhayIsIG9mZjogIlNFTEFMVSBUQU5ZQSIgfVthdXRvTW9kZV19LiBVYmFoIGRlbmdhbiAvYXV0by4gQ3RybCtD
::B64:agent.js:IHVudHVrIG1lbmdoZW50aWthbi5gKTsKc2hvd1doYXRzTmV3KCk7CmNvbnNvbGUubG9nKCdLZXRpayBwZXJpbnRhaCBkYWxhbSBiYWhhc2EgYmlhc2EuIEtldGlrIC9iYW50dWFuIHVudHVrIGRhZnRhciBmaXR1ciwgL2xvZ2luIHVudHVrIGxvZ2luLCBleGl0IHVu
::B64:agent.js:dHVrIGtlbHVhci4nKTsKY2hlY2tVcGRhdGUoKTsKd2hpbGUgKHRydWUpIHsKICBjb25zdCBjbWQgPSBhd2FpdCBybC5xdWVzdGlvbigiXG5QZXJpbnRhaD4gIik7CiAgY29uc3QgYyA9IGNtZC50cmltKCk7CiAgaWYgKGMgPT09ICJleGl0IikgYnJlYWs7CiAgaWYg
::B64:agent.js:KCFjKSBjb250aW51ZTsKICBpZiAoYyA9PT0gIi90ZXMiKSB7CiAgICBpZiAoIWZhbGxiYWNrTW9kZWxzKSBmYWxsYmFja01vZGVscyA9IGF3YWl0IGRpc2NvdmVyTW9kZWxzKCk7CiAgICBjb25zdCBsaXN0ID0gbW9kZWxQb29sKCkuc2xpY2UoMCwgOSk7CiAgICBj
::B64:agent.js:b25zb2xlLmxvZyhgTWVuZ3VqaSAke2xpc3QubGVuZ3RofSBtb2RlbCwgdGlhcCBtb2RlbCBtYWtzaW1hbCA0NSBkZXRpay4uLmApOwogICAgY29uc3QgcmVzdWx0cyA9IGF3YWl0IFByb21pc2UuYWxsKGxpc3QubWFwKGFzeW5jIChtKSA9PiAoeyBtLCByOiBhd2Fp
::B64:agent.js:dCB0ZXN0TW9kZWwobSkgfSkpKTsgLy8gZGl1amkgYmVyc2FtYWFuCiAgICBmb3IgKGNvbnN0IHsgbSwgciB9IG9mIHJlc3VsdHMpIGNvbnNvbGUubG9nKGAgICR7ci5tYXJrfSAke219ICAgJHtyLm1zfSBtcyAgICR7ci50ZXh0fWApOwogICAgY29uc3QgYmVzdCA9
::B64:agent.js:IHJlc3VsdHMuZmlsdGVyKCh4KSA9PiB4LnIubWFyayA9PT0gIltPS10iKS5zb3J0KCh4LCB5KSA9PiB4LnIubXMgLSB5LnIubXMpWzBdPy5tIHx8ICIiOwogICAgaWYgKCFiZXN0KSB7CiAgICAgIGNvbnNvbGUubG9nKCJcblRpZGFrIGFkYSBtb2RlbCB5YW5nIGxv
::B64:agent.js:bG9zLiBDZWsgZGFzaGJvYXJkIDlSb3V0ZXI6IHByb3ZpZGVyIHRlcmh1YnVuZywga3VvdGEsIGRhbiBtZW51IENvbnNvbGUgTG9nLiIpOwogICAgfSBlbHNlIGlmIChiZXN0ID09PSBiYXNlTW9kZWwpIHsKICAgICAgY29uc29sZS5sb2coYFxuTW9kZWwgYWt0aWYg
::B64:agent.js:KCR7YmFzZU1vZGVsfSkgc3VkYWggeWFuZyB0ZXJjZXBhdCBkYW4gYmVyZnVuZ3NpLmApOwogICAgfSBlbHNlIHsKICAgICAgYmFzZU1vZGVsID0gYmVzdDsKICAgICAgcG9vbElkeCA9IDA7CiAgICAgIHRyeSB7CiAgICAgICAgZnMud3JpdGVGaWxlU3luYyhNT0RF
::B64:agent.js:TF9GSUxFLCBiZXN0KTsKICAgICAgfSBjYXRjaCB7fQogICAgICBjb25zb2xlLmxvZyhgXG5Nb2RlbCB0ZXJjZXBhdCB5YW5nIGJlcmZ1bmdzaSBkaXBpbGloIG90b21hdGlzOiAke2Jlc3R9ICh0ZXJzaW1wYW4sIGtldGlrIC9tb2RlbCByZXNldCB1bnR1ayBrZW1i
::B64:agent.js:YWxpIGtlIGJhd2FhbikuYCk7CiAgICB9CiAgICBjb250aW51ZTsKICB9CiAgaWYgKGMgPT09ICIvbW9kZWwiIHx8IGMuc3RhcnRzV2l0aCgiL21vZGVsICIpKSB7CiAgICBjb25zdCBhcmcgPSBjLnNsaWNlKDYpLnRyaW0oKTsKICAgIGlmICghYXJnKSB7CiAgICAg
::B64:agent.js:IGlmICghZmFsbGJhY2tNb2RlbHMpIGZhbGxiYWNrTW9kZWxzID0gYXdhaXQgZGlzY292ZXJNb2RlbHMoKTsKICAgICAgY29uc29sZS5sb2coYE1vZGVsIGFrdGlmOiAke2Jhc2VNb2RlbH1cbk1vZGVsIGxhaW4geWFuZyB0ZXJzZWRpYTogJHttb2RlbFBvb2woKS5z
::B64:agent.js:bGljZSgxKS5qb2luKCIsICIpIHx8ICIodGlkYWsgYWRhKSJ9YCk7CiAgICB9IGVsc2UgaWYgKGFyZyA9PT0gInJlc2V0IikgewogICAgICB0cnkgewogICAgICAgIGZzLnVubGlua1N5bmMoTU9ERUxfRklMRSk7CiAgICAgIH0gY2F0Y2gge30KICAgICAgYmFzZU1v
::B64:agent.js:ZGVsID0gTU9ERUw7CiAgICAgIHBvb2xJZHggPSAwOwogICAgICBjb25zb2xlLmxvZyhgS2VtYmFsaSBrZSBtb2RlbCBiYXdhYW46ICR7TU9ERUx9YCk7CiAgICB9IGVsc2UgewogICAgICBiYXNlTW9kZWwgPSBhcmc7CiAgICAgIHBvb2xJZHggPSAwOwogICAgICB0
::B64:agent.js:cnkgewogICAgICAgIGZzLndyaXRlRmlsZVN5bmMoTU9ERUxfRklMRSwgYXJnKTsKICAgICAgfSBjYXRjaCB7fQogICAgICBjb25zb2xlLmxvZyhgTW9kZWwgZGlnYW50aSBrZTogJHthcmd9YCk7CiAgICB9CiAgICBjb250aW51ZTsKICB9CiAgaWYgKGMgPT09ICIv
::B64:agent.js:YmFudHVhbiIpIHsKICAgIGNvbnNvbGUubG9nKEhFTFApOwogICAgY29udGludWU7CiAgfQogIGlmIChjID09PSAiL2JhcnUiKSB7CiAgICBzaG93V2hhdHNOZXcodHJ1ZSk7CiAgICBjb250aW51ZTsKICB9CiAgaWYgKGMuc3RhcnRzV2l0aCgiL2xvZ2luIikpIHsK
::B64:agent.js:ICAgIGxldCB0YXJnZXQgPSBjLnNwbGl0KC9ccysvKVsxXSB8fCAiaHR0cHM6Ly9hY2NvdW50cy5nb29nbGUuY29tL1NlcnZpY2VMb2dpbj9zZXJ2aWNlPXlvdXR1YmUmY29udGludWU9aHR0cHM6Ly93d3cueW91dHViZS5jb20vIjsKICAgIGlmICghL15odHRwcz86
::B64:agent.js:XC9cLy9pLnRlc3QodGFyZ2V0KSkgdGFyZ2V0ID0gImh0dHBzOi8vIiArIHRhcmdldDsKICAgIHRyeSB7CiAgICAgIGF3YWl0IGVuc3VyZVBhZ2UoKTsKICAgICAgYXdhaXQgcGFnZS5icmluZ1RvRnJvbnQoKTsKICAgICAgYXdhaXQgcGFnZS5nb3RvKHRhcmdldCwg
::B64:agent.js:eyB3YWl0VW50aWw6ICJkb21jb250ZW50bG9hZGVkIiB9KTsKICAgIH0gY2F0Y2ggKGUpIHsKICAgICAgY29uc29sZS5sb2coIkdhZ2FsIG1lbWJ1a2EgaGFsYW1hbiBsb2dpbjoiLCBlLm1lc3NhZ2UpOwogICAgfQogICAgY29uc29sZS5sb2coIlNpbGFrYW4gbG9n
::B64:agent.js:aW4gZGkgamVuZGVsYSBicm93c2VyIChrYW11IHlhbmcgbWVuZ2V0aWssIGFnZW50IHRpZGFrIG1lbGloYXQgcGFzc3dvcmQpLiIpOwogICAgYXdhaXQgcmwucXVlc3Rpb24oIlNldGVsYWggc2VsZXNhaSwgdGVrYW4gRW50ZXIgZGkgc2luaS4uLiAiKTsKICAgIGNv
::B64:agent.js:bnNvbGUubG9nKCJMb2dpbiB0ZXJzaW1wYW4gZGkgcHJvZmlsIGJyb3dzZXIuIEJlcmlrdXRueWEgdGlkYWsgcGVybHUgbG9naW4gbGFnaS4iKTsKICAgIGNvbnRpbnVlOwogIH0KICBpZiAoYyA9PT0gIi92ZXJzaSIpIHsKICAgIGNvbnNvbGUubG9nKGBWZXJzaSBh
::B64:agent.js:Z2VudDogJHtsb2NhbFZlcnNpb24oKX1gKTsKICAgIGF3YWl0IGNoZWNrVXBkYXRlKCk7CiAgICBpZiAoIXBlbmRpbmdWZXJzaW9uKSBjb25zb2xlLmxvZygiU3VkYWggdmVyc2kgdGVyYmFydSAoYXRhdSB1cGRhdGUgb25saW5lIHRpZGFrIGFrdGlmKS4iKTsKICAg
::B64:agent.js:IGNvbnRpbnVlOwogIH0KICBpZiAoYyA9PT0gIi91cGRhdGUiKSB7CiAgICBjb25zb2xlLmxvZygiTWVtcGVyYmFydWkuLi4gYWdlbnQgYWthbiBtZW51dHVwIGRhbiBtZW55YWxhIGxhZ2kgb3RvbWF0aXMgbGV3YXQgc3RhcnQtYWdlbnQuYmF0LiIpOwogICAgYXdh
::B64:agent.js:aXQgc2h1dGRvd25Ccm93c2VyKCk7CiAgICBybC5jbG9zZSgpOwogICAgcHJvY2Vzcy5leGl0KDQyKTsgLy8ga29kZSA0MiA9IHBlcm1pbnRhYW4gcmVzdGFydCB1bnR1ayB1cGRhdGU7IGRpdGFuZ2thcCBvbGVoIHN0YXJ0LWFnZW50LmJhdAogIH0KICBpZiAoYyA9
::B64:agent.js:PT0gIi9hdXRvIiB8fCBjLnN0YXJ0c1dpdGgoIi9hdXRvICIpKSB7CiAgICBjb25zdCBhcmcgPSBjLnNsaWNlKDUpLnRyaW0oKS50b0xvd2VyQ2FzZSgpOwogICAgY29uc3QgYWxpYXMgPSB7IHlhOiAib24iLCBvdG9tYXRpczogIm9uIiwgdHJ1ZTogIm9uIiwgdGFu
::B64:agent.js:eWE6ICJvZmYiLCBtYW51YWw6ICJvZmYiLCBtYXRpOiAib2ZmIiB9OwogICAgY29uc3QgbW9kZSA9IGFsaWFzW2FyZ10gfHwgYXJnOwogICAgaWYgKFsib24iLCAiYW1hbiIsICJvZmYiXS5pbmNsdWRlcyhtb2RlKSkgewogICAgICBhdXRvTW9kZSA9IG1vZGU7CiAg
::B64:agent.js:ICAgIHRyeSB7CiAgICAgICAgZnMud3JpdGVGaWxlU3luYyhBVVRPX0ZJTEUsIG1vZGUpOwogICAgICB9IGNhdGNoIHt9CiAgICB9IGVsc2UgaWYgKGFyZykgewogICAgICBjb25zb2xlLmxvZygiUGlsaWhhbjogL2F1dG8gb24sIC9hdXRvIGFtYW4sIC9hdXRvIG9m
::B64:agent.js:ZiIpOwogICAgICBjb250aW51ZTsKICAgIH0KICAgIGNvbnNvbGUubG9nKAogICAgICBgSXppbiBha3NpIHNla2FyYW5nOiAke3sgb246ICJPVE9NQVRJUywgc2VtdWEgbGFuZ3N1bmcgeWEgKGthbXUgdGlkYWsgcGVybHUgbWVudW5nZ3UpIiwgYW1hbjogIk9UT01B
::B64:agent.js:VElTIGtlY3VhbGkgYWtzaSBtZXJ1c2FrICh0aW1wYSBmaWxlLCBoYXB1cywgdHV0dXAgamVuZGVsYSwgcGluZGFoKSB5YW5nIHRldGFwIGJlcnRhbnlhIiwgb2ZmOiAiU0VMQUxVIFRBTllBIHkvbiIgfVthdXRvTW9kZV19YAogICAgKTsKICAgIGNvbnRpbnVlOwog
::B64:agent.js:IH0KICBpZiAoYyA9PT0gIi9mYXN0IiB8fCBjLnN0YXJ0c1dpdGgoIi9mYXN0ICIpKSB7CiAgICBjb25zdCBhcmcgPSBjLnNsaWNlKDUpLnRyaW0oKS50b0xvd2VyQ2FzZSgpOwogICAgaWYgKGFyZyA9PT0gIm9uIikgRkFTVCA9IHRydWU7CiAgICBlbHNlIGlmIChh
::B64:agent.js:cmcgPT09ICJvZmYiKSBGQVNUID0gZmFsc2U7CiAgICBjb25zb2xlLmxvZyhgSmFsdXIgY2VwYXQgKHRhbnBhIEFJIHVudHVrIHBlcmludGFoIHVtdW0pOiAke0ZBU1QgPyAiQUtUSUYiIDogIk1BVEkifS4gS2V0aWsgL2Zhc3Qgb24gYXRhdSAvZmFzdCBvZmYuYCk7
::B64:agent.js:CiAgICBjb250aW51ZTsKICB9CiAgaWYgKGMgPT09ICIvcmVzZXQiKSB7CiAgICBoaXN0b3J5Lmxlbmd0aCA9IDA7CiAgICBleHRyYUdyb3Vwcy5jbGVhcigpOwogICAgY29uc29sZS5sb2coIlBlcmNha2FwYW4gZGlsdXBha2FuLiIpOwogICAgY29udGludWU7CiAg
::B64:agent.js:fQogIGNvbnN0IHQwID0gRGF0ZS5ub3coKTsKICBjb25zdCBkZXRpayA9ICgpID0+ICgoRGF0ZS5ub3coKSAtIHQwKSAvIDEwMDApLnRvRml4ZWQoMSk7CiAgaWYgKEZBU1QpIHsKICAgIGxldCByID0gbnVsbDsKICAgIHRyeSB7CiAgICAgIHIgPSBhd2FpdCB0cnlG
::B64:agent.js:YXN0Q29tbWFuZChjKTsKICAgIH0gY2F0Y2ggKGUpIHsKICAgICAgY29uc29sZS5sb2coYCAgKGphbHVyIGNlcGF0IGdhZ2FsOiAke1N0cmluZyhlLm1lc3NhZ2UpLnNsaWNlKDAsIDE2MCl9LiBEaXNlcmFoa2FuIGtlIEFJLi4uKWApOwogICAgfQogICAgaWYgKHIg
::B64:agent.js:IT0gbnVsbCkgewogICAgICBjb25zb2xlLmxvZyhgXG5bY2VwYXRdICR7cn1cbigke2RldGlrKCl9IGR0aywgdGFucGEgQUkpYCk7CiAgICAgIGhpc3RvcnkucHVzaCh7IHJvbGU6ICJ1c2VyIiwgY29udGVudDogYyB9LCB7IHJvbGU6ICJhc3Npc3RhbnQiLCBjb250
::B64:agent.js:ZW50OiBgW2phbHVyIGNlcGF0XSAke1N0cmluZyhyKS5zbGljZSgwLCA1MDApfWAgfSk7CiAgICAgIHRyaW1IaXN0b3J5KCk7CiAgICAgIGNvbnRpbnVlOwogICAgfQogIH0KICB0cnkgewogICAgYXdhaXQgcnVuVGFzayhjKTsKICAgIGNvbnNvbGUubG9nKGAoc2Vs
::B64:agent.js:ZXNhaSBkYWxhbSAke2RldGlrKCl9IGR0aylgKTsKICB9IGNhdGNoIChlKSB7CiAgICBjb25zb2xlLmVycm9yKCJHYWdhbDoiLCBlLm1lc3NhZ2UpOwogIH0KfQphd2FpdCBzaHV0ZG93bkJyb3dzZXIoKTsKcmwuY2xvc2UoKTsK
::B64:package.json:ewogICJuYW1lIjogImJvdC1hZ2VudCIsCiAgInZlcnNpb24iOiAiMS4wLjAiLAogICJ0eXBlIjogIm1vZHVsZSIsCiAgInNjcmlwdHMiOiB7CiAgICAic3RhcnQiOiAibm9kZSBhZ2VudC5qcyIKICB9LAogICJkZXBlbmRlbmNpZXMiOiB7CiAgICAicGxheXdyaWdo
::B64:package.json:dCI6ICJeMS40OC4wIgogIH0KfQo=
