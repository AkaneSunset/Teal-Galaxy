@echo off
rem Starts the galaxy server plus three game windows: one phone-shaped Builder, two Explorers.
rem Usage: set GODOT=C:\path\to\Godot.exe  then  run_local.bat
cd /d "%~dp0"
if "%GODOT%"=="" set GODOT=godot
pushd server
call npm install --silent
start "Galaxy server" node server.js
popd
timeout /t 1 >nul
start "" "%GODOT%" --path game -- --mode=builder --name=Akane
start "" "%GODOT%" --path game -- --mode=explorer --name="Pilot A"
start "" "%GODOT%" --path game -- --mode=explorer --name="Pilot B"
