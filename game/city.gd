extends "res://place.gd"
## A city on foot, and the city builder. Cities stand on the factions' capital worlds (laid out by
## the game's admins) and on terraformed Frontier worlds (built by their Founder): see the server's
## cities.ts. The city is a square grid of 10 m cells, 1.2 km on a side; every piece (a road, a
## plaza, a habitat block, a wall...) covers a block of cells, turned a quarter at a time.
##
## You arrive on foot at the shuttle stop on the city's south edge; its console takes you back up.
## If you may build here, the CITY PLANNING console beside it (or B, anywhere in the city) opens the
## builder: a camera high over the city, the pieces down the right, and the mouse to lay them out.
##   Left click       place the chosen piece (hold and drag to lay roads and walls), or pick one
##   R                turn the piece (or the picked one) a quarter
##   M                move the picked piece: it follows the mouse until you click
##   Delete / X       take the picked piece up
##   Right click      put the chosen piece down / let go of the picked one
##   Ctrl+Z           undo the last placement, move, turn or take-up (a dragged road is one step)
##   W A S D, right drag   pan      Q / E   turn the view      Wheel   zoom      B / Esc   leave
## On a colony, a colony building (habitat, precinct, mine...) uses one the colony has in store, or
## builds a new one, paid for like on the Frontier screen's Colony page. Taking one up puts it back
## in store. A city whose colony collapsed and went to auction stands as ruins.
##
## Style: every city is built in its faction's look (the homeworld's owner, or the colony Founder's
## faction). A piece's model is res://city/<faction>/<piece>.glb, made in Blender by
## tools/blender/city_models.py, authored to its footprint with its front toward -Z. A piece with no
## model for that faction yet uses the shared stand-in below.
##
## Drawing: pieces are not nodes. Every part of every model is drawn as one MultiMesh per piece type
## per 200 m chunk of the city, so a full city of 4,000 pieces is a few hundred draw calls, chunks
## off screen are culled, and small details stop drawing from far away.
## Zones: a housing zone (low or high density) is dragged out like a road, a lot at a time. Each lot
## is drawn as one of the faction's looks for that density (res://city/<faction>/zone_low_<n>.glb),
## picked from the piece's id, so a zoned street is a mix of homes and everyone sees the same one.
## The pieces themselves come from the server on request (city_get), not in every state: each state
## only says when each city last changed.

signal leave_city # the shuttle back up

const BaseModels := preload("res://base_models.gd")
const Terrain := preload("res://terrain.gd")

const ARRIVAL_Z := 640.0 # the shuttle stop, just south of the grid
const GROUND_PIECES := ["road", "plaza", "park", "pad"] # flat: you walk over them
const GROUP_ORDER := ["Ground", "Zones", "Civic", "Housing", "Industry", "Defence"]
const DRAG_PIECES := ["road", "wall", "zone_low", "zone_high"] # hold the button and drag to lay these
const STYLE_PATH := "res://city/%s/%s.glb"
const CHUNK := 20 # cells on a side of a drawing chunk
const SMALL_PART := 2.5 # metres: parts no bigger than this are details...
const DETAIL_RANGE := 320.0 # ...drawn only this close
const UNDO_STEPS := 100

var can_build := false # set from the server's rules (see _may_build)
var building := false # the builder is up

var _cell := 10.0
var _half := 60
var _catalog := {} # piece type -> {name, w, d, group, where}
var _data := {} # this city as the server last sent it: {pieces, updated}
var _asked := -1 # the stamp last asked for
var _pieces := {} # piece id -> {"key", "type", "chunk", "xf", "solid"}
var _parts := {} # piece type -> [{mesh, material, xf, small}]: its model, taken apart for drawing
var _scenes := {} # glb path -> PackedScene (or null: none for this faction yet)
var _looks := {} # zone type -> how many looks the faction has for it
var _batches := {} # "type@chunk" -> Node3D holding its MultiMeshInstance3Ds
var _city_root: Node3D
var _grid: MeshInstance3D
var _paint := "teal"
var _style := "" # the faction whose look the city is built in

# The builder.
var _cam: Camera3D
var _cam_target := Vector3.ZERO
var _cam_yaw := 0.0
var _cam_dist := 420.0
var _dragging_view := false
var _ui: CanvasLayer
var _list: VBoxContainer
var _info: Label
var _status: Label
var _choose := "" # the piece type to place
var _rot := 0
var _picked := -1 # a placed piece's id
var _moving := false
var _ghost: MeshInstance3D
var _ghost_ok := StandardMaterial3D.new()
var _ghost_bad := StandardMaterial3D.new()
var _hover := Vector2i(0, 0)
var _laying := false # left button held with a road or wall chosen
var _last_laid := Vector2i(999999, 999999)
var _clear_armed := 0.0
var _copy_from: OptionButton
var _tip: Label # beside the mouse: what the piece is, costs and adds, or why it can't go there
var _perf: Label
var _perf_wait := 0.0
var _select: MeshInstance3D # over the picked piece
var _undo := [] # [{"stroke", "ops": [{"op": "placed"|"moved"|"removed", ...}]}], newest last
var _pending := {} # tag -> the undo op its city_result confirms
var _stroke := 0 # one press of the mouse: a dragged road undoes as one
var _tags := 0


func _build() -> void:
	var cat: Dictionary = Net.catalog.get("cities", {})
	_cell = float(cat.get("cell", 10))
	_half = int(cat.get("cells", 120)) / 2
	_catalog = cat.get("pieces", {})
	var homeworld := not WarInfo.planet(planet_id).is_empty()
	var side = WarInfo.planet(planet_id).get("owner") if homeworld else _colony().get("faction")
	if side != null and str(side) != "":
		_style = str(side)
		_paint = Models.paint(WarInfo.faction_color(_style), false)
	place_name = "The city on %s" % _world_name()
	_build_world()
	Net.state_changed.connect(_on_state)
	Net.message.connect(_on_message)
	Net.server_error.connect(_on_error)
	_build_builder_ui()
	_fetch()


