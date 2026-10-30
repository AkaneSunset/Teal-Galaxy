@echo off
rem Starts the galaxy server plus three game windows: one phone-shaped Builder, two Explorers.
rem Usage: set GODOT=C:\path\to\Godot.exe  then  run_local.bat
cd /d "%~dp0"
if "%GODOT%"=="" set GODOT=godot
rem Registers the game's classes (the battle screens and the rest) so a fresh checkout runs.
"%GODOT%" --headless --path game --import >nul 2>&1
pushd server
call npm install --silent
start "Galaxy server" node server.js
popd
timeout /t 1 >nul
rem Each window signs in to an account of its own (opened the first time), so side locks never tie
rem the two pilots together.
start "" "%GODOT%" --path game -- --mode=builder --name=Akane --account=Akane --password=local-play
start "" "%GODOT%" --path game -- --mode=explorer --name="Pilot A" --account="Pilot A" --password=local-play
start "" "%GODOT%" --path game -- --mode=explorer --name="Pilot B" --account="Pilot B" --password=local-play
