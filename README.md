# Teal Galaxy

A galactic city builder you play on your phone, set in a galaxy you explore on PC.
Phone players (Builders) grow star systems and planetary bases. PC players (Explorers)
fly to those places, take the jobs builders post, and play together.

This is the first playable prototype: one star system, one planet, one job loop.

## What's here

| Folder | What it is |
| --- | --- |
| `game/` | One Godot 4.5 project with two modes: **Builder** (phone) and **Explorer** (PC) |
| `server/` | The galaxy server (Node.js + WebSockets). Holds the shared galaxy and keeps every app in sync |

## Run it on one computer

You need [Godot 4.5](https://godotengine.org/download) and [Node.js 20+](https://nodejs.org).

**Quick way:** set `GODOT` to your Godot program and run the launcher. It starts the server,
a phone-shaped Builder window, and two Explorer windows.

```bash
GODOT=/path/to/godot ./run_local.sh        # Mac / Linux
set GODOT=C:\path\to\Godot.exe & run_local.bat   # Windows
```

**From the Godot editor:**

1. Start the server: `cd server && npm install && npm start`
2. Open `game/project.godot` in Godot.
3. Debug > Customize Run Instances: enable multiple instances, set 3, and give them launch arguments
   `-- --mode=builder --name=Akane`, `-- --mode=explorer --name=PilotA`, `-- --mode=explorer --name=PilotB`.
4. Press Play. Without arguments the game shows a start screen where you pick a mode.

## The prototype loop

1. **Builder:** build a Spaceport on planet Aster (costs 30 metal), then post the job
   "deliver 10 ice for 100 credits". Mines add metal over time.
2. **Explorers:** the Spaceport appears on top of Aster. Fly to the pale asteroid field (to your right
   at the start), hold **E** to mine ice, then fly to the Spaceport and press **E** to deliver.
3. **Builder:** the job completes, 10 ice lands in stock, and Hydroponics unlocks.
   Pilots are paid by how much each delivered.

Explorer controls: W/S thrust, A/D turn, R/F pitch, Space brake, E interact.

## Play the Builder on your real phone

Run the server on your computer, then export the game to Android from Godot
(Project > Export, add an Android preset). On the phone's start screen choose Builder and
set the server to `ws://<your computer's Wi-Fi address>:8080`. Both devices must be on the same Wi-Fi.

## Tests

```bash
cd server && npm test     # builder + two pilots complete the ice job over real WebSockets
```

`game/tests/smoke.tscn` is a headless check of both modes against a running server
(instructions at the top of `game/tests/smoke.gd`).
