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

## The Builder screen

The Builder is a base-builder view of your home planet, like Clash of Clans, played with the phone held sideways.
Every Builder gets their own planet and economy: the first one to connect takes Aster, later ones found
Brisa, Corvo and so on. Drag to pan, pinch (or scroll the mouse wheel) to zoom. Six build pads ring the command centre:
tap a pad to select it, and its actions appear at the bottom (Info, Post job on the Spaceport,
Ship cargo, security tier upgrades and the Alarm on facilities). **Build** (bottom right) opens the shop:
pick a building, then tap a free pad (or select an empty pad first and it builds there).
Jobs, Raids and Chat open from the buttons bottom left, and activity pops up as short messages.
During a raid the facility glows red and a banner shows the raid clock; tap it to jump there.
Buildings without a finished 3D model yet use the stand-ins in `game/base_models.gd`.

**Passive income.** Buildings produce on their own, so a Builder grows even with no pilots online:
Mines dig 12 metal a minute, Ice Extractors (15 metal) melt 2 ice a minute, Habitats pay 12 credits a
minute in rent and Hydroponics sells 24 credits of food a minute. The first ice unlocks Hydroponics, however
it arrives. Facilities fill their vaults as before, and a freighter brings the goods home every 5 minutes
on its own (*Ship cargo* sends one sooner); until then the vault is there for pilots to raid. Pilots' ice
jobs are still the fast way to get ice: one delivery is 10.

**Satellite sites.** Facilities (below) don't go on pads: buying one founds its own satellite site off your
planet (up to 3), opened from **Sites**. A site is a free 12x12 grid with the facility in the middle;
Build opens the defence shop there: Turrets (2x2, 20 metal, 5 alloy), Walls (1x1, 5 metal) and
Guard posts (2x2, 15 metal), placed on any free tiles. Tap a piece to remove it for half its cost back.

**Ship Foundry** (60 metal, 10 ice, needs a Spaceport, one per base) builds warships for your navy.
Tap it and open the **Shipyard** to queue Corvettes (25 metal, 1 min), Frigates (50 metal, 10 alloy, 3 min)
or Destroyers (100 metal, 25 alloy, 3 isotope cells, 8 min). Ships build one at a time, up to 5 in the
queue and 10 in the hangar; cancelling the last one refunds it. Finished ships wait in the hangar
(the navy count is in the top bar).

**Fleet attacks.** Tap the navy count (or *Fleet and attacks* in the Shipyard) to open the Fleet page. It
lists other Builders' satellite sites with their defence (placed pieces plus the security tier's turrets
and guards); tap one to send every ship in the hangar. The fleet flies 2 minutes divided by its slowest
ship's speed, and the defender sees a red *Incoming* banner meanwhile. The battle runs up to 6 rounds,
lightest ships sinking first. If the fleet breaks the defences it takes 40% of each vault stack and the
site gets a 10-minute shield; survivors fly home with the loot (intel sells for credits). Home planets
can't be attacked.

## The prototype loop

1. **Builder:** build a Spaceport on planet Aster (costs 30 metal), then post the job
   "deliver 10 ice for 100 credits". Mines add metal over time.
2. **Explorers:** you start in the pilot's seat 4 km from Aster High Port, which appears once it's built.
   Open the map (**M**), click Aster Ice Field, and fly there (about 15 km: a minute at cruise, less with
   boost). Hold **F** to mine ice, then fly back within 1.5 km of the port, slow down, and press **F** to deliver.
3. **Builder:** the job completes, 10 ice lands in stock, and Hydroponics unlocks.
   Pilots are paid by how much each delivered.

## Raids: facilities and the pilots who rob them

Based on the Facility Heist design doc. Builders buy **facilities** in the Build shop, and each one founds its own satellite site:

| Facility | Cost | Fills its vault with |
| --- | --- | --- |
| Mining Refinery | 40 metal | Alloy plates, isotope cells, rarely exotic matter |
| Research Outpost | 30 metal, 10 ice | Design drives and blueprint cases (plans) |
| Data Spire | 50 metal, 150 credits | Data shards and security dossiers (intel) |

**Builder (phone):** tap a facility and press Info to see its vault. *Ship cargo to HQ* brings the goods home
(materials and plans go to stock, intel sells for credits; once a minute). Spend them on
**security tiers**: more guards, vault turrets, rarer loot and a longer raid clock. When a pilot
boards, the facility turns red and the Raids list shows the intruder's Heat and time left live.
*Sound the alarm* (50 credits) adds 25 Heat for them. A raid can reach 60% of each vault stack; the
rest is in deep storage, and anything the raider doesn't carry out goes back in the vault.

**Explorer (PC):** facilities orbit 25 km from the Spaceport and show on the map in red. Fly
within 1.5 km, slow down and press **F** to board. Inside, on foot and in first person:

- The facility is a grid of rooms. The **vault** is the room furthest from the airlock, behind a
  red door: swipe an **access keycard** (one is hidden in some container) or drill it (loud, 30 s).
- **Search** containers with **F**: items show as dark placeholders and reveal one at a time.
  Left-click takes into the backpack, right-click into the **Secure Case**, which you keep if you die.
- **Heat** rises with time, gunfire, being spotted and bodies found. At Alerted guards hunt you and
  turrets wake, Lockdown seals the Escape Pod and sends reinforcements, Purge sends an elite team
  and doubles extract timers.
- **Extract** by standing in a zone: the Shuttle Pad outside the airlock (20 s, loud), the Service
  Lift (8 s, silent, eats a keycard) or the Escape Pod (5 s, one use, after minute 3). With 5 minutes
  left the extracts freeze as they are. If the clock runs out you're missing in action.
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

`game/tests/raid.tscn` plays a whole raid against a running server: board, find the keycard,
open the vault, extract (instructions at the top of `game/tests/raid_test.gd`).

`game/tests/flight_test.gd` checks the flight model on its own:
`godot --headless --path game --script res://tests/flight_test.gd`

`game/tests/smoke.tscn` is a headless check of both modes against a running server
(instructions at the top of `game/tests/smoke.gd`).