func _exit_tree() -> void:
	if Net.state_changed.is_connected(_on_state):
		Net.state_changed.disconnect(_on_state)
	if Net.message.is_connected(_on_message):
		Net.message.disconnect(_on_message)
	if Net.server_error.is_connected(_on_error):
		Net.server_error.disconnect(_on_error)


func _location() -> String:
	return "builder (B)" if can_build and not building else ""


func _leave_hint() -> String:
	return "To leave, take the shuttle back up from the stop at the city's south edge."


func _seated_text() -> String:
	return place_name


## The world's name: a homeworld of the war, or a planet of a Frontier cluster.
func _world_name() -> String:
	var wp := WarInfo.planet(planet_id)
	if not wp.is_empty():
		return str(wp.get("name", planet_id))
	for c in Net.state.get("frontier", {}).get("clusters", {}).values():
		for sys in c.get("systems", []):
			for p in sys.get("planets", []):
				if str(p.get("id", "")) == planet_id:
					return str(p.get("name", planet_id))
	return planet_id


## The Frontier cluster whose colony stands here ({} on a homeworld, or once the colony is gone).
func _colony() -> Dictionary:
	for c in Net.state.get("frontier", {}).get("clusters", {}).values():
		var col = c.get("colony")
		if col is Dictionary and str(col.get("planet", "")) == planet_id:
			return c
	return {}


## Whether you may build here: an admin on a homeworld, the Founder on their living colony.
func _may_build() -> bool:
	if not WarInfo.planet(planet_id).is_empty():
		return Net.admin
	var c := _colony()
	return not c.is_empty() and str(c.get("owner", "")) == Net.my_name and c.colony.get("collapseAt") == null


func _city() -> Dictionary:
	return _data


## Asks the server for this city when the state says it changed since we last asked.
func _fetch() -> void:
	var stamp := int(Net.state.get("cities", {}).get(planet_id, 0))
	if stamp == _asked:
		return
	_asked = stamp
	Net.send({"type": "city_get", "planet": planet_id})


func _ruins() -> bool:
	return WarInfo.planet(planet_id).is_empty() and _colony().is_empty()


# --- The world --------------------------------------------------------------------------------

func _build_world() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.16, 0.27, 0.45)
	sky_mat.sky_horizon_color = Color(0.62, 0.7, 0.8)
	sky_mat.ground_horizon_color = Color(0.62, 0.7, 0.8)
	sky_mat.ground_bottom_color = Color(0.22, 0.24, 0.28)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.68, 0.85)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.66, 0.72, 0.82)
	env.fog_density = 0.0006
	env.fog_sky_affect = 0.5
	env.glow_enabled = true
	env.glow_intensity = 0.4
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 400.0
	add_child(sun)

	var span := _half * _cell
	var terrain := Terrain.new()
	terrain.position.y = -0.4
	add_child(terrain)
	terrain.generate(planet_id, span + 40.0)
	# Something to stand on everywhere in the city.
	_box(self, Vector3(span * 2.0 + 120.0, 0.4, span * 2.0 + 120.0), Vector3(0, -0.2, 0), Color(0, 0, 0), true).visible = false
	_city_root = Node3D.new()
	add_child(_city_root)

	# The shuttle stop, south of the grid, looking north up into the city.
	var stop := Vector3(0, 0, ARRIVAL_Z)
	var pad := BaseModels.landing_pad(6.0, true)
	pad.position = stop
	add_child(pad)
	_arrival = Marker3D.new()
	_arrival.position = stop + Vector3(0, 0.1, -3.0)
	add_child(_arrival)
	var at := stop + Vector3(5.0, 0, -4.0)
	_console(self, at, Vector3(-1, 0, 0), "SHUTTLE", "Back up to orbit\nPress F.", 1.6)
	_use(self, at + Vector3(-0.7, 1.0, 0), func(): return "Press %s for the shuttle back up" % _key(), func(): leave_city.emit())
	_light(self, at + Vector3(0, 3.0, 0), Color(0.85, 0.92, 1.0), 0.8, 6.0)
	var plan := stop + Vector3(-5.0, 0, -4.0)
	_console(self, plan, Vector3(1, 0, 0), "CITY PLANNING", "Lay out the city\nPress F.", 1.6)
	_use(self, plan + Vector3(0.7, 1.0, 0), _plan_prompt, _plan_use)
	_light(self, plan + Vector3(0, 3.0, 0), Color(0.85, 0.92, 1.0), 0.8, 6.0)


func _plan_prompt() -> String:
	if _may_build():
		return "Press %s to open the city builder" % _key()
	if _ruins():
		return "City planning: these are ruins now"
	return "City planning: only the Founder builds here" if WarInfo.planet(planet_id).is_empty() else "City planning: the game's admins lay out the homeworlds"


func _plan_use() -> void:
	if _may_build():
		set_building(true)


func _on_state(_s: Dictionary) -> void:
	can_build = _may_build()
	if building and not can_build:
		set_building(false)
	_fetch()
	_refresh_city() # a colony may have fallen to ruins
	if building:
		_refresh_list()


func _on_message(msg: Dictionary) -> void:
	if str(msg.get("planet", "")) != planet_id:
		return
	match str(msg.get("type", "")):
		"city":
			_data = {"pieces": msg.get("pieces", []), "updated": int(msg.get("updated", 0))}
			_refresh_city()
			if building:
				_refresh_list()
		"city_result":
			_confirm(str(msg.get("tag", "")), msg)
			if msg.get("built", false):
				_set_status("Built and placed.")
			elif str(msg.action) == "city_place":
				_set_status("")


func _on_error(reason: String) -> void:
	if building:
		_set_status(reason)


