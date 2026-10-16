extends Node3D
## A satellite site in the Builder: the facility core in the middle of a free grid of tiles,
## with the defences the Builder has placed around it (turrets, walls, guard posts).
## The grid and its rules come from the server (sites.js); this only draws it and maps taps to tiles.

const BaseModels := preload("res://base_models.gd")
const TILE := 4.0 # metres per tile

var grid := 12
var core := Rect2i(4, 4, 4, 4)

var _key := "" # what's drawn now, so it is only rebuilt when the site changes
var _content: Node3D
var _highlight: MeshInstance3D
var _raid_light: OmniLight3D
var _label: Label3D
var _pieces := [] # copies of the site's pieces, for picking
var _obstacles := [] # boulders, ice and wreckage the Builder pays to clear
var _clock := 0.0


func _ready() -> void:
	_highlight = MeshInstance3D.new()
	var box := BoxMesh.new()
	_highlight.mesh = box
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.62, 0.15, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_highlight.material_override = m
	_highlight.visible = false
	add_child(_highlight)
	_raid_light = OmniLight3D.new()
	_raid_light.light_color = Color(0.9, 0.25, 0.22)
	_raid_light.omni_range = 26.0
	_raid_light.position.y = 12.0
	_raid_light.visible = false
	add_child(_raid_light)
	_label = Label3D.new()
	_label.font_size = 40
	_label.pixel_size = 0.07
	_label.outline_size = 10
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.position.y = 20.0
	add_child(_label)


func _process(delta: float) -> void:
	_clock += delta
	if _raid_light.visible:
		_raid_light.light_energy = 1.0 + 4.0 * (0.5 + 0.5 * sin(_clock * 6.0))


## Draws `site` (a satellite planet from the server). `turrets` is how many its security tier adds.
func show_site(site: Dictionary, label: String, raid: bool, tier_turrets: int) -> void:
	grid = int(site.get("grid", 12))
	var c: Dictionary = Net.catalog.get("sites", {}).get("core", {"w": 4, "h": 4})
	core = Rect2i((grid - int(c.w)) / 2, (grid - int(c.h)) / 2, int(c.w), int(c.h))
	_pieces = site.get("pieces", [])
	_obstacles = site.get("obstacles", [])
	var b: Dictionary = site.buildings[0] if site.buildings else {}
	var key := JSON.stringify([site.id, b.get("type", ""), tier_turrets, _pieces, _obstacles])
	if key != _key:
		_key = key
		_rebuild(b.get("type", ""), tier_turrets)
	_label.text = ("RAID!  " + label) if raid else label
	_label.modulate = Color(1, 0.55, 0.45) if raid else Color(1, 1, 1, 0.9)
	_raid_light.visible = raid


func _rebuild(type: String, tier_turrets: int) -> void:
	if _content:
		_content.queue_free()
	_content = Node3D.new()
	add_child(_content)
	var size := grid * TILE

	# The site: a platform of tiles on rock, with grid lines between tiles.
	var deck := MeshInstance3D.new()
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = Vector3(size + 2.0, 1.2, size + 2.0)
	deck.mesh = deck_mesh
	deck.position.y = -0.6
	deck.material_override = _flat(Color(0.2, 0.25, 0.35))
	_content.add_child(deck)
	var line_mat := _flat(Color(0.32, 0.42, 0.56))
	for i in grid + 1:
		var off := -size / 2.0 + i * TILE
		for along_x in [true, false]:
			var line := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(size, 0.06, 0.18) if along_x else Vector3(0.18, 0.06, size)
			line.mesh = lm
			line.position = Vector3(0, 0.03, off) if along_x else Vector3(off, 0.03, 0)
			line.material_override = line_mat
			_content.add_child(line)

	# The facility core: its pad and model, with any turrets its security tier adds.
	var centre := rect_centre(core)
	var core_node := Node3D.new()
	core_node.position = centre
	_content.add_child(core_node)
	var pad := BaseModels.pad()
	pad.scale = Vector3.ONE * (core.size.x * TILE / 19.0)
	core_node.add_child(pad)
	if type != "":
		var model := BaseModels.building(type)
		model.position.y = 1.0
		model.scale = Vector3.ONE * 0.8
		core_node.add_child(model)
	for t in tier_turrets:
		var tur := BaseModels.turret()
		var ang := TAU * (t + 0.5) / maxf(tier_turrets, 1) + 0.6
		tur.position = Vector3(cos(ang), 0.8, sin(ang)) * Vector3(6.6, 1, 6.6)
		core_node.add_child(tur)

	for p in _pieces:
		_content.add_child(_piece_model(p))
	for o in _obstacles:
		_content.add_child(_obstacle_model(o))


