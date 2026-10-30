extends RefCounted
## The Teal Prime system at roughly real scale, plus distance and speed formatting. Teal Prime is
## the home system, laid out here; the war map's other systems are made up the same way when a fleet
## carrier jumps to one (enter()), and then the star and planets below are that system's.
##
## Positions are metres from the star, kept as plain GDScript floats (64-bit) in [x, y, z] arrays.
## Godot's Vector3 is 32-bit, which can't place a ship precisely 60 million km from the star, so the
## explorer keeps the ship at the scene origin and draws everything relative to it.

const C := 299_792_458.0 # speed of light, m/s
const LS := C # one light second, m
const AU := 149_597_870_700.0

const STAR := {
	"id": "teal-prime", "name": "Teal Prime", "kind": "star",
	"pos": [0.0, 0.0, 0.0], "radius": 696_000_000.0, "color": Color(1.0, 0.85, 0.55),
}
const PLANETS := [
	{"id": "cinder", "name": "Cinder", "kind": "planet", "pos": [41_000_000_000.0, 2_000_000_000.0, 18_000_000_000.0],
		"radius": 2_400_000.0, "color": Color(0.75, 0.42, 0.28), "bands": false},
	{"id": "aster", "name": "Aster", "kind": "planet", "pos": [0.0, 0.0, -60_000_000_000.0],
		"radius": 6_000_000.0, "color": Color(0.15, 0.55, 0.55), "bands": false},
	{"id": "vesper", "name": "Vesper", "kind": "planet", "pos": [-150_000_000_000.0, -9_000_000_000.0, -120_000_000_000.0],
		"radius": 58_000_000.0, "color": Color(0.78, 0.66, 0.5), "bands": true},
	# A temperate world at 0.7 AU, between Aster and the Builders' outer homes.
	{"id": "halcyon", "name": "Halcyon", "kind": "planet", "pos": [-98_700_000_000.0, 4_000_000_000.0, 35_900_000_000.0],
		"radius": 5_600_000.0, "color": Color(0.32, 0.6, 0.44), "bands": false},
	# An ice giant at 1.65 AU, about Neptune's size.
	{"id": "morrow", "name": "Morrow", "kind": "planet", "pos": [212_000_000_000.0, -11_000_000_000.0, -126_000_000_000.0],
		"radius": 24_000_000.0, "color": Color(0.52, 0.44, 0.7), "bands": true},
]

# Cinder, Vesper, Halcyon and Morrow are the system's contested worlds in the faction war: no
# Builder lives there, but each has an orbital station (Cinder Orbital, ...) over the outposts
# Builders found in its sectors.
const ORBITAL_ALTITUDE := 1_400_000.0 # an orbital station's height above its planet, as Aster's High Port

# Places near Aster. The Spaceport orbits about 1,400 km above the surface.
const PORT_POS := [1_000_000.0, 2_000_000.0, -60_000_000_000.0 + 7_000_000.0]
const FIELD_POS := [1_000_000.0 + 12_000.0, 2_000_000.0 + 1_500.0, -60_000_000_000.0 + 7_000_000.0 - 6_000.0]
const SPAWN_POS := [1_000_000.0, 2_000_000.0 + 300.0, -60_000_000_000.0 + 7_000_000.0 + 4_000.0]

const PORT_NAME := "Aster High Port"
const FIELD_NAME := "Aster Ice Field"

# Every Builder's home planet has a High Port in orbit, placed off the planet like Aster's.
const STATION_OFFSET := Vector3(1_000_000.0, 2_000_000.0, 7_000_000.0)

## Builder home planets other than Aster (Brisa, Corvo, ...), added as Builders join.
static var homes: Array = []

## The system the ship is in (a war map system id), and its star and planets.
static var current := "teal-prime"
static var _star: Dictionary = STAR
static var _planets: Array = PLANETS
const STAR_COLOURS := [Color(1.0, 0.85, 0.55), Color(1.0, 0.68, 0.42), Color(0.78, 0.86, 1.0), Color(1.0, 0.95, 0.85)]


## Into a system: Teal Prime as laid out above, or another of the war map's, made up from its id
## (the same for everyone): a star, and `planets` ([{id, name}], the war planets there) on their
## orbits round it.
static func enter(id: String, system_name := "", planets: Array = []) -> void:
	current = id
	if id == "teal-prime":
		_star = STAR
		_planets = PLANETS
		return
	var h := absi(hash(id))
	_star = {"id": id, "name": system_name, "kind": "star", "pos": [0.0, 0.0, 0.0],
		"radius": 400_000_000.0 + (h % 5) * 150_000_000.0, "color": STAR_COLOURS[h % STAR_COLOURS.size()]}
	_planets = []
	for i in planets.size():
		var p: Dictionary = planets[i]
		var ph := absi(hash(str(p.id)))
		var a := fposmod(ph * 0.37, TAU)
		var r := (45.0 + i * 55.0) * 1_000_000_000.0
		_planets.append({"id": str(p.id), "name": str(p.name), "kind": "planet", "pos": [cos(a) * r, sin(i * 1.3) * 3_000_000_000.0, sin(a) * r],
			"radius": 3_000_000.0 + (ph % 9) * 2_500_000.0, "color": Color.from_hsv(fposmod(ph * 0.618034, 1.0), 0.45, 0.62), "bands": ph % 4 == 0})


