extends Control
## The faction choice: a full-screen overlay with the factions a pilot can join, for a pilot who
## hasn't picked one. Every character picks once (the server says no to a second time).
## Players pick from the three playable factions; the Coma Conglomerate is for the galaxy's admins,
## so its card shows (tagged "Admins only") only when the server knows you as one.
## Choosing sends `choose_faction`; the explorer closes this when the galaxy shows your side.

const WarInfo := preload("res://war_info.gd")

signal dismissed

var _cards: HBoxContainer
var _status: Label
var _intro: Label
var _built_for := "" # the factions the cards were built for, so they're rebuilt if that changes


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.02, 0.05, 0.92)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)

	var title := Label.new()
	title.text = "Choose your side"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	_intro = Label.new()
	_intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro.modulate = Color(1, 1, 1, 0.75)
	col.add_child(_intro)

	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 16)
	_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_cards)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status)
	var later := Button.new()
	later.text = "Not now (choose later from your ship's menu)"
	later.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	later.pressed.connect(func(): dismissed.emit())
	col.add_child(later)
	Net.server_error.connect(func(reason): if visible: _status.text = "Server: " + reason)
	refresh()


## Builds the cards from the catalog (it arrives with the server's welcome): the playable
## factions, and the Coma Conglomerate too for an admin.
func refresh() -> void:
	if not is_node_ready():
		return
	var ids := WarInfo.faction_ids().filter(func(f): return WarInfo.playable(f) or Net.admin)
	if ",".join(ids) == _built_for:
		return
	_built_for = ",".join(ids)
	for child in _cards.get_children():
		child.queue_free()
	for id in ids:
		_cards.add_child(_card(id, WarInfo.factions()[id]))
	var players := WarInfo.player_factions().map(func(f): return WarInfo.faction_name(f))
	var coma := WarInfo.faction_ids().filter(func(f): return not WarInfo.playable(f)).map(func(f): return WarInfo.the(f))
	_intro.text = "%s factions are at war over Teal Prime's contested worlds%s. Every pilot fights for one, and picks it once.\nYour side decides whose outposts you raid (never your own), whose Carrier Docks trade with you, and who you take sectors for." % [
		["No", "One", "Two", "Three", "Four"][mini(players.size(), 4)], (", and %s presses in on them all" % " and ".join(coma)) if not coma.is_empty() else ""]


func _card(id: String, f: Dictionary) -> Control:
	var colour := WarInfo.faction_color(id)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(272, 340)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.06, 0.09, 0.95)
	style.border_color = colour
	style.set_border_width_all(2)
	style.border_width_top = 6
	style.set_corner_radius_all(6)
	style.set_content_margin_all(16)
	card.add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)
	var heading := Label.new()
	heading.text = str(f.get("name", id))
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", colour)
	col.add_child(heading)
	var mirrors := Label.new()
	mirrors.text = "Mirrors the %s" % str(f.get("mirrors", "?"))
	mirrors.modulate = Color(1, 1, 1, 0.55)
	col.add_child(mirrors)
	if not WarInfo.playable(id):
		var tag := Label.new()
		tag.text = "Admins only"
		tag.add_theme_color_override("font_color", Color(0.02, 0.04, 0.06))
		var chip := StyleBoxFlat.new()
		chip.bg_color = colour
		chip.set_corner_radius_all(4)
		chip.set_content_margin_all(4)
		chip.content_margin_left = 8
		chip.content_margin_right = 8
		tag.add_theme_stylebox_override("normal", chip)
		tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		col.add_child(tag)
		col.add_child(_wrapped("Played by the galaxy's admins and its AI director, never by players."))
		col.get_child(-1).modulate = Color(1, 1, 1, 0.6)
	col.add_child(_wrapped(str(f.get("style", ""))))
	var bonus_head := Label.new()
	bonus_head.text = "Faction bonus"
	bonus_head.add_theme_color_override("font_color", colour)
	col.add_child(bonus_head)
	col.add_child(_wrapped(str(f.get("bonus", ""))))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	var join := Button.new()
	join.text = ("Play the %s" if not WarInfo.playable(id) else "Join the %s") % str(f.get("name", id))
	join.add_theme_color_override("font_color", colour)
	join.pressed.connect(_choose.bind(id))
	col.add_child(join)
	return card


func _wrapped(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(240, 0)
	return l


func _choose(id: String) -> void:
	_status.text = "Joining %s..." % WarInfo.the(id)
	Net.send({"type": "choose_faction", "faction": id})
