@echo off
setlocal EnableExtensions
title Agent Automation
set "SELF=%~f0"
set "EMBED_VER=3"

rem ============================================================
rem  AGENT AUTOMATION - All-in-one (folder + file + setup + update + run)
rem  Pemakaian biasa : klik dua kali file ini, di folder mana pun
rem  Ganti API key   : start-agent.bat reset
rem  Atur URL update : start-agent.bat seturl
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
if defined UPDATE_URL goto EXTRACT_DECIDED
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
echo [3/7] Memeriksa pembaruan...
if defined UPDATE_URL goto UPDATE_CHECK
echo     Update online belum aktif. Untuk mengaktifkan: start-agent.bat seturl
goto UPDATE_DONE
:UPDATE_CHECK
curl.exe -fsSL --max-time 15 -o ".remote-version" "%UPDATE_URL%/version.txt" 2>nul
if errorlevel 1 goto UPDATE_OFFLINE
set "LOCALVER=0"
if exist "version.txt" set /p LOCALVER=<"version.txt"
set "REMOTEVER="
set /p REMOTEVER=<".remote-version"
if not defined REMOTEVER goto UPDATE_OFFLINE
if "%LOCALVER%"=="%REMOTEVER%" goto UPDATE_SAME
echo     Versi baru %REMOTEVER% tersedia, versi sekarang %LOCALVER%. Mengunduh...
copy /y "package.json" "package.json.bak" >nul
set "UPDATE_FAILED="
curl.exe -fsSL --max-time 15 -o ".remote-files" "%UPDATE_URL%/files.txt" 2>nul
if errorlevel 1 goto UPDATE_FAIL
for /f "usebackq delims=" %%F in (".remote-files") do call :DL_FILE "%%F"
if defined UPDATE_FAILED goto UPDATE_FAIL
copy /y ".remote-version" "version.txt" >nul
fc "package.json" "package.json.bak" >nul 2>&1
if errorlevel 1 set "NEED_INSTALL=1"
echo     Pembaruan selesai. Sekarang versi %REMOTEVER%.
goto UPDATE_DONE
:UPDATE_SAME
echo     Sudah versi terbaru: %LOCALVER%
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
if exist "config.bat" call "config.bat"
if defined ROUTER_KEY goto KEY_LOADED

echo.
echo     Masukkan API key dari dashboard 9Router.
echo     Lokasinya: http://localhost:20128/dashboard  menu  Endpoint ^& Key
echo.
set /p "ROUTER_KEY=    API Key: "
if not defined ROUTER_KEY goto KEY_STEP
call :SAVE_CONFIG
call :ASK_URL
call :SAVE_CONFIG
echo     Key tersimpan. Berikutnya tidak perlu input lagi.
goto KEY_VALIDATE

:KEY_LOADED
echo     Key ditemukan dari penyimpanan.

:KEY_VALIDATE
set "HTTPCODE="
for /f %%i in ('curl.exe -s -o nul -w "%%{http_code}" -H "Authorization: Bearer %ROUTER_KEY%" http://localhost:20128/v1/models 2^>nul') do set "HTTPCODE=%%i"
if "%HTTPCODE%"=="401" goto BAD_KEY
if "%HTTPCODE%"=="403" goto BAD_KEY
goto RUN_AGENT

:BAD_KEY
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
echo.
echo Agent berhenti.
pause
exit /b 0

rem ---------- Subroutine: simpan konfigurasi ----------
:SAVE_CONFIG
> "config.bat" echo set "ROUTER_KEY=%ROUTER_KEY%"
>> "config.bat" echo set "ROUTER_MODEL=bot-combo"
>> "config.bat" echo set "SAFE_DIR=%APPDIR%\upload-folder"
>> "config.bat" echo set "CONFIRM=1"
if defined UPDATE_URL >> "config.bat" echo set "UPDATE_URL=%UPDATE_URL%"
exit /b 0