## Whether the ship is in the home system (Aster, its High Port and ice field, the Builders' homes).
static func home() -> bool:
	return current == "teal-prime"


static func star() -> Dictionary:
	return _star


## The planets of the system the ship is in (in Teal Prime, with the Builders' homes).
static func planets() -> Array:
	return _planets + homes if home() else _planets.duplicate()


## A Builder home planet other than Aster: the `index`th one founded gets its own orbit around the star.
static func home_planet(id: String, planet_name: String, index: int) -> Dictionary:
	var a := 1.1 + index * 2.4
	var r := (90.0 + index * 35.0) * 1_000_000_000.0
	var h := absi(hash(id))
	return {"id": id, "name": planet_name, "kind": "planet", "pos": [cos(a) * r, sin(index * 1.7) * 3_000_000_000.0, sin(a) * r],
		"radius": 4_000_000.0 + (h % 4) * 1_000_000.0, "color": Color.from_hsv(fposmod(h * 0.618034, 1.0), 0.45, 0.62), "bands": false}


## A planet by id in the system the ship is in (in Teal Prime: Aster, a contested world or one of
## the homes), else an empty Dictionary.
static func builder_planet(id: String) -> Dictionary:
	for p in planets():
		if p.id == id:
			return p
	return {}


## Where a Builder planet's High Port orbits. Aster's is PORT_POS.
static func station_pos(planet_id: String) -> Array:
	if planet_id == "aster":
		return PORT_POS
	var p := builder_planet(planet_id)
	if p.is_empty():
		return PORT_POS
	# On the sunward side, like Aster's, so the station is lit with the planet's day side behind it.
	var sunward := -Vector3(p.pos[0], p.pos[1], p.pos[2]).normalized()
	var side := sunward.cross(Vector3.UP).normalized()
	return offset(p.pos, sunward * STATION_OFFSET.z + Vector3.UP * STATION_OFFSET.y + side * STATION_OFFSET.x)


static func station_name(planet_name: String) -> String:
	return "%s High Port" % planet_name


## Where a contested planet's orbital station is: off the sunward side like a High Port, but at a
## height over the surface, since these worlds run from Cinder's size to Vesper's gas giant.
static func orbital_pos(planet_id: String) -> Array:
	var p := builder_planet(planet_id)
	if p.is_empty():
		return PORT_POS
	var sunward := -Vector3(p.pos[0], p.pos[1], p.pos[2]).normalized()
	var side := sunward.cross(Vector3.UP).normalized()
	var dir := (sunward * STATION_OFFSET.z + Vector3.UP * STATION_OFFSET.y + side * STATION_OFFSET.x).normalized()
	return offset(p.pos, dir * (p.radius + ORBITAL_ALTITUDE))


static func orbital_name(planet_name: String) -> String:
	return "%s Orbital" % planet_name


static func bodies() -> Array:
	return [_star] + planets()


static func diff(a: Array, b: Array) -> Vector3:
	## a - b as a 32-bit vector. Only precise when the result is small, or used as a direction.
	return Vector3(a[0] - b[0], a[1] - b[1], a[2] - b[2])


static func distance(a: Array, b: Array) -> float:
	var dx: float = a[0] - b[0]
	var dy: float = a[1] - b[1]
	var dz: float = a[2] - b[2]
	return sqrt(dx * dx + dy * dy + dz * dz)


static func offset(a: Array, v: Vector3) -> Array:
	return [a[0] + v.x, a[1] + v.y, a[2] + v.z]


static func format_distance(m: float) -> String:
	if m < 1_000.0:
		return "%d m" % m
	if m < 1_000_000.0:
		return "%.1f km" % (m / 1_000.0)
	if m < 0.1 * LS:
		return "%.1f Mm" % (m / 1_000_000.0)
	if m < 0.1 * AU:
		return "%.1f ls" % (m / LS)
	return "%.2f AU" % (m / AU)


static func format_speed(mps: float) -> String:
	if mps < 1_000.0:
		return "%d m/s" % mps
	if mps < 0.1 * C:
		return "%.1f km/s" % (mps / 1_000.0)
	return "%.2f c" % (mps / C)


static func format_time(seconds: float) -> String:
	if seconds < 0 or seconds > 359_999:
		return "--:--"
	var s := int(seconds)
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]
