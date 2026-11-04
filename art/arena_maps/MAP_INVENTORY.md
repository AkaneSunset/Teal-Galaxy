# Every map in the arena modes report, and where it's built

This lists every map and map layout described in *Arena Shooter Game Modes: What Works, Why, and What Teal
Galaxy Should Build*, with the layout data the report gives for each one and the Blender map that builds
it (in this folder). There are 19 maps in total.

The report also names existing maps from other games as examples: Live Fire, Recharge, Streets, Fortress,
Forbidden, Aquarius and Origin (Halo), Gold Rush (TF2) and Route 66 (Overwatch). Those are other studios'
maps, so they're not rebuilt here. Their design rules are part of the archetypes below, and each map here is
an original Teal Galaxy layout that follows those rules.

## A. The Teal Galaxy map concepts (section 10.4, table 14, figure 16)

| Map (Blender id) | Canon space | Archetype | Modes | Layout data in the report |
|---|---|---|---|---|
| High Port Ring (`high_port_ring`) | Walkable station / High Port | Static zones, rotational symmetry | Sector Hold, Hardpoint, Slayer, Oddball | A ring corridor around a core atrium. Three zones 120° apart, so it works for 2 or 3 teams. Balconies round the atrium give height. It's the only map for the three-faction event format (3 zones, 3 spawns; table 17). |
| Carrier Dock Pads (`carrier_dock_pads`) | Builder base with Carrier Dock; crew walk-out | Mirrored three-lane | Slayer, CTF, Hardpoint | Two landed carriers face each other across a dock. Ramps and cargo make the lanes, and each carrier's hold is a base. |
| Hangar and Flight Deck (`hangar_flight_deck`) | Carrier vehicle bays and flight deck | Rotating hill | Hardpoint, Slayer | The hill rotates round the hangar floor, a lift, the deck catapult and the observation tower. Long sightlines on deck, close quarters below. |
| Outpost Vault (`outpost_vault`) | Outpost surface grid (12x12), levels below ground, vault | Bomb attack-defend | Core Breach, One Flag "Data Core" | Attackers come in from the surface grid and go down two or three shafts. Two charge points on the lower level. Defenders spawn near the vault. |
| Carrier Boarding (`carrier_boarding`) | Carrier bridge, power, decks | Linear progress (Hybrid) | Boarding Action | Section 1: take the hangar. Section 2: escort a breach charge through the power room. Section 3: the bridge. Forward spawns at each checkpoint. Figure 16 has the flight deck and hangar as the two attacker entries, then the power room, then the bridge. |
| Besieged Outpost (`besieged_outpost`) | Outpost with turrets and walls | Wave hub | Coma Firefight | A hub at the outpost core. Coma phase-shifting bots drop in at the edges. Resupply is at the turrets, away from cover. |

Every one of these should also get a cosmetic skin for each faction (Compact armour plate, Ashen dark hulls,
Luminar clean lines) with identical geometry.

## B. The four map archetypes (sections 5, 6 and 8; figures 7, 8, 10 and 12)

| Map (Blender id) | Archetype | Modes | Layout data in the report |
|---|---|---|---|
| Twin Bastions (`twin_bastions`) | 1: symmetric three-lane arena (figure 7) | CTF, Slayer; also One Flag and Neutral Bomb | Two mirrored bases (rotated or reflected), each with its flag, a spawn area, 2 or 3 entrances and a high defensive perch. The **top lane** has long sightlines and the sniper or power weapon, with mirrored weapon pickups (W). The **middle** is a short route with the contested power-up (P). The **bottom lane** has cover and flanks and is the flag-run route. The flag-to-flag run is about 25 to 40 s on foot, tuned to the capture limit (3 or 5). Neutral Bomb uses a symmetric map with the bomb spawning in the middle. |
| Spindle Yard (`spindle_yard`) | 2: rotating hill (figure 8, left) | Hardpoint, King of the Hill | H1 in the middle, H2 to H5 round it, team spawns on the left and right. The hill moves on a fixed rotation, every 60 s in the CDL. Each hill has 2 or 3 entries and a nearby high spot or "power position". The power weapon sits off the hill's line. Spawns flip as the hill moves. |
| Three Pylons (`three_pylons`) | 2: static three zones (figure 8, right) | Domination, Strongholds, Land Grab, Total Control | Red and Blue spawns in the top corners, then zones A, B and C in a row. A and C are the "home" points, and B is the fight. Holding 2 of 3 outscores the enemy, and flipping their home point flips their spawns. Scoring is 2 zones = 1/s and 3 zones = 2/s (Halo); CoD Domination is 1, 2 or 3 per tick. There's a mid power-up near B. |
| Supply Line (`supply_line`) | 3: linear progress (figure 10) | Payload, Escort, Hybrid, Rush, Breakthrough | The attacker spawn is at the start of one winding route, and the cart or robot starts beside it. The route has three sections, each with its own choke the defenders can hold. CP1 and CP2 add time and move both sides' spawns forward, and the final point is a capture or the bomb. Defender spawns sit beside each section. Health packs are along the route. Each section is a mini-map, and the map is played once per side in competitive play. Hybrid starts with a capture point; Rush has charge stations (M-COMs) in each sector. |
| Lattice (`lattice`) | 4: node-chain war map (figure 12) | Onslaught, Warfare, Conquest | A red core and a blue core (5,000 HP) with power nodes (2,000 HP) between them in a chain: core to two nodes, both to a centre node, that to two nodes, both to the other core. A node can be built or attacked only if it links to your core or a node you hold, and the enemy core is open only while you hold a node linked to it. Scoring is 2 points for a core kill, 1 in sudden death. Warfare adds the Orb (an instant node capture) and side nodes (a vehicle node, a countdown node). Conquest and Onslaught maps are very large, for 16 to 64 players with vehicles. |

