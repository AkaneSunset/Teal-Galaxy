#!/usr/bin/env bash
# Starts the galaxy server plus three game windows: one phone-shaped Builder, two Explorers.
# Usage: GODOT=/path/to/godot ./run_local.sh
set -e
cd "$(dirname "$0")"
GODOT="${GODOT:-godot}"
# Registers the game's classes (the battle screens and the rest) so a fresh checkout runs.
"$GODOT" --headless --path game --import >/dev/null 2>&1 || true
(cd server && npm install --silent && node server.js) &
SERVER=$!
trap 'kill $SERVER 2>/dev/null' EXIT
sleep 1
# Each window signs in to an account of its own (opened the first time), so side locks never tie
# the two pilots together.
"$GODOT" --path game -- --mode=builder --name=Akane --account=Akane --password=local-play &
"$GODOT" --path game -- --mode=explorer --name="Pilot A" --account="Pilot A" --password=local-play &
"$GODOT" --path game -- --mode=explorer --name="Pilot B" --account="Pilot B" --password=local-play &
wait
