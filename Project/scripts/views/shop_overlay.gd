extends Control

const UF = preload("res://scripts/views/ui_factory.gd")
const Card = preload("res://scripts/card.gd")
const CardDatabase = preload("res://scripts/card_database.gd")

@onready var lbl_shop_day: Label = $ShopPanel/Margin/RootVBox/TopBar/LblShopDay
@onready var lbl_shop_cash: Label = $ShopPanel/Margin/RootVBox/TopBar/LblShopCash
@onready var lbl_summary: Label = $ShopPanel/Margin/RootVBox/MidArea/SummaryPanel/SumMargin/SumVBox/LblSummary
@onready var deck_preview: RichTextLabel = $ShopPanel/Margin/RootVBox/MidArea/DeckPanel/DeckMargin/DeckVBox/DeckPreview
@onready var shop_buy_grid: HBoxContainer = $"ShopPanel/Margin/RootVBox/Tabs/买卡/BuyGrid"
@onready var shop_upgrade_list: VBoxContainer = $"ShopPanel/Margin/RootVBox/Tabs/升级/UpgradeList"
@onready var shop_delete_list: VBoxContainer = $"ShopPanel/Margin/RootVBox/Tabs/删卡/DeleteList"
@onready var btn_leave_shop: Button = $ShopPanel/Margin/RootVBox/BottomBar/BtnLeaveShop
@onready var summary_panel: PanelContainer = $ShopPanel/Margin/RootVBox/MidArea/SummaryPanel
@onready var deck_panel: PanelContainer = $ShopPanel/Margin/RootVBox/MidArea/DeckPanel


func _ready() -> void:
	btn_leave_shop.add_theme_color_override("font_color", UF.COL_HIGHLIGHT)
	var sb := UF.panel_stylebox(UF.COL_HIGHLIGHT)
	btn_leave_shop.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(UF.COL_HIGHLIGHT.r, UF.COL_HIGHLIGHT.g, UF.COL_HIGHLIGHT.b, 0.18)
	btn_leave_shop.add_theme_stylebox_override("hover", hover)
	summary_panel.add_theme_stylebox_override("panel", UF.panel_stylebox())
	deck_panel.add_theme_stylebox_override("panel", UF.panel_stylebox())
	btn_leave_shop.pressed.connect(_on_leave_shop_pressed)
	Game.shop_entered.connect(_on_shop_entered)
	Game.shop_changed.connect(_refresh_shop)
	Game.phase_changed.connect(_on_phase_changed)


func _on_shop_entered(_d: int) -> void:
	visible = true
	_refresh_shop()


func _on_phase_changed(p: int) -> void:
	if p != Game.Phase.SHOP:
		visible = false


func _on_leave_shop_pressed() -> void:
	Game.leave_shop_to_next_day()


func _refresh_shop() -> void:
	if not visible:
		return
	lbl_shop_day.text = "第 %d / %d 天 结束" % [Game.day, Game.DAYS_PER_LEVEL]
	lbl_shop_cash.text = "¥%s" % UF.fmt_money(Game.cash)

	var s: Dictionary = Game.day_close_summary
	if s.is_empty():
		lbl_summary.text = "(无)"
	else:
		var pnl: float = s["day_pnl"]
		var pnl_str: String = "%s¥%s" % ["+" if pnl >= 0 else "-", UF.fmt_money(abs(pnl))]
		var price_pct: float = s["price_change_pct"]
		lbl_summary.text = (
			"开盘 ¥%.2f → 收盘 ¥%.2f (%+.2f%%)\n" +
			"持仓 %d 股, 市值 ¥%s\n" +
			"现金 ¥%s, 总资产 ¥%s\n" +
			"今日盈亏 %s"
		) % [
			s["open_price"], s["close_price"], price_pct,
			int(s["shares"]), UF.fmt_money(s["holding_value"]),
			UF.fmt_money(s["cash"]), UF.fmt_money(s["total_assets"]),
			pnl_str
		]

	var counts: Dictionary = {}
	for c in Game.get_full_deck():
		var k: String = "%s|%s" % [c.name, c.effect_id]
		counts[k] = counts.get(k, 0) + 1
	var lines: Array = []
	for k in counts.keys():
		var name_part: String = (k as String).split("|")[0]
		lines.append("%s × %d" % [name_part, counts[k]])
	deck_preview.clear()
	deck_preview.append_text("共 %d 张\n" % Game.get_deck_size())
	for ln in lines:
		deck_preview.append_text(ln + "\n")

	_refresh_shop_buy()
	_refresh_shop_upgrade()
	_refresh_shop_delete()

	if Game.day >= Game.DAYS_PER_LEVEL:
		btn_leave_shop.text = "结束本周, 进入最终结算 →"