## Every piece where the server has it: new ones added, moved or turned ones redone, gone ones
## taken away; then each drawing batch they touched is redrawn.
func _refresh_city() -> void:
	var want := {}
	var dirty := {}
	var ruins := _ruins()
	for p in _city().get("pieces", []):
		var id := int(p.id)
		var key := "%s:%d:%d:%d:%s" % [p.type, int(p.x), int(p.z), int(p.rot), ruins]
		want[id] = true
		var have: Dictionary = _pieces.get(id, {})
		if have.get("key", "") == key:
			continue
		if not have.is_empty():
			dirty[have.batch] = true
		_drop_piece(id)
		var made := _make_piece(p, key, ruins)
		_pieces[id] = made
		dirty[made.batch] = true
	for id in _pieces.keys():
		if not want.has(id):
			dirty[_pieces[id].batch] = true
			_drop_piece(id)
	if not dirty.is_empty():
		var by_batch := {}
		for id in _pieces:
			var b: String = _pieces[id].batch
			if dirty.has(b):
				if not by_batch.has(b):
					by_batch[b] = []
				by_batch[b].append(_pieces[id].xf)
		for b in dirty:
			_draw_batch(str(b), by_batch.get(b, []))
	_mark_picked()


func _drop_piece(id: int) -> void:
	var have: Dictionary = _pieces.get(id, {})
	if have.is_empty():
		return
	if have.solid:
		(have.solid as Node).queue_free()
	_pieces.erase(id)


## Redraws one batch (one look in one chunk): a MultiMesh per part of the look's model.
func _draw_batch(batch: String, xfs: Array) -> void:
	var old: Node = _batches.get(batch)
	if old:
		old.queue_free()
		_batches.erase(batch)
	if xfs.is_empty():
		return
	var holder := Node3D.new()
	holder.name = batch.replace("@", "_").replace(",", "_").replace("-", "m")
	_city_root.add_child(holder)
	_batches[batch] = holder
	for part in _parts_of(batch.get_slice("@", 0)):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part.mesh
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, (xfs[i] as Transform3D) * (part.xf as Transform3D))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if part.material:
			mmi.material_override = part.material
		if part.small:
			mmi.visibility_range_end = DETAIL_RANGE
			mmi.visibility_range_end_margin = 40.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mmi)


## A look's model taken apart: every mesh in it, with its material and where it sits.
func _parts_of(look: String) -> Array:
	if _parts.has(look):
		return _parts[look]
	var info: Dictionary = _catalog.get(_type_of(look), {"w": 1, "d": 1})
	var model := _model(look, Vector2(float(info.w), float(info.d)) * _cell)
	var out := []
	_collect(model, Transform3D.IDENTITY, out)
	model.free()
	_parts[look] = out
	return out


## How a piece is drawn: its type, or for a zone lot one of the faction's looks for it
## ("zone_low_3"), always the same one for the same piece.
func _look(type: String, id: int) -> String:
	if not type.begins_with("zone_"):
		return type
	if not _looks.has(type):
		var count := 0
		while _style != "" and ResourceLoader.exists(STYLE_PATH % [_style, "%s_%d" % [type, count + 1]]):
			count += 1
		_looks[type] = count
	var n: int = _looks[type]
	return type if n == 0 else "%s_%d" % [type, 1 + ((id * 2654435761) >> 8) % n]


## The piece type a look belongs to.
func _type_of(look: String) -> String:
	return look if _catalog.has(look) else look.substr(0, look.rfind("_"))


func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	var here := xf * (n as Node3D).transform if n is Node3D else xf
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mi := n as MeshInstance3D
		var mat: Material = mi.material_override
		if mat == null and mi.mesh.get_surface_count() == 1:
			mat = mi.get_surface_override_material(0)
		var box := here * mi.mesh.get_aabb()
		# A Blender model's small parts come joined in one mesh called "detail".
		var small := box.get_longest_axis_size() <= SMALL_PART or str(mi.name).begins_with("detail")
		out.append({"mesh": mi.mesh, "material": mat, "xf": here, "small": small})
	for c in n.get_children():
		_collect(c, here, out)


## A piece's width and depth in cells, as turned.
func _size(type: String, rot: int) -> Vector2i:
	var info: Dictionary = _catalog.get(type, {"w": 1, "d": 1})
	return Vector2i(int(info.d), int(info.w)) if rot % 2 == 1 else Vector2i(int(info.w), int(info.d))


## The middle of a piece standing at cell (x, z), on the ground.
func _centre(type: String, x: int, z: int, rot: int) -> Vector3:
	var s := _size(type, rot)
	return Vector3((x + s.x * 0.5) * _cell, 0, (z + s.y * 0.5) * _cell)


## A piece's place in the city: where it draws (its transform and batch) and what you bump into.
func _make_piece(p: Dictionary, key: String, ruins: bool) -> Dictionary:
	var type := str(p.type)
	var rot := int(p.rot)
	var x := int(p.x)
	var z := int(p.z)
	var centre := _centre(type, x, z, rot)
	var basis := Basis(Vector3.UP, rot * PI * 0.5)
	if ruins and not type in GROUND_PIECES:
		basis = basis * Basis.from_scale(Vector3(1.0, 0.3, 1.0)) # tumbled down
	var batch := "%s@%d,%d" % [_look(type, int(p.id)), floori(float(x) / CHUNK), floori(float(z) / CHUNK)]
	var solid: Node3D = null
	if not type in GROUND_PIECES:
		var s := _size(type, rot)
		solid = _box(self, Vector3(s.x * _cell * 0.86, 30.0, s.y * _cell * 0.86), centre + Vector3(0, 15.0, 0), Color(0, 0, 0), true)
		solid.visible = false
	return {"key": key, "type": type, "batch": batch, "xf": Transform3D(basis, centre), "solid": solid}