## C. The per-mode map types (table 9 and sections 4, 7 and 8)

| Map (Blender id) | Map type | Modes | Layout data in the report |
|---|---|---|---|
| Foundry Spire (`foundry_spire`) | Deathmatch / FFA arena (Quake tradition) | DM, FFA, Duel, Clan Arena, Freeze Tag, Invasion | Small to medium, 2 to 8 players. Symmetry isn't needed but the loops are balanced. Many loops and no single choke. Spawns away from the nearest enemy. Item timing (armour, power-ups) is the objective. High verticality with jump routes. Clan Arena takes the items out; Invasion is played on Deathmatch maps. |
| Longwatch (`longwatch`) | Instagib map | Instagib | Long sightlines and verticality, because every hit kills and the skill is in tracking and dodging. |
| Crossfire Box (`crossfire_box`) | Gun Game map | Gun Game | Small and symmetrical, so neither side has an edge. |
| Nest Loop (`nest_loop`) | Oddball map (compact loop) | Oddball; also KotH and Strongholds | A compact, mirrored loop. The ball spawns in the middle. There are several defensible "nests" where the carrier is shielded by teammates, each breakable from at least two directions. Verticality is high. |
| Relay Sites (`relay_sites`) | Bomb / Search and Destroy map | S&D, bomb defusal | Medium, asymmetric by role, with sides swapping at halftime. Attackers start on one side with 2 or 3 routes to each of two sites. Defenders start nearer the sites and must split. A fixed start, with no respawns in a round, and a loadout instead of pickups. Verticality is low to medium. |
| Tug Line (`tug_line`) | Push map | Push | Long and mirrored, with one central track. The robot starts in the middle and pushes a barricade toward whichever team's spawn it's moving, at about 1.22 m/s. Forward spawns open after each checkpoint. Health packs. |
| Goal Field (`goal_field`) | Bombing Run map | Bombing Run | A long symmetric field like a CTF map, but with a single ball spawn in the centre and a hoop at each end. Carrying the ball through scores 7 and throwing it through scores 3, so the area near each hoop matters most. |
| Attrition Front (`attrition_front`) | Attrition map | Attrition | Larger, with AI soldiers so even weaker players have targets that score. Points: grunts 1, reapers 3, pilots 5, heavies 10 (Titanfall's values). The heavy unit here stands in for a Titan. |
| *(Besieged Outpost, above)* | Firefight / Invasion wave hub | Firefight | Medium arena. One strong defensive hub surrounded by enemy drop zones. Players start at the hub. Resupply is placed so players have to leave cover. Waves come from the edges. |

Modes with no map of their own in the report, and where they're played:

- Hardpoint and KotH: Spindle Yard, High Port Ring, Hangar and Flight Deck, Carrier Dock Pads.
- One Flag, Neutral Flag and Neutral Bomb: Twin Bastions (as CTF maps, with the object in the middle or in one base).
- TDM / Slayer: every symmetric map. The report's Slayer map is mirrored with 3 lanes, team-biased spawns away from enemies, a power weapon in the contested middle and medium to high verticality.
- Infection: any of the small arenas.

## Shared map rules (section 9)

- A mirrored map, or a side swap, is the price of a fair objective.
- Spawns must respond to the objective (Domination's spawn flip, Hardpoint spawns following the hill, Escort's forward spawns), so a winning team can't camp the losing team's spawn.
- The strongest pickup sits on the path to the objective, not on top of it.
- One map pool, many modes: each map gets a base layout good for Slayer, and each mode adds its own overlay of objective spots, spawn sets and pickups. Compact looped arenas carry zone modes and Oddball, and long base-to-base maps carry flag and bomb modes.
- "Size" means the time to cross the map on foot, not metres.
