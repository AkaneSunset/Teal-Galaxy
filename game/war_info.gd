extends RefCounted
## The faction war as the Explorer's screens see it: the four factions and their colours, the war
## map (g.war: systems, contested planets and their sectors, orbital control), the pilot's own side,
## and whether a sector can be taken. Read-only helpers over Net.state and Net.catalog.
##
## The rules here mirror the server's (war.js canAttack and capture) so a screen can say why
## before anything is sent; the server still decides.

const NEUTRAL := Color(0.55, 0.58, 0.62)
const DAY_MS := 24.0 * 3600_000.0


static func factions() -> Dictionary:
	return Net.catalog.get("factions", {})


## The factions in the server's order: compact, ashen, luminar, coma.
static func faction_ids() -> Array:
	return factions().keys()


## Whether players may join a faction. The Coma Conglomerate is for the galaxy's admins: they
## play it, and its AI director plays it the rest of the time.
static func playable(id: String) -> bool:
	return factions().get(id, {}).get("playable", true) == true


## The factions players pick from (and the director weighs up): compact, ashen, luminar.
static func player_factions() -> Array:
	return faction_ids().filter(func(f): return playable(f))


static func faction_name(id) -> String:
	if id == null or str(id) == "":
		return "Neutral"
	return str(factions().get(str(id), {}).get("name", str(id).capitalize()))


## "the Terran Compact", as the server says it.
static func the(id) -> String:
	return "the %s" % faction_name(id) if id != null and str(id) != "" else "nobody"


static func faction_color(id) -> Color:
	if id == null or str(id) == "":
		return NEUTRAL
	var hex := str(factions().get(str(id), {}).get("color", ""))
	return Color.html(hex) if Color.html_is_valid(hex) else NEUTRAL


## This pilot's faction, or "" before they have picked one.
static func my_faction() -> String:
	if Net.state.is_empty():
		return ""
	var f = Net.state.get("pilots", {}).get(Net.my_name, {}).get("faction")
	return str(f) if f != null else ""


## A Builder's faction (on their economy), or "".
static func builder_faction(builder: String) -> String:
	var f = Net.state.get("bases", {}).get(builder, {}).get("faction")
	return str(f) if f != null else ""


# --- The war map ------------------------------------------------------------------------------

static func war() -> Dictionary:
	return Net.state.get("war", {}) if not Net.state.is_empty() else {}


static func system(id: String) -> Dictionary:
	for s in war().get("systems", []):
		if s.id == id:
			return s
	return {}


## A contested planet of the war by id ("cinder"), or an empty Dictionary.
static func planet(id: String) -> Dictionary:
	for p in war().get("planets", []):
		if p.id == id:
			return p
	return {}


static func planets_in(system_id: String) -> Array:
	return war().get("planets", []).filter(func(p): return p.system == system_id)


static func sector(wp: Dictionary, id: String) -> Dictionary:
	for s in wp.get("sectors", []):
		if s.id == id:
			return s
	return {}


## How many of a planet's sectors `faction` holds.
static func held(wp: Dictionary, faction) -> int:
	var n := 0
	for s in wp.get("sectors", []):
		if s.owner == faction:
			n += 1
	return n


## How hard a planet is fought over: quiet with one side (or none) able to fight there, a front
## line with two, a warzone with more.
static func contention(wp: Dictionary) -> String:
	var n: int = wp.get("contenders", []).size()
	return "quiet" if n <= 1 else ("front line" if n == 2 else "warzone")


## How long a planet stays locked after changing hands ("6 more days"), or "" if it isn't.
static func lock_left(wp: Dictionary) -> String:
	var ms := float(wp.get("lockedUntil", 0)) - Net.now_ms()
	if ms <= 0.0:
		return ""
	if ms >= DAY_MS:
		var days := ceili(ms / DAY_MS)
		return "%d more day%s" % [days, "" if days == 1 else "s"]
	var hours := maxi(1, ceili(ms / 3600_000.0))
	return "%d more hour%s" % [hours, "" if hours == 1 else "s"]


## A faction's orbital control over a system, 0 to 1, from the fleets stationed there.
static func orbital(system_id: String, faction: String) -> float:
	return float(war().get("orbital", {}).get(system_id, {}).get(faction, 0.0))


static func carrier_share() -> float:
	return float(Net.catalog.get("war", {}).get("carrierShare", 0.25))


## How much of a system a faction holds: its share of the planets there (a capital system is
## wholly its own faction's).
static func system_share(system_id: String, faction: String) -> float:
	var s := system(system_id)
	if s.is_empty():
		return 0.0
	if s.get("capitalOf") != null:
		return 1.0 if s.capitalOf == faction else 0.0
	var ps := planets_in(system_id)
	return float(ps.filter(func(p): return p.owner == faction).size()) / ps.size() if not ps.is_empty() else 0.0


