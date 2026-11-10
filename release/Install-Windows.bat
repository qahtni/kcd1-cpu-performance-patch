@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem CPU Performance Patch 1.0.0 - installer for Windows.
rem Double-click it in the extracted archive, wherever that is (for example Downloads).
rem It finds the game itself: in every Steam library, else in the GOG Galaxy and Epic default
rem folders. To pick a folder yourself, drag the game folder onto this file.
rem What it does (nothing else):
rem   1. Checks the game is closed.
rem   2. Copies install\KCDPerf.asi (the patch), install\KCDPerf.ini (its settings, kept if you
rem      already have one) and install\version.dll (Ultimate ASI Loader) to Bin\Win64, next to
rem      KingdomCome.exe. A different version.dll that is already there is left alone.
rem   3. Copies the uninstaller to the game folder as CPUPerformancePatch-Uninstall.bat.
rem No game file is changed. Windows needs no launch option: it loads version.dll from the game
rem folder by itself. Files are recognised by their exact size in bytes.
title CPU Performance Patch - install
set "ASI_SIZE=@ASI_SIZE@"
set "UAL_SIZE=@UAL_SIZE@"
set "SELF=%~dp0"
set "SELF=%SELF:~0,-1%"
set "ARG=%~1"
echo CPU Performance Patch 1.0.0 - install
call :findgame
if not defined GAME goto :nogame
echo Game folder: "%GAME%"
set "B=%GAME%\Bin\Win64"
tasklist /fi "imagename eq KingdomCome.exe" 2>nul | find /i "KingdomCome.exe" >nul && goto :running
if not exist "%SELF%\install\KCDPerf.asi" (set "ERR=install\KCDPerf.asi is missing from the extracted folder." & goto :fail)
if not exist "%SELF%\install\KCDPerf.ini" (set "ERR=install\KCDPerf.ini is missing from the extracted folder." & goto :fail)
if not exist "%SELF%\install\version.dll" (set "ERR=install\version.dll is missing from the extracted folder." & goto :fail)
call :size "%SELF%\install\KCDPerf.asi" SZ
if not "%SZ%"=="%ASI_SIZE%" (set "ERR=install\KCDPerf.asi is damaged. Download the mod again." & goto :fail)
call :size "%SELF%\install\version.dll" SZ
if not "%SZ%"=="%UAL_SIZE%" (set "ERR=install\version.dll is damaged. Download the mod again." & goto :fail)

copy /y /b "%SELF%\install\KCDPerf.asi" "%B%\KCDPerf.asi" >nul || goto :copyfail
del /q "%B%\KCDPerf.log" 2>nul
echo Plugin: Bin\Win64\KCDPerf.asi copied.
if exist "%B%\KCDPerf.ini" (echo Settings: Bin\Win64\KCDPerf.ini is already there. Kept.& goto :loader)
copy /y "%SELF%\install\KCDPerf.ini" "%B%\KCDPerf.ini" >nul || goto :copyfail
echo Settings: Bin\Win64\KCDPerf.ini copied.
:loader
set "CUR="
if exist "%B%\version.dll" call :size "%B%\version.dll" CUR
if defined CUR if not "%CUR%"=="%UAL_SIZE%" goto :foreign
copy /y /b "%SELF%\install\version.dll" "%B%\version.dll" >nul || goto :copyfail
copy /y "%SELF%\install\Ultimate-ASI-Loader-LICENSE.txt" "%B%\Ultimate-ASI-Loader-LICENSE.txt" >nul 2>nul
echo Loader: Bin\Win64\version.dll copied (Ultimate ASI Loader).
goto :uninstaller
:foreign
echo Loader: Bin\Win64\version.dll is already there and is a different file. Left alone.
echo         If it is an ASI loader, the patch loads through it. Check Bin\Win64\KCDPerf.log after a start.

:uninstaller
copy /y "%SELF%\Uninstall-Windows.bat" "%GAME%\CPUPerformancePatch-Uninstall.bat" >nul && echo Uninstaller copied to the game folder: CPUPerformancePatch-Uninstall.bat
echo.
echo Done. No launch options are needed on Windows. Start the game.
echo Bin\Win64\KCDPerf.log then says "smart: on". Settings: Bin\Win64\KCDPerf.ini (a text file).
echo.
pause
exit /b 0

:copyfail
set "ERR=Could not copy into Bin\Win64 (no permission?). Try right-click, Run as administrator."
goto :fail
:nogame
set "ERR=Kingdom Come: Deliverance not found. Drag the game folder (the one with Bin, Data and Engine) onto this file."
goto :fail
:running
set "ERR=The game is running. Close it first."
:fail
echo.
setlocal EnableDelayedExpansion
echo ERROR: !ERR!
endlocal
echo Nothing more was changed.
echo.
pause
exit /b 1

:size
set "%~2=%~z1"
exit /b

rem Game folder search: around this file, the dragged folder, Steam libraries, GOG/Epic defaults.
:findgame
set "GAME="
for %%I in ("%SELF%\..\..") do if exist "%%~fI\Bin\Win64\KingdomCome.exe" set "GAME=%%~fI"
if defined GAME exit /b
if exist "%SELF%\Bin\Win64\KingdomCome.exe" (set "GAME=%SELF%" & exit /b)
if defined ARG call :trydir "%ARG%"
if defined GAME exit /b
set "STEAM="
for /f "tokens=2,*" %%A in ('reg query "HKCU\Software\Valve\Steam" /v SteamPath 2^>nul ^| find /i "SteamPath"') do set "STEAM=%%B"
if not defined STEAM set "STEAM=%ProgramFiles(x86)%\Steam"
set "STEAM=%STEAM:/=\%"
call :trylib "%STEAM%"
if exist "%STEAM%\steamapps\libraryfolders.vdf" for /f usebackq^ tokens^=2^,4^ delims^=^" %%A in ("%STEAM%\steamapps\libraryfolders.vdf") do if /i "%%A"=="path" call :trylib "%%B"
if defined GAME exit /b
call :trydir "%ProgramFiles(x86)%\GOG Galaxy\Games\Kingdom Come Deliverance"
call :trydir "%ProgramFiles%\Epic Games\KingdomComeDeliverance"
exit /b
:trylib
if defined GAME exit /b
set "L=%~1"
set "L=%L:\\=\%"
call :trydir "%L%\steamapps\common\KingdomComeDeliverance"
exit /b
:trydir
if not defined GAME if exist "%~1\Bin\Win64\KingdomCome.exe" set "GAME=%~f1"
exit /b
