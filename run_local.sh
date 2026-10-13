#!/usr/bin/env bash
# Starts the galaxy server plus three game windows: one phone-shaped Builder, two Explorers.
# Usage: GODOT=/path/to/godot ./run_local.sh
set -e
cd "$(dirname "$0")"
GODOT="${GODOT:-godot}"
(cd server && npm install --silent && node server.js) &
SERVER=$!
trap 'kill $SERVER 2>/dev/null' EXIT
sleep 1
"$GODOT" --path game -- --mode=builder --name=Akane &
"$GODOT" --path game -- --mode=explorer --name="Pilot A" &
"$GODOT" --path game -- --mode=explorer --name="Pilot B" &
wait