## The faction's Blender model of a piece, or null if it has none yet.
func _style_model(type: String) -> Node3D:
	if _style == "":
		return null
	var path := STYLE_PATH % [_style, type]
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	var scene: PackedScene = _scenes[path]
	return scene.instantiate() as Node3D if scene else null


## A piece's model, `foot` metres wide and deep (before turning), its origin on the ground: the
## faction's own, or the shared stand-in.
func _model(look: String, foot: Vector2) -> Node3D:
	var own := _style_model(look)
	if own:
		return own # authored to its footprint in Blender
	var type := _type_of(look)
	var n := Node3D.new()
	match type:
		"zone_low":
			Models.block(n, Vector3(foot.x * 0.98, 0.2, foot.y * 0.98), "deck", Vector3(0, 0.1, 0), 0.0)
			for sx in [-1.0, 1.0]:
				Models.block(n, Vector3(foot.x * 0.36, 5.0, foot.y * 0.6), "navy", Vector3(sx * foot.x * 0.22, 2.7, 0), 0.3)
				Models.block(n, Vector3(foot.x * 0.38, 0.5, foot.y * 0.62), _paint, Vector3(sx * foot.x * 0.22, 5.4, 0), 0.1)
			return n
		"zone_high":
			var zw := foot.x * 0.8
			Models.block(n, Vector3(zw, 56.0, zw), "navy", Vector3(0, 28.0, 0), 0.4)
			for f in 9:
				Models.block(n, Vector3(zw + 0.2, 1.2, zw + 0.2), "window", Vector3(0, 4.0 + f * 6.0, 0), 0.0)
			Models.block(n, Vector3(zw + 0.6, 2.0, zw + 0.6), _paint, Vector3(0, 57.0, 0), 0.3)
			return n
		"road":
			Models.block(n, Vector3(foot.x, 0.3, foot.y), "dark", Vector3(0, 0.15, 0), 0.0)
			Models.block(n, Vector3(0.35, 0.05, foot.y * 0.4), "deck", Vector3(0, 0.32, 0), 0.0)
			return n
		"plaza":
			Models.block(n, Vector3(foot.x, 0.35, foot.y), "deck", Vector3(0, 0.18, 0), 0.05)
			Models.drum(n, 1.6, 0.9, "teal", Vector3(0, 0.8, 0), Vector3.ZERO, 12)
			Models.ball(n, 0.6, "amber", Vector3(0, 1.6, 0))
			return n
		"park":
			Models.block(n, Vector3(foot.x, 0.3, foot.y), "paint:#3c6e48", Vector3(0, 0.15, 0), 0.05)
			for i in 5:
				var a := i * TAU / 5.0 + 0.4
				var at := Vector3(cos(a), 0, sin(a)) * foot.x * 0.3
				Models.drum(n, 0.35, 3.0, "dark", at + Vector3(0, 1.8, 0), Vector3.ZERO, 8)
				Models.ball(n, 2.4, "paint:#2f8a4a", at + Vector3(0, 4.6, 0))
			return n
		"tower", "highrise":
			var h := 38.0 if type == "tower" else 92.0
			var w := foot.x * 0.78
			Models.block(n, Vector3(w, h, w), "navy", Vector3(0, h * 0.5, 0), 0.4)
			var floors := int(h / 6.0)
			for f in floors:
				Models.block(n, Vector3(w + 0.2, 1.2, w + 0.2), "window", Vector3(0, 3.5 + f * 6.0, 0), 0.0)
			Models.block(n, Vector3(w + 0.6, 2.0, w + 0.6), _paint, Vector3(0, h + 1.0, 0), 0.3)
			Models.ball(n, 0.7, "amber", Vector3(0, h + 3.0, 0))
			return n
		"precinct":
			Models.block(n, Vector3(foot.x * 0.8, 9.0, foot.y * 0.8), "teal", Vector3(0, 4.5, 0), 0.4)
			Models.block(n, Vector3(foot.x * 0.84, 1.2, foot.y * 0.84), "navy", Vector3(0, 9.6, 0), 0.2)
			Models.ball(n, 1.0, "paint:#3d7bff", Vector3(0, 11.0, 0))
			return n
		"clinic":
			Models.block(n, Vector3(foot.x * 0.8, 10.0, foot.y * 0.8), "teal_light", Vector3(0, 5.0, 0), 0.4)
			Models.block(n, Vector3(8.0, 0.6, 2.4), "paint:#e04848", Vector3(0, 10.3, 0), 0.05)
			Models.block(n, Vector3(2.4, 0.6, 8.0), "paint:#e04848", Vector3(0, 10.3, 0), 0.05)
			return n
		"wall":
			n.add_child(BaseModels.wall(foot.x))
			return n
		"pad":
			n.add_child(BaseModels.landing_pad(foot.x * 0.45, true))
			return n
	var m: Node3D
	match type:
		"hall":
			m = BaseModels.command_center_at(5)
		"wall_tower":
			m = BaseModels.wall_tower()
		"turret":
			m = BaseModels.turret()
		"mine":
			m = BaseModels.building("extractor")
		"smelter":
			m = BaseModels.building("refinery")
		"works":
			m = BaseModels.building("lab")
		"reactor":
			m = BaseModels.building("power")
		"shipyard":
			m = BaseModels.building("foundry")
		_:
			m = BaseModels.building(type)
	n.add_child(m)
	_fit(m, foot)
	return n


## Scales a model so its widest side fills most of its footprint.
func _fit(m: Node3D, foot: Vector2) -> void:
	var box := _bounds(m, Transform3D.IDENTITY)
	var widest := maxf(box.size.x, box.size.z)
	if widest < 0.01:
		return
	var k := minf(foot.x, foot.y) * 0.9 / widest
	m.scale = Vector3.ONE * k
	m.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z) * k


