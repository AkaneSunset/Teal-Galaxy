extends Control
## The raid inventory: the container being searched, the backpack and the Secure Case, as grids.
## Items take up space by their size, so what fits is the limit. The server places everything;
## this only shows it and asks for moves.
##
## Left-click moves an item between the container and the backpack.
## Right-click moves it into or out of the Secure Case, which you keep even if you die.
## Healing goes straight into the pouch (shown under the backpack), and clicking a vest puts it on.

signal take(uid: String, to: String)
signal drop(uid: String)
signal stow(uid: String, to: String)
signal closed

const CELL := 52.0
const RARITY_COLOURS := {
	"common": Color(0.55, 0.57, 0.6), "uncommon": Color(0.35, 0.72, 0.38), "rare": Color(0.3, 0.52, 0.95),
	"epic": Color(0.62, 0.38, 0.95), "legendary": Color(0.95, 0.72, 0.2),
}

var _items: Array = [] # carried, each with "grid" and "rect"
var _backpack := Vector2i(6, 4)
var _secure := Vector2i(2, 2)
var _container_name := ""
var _container_grid := Vector2i.ZERO
var _slots: Array = [] # container: revealed items, or placeholders {uid, rect, revealIn}
var _reveal_at := {} # uid -> msec when its search finishes
var _status := ""
var _pouch_text := ""
var _area: Control
var _help: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.02, 0.05, 0.82)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_area = Control.new()
	_area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_area.mouse_filter = Control.MOUSE_FILTER_PASS
	_area.draw.connect(_draw_grids)
	_area.gui_input.connect(_on_input)
	add_child(_area)
	_help = Label.new()
	_help.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_help.position.y -= 60
	_help.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help.modulate = Color(1, 1, 1, 0.7)
	_help.text = "Left-click: take from the container / put back.   Right-click: into or out of the Secure Case (kept if you die).\nHealing goes in your pouch; click a vest to put it on.   Tab, Esc or F to close."
	add_child(_help)


func set_inventory(items: Array, backpack: Array, secure: Array) -> void:
	_items = items
	_backpack = Vector2i(int(backpack[0]), int(backpack[1]))
	_secure = Vector2i(int(secure[0]), int(secure[1]))
	if _area:
		_area.queue_redraw()


## The pouch and the worn vest, as a line of text under the backpack.
func set_pouch(text: String) -> void:
	_pouch_text = text
	if _area:
		_area.queue_redraw()


func set_container(container_name: String, slots: Array, grid: Array, status: String) -> void:
	_container_name = container_name
	_container_grid = Vector2i(int(grid[0]), int(grid[1]))
	_slots = slots
	_status = status
	_reveal_at.clear()
	for s in slots:
		if s.has("revealIn"):
			_reveal_at[s.uid] = Time.get_ticks_msec() + float(s.revealIn)
	if _area:
		_area.queue_redraw()


func reveal(item: Dictionary) -> void:
	for i in _slots.size():
		if _slots[i].uid == item.uid:
			_slots[i] = item
	if _slots.all(func(s): return s.has("item")):
		_status = ""
	_area.queue_redraw()


func _process(_delta: float) -> void:
	if visible and not _reveal_at.is_empty():
		_area.queue_redraw()


# Where each grid sits on screen.
func _origins() -> Dictionary:
	var size := _area.size
	var widths := [_container_grid.x * CELL if _container_name != "" else 0.0, _backpack.x * CELL, _secure.x * CELL]
	var total: float = widths[0] + widths[1] + widths[2] + 2 * 60.0
	var x := (size.x - total) / 2.0
	var y := size.y * 0.3
	var out := {}
	if _container_name != "":
		out["container"] = Vector2(x, y)
		x += widths[0] + 60.0
	else:
		x += 30.0
	out["backpack"] = Vector2(x, y)
	out["secure"] = Vector2(x + widths[1] + 60.0, y)
	return out


