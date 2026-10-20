# Teal Galaxy

A galactic city builder you play on your phone, set in a galaxy you explore on PC.
Phone players (Builders) grow star systems and planetary bases. PC players (Explorers)
fly to those places, take the jobs builders post, and play together.

This is an early playable prototype: one star system with a planet for every Builder, jobs,
walkable space stations shared with the other pilots there, first-person raids on Builders' outposts,
and a galactic war between factions, fought with navies across seven star systems and, on the
ground, in real-time sector battles commanded from a walkable fleet carrier.

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
Demo mode also turns on **the demo war**, for play-testing sector battles: every faction holds at least
25% of the orbit of every system that isn't a capital (so anyone may bring a carrier anywhere), footholds
are waived, a captured planet locks for 5 minutes instead of a week, and every pilot flies a
[fleet carrier](#the-fleet-carrier-demo). Pilots can still take sectors by hand too (see
[Taking planets](#taking-planets)).

**Fast battles:** `BATTLE_SPEED=10 npm start` runs [sector battles](#sector-battles) ten times faster
(the game tests use 10 to 20).

**Admins:** start the server with `ADMIN_KEY=<any secret> npm start`, and apps that say hello with
that key can play the Coma Conglomerate and steer its AI director (see
[The Coma Conglomerate](#the-coma-conglomerate-admins-and-the-ai-director)).

## The Builder screen

The Builder is a base-builder view of your home planet, like Clash of Clans, played with the phone held sideways.
Every Builder gets their own planet and economy: the first one to connect takes Aster, later ones found
Brisa, Corvo and so on. Drag to pan, pinch (or scroll the mouse wheel) to zoom. Six build pads ring the command centre:
tap a pad to select it, and its actions appear at the bottom (Info, Post job on the Spaceport,
Ship cargo, security tier upgrades and the Alarm on outposts). **Build** (bottom right) opens the shop:
pick a building, then tap a free pad (or select an empty pad first and it builds there).
Jobs, Raids, Chat, Sites (your outposts) and War open from the buttons bottom left, and activity and
alerts pop up as short messages. The first time you connect, the faction choice covers the screen
until you pick a side (see [The faction war](#the-faction-war)); the header then shows your faction
and War Merit rank.
During a raid the outpost glows red and a banner shows the raid clock; tap it to jump there.
Buildings without a finished 3D model yet use the stand-ins in `game/base_models.gd`.
The ground around every base and outpost is an icy, faceted landscape generated from its id
(`game/terrain.gd`): a flat clearing for the base, then snow, frost-covered slopes, bare rock cliffs, mesas
and jagged peaks further out, with mist drifting in the valleys. Most bases also get a cliff (or a ledge dropping away) off one side,
and many a winding canyon off another, so the high ground doesn't ring the base like a crater. No two bases look the same, and a base
always looks the same each time you open it.

**Build times and levels.** Every building takes time to build (Mine 20 s up to 3 min for a Hauler Yard or Carrier Dock) and
does nothing until it's finished: its pad shows scaffolding and a countdown. Once built, select it and press
*Level N* to upgrade it, up to level 5. Each level costs twice the one before and takes twice as long, and
the building stops working while it upgrades. Higher levels produce more: Mines, Extractors, Habitats and
Hydroponics add their base rate again per level, outposts make more per batch and hold more, the Ship
Foundry builds warships 25% faster per level, and the Spaceport makes outpost freighters come sooner.
Defences placed on a site take a few seconds to build and don't fight until they're done.

**Passive income.** Buildings produce on their own, so a Builder grows even with no pilots online:
Mines dig 12 metal a minute, Ice Extractors (15 metal) melt 2 ice a minute, Habitats pay 12 credits a
minute in rent and Hydroponics sells 24 credits of food a minute. The first ice unlocks Hydroponics, however
it arrives. Outposts fill their vaults, and a freighter brings the goods home every 5 minutes
on its own (*Ship cargo* sends one sooner); until then the vault is there for pilots to raid. Pilots' ice
jobs are still the fast way to get ice: one delivery is 10.

**Outposts** (the nine types are under [Outposts](#outposts)) don't go on pads: buying one in the shop
opens a sector picker, and the outpost is founded on its own site in the sector you tap, on a contested
planet your faction holds. **Sites** lists your home and your outposts ("Cinder 7 Fuel Depot", "Cinder,
sector 7"). A site is a free 12x12 grid with the outpost's core in the middle; Build opens the defence
shop there: Turrets (2x2, 20 metal, 5 alloy), Walls (1x1, 5 metal), Guard posts (2x2, 15 metal) and one
Power plant (2x2, 25 metal), which powers the core's main door for raids, placed on any free tiles.
Tap a piece to remove it for half its cost back.
A new site also comes scattered with obstacles that block building until you clear them for credits:
Boulders (120 credits, leave 10 metal), Ice crystals (40 credits, leave 4 ice) and Old wreckage
(200 credits, leave 25 metal and 2 alloy). Tap one and press *Clear*.
Every base has its own place on its planet's surface, well apart from the others, and outposts stand in
their sector, a little apart when it has more than one; the planet holograms in the High Ports and
orbital stations mark each one.

**Ship Foundry** (60 metal, 10 ice, needs a Spaceport, one per base) builds warships for your navy.
Tap it and open the **Shipyard** to queue Corvettes (25 metal, 1 min), Frigates (50 metal, 10 alloy, 3 min)
or Destroyers (100 metal, 25 alloy, 3 isotope cells, 8 min). Ships build one at a time, up to 5 in the
queue and 10 in the hangar, counting ships out with your fleets; cancelling the last one refunds it.
Finished ships wait in the hangar (the navy count is in the top bar, and tapping it opens the Shipyard).
*War map: send fleets* in the Shipyard opens the War screen, where your navy fights for orbits (see
[Navies and orbital control](#navies-and-orbital-control)).

## The prototype loop

1. **Builder:** pick a faction, build a Spaceport on planet Aster (costs 30 metal), then post the job
   "deliver 10 ice for 100 credits". Mines add metal over time.
2. **Explorers:** pick a side too (or *Not now*). You start in the pilot's seat 4 km from Aster High Port, which appears once it's built.
   Open the map (**M**), click Aster Ice Field, and fly there (about 15 km: a minute at cruise, less with
   boost). Hold **F** to mine ice, then fly back within 1.5 km of the port, slow down, and press **F** to deliver.
3. **Builder:** the job completes, 10 ice lands in stock, and Hydroponics unlocks.
   Pilots are paid by how much each delivered.

## The faction war

Four factions are at war over Teal Prime and the systems around it, mirroring Supreme Commander's.
Every character picks a side once, for good: each Builder base and each pilot picks its own (a Builder and
a pilot with the same name are different characters, and neither can act for the other). Players choose
from three; the fourth, the Coma Conglomerate, is played by the galaxy's admins and its AI director.

| Faction | Mirrors | Style | Bonus |
| --- | --- | --- | --- |
| Terran Compact | UEF | Durable and methodical: shields, artillery, heavy armour | Outpost defences are 25% tougher in raids |
| Ashen Collective | Cybran | Fast and tricky: stealth, cloaking, hit and run | Raiders build Heat 25% faster inside your outposts |
| Luminar Accord | Aeon | Hover units, precise and powerful strikes | Outposts produce 20% more |
| Coma Conglomerate (admins only) | Seraphim | Alien tech, strong all-round units, the strategic missile | Outposts recover from raids twice as fast |

The phone asks before anything else: tap *Join* on a card, then tap again to join for good. A pilot gets
the same cards on PC and can put it off with *Not now* and choose later from the ship's menu. Your side
shows in the phone's header and the PC HUD.

### The war map

Seven star systems joined by lanes. Teal Prime, the Builders' home system, is in the middle, each
faction's capital system is next to it, and Marrow Reach and The Drift lie beyond, held by nobody at the start.

| System | Lanes to | What it is | Contested planets (first owner) |
| --- | --- | --- | --- |
| Teal Prime | Fortitude, Umbra, Aurelia, Comae | the Builders' home system | Cinder (Compact), Vesper (Ashen), Halcyon (Luminar), Morrow (Coma) |
| Fortitude | Teal Prime, Marrow Reach | Terran Compact capital | Bastion, Anvil |
| Umbra | Teal Prime, Marrow Reach | Ashen Collective capital | Shade, Hollow |
| Aurelia | Teal Prime, The Drift | Luminar Accord capital | Radiance, Glimmer |
| Comae | Teal Prime, The Drift | Coma Conglomerate capital | Nadir, Zenith |
| Marrow Reach | Fortitude, Umbra | neutral | Scar, Rift, Cairn |
| The Drift | Aurelia, Comae | neutral | Eddy, Mire |

Each planet of the war has 10 to 25 sectors, each linked to its nearest neighbours; the first is its
capital sector. The planets of a capital system are **capital worlds**: their faction's for good. The
Builders' own home planets (Aster, Brisa, ...) aren't part of the war at all and are always safe. A
planet is *quiet* while one faction at most can fight over it, a *front line* with two and a *warzone*
with three or more.

On the phone, **War** opens the War screen: the map on the left, each contested planet a dot in its
owner's colour (with a padlock while it's locked), a ring round each system for its orbital control,
and markers for the fleets. Tap a system for its planets (owner, sectors each faction holds, lock time
left, contention), its orbital control bars with the 25% line, the fleets there and *Send fleet*. On PC
the nav map's Galactic level (**M**) is the war map, with each system's planets, orbital control and
fleets written under it and your faction's systems lit up; the System level marks Teal Prime's
contested planets. Click a planet there, use one of the **War terminals** in a station's Terminal
Hall, or pick *War terminal* in the ship's menu, for the sector view: the planet as a globe you drag
to turn, its sectors in their owners' colours, the links between them, the capital sector ringed and
outposts as small squares. The Terminal Hall's boards show the war front and the fleets in orbit.

### Outposts

Every site a Builder founds is an **outpost**, one of nine types (the first three were the Mining
Refinery, Research Outpost and Data Spire):

| Outpost | Cost | Build | Fills its vault with |
| --- | --- | --- | --- |
| Extractor | 40 metal | 1.5 min | Alloy plates, isotope cells, rarely exotic matter |
| Armoury | 30 metal, 10 ice | 2 min | Weapon systems, design drives and blueprint cases |
| Sensor Works | 50 metal, 150 credits | 2.5 min | Sensor modules, data shards and security dossiers |
| Fuel Depot | 30 metal, 10 ice | 1 min | Fuel cells |
| Light Munitions Works | 40 metal | 1.5 min | Slug crates and shell crates |
| Heavy Munitions Works | 50 metal, 10 alloy | 2 min | Missiles, torpedoes, rarely a strategic warhead |
| Drone Yard | 50 metal, 15 alloy | 2.5 min | Drone chassis |
| Lander Yard | 60 metal, 15 alloy | 2.5 min | Lander chassis |
| Hauler Yard | 70 metal, 20 alloy | 3 min | Hauler hulls |

Outposts go only on the contested planets of your own system (Cinder, Vesper, Halcyon and Morrow in
Teal Prime), on a planet your faction holds, in a sector your faction holds. The sector picker lists
each of those planets with a button per sector and the outposts already in it; another faction's
sectors and full ones are greyed out. A Builder can have **5 outposts**, and a sector holds **3**
(everyone's together). Each is named after its sector: "Cinder 7 Fuel Depot". War goods come home to
stock like materials: sell them at your Carrier Dock, fill contracts with them or donate them. Sites
from before the war move to a sector your faction holds when you pick your side.

**Dormancy.** When your faction loses the planet an outpost stands on, the outpost goes **dormant**:
it makes nothing, no freighter comes for its vault, and you can't build, place, clear or upgrade
anything there or raise its security. Raiders can still break in. It wakes up exactly as it was when
your faction retakes the planet. The phone marks it *Dormant* and says why, and the station holograms
dim it.

### Navies and orbital control

Fleets don't take ground: they fight for **orbital control** of a system, and a faction needs at least
**25%** of a system's orbital control before it can attack the planets there. Holding a system's orbit
never secures it on its own; only its planets do.

Builders send their ships: pick a system on the War screen, choose how many of each ship from the
hangar and press *Send fleet*.
A fleet can go to any system that isn't a capital: Teal Prime, Marrow Reach or The Drift. It flies a
jump per lane from Teal Prime, passing through capital systems but never stopping in one. A jump takes
2 minutes divided by the slowest ship's speed (Corvette 3, Frigate 2, Destroyer 1), and holding Teal
Prime's own orbit is a quarter of a jump, so a fleet with a Destroyer in it is over Teal Prime in 30 s
and over Marrow Reach or The Drift in 4 min. *Recall* turns a fleet round: one in orbit takes the whole
way home, one still flying comes back as far as it came. Home, its ships rejoin the hangar.

A faction's share of a system's orbit is its stationed fleets' power over everyone's (attack plus a
fifth of hull per ship: Corvette 4, Frigate 11, Destroyer 26). When two or more factions have fleets
in orbit together they fight a round every 2 minutes, the first one 2 minutes after they meet (time
to call yours home): each side's attack is split across the others by their power, the lightest ships
sink first, and every round goes in the war log. A fleet that arrives where another faction is in
orbit has no say in orbital control until it has fought a round there (or the others have left), so
a fleet called home before every round never wins any.

**Upkeep.** A fleet uses fuel cells from your stock as it takes station and every 10 minutes it stays
in orbit (Corvette 1, Frigate 2, Destroyer 4 a ship), or 20 credits for each cell you're short. With
neither, it comes home and your phone tells you.

### Taking planets

A planet belongs to the faction holding its **capital sector and 75%** of its sectors. When it changes
hands it **locks for a week**, and nobody can attack it until then. To attack a planet a faction needs
25% of the orbital control of its system and a **foothold** near it: a sector of that planet, another
planet it holds in the same system, or at least half the planets of a system one lane away (a capital
system counts as wholly its faction's). Once it holds a sector of a planet, the next must be linked to
one it holds. Capital worlds can't be attacked at all. Builders with outposts on a planet get an alert
when one of their faction's sectors there falls.

Sectors change hands in [sector battles](#sector-battles). A server started with `DEMO=1` also lets
pilots take sectors by hand: in the War terminal's sector view a sector your side may take has
*Take sector (demo)*, and every rule above applies.

### Carrier Dock, contracts and war supply

**Carrier Dock** (80 metal, 10 alloy, needs a Spaceport, one per base, 3 min) is where your faction's
carriers will dock. For now it hosts your **dock market**: select it and open *Dock market* to put a
price on anything in stock (1 to 100000 credits a unit) or take it off sale; it keeps trading while
the dock upgrades. Pilots of your faction buy from it when they land at your base, from the ship's menu
or the console in front of the dock; you're paid at once, and told. What they buy goes in their
**war goods hold**, for the carriers to come.

**Supply contracts.** A pilot posts a contract for metal, ice or a material or war supply (1 to 1000
units, at most 5 open) from a station's Job Board or the ship's menu, and the reward is held from
their credits. Builders of the same faction find it under **Jobs** and fill as much of it as they like
from stock, paid their share of the reward as they go; the goods go in the pilot's hold. The pilot can
cancel it and get back whatever hasn't been paid.

**War supply and War Merit.** The War screen's **Supply** tab gives goods from stock to your faction's
war supply in your system, which sector battles will spend. Each unit earns War Merit by its value
(metal 2, ice 3, any other item what it's worth), and Merit ranks make your outposts produce more:

| Rank | War Merit | Outposts produce |
| --- | --- | --- |
| Recruit | 0 | as normal |
| Supplier | 500 | 2% more |
| Quartermaster | 2000 | 4% more |
| Provisioner | 8000 | 6% more |
| War Industrialist | 25000 | 8% more |

### The Coma Conglomerate: admins and the AI director

Players can't join the Coma Conglomerate. The galaxy's admins play it, and the rest of the time an AI
director does, steered by the admins to keep players busy: it pushes hardest on the strongest player
faction and eases off weaker or quieter ones.

**Admins.** Start the server with `ADMIN_KEY=<any secret>` (unset or empty: nobody is an admin). An
app that says hello with the same key is an admin's. Type the key into *Admin key* on the start
screen (phone and PC), or on PC into *Admin key* in Settings (Enter reconnects), or start the game with
`-- --admin-key=<key>` (the argument wins). A typed key is saved with the settings for the server it
was typed for, and the app only ever sends it to that server. The phone also asks for the key when the
server turns away a Coma character. The server never sends the key back, logs it or saves it. The PC
HUD says *admin* once the server knows you as one.

Admins see the Coma Conglomerate on the faction cards, tagged *Admins only*, and can play characters
for it. A Coma character is protected by the key: an app without it is turned away, and both apps
show the server's reason. An app that was already playing the character without the key is turned
away the moment an admin takes it into Coma.

**What admins can do.** The **Director** tab of the phone's War screen and the *Coma director (admin)*
page of the PC War terminal:

- pause the director, and set its master scale from 0 to 2;
- for each player faction, see its strength, its automatic intensity and the intensity in use, and
  fix a level from 0 to 1 or leave it on *Auto*;
- set each of Teal Prime, Marrow Reach and The Drift to **Push** (armadas match the strongest player
  faction there), **Hold** (nothing new goes in, nothing is called home) or **Withdraw** (every armada
  there comes home at once);
- see Coma's armada power in each system against the strongest player faction's, send an armada of
  their own (power 10 to 400) and recall any armada;
- take sectors for Coma with *Take for Coma*, in the phone's Director tab or the PC sector view, with
  every rule of the war (no demo mode needed).

Any change takes effect at once, and the director takes its turn straight away unless it's paused.

**How the director picks its intensity.** Every 5 minutes it scores each player faction: half its share
of the war's sectors (capital worlds aside), three tenths its mean orbital share over Teal Prime,
Marrow Reach and The Drift, and a fifth its share of the players active in the last day. The strongest
faction gets intensity 1 and the others less in proportion, down to 0.15 (all 0.15 when nobody scores).
An admin's fixed level replaces the automatic one. In each system on Push the director aims for the
strongest player faction's fleet power there times that faction's intensity and the scale, or a patrol
of 30 power (times the scale and the mean intensity) where no player fleet is. When it's short by more
than a corvette it sends an armada from Comae (destroyers first, then frigates, then corvettes), and
when it has more than 1.25 times what it needs it calls its smallest armadas home. All armadas together
stay under 600 power times the scale; when that limit bites, the systems with the strongest factions
come first.

**What players see.** Armadas are ships in space: every war map shows them, as a *Coma armada* (a
diamond on the maps) with its ships, and they fight, hold orbit and count for orbital control like any
fleet. They need no supplies, and they stand down when they get home to Comae. The war log says what
they do ("A Coma armada of 2 Destroyers and 3 Frigates is heading for Teal Prime") but never shows the
director's numbers. Players are never sent the director's settings, or which armadas an admin sent.

## Raids: outposts and the pilots who rob them

Based on the Facility Heist design doc. Every [outpost](#outposts) fills a vault, and pilots of the
other factions break in to rob it.

**Builder (phone):** tap an outpost's core and press Info to see its vault. *Ship cargo to HQ* brings the goods home
(materials, plans and war goods go to stock, intel sells for credits; once a minute). Spend them on
**security tiers**: more guards, vault turrets, rarer loot and a longer raid clock. When a pilot
boards, the outpost turns red and the Raids list shows live where the intruder is (breaching,
which level, or racing the self-destruct), their Heat and time left.
*Sound the alarm* (50 credits) adds 25 Heat for them. A raid can reach 60% of each vault stack; the
rest is in deep storage, and anything the raider doesn't carry out goes back in the vault.

**Explorer (PC):** every Builder planet (Aster, Brisa, Corvo...) has a **High Port** in orbit, and each
contested planet of Teal Prime (Cinder, Vesper, Halcyon, Morrow) has an **orbital station** (Cinder
Orbital, ...) over its outposts; all of them are on the nav map. Fly within 1.5 km, slow down and press
**F** to dock: your ship lands on pad 06 in the station's hangar and you're in the pilot's seat, with
the ship's menu up. From the seat you can leave it and walk down the ramp into the station, fly down to
the planet's base from a High Port (your ship lands beside the Builder's Spaceport, in the base the
Builder sees on their phone, where you deliver jobs, sell to the Fence, trade at a Carrier Dock or
walk around), raid one of the planet's outposts from an orbital station, or launch back into space.
After a raid you're back in your seat in the hangar. Walking back up your ship's ramp sits you down
again; Esc only pauses, since the way out of a place is your ship.

You raid only the outposts of other factions, so pick a side first. The ship's menu lists your own
side's outposts as friendly (they can't be picked) and marks dormant ones, which can still be raided.
Faction bonuses count inside: a Terran Compact outpost's defences have 25% more hit points, Heat builds
25% faster in an Ashen Collective one, and a Coma Conglomerate outpost is ready for the next raid in
half the time (2.5 minutes, not 5).

### How a raid plays

Picking an outpost in the ship's menu flies you to it. Everything after that is on foot, in first
person:

1. **Pick where to land.** The raid opens on an overhead map of the site and the ground around it.
   Each turret's reach is a red ring. Click a spot on open ground (off the site, outside every red
   ring, within 120 m of the core) and confirm. Your ship flies in, drops you off beside it facing
   the site, and **leaves**.
2. **Break the outside.** The site is exactly as the Builder laid it out, drawn with their own models
   on the same terrain: turrets, guard posts, walls, power plant and leftover obstacles, plus the
   turrets the security tier mounts on the core. Shoot defences (or grenade them) to destroy them.
   With the power plant down the core's **blast door** opens; with no power plant the core runs on
   its own power and the door never opens, so cut through one of its **vent** grates instead (6 s,
   silent). Your ship comes back, to a pad beside the blast door, **only once every outside defence
   is destroyed**: turrets (the core's too), guard posts and power plants. Sneaking in through a vent
   doesn't change that. The HUD shows how many are left.
3. **Clear down to the vault.** The outpost has one level below ground for each level of its core
   building, up to five. Deeper levels are bigger, with more guards and turrets and rarer loot. Each
   level's lift down is in the room furthest from where you arrived, and every minute inside brings a
   bigger wave of guards. The **safe room** on the deepest level holds the vault behind amber doors:
   swipe the **access keycard** (hidden in a container on that level) or drill it (loud, 30 s). A
   Vault Warden may be waiting there.
4. **Escape the self-destruct.** Opening the vault starts the **self-destruct** (70 s plus 30 s per
   level). Ride the lifts back up and board your ship at the blast door (stand on its pad for 3 s)
   before it ends, or you die with the outpost, lose your ship and keep only your Secure Case.

- **Search** containers with **F**: items show as dark placeholders and reveal one at a time.
  Left-click takes into the backpack, right-click into the **Secure Case**, which you keep if you die.
- **Heat** rises with time, gunfire, explosions, being spotted and bodies found. At Alerted guards
  hunt you and turrets wake; Purge sends an elite team. Standing guard posts send out new guards.
- **Bailing out:** in the first 2 minutes the pause menu can recall your ship, ending the raid with
  nothing you found. If the raid clock runs out you're missing in action.
- Extracted loot goes to your stash; sell it to the Fence (the black market terminal in a High
  Port's Cantina, or any Spaceport) for half its value.

### Your kit: health, armour, healing and weapons

- **Health and armour,** as in Apex Legends: 100 health plus the armour of your vest, shown in
  25-point segments. Armour takes damage first and nothing grows back. Every raid starts in a
  50-armour vest; 75 (Heavy) and 100 (Assault) vests turn up inside, mostly on deeper levels. **F**
  on one puts it on and leaves yours behind, with what armour it had left. Vests are for the raid only.
- **The healing pouch** is separate from the backpack:

  | Item | Restores | Takes | Pouch holds |
  | --- | --- | --- | --- |
  | Syringe | 25 health | 5 s | 4 |
  | Med kit | all health | 8 s | 2 |
  | Shield cell | 25 armour | 3 s | 4 |
  | Shield battery | all armour | 5 s | 2 |

  **Tap H** to use the best item for what you're missing (armour first; the small item for a little,
  the big one for most of a bar). **Hold H** for the heal wheel: point at a slice with the mouse or
  right stick and let go, or let go in the middle to cancel. The raid doesn't pause. You walk slowly
  while using one, and a ring round the crosshair fills; firing, sprinting or switching weapons stops
  it without using it up, but taking damage doesn't. What's in your pouch when you extract comes with
  you next raid (the server keeps the counts); die and it's lost. An empty pouch is refilled with the
  basic kit: 2 syringes, a med kit, 2 shield cells and a battery.
- **Health supplies inside:** white **med cabinets** with a green cross hang on the walls of about one
  room in three (more deeper down). Search them like lockers for healing and sometimes a vest. Loose
  syringes and shield cells lie on shelves and floors; **F** picks them up. If your pouch is full the
  rest stays where it is.
- **Two weapons.** The **rifle** (30-round magazine, 150 spare) and the **grenade launcher**: 7 rounds
  for the whole raid, one a second. Grenades arc and burst on impact: 6 m across, up to 120 damage at
  the centre falling off to nothing at the edge, and three times that against the site's defences and
  turrets. Walls stop the blast, it's loud, and your own does half damage to you. While aiming the
  launcher a dotted arc shows where it will land. Switching takes half a second and stops a reload.

| Raid | Keyboard and mouse | Gamepad |
| --- | --- | --- |
| Pick a landing spot / confirm | Click / F or Enter | Left stick / A |
| Move, look | W A S D, mouse (or arrow keys) | Left stick, right stick |
| Sprint / crouch (quiet) / jump | Shift / C / Space | Left stick click / B / Y |
| Fire / aim / reload | Left / right mouse / R | RT / LT / X |
| Rifle / grenade launcher | 1 / 2, or the mouse wheel | D-pad right |
| Search, swipe, drill, silent takedown from behind | F | A |
| Inventory / heal (tap: best item, hold: wheel) | Tab / H | Back / D-pad up (right stick picks a slice) |
| Pause (recall your ship and bail out in the first 2 minutes) | Esc | Start |

**Inside the High Port.** *Leave your seat* takes you down your ship's ramp into the station
(`game/station.gd`), built from Akane's concept art; orbital stations are built the same way. Every ship has an exit ramp: a landed ship that's
open has its ramp down and walking up it boards the ship (yours sits you back in the pilot's seat); a
locked ship keeps its ramp up. A Concourse Ring lined with windows circles the Planetary Terminal Hall,
where a hologram of the planet marks every base and outpost (outposts in their faction's colour, dimmed
while dormant, red while under raid), the Surface Transit consoles open the same trips as the ship's
menu, and two War terminals open the [war map's](#the-war-map) sector view. Off the ring: Ship Services
(repairs your ship), the Supply Shop, the Commodity Exchange, the Job Board (deliver cargo, and supply
contracts), the Cantina (live chat on its
screen, and the black market terminal in its back corner, where the Fence buys raided loot), the Security Office (the raid log as a wanted
board), the Crew Cabins and the Observation Lounge. The mouse looks around, F uses things, Enter chats
and Esc pauses. A Builder's base on the surface (`game/surface.gd`) works the same way on foot, with a
console in front of a finished Carrier Dock for its market.
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
| Leave seat (fleet carrier) | G | Right stick click |
| Outside view (fleet carrier) | V | |
| Chat | Enter | Guide |
| Settings and rebinding | Esc | Start |

Every control can be rebound in Settings, which is also how a HOTAS is set up: click a binding and
move the stick axis or press the button you want. Settings also hold drift on or off by default,
hold-to-drift, mouse invert and sensitivity, the HUD colour and the admin key for the server you're
on (for the galaxy's [admins](#the-coma-conglomerate-admins-and-the-ai-director) only). They save to
Godot's user folder.

Power works as in Elite: six pips shared across systems (shield recharge), engines (top speed,
turn rate, boost recharge) and weapons (the mining laser). The map has Local, System and Galactic
levels (the Galactic level is the [war map](#the-war-map)), filters for landmarks, waypoints and other
pilots, and a route queue (shift-click).
Chat works from both the cockpit and the phone; the ship keeps flying while you type.

## The fleet carrier (demo)

On a `DEMO=1` server every pilot's ship is a **fleet carrier**: a 260 m warship in its pilot's faction
colours with a flight deck, a bridge island, gun sponsons and four engines. It flies like the small ship,
only heavier (slower to turn and to get going; boost still works). Other pilots' carriers are drawn the
same way. **V** switches to the outside view.

**Leave seat (G**, or the button on the HUD) gets you up from the pilot's chair while flying: the carrier
sheds its speed over two seconds and holds still, and you're on your feet on the Bridge, with the real
sky, the planet and the stations out of the windows. Sit in the chair again (**F**) to fly. Aboard:

| Deck | What's there |
| --- | --- |
| Bridge | The pilot's chair on its dais, the wide forward window, crew consoles; COMMS (**F**) opens or closes your carrier to visitors |
| Command Deck | The **holo table** (**F**: [Sector Battles](#sector-battles) for the planet below, with its sectors floating over the table), the war log, the planet-below screen |
| Crew Lounge | The lobby: sofas, the bar and its stools (**F** to sit), who's aboard, the pilots' channel |
| Hangar Deck | Down the lift: parked tanks, strikers, gunships and landers, the launch doors, and the airlock to the station when docked |

**Docking and pads.** Near a station, slow down and press **F** to ask for a berth (`dock_request`).
Each copy of a station has 32 pads, and a full station opens another copy, so the pads decide how many
pilots share one. The carrier then flies itself in (approach, lining up, final approach, clamps) in
about 25 seconds while you watch from outside; **F** skips to the clamps. It says where you are:
*Berth 12, Cinder Orbital (1)*, the number in brackets being the copy. Clamped, you're in the chair;
undock from there.

**Shared spaces.** On foot you share the space with everyone in the same one: a station's copy, a
carrier, or a Builder's base. You see the others walk, run and sit, with their names over them, and chat
works as everywhere. From the Hangar Deck the airlock leads into the station's **Carrier Berths**, where
every carrier docked in your copy has a boarding gate ("Board Akane's carrier"; yours is lit green;
the hall has nine at a time, and DOCK CONTROL by the entrance shows the next nine).
Walk through one to visit that carrier; the same gate, or the shuttle console on its Hangar Deck, takes
you back. If its owner undocks with you aboard, you ride along as crew, and you can only step off where
the carrier docks next.

## Sector battles

A sector battle is a real-time battle over one sector of a contested planet, in the spirit of
Supreme Commander: Forged Alliance, simulated on the server for up to 32 pilots. Open **Sector Battles**
from the carrier's holo table (or the War terminal's sector view): it shows the planet below, its sectors
and owners, which ones your side can attack (the same rules as [taking planets](#taking-planets); you
must be aboard a carrier in that planet's orbit, within 30 km of its orbital station or docked there),
and the battles running there. **Attack sector** starts one; **Join battle** joins one on your side (the
defenders' pilots can also join from the planet's station). The defender is the sector's owner, played
by an AI (plus any of its pilots who join), or a militia if nobody holds it. You lead one attack at a
time: starting another gives up the last one unless other pilots are still fighting it.

The RTS view takes over the screen. You start with 400 mass and earn 2 a second from your carrier plus
3 per Mass Extractor. Call units in by drop pod from the panel on the right; they land in your landing
zone 6 seconds later. Engineers build extractors on mass points, turrets and land factories.
The defender's AI keeps a guard round its base and, after giving you five minutes to dig in, sends
waves at your strongest group (*Enemy wave incoming*); its army grows with yours, and a faction fields
more than a militia. **Destroy the Command Node** to take the sector (*Sector taken*); the defenders win if they
hold for 30 minutes, if the attackers have nothing on the field for a minute, or if none of the
attackers' pilots has been in the battle for five minutes. An attack is called off if the planet locks
meanwhile (another sector's battle took it). Either way a banner says so and you're back at the holo
table.

| Command | Keys and mouse |
| --- | --- |
| Select | Left click, left drag for a box, double click for every unit of that type on screen, Shift adds |
| Move / attack | Right click on the ground / on an enemy |
| Attack-move | **A**, then left click |
| Stop | **S** |
| Queue orders | Hold Shift (queued waypoints are drawn as lines) |
| Build (engineers) | The build buttons, then left click (extractors snap to mass points); or right click a free mass point |
| Produce (a factory selected) | The produce buttons |
| Groups | Ctrl+1-9 sets a group, 1-9 recalls it (twice: look at it) |
| Camera | WASD, the arrow keys or the screen's edges to pan; the wheel to zoom from 25 m to the whole map (units turn into strategic icons past 500 m); Q / E or middle drag to turn; Space looks at your units, H at your landing zone; click the minimap to look there |
| Take control | **P** with one unit selected: WASD drives it, the mouse aims, left mouse fires (+25% damage); **P** or Esc hands it back |
| Leave battle | The button at the top: your units stay on the field, and Join battle brings you back |

## Play the Builder on your real phone (Android)

1. Start the server on your computer (`cd server && npm start`). It prints the address to use, such as
   `Phone: ws://192.168.1.20:8080`. If the phone can't connect, allow Node through the computer's firewall.
2. Install the APK on the phone: copy `teal-galaxy.apk` over (or download it), open it, and allow
   installing from that app when Android asks.
3. Open Teal Galaxy, type your name and the server address, and tap **Play**. Both devices must be on
   the same Wi-Fi. The phone remembers both for next time.

The phone app is the Builder only, held sideways either way up. Android's back button closes the open
panel, the shop or the War screen a step at a time, and leaves the app when nothing is open.

**Building the APK yourself.** `game/export_presets.cfg` has an **Android** preset (arm64, internet
permission, the app icon). In Godot install the export templates (Editor > Manage Export Templates),
set the Android SDK and a keystore in Editor Settings > Export > Android, then Project > Export > Android.
Or headless, with the keystore in environment variables:

```bash
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=/path/to/your.keystore
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=<alias> GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=<password>
godot --headless --path game --export-release Android ../build/teal-galaxy.apk
```

Sign every build with the same keystore so a new APK installs over the old one.

## Tests

```bash
cd server && npm test     # every server rule (jobs, raids, the war, the director, admin keys, shared spaces, sector battles) and games over real WebSockets
```

The game tests play against a running server, each on a **fresh galaxy**: give the server a save file
that doesn't exist yet, and a port of its own if you run several at once.

`game/tests/smoke.tscn` is a headless check of both modes against a server started with `BUILD_SPEED=0`
(instant buildings). Run the two roles at the same time: the Builder joins the Terran Compact, posts the
ice job, founds a Fuel Depot on a sector of Cinder with the ice and opens the War screen; the pilot
joins the Ashen Collective, mines and delivers the ice, and opens the war map and the War terminal.

```bash
cd server && rm -f /tmp/smoke.json && SAVE_FILE=/tmp/smoke.json PORT=9000 BUILD_SPEED=0 npm start
godot --headless --path game res://tests/smoke.tscn -- --role=builder --server=ws://127.0.0.1:9000    # second terminal
godot --headless --path game res://tests/smoke.tscn -- --role=explorer --server=ws://127.0.0.1:9000   # third, together
```

For the admin check, start the server with `ADMIN_KEY=letmein` as well and add `--admin-key=letmein`
to both: they check that the Coma Conglomerate is on the faction cards and the Director opens. Run
them without the key against the same kind of server and they check that neither shows. Each run
prints PASS or FAIL (instructions at the top of `game/tests/smoke.gd`).

`game/tests/raid.tscn` plays a whole raid against a running server (`DEMO=1 BUILD_SPEED=0`): a
Luminar Accord Builder founds an Extractor on a sector of Halcyon, lays it out and upgrades it to
level 3, then an Ashen Collective pilot docks at Halcyon Orbital, picks the outpost and a landing spot
from overhead, is dropped off, checks the site matches, blows up the power plant, checks armour,
healing, the heal wheel, the grenade launcher and supplies on level 1, rides the lifts to the deepest
level, finds the keycard, opens the vault, gets back up, destroys the remaining defences so the ship
returns, and boards it (instructions at the top of `game/tests/raid_test.gd`).

```bash
cd server && rm -f /tmp/raid.json && SAVE_FILE=/tmp/raid.json PORT=9001 DEMO=1 BUILD_SPEED=0 npm start
godot --headless --path game res://tests/raid.tscn -- --server=ws://127.0.0.1:9001
```

`game/tests/spaces_test.tscn` checks the fleet carrier and shared spaces against a `DEMO=1` server: two
pilots dock at Cinder Orbital (different pads, one copy); the game's pilot flies the automated approach,
leaves the chair, walks the carrier, goes through the airlock into the Carrier Berths, where each sees the
other move, is refused at the other's closed carrier, and boards it once it's open.
`game/tests/battle_test.tscn` plays a whole sector battle from the pilot's chair against a `DEMO=1`
server with fast battles: G to leave the seat, a walk to the holo table, F, Attack sector, tanks called
in, an attack-move (A and a click), a tank driven (P and D), and the fight until the Command Node falls
and the pilot is back on the Command Deck (it also checks the defenders' AI fought back, and that the War
terminal opens Sector Battles). `game/tests/rts_test.tscn` checks the RTS view itself: 360 units drawn in
budget, leaving and rejoining a battle, and taking a militia sector on Scar.

```bash
cd server && rm -f /tmp/spaces.json && SAVE_FILE=/tmp/spaces.json PORT=9002 DEMO=1 npm start
godot --headless --path game res://tests/spaces_test.tscn -- --server=ws://127.0.0.1:9002
cd server && rm -f /tmp/battle.json && SAVE_FILE=/tmp/battle.json PORT=9003 DEMO=1 BATTLE_SPEED=20 npm start
godot --headless --path game res://tests/battle_test.tscn -- --server=ws://127.0.0.1:9003
godot --headless --path game res://tests/rts_test.tscn -- --server=ws://127.0.0.1:9003   # a fresh server for each
```

Add `--shots=<folder>` and run them with a display (not `--headless`) to save screenshots along the way.
`game/tests/tour_shots.tscn` saves views of the carrier inside and out for looking it over (a display
and a `DEMO=1` server).

`game/tests/flight_test.gd` checks the flight model on its own, with no server:
`godot --headless --path game --script res://tests/flight_test.gd`

`game/tests/station_interior_shots.tscn` and `game/tests/station_shots.tscn` save screenshots of a
High Port. They need a display and a running server where Builders have built Spaceports on Aster (and
on Brisa, for `station_shots`); instructions at the top of each.