rem ---------- Subroutine: tanya URL update ----------
:ASK_URL
echo.
echo     Update otomatis ^(opsional^): isi alamat tempat file agent disimpan online,
echo     contoh: https://raw.githubusercontent.com/NAMAKAMU/NAMAREPO/main
echo     Tekan Enter untuk melewati.
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
curl.exe -fsSL --max-time 60 -o "%FN%.new" "%UPDATE_URL%/%FN%" 2>nul
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
::B64:agent.js:SF9ST09UUy5zcGxpdCgiOyIpIDogW10pXTsKCmlmICghQVBJX0tFWSkgewogIGNvbnNvbGUuZXJyb3IoIlJPVVRFUl9LRVkgYmVsdW0gZGlpc2kuIik7CiAgcHJvY2Vzcy5leGl0KDEpOwp9CmZzLm1rZGlyU3luYyhTQUZFX0RJUiwgeyByZWN1cnNpdmU6IHRydWUg
::B64:agent.js:fSk7Cgpjb25zdCBybCA9IHJlYWRsaW5lLmNyZWF0ZUludGVyZmFjZSh7IGlucHV0OiBwcm9jZXNzLnN0ZGluLCBvdXRwdXQ6IHByb2Nlc3Muc3Rkb3V0IH0pOwpjb25zdCBzbGVlcCA9IChtcykgPT4gbmV3IFByb21pc2UoKHIpID0+IHNldFRpbWVvdXQociwgbXMp
::B64:agent.js:KTsKCi8vIEJyb3dzZXIgZGVuZ2FuIHByb2ZpbCBwZXJtYW5lbjogbG9naW4gc2VrYWxpLCBzZXNpIHRlcnNpbXBhbgpjb25zdCBjb250ZXh0ID0gYXdhaXQgY2hyb21pdW0ubGF1bmNoUGVyc2lzdGVudENvbnRleHQoIi4vYnJvd3Nlci1wcm9maWxlIiwgewogIGhl
::B64:agent.js:YWRsZXNzOiBmYWxzZSwKICBhcmdzOiBbIi0tYXV0b3BsYXktcG9saWN5PW5vLXVzZXItZ2VzdHVyZS1yZXF1aXJlZCJdLAp9KTsKY29uc3QgcGFnZSA9IGNvbnRleHQucGFnZXMoKVswXSB8fCAoYXdhaXQgY29udGV4dC5uZXdQYWdlKCkpOwoKZnVuY3Rpb24gc2Fm
::B64:agent.js:ZVBhdGgobmFtZSkgewogIGNvbnN0IGZ1bGwgPSBwYXRoLnJlc29sdmUoU0FGRV9ESVIsIG5hbWUpOwogIGlmICghZnVsbC5zdGFydHNXaXRoKFNBRkVfRElSKSkgdGhyb3cgbmV3IEVycm9yKCJGaWxlIGRpIGx1YXIgZm9sZGVyIHlhbmcgZGlpemlua2FuIik7CiAg
::B64:agent.js:cmV0dXJuIGZ1bGw7Cn0KCmFzeW5jIGZ1bmN0aW9uIGFzayhtc2cpIHsKICBpZiAoIUNPTkZJUk0pIHJldHVybiB0cnVlOwogIGNvbnN0IGEgPSBhd2FpdCBybC5xdWVzdGlvbihgXG5bSVpJTl0gJHttc2d9ICh5L24pOiBgKTsKICByZXR1cm4gYS50cmltKCkudG9M
::B64:agent.js:b3dlckNhc2UoKSA9PT0gInkiOwp9CgovLyA9PT09PSBIZWxwZXIgUG93ZXJTaGVsbCAoa29udHJvbCBkZXNrdG9wIFdpbmRvd3MgdGFucGEgbGlicmFyeSB0YW1iYWhhbikgPT09PT0KZnVuY3Rpb24gcHMoc2NyaXB0LCBlbnYgPSB7fSkgewogIGNvbnN0IGVuY29k
::B64:agent.js:ZWQgPSBCdWZmZXIuZnJvbShzY3JpcHQsICJ1dGYxNmxlIikudG9TdHJpbmcoImJhc2U2NCIpOwogIHJldHVybiBuZXcgUHJvbWlzZSgocmVzb2x2ZSwgcmVqZWN0KSA9PiB7CiAgICBleGVjRmlsZSgKICAgICAgInBvd2Vyc2hlbGwiLAogICAgICBbIi1Ob1Byb2Zp
::B64:agent.js:bGUiLCAiLU5vbkludGVyYWN0aXZlIiwgIi1FbmNvZGVkQ29tbWFuZCIsIGVuY29kZWRdLAogICAgICB7IGVudjogeyAuLi5wcm9jZXNzLmVudiwgLi4uZW52IH0sIHRpbWVvdXQ6IDMwMDAwLCBtYXhCdWZmZXI6IDIwICogMTAyNCAqIDEwMjQgfSwKICAgICAgKGVy
::B64:agent.js:ciwgc3Rkb3V0LCBzdGRlcnIpID0+CiAgICAgICAgZXJyID8gcmVqZWN0KG5ldyBFcnJvcigoc3RkZXJyIHx8IGVyci5tZXNzYWdlKS5zbGljZSgwLCAzMDApKSkgOiByZXNvbHZlKHN0ZG91dC50cmltKCkpCiAgICApOwogIH0pOwp9Cgpjb25zdCBQU19IRUFEID0g
::B64:agent.js:YApBZGQtVHlwZSBAIgp1c2luZyBTeXN0ZW07CnVzaW5nIFN5c3RlbS5SdW50aW1lLkludGVyb3BTZXJ2aWNlczsKcHVibGljIGNsYXNzIFcgewogIFtEbGxJbXBvcnQoInVzZXIzMi5kbGwiKV0gcHVibGljIHN0YXRpYyBleHRlcm4gYm9vbCBTZXRQcm9jZXNzRFBJ
::B64:agent.js:QXdhcmUoKTsKICBbRGxsSW1wb3J0KCJ1c2VyMzIuZGxsIildIHB1YmxpYyBzdGF0aWMgZXh0ZXJuIGJvb2wgU2V0Q3Vyc29yUG9zKGludCB4LCBpbnQgeSk7CiAgW0RsbEltcG9ydCgidXNlcjMyLmRsbCIpXSBwdWJsaWMgc3RhdGljIGV4dGVybiB2b2lkIG1vdXNl
::B64:agent.js:X2V2ZW50KHVpbnQgZiwgdWludCBkeCwgdWludCBkeSwgaW50IGQsIFVJbnRQdHIgZSk7Cn0KIkAKW1ddOjpTZXRQcm9jZXNzRFBJQXdhcmUoKSB8IE91dC1OdWxsCkFkZC1UeXBlIC1Bc3NlbWJseU5hbWUgU3lzdGVtLldpbmRvd3MuRm9ybXMsU3lzdGVtLkRyYXdp
::B64:agent.js:bmcKYDsKCmxldCBzY2FsZSA9IDE7IC8vIHJhc2lvIGxheWFyIGFzbGkgLyBzY3JlZW5zaG90CmNvbnN0IHBlbmRpbmdJbWFnZXMgPSBbXTsgLy8gZ2FtYmFyIHlhbmcgZGlraXJpbSBrZSBtb2RlbCBzZXRlbGFoIHRvb2wgZGlqYWxhbmthbgoKZnVuY3Rpb24gZmlu
::B64:agent.js:ZERpcnMobmFtZSwgcm9vdCwgZGVwdGgsIG91dCkgewogIGlmIChkZXB0aCA8IDAgfHwgb3V0Lmxlbmd0aCA+PSAxMCkgcmV0dXJuOwogIGxldCBlbnRyaWVzOwogIHRyeSB7CiAgICBlbnRyaWVzID0gZnMucmVhZGRpclN5bmMocm9vdCwgeyB3aXRoRmlsZVR5cGVz
::B64:agent.js:OiB0cnVlIH0pOwogIH0gY2F0Y2ggewogICAgcmV0dXJuOwogIH0KICBmb3IgKGNvbnN0IGUgb2YgZW50cmllcykgewogICAgaWYgKCFlLmlzRGlyZWN0b3J5KCkpIGNvbnRpbnVlOwogICAgaWYgKFsibm9kZV9tb2R1bGVzIiwgIkFwcERhdGEiLCAiLmdpdCJdLmlu
::B64:agent.js:Y2x1ZGVzKGUubmFtZSkgfHwgZS5uYW1lLnN0YXJ0c1dpdGgoIiQiKSkgY29udGludWU7CiAgICBjb25zdCBmdWxsID0gcGF0aC5qb2luKHJvb3QsIGUubmFtZSk7CiAgICBpZiAoZS5uYW1lLnRvTG93ZXJDYXNlKCkuaW5jbHVkZXMobmFtZS50b0xvd2VyQ2FzZSgp
::B64:agent.js:KSkgb3V0LnB1c2goZnVsbCk7CiAgICBmaW5kRGlycyhuYW1lLCBmdWxsLCBkZXB0aCAtIDEsIG91dCk7CiAgfQp9CgovLyA9PT09PSAiVGFuZ2FuIiBhZ2VudCA9PT09PQpjb25zdCBpbXBsID0gewogIC8vIC0tLSBEZXNrdG9wOiBmaWxlICYgZm9sZGVyIC0tLQog
::B64:agent.js:IGZpbmRfZm9sZGVyOiBhc3luYyAoeyBuYW1lIH0pID0+IHsKICAgIGNvbnN0IG91dCA9IFtdOwogICAgZm9yIChjb25zdCByb290IG9mIFNFQVJDSF9ST09UUykgZmluZERpcnMoU3RyaW5nKG5hbWUpLCByb290LCA0LCBvdXQpOwogICAgcmV0dXJuIG91dC5sZW5n
::B64:agent.js:dGggPyBvdXQuam9pbigiXG4iKSA6ICJUaWRhayBkaXRlbXVrYW4iOwogIH0sCgogIGxpc3RfZGlyOiBhc3luYyAoeyBwYXRoOiBwIH0pID0+IHsKICAgIGNvbnN0IGl0ZW1zID0gZnMucmVhZGRpclN5bmMocCwgeyB3aXRoRmlsZVR5cGVzOiB0cnVlIH0pLnNsaWNl
::B64:agent.js:KDAsIDEwMCk7CiAgICByZXR1cm4gaXRlbXMubWFwKChlKSA9PiAoZS5pc0RpcmVjdG9yeSgpID8gIltESVJdICIgOiAiW0ZJTEVdICIpICsgZS5uYW1lKS5qb2luKCJcbiIpIHx8ICIoa29zb25nKSI7CiAgfSwKCiAgb3Blbl9wYXRoOiBhc3luYyAoeyB0YXJnZXQg
::B64:agent.js:fSkgPT4gewogICAgaWYgKCEoYXdhaXQgYXNrKGBCdWthOiAke3RhcmdldH1gKSkpIHJldHVybiAiRGliYXRhbGthbiB1c2VyIjsKICAgIGF3YWl0IHBzKCJTdGFydC1Qcm9jZXNzIC1GaWxlUGF0aCAkZW52OlRBUkdFVCIsIHsgVEFSR0VUOiBTdHJpbmcodGFyZ2V0
::B64:agent.js:KSB9KTsKICAgIGF3YWl0IHNsZWVwKDE1MDApOwogICAgcmV0dXJuICJvaywgZGlidWthIjsKICB9LAoKICAvLyAtLS0gRGVza3RvcDogbGF5YXIsIG1vdXNlLCBrZXlib2FyZCAtLS0KICBzY3JlZW5zaG90OiBhc3luYyAoKSA9PiB7CiAgICBjb25zdCBvdXQgPSBw
::B64:agent.js:YXRoLnJlc29sdmUoInNjcmVlbi5wbmciKTsKICAgIGNvbnN0IHIgPSBhd2FpdCBwcygKICAgICAgUFNfSEVBRCArCiAgICAgICAgYAokYiA9IFtTeXN0ZW0uV2luZG93cy5Gb3Jtcy5TY3JlZW5dOjpQcmltYXJ5U2NyZWVuLkJvdW5kcwokYm1wID0gTmV3LU9iamVj
::B64:agent.js:dCBTeXN0ZW0uRHJhd2luZy5CaXRtYXAgJGIuV2lkdGgsICRiLkhlaWdodAokZyA9IFtTeXN0ZW0uRHJhd2luZy5HcmFwaGljc106OkZyb21JbWFnZSgkYm1wKQokZy5Db3B5RnJvbVNjcmVlbigkYi5YLCAkYi5ZLCAwLCAwLCAkYm1wLlNpemUpCiRudyA9IFtNYXRo
::B64:agent.js:XTo6TWluKDEyODAsICRiLldpZHRoKQokbmggPSBbaW50XSgkYi5IZWlnaHQgKiAkbncgLyAkYi5XaWR0aCkKJHNtYWxsID0gTmV3LU9iamVjdCBTeXN0ZW0uRHJhd2luZy5CaXRtYXAgJGJtcCwgJG53LCAkbmgKJHNtYWxsLlNhdmUoJGVudjpPVVQsIFtTeXN0ZW0u
::B64:agent.js:RHJhd2luZy5JbWFnaW5nLkltYWdlRm9ybWF0XTo6UG5nKQpXcml0ZS1PdXRwdXQgIiQoJGIuV2lkdGgpLCRudywkbmgiCmAsCiAgICAgIHsgT1VUOiBvdXQgfQogICAgKTsKICAgIGNvbnN0IFt3LCBudywgbmhdID0gci5zcGxpdCgiXG4iKS5wb3AoKS5zcGxpdCgi
::B64:agent.js:LCIpLm1hcChOdW1iZXIpOwogICAgc2NhbGUgPSB3IC8gbnc7CiAgICBwZW5kaW5nSW1hZ2VzLnB1c2goZnMucmVhZEZpbGVTeW5jKG91dCkudG9TdHJpbmcoImJhc2U2NCIpKTsKICAgIHJldHVybiBgU2NyZWVuc2hvdCBkaWFtYmlsICgke253fXgke25ofSkuIEdh
::B64:agent.js:bWJhcm55YSBhZGEgZGkgcGVzYW4gYmVyaWt1dG55YS4gUGFrYWkga29vcmRpbmF0IGRhcmkgZ2FtYmFyIGl0dS5gOwogIH0sCgogIGNsaWNrX3NjcmVlbjogYXN5bmMgKHsgeCwgeSwgYnV0dG9uID0gImxlZnQiLCBkb3VibGUgPSBmYWxzZSB9KSA9PiB7CiAgICBj
::B64:agent.js:b25zdCByeCA9IE1hdGgucm91bmQoTnVtYmVyKHgpICogc2NhbGUpOwogICAgY29uc3QgcnkgPSBNYXRoLnJvdW5kKE51bWJlcih5KSAqIHNjYWxlKTsKICAgIGNvbnN0IGRibCA9IGRvdWJsZSA9PT0gdHJ1ZSB8fCBkb3VibGUgPT09ICJ0cnVlIjsKICAgIGlmICgh
::B64:agent.js:KGF3YWl0IGFzayhgJHtkYmwgPyAiRG91YmxlLWtsaWsiIDogIktsaWsifSAke2J1dHRvbn0gZGkgKCR7eH0sJHt5fSlgKSkpIHJldHVybiAiRGliYXRhbGthbiB1c2VyIjsKICAgIGF3YWl0IHBzKAogICAgICBQU19IRUFEICsKICAgICAgICBgCltXXTo6U2V0Q3Vy
::B64:agent.js:c29yUG9zKFtpbnRdJGVudjpYLCBbaW50XSRlbnY6WSkgfCBPdXQtTnVsbApTdGFydC1TbGVlcCAtTWlsbGlzZWNvbmRzIDE1MAokZG93biA9IDI7ICR1cCA9IDQKaWYgKCRlbnY6QlROIC1lcSAicmlnaHQiKSB7ICRkb3duID0gODsgJHVwID0gMTYgfQpmb3IgKCRp
::B64:agent.js:ID0gMDsgJGkgLWx0IFtpbnRdJGVudjpDT1VOVDsgJGkrKykgewogIFtXXTo6bW91c2VfZXZlbnQoJGRvd24sIDAsIDAsIDAsIFtVSW50UHRyXTo6WmVybykKICBbV106Om1vdXNlX2V2ZW50KCR1cCwgMCwgMCwgMCwgW1VJbnRQdHJdOjpaZXJvKQogIFN0YXJ0LVNs
::B64:agent.js:ZWVwIC1NaWxsaXNlY29uZHMgODAKfQpgLAogICAgICB7IFg6IFN0cmluZyhyeCksIFk6IFN0cmluZyhyeSksIEJUTjogU3RyaW5nKGJ1dHRvbiksIENPVU5UOiBkYmwgPyAiMiIgOiAiMSIgfQogICAgKTsKICAgIGF3YWl0IHNsZWVwKDgwMCk7CiAgICByZXR1cm4g
::B64:agent.js:Im9rLCBkaWtsaWsiOwogIH0sCgogIHNjcm9sbF9zY3JlZW46IGFzeW5jICh7IGFtb3VudCB9KSA9PiB7CiAgICBjb25zdCBkZWx0YSA9IC0xMjAgKiBNYXRoLnJvdW5kKE51bWJlcihhbW91bnQpKTsgLy8gcG9zaXRpZiA9IHR1cnVuCiAgICBpZiAoIShhd2FpdCBh
::B64:agent.js:c2soYFNjcm9sbCAke2Ftb3VudCA+IDAgPyAidHVydW4iIDogIm5haWsifSAke01hdGguYWJzKGFtb3VudCl9eGApKSkgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgYXdhaXQgcHMoUFNfSEVBRCArIGBbV106Om1vdXNlX2V2ZW50KDB4MDgwMCwgMCwgMCwg
::B64:agent.js:W2ludF0kZW52OkQsIFtVSW50UHRyXTo6WmVybylgLCB7IEQ6IFN0cmluZyhkZWx0YSkgfSk7CiAgICBhd2FpdCBzbGVlcCg1MDApOwogICAgcmV0dXJuICJvayI7CiAgfSwKCiAgdHlwZV9kZXNrdG9wOiBhc3luYyAoeyB0ZXh0IH0pID0+IHsKICAgIGlmICghKGF3
::B64:agent.js:YWl0IGFzayhgS2V0aWs6ICIke1N0cmluZyh0ZXh0KS5zbGljZSgwLCA2MCl9ImApKSkgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgYXdhaXQgcHMoCiAgICAgIFBTX0hFQUQgKwogICAgICAgIGAKU2V0LUNsaXBib2FyZCAtVmFsdWUgJGVudjpUWFQKU3Rh
::B64:agent.js:cnQtU2xlZXAgLU1pbGxpc2Vjb25kcyAxNTAKW1N5c3RlbS5XaW5kb3dzLkZvcm1zLlNlbmRLZXlzXTo6U2VuZFdhaXQoIl52IikKYCwKICAgICAgeyBUWFQ6IFN0cmluZyh0ZXh0KSB9CiAgICApOwogICAgYXdhaXQgc2xlZXAoNTAwKTsKICAgIHJldHVybiAib2ss
::B64:agent.js:IGRpa2V0aWsiOwogIH0sCgogIHByZXNzX2tleXM6IGFzeW5jICh7IGtleXMgfSkgPT4gewogICAgaWYgKCEoYXdhaXQgYXNrKGBUZWthbiB0b21ib2w6ICR7a2V5c31gKSkpIHJldHVybiAiRGliYXRhbGthbiB1c2VyIjsKICAgIGF3YWl0IHBzKFBTX0hFQUQgKyBg
::B64:agent.js:W1N5c3RlbS5XaW5kb3dzLkZvcm1zLlNlbmRLZXlzXTo6U2VuZFdhaXQoJGVudjpLRVlTKWAsIHsgS0VZUzogU3RyaW5nKGtleXMpIH0pOwogICAgYXdhaXQgc2xlZXAoNTAwKTsKICAgIHJldHVybiAib2siOwogIH0sCgogIHdhaXQ6IGFzeW5jICh7IHNlY29uZHMg
::B64:agent.js:fSkgPT4gewogICAgYXdhaXQgc2xlZXAoTWF0aC5taW4oTnVtYmVyKHNlY29uZHMpIHx8IDEsIDE1KSAqIDEwMDApOwogICAgcmV0dXJuICJvayI7CiAgfSwKCiAgLy8gLS0tIEJyb3dzZXIgKFBsYXl3cmlnaHQpIC0tLQogIGxpc3RfZmlsZXM6IGFzeW5jICgpID0+
::B64:agent.js:IGZzLnJlYWRkaXJTeW5jKFNBRkVfRElSKS5qb2luKCJcbiIpIHx8ICIoZm9sZGVyIHVwbG9hZCBrb3NvbmcpIiwKCiAgb3Blbl91cmw6IGFzeW5jICh7IHVybCB9KSA9PiB7CiAgICBhd2FpdCBwYWdlLmdvdG8odXJsLCB7IHdhaXRVbnRpbDogImRvbWNvbnRlbnRs
::B64:agent.js:b2FkZWQiIH0pOwogICAgcmV0dXJuICJUZXJidWthOiAiICsgKGF3YWl0IHBhZ2UudGl0bGUoKSk7CiAgfSwKCiAgaW5zcGVjdF9wYWdlOiBhc3luYyAoKSA9PiB7CiAgICBjb25zdCBpdGVtcyA9IGF3YWl0IHBhZ2UuZXZhbHVhdGUoKCkgPT4KICAgICAgWy4uLmRv
::B64:agent.js:Y3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoImlucHV0LCBidXR0b24sIGEsIHRleHRhcmVhLCBzZWxlY3QiKV0KICAgICAgICAuc2xpY2UoMCwgNjApCiAgICAgICAgLm1hcCgoZSkgPT4gKHsKICAgICAgICAgIHRhZzogZS50YWdOYW1lLnRvTG93ZXJDYXNlKCksCiAg
::B64:agent.js:ICAgICAgICBpZDogZS5pZCB8fCB1bmRlZmluZWQsCiAgICAgICAgICBuYW1lOiBlLmdldEF0dHJpYnV0ZSgibmFtZSIpIHx8IHVuZGVmaW5lZCwKICAgICAgICAgIHR5cGU6IGUuZ2V0QXR0cmlidXRlKCJ0eXBlIikgfHwgdW5kZWZpbmVkLAogICAgICAgICAgdGV4
::B64:agent.js:dDogKGUuaW5uZXJUZXh0IHx8IGUudmFsdWUgfHwgZS5wbGFjZWhvbGRlciB8fCAiIikudHJpbSgpLnNsaWNlKDAsIDQwKSB8fCB1bmRlZmluZWQsCiAgICAgICAgfSkpCiAgICApOwogICAgcmV0dXJuIEpTT04uc3RyaW5naWZ5KGl0ZW1zKTsKICB9LAoKICB5b3V0
::B64:agent.js:dWJlX3BsYXk6IGFzeW5jICh7IHF1ZXJ5LCBwaWNrID0gMSB9KSA9PiB7CiAgICBhd2FpdCBwYWdlLmJyaW5nVG9Gcm9udCgpOwogICAgYXdhaXQgcGFnZS5nb3RvKCJodHRwczovL3d3dy55b3V0dWJlLmNvbS9yZXN1bHRzP3NlYXJjaF9xdWVyeT0iICsgZW5jb2Rl
::B64:agent.js:VVJJQ29tcG9uZW50KFN0cmluZyhxdWVyeSkpLCB7CiAgICAgIHdhaXRVbnRpbDogImRvbWNvbnRlbnRsb2FkZWQiLAogICAgfSk7CiAgICBhd2FpdCBwYWdlLndhaXRGb3JTZWxlY3RvcigieXRkLXZpZGVvLXJlbmRlcmVyIGEjdmlkZW8tdGl0bGUiLCB7IHRpbWVv
::B64:agent.js:dXQ6IDIwMDAwIH0pOwogICAgY29uc3QgbGlzdCA9IGF3YWl0IHBhZ2UuJCRldmFsKCJ5dGQtdmlkZW8tcmVuZGVyZXIgYSN2aWRlby10aXRsZSIsIChlbHMpID0+CiAgICAgIGVscy5zbGljZSgwLCA1KS5tYXAoKGUpID0+ICh7IHRpdGxlOiBlLnRleHRDb250ZW50
::B64:agent.js:LnRyaW0oKSwgaHJlZjogZS5ocmVmIH0pKQogICAgKTsKICAgIGlmICghbGlzdC5sZW5ndGgpIHJldHVybiAiVGlkYWsgYWRhIGhhc2lsIjsKICAgIGNvbnN0IGlkeCA9IE1hdGgubWluKE1hdGgubWF4KE51bWJlcihwaWNrKSB8fCAxLCAxKSwgbGlzdC5sZW5ndGgp
::B64:agent.js:IC0gMTsKICAgIGF3YWl0IHBhZ2UuZ290byhsaXN0W2lkeF0uaHJlZiwgeyB3YWl0VW50aWw6ICJkb21jb250ZW50bG9hZGVkIiB9KTsKICAgIGF3YWl0IHNsZWVwKDI1MDApOwogICAgYXdhaXQgcGFnZS5ldmFsdWF0ZSgoKSA9PiB7CiAgICAgIGNvbnN0IHYgPSBk
::B64:agent.js:b2N1bWVudC5xdWVyeVNlbGVjdG9yKCJ2aWRlbyIpOwogICAgICBpZiAodiAmJiB2LnBhdXNlZCkgdi5wbGF5KCkuY2F0Y2goKCkgPT4ge30pOwogICAgfSk7CiAgICBjb25zdCBvdGhlcnMgPSBsaXN0Lm1hcCgodiwgaSkgPT4gYCR7aSArIDF9LiAke3YudGl0bGV9
::B64:agent.js:YCkuam9pbigiXG4iKTsKICAgIHJldHVybiBgTWVtdXRhciAjJHtpZHggKyAxfTogJHtsaXN0W2lkeF0udGl0bGV9XG5IYXNpbCBwZW5jYXJpYW46XG4ke290aGVyc31gOwogIH0sCgogIGdldF9wYWdlX3RleHQ6IGFzeW5jICgpID0+IChhd2FpdCBwYWdlLmlubmVy
::B64:agent.js:VGV4dCgiYm9keSIpKS5zbGljZSgwLCA0MDAwKSwKCiAgdHlwZV90ZXh0OiBhc3luYyAoeyBzZWxlY3RvciwgdGV4dCB9KSA9PiB7CiAgICBhd2FpdCBwYWdlLmZpbGwoc2VsZWN0b3IsIHRleHQpOwogICAgcmV0dXJuICJvayI7CiAgfSwKCiAgY2xpY2s6IGFzeW5j
::B64:agent.js:ICh7IHNlbGVjdG9yIH0pID0+IHsKICAgIGlmICghKGF3YWl0IGFzayhgS2xpayBlbGVtZW4gYnJvd3NlcjogJHtzZWxlY3Rvcn1gKSkpIHJldHVybiAiRGliYXRhbGthbiB1c2VyIjsKICAgIGF3YWl0IHBhZ2UuY2xpY2soc2VsZWN0b3IsIHsgdGltZW91dDogMTAw
::B64:agent.js:MDAgfSk7CiAgICByZXR1cm4gIm9rIjsKICB9LAoKICB1cGxvYWRfZmlsZTogYXN5bmMgKHsgc2VsZWN0b3IsIGZpbGVuYW1lIH0pID0+IHsKICAgIGNvbnN0IGZ1bGwgPSBzYWZlUGF0aChmaWxlbmFtZSk7CiAgICBpZiAoIShhd2FpdCBhc2soYFVwbG9hZCBmaWxl
::B64:agent.js:OiAke2ZpbGVuYW1lfWApKSkgcmV0dXJuICJEaWJhdGFsa2FuIHVzZXIiOwogICAgYXdhaXQgcGFnZS5zZXRJbnB1dEZpbGVzKHNlbGVjdG9yLCBmdWxsKTsKICAgIHJldHVybiAib2ssIGZpbGUgZGlwaWxpaCI7CiAgfSwKfTsKCmNvbnN0IGZuID0gKG5hbWUsIGRl
::B64:agent.js:c2NyaXB0aW9uLCBwcm9wZXJ0aWVzID0ge30sIG9wdGlvbmFsID0gW10pID0+ICh7CiAgdHlwZTogImZ1bmN0aW9uIiwKICBmdW5jdGlvbjogewogICAgbmFtZSwKICAgIGRlc2NyaXB0aW9uLAogICAgcGFyYW1ldGVyczogewogICAgICB0eXBlOiAib2JqZWN0IiwK
::B64:agent.js:ICAgICAgcHJvcGVydGllcywKICAgICAgcmVxdWlyZWQ6IE9iamVjdC5rZXlzKHByb3BlcnRpZXMpLmZpbHRlcigoaykgPT4gIW9wdGlvbmFsLmluY2x1ZGVzKGspKSwKICAgIH0sCiAgfSwKfSk7CmNvbnN0IHN0ciA9IChkKSA9PiAoeyB0eXBlOiAic3RyaW5nIiwg
::B64:agent.js:ZGVzY3JpcHRpb246IGQgfSk7CmNvbnN0IG51bSA9IChkKSA9PiAoeyB0eXBlOiAibnVtYmVyIiwgZGVzY3JpcHRpb246IGQgfSk7Cgpjb25zdCB0b29scyA9IFsKICBmbigiZmluZF9mb2xkZXIiLCAiQ2FyaSBmb2xkZXIgZGkgUEMgYmVyZGFzYXJrYW4gbmFtYSAo
::B64:agent.js:c2ViYWdpYW4gbmFtYSBjdWt1cCkiLCB7IG5hbWU6IHN0cigiTmFtYSBmb2xkZXIiKSB9KSwKICBmbigibGlzdF9kaXIiLCAiTGloYXQgaXNpIHNlYnVhaCBmb2xkZXIgZGkgUEMiLCB7IHBhdGg6IHN0cigiUGF0aCBsZW5na2FwIGZvbGRlciIpIH0pLAogIGZuKCJv
::B64:agent.js:cGVuX3BhdGgiLCAiQnVrYSBmb2xkZXIsIGZpbGUsIGFwbGlrYXNpIChtaXMuIG5vdGVwYWQpLCBhdGF1IFVSTCBkaSBQQyIsIHsgdGFyZ2V0OiBzdHIoIlBhdGgvbmFtYSBhcGxpa2FzaS9VUkwiKSB9KSwKICBmbigic2NyZWVuc2hvdCIsICJBbWJpbCBzY3JlZW5z
::B64:agent.js:aG90IGxheWFyIFBDIHVudHVrIG1lbGloYXQga29uZGlzaSBzZWthcmFuZyIpLAogIGZuKAogICAgImNsaWNrX3NjcmVlbiIsCiAgICAiS2xpayBkaSBsYXlhciBQQyBwYWRhIGtvb3JkaW5hdCBkYXJpIHNjcmVlbnNob3QgdGVyYWtoaXIiLAogICAgeyB4OiBudW0o
::B64:agent.js:Iktvb3JkaW5hdCBYIGRpIHNjcmVlbnNob3QiKSwgeTogbnVtKCJLb29yZGluYXQgWSBkaSBzY3JlZW5zaG90IiksIGJ1dHRvbjogc3RyKCJsZWZ0IGF0YXUgcmlnaHQiKSwgZG91YmxlOiB7IHR5cGU6ICJib29sZWFuIiwgZGVzY3JpcHRpb246ICJkb3VibGUta2xp
::B64:agent.js:ayIgfSB9LAogICAgWyJidXR0b24iLCAiZG91YmxlIl0KICApLAogIGZuKCJzY3JvbGxfc2NyZWVuIiwgIlNjcm9sbCBsYXlhci4gUG9zaXRpZiA9IHR1cnVuLCBuZWdhdGlmID0gbmFpayIsIHsgYW1vdW50OiBudW0oIkp1bWxhaCBzY3JvbGwiKSB9KSwKICBmbigi
::B64:agent.js:dHlwZV9kZXNrdG9wIiwgIktldGlrIHRla3MgZGkgYXBsaWthc2kgeWFuZyBzZWRhbmcgZm9rdXMgZGkgUEMiLCB7IHRleHQ6IHN0cigiVGVrcyIpIH0pLAogIGZuKCJwcmVzc19rZXlzIiwgIlRla2FuIHRvbWJvbCBmb3JtYXQgU2VuZEtleXM6IHtFTlRFUn0sIHtU
::B64:agent.js:QUJ9LCB7RVNDfSwgXmMgKEN0cmwrQyksIF52LCBebCwgJXtGNH0iLCB7IGtleXM6IHN0cigiS29tYmluYXNpIHRvbWJvbCIpIH0pLAogIGZuKCJ3YWl0IiwgIlR1bmdndSBiZWJlcmFwYSBkZXRpayAobWFrcyAxNSkgc3VwYXlhIGhhbGFtYW4vYXBsaWthc2kgc2Vs
::B64:agent.js:ZXNhaSBkaW11YXQiLCB7IHNlY29uZHM6IG51bSgiRGV0aWsiKSB9KSwKICBmbigibGlzdF9maWxlcyIsICJMaWhhdCBkYWZ0YXIgZmlsZSBkaSBmb2xkZXIgdXBsb2FkIGtodXN1cyIpLAogIGZuKCJvcGVuX3VybCIsICJCdWthIHdlYnNpdGUgZGkgYnJvd3NlciBQ
::B64:agent.js:bGF5d3JpZ2h0ICh1bnR1ayBvdG9tYXNpIHdlYikiLCB7IHVybDogc3RyKCJVUkwgbGVuZ2thcCIpIH0pLAogIGZuKCJpbnNwZWN0X3BhZ2UiLCAiRGFmdGFyIHRvbWJvbC9pbnB1dCBkaSBoYWxhbWFuIGJyb3dzZXIgdW50dWsgbWVuY2FyaSBDU1Mgc2VsZWN0b3Ii
::B64:agent.js:KSwKICBmbigKICAgICJ5b3V0dWJlX3BsYXkiLAogICAgIkNhcmkgdmlkZW8gZGkgWW91VHViZSBsYWx1IE9UT01BVElTIG1lbXV0YXIgaGFzaWwgcGlsaWhhbiBkaSBicm93c2VyIGFnZW50LiBQYWthaSBpbmkgdW50dWsgc2VtdWEgcGVybWludGFhbiBub250b24v
::B64:agent.js:Y2FyaSB2aWRlby9sYWd1IGRpIFlvdVR1YmUuIiwKICAgIHsgcXVlcnk6IHN0cigiS2F0YSBrdW5jaSBwZW5jYXJpYW4iKSwgcGljazogbnVtKCJVcnV0YW4gaGFzaWwgeWFuZyBkaXB1dGFyLCAxLTUgKGRlZmF1bHQgMSkiKSB9LAogICAgWyJwaWNrIl0KICApLAog
::B64:agent.js:IGZuKCJkb25lIiwgIlBhbmdnaWwgaW5pIGppa2EgdHVnYXMgU0VMRVNBSSwgYXRhdSBqaWthIHBlcmx1IGJlcnRhbnlhL21lbGFwb3Iga2UgdXNlciIsIHsgbWVzc2FnZTogc3RyKCJQZXNhbiBzaW5na2F0IHVudHVrIHVzZXIiKSB9KSwKICBmbigiZ2V0X3BhZ2Vf
::B64:agent.js:dGV4dCIsICJCYWNhIHRla3MgaGFsYW1hbiBicm93c2VyIHNhYXQgaW5pIiksCiAgZm4oInR5cGVfdGV4dCIsICJJc2kga29sb20gdGVrcyBkaSBicm93c2VyIiwgeyBzZWxlY3Rvcjogc3RyKCJDU1Mgc2VsZWN0b3IiKSwgdGV4dDogc3RyKCJUZWtzIikgfSksCiAg
::B64:agent.js:Zm4oImNsaWNrIiwgIktsaWsgZWxlbWVuIGRpIGJyb3dzZXIiLCB7IHNlbGVjdG9yOiBzdHIoIkNTUyBzZWxlY3RvciIpIH0pLAogIGZuKCJ1cGxvYWRfZmlsZSIsICJVcGxvYWQgZmlsZSBkYXJpIGZvbGRlciB1cGxvYWQga2UgaW5wdXQgZmlsZSBkaSBicm93c2Vy
::B64:agent.js:IiwgewogICAgc2VsZWN0b3I6IHN0cigiQ1NTIHNlbGVjdG9yIGlucHV0W3R5cGU9ZmlsZV0iKSwKICAgIGZpbGVuYW1lOiBzdHIoIk5hbWEgZmlsZSBkaSBmb2xkZXIgdXBsb2FkIiksCiAgfSksCl07Cgpjb25zdCBTWVNURU0gPSBgS2FtdSBhZ2VudCB5YW5nIG1l
::B64:agent.js:bmdvbnRyb2wgUEMgV2luZG93cyBtaWxpayB1c2VyIGRhbiBicm93c2VyLiBLZXJqYWthbiBwZXJpbnRhaCB1c2VyIGRlbmdhbiBtZW1hbmdnaWwgdG9vbC4KQVRVUkFOIFBFTlRJTkc6Ci0gS2FtdSBIQVJVUyBzZWxhbHUgbWVtYW5nZ2lsIHRvb2wgZGkgc2V0aWFw
::B64:agent.js:IGxhbmdrYWguIEpBTkdBTiBwZXJuYWggbWVudWxpcyByZW5jYW5hLCBuYXJhc2ksIGF0YXUgInNheWEgYWthbiAuLi4iLiBMYW5nc3VuZyBwYW5nZ2lsIHRvb2wtbnlhLgotIFNldGVsYWggdHVnYXMgc2VsZXNhaSAoYXRhdSBwZXJsdSBiZXJ0YW55YSBrZSB1c2Vy
::B64:agent.js:KSwgcGFuZ2dpbCB0b29sIGRvbmUgZGVuZ2FuIHBlc2FuIHNpbmdrYXQuCi0gTm9udG9uL2NhcmkgdmlkZW8vbGFndSBkaSBZb3VUdWJlOiBsYW5nc3VuZyBwYW5nZ2lsIHlvdXR1YmVfcGxheSBkZW5nYW4ga2F0YSBrdW5jaSBkYXJpIHVzZXIuIEppa2EganVkdWwg
::B64:agent.js:eWFuZyBkaXB1dGFyIGt1cmFuZyBjb2NvaywgcGFuZ2dpbCBsYWdpIGRlbmdhbiBwaWNrIGxhaW4uCi0gVGFmc2lya2FuIHBlcmludGFoIHNpbmdrYXQvdHlwbyB1c2VyIGRlbmdhbiB3YWphciwgamFuZ2FuIGJlcnRhbnlhIGhhbCB5YW5nIGJpc2EgZGl0ZWJhay4K
::B64:agent.js:LSBGb2xkZXIvZmlsZSBkaSBQQzogcGFrYWkgZmluZF9mb2xkZXIgdW50dWsgbWVuY2FyaSwgbGFsdSBvcGVuX3BhdGggdW50dWsgbWVtYnVrYS4KLSBBcGxpa2FzaS9qZW5kZWxhIGRpIFBDOiBzY3JlZW5zaG90IGR1bHUgdW50dWsgbWVsaWhhdCBsYXlhciwgbGFs
::B64:agent.js:dSBjbGlja19zY3JlZW4vdHlwZV9kZXNrdG9wL3ByZXNzX2tleXMsIGxhbHUgc2NyZWVuc2hvdCBsYWdpIHVudHVrIG1lbWVyaWtzYSBoYXNpbC4KLSBLb29yZGluYXQga2xpayBoYXJ1cyBkYXJpIHNjcmVlbnNob3QgdGVyYWtoaXIuCi0gVW50dWsgb3RvbWFzaSB3
::B64:agent.js:ZWJzaXRlIHBha2FpIHRvb2wgYnJvd3NlciAob3Blbl91cmwsIGluc3BlY3RfcGFnZSwgdHlwZV90ZXh0LCBjbGljaywgdXBsb2FkX2ZpbGUpLiBTZWxhbHUgaW5zcGVjdF9wYWdlIHNlYmVsdW0ga2xpay4KLSBKaWthIGJ1bnR1LCBidXR1aCBsb2dpbiwgYXRhdSBy
::B64:agent.js:YWd1LCBiZXJoZW50aSBkYW4gdGFueWEgdXNlci4KLSBKYXdhYiBkYWxhbSBCYWhhc2EgSW5kb25lc2lhLCBzaW5na2F0LiBKYW5nYW4gbWVuZ2FyYW5nIGhhc2lsOyBsYXBvcmthbiBhcGEgYWRhbnlhLmA7CgpsZXQgdXNlVG9vbENob2ljZSA9IHRydWU7IC8vIHBh
::B64:agent.js:a3NhIG1vZGVsIHNlbGFsdSBtZW1hbmdnaWwgdG9vbDsgZGltYXRpa2FuIG90b21hdGlzIGppa2EgcHJvdmlkZXIgbWVub2xhawphc3luYyBmdW5jdGlvbiBjYWxsTExNKG1lc3NhZ2VzKSB7CiAgY29uc3QgYm9keSA9IHsgbW9kZWw6IE1PREVMLCBtZXNzYWdlcywg
::B64:agent.js:dG9vbHMsIHN0cmVhbTogdHJ1ZSB9OwogIGlmICh1c2VUb29sQ2hvaWNlKSBib2R5LnRvb2xfY2hvaWNlID0gInJlcXVpcmVkIjsKICBjb25zdCByZXMgPSBhd2FpdCBmZXRjaChgJHtCQVNFX1VSTH0vY2hhdC9jb21wbGV0aW9uc2AsIHsKICAgIG1ldGhvZDogIlBP
::B64:agent.js:U1QiLAogICAgaGVhZGVyczogeyAiQ29udGVudC1UeXBlIjogImFwcGxpY2F0aW9uL2pzb24iLCBBdXRob3JpemF0aW9uOiBgQmVhcmVyICR7QVBJX0tFWX1gIH0sCiAgICBib2R5OiBKU09OLnN0cmluZ2lmeShib2R5KSwKICB9KTsKICBpZiAoIXJlcy5vaykgewog
::B64:agent.js:ICAgY29uc3QgZXJyVGV4dCA9IGF3YWl0IHJlcy50ZXh0KCk7CiAgICBpZiAodXNlVG9vbENob2ljZSAmJiByZXMuc3RhdHVzID09PSA0MDApIHsKICAgICAgdXNlVG9vbENob2ljZSA9IGZhbHNlOwogICAgICByZXR1cm4gY2FsbExMTShtZXNzYWdlcyk7CiAgICB9
::B64:agent.js:CiAgICB0aHJvdyBuZXcgRXJyb3IoYDlSb3V0ZXIgZXJyb3IgJHtyZXMuc3RhdHVzfTogJHtlcnJUZXh0fWApOwogIH0KCiAgY29uc3QgcmF3ID0gYXdhaXQgcmVzLnRleHQoKTsKICBpZiAoIXJhdy50cmltU3RhcnQoKS5zdGFydHNXaXRoKCJkYXRhOiIpKSB7CiAg
::B64:agent.js:ICByZXR1cm4gSlNPTi5wYXJzZShyYXcpLmNob2ljZXNbMF0ubWVzc2FnZTsKICB9CgogIGxldCBjb250ZW50ID0gIiI7CiAgY29uc3QgY2FsbHMgPSBbXTsKICBmb3IgKGNvbnN0IGxpbmUgb2YgcmF3LnNwbGl0KCJcbiIpKSB7CiAgICBpZiAoIWxpbmUuc3RhcnRz
::B64:agent.js:V2l0aCgiZGF0YToiKSkgY29udGludWU7CiAgICBjb25zdCBkYXRhID0gbGluZS5zbGljZSg1KS50cmltKCk7CiAgICBpZiAoIWRhdGEgfHwgZGF0YSA9PT0gIltET05FXSIpIGNvbnRpbnVlOwogICAgbGV0IGNodW5rOwogICAgdHJ5IHsKICAgICAgY2h1bmsgPSBK
::B64:agent.js:U09OLnBhcnNlKGRhdGEpOwogICAgfSBjYXRjaCB7CiAgICAgIGNvbnRpbnVlOwogICAgfQogICAgY29uc3QgY2hvaWNlID0gY2h1bmsuY2hvaWNlcz8uWzBdOwogICAgY29uc3QgZGVsdGEgPSBjaG9pY2U/LmRlbHRhIHx8IGNob2ljZT8ubWVzc2FnZSB8fCB7fTsK
::B64:agent.js:ICAgIGlmIChkZWx0YS5jb250ZW50KSBjb250ZW50ICs9IGRlbHRhLmNvbnRlbnQ7CiAgICBmb3IgKGNvbnN0IHRjIG9mIGRlbHRhLnRvb2xfY2FsbHMgfHwgW10pIHsKICAgICAgY29uc3QgaSA9IHRjLmluZGV4ID8/IDA7CiAgICAgIGNhbGxzW2ldID8/PSB7IGlk
::B64:agent.js:OiAiIiwgdHlwZTogImZ1bmN0aW9uIiwgZnVuY3Rpb246IHsgbmFtZTogIiIsIGFyZ3VtZW50czogIiIgfSB9OwogICAgICBpZiAodGMuaWQpIGNhbGxzW2ldLmlkID0gdGMuaWQ7CiAgICAgIGlmICh0Yy5mdW5jdGlvbj8ubmFtZSkgY2FsbHNbaV0uZnVuY3Rpb24u
::B64:agent.js:bmFtZSArPSB0Yy5mdW5jdGlvbi5uYW1lOwogICAgICBpZiAodGMuZnVuY3Rpb24/LmFyZ3VtZW50cykgY2FsbHNbaV0uZnVuY3Rpb24uYXJndW1lbnRzICs9IHRjLmZ1bmN0aW9uLmFyZ3VtZW50czsKICAgIH0KICB9CgogIGNvbnN0IG1zZyA9IHsgcm9sZTogImFz
::B64:agent.js:c2lzdGFudCIsIGNvbnRlbnQ6IGNvbnRlbnQgfHwgbnVsbCB9OwogIGNvbnN0IHZhbGlkID0gY2FsbHMuZmlsdGVyKEJvb2xlYW4pLm1hcCgoYywgaSkgPT4gKHsgLi4uYywgaWQ6IGMuaWQgfHwgYGNhbGxfJHtpfWAgfSkpOwogIGlmICh2YWxpZC5sZW5ndGgpIG1z
::B64:agent.js:Zy50b29sX2NhbGxzID0gdmFsaWQ7CiAgcmV0dXJuIG1zZzsKfQoKYXN5bmMgZnVuY3Rpb24gcnVuVGFzayhjb21tYW5kKSB7CiAgY29uc3QgbWVzc2FnZXMgPSBbCiAgICB7IHJvbGU6ICJzeXN0ZW0iLCBjb250ZW50OiBTWVNURU0gfSwKICAgIHsgcm9sZTogInVz
::B64:agent.js:ZXIiLCBjb250ZW50OiBjb21tYW5kIH0sCiAgXTsKICBsZXQgbnVkZ2VzID0gMDsKCiAgZm9yIChsZXQgc3RlcCA9IDE7IHN0ZXAgPD0gTUFYX1NURVBTOyBzdGVwKyspIHsKICAgIGNvbnN0IG1zZyA9IGF3YWl0IGNhbGxMTE0obWVzc2FnZXMpOwogICAgbWVzc2Fn
::B64:agent.js:ZXMucHVzaChtc2cpOwoKICAgIGlmICghbXNnLnRvb2xfY2FsbHM/Lmxlbmd0aCkgewogICAgICAvLyBNb2RlbCBjdW1hIG1lbnVsaXMgdGVrcy9yZW5jYW5hIHRhbnBhIG1lbWFuZ2dpbCB0b29sIC0+IHBha3NhIHBhbmdnaWwgdG9vbAogICAgICBpZiAobnVkZ2Vz
::B64:agent.js:IDwgMykgewogICAgICAgIG51ZGdlcysrOwogICAgICAgIG1lc3NhZ2VzLnB1c2goewogICAgICAgICAgcm9sZTogInVzZXIiLAogICAgICAgICAgY29udGVudDogIkthbXUgaGFydXMgbWVtYW5nZ2lsIHRvb2wuIEphbmdhbiBtZW51bGlzIHRla3MgYmlhc2EuIExh
::B64:agent.js:bmdzdW5nIHBhbmdnaWwgdG9vbCB5YW5nIHNlc3VhaSwgYXRhdSBwYW5nZ2lsIGRvbmUgamlrYSB0dWdhcyBzdWRhaCBzZWxlc2FpLiIsCiAgICAgICAgfSk7CiAgICAgICAgY29udGludWU7CiAgICAgIH0KICAgICAgY29uc29sZS5sb2coIlxuQWdlbnQ6IiwgbXNn
::B64:agent.js:LmNvbnRlbnQpOwogICAgICByZXR1cm47CiAgICB9CgogICAgZm9yIChjb25zdCBjYWxsIG9mIG1zZy50b29sX2NhbGxzKSB7CiAgICAgIGNvbnN0IG5hbWUgPSBjYWxsLmZ1bmN0aW9uLm5hbWU7CiAgICAgIGlmIChuYW1lID09PSAiZG9uZSIpIHsKICAgICAgICBs
::B64:agent.js:ZXQgbSA9ICIiOwogICAgICAgIHRyeSB7CiAgICAgICAgICBtID0gSlNPTi5wYXJzZShjYWxsLmZ1bmN0aW9uLmFyZ3VtZW50cyB8fCAie30iKS5tZXNzYWdlIHx8ICIiOwogICAgICAgIH0gY2F0Y2gge30KICAgICAgICBjb25zb2xlLmxvZygiXG5BZ2VudDoiLCBt
::B64:agent.js:IHx8ICJTZWxlc2FpLiIpOwogICAgICAgIHJldHVybjsKICAgICAgfQogICAgICBsZXQgcmVzdWx0OwogICAgICB0cnkgewogICAgICAgIGNvbnN0IGFyZ3MgPSBKU09OLnBhcnNlKGNhbGwuZnVuY3Rpb24uYXJndW1lbnRzIHx8ICJ7fSIpOwogICAgICAgIGNvbnNv
::B64:agent.js:bGUubG9nKGBbJHtzdGVwfV0gJHtuYW1lfWAsIGFyZ3MpOwogICAgICAgIGlmICghaW1wbFtuYW1lXSkgdGhyb3cgbmV3IEVycm9yKCJUb29sIHRpZGFrIGRpa2VuYWw6ICIgKyBuYW1lKTsKICAgICAgICByZXN1bHQgPSBhd2FpdCBpbXBsW25hbWVdKGFyZ3MpOwog
::B64:agent.js:ICAgICB9IGNhdGNoIChlKSB7CiAgICAgICAgcmVzdWx0ID0gIkVSUk9SOiAiICsgZS5tZXNzYWdlOwogICAgICB9CiAgICAgIG1lc3NhZ2VzLnB1c2goeyByb2xlOiAidG9vbCIsIHRvb2xfY2FsbF9pZDogY2FsbC5pZCwgY29udGVudDogU3RyaW5nKHJlc3VsdCkg
::B64:agent.js:fSk7CiAgICB9CgogICAgLy8gS2lyaW0gc2NyZWVuc2hvdCAoamlrYSBhZGEpIHNlYmFnYWkgZ2FtYmFyIGFnYXIgbW9kZWwgYmlzYSAibWVsaWhhdCIKICAgIGlmIChwZW5kaW5nSW1hZ2VzLmxlbmd0aCkgewogICAgICBtZXNzYWdlcy5wdXNoKHsKICAgICAgICBy
::B64:agent.js:b2xlOiAidXNlciIsCiAgICAgICAgY29udGVudDogWwogICAgICAgICAgeyB0eXBlOiAidGV4dCIsIHRleHQ6ICJJbmkgc2NyZWVuc2hvdCBsYXlhciB0ZXJiYXJ1OiIgfSwKICAgICAgICAgIC4uLnBlbmRpbmdJbWFnZXMuc3BsaWNlKDApLm1hcCgoYjY0KSA9PiAo
::B64:agent.js:ewogICAgICAgICAgICB0eXBlOiAiaW1hZ2VfdXJsIiwKICAgICAgICAgICAgaW1hZ2VfdXJsOiB7IHVybDogYGRhdGE6aW1hZ2UvcG5nO2Jhc2U2NCwke2I2NH1gIH0sCiAgICAgICAgICB9KSksCiAgICAgICAgXSwKICAgICAgfSk7CiAgICB9CiAgICBhd2FpdCBz
::B64:agent.js:bGVlcCgzMDApOwogIH0KICBjb25zb2xlLmxvZygiQmVyaGVudGk6IG1lbGV3YXRpIGJhdGFzIGxhbmdrYWguIik7Cn0KCmNvbnNvbGUubG9nKGBBZ2VudCBzaWFwLiBGb2xkZXIgdXBsb2FkOiAke1NBRkVfRElSfWApOwpjb25zb2xlLmxvZyhgSXppbiBzZWJlbHVt
::B64:agent.js:IGFrc2k6ICR7Q09ORklSTSA/ICJBS1RJRiIgOiAiTUFUSSJ9LiBUZWthbiBDdHJsK0Mga2FwYW4gc2FqYSB1bnR1ayBtZW5naGVudGlrYW4uYCk7CmNvbnNvbGUubG9nKCdLZXRpayBwZXJpbnRhaCBkYWxhbSBiYWhhc2EgYmlhc2EgKGF0YXUgImV4aXQiKS4nKTsK
::B64:agent.js:d2hpbGUgKHRydWUpIHsKICBjb25zdCBjbWQgPSBhd2FpdCBybC5xdWVzdGlvbigiXG5QZXJpbnRhaD4gIik7CiAgaWYgKGNtZC50cmltKCkgPT09ICJleGl0IikgYnJlYWs7CiAgaWYgKCFjbWQudHJpbSgpKSBjb250aW51ZTsKICB0cnkgewogICAgYXdhaXQgcnVu
::B64:agent.js:VGFzayhjbWQpOwogIH0gY2F0Y2ggKGUpIHsKICAgIGNvbnNvbGUuZXJyb3IoIkdhZ2FsOiIsIGUubWVzc2FnZSk7CiAgfQp9CmF3YWl0IGNvbnRleHQuY2xvc2UoKTsKcmwuY2xvc2UoKTsK
::B64:package.json:ewogICJuYW1lIjogImJvdC1hZ2VudCIsCiAgInZlcnNpb24iOiAiMS4wLjAiLAogICJ0eXBlIjogIm1vZHVsZSIsCiAgInNjcmlwdHMiOiB7CiAgICAic3RhcnQiOiAibm9kZSBhZ2VudC5qcyIKICB9LAogICJkZXBlbmRlbmNpZXMiOiB7CiAgICAicGxheXdyaWdo
::B64:package.json:dCI6ICJeMS40OC4wIgogIH0KfQo=
