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

**Demo mode:** start the server with `DEMO=1 npm start` and every Builder base gets 2000 metal, 200 ice,
200 alloy, 40 isotope cells, a few plans and 5000 credits, enough to try every building, defence, warship and
security tier, and everything builds 10 times faster. Each base is topped up once, the first time its Builder connects with demo mode on.

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
The ground around every base and satellite site is an icy, faceted landscape generated from its id
(`game/terrain.gd`): a flat clearing for the base, then snow, frost-covered slopes, bare rock cliffs, mesas
and jagged peaks further out, with mist drifting in the valleys. Most bases also get a cliff (or a ledge dropping away) off one side,
and many a winding canyon off another, so the high ground doesn't ring the base like a crater. No two bases look the same, and a base
always looks the same each time you open it.

**Build times and levels.** Every building takes time to build (Mine 20 s up to Data Spire 2.5 min) and
does nothing until it's finished: its pad shows scaffolding and a countdown. Once built, select it and press
*Level N* to upgrade it, up to level 5. Each level costs twice the one before and takes twice as long, and
the building stops working while it upgrades. Higher levels produce more: Mines, Extractors, Habitats and
Hydroponics add their base rate again per level, facilities make more per batch and hold more, the Ship
Foundry builds warships 25% faster per level, and the Spaceport makes facility freighters come sooner.
Defences placed on a site take a few seconds to build and don't fight until they're done.

**Passive income.** Buildings produce on their own, so a Builder grows even with no pilots online:
Mines dig 12 metal a minute, Ice Extractors (15 metal) melt 2 ice a minute, Habitats pay 12 credits a
minute in rent and Hydroponics sells 24 credits of food a minute. The first ice unlocks Hydroponics, however
it arrives. Facilities fill their vaults as before, and a freighter brings the goods home every 5 minutes
on its own (*Ship cargo* sends one sooner); until then the vault is there for pilots to raid. Pilots' ice
jobs are still the fast way to get ice: one delivery is 10.

**Satellite sites.** Facilities (below) don't go on pads: buying one founds its own satellite site off your
planet (up to 3), opened from **Sites**. A site is a free 12x12 grid with the facility in the middle;
Build opens the defence shop there: Turrets (2x2, 20 metal, 5 alloy), Walls (1x1, 5 metal),
Guard posts (2x2, 15 metal) and one Power plant (2x2, 25 metal), which powers the facility's main
door for raids, placed on any free tiles. Tap a piece to remove it for half its cost back.
A new site also comes scattered with obstacles that block building until you clear them for credits:
Boulders (120 credits, leave 10 metal), Ice crystals (40 credits, leave 4 ice) and Old wreckage
(200 credits, leave 25 metal and 2 alloy). Tap one and press *Clear*.

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
boards, the facility turns red and the Raids list shows live where the intruder is (breaching,
which level, or racing the self-destruct), their Heat and time left.
*Sound the alarm* (50 credits) adds 25 Heat for them. A raid can reach 60% of each vault stack; the
rest is in deep storage, and anything the raider doesn't carry out goes back in the vault.

**Explorer (PC):** every Builder planet (Aster, Brisa, Corvo...) has a **High Port** in orbit, on the
nav map. Fly within 1.5 km, slow down and press **F** to dock: your ship lands on pad 06 in the High
Port's hangar and you're in the pilot's seat, with the ship's menu up. From the seat you can leave it
and walk down the ramp into the station, fly down to the planet's base (your ship lands beside the
Builder's Spaceport, in the base the Builder sees on their phone, where you deliver jobs, sell to the
Fence or walk around), raid one of the planet's facilities, or launch back into space. After a raid
you're back in your seat in the hangar. Walking back up your ship's ramp sits you down again; Esc
only pauses, since the way out of a place is your ship. Picking a facility in the menu flies your ship down to
the facility's landing pad. On foot and in first person:


- **Getting in.** The map outside is the site exactly as the Builder laid it out, drawn with the
  Builder's own models on the same terrain: their turrets, guard posts, walls, power plant and
  leftover obstacles, plus the turrets the security tier mounts on the core. Shoot defences to
  destroy them. With the power plant down the core's **blast door** opens; with no power plant the
  core runs on its own power and the door never opens. Either way you can cut through one of the
  core's **vent** grates instead (6 s, silent).
- **Going down.** The facility has one level below ground for each level of its core building, up
  to five. Deeper levels are bigger, with more guards and turrets and rarer loot. Each level's lift
  down is in the room furthest from where you arrived. Every minute inside brings a bigger wave of
  guards.
- **Getting out.** The **safe room** on the deepest level holds the vault, behind amber doors: swipe
  the **access keycard** (hidden in a container on that level) or drill it (loud, 30 s). A Vault
  Warden may be waiting there. Opening the vault starts the **self-destruct** (60 s plus 30 s per
  level): ride the lifts back up and board your ship before it ends, or you die with the facility,
  lose your ship and keep only your Secure Case.
- **Search** containers with **F**: items show as dark placeholders and reveal one at a time.
  Left-click takes into the backpack, right-click into the **Secure Case**, which you keep if you die.
- **Heat** rises with time, gunfire, explosions, being spotted and bodies found. At Alerted guards
  hunt you and turrets wake; Purge sends an elite team. Standing guard posts send out new guards.
- **Leave** any time by standing on your ship's pad for 3 s. If the raid clock runs out you're
  missing in action. You end up back in your ship's pilot seat in the High Port's hangar.
- Extracted loot goes to your stash; sell it to the Fence (the black market terminal in a High Port's Cantina, or any Spaceport) for half its value.

| On foot | Keyboard and mouse | Gamepad |
| --- | --- | --- |
| Move, look | W A S D, mouse (or arrow keys) | Left stick, right stick |
| Sprint / crouch (quiet) / jump | Shift / C / Space | Left stick click / B / Y |
| Fire / aim / reload | Left / right mouse / R | RT / LT / X |
| Search, swipe, drill, silent takedown from behind | F | A |
| Inventory / use a trauma kit | Tab / H | Back / D-pad up |
| Pause (bail out in the first 2 minutes) | Esc | Start |

**Inside the High Port.** *Leave your seat* takes you down your ship's ramp into the station
(`game/station.gd`), built from Akane's concept art. Every ship has an exit ramp: a landed ship that's
open has its ramp down and walking up it boards the ship (yours sits you back in the pilot's seat); a
locked ship keeps its ramp up. A Concourse Ring lined with windows circles the Planetary Terminal Hall,
where a hologram of the planet marks every base and site (red while under raid) and the Surface Transit
consoles open the same trips as the ship's menu. Off the ring: Ship Services (repairs your ship), the
Supply Shop, the Commodity Exchange, the Job Board (deliver cargo), the Cantina (live chat on its
screen, and the black market terminal in its back corner, where the Fence buys raided loot), the Security Office (the raid log as a wanted
board), the Crew Cabins and the Observation Lounge. The mouse looks around, F uses things, Enter chats
and Esc pauses. A Builder's base on the surface (`game/surface.gd`) works the same way on foot.
`game/tests/station_interior_shots.tscn` saves a picture of every room and of a base.

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

`game/tests/raid.tscn` plays a whole raid against a running server (`DEMO=1 BUILD_SPEED=0`): a
Builder lays out a site and upgrades it to level 3, then the pilot lands, checks the site matches,
blows up the power plant, rides the lifts to the deepest level, find the keycard, open the vault, get back up and
board the ship (instructions at the top of `game/tests/raid_test.gd`).

`game/tests/flight_test.gd` checks the flight model on its own:
`godot --headless --path game --script res://tests/flight_test.gd`

`game/tests/smoke.tscn` is a headless check of both modes against a server started with `BUILD_SPEED=0` (instant buildings)
(instructions at the top of `game/tests/smoke.gd`).