func _bounds(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var here := xf * (n as Node3D).transform if n is Node3D else xf
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out = here * (n as MeshInstance3D).mesh.get_aabb()
		first = false
	for c in n.get_children():
		var b := _bounds(c, here)
		if b.size == Vector3.ZERO:
			continue
		out = b if first else out.merge(b)
		first = false
	return out


# --- The builder ------------------------------------------------------------------------------

func set_building(on: bool) -> void:
	if on and not _may_build():
		return
	building = on
	_ui.visible = on
	_grid.visible = on
	_ghost.visible = false
	set_menu_open(on)
	if on:
		var here := _player.global_position if _player else Vector3.ZERO
		_cam_target = Vector3(clampf(here.x, -_half * _cell, _half * _cell), 0, clampf(here.z, -_half * _cell, _half * _cell))
		_cam.make_current()
		_place_cam()
		_refresh_list()
		if controls:
			controls.release_mouse()
	else:
		_choose = ""
		_picked = -1
		_moving = false
		_laying = false
		_tip.visible = false
		_camera.make_current()
		_mark_picked()


func _build_builder_ui() -> void:
	can_build = _may_build()
	_cam = Camera3D.new()
	_cam.far = 6000.0
	add_child(_cam)
	_ghost_ok.albedo_color = Color(0.3, 1.0, 0.55, 0.35)
	_ghost_bad.albedo_color = Color(1.0, 0.3, 0.3, 0.35)
	for m in [_ghost_ok, _ghost_bad]:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost = MeshInstance3D.new()
	_ghost.mesh = BoxMesh.new()
	_ghost.visible = false
	add_child(_ghost)
	_select = MeshInstance3D.new()
	_select.mesh = BoxMesh.new()
	var sel := StandardMaterial3D.new()
	sel.albedo_color = Color(0.45, 0.95, 1.0, 0.3)
	sel.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sel.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sel.no_depth_test = true # seen through the buildings around it
	_select.material_override = sel
	_select.visible = false
	add_child(_select)
	_grid = _grid_mesh()
	_grid.visible = false
	add_child(_grid)

	_ui = CanvasLayer.new()
	_ui.layer = 7
	_ui.visible = false
	add_child(_ui)
	var side := PanelContainer.new()
	side.anchor_left = 1.0
	side.anchor_right = 1.0
	side.anchor_bottom = 1.0
	side.offset_left = -330.0
	side.offset_top = 12.0
	side.offset_right = -12.0
	side.offset_bottom = -12.0
	_ui.add_child(side)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	side.add_child(col)
	var title := Label.new()
	title.text = "CITY BUILDER · %s" % _world_name()
	title.add_theme_font_size_override("font_size", 20)
	col.add_child(title)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	col.add_child(_info)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var row := HBoxContainer.new()
	col.add_child(row)
	for e in [["Turn (R)", _turn], ["Move (M)", _start_move], ["Take up (X)", _take_up], ["Undo", _undo_last]]:
		var b := Button.new()
		b.text = e[0]
		b.pressed.connect(e[1])
		row.add_child(b)
	if Net.admin and not WarInfo.planet(planet_id).is_empty():
		var copy_row := HBoxContainer.new()
		col.add_child(copy_row)
		_copy_from = OptionButton.new()
		for wp in WarInfo.war().get("planets", []):
			if wp.get("capital", false) and str(wp.id) != planet_id:
				_copy_from.add_item(str(wp.name))
				_copy_from.set_item_metadata(_copy_from.item_count - 1, str(wp.id))
		copy_row.add_child(_copy_from)
		var copy := Button.new()
		copy.text = "Copy city from"
		copy.pressed.connect(_copy_city)
		copy_row.add_child(copy)
		copy_row.move_child(copy, 0)
	var clear := Button.new()
	clear.text = "Clear the whole city"
	clear.pressed.connect(_clear_city)
	col.add_child(clear)
	var done := Button.new()
	done.text = "Leave the builder (B)"
	done.pressed.connect(set_building.bind(false))
	col.add_child(done)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color(1.0, 0.8, 0.45))
	col.add_child(_status)
	_perf = Label.new()
	_perf.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	_perf.add_theme_font_size_override("font_size", 12)
	col.add_child(_perf)
	_tip = Label.new()
	_tip.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_tip.add_theme_constant_override("outline_size", 5)
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	_ui.add_child(_tip)
	var help := Label.new()
	help.text = "Click: place or pick   Drag: lay roads and walls   R turn   M move   X take up   Ctrl+Z undo   Right click: let go\nW A S D or right drag: pan   Q / E: turn the view   Wheel: zoom   B or Esc: leave"
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.offset_left = 16.0
	help.offset_top = -56.0
	help.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	help.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	help.add_theme_constant_override("outline_size", 4)
	_ui.add_child(help)


## The cell lines over the city, shown while building.
func _grid_mesh() -> MeshInstance3D:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var span := _half * _cell
	for i in range(-_half, _half + 1):
		var at := i * _cell
		im.surface_add_vertex(Vector3(at, 0.45, -span))
		im.surface_add_vertex(Vector3(at, 0.45, span))
		im.surface_add_vertex(Vector3(-span, 0.45, at))
		im.surface_add_vertex(Vector3(span, 0.45, at))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 1.0, 0.95, 0.22)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	return mi


