@echo off
REM Run main trading scene (windowed)
REM Usage: F:\Aion\LegendaryTrader\Project\run_game.bat
setlocal

set "PROJ=%~dp0"
if "%PROJ:~-1%"=="\" set "PROJ=%PROJ:~0,-1%"

set "GODOT_DIR=F:\Aion\Godot_v4.6.2-stable_win64.exe"
set "GODOT_GUI=%GODOT_DIR%\Godot_v4.6.2-stable_win64.exe"
set "GODOT_CON=%GODOT_DIR%\Godot_v4.6.2-stable_win64_console.exe"

if not exist "%GODOT_GUI%" (
    echo [run_game] FATAL: Godot GUI exe not found: %GODOT_GUI%
    exit /b 2
)

echo [run_game] PROJ=%PROJ%
echo [run_game] GODOT=%GODOT_GUI%
echo [run_game] launching main scene...

"%GODOT_GUI%" --path "%PROJ%" "res://scenes/Main.tscn"
exit /b %ERRORLEVEL%