## A faction can only reach a planet near a foothold: a sector of it, another planet it owns in
## the system, or half of a system one lane away.
static func foothold(faction: String, wp: Dictionary) -> bool:
	if held(wp, faction) > 0:
		return true
	for p in war().get("planets", []):
		if p.id != wp.id and p.system == wp.system and p.owner == faction:
			return true
	for id in system(wp.system).get("lanes", []):
		if system_share(id, faction) >= 0.5:
			return true
	return false


## Why `faction` can't take a sector now, or "" when it can (the server's capture rules).
static func take_problem(faction: String, wp: Dictionary, sec: Dictionary) -> String:
	if faction == "":
		return "choose a faction first"
	if wp.get("capital", false):
		return "capital worlds can't be attacked"
	var lock := lock_left(wp)
	if lock != "":
		return "%s is locked for %s" % [wp.name, lock]
	if not foothold(faction, wp):
		return "%s has no foothold near %s" % [the(faction), wp.name]
	var share := orbital(wp.system, faction)
	if share + 1e-9 < carrier_share():
		return "you need %d%% orbital control of %s: you have %d%%" % [roundi(carrier_share() * 100.0), system(wp.system).get("name", wp.system), floori(share * 100.0 + 1e-9)]
	if sec.owner == faction:
		return "%s already holds %s" % [the(faction), sec.name]
	if held(wp, faction) > 0:
		var linked := false
		for id in sec.get("links", []):
			if sector(wp, id).get("owner") == faction:
				linked = true
		if not linked:
			return "%s isn't next to a sector you hold" % sec.name
	return ""


# --- Fleets and armadas ----------------------------------------------------------------------

## A Coma armada: one of the AI director's fleets (or one an admin sent), with no Builder behind it.
static func is_armada(fl: Dictionary) -> bool:
	return fl.get("ai", false) == true or fl.get("owner") == null


## "Coma armada", or "Brann's fleet".
static func fleet_name(fl: Dictionary) -> String:
	if is_armada(fl):
		return "%s armada" % faction_name(fl.get("faction")).get_slice(" ", 0)
	return "%s's fleet" % str(fl.owner)


## A fleet's fighting power, as the server counts it: each ship's attack plus a fifth of its hull
## (a corvette 4, a frigate 11, a destroyer 26).
static func power(ships: Dictionary) -> float:
	var defs: Dictionary = Net.catalog.get("ships", {})
	var p := 0.0
	for id in ships:
		if defs.has(id):
			p += int(ships[id]) * (float(defs[id].attack) + float(defs[id].hull) / 5.0)
	return p


static func ship_count(ships: Dictionary) -> int:
	var n := 0
	for id in ships:
		n += int(ships[id])
	return n


## "2 Destroyers, 3 Frigates"
static func ships_text(ships: Dictionary) -> String:
	var defs: Dictionary = Net.catalog.get("ships", {})
	var parts := []
	for id in ["destroyer", "frigate", "corvette"] + ships.keys():
		var n := int(ships.get(id, 0))
		if n > 0 and not parts.has(id):
			parts.append(id)
	return ", ".join(parts.map(func(id): return "%d %s%s" % [int(ships[id]), defs.get(id, {}).get("name", str(id).capitalize()), "" if int(ships[id]) == 1 else "s"]))


## The fleets in orbit over a system or on their way there (not those heading home).
static func fleets_at(system_id: String) -> Array:
	return war().get("fleets", []).filter(func(fl): return fl.system == system_id and fl.status != "returning")


## The systems that can be fought over: every one that isn't a faction's capital.
## A front's war supply this campaign (the server's ledger.ts), as everyone may see it:
## {"factions": {faction: {"total", "sources", "capped", "perHour"}}, "history", "multipliers"}.
static func front_supply(planet_id: String) -> Dictionary:
	var f = war().get("ledger", {}).get("fronts", {}).get(planet_id)
	return f if f is Dictionary else {}


## A faction's underdog multiplier on war supply (1 when the server doesn't weigh it).
static func supply_multiplier(faction: String) -> float:
	return float(war().get("ledger", {}).get("multipliers", {}).get(faction, 1.0))


