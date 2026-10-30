extends Control
## The HIGH COMMAND terminal (a carrier's Command Deck, or the War terminal's Orders): your faction's
## orders, full screen, over whatever you were doing. The orders themselves are orders_view.gd.

const WarInfo := preload("res://war_info.gd")
const OrdersView := preload("res://orders_view.gd")

signal closed

var colour := Color(0.36, 0.78, 0.78)
var view: VBoxContainer
var _tick := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.06, 0.95)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 120
	scroll.offset_right = -120
	scroll.offset_top = 30
	scroll.offset_bottom = -80
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	view = OrdersView.new()
	scroll.add_child(view)
	var close := Button.new()
	close.text = "Close (Esc)"
	close.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	close.offset_left = -80
	close.offset_right = 80
	close.offset_top = -60
	close.offset_bottom = -24
	close.pressed.connect(func(): closed.emit())
	add_child(close)


func open() -> void:
	refresh()


func refresh() -> void:
	view.show_for(Net.state, WarInfo.my_faction(), Net.my_name)


func _process(delta: float) -> void:
	if not visible:
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = 1.0
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu")):
		closed.emit()
		get_viewport().set_input_as_handled()