func _piece_model(p: Dictionary) -> Node3D:
	var def: Dictionary = Net.catalog.sites.pieces[p.type]
	var r := Rect2i(int(p.x), int(p.y), int(def.w), int(def.h))
	var n := Node3D.new()
	n.position = rect_centre(r)
	match p.type:
		"turret":
			BaseModels.Models.block(n, Vector3(7.0, 0.8, 7.0), "navy", Vector3(0, 0.4, 0), 0.3)
			var tur := BaseModels.turret()
			tur.position.y = 0.8
			tur.scale = Vector3.ONE * 1.4
			tur.rotation.y = atan2(n.position.x, n.position.z) + PI # guns face outward
			n.add_child(tur)
		"wall":
			BaseModels.Models.block(n, Vector3(3.8, 3.0, 3.8), "teal_light", Vector3(0, 1.5, 0), 0.4)
			BaseModels.Models.block(n, Vector3(4.0, 0.5, 4.0), "navy", Vector3(0, 3.1, 0), 0.15)
		"guardpost":
			BaseModels.Models.block(n, Vector3(6.4, 1.0, 6.4), "navy", Vector3(0, 0.5, 0), 0.3)
			BaseModels.Models.block(n, Vector3(3.6, 5.0, 3.6), "teal", Vector3(0, 3.5, 0), 0.5)
			BaseModels.Models.block(n, Vector3(4.6, 1.2, 4.6), "teal_light", Vector3(0, 6.6, 0), 0.3)
			BaseModels.Models.block(n, Vector3(3.0, 0.5, 0.3), "amber", Vector3(0, 6.6, -2.35), 0.1)
			BaseModels.Models.ball(n, 0.5, "amber", Vector3(0, 7.6, 0))
	return n


func _obstacle_model(o: Dictionary) -> Node3D:
	var r := obstacle_rect(o)
	var n := Node3D.new()
	n.position = rect_centre(r)
	var spin := float(int(o.id) * 47 % 360)
	match o.type:
		"boulder":
			var rock := BaseModels.boulder(3.4, int(o.id))
			rock.rotation_degrees.y = spin
			n.add_child(rock)
			var small := BaseModels.boulder(1.6, int(o.id) + 7)
			small.position = Vector3(2.4, 0, 1.8)
			n.add_child(small)
		"crystals":
			for i in 3:
				var c := Node3D.new()
				c.position = Vector3(cos(i * 2.1), 0, sin(i * 2.1)) * 0.7
				c.rotation_degrees = Vector3(12 - i * 9, spin + i * 50, 10 + i * 6)
				c.scale = Vector3.ONE * 1.7
				BaseModels.Models.drum(c, 0.45 - i * 0.08, 2.6 - i * 0.6, "ice", Vector3(0, 1.2 - i * 0.3, 0), Vector3.ZERO, 6)
				n.add_child(c)
		"wreck":
			BaseModels.Models.block(n, Vector3(6.0, 1.6, 2.6), "navy", Vector3(0, 0.6, 0), 0.4, Vector3(0, 0, 8))
			BaseModels.Models.block(n, Vector3(2.6, 1.2, 2.2), "teal", Vector3(1.6, 1.6, 0.2), 0.3, Vector3(14, 20, -10))
			BaseModels.Models.block(n, Vector3(0.4, 3.2, 0.4), "steel", Vector3(-1.8, 1.8, 0), 0.05, Vector3(0, 0, -28))
			BaseModels.Models.block(n, Vector3(1.2, 0.3, 0.8), "amber", Vector3(-0.6, 1.5, -1.0), 0.05, Vector3(0, 30, 0))
	return n


func obstacle_rect(o: Dictionary) -> Rect2i:
	var def: Dictionary = Net.catalog.sites.obstacles[o.type]
	return Rect2i(int(o.x), int(o.y), int(def.w), int(def.h))


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


## World position of the middle of a rectangle of tiles, on the deck.
func rect_centre(r: Rect2i) -> Vector3:
	var size := grid * TILE
	return Vector3(-size / 2.0 + (r.position.x + r.size.x / 2.0) * TILE, 0.0, -size / 2.0 + (r.position.y + r.size.y / 2.0) * TILE)


## The tile under a point on the ground, or (-1, -1) off the site.
func tile_at(world: Vector3) -> Vector2i:
	var size := grid * TILE
	var t := Vector2i(floori((world.x + size / 2.0) / TILE), floori((world.z + size / 2.0) / TILE))
	if t.x < 0 or t.y < 0 or t.x >= grid or t.y >= grid:
		return Vector2i(-1, -1)
	return t


## What sits on a tile: {"kind": "core"}, {"kind": "piece", "piece": {...}}, {"kind": "obstacle", ...}, or {}.
func what_at(t: Vector2i) -> Dictionary:
	if core.has_point(t):
		return {"kind": "core"}
	for p in _pieces:
		var def: Dictionary = Net.catalog.sites.pieces[p.type]
		if Rect2i(int(p.x), int(p.y), int(def.w), int(def.h)).has_point(t):
			return {"kind": "piece", "piece": p}
	for o in _obstacles:
		if obstacle_rect(o).has_point(t):
			return {"kind": "obstacle", "obstacle": o}
	return {}


## Highlights a rectangle of tiles (the selection), or nothing with an empty Rect2i.
func highlight(r: Rect2i) -> void:
	_highlight.visible = r.size != Vector2i.ZERO
	if _highlight.visible:
		(_highlight.mesh as BoxMesh).size = Vector3(r.size.x * TILE, 0.4, r.size.y * TILE)
		_highlight.position = rect_centre(r) + Vector3(0, 0.25, 0)