## The pieces down the side, by group; on a colony, what each colony building has in store or costs.
func _refresh_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	var colony := _colony()
	var homeworld := colony.is_empty()
	var store := {}
	var tier := 0
	if not homeworld:
		store = colony.colony.get("buildings", {})
		tier = int(colony.colony.get("tier", 0))
		_info.text = "Population %d · tier %d · %s credits" % [int(colony.colony.get("pop", 0)), tier, _credits()]
	else:
		_info.text = "A homeworld city: every piece is scenery. %d pieces placed." % _city().get("pieces", []).size()
	var placed := {}
	for p in _city().get("pieces", []):
		placed[p.type] = int(placed.get(p.type, 0)) + 1
	var fb: Dictionary = Net.catalog.get("frontier", {}).get("buildings", {})
	for group in GROUP_ORDER:
		var head := Label.new()
		head.text = group
		head.add_theme_color_override("font_color", Color(0.6, 1.0, 0.9))
		_list.add_child(head)
		for type in _catalog:
			var info: Dictionary = _catalog[type]
			if str(info.group) != group or (not homeworld and str(info.where) == "home"):
				continue
			var b := Button.new()
			b.toggle_mode = true
			b.button_pressed = type == _choose
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var text := "%s  %dx%d" % [info.name, int(info.w), int(info.d)]
			if not homeworld and str(info.where) == "colony":
				var spare := int(store.get(type, 0)) - int(placed.get(type, 0))
				var fbi: Dictionary = fb.get(type, {})
				if spare > 0:
					text += "  · %d in store" % spare
				elif tier < int(fbi.get("tier", 0)):
					text += "  · tier %d" % int(fbi.get("tier", 0))
					b.disabled = true
				else:
					text += "  · builds for %s" % _money(int(fbi.get("cost", 0)))
			b.text = text
			b.pressed.connect(_choose_piece.bind(type))
			_list.add_child(b)


func _credits() -> String:
	return _money(int(_me().get("credits", 0)))


func _money(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func _choose_piece(type: String) -> void:
	_choose = "" if _choose == type else type
	_picked = -1
	_moving = false
	_mark_picked()
	_refresh_list()


func _set_status(text: String) -> void:
	if _status:
		_status.text = text


func _piece(id: int) -> Dictionary:
	for p in _city().get("pieces", []):
		if int(p.id) == id:
			return p
	return {}


## Whether a piece fits at cell (x, z): inside the city, on nobody else's cells.
func _fits(type: String, x: int, z: int, rot: int, skip := -1) -> bool:
	return _why_not(type, x, z, rot, skip) == ""


## Why a piece can't go at cell (x, z), or "" if it can (the server checks again). `skip`: the
## piece being moved, which costs nothing.
func _why_not(type: String, x: int, z: int, rot: int, skip := -1) -> String:
	var s := _size(type, rot)
	if x < -_half or z < -_half or x + s.x > _half or z + s.y > _half:
		return "Outside the city"
	var me := Rect2i(x, z, s.x, s.y)
	for p in _city().get("pieces", []):
		if int(p.id) == skip:
			continue
		var ps := _size(str(p.type), int(p.rot))
		if me.intersects(Rect2i(int(p.x), int(p.z), ps.x, ps.y)):
			return "%s is in the way" % _catalog.get(str(p.type), {}).get("name", "A piece")
	if skip < 0:
		return str(_offer(type).get("why", ""))
	return ""


## What placing a new piece takes and gives: {"cost", "adds"}, and "why" if it can't be had now.
func _offer(type: String) -> Dictionary:
	var info: Dictionary = _catalog.get(type, {})
	var colony := _colony()
	if colony.is_empty():
		return {"cost": "", "adds": ""} # a homeworld: scenery
	if str(info.get("where", "")) != "colony":
		return {"cost": "free", "adds": ""}
	var fbi: Dictionary = Net.catalog.get("frontier", {}).get("buildings", {}).get(type, {})
	var adds := _adds(fbi)
	var placed := 0
	for p in _city().get("pieces", []):
		if str(p.type) == type:
			placed += 1
	var spare := int(colony.colony.get("buildings", {}).get(type, 0)) - placed
	if spare > 0:
		return {"cost": "one from store (%d there)" % spare, "adds": adds}
	var tier := int(fbi.get("tier", 0))
	if int(colony.colony.get("tier", 0)) < tier:
		return {"cost": "", "adds": adds, "why": "Unlocks at colony tier %d" % tier}
	var cost := int(fbi.get("cost", 0))
	var out := {"cost": "builds a new one for %s credits" % _money(cost), "adds": adds}
	if int(_me().get("credits", 0)) < cost:
		out.why = "Needs %s credits; you have %s" % [_money(cost), _credits()]
	return out


## What a colony building does for the colony, in a few words.
func _adds(fbi: Dictionary) -> String:
	if fbi.has("covers"):
		return "keeps %s in hand for %s people" % [fbi.covers, _money(int(fbi.get("per", 0)))]
	if fbi.has("houses"):
		return "houses %s people" % _money(int(fbi.houses))
	if fbi.has("makes"):
		return "makes %s" % fbi.makes
	return ""


## The cell under the mouse, on the ground.
func _mouse_cell() -> Variant:
	var mouse := get_viewport().get_mouse_position()
	var from := _cam.project_ray_origin(mouse)
	var dir := _cam.project_ray_normal(mouse)
	if absf(dir.y) < 0.0001:
		return null
	var t := -from.y / dir.y
	if t < 0.0:
		return null
	var hit := from + dir * t
	return Vector2(hit.x / _cell, hit.z / _cell)


## Where a piece of `type` goes with the mouse at `at` (in cells): centred on the mouse.
func _corner(type: String, rot: int, at: Vector2) -> Vector2i:
	var s := _size(type, rot)
	return Vector2i(floori(at.x - s.x * 0.5 + 0.5), floori(at.y - s.y * 0.5 + 0.5))


## The piece standing on a cell, or -1.
func _piece_at(cell: Vector2i) -> int:
	for p in _city().get("pieces", []):
		var s := _size(str(p.type), int(p.rot))
		if Rect2i(int(p.x), int(p.z), s.x, s.y).has_point(cell):
			return int(p.id)
	return -1


func _ghost_type() -> String:
	if _moving and _picked >= 0:
		return str(_piece(_picked).get("type", ""))
	return _choose


func _update_ghost() -> void:
	var type := _ghost_type()
	var at = _mouse_cell()
	if type == "" or at == null or _mouse_over_ui():
		_ghost.visible = false
		_tip.visible = false
		return
	var c := _corner(type, _rot, at)
	_hover = c
	var s := _size(type, _rot)
	(_ghost.mesh as BoxMesh).size = Vector3(s.x * _cell - 0.6, 4.0, s.y * _cell - 0.6)
	_ghost.position = Vector3((c.x + s.x * 0.5) * _cell, 2.0, (c.y + s.y * 0.5) * _cell)
	var why := _why_not(type, c.x, c.y, _rot, _picked if _moving else -1)
	_ghost.material_override = _ghost_ok if why == "" else _ghost_bad
	_ghost.visible = true
	_show_tip(type, why)


## Beside the mouse: the piece, what it costs and adds, and in red why it can't go here.
func _show_tip(type: String, why: String) -> void:
	var label := str(_catalog.get(type, {}).get("name", type))
	var lines := PackedStringArray(["Moving: " + label if _moving else label])
	if not _moving:
		var o := _offer(type)
		var line := str(o.cost)
		if str(o.adds) != "":
			line = str(o.adds) if line == "" else line + " · " + str(o.adds)
		if line != "":
			lines.append(line)
		if type.begins_with("zone_"):
			_look(type, 0) # counts the faction's looks for it
			var looks := int(_looks.get(type, 0))
			lines.append("Hold and drag to zone a street" + (": each lot gets one of %d homes" % looks if looks > 1 else ""))
	if why != "":
		lines.append(why)
	_tip.text = "\n".join(lines)
	_tip.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5) if why != "" else Color(0.75, 1.0, 0.85))
	_tip.position = get_viewport().get_mouse_position() + Vector2(20, 18)
	_tip.visible = true