## One line per faction with war supply on a front: its total and where it came from, and what the
## arena and Frontier shares kept out. Empty when nobody has any yet.
static func supply_lines(planet_id: String) -> Array:
	var names: Dictionary = Net.catalog.get("ledger", {}).get("sources", {})
	var out := []
	var factions_in: Dictionary = front_supply(planet_id).get("factions", {})
	for f in faction_ids():
		if not factions_in.has(f):
			continue
		var s: Dictionary = factions_in[f]
		var parts := []
		for src in ["builder", "battle", "arena", "frontier"]:
			var n := float(s.get("sources", {}).get(src, 0))
			if n > 0:
				parts.append("%s %s" % [str(names.get(src, src)), _num(n)])
		var capped := 0.0
		for src in s.get("capped", {}):
			capped += float(s.capped[src])
		var line := "%s %s (%s)" % [faction_name(f), _num(float(s.get("total", 0))), ", ".join(parts) if not parts.is_empty() else "nothing yet"]
		if capped > 0:
			line += ", %s over the source shares" % _num(capped)
		out.append(line)
	return out


static func _num(x: float) -> String:
	return str(int(x)) if is_equal_approx(x, roundf(x)) else "%.1f" % x


static func contested_systems() -> Array:
	return war().get("systems", []).filter(func(s): return s.get("capitalOf") == null)


## The lanes from one system to another, as the systems on the way (both ends included), or [].
static func route(from: String, to: String) -> Array:
	var back := {from: ""}
	var queue := [from]
	while not queue.is_empty():
		var id: String = queue.pop_front()
		if id == to:
			var path := [id]
			while back[path[0]] != "":
				path.push_front(back[path[0]])
			return path
		for next in system(id).get("lanes", []):
			if not back.has(next):
				back[next] = id
				queue.append(next)
	return []


## Where a fleet set out from: an armada from its faction's capital, a Builder's fleet from the
## Builders' home system.
static func fleet_home(fl: Dictionary) -> String:
	if is_armada(fl):
		return str(factions().get(str(fl.faction), {}).get("capital", "comae"))
	for s in war().get("systems", []):
		if s.get("home", false):
			return s.id
	return "teal-prime"


# --- Outposts, goods and docks -------------------------------------------------------------------

## The outposts standing on a planet: sites whose `parent` is that planet (a contested world's
## sectors, or a Builder's home for sites from before the war).
static func outposts_on(planet_id: String) -> Array:
	if Net.state.is_empty():
		return []
	return Net.state.system.planets.filter(func(p): return p.get("kind", "") == "satellite" and p.get("parent", "") == planet_id)


## What a site is called on its planet's hologram, without its sector: "Fuel Depot".
static func short_site_name(site: Dictionary) -> String:
	var wp := planet(str(site.get("parent", "")))
	var sec := sector(wp, str(site.get("sector", "")))
	var n := str(site.get("name", site.get("id", "")))
	return n.trim_prefix(str(sec.name) + " ") if not sec.is_empty() else n


## Metal, ice, or an item from the catalog: "Fuel cell".
static func goods_name(id: String) -> String:
	if Net.catalog.get("items", {}).has(id):
		return Net.item_name(id)
	return id.capitalize()


## "20 Fuel cells", "1 Missile", "40 Metal".
static func amount_of(id: String, n: int) -> String:
	var name := goods_name(id)
	if n == 1 or not Net.catalog.get("items", {}).has(id) or name.ends_with("s") or name.ends_with("matter"):
		return "%d %s" % [n, name]
	return "%d %ss" % [n, name]


## "20 Fuel cells, 2 Missiles", or `empty` for nothing.
static func goods_list(goods: Dictionary, empty := "nothing") -> String:
	var parts := []
	for id in goods:
		if int(goods[id]) > 0:
			parts.append(amount_of(str(id), int(goods[id])))
	return ", ".join(parts) if not parts.is_empty() else empty


## A Builder's Carrier Dock on their home planet: the building record (finished or not), or {}.
static func dock_of(builder: String) -> Dictionary:
	if Net.state.is_empty():
		return {}
	for p in Net.state.system.planets:
		if p.get("owner") == builder and p.get("kind", "") != "satellite":
			for b in p.buildings:
				if b.type == "dock":
					return b
	return {}


static func dock_finished(builder: String) -> bool:
	var b := dock_of(builder)
	return not b.is_empty() and int(b.get("level", 1)) >= 1


## Why a Builder's finished Carrier Dock won't trade with you, or "" when it will: it only
## trades with pilots of its Builder's faction.
static func dock_problem(builder: String) -> String:
	var side := builder_faction(builder)
	if side == "":
		return "%s's Carrier Dock isn't trading yet: %s hasn't joined a faction." % [builder, builder]
	var mine := my_faction()
	if mine == "":
		return "%s's Carrier Dock trades with %s. Choose a faction to trade there." % [builder, the(side)]
	if mine != side:
		return "%s's Carrier Dock only trades with %s." % [builder, the(side)]
	return ""
