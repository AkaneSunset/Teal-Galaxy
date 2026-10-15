extends VBoxContainer
## Chat that works anywhere, including mid-flight. Lines fade after a while; open it to type.
## The ship keeps flying on its current throttle while you type, so mind where you're pointed.

const SHOW_SECONDS := 12.0
const KEEP_LINES := 8

signal opened
signal closed

var _log: Label
var _edit: LineEdit
var _lines := [] # {"text", "at"}


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	_log = Label.new()
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_log.custom_minimum_size = Vector2(420, 0)
	_log.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	add_child(_log)
	_edit = LineEdit.new()
	_edit.placeholder_text = "Say something (Enter to send, Esc to cancel)"
	_edit.max_length = 200
	_edit.visible = false
	_edit.text_submitted.connect(_on_submit)
	add_child(_edit)
	Net.chat_received.connect(add_line)


func is_typing() -> bool:
	return _edit.visible


func open() -> void:
	_edit.visible = true
	_edit.text = ""
	_edit.grab_focus()
	opened.emit()


func close() -> void:
	_edit.visible = false
	_edit.release_focus()
	closed.emit()


func add_line(sender: String, role: String, text: String) -> void:
	var tag := " (builder)" if role == "builder" else ""
	_lines.append({"text": "%s%s: %s" % [sender, tag, text], "at": Time.get_ticks_msec() / 1000.0})
	if _lines.size() > KEEP_LINES:
		_lines.pop_front()


func _on_submit(text: String) -> void:
	if text.strip_edges() != "":
		Net.send({"type": "chat", "text": text})
	close()


func _unhandled_key_input(event: InputEvent) -> void:
	if is_typing() and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var shown := []
	for l in _lines:
		if is_typing() or now - l.at < SHOW_SECONDS:
			shown.append(l.text)
	_log.text = "\n".join(shown)
