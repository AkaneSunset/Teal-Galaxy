extends RefCounted
## Textures on the game's surfaces: painted hull plating, tread plate, the Compact's armour, Ashen
## chitin, Luminar ceramic, Coma gunmetal... Every model keeps its own colours; a material listed in
## res://textures/surfaces.json also gets that set's maps (albedo detail, normal, ambient occlusion,
## roughness and metal, and a glow map where it lights up), laid on from the three axes in the
## model's own space so nothing needs UVs and a texture moves with its model. The sets are drawn by
## tools/textures/make_textures.py.
##   Surfaces.apply(material, "models", "teal")   # textures a material in place
##   Surfaces.shared(material, "compact", "navy") # a textured copy, one per group and name
##   Surfaces.maps("battle", "compact")           # the maps themselves, for a shader of your own

const TABLE := "res://textures/surfaces.json"
const MAP := "res://textures/%s/%s.png"

static var _table = null
static var _maps := {} # map path -> Texture2D, or null where the set has no such map
static var _shared := {} # "group/name" -> textured copy


## The table: {"sets": {set: metres per tile}, group: {name: set or {set, tile, glow}}}.
static func table() -> Dictionary:
	if _table == null:
		_table = {}
		var f := FileAccess.open(TABLE, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_table = parsed
	return _table


## What the material called `name` in `group` wears: {set, tile, glow?}, or {} for nothing.
static func entry(group: String, name: String) -> Dictionary:
	var t := table()
	var e = (t.get(group, {}) as Dictionary).get(name)
	if e == null:
		return {}
	var out: Dictionary = {"set": e} if e is String else (e as Dictionary).duplicate()
	if not out.has("tile"):
		out.tile = float((t.get("sets", {}) as Dictionary).get(out.set, 4.0))
	return out


static func _map(set_name: String, map: String) -> Texture2D:
	var path := MAP % [set_name, map]
	if not _maps.has(path):
		_maps[path] = load(path) if ResourceLoader.exists(path) else null
	return _maps[path]


## The maps listed for `name` in `group`, for a shader of your own (the battle units'):
## {albedo, orm, glow (null if the set has none), tile}, or {} if none are listed or the set's
## maps aren't there.
static func maps(group: String, name: String) -> Dictionary:
	var e := entry(group, name)
	if e.is_empty():
		return {}
	var set_name := str(e["set"])
	var albedo := _map(set_name, "albedo")
	if albedo == null:
		return {}
	return {"albedo": albedo, "orm": _map(set_name, "orm"), "glow": _map(set_name, "glow"), "tile": float(e["tile"])}


## Gives `m` the textures listed for `name` in `group`. False (and `m` untouched) if none are listed
## or the set's maps aren't there.
static func apply(m: BaseMaterial3D, group: String, name: String) -> bool:
	if m == null:
		return false
	var e := entry(group, name)
	if e.is_empty():
		return false
	var set_name: String = e.set
	var albedo := _map(set_name, "albedo")
	if albedo == null:
		return false
	var orm := _map(set_name, "orm")
	m.albedo_texture = albedo
	m.normal_enabled = true
	m.normal_texture = _map(set_name, "normal")
	# The orm map's green and blue scale the material's own roughness and metal; its greens sit
	# around 0.8, so lift the roughness to keep the surface as rough on average as it was.
	m.roughness_texture = orm
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.roughness = minf(1.0, m.roughness * 1.25)
	m.metallic_texture = orm
	m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	m.ao_enabled = true
	m.ao_texture = orm
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	var glow := _map(set_name, "glow")
	if glow:
		if not m.emission_enabled and e.has("glow"):
			m.emission_enabled = true
			m.emission = Color.html(str(e.glow))
			m.emission_energy_multiplier = 2.0
		if m.emission_enabled:
			m.emission_texture = glow
			m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE / maxf(0.1, float(e.tile))
	return true


## A textured copy of `m` (from a Blender model, say), made once for each group and name and then
## shared, so every model that uses the material draws with the same one. `m` itself if nothing is
## listed for it.
static func shared(m: Material, group: String, name: String) -> Material:
	if not m is BaseMaterial3D or name == "":
		return m
	var key := group + "/" + name
	if not _shared.has(key):
		var copy := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
		_shared[key] = copy if apply(copy, group, name) else null
	return _shared[key] if _shared[key] != null else m


## What a plain box of `size` is, for its textures in a walk-in room: a broad flat slab is floor (or
## ceiling), anything else wall, and a glowing one a light that stays plain ("").
static func box_surface(size: Vector3, glow: float) -> String:
	if glow > 0.0:
		return ""
	return "floor" if size.y <= 0.6 and minf(size.x, size.z) >= 1.5 else "wall"
