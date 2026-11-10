@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem CPU Performance Patch 1.0.0 - uninstaller for Windows.
rem Works from the game folder (the installer leaves a copy there as CPUPerformancePatch-Uninstall.bat)
rem or from the extracted archive (it then finds the game the same way the installer does; or drag
rem the game folder onto this file).
rem What it does:
rem   1. Deletes Bin\Win64\KCDPerf.asi, KCDPerf.ini, KCDPerf.log and KCDPerf.cmd.
rem   2. Deletes Bin\Win64\version.dll if it is the loader this mod installed and no other .asi
rem      plugin is left in Bin\Win64 (another plugin would still need it).
rem   3. Deletes CPUPerformancePatch-Uninstall.bat from the game folder.
title CPU Performance Patch - uninstall
set "UAL_SIZE=@UAL_SIZE@"
set "SELF=%~dp0"
set "SELF=%SELF:~0,-1%"
set "ARG=%~1"
echo CPU Performance Patch 1.0.0 - uninstall
call :findgame
if not defined GAME goto :nogame
echo Game folder: "%GAME%"
set "B=%GAME%\Bin\Win64"
tasklist /fi "imagename eq KingdomCome.exe" 2>nul | find /i "KingdomCome.exe" >nul && goto :running

del /q "%B%\KCDPerf.asi" "%B%\KCDPerf.ini" "%B%\KCDPerf.log" "%B%\KCDPerf.cmd" "%B%\KCDPerf.frames" 2>nul
if exist "%B%\KCDPerf.asi" (set "ERR=Could not delete Bin\Win64\KCDPerf.asi. Try right-click, Run as administrator." & goto :fail)
echo Plugin: Bin\Win64\KCDPerf.asi removed.
if not exist "%B%\version.dll" (echo Loader: no version.dll there.& goto :done)
call :size "%B%\version.dll" CUR
if not "%CUR%"=="%UAL_SIZE%" (echo Loader: Bin\Win64\version.dll is not the file this mod installs. Left alone.& goto :done)
set "OTHER="
if exist "%B%\*.asi" set "OTHER=1"
if exist "%B%\scripts\*.asi" set "OTHER=1"
if exist "%B%\plugins\*.asi" set "OTHER=1"
if defined OTHER (echo Loader: another .asi plugin is still in Bin\Win64. version.dll left in place for it.& goto :done)
del /q "%B%\version.dll" "%B%\Ultimate-ASI-Loader-LICENSE.txt" 2>nul
echo Loader: Bin\Win64\version.dll removed.

:done
echo.
echo Done. The game draws its far shadows and streams its textures the stock way again.
echo.
pause
if /i "%SELF%"=="%GAME%" goto :delself
del /q "%GAME%\CPUPerformancePatch-Uninstall.bat" 2>nul
exit /b 0
:delself
(goto) 2>nul & del /q "%~f0"

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
