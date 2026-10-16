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
2. **Explorers:** you start in the pilot's seat 4 km from Aster High Port, which appears once it's built.
   Open the map (**M**), click Aster Ice Field, and fly there (about 15 km: a minute at cruise, less with
   boost). Hold **F** to mine ice, then fly back within 1.5 km of the port, slow down, and press **F** to deliver.
3. **Builder:** the job completes, 10 ice lands in stock, and Hydroponics unlocks.
   Pilots are paid by how much each delivered.

## Raids: facilities and the pilots who rob them

Based on the Facility Heist design doc. Builders build **facilities** on Aster (tap an empty slot):

| Facility | Cost | Fills its vault with |
| --- | --- | --- |
| Mining Refinery | 40 metal | Alloy plates, isotope cells, rarely exotic matter |
| Research Outpost | 30 metal, 10 ice | Design drives and blueprint cases (plans) |
| Data Spire | 50 metal, 150 credits | Data shards and security dossiers (intel) |

**Builder (phone):** tap a facility to see its vault. *Ship cargo to HQ* brings the goods home
(materials and plans go to stock, intel sells for credits; once a minute). Spend them on
**security tiers**: more guards, vault turrets, rarer loot and a longer raid clock. When a pilot
boards, the facility turns red and the Raids list shows live where the intruder is (breaching,
which level, or racing the self-destruct), their Heat and time left.
*Sound the alarm* (50 credits) adds 25 Heat for them. A raid can reach 60% of each vault stack; the
rest is in deep storage, and anything the raider doesn't carry out goes back in the vault.

**Explorer (PC):** facilities orbit 25 km from the Spaceport and show on the map in red. Fly
within 1.5 km, slow down and press **F** to set down on the facility's landing pad. A raid then
runs in three stages, on foot and in first person:

1. **Breach.** The map is the facility's site exactly as the Builder laid it out on its grid
   (a satellite site's turrets, guard posts, walls, power plant and leftover obstacles; a facility
   without a site gets defences set out from its security tier). Shoot turrets, guard posts and the
   **power plant** to destroy them. With the power plant down the core's **blast door** opens; with
   no power plant the core runs on its own power and the door never opens. Either way you can cut
   through one of the core's **vents** instead (6 s, silent).
2. **Loot.** From the lobby a lift takes you down. The facility has one level below ground for each
   level of its core building (its security tier until buildings have levels), up to five. Deeper
   levels are bigger, with more guards and turrets and rarer loot. Each level's lift down is in the
   room furthest from where you arrived. Every minute inside brings in a bigger wave of guards.
3. **Extraction.** The **safe room** on the deepest level holds the vault, behind red doors: swipe
   the **access keycard** (hidden in a container on that level) or drill it (loud, 30 s). A Vault
   Warden boss may be waiting there. Opening the vault starts the **self-destruct** (60 s plus 30 s
   per level): ride the lifts back up and board your ship before it ends, or you die with the
   facility, lose your ship and keep only your Secure Case.

- **Search** containers with **F**: items show as dark placeholders and reveal one at a time.
  Left-click takes into the backpack, right-click into the **Secure Case**, which you keep if you die.
- **Heat** rises with time, gunfire, explosions, being spotted and bodies found. At Alerted guards
  hunt you and turrets wake; Purge sends an elite team. Standing guard posts send out new guards.
- **Leave** any time by standing on your ship's pad for 3 s. If the raid clock runs out you're
  missing in action.
- Extracted loot goes to your stash; sell it to the Fence at the Spaceport for half its value.

| On foot | Keyboard and mouse | Gamepad |
| --- | --- | --- |
| Move, look | W A S D, mouse (or arrow keys) | Left stick, right stick |
| Sprint / crouch (quiet) / jump | Shift / C / Space | Left stick click / B / Y |
| Fire / aim / reload | Left / right mouse / R | RT / LT / X |
| Search, swipe, drill, silent takedown from behind | F | A |
| Inventory / use a trauma kit | Tab / H | Back / D-pad up |
| Pause (bail out in the first 2 minutes) | Esc | Start |

## Flying (Explorer)

Teal Prime is built at roughly real scale: Aster is 200 light seconds from the star, and a
small ship cruises at 280 m/s with full engine power, as in Elite Dangerous. Flight assist keeps the
ship flying where its nose points; turn on drift to fly with free Newtonian momentum instead.
The phase-shift drive crosses the system: it charges for 4 seconds, can't start within 5 km of the
station, speeds up the further you are from planets and the star, and slows as you near your
destination, dropping you out about 2 km short of it.

| Control | Keyboard and mouse | Gamepad |
| --- | --- | --- |
| Steer (pitch, yaw) | Mouse as a virtual stick (middle click recentres), or arrow keys | Right stick |
| Roll | Q / E | LB / RB |
| Throttle up / down | W / S | RT / LT |
| All stop | X | Left stick click |
| Strafe, thrust up/down | A / D, Space / Ctrl | Left stick |
| Boost (5 s cooldown) | Shift | B |
| Phase-shift drive | J | Y |
| Drift (flight assist off) | Z | X |
| Power to systems / engines / weapons, balance | 1 / 2 / 3 / 4 | D-pad left / up / right / down |
| Mine, deliver | F | A |
| Navigation map | M | Back |
| Chat | Enter | Guide |
| Settings and rebinding | Esc | Start |

Every control can be rebound in Settings, which is also how a HOTAS is set up: click a binding and
move the stick axis or press the button you want. Settings also hold drift on or off by default,
hold-to-drift, mouse invert and sensitivity, and the HUD colour. They save to Godot's user folder.

Power works as in Elite: six pips shared across systems (shield recharge), engines (top speed,
turn rate, boost recharge) and weapons (the mining laser). The map has Local, System and Galactic
levels, filters for landmarks, waypoints and other pilots, and a route queue (shift-click).
Chat works from both the cockpit and the phone; the ship keeps flying while you type.

## Play the Builder on your real phone

Run the server on your computer, then export the game to Android from Godot
(Project > Export, add an Android preset). On the phone's start screen choose Builder and
set the server to `ws://<your computer's Wi-Fi address>:8080`. Both devices must be on the same Wi-Fi.

## Tests

```bash
cd server && npm test     # the ice job, raid rules, and a full raid over real WebSockets
```

`game/tests/raid.tscn` plays a whole raid against a running server: land, blow up the power
plant, ride the lifts to the deepest level, find the keycard, open the vault, get back up and
board the ship (instructions at the top of `game/tests/raid_test.gd`).

`game/tests/flight_test.gd` checks the flight model on its own:
`godot --headless --path game --script res://tests/flight_test.gd`

`game/tests/smoke.tscn` is a headless check of both modes against a running server
(instructions at the top of `game/tests/smoke.gd`).