func _mouse_over_ui() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null and hovered.is_visible_in_tree()


func _place_cam() -> void:
	var pitch := deg_to_rad(52.0)
	var back := Vector3(sin(_cam_yaw), 0, cos(_cam_yaw)) * cos(pitch) * _cam_dist
	_cam.position = _cam_target + back + Vector3(0, sin(pitch) * _cam_dist, 0)
	_cam.look_at(_cam_target, Vector3.UP)


func _tick(delta: float) -> void:
	if _clear_armed > 0.0:
		_clear_armed -= delta
	if not building:
		return
	var pan := Vector2.ZERO
	if not _typing():
		if Input.is_physical_key_pressed(KEY_W):
			pan.y -= 1
		if Input.is_physical_key_pressed(KEY_S):
			pan.y += 1
		if Input.is_physical_key_pressed(KEY_A):
			pan.x -= 1
		if Input.is_physical_key_pressed(KEY_D):
			pan.x += 1
		if Input.is_physical_key_pressed(KEY_Q):
			_cam_yaw += delta * 1.4
		if Input.is_physical_key_pressed(KEY_E):
			_cam_yaw -= delta * 1.4
	if pan != Vector2.ZERO:
		var speed := _cam_dist * 1.2
		var fwd := Vector3(-sin(_cam_yaw), 0, -cos(_cam_yaw))
		var right := Vector3(cos(_cam_yaw), 0, -sin(_cam_yaw))
		_cam_target += (right * pan.x - fwd * pan.y) * speed * delta
	var span := _half * _cell
	_cam_target.x = clampf(_cam_target.x, -span, span)
	_cam_target.z = clampf(_cam_target.z, -span, span)
	_place_cam()
	_update_ghost()
	_perf_wait -= delta
	if _perf_wait <= 0.0:
		_perf_wait = 0.5
		_perf.text = "%d pieces · %d fps · %d draw calls" % [_pieces.size(), int(Performance.get_monitor(Performance.TIME_FPS)), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))]


func _typing() -> bool:
	return _chat.is_typing()