func _refresh_shop_buy() -> void:
	for c in shop_buy_grid.get_children():
		c.queue_free()
	for i in range(Game.shop_offers.size()):
		var card: Card = Game.shop_offers[i]
		shop_buy_grid.add_child(_make_shop_card_buy(card, i))
	if Game.shop_offers.is_empty():
		shop_buy_grid.add_child(UF.label("(本日商品已全部售出)", 12, UF.COL_TEXT_DIM))


func _make_shop_card_buy(card: Card, index: int) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var preview := _make_card_preview(card, 130, 96)
	box.add_child(preview)
	box.add_child(UF.label("¥%d" % Game.SHOP_BUY_PRICE, 12, UF.COL_GOLD))
	var btn := UF.button("购买", UF.COL_UP, 13)
	btn.disabled = Game.cash < Game.SHOP_BUY_PRICE
	btn.pressed.connect(func(): Game.shop_buy_card(index))
	box.add_child(btn)
	return box


func _refresh_shop_upgrade() -> void:
	for c in shop_upgrade_list.get_children():
		c.queue_free()
	var deck: Array = Game.get_full_deck()
	var any_upgradable: bool = false
	for i in range(deck.size()):
		var card: Card = deck[i]
		var target_eid: String = CardDatabase.upgrade_target(card.effect_id)
		if target_eid == "":
			continue
		any_upgradable = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		shop_upgrade_list.add_child(row)
		row.add_child(UF.label("%s → %s" % [card.name, _name_for_effect(target_eid)], 13, UF.COL_TEXT))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		row.add_child(UF.label("¥%d" % Game.SHOP_UPGRADE_PRICE, 12, UF.COL_GOLD))
		var idx_capture: int = i
		var btn := UF.button("升级", UF.COL_HIGHLIGHT, 12)
		btn.disabled = Game.cash < Game.SHOP_UPGRADE_PRICE
		btn.pressed.connect(func(): Game.shop_upgrade_card(idx_capture))
		row.add_child(btn)
	if not any_upgradable:
		shop_upgrade_list.add_child(UF.label("(没有可升级的卡)", 12, UF.COL_TEXT_DIM))


func _refresh_shop_delete() -> void:
	for c in shop_delete_list.get_children():
		c.queue_free()
	var deck: Array = Game.get_full_deck()
	var del_price: int = Game.current_delete_price()
	shop_delete_list.add_child(UF.label("当前删卡价: ¥%d (每删 1 张 +¥1000)" % del_price, 12, UF.COL_TEXT_DIM))
	for i in range(deck.size()):
		var card: Card = deck[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		shop_delete_list.add_child(row)
		row.add_child(UF.label(card.name, 13, UF.COL_TEXT))
		row.add_child(UF.label("[%s]" % card.description, 11, UF.COL_TEXT_DIM))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		row.add_child(UF.label("¥%d" % del_price, 12, UF.COL_GOLD))
		var idx_capture: int = i
		var btn := UF.button("删除", UF.COL_DOWN, 12)
		btn.disabled = (Game.cash < del_price) or (deck.size() <= 1)
		btn.pressed.connect(func(): Game.shop_delete_card(idx_capture))
		row.add_child(btn)


func _make_card_preview(card: Card, w: float, h: float) -> Control:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(w, h)
	var col: Color = UF.kind_color(card.kind)
	var sb := StyleBoxFlat.new()
	sb.bg_color = UF.COL_PANEL
	sb.border_color = col
	sb.border_width_top = 6
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	box.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	box.add_child(v)
	v.add_child(UF.label(card.name, 12, UF.COL_TEXT))
	v.add_child(UF.label("耗 %d" % card.cost, 10, col))
	var d := UF.label(card.description, 10, UF.COL_TEXT_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(d)
	return box


func _name_for_effect(eid: String) -> String:
	var tmp: Card = CardDatabase.make_by_effect(eid, "_preview")
	return tmp.name