func _draw_grids() -> void:
	var font := get_theme_default_font()
	var o := _origins()
	var grids := {"backpack": [_backpack, "Backpack"], "secure": [_secure, "Secure Case"]}
	if _container_name != "":
		grids["container"] = [_container_grid, _container_name + ("   " + _status if _status != "" else "")]
	for key in grids:
		var dims: Vector2i = grids[key][0]
		var origin: Vector2 = o[key]
		_area.draw_string(font, origin + Vector2(0, -12), grids[key][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
		_area.draw_rect(Rect2(origin, Vector2(dims) * CELL), Color(1, 1, 1, 0.05))
		for y in dims.y:
			for x in dims.x:
				_area.draw_rect(Rect2(origin + Vector2(x, y) * CELL, Vector2(CELL, CELL)), Color(1, 1, 1, 0.15), false, 1.0)
	var carried_value := 0
	for it in _items:
		carried_value += int(it.value) * int(it.qty)
		_draw_item(it, o[it.grid])
	_area.draw_string(font, o.backpack + Vector2(0, _backpack.y * CELL + 24), "Carrying %d credits of loot" % carried_value, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.7))
	var pouch_lines := _pouch_text.split("\n")
	for i in pouch_lines.size():
		_area.draw_string(font, o.backpack + Vector2(0, _backpack.y * CELL + 48 + i * 20), pouch_lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.95, 0.65) if i == 0 else Color(0.7, 0.8, 1.0))
	if _container_name != "":
		for s in _slots:
			_draw_item(s, o.container)

	var hover := _item_at(_area.get_local_mouse_position())
	if not hover.is_empty() and hover.item.has("item"):
		var it: Dictionary = hover.item
		var secure_ok: bool = Net.catalog.get("items", {}).get(it.item, {}).get("secure", true) != false
		var lines := ["%s  x%d" % [it.name, int(it.qty)], "%s, %s" % [it.rarity.capitalize(), it.cat], "Worth %d credits each (%d per cell)" % [int(it.value), int(it.value) / (int(it.size[0]) * int(it.size[1]))],
			"Fits the Secure Case" if secure_ok else "Too big for the Secure Case"]
		if it.cat == "medical":
			lines[2] = "Goes in your pouch (kept if you extract)"
			lines[3] = "Use it with the heal key"
		elif it.cat == "armor":
			lines[2] = "%d / %d armour" % [int(it.get("armor", 0)), int(it.get("vest", 0))]
			lines[3] = "Click to put on (leaves yours here)"
		var p := _area.get_local_mouse_position() + Vector2(16, 16)
		_area.draw_rect(Rect2(p, Vector2(270, 84)), Color(0.02, 0.04, 0.06, 0.95))
		for i in lines.size():
			_area.draw_string(font, p + Vector2(8, 20 + i * 18), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


func _draw_item(it: Dictionary, origin: Vector2) -> void:
	var r: Dictionary = it.rect
	var rect := Rect2(origin + Vector2(r.x, r.y) * CELL, Vector2(r.w, r.h) * CELL).grow(-3)
	var font := get_theme_default_font()
	if not it.has("item"):
		# Still being searched: a dark placeholder that fills as the search reaches it.
		_area.draw_rect(rect, Color(0.08, 0.09, 0.1))
		var left: float = _reveal_at.get(it.uid, 0.0) - Time.get_ticks_msec()
		_area.draw_string(font, rect.get_center() + Vector2(-5, 6), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.3 if left > 0 else 0.6))
		return
	var col: Color = RARITY_COLOURS.get(it.rarity, Color.GRAY)
	_area.draw_rect(rect, col.darkened(0.55))
	_area.draw_rect(rect, col, false, 2.0)
	_area.draw_string(font, rect.position + Vector2(4, 16), it.name, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 6, 12, Color.WHITE)
	if int(it.qty) > 1:
		_area.draw_string(font, rect.end - Vector2(22, 6), "x%d" % int(it.qty), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)


func _item_at(p: Vector2) -> Dictionary:
	var o := _origins()
	for it in _items:
		if _rect_of(it, o[it.grid]).has_point(p):
			return {"item": it, "where": it.grid}
	if _container_name != "":
		for s in _slots:
			if _rect_of(s, o.container).has_point(p):
				return {"item": s, "where": "container"}
	return {}


func _rect_of(it: Dictionary, origin: Vector2) -> Rect2:
	var r: Dictionary = it.rect
	return Rect2(origin + Vector2(r.x, r.y) * CELL, Vector2(r.w, r.h) * CELL)


func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_area.queue_redraw()
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	var hit := _item_at(event.position)
	if hit.is_empty() or not hit.item.has("item"):
		return
	var right: bool = event.button_index == MOUSE_BUTTON_RIGHT
	var uid: String = hit.item.uid
	match hit.where:
		"container":
			take.emit(uid, "secure" if right else "backpack")
		"backpack":
			if right:
				stow.emit(uid, "secure")
			elif _container_name != "":
				drop.emit(uid)
		"secure":
			if right:
				stow.emit(uid, "backpack")
			elif _container_name != "":
				drop.emit(uid)
	accept_event()