func _unhandled_input(event: InputEvent) -> void:
	if not building:
		if can_build and not seated and not menu_open and not _paused.visible and not _chat.is_typing() \
				and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_B:
			set_building(true)
			get_viewport().set_input_as_handled()
			return
		super(event)
		return
	if _typing():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_Z and (event.ctrl_pressed or event.meta_pressed):
			_undo_last()
			get_viewport().set_input_as_handled()
			return
		match event.physical_keycode:
			KEY_B, KEY_ESCAPE:
				set_building(false)
			KEY_R:
				_turn()
			KEY_M:
				_start_move()
			KEY_X, KEY_DELETE:
				_take_up()
			_:
				return
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_cam_dist = clampf(_cam_dist * 0.88, 40.0, 1500.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				_cam_dist = clampf(_cam_dist / 0.88, 40.0, 1500.0)
			MOUSE_BUTTON_RIGHT:
				_dragging_view = event.pressed
				if event.pressed:
					_let_go()
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_click()
				else:
					_laying = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if _dragging_view:
			var k := _cam_dist * 0.0022
			var fwd := Vector3(-sin(_cam_yaw), 0, -cos(_cam_yaw))
			var right := Vector3(cos(_cam_yaw), 0, -sin(_cam_yaw))
			_cam_target -= right * event.relative.x * k
			_cam_target -= fwd * -event.relative.y * k
		elif _laying:
			_lay_here()


func _click() -> void:
	var at = _mouse_cell()
	if at == null:
		return
	if _moving and _picked >= 0:
		var p := _piece(_picked)
		var c := _corner(str(p.type), _rot, at)
		_send_city({"type": "city_move", "id": _picked, "x": c.x, "z": c.y, "rot": _rot}, _was(p))
		_moving = false
		return
	if _choose != "":
		_stroke += 1
		_last_laid = Vector2i(999999, 999999)
		_laying = _choose in DRAG_PIECES
		_lay_here()
		return
	_picked = _piece_at(Vector2i(floori(at.x), floori(at.y)))
	if _picked >= 0:
		_rot = int(_piece(_picked).rot)
		var info: Dictionary = _catalog.get(str(_piece(_picked).type), {})
		_set_status("%s picked: R turns it, M moves it, X takes it up." % info.get("name", "Piece"))
	else:
		_set_status("")
	_mark_picked()


## Places the chosen piece under the mouse (once per cell while dragging a road or wall).
func _lay_here() -> void:
	var at = _mouse_cell()
	if at == null or _choose == "":
		return
	var c := _corner(_choose, _rot, at)
	if c == _last_laid:
		return
	_last_laid = c
	if _laying and not _fits(_choose, c.x, c.y, _rot):
		return
	_send_city({"type": "city_place", "piece": _choose, "x": c.x, "z": c.y, "rot": _rot}, {"op": "placed", "stroke": _stroke})


func _let_go() -> void:
	if _moving:
		_moving = false
	elif _choose != "":
		_choose = ""
		_refresh_list()
	else:
		_picked = -1
		_mark_picked()
		_set_status("")


func _turn() -> void:
	_rot = (_rot + 1) % 4
	if _picked >= 0 and not _moving:
		var p := _piece(_picked)
		if not p.is_empty():
			_send_city({"type": "city_move", "id": _picked, "x": int(p.x), "z": int(p.z), "rot": _rot}, _was(p))


func _start_move() -> void:
	if _picked >= 0:
		_moving = true
		_choose = ""
		_set_status("Moving: click where it goes, right click to cancel.")


func _take_up() -> void:
	if _picked < 0:
		return
	var p := _piece(_picked)
	if not p.is_empty():
		_stroke += 1
		_send_city({"type": "city_remove", "id": _picked}, {"op": "removed", "stroke": _stroke, "id": _picked, "type": str(p.type), "x": int(p.x), "z": int(p.z), "rot": int(p.rot)})
	_picked = -1
	_moving = false
	_mark_picked()


## Clearing the whole city takes two presses, a few seconds apart at most.
func _clear_city() -> void:
	if _clear_armed <= 0.0:
		_clear_armed = 4.0
		_set_status("Press again to clear every piece from the city.")
		return
	_clear_armed = 0.0
	Net.send({"type": "city_clear", "planet": planet_id})
	_undo.clear()
	_set_status("City cleared. This can't be undone.")


func _copy_city() -> void:
	if _copy_from == null or _copy_from.selected < 0:
		return
	Net.send({"type": "city_copy", "from": str(_copy_from.get_item_metadata(_copy_from.selected)), "planet": planet_id})
	_undo.clear()
	_set_status("Copied: this city now matches %s." % _copy_from.get_item_text(_copy_from.selected))


## A light box over the picked piece, so you can see what R, M and X act on.
func _mark_picked() -> void:
	if _select == null:
		return
	var p := _piece(_picked) if _picked >= 0 else {}
	if p.is_empty():
		_select.visible = false
		return
	var s := _size(str(p.type), int(p.rot))
	(_select.mesh as BoxMesh).size = Vector3(s.x * _cell + 0.8, 1.2, s.y * _cell + 0.8)
	_select.position = _centre(str(p.type), int(p.x), int(p.z), int(p.rot)) + Vector3(0, 0.6, 0)
	_select.visible = true


# --- Undo -------------------------------------------------------------------------------------
# Each change you make is remembered once the server confirms it (its city_result carries the tag
# it was sent with). Ctrl+Z sends the opposite change. A colony building you paid for and then undo
# goes back into the colony's store, like taking it up.

## The undo step for moving or turning a piece: where it was.
func _was(p: Dictionary) -> Dictionary:
	_stroke += 1
	return {"op": "moved", "stroke": _stroke, "id": int(p.id), "x": int(p.x), "z": int(p.z), "rot": int(p.rot)}


func _send_city(msg: Dictionary, op: Dictionary) -> void:
	msg.planet = planet_id
	if not op.is_empty():
		_tags += 1
		msg.tag = str(_tags)
		_pending[msg.tag] = op
		if _pending.size() > 400: # refused ones never come back
			_pending.erase(_pending.keys()[0])
	Net.send(msg)


func _confirm(tag: String, msg: Dictionary) -> void:
	if not _pending.has(tag):
		return
	var op: Dictionary = _pending[tag]
	_pending.erase(tag)
	if op.op == "remap": # an undone take-up came back as a new piece: later steps follow it
		for step in _undo:
			for o in step.ops:
				if int(o.get("id", -1)) == int(op.old):
					o.id = int(msg.get("piece", -1))
		return
	if op.op == "placed":
		op.id = int(msg.get("piece", -1))
		op.built = msg.get("built", false)
	if not _undo.is_empty() and _undo[-1].stroke == op.stroke:
		_undo[-1].ops.append(op)
	else:
		_undo.append({"stroke": op.stroke, "ops": [op]})
	if _undo.size() > UNDO_STEPS:
		_undo.pop_front()


func _undo_last() -> void:
	if _undo.is_empty():
		_set_status("Nothing to undo.")
		return
	var ops: Array = _undo.pop_back().ops
	var paid := false
	for i in range(ops.size() - 1, -1, -1):
		var o: Dictionary = ops[i]
		match str(o.op):
			"placed":
				paid = paid or o.get("built", false)
				_send_city({"type": "city_remove", "id": o.id}, {})
			"moved":
				_send_city({"type": "city_move", "id": o.id, "x": o.x, "z": o.z, "rot": o.rot}, {})
			"removed":
				_send_city({"type": "city_place", "piece": o.type, "x": o.x, "z": o.z, "rot": o.rot}, {"op": "remap", "old": o.id})
	_picked = -1
	_moving = false
	_mark_picked()
	_set_status("Undone. The building you paid for is back in the colony's store." if paid else "Undone.")
