extends Control
## Trade for the war, in one panel with two pages:
##   market     a Builder's Carrier Dock: what they list (item, price, in stock); buy an amount
##              with `dock_buy`. Only Builders of your own faction trade with you.
##   contracts  supply contracts: post one (an item from the catalog's contract items, an amount
##              and a reward, held from your credits) with `post_contract`, follow yours as
##              Builders of your faction fill them, and cancel with `cancel_contract`.
## Both show your credits and your war goods hold (pilot.hold): what you've bought and been
## supplied, which loads into your carrier when carriers come.

const WarInfo := preload("res://war_info.gd")

signal closed
signal wants_faction

var colour := Color(0.35, 0.95, 0.88)
var mode := "contracts"
var builder := "" # whose Carrier Dock, on the market page

var _title: Label
var _wallet: Label
var _body: VBoxContainer
var _status: Label
var _rows := {} # market: item -> {"price", "stock", "qty", "buy"}
var _grid: GridContainer
var _empty: Label
var _form: VBoxContainer
var _item: OptionButton
var _amount: SpinBox
var _reward: SpinBox
var _mine: VBoxContainer
var _others: Label
var _no_side: VBoxContainer
var _pending := {} # the last request, until the state shows it done: {"kind": "buy" | "post" | "cancel", ...}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.02, 0.05, 0.7)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 0)
	# Nearly opaque, so the console screens and signs behind don't show through the rows.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.06, 0.09, 0.95)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)
	var top := HBoxContainer.new()
	col.add_child(top)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	var close := Button.new()
	close.text = "Close (Esc)"
	close.pressed.connect(func(): closed.emit())
	top.add_child(close)
	_wallet = Label.new()
	_wallet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_wallet)
	col.add_child(HSeparator.new())
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	col.add_child(_body)
	_status = Label.new()
	_status.modulate = Color(1, 1, 1, 0.7)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)
	Net.server_error.connect(func(reason):
		_pending = {}
		if visible:
			_status.text = "Server: " + reason)
	_build_market()
	_build_contracts()
	refresh()


func _label(text: String, muted := false) -> Label:
	var l := Label.new()
	l.text = text
	if muted:
		l.modulate = Color(1, 1, 1, 0.6)
	return l


## Opens a page: "market" (with the Builder whose dock it is) or "contracts".
func open(page: String, dock_owner := "") -> void:
	mode = page
	builder = dock_owner
	_status.text = ""
	_pending = {}
	refresh()


func refresh() -> void:
	if not is_node_ready() or Net.state.is_empty():
		return
	var me: Dictionary = Net.state.get("pilots", {}).get(Net.my_name, {})
	_wallet.text = "Credits %d   ·   War goods hold: %s" % [int(me.get("credits", 0)), WarInfo.goods_list(me.get("hold", {}), "empty")]
	_check_pending(me)
	var side := WarInfo.my_faction()
	_no_side.visible = side == ""
	_grid.get_parent().visible = mode == "market" and side != ""
	_form.visible = mode == "contracts" and side != ""
	if mode == "market":
		_refresh_market()
	else:
		_refresh_contracts()


# --- The Carrier Dock market ------------------------------------------------------------------

func _build_market() -> void:
	_no_side = VBoxContainer.new()
	_no_side.add_child(_label("Trading for the war is between pilots and Builders of one faction. Choose your side first."))
	var pick := Button.new()
	pick.text = "Choose a faction"
	pick.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	pick.pressed.connect(func(): wants_faction.emit())
	_no_side.add_child(pick)
	_body.add_child(_no_side)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_body.add_child(box)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 24)
	_grid.add_theme_constant_override("v_separation", 6)
	box.add_child(_grid)
	for h in ["Item", "Price", "In stock", "Amount", ""]:
		var l := _label(h, true)
		_grid.add_child(l)
	_empty = _label("Nothing is listed for sale here yet.", true)
	box.add_child(_empty)


func _refresh_market() -> void:
	var e: Dictionary = Net.state.get("bases", {}).get(builder, {})
	var side := WarInfo.builder_faction(builder)
	_title.text = "%s's Carrier Dock" % builder
	if side != "":
		_title.text += " · %s" % WarInfo.faction_name(side)
		_title.add_theme_color_override("font_color", WarInfo.faction_color(side))
	var market: Dictionary = e.get("market", {})
	var stock: Dictionary = e.get("stock", {})
	# Rows come and go with the listings; the amounts you've typed stay put.
	for item in _rows.keys():
		if not market.has(item):
			for k in ["name", "price", "stock", "qty", "buy"]:
				_rows[item][k].queue_free()
			_rows.erase(item)
	for item in market:
		if not _rows.has(item):
			var row := {"name": _label(WarInfo.goods_name(item)), "price": _label(""), "stock": _label("")}
			var qty := SpinBox.new()
			qty.min_value = 1
			qty.value = 1
			qty.custom_minimum_size = Vector2(110, 0)
			var buy := Button.new()
			buy.custom_minimum_size = Vector2(170, 0)
			buy.pressed.connect(_buy.bind(item))
			qty.value_changed.connect(func(_v): _update_row(item))
			row.qty = qty
			row.buy = buy
			_rows[item] = row
			for k in ["name", "price", "stock", "qty", "buy"]:
				_grid.add_child(row[k])
		_update_row(item)
	_empty.visible = market.is_empty()


func _update_row(item: String) -> void:
	var e: Dictionary = Net.state.get("bases", {}).get(builder, {})
	var price := int(e.get("market", {}).get(item, 0))
	var have := int(e.get("stock", {}).get(item, 0))
	var row: Dictionary = _rows[item]
	row.price.text = "%d CR each" % price
	row.stock.text = str(have)
	var qty: SpinBox = row.qty
	qty.max_value = maxi(1, have)
	qty.editable = have > 0
	var buy: Button = row.buy
	buy.disabled = have <= 0
	buy.text = "Sold out" if have <= 0 else "Buy for %d CR" % (price * int(qty.value))


## Once the state shows the last request done, says so in place of "Buying...".
func _check_pending(me: Dictionary) -> void:
	match _pending.get("kind", ""):
		"buy":
			if int(me.get("hold", {}).get(_pending.item, 0)) > int(_pending.had):
				_status.text = "Bought %s for your war goods hold." % WarInfo.amount_of(_pending.item, _pending.qty)
				_pending = {}
		"post":
			for c in Net.state.get("contracts", []):
				if c.pilot == Net.my_name and int(c.id) > int(_pending.after):
					_status.text = "Posted contract #%d. %d CR is held from your credits for it." % [int(c.id), int(c.reward)]
					_pending = {}
					break
		"cancel":
			for c in Net.state.get("contracts", []):
				if int(c.id) == int(_pending.id) and c.status != "open":
					_status.text = "Cancelled contract #%d: what wasn't paid out is back in your credits." % int(c.id)
					_pending = {}
					break


func _buy(item: String) -> void:
	var n := int(_rows[item].qty.value)
	var me: Dictionary = Net.state.get("pilots", {}).get(Net.my_name, {})
	_pending = {"kind": "buy", "item": item, "qty": n, "had": int(me.get("hold", {}).get(item, 0))}
	_status.text = "Buying %s..." % WarInfo.amount_of(item, n)
	Net.send({"type": "dock_buy", "builder": builder, "item": item, "qty": n})


# --- Supply contracts -------------------------------------------------------------------------

func _build_contracts() -> void:
	_form = VBoxContainer.new()
	_form.add_theme_constant_override("separation", 8)
	_body.add_child(_form)
	_form.add_child(_label("Post a contract"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_form.add_child(row)
	_item = OptionButton.new()
	_item.custom_minimum_size = Vector2(220, 0)
	row.add_child(_item)
	row.add_child(_label("Amount"))
	_amount = SpinBox.new()
	_amount.min_value = 1
	_amount.max_value = 1000
	_amount.value = 20
	row.add_child(_amount)
	row.add_child(_label("Reward"))
	_reward = SpinBox.new()
	_reward.min_value = 1
	_reward.max_value = 100000
	_reward.value = 200
	_reward.suffix = "CR"
	_reward.custom_minimum_size = Vector2(130, 0)
	row.add_child(_reward)
	var post := Button.new()
	post.text = "Post"
	post.pressed.connect(_post)
	row.add_child(post)
	_form.add_child(_label("The reward is held from your credits and paid out as Builders of your faction fill the contract. Goods go in your war goods hold.", true))
	_form.get_child(-1).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_form.add_child(HSeparator.new())
	_form.add_child(_label("Your contracts"))
	_mine = VBoxContainer.new()
	_mine.add_theme_constant_override("separation", 4)
	_form.add_child(_mine)
	_others = _label("", true)
	_others.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_form.add_child(_others)


func _refresh_contracts() -> void:
	var side := WarInfo.my_faction()
	_title.text = "Supply contracts" + (" · %s" % WarInfo.faction_name(side) if side != "" else "")
	_title.add_theme_color_override("font_color", WarInfo.faction_color(side) if side != "" else Color.WHITE)
	if _item.item_count == 0:
		for id in Net.catalog.get("contractItems", []):
			_item.add_item(WarInfo.goods_name(id))
			_item.set_item_metadata(_item.item_count - 1, id)
	for child in _mine.get_children():
		child.queue_free()
	var mine := []
	var others := []
	for c in Net.state.get("contracts", []):
		if c.pilot == Net.my_name:
			mine.append(c)
		elif c.status == "open" and c.faction == side:
			others.append(c)
	mine.reverse()
	var closed := 0
	for c in mine:
		if c.status != "open":
			closed += 1
			if closed > 4:
				continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var l := _label("#%d   %s for %d CR   ·   %d/%d filled, %d CR paid   ·   %s" % [int(c.id), WarInfo.amount_of(c.item, int(c.amount)), int(c.reward),
			int(c.filled), int(c.amount), int(c.paid), str(c.status).to_upper()], c.status != "open")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if c.status == "open":
			var cancel := Button.new()
			cancel.text = "Cancel (refund %d CR)" % (int(c.reward) - int(c.paid))
			cancel.pressed.connect(_cancel.bind(int(c.id)))
			row.add_child(cancel)
		_mine.add_child(row)
	if mine.is_empty():
		_mine.add_child(_label("None yet.", true))
	var lines := []
	for c in others.slice(0, 4):
		lines.append("#%d  %s wants %s for %d CR (%d/%d)" % [int(c.id), c.pilot, WarInfo.amount_of(c.item, int(c.amount)), int(c.reward), int(c.filled), int(c.amount)])
	_others.text = ("Open contracts from other pilots of your side:\n" + "\n".join(lines)) if not lines.is_empty() else ""
	_others.visible = not lines.is_empty()


func _post() -> void:
	if _item.selected < 0:
		return
	var id: String = _item.get_item_metadata(_item.selected)
	var last := 0
	for c in Net.state.get("contracts", []):
		last = maxi(last, int(c.id))
	_pending = {"kind": "post", "after": last}
	_status.text = "Posting a contract for %s..." % WarInfo.amount_of(id, int(_amount.value))
	Net.send({"type": "post_contract", "item": id, "amount": int(_amount.value), "reward": int(_reward.value)})


func _cancel(id: int) -> void:
	_pending = {"kind": "cancel", "id": id}
	_status.text = "Cancelling contract #%d..." % id
	Net.send({"type": "cancel_contract", "contract": id})
