# 《不要怕，是技术性调整！》交易界面 - 阶段3 最小可运行版
# 全部用 Control 节点动态生成, 不依赖任何美术切图; 跑通 Game 信号驱动的回合 UI 即可.
extends Control

const Card = preload("res://scripts/card.gd")
const CardDatabase = preload("res://scripts/card_database.gd")

# ===== 配色 =====
const COL_BG: Color = Color("#0d1b2a")
const COL_PANEL: Color = Color("#1b2a41")
const COL_PANEL_LIGHT: Color = Color("#26395a")
const COL_BORDER: Color = Color("#3a4a6a")
const COL_TEXT: Color = Color("#ffffff")
const COL_TEXT_DIM: Color = Color("#9aa7c0")
const COL_GOLD: Color = Color("#ffd166")
const COL_UP: Color = Color("#06d6a0")
const COL_DOWN: Color = Color("#ef476f")
const COL_BLUE: Color = Color("#118ab2")
const COL_GREEN: Color = Color("#06d6a0")
const COL_YELLOW: Color = Color("#ffd166")
const COL_RED: Color = Color("#ef476f")
const COL_HIGHLIGHT: Color = Color("#ffae42")
const COL_AP_ON: Color = Color("#5cd5ff")
const COL_AP_OFF: Color = Color("#33425c")
const COL_BULL: Color = Color("#06d6a0")
const COL_BEAR: Color = Color("#ef476f")

# ===== 节点引用 (顶部) =====
var lbl_day: Label
var lbl_turn: Label
var lbl_price_top: Label
var btn_emotion: Button
var btn_event: Button
var btn_pause: Button
var btn_play: Button
var btn_ff: Button

# ===== 左侧四色金钱柱 =====
var money_bar_marker: ColorRect

# ===== 右侧目标进度条 (竖向, 在数据面板右侧 40px 槽) =====
var money_target_bg: ColorRect       # 黑色背景
var money_target_fill: ColorRect     # 黄色填充 (底部向上)
var money_target_max_h: float = 378.0
var money_target_bottom_y: float = 0.0
var money_target_max_w: float = 0.0  # 已废弃, 保留占位
var lbl_money_target: Label          # 已废弃, 防引用
var lbl_money_progress: Label        # 显示百分比 (竖条下方)

# ===== 行动力费用条 =====
var lbl_card_cost_hint: Label

# ===== 中央 K 线区 =====
var k_chart: Control

# ===== 右侧数据面板 =====
var lbl_stock_price: Label
var lbl_stock_change: Label
var lbl_cash: Label
var lbl_shares: Label
var lbl_holding_value: Label
var lbl_pnl: Label
var lbl_pnl_pct: Label
var lbl_total_assets: Label
var lbl_target: Label

# ===== 情绪显示 (移到顶栏) =====
var lbl_bull: Label
var lbl_bear: Label
var lbl_emotion_state: Label

# ===== 底部操作区 =====
var lbl_action_points: Label
var hand_box: HBoxContainer
var btn_end_turn: Button
var lbl_draw_pile: Label
var lbl_discard_pile: Label

# ===== 玩家 / 商战对手占位 =====
var lbl_player_cash: Label
var enemy_panel: Control
var lbl_enemy_status: Label

# ===== 日志 / 弹幕 =====
var log_text: RichTextLabel

# ===== 关卡结束面板 =====
var end_panel: PanelContainer
var lbl_end_title: Label
var lbl_end_detail: Label
var btn_end_restart: Button

# ===== 商店面板 =====
var shop_overlay: Control
var lbl_shop_day: Label
var lbl_shop_cash: Label
var lbl_shop_summary: Label
var lbl_shop_deck_preview: RichTextLabel
var shop_tabs_container: TabContainer
var shop_buy_grid: HBoxContainer
var shop_upgrade_list: VBoxContainer
var shop_delete_list: VBoxContainer
var btn_leave_shop: Button


func _ready() -> void:
	custom_minimum_size = Vector2(1280, 720)
	anchor_right = 1.0
	anchor_bottom = 1.0
	_build_ui()
	# 接 Game 信号
	Game.state_changed.connect(_refresh_state)
	Game.hand_changed.connect(_refresh_hand)
	Game.log_message.connect(_append_log)
	Game.turn_started.connect(_on_turn_started)
	Game.turn_ended.connect(_on_turn_ended)
	Game.day_started.connect(_on_day_started)
	Game.day_ended.connect(_on_day_ended)
	Game.candle_committed.connect(_on_candle_committed)
	Game.intraday_updated.connect(_on_intraday_updated)
	Game.level_finished.connect(_on_level_finished)
	Game.shop_entered.connect(_on_shop_entered)
	Game.shop_changed.connect(_refresh_shop)
	Game.phase_changed.connect(_on_phase_changed)
	# 启动新一关
	Game.new_level()


# ============================================================
# UI 构建
# ============================================================
func _build_ui() -> void:
	# 背景
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)
	_build_top_bar()
	_build_left_money_bar()
	_build_chart_area()
	_build_right_panel()
	_build_emotion_bar()
	_build_bottom_area()
	_build_log_overlay()
	_build_end_dialog()
	_build_shop_overlay()


func _build_top_bar() -> void:
	var bar := _make_panel(Vector2(8, 8), Vector2(1264, 36))
	var hb := HBoxContainer.new()
	hb.position = Vector2(12, 6)
	hb.size = Vector2(1240, 24)
	hb.add_theme_constant_override("separation", 14)
	bar.add_child(hb)

	lbl_day = _label("第 1 / 5 天 (周一)", 13, COL_TEXT)
	hb.add_child(lbl_day)
	hb.add_child(_sep_v())
	lbl_turn = _label("第 1 / 10 回合", 13, COL_TEXT)
	hb.add_child(lbl_turn)
	hb.add_child(_sep_v())
	lbl_price_top = _label("¥100.00", 14, COL_GOLD)
	hb.add_child(lbl_price_top)
	hb.add_child(_sep_v())
	# 顶栏情绪显示 (取代底部独立情绪条)
	lbl_bull = _label("上涨 50", 12, COL_BULL)
	hb.add_child(lbl_bull)
	var slash := _label("/", 12, COL_TEXT_DIM)
	hb.add_child(slash)
	lbl_bear = _label("50 下跌", 12, COL_BEAR)
	hb.add_child(lbl_bear)
	lbl_emotion_state = _label("· 偏多", 11, COL_GOLD)
	hb.add_child(lbl_emotion_state)

	# spacer
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer)

	btn_emotion = _button("情绪详情", COL_GOLD, 11)
	btn_emotion.custom_minimum_size = Vector2(76, 24)
	hb.add_child(btn_emotion)
	btn_event = _button("突发事件", COL_GOLD, 11)
	btn_event.custom_minimum_size = Vector2(76, 24)
	hb.add_child(btn_event)
	btn_pause = _button("⏸", COL_TEXT_DIM, 11)
	btn_pause.custom_minimum_size = Vector2(28, 24)
	hb.add_child(btn_pause)
	btn_play = _button("▶", COL_TEXT_DIM, 11)
	btn_play.custom_minimum_size = Vector2(28, 24)
	hb.add_child(btn_play)
	btn_ff = _button("⏩", COL_TEXT_DIM, 11)
	btn_ff.custom_minimum_size = Vector2(28, 24)
	hb.add_child(btn_ff)


func _build_left_money_bar() -> void:
	# 仅四色金钱柱 + 现金 marker. 目标进度条已移到右侧数据面板.
	var panel := _make_panel(Vector2(8, 52), Vector2(56, 460))
	var lbl := _label("现金", 11, COL_TEXT_DIM)
	lbl.position = Vector2(8, 4)
	panel.add_child(lbl)
	# 四色段 (从顶到底: 蓝 / 绿 / 黄 / 红)
	var rect_y_start: float = 20.0
	var bar_h: float = 432.0
	var seg_h: float = bar_h / 4.0
	var seg_w: float = 28.0
	var seg_x: float = 14.0
	var colors: Array = [COL_BLUE, COL_GREEN, COL_YELLOW, COL_RED]
	for i in range(4):
		var seg := ColorRect.new()
		seg.color = colors[i]
		seg.position = Vector2(seg_x, rect_y_start + float(i) * seg_h)
		seg.size = Vector2(seg_w, seg_h - 2.0)
		panel.add_child(seg)
	# 当前现金 marker (横线)
	money_bar_marker = ColorRect.new()
	money_bar_marker.color = COL_TEXT
	money_bar_marker.size = Vector2(seg_w + 8, 2)
	money_bar_marker.position = Vector2(seg_x - 4, rect_y_start)
	panel.add_child(money_bar_marker)


func _build_chart_area() -> void:
	var panel := _make_panel(Vector2(72, 52), Vector2(820, 412))
	# 标题
	var title := _label("价格图表  (上: 回合K · 下: 分时K)", 11, COL_TEXT_DIM)
	title.position = Vector2(10, 4)
	panel.add_child(title)
	# 绘图区
	k_chart = Control.new()
	k_chart.position = Vector2(10, 22)
	k_chart.size = Vector2(800, 384)
	k_chart.draw.connect(_on_draw_chart)
	panel.add_child(k_chart)


func _build_right_panel() -> void:
	# 数据面板 372×460. 文字区收窄到左 308 宽, 右边留 40 宽给竖向目标进度条.
	var panel := _make_panel(Vector2(900, 52), Vector2(372, 460))
	var vb := VBoxContainer.new()
	vb.position = Vector2(12, 8)
	vb.size = Vector2(308, 444)
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)

	# 股价 (主大字, 单独一行避免百分比挤压)
	vb.add_child(_label("股价 · 飞港工业", 10, COL_TEXT_DIM))
	lbl_stock_price = _label("¥100.00", 20, COL_TEXT)
	vb.add_child(lbl_stock_price)
	lbl_stock_change = _label("+0.00% (开盘 ¥100)", 11, COL_TEXT_DIM)
	vb.add_child(lbl_stock_change)
	vb.add_child(_h_sep())

	# 现金
	vb.add_child(_label("现金", 10, COL_TEXT_DIM))
	lbl_cash = _label("¥100,000", 16, COL_GOLD)
	vb.add_child(lbl_cash)
	vb.add_child(_h_sep())

	# 持仓: 股数 + 市值 分两行
	vb.add_child(_label("持仓", 10, COL_TEXT_DIM))
	lbl_shares = _label("0 股", 13, COL_TEXT)
	vb.add_child(lbl_shares)
	lbl_holding_value = _label("市值 ¥0", 11, COL_TEXT_DIM)
	vb.add_child(lbl_holding_value)
	vb.add_child(_h_sep())

	# 总盈亏: 金额 + 百分比 分两行
	vb.add_child(_label("总盈亏", 10, COL_TEXT_DIM))
	lbl_pnl = _label("¥0", 13, COL_TEXT)
	vb.add_child(lbl_pnl)
	lbl_pnl_pct = _label("0.0%", 11, COL_TEXT_DIM)
	vb.add_child(lbl_pnl_pct)
	vb.add_child(_h_sep())

	# 总资产 + 目标进度条 (横向 ColorRect)
	vb.add_child(_label("总资产", 10, COL_TEXT_DIM))
	lbl_total_assets = _label("¥100,000", 14, COL_TEXT)
	vb.add_child(lbl_total_assets)
	lbl_target = _label("目标 ¥120K  ·  0%", 11, COL_TEXT_DIM)
	vb.add_child(lbl_target)
	# 竖向目标进度条 (放在 panel 右侧 40px 留白槽; 黑底 + 底部向上的黄色填充)
	# panel 内坐标: x=332 (panel 宽 372 - 40 槽)
	var bar_x: float = 336.0
	var bar_y: float = 24.0
	var bar_w_v: float = 24.0
	var bar_h_v: float = 380.0
	money_target_max_h = bar_h_v - 2.0
	money_target_bottom_y = bar_y + 1.0 + money_target_max_h
	# 顶部 "目标" 文字
	var lbl_t_title := _label("目标", 10, COL_TEXT_DIM)
	lbl_t_title.position = Vector2(332, 8)
	lbl_t_title.size = Vector2(32, 14)
	lbl_t_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(lbl_t_title)
	# 金色外框
	var bar_border_v := ColorRect.new()
	bar_border_v.color = COL_GOLD
	bar_border_v.position = Vector2(bar_x - 1, bar_y)
	bar_border_v.size = Vector2(bar_w_v + 2, bar_h_v)
	panel.add_child(bar_border_v)
	# 黑色背景 (代表"还差")
	money_target_bg = ColorRect.new()
	money_target_bg.color = Color.BLACK
	money_target_bg.position = Vector2(bar_x, bar_y + 1)
	money_target_bg.size = Vector2(bar_w_v, money_target_max_h)
	panel.add_child(money_target_bg)
	# 黄色填充 (从底向上)
	money_target_fill = ColorRect.new()
	money_target_fill.color = COL_GOLD
	money_target_fill.position = Vector2(bar_x, money_target_bottom_y)
	money_target_fill.size = Vector2(bar_w_v, 0.0)
	panel.add_child(money_target_fill)
	# 底部 "¥120K" + 百分比
	var lbl_t_value := _label("¥120K", 11, COL_GOLD)
	lbl_t_value.position = Vector2(332, bar_y + bar_h_v + 4)
	lbl_t_value.size = Vector2(32, 14)
	lbl_t_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(lbl_t_value)
	lbl_money_progress = _label("0%", 12, COL_TEXT)
	lbl_money_progress.position = Vector2(332, bar_y + bar_h_v + 20)
	lbl_money_progress.size = Vector2(32, 14)
	lbl_money_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(lbl_money_progress)


func _build_emotion_bar() -> void:
	# 原情绪条已搬到顶栏; 此区改为"行动力 / 费用提示条"
	# (信号变量名 emotion_bull_bar / lbl_bull / lbl_bear 已被顶栏复用)
	var panel := _make_panel(Vector2(72, 472), Vector2(820, 28))
	# 左侧: 大字行动力
	var hb := HBoxContainer.new()
	hb.position = Vector2(12, 4)
	hb.size = Vector2(796, 20)
	hb.add_theme_constant_override("separation", 16)
	panel.add_child(hb)
	lbl_action_points = _label("行动力 3 / 3   ● ● ●", 14, COL_AP_ON)
	hb.add_child(lbl_action_points)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sp)
	# 右侧: 选中/悬停的卡牌费用提示 (没有选中就显示 "—")
	lbl_card_cost_hint = _label("选中卡牌查看费用", 12, COL_TEXT_DIM)
	hb.add_child(lbl_card_cost_hint)


func _build_bottom_area() -> void:
	# 底部 4 列布局 (y=508..712, h=204)
	# 列宽分配: 对手 8-176(168) / 手牌 184-936(752) / 行动+结束 944-1080(136) / 玩家 1088-1272(184)
	# 左列 - 商战对手
	enemy_panel = _make_panel(Vector2(8, 508), Vector2(168, 204))
	var ev := VBoxContainer.new()
	ev.position = Vector2(10, 10)
	ev.size = Vector2(148, 184)
	ev.add_theme_constant_override("separation", 4)
	enemy_panel.add_child(ev)
	ev.add_child(_label("商战对手", 11, COL_TEXT_DIM))
	var avatar_e := ColorRect.new()
	avatar_e.color = COL_PANEL_LIGHT
	avatar_e.custom_minimum_size = Vector2(64, 64)
	ev.add_child(avatar_e)
	lbl_enemy_status = _label("未出现", 11, COL_TEXT_DIM)
	ev.add_child(lbl_enemy_status)
	var btn_enemy_deck := _button("对手牌组", COL_TEXT_DIM, 10)
	btn_enemy_deck.disabled = true
	ev.add_child(btn_enemy_deck)

	# 中列 - 手牌 (左 56px 抽牌堆 / 中央 ~620px 手牌 / 右 56px 弃牌堆)
	var hand_panel := _make_panel(Vector2(184, 508), Vector2(752, 204))
	# 抽牌堆 - 左侧, 缩小到 48×64 卡背 + 下方数字
	var draw_pile_panel := Panel.new()
	draw_pile_panel.position = Vector2(8, 24)
	draw_pile_panel.size = Vector2(48, 64)
	var sb_draw := StyleBoxFlat.new()
	sb_draw.bg_color = COL_PANEL_LIGHT
	sb_draw.border_color = COL_GOLD
	sb_draw.border_width_left = 2
	sb_draw.border_width_right = 2
	sb_draw.border_width_top = 2
	sb_draw.border_width_bottom = 2
	sb_draw.corner_radius_top_left = 4
	sb_draw.corner_radius_top_right = 4
	sb_draw.corner_radius_bottom_left = 4
	sb_draw.corner_radius_bottom_right = 4
	draw_pile_panel.add_theme_stylebox_override("panel", sb_draw)
	hand_panel.add_child(draw_pile_panel)
	# 卡背中央数字
	lbl_draw_pile = _label("0", 22, COL_GOLD)
	lbl_draw_pile.position = Vector2(8, 4)
	lbl_draw_pile.size = Vector2(56, 16)
	lbl_draw_pile.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hand_panel.add_child(lbl_draw_pile)
	var lbl_draw_title := _label("抽牌堆", 10, COL_TEXT_DIM)
	lbl_draw_title.position = Vector2(8, 92)
	lbl_draw_title.size = Vector2(48, 14)
	lbl_draw_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hand_panel.add_child(lbl_draw_title)
	# 卡背中央渲染数字 (覆盖 panel 上方)
	var lbl_draw_num := _label("·", 22, COL_GOLD)  # 占位防 lambda 误删
	lbl_draw_num.visible = false
	hand_panel.add_child(lbl_draw_num)
	# 真正显示在卡背中央的数字: 直接覆盖 draw_pile_panel
	lbl_draw_pile.position = Vector2(8, 38)        # 落在卡背 y=24..88 内, 居中
	lbl_draw_pile.size = Vector2(48, 28)

	# 手牌容器: 用 ScrollContainer 包 HBox
	var hand_scroll := ScrollContainer.new()
	hand_scroll.position = Vector2(64, 8)
	hand_scroll.size = Vector2(624, 188)
	hand_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	hand_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hand_panel.add_child(hand_scroll)
	hand_box = HBoxContainer.new()
	hand_box.alignment = BoxContainer.ALIGNMENT_CENTER
	hand_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hand_box.add_theme_constant_override("separation", 6)
	hand_scroll.add_child(hand_box)

	# 弃牌堆 - 右侧, 同样 48×64
	var discard_pile_panel := Panel.new()
	discard_pile_panel.position = Vector2(696, 24)
	discard_pile_panel.size = Vector2(48, 64)
	var sb_disc := StyleBoxFlat.new()
	sb_disc.bg_color = COL_PANEL_LIGHT
	sb_disc.border_color = COL_TEXT_DIM
	sb_disc.border_width_left = 2
	sb_disc.border_width_right = 2
	sb_disc.border_width_top = 2
	sb_disc.border_width_bottom = 2
	sb_disc.corner_radius_top_left = 4
	sb_disc.corner_radius_top_right = 4
	sb_disc.corner_radius_bottom_left = 4
	sb_disc.corner_radius_bottom_right = 4
	discard_pile_panel.add_theme_stylebox_override("panel", sb_disc)
	hand_panel.add_child(discard_pile_panel)
	lbl_discard_pile = _label("0", 22, COL_TEXT)
	lbl_discard_pile.position = Vector2(696, 38)
	lbl_discard_pile.size = Vector2(48, 28)
	lbl_discard_pile.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hand_panel.add_child(lbl_discard_pile)
	var lbl_disc_title := _label("弃牌堆", 10, COL_TEXT_DIM)
	lbl_disc_title.position = Vector2(696, 92)
	lbl_disc_title.size = Vector2(48, 14)
	lbl_disc_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hand_panel.add_child(lbl_disc_title)

	# 第 3 列 - 独立的"结束回合"按钮列 (944, 508, 136×204)
	var action_panel := _make_panel(Vector2(944, 508), Vector2(136, 204))
	var av := VBoxContainer.new()
	av.position = Vector2(10, 10)
	av.size = Vector2(116, 184)
	av.add_theme_constant_override("separation", 8)
	av.alignment = BoxContainer.ALIGNMENT_CENTER
	action_panel.add_child(av)
	var hint := _label("交易回合", 10, COL_TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	av.add_child(hint)
	btn_end_turn = _button("结束回合\n(空格)", COL_HIGHLIGHT, 13)
	btn_end_turn.custom_minimum_size = Vector2(116, 80)
	btn_end_turn.pressed.connect(_on_end_turn_pressed)
	av.add_child(btn_end_turn)
	var hint2 := _label("(打牌后点)", 10, COL_TEXT_DIM)
	hint2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	av.add_child(hint2)

	# 第 4 列 - 玩家 (1088, 508, 184×204)
	var player_panel := _make_panel(Vector2(1088, 508), Vector2(184, 204))
	var pv := VBoxContainer.new()
	pv.position = Vector2(10, 10)
	pv.size = Vector2(164, 184)
	pv.add_theme_constant_override("separation", 4)
	player_panel.add_child(pv)
	pv.add_child(_label("玩家", 11, COL_TEXT_DIM))
	var avatar_p := ColorRect.new()
	avatar_p.color = COL_PANEL_LIGHT
	avatar_p.custom_minimum_size = Vector2(64, 64)
	pv.add_child(avatar_p)
	lbl_player_cash = _label("¥100,000", 11, COL_GOLD)
	pv.add_child(lbl_player_cash)
	var btn_deck := _button("查看牌组", COL_TEXT_DIM, 10)
	pv.add_child(btn_deck)


func _build_log_overlay() -> void:
	# 阶段3 日志区放在右上角小条, 但用户反馈挤压, 这里直接隐藏.
	# 仍保留节点以满足 _append_log 调用; 需要时改 visible = true.
	log_text = RichTextLabel.new()
	log_text.bbcode_enabled = true
	log_text.scroll_following = true
	log_text.position = Vector2(0, 0)
	log_text.size = Vector2(0, 0)
	log_text.visible = false
	log_text.add_theme_color_override("default_color", COL_TEXT_DIM)
	log_text.add_theme_font_size_override("normal_font_size", 10)
	add_child(log_text)


func _build_end_dialog() -> void:
	end_panel = PanelContainer.new()
	end_panel.position = Vector2(384, 220)
	end_panel.size = Vector2(512, 280)
	end_panel.visible = false
	end_panel.add_theme_stylebox_override("panel", _panel_stylebox(COL_HIGHLIGHT))
	add_child(end_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	end_panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)

	lbl_end_title = _label("关卡结算", 32, COL_TEXT)
	lbl_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl_end_title)

	lbl_end_detail = _label("", 16, COL_TEXT_DIM)
	lbl_end_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_end_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(lbl_end_detail)

	btn_end_restart = _button("再来一关", COL_UP, 18)
	btn_end_restart.custom_minimum_size = Vector2(0, 44)
	btn_end_restart.pressed.connect(func(): end_panel.visible = false; Game.new_level())
	vbox.add_child(btn_end_restart)


# ============================================================
# 商店面板 (覆盖在交易界面之上, 进 SHOP 阶段时 visible)
# ============================================================
func _build_shop_overlay() -> void:
	shop_overlay = Control.new()
	shop_overlay.anchor_right = 1.0
	shop_overlay.anchor_bottom = 1.0
	shop_overlay.visible = false
	add_child(shop_overlay)

	# 半透明遮罩
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.07, 0.13, 0.9)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	shop_overlay.add_child(dim)

	# 主面板
	var panel := PanelContainer.new()
	panel.position = Vector2(40, 24)
	panel.size = Vector2(1200, 672)
	panel.add_theme_stylebox_override("panel", _panel_stylebox(COL_HIGHLIGHT))
	shop_overlay.add_child(panel)

	var root_vb := VBoxContainer.new()
	root_vb.add_theme_constant_override("separation", 8)
	panel.add_child(root_vb)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.remove_child(root_vb)
	panel.add_child(margin)
	margin.add_child(root_vb)

	# 顶栏
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	root_vb.add_child(top)
	top.add_child(_label("盘后商店", 26, COL_HIGHLIGHT))
	top.add_child(_sep_v())
	lbl_shop_day = _label("第 1 / 5 天 结束", 16, COL_TEXT)
	top.add_child(lbl_shop_day)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	top.add_child(_label("当前现金", 12, COL_TEXT_DIM))
	lbl_shop_cash = _label("¥100,000", 22, COL_GOLD)
	top.add_child(lbl_shop_cash)

	root_vb.add_child(_h_sep())

	# 中区: 左 当日结算, 右 牌组预览
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 16)
	root_vb.add_child(mid)
	# 左 当日结算
	var sum_panel := PanelContainer.new()
	sum_panel.add_theme_stylebox_override("panel", _panel_stylebox())
	sum_panel.custom_minimum_size = Vector2(560, 140)
	mid.add_child(sum_panel)
	var sm := MarginContainer.new()
	sm.add_theme_constant_override("margin_left", 12)
	sm.add_theme_constant_override("margin_right", 12)
	sm.add_theme_constant_override("margin_top", 10)
	sm.add_theme_constant_override("margin_bottom", 10)
	sum_panel.add_child(sm)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 4)
	sm.add_child(sv)
	sv.add_child(_label("当日结算", 14, COL_TEXT_DIM))
	lbl_shop_summary = _label("...", 13, COL_TEXT)
	lbl_shop_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sv.add_child(lbl_shop_summary)
	# 右 牌组预览
	var deck_panel := PanelContainer.new()
	deck_panel.add_theme_stylebox_override("panel", _panel_stylebox())
	deck_panel.custom_minimum_size = Vector2(580, 140)
	mid.add_child(deck_panel)
	var dm := MarginContainer.new()
	dm.add_theme_constant_override("margin_left", 12)
	dm.add_theme_constant_override("margin_right", 12)
	dm.add_theme_constant_override("margin_top", 10)
	dm.add_theme_constant_override("margin_bottom", 10)
	deck_panel.add_child(dm)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 4)
	dm.add_child(dv)
	dv.add_child(_label("当前牌组预览", 14, COL_TEXT_DIM))
	lbl_shop_deck_preview = RichTextLabel.new()
	lbl_shop_deck_preview.bbcode_enabled = true
	lbl_shop_deck_preview.fit_content = false
	lbl_shop_deck_preview.scroll_active = true
	lbl_shop_deck_preview.custom_minimum_size = Vector2(0, 100)
	lbl_shop_deck_preview.add_theme_font_size_override("normal_font_size", 12)
	dv.add_child(lbl_shop_deck_preview)

	# 标签页: 买卡 / 升级 / 删卡
	shop_tabs_container = TabContainer.new()
	shop_tabs_container.custom_minimum_size = Vector2(0, 360)
	shop_tabs_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shop_tabs_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vb.add_child(shop_tabs_container)

	# Tab 1 买卡
	var buy_panel := ScrollContainer.new()
	buy_panel.name = "买卡"
	shop_buy_grid = HBoxContainer.new()
	shop_buy_grid.add_theme_constant_override("separation", 12)
	buy_panel.add_child(shop_buy_grid)
	shop_tabs_container.add_child(buy_panel)

	# Tab 2 升级
	var up_panel := ScrollContainer.new()
	up_panel.name = "升级"
	shop_upgrade_list = VBoxContainer.new()
	shop_upgrade_list.add_theme_constant_override("separation", 4)
	shop_upgrade_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	up_panel.add_child(shop_upgrade_list)
	shop_tabs_container.add_child(up_panel)

	# Tab 3 删卡
	var del_panel := ScrollContainer.new()
	del_panel.name = "删卡"
	shop_delete_list = VBoxContainer.new()
	shop_delete_list.add_theme_constant_override("separation", 4)
	shop_delete_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	del_panel.add_child(shop_delete_list)
	shop_tabs_container.add_child(del_panel)

	# 底部按钮
	var bot := HBoxContainer.new()
	bot.alignment = BoxContainer.ALIGNMENT_END
	root_vb.add_child(bot)
	btn_leave_shop = _button("离开商店, 进入下一天 →", COL_HIGHLIGHT, 16)
	btn_leave_shop.custom_minimum_size = Vector2(280, 44)
	btn_leave_shop.pressed.connect(_on_leave_shop_pressed)
	bot.add_child(btn_leave_shop)


func _on_shop_entered(_d: int) -> void:
	shop_overlay.visible = true
	_refresh_shop()


func _on_phase_changed(p: int) -> void:
	# 离开 SHOP 阶段时收起 overlay
	if p != Game.Phase.SHOP and shop_overlay != null:
		shop_overlay.visible = false


func _on_leave_shop_pressed() -> void:
	Game.leave_shop_to_next_day()


func _refresh_shop() -> void:
	if not shop_overlay.visible: return
	# 顶部
	lbl_shop_day.text = "第 %d / %d 天 结束" % [Game.day, Game.DAYS_PER_LEVEL]
	lbl_shop_cash.text = "¥%s" % _fmt_money(Game.cash)
	# 当日结算
	var s: Dictionary = Game.day_close_summary
	if s.is_empty():
		lbl_shop_summary.text = "(无)"
	else:
		var pnl: float = s["day_pnl"]
		var pnl_str: String = "%s¥%s" % ["+" if pnl >= 0 else "-", _fmt_money(abs(pnl))]
		var price_pct: float = s["price_change_pct"]
		lbl_shop_summary.text = (
			"开盘 ¥%.2f → 收盘 ¥%.2f (%+.2f%%)\n" +
			"持仓 %d 股, 市值 ¥%s\n" +
			"现金 ¥%s, 总资产 ¥%s\n" +
			"今日盈亏 %s"
		) % [
			s["open_price"], s["close_price"], price_pct,
			int(s["shares"]), _fmt_money(s["holding_value"]),
			_fmt_money(s["cash"]), _fmt_money(s["total_assets"]),
			pnl_str
		]
	# 牌组预览 (按 effect_id 聚合数量)
	var counts: Dictionary = {}
	for c in Game.get_full_deck():
		var k: String = "%s|%s" % [c.name, c.effect_id]
		counts[k] = counts.get(k, 0) + 1
	var lines: Array = []
	for k in counts.keys():
		var name_part: String = (k as String).split("|")[0]
		lines.append("%s × %d" % [name_part, counts[k]])
	lbl_shop_deck_preview.clear()
	lbl_shop_deck_preview.append_text("共 %d 张\n" % Game.get_deck_size())
	for ln in lines:
		lbl_shop_deck_preview.append_text(ln + "\n")

	# 三标签
	_refresh_shop_buy()
	_refresh_shop_upgrade()
	_refresh_shop_delete()

	# 第 5 天后按钮文字变化
	if Game.day >= Game.DAYS_PER_LEVEL:
		btn_leave_shop.text = "结束本周, 进入最终结算 →"


func _refresh_shop_buy() -> void:
	for c in shop_buy_grid.get_children():
		c.queue_free()
	for i in range(Game.shop_offers.size()):
		var card: Card = Game.shop_offers[i]
		shop_buy_grid.add_child(_make_shop_card_buy(card, i))
	if Game.shop_offers.is_empty():
		var l := _label("(本日商品已全部售出)", 12, COL_TEXT_DIM)
		shop_buy_grid.add_child(l)


func _make_shop_card_buy(card: Card, index: int) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var preview := _make_card_preview(card, 130, 96)
	box.add_child(preview)
	box.add_child(_label("¥%d" % Game.SHOP_BUY_PRICE, 12, COL_GOLD))
	var btn := _button("购买", COL_UP, 13)
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
		row.add_child(_label("%s → %s" % [card.name, _name_for_effect(target_eid)], 13, COL_TEXT))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		row.add_child(_label("¥%d" % Game.SHOP_UPGRADE_PRICE, 12, COL_GOLD))
		var idx_capture: int = i
		var btn := _button("升级", COL_HIGHLIGHT, 12)
		btn.disabled = Game.cash < Game.SHOP_UPGRADE_PRICE
		btn.pressed.connect(func(): Game.shop_upgrade_card(idx_capture))
		row.add_child(btn)
	if not any_upgradable:
		shop_upgrade_list.add_child(_label("(没有可升级的卡)", 12, COL_TEXT_DIM))


func _refresh_shop_delete() -> void:
	for c in shop_delete_list.get_children():
		c.queue_free()
	var deck: Array = Game.get_full_deck()
	var price: int = Game.current_delete_price()
	shop_delete_list.add_child(_label("当前删卡价: ¥%d (每删 1 张 +¥1000)" % price, 12, COL_TEXT_DIM))
	for i in range(deck.size()):
		var card: Card = deck[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		shop_delete_list.add_child(row)
		row.add_child(_label(card.name, 13, COL_TEXT))
		row.add_child(_label("[%s]" % card.description, 11, COL_TEXT_DIM))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		row.add_child(_label("¥%d" % price, 12, COL_GOLD))
		var idx_capture: int = i
		var btn := _button("删除", COL_DOWN, 12)
		btn.disabled = (Game.cash < price) or (deck.size() <= 1)
		btn.pressed.connect(func(): Game.shop_delete_card(idx_capture))
		row.add_child(btn)


func _make_card_preview(card: Card, w: float, h: float) -> Control:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(w, h)
	var col: Color = _kind_color(card.kind)
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
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
	v.add_child(_label(card.name, 12, COL_TEXT))
	v.add_child(_label("耗 %d" % card.cost, 10, col))
	var d := _label(card.description, 10, COL_TEXT_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(d)
	return box


# 给 effect_id 反查显示名 (升级目标用)
func _name_for_effect(eid: String) -> String:
	# 偷懒做法: 临时造一张卡读 name
	var tmp: Card = CardDatabase.make_by_effect(eid, "_preview")
	return tmp.name


# ============================================================
# 信号刷新
# ============================================================
func _refresh_state() -> void:
	# 顶部
	lbl_day.text = "第 %d / %d 天 %s" % [max(Game.day, 1), Game.DAYS_PER_LEVEL, _weekday_name(Game.day)]
	lbl_turn.text = "第 %d / %d 回合" % [max(Game.turn_in_day, 1), Game.TURNS_PER_DAY]
	lbl_price_top.text = "¥%.2f" % Game.price

	# 右侧
	lbl_stock_price.text = "¥%.2f" % Game.price
	var pct: float = (Game.price / Game.INITIAL_PRICE - 1.0) * 100.0
	var arrow := "▲" if pct >= 0 else "▼"
	lbl_stock_change.text = "%s %+.2f%%" % [arrow, pct]
	var price_color := COL_UP if pct >= 0 else COL_DOWN
	lbl_stock_price.add_theme_color_override("font_color", price_color)
	lbl_stock_change.add_theme_color_override("font_color", price_color)

	lbl_cash.text = "¥%s" % _fmt_money(Game.cash)
	lbl_player_cash.text = "¥%s" % _fmt_money(Game.cash)
	lbl_shares.text = "%d 股" % Game.shares
	lbl_holding_value.text = "市值 ¥%s" % _fmt_money(Game.get_holding_value())

	var pnl: float = Game.get_total_assets() - Game.START_CASH
	var pnl_pct: float = pnl / Game.START_CASH * 100.0
	lbl_pnl.text = "%s¥%s" % ["+" if pnl >= 0 else "-", _fmt_money(abs(pnl))]
	lbl_pnl_pct.text = "%+.1f%%" % pnl_pct
	var pnl_color := COL_UP if pnl >= 0 else COL_DOWN
	lbl_pnl.add_theme_color_override("font_color", pnl_color)
	lbl_pnl_pct.add_theme_color_override("font_color", pnl_color)

	lbl_total_assets.text = "¥%s" % _fmt_money(Game.get_total_assets())
	var to_target: float = Game.VICTORY_TARGET - Game.get_total_assets()
	if to_target <= 0:
		lbl_target.text = "目标 ¥%s ✓ 已达成" % _fmt_money(Game.VICTORY_TARGET)
		lbl_target.add_theme_color_override("font_color", COL_UP)
	else:
		lbl_target.text = "目标 ¥%s · 差 ¥%s" % [_fmt_money(Game.VICTORY_TARGET), _fmt_money(to_target)]
		lbl_target.add_theme_color_override("font_color", COL_TEXT_DIM)

	# 顶栏情绪
	lbl_bull.text = "上涨 %d" % Game.bull
	lbl_bear.text = "%d 下跌" % Game.bear
	lbl_emotion_state.text = "· " + Game.emotion_state()

	# 行动力 (数字 + 圆点, 满 3 时高亮)
	lbl_action_points.text = "行动力 %d / %d   %s" % [Game.action_points, Game.ACTION_POINTS_PER_TURN, _ap_dots(Game.action_points)]
	if Game.action_points == Game.ACTION_POINTS_PER_TURN:
		lbl_action_points.add_theme_color_override("font_color", COL_AP_ON)
	elif Game.action_points == 0:
		lbl_action_points.add_theme_color_override("font_color", COL_DOWN)
	else:
		lbl_action_points.add_theme_color_override("font_color", COL_GOLD)

	# 抽弃堆
	lbl_draw_pile.text = "%d" % Game.draw_pile.size()
	lbl_discard_pile.text = "%d" % Game.discard_pile.size()

	# 现金 marker 在四色柱上的位置 (现金区间 0..START_CASH*2 截断)
	var bar_top_y: float = 20.0
	var bar_height: float = 432.0
	var ratio: float = clamp(Game.cash / (Game.START_CASH * 2.0), 0.0, 1.0)
	money_bar_marker.position.y = bar_top_y + (1.0 - ratio) * bar_height - 1.0

	# 目标进度条 (竖向 ColorRect: 黄色 fill 高度 = 总资产/目标 × 最大高, 从底部向上长)
	var prog: float = Game.get_total_assets() / Game.VICTORY_TARGET * 100.0
	var ratio_p: float = clamp(prog / 100.0, 0.0, 1.0)
	var fill_h: float = money_target_max_h * ratio_p
	money_target_fill.size.y = fill_h
	money_target_fill.position.y = money_target_bottom_y - fill_h
	lbl_money_progress.text = "%.0f%%" % clamp(prog, 0.0, 999.0)
	lbl_target.text = "目标 ¥%s  ·  %.0f%%" % [_fmt_money(Game.VICTORY_TARGET), clamp(prog, 0.0, 999.0)]
	if prog >= 100.0:
		lbl_target.add_theme_color_override("font_color", COL_UP)
		lbl_money_progress.add_theme_color_override("font_color", COL_UP)
	else:
		lbl_target.add_theme_color_override("font_color", COL_TEXT_DIM)
		lbl_money_progress.add_theme_color_override("font_color", COL_TEXT)

	# 结束回合按钮
	btn_end_turn.disabled = Game.is_level_over or Game.phase != Game.Phase.PLAY

	# 按 phase / AP 同步手牌按钮 disabled (避免按钮创建时 phase 还在 SETTLE 导致全锁)
	if hand_box != null:
		var children: Array = hand_box.get_children()
		for i in range(min(children.size(), Game.hand.size())):
			var btn := children[i] as Button
			if btn == null: continue
			var c: Card = Game.hand[i]
			btn.disabled = (Game.action_points < c.cost) or (Game.phase != Game.Phase.PLAY) or Game.is_level_over

	if k_chart: k_chart.queue_redraw()


func _refresh_hand() -> void:
	for c in hand_box.get_children():
		c.queue_free()
	for i in range(Game.hand.size()):
		var card: Card = Game.hand[i]
		hand_box.add_child(_make_card_button(card, i))


func _make_card_button(card: Card, index: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(96, 148)
	var col: Color = _kind_color(card.kind)
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = col
	sb.border_width_top = 5
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	b.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = COL_PANEL_LIGHT
	b.add_theme_stylebox_override("hover", hover)
	var disabled := sb.duplicate() as StyleBoxFlat
	disabled.border_color = COL_AP_OFF
	disabled.bg_color = Color("#0a1422")
	b.add_theme_stylebox_override("disabled", disabled)
	b.text = ""
	# 内容
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE)
	v.offset_top = 7
	v.offset_left = 5
	v.offset_right = -5
	v.offset_bottom = -5
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 3)
	b.add_child(v)
	var ln := _label(card.name, 11, COL_TEXT)
	ln.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ln)
	var lc := _label("耗 %d" % card.cost, 10, col)
	lc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(lc)
	var ld := _label(card.description, 9, COL_TEXT_DIM)
	ld.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ld.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ld.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(ld)
	# 出牌
	if Game.action_points < card.cost or Game.phase != Game.Phase.PLAY or Game.is_level_over:
		b.disabled = true
	b.pressed.connect(func(): Game.play_card(index))
	return b


func _kind_color(kind: int) -> Color:
	match kind:
		Card.Kind.BUY:   return COL_UP
		Card.Kind.SELL:  return COL_DOWN
		Card.Kind.SKILL: return COL_HIGHLIGHT
		Card.Kind.EVENT: return COL_GOLD
	return COL_TEXT


# ============================================================
# 信号回调
# ============================================================
func _on_turn_started(_d: int, _t: int) -> void: pass
func _on_turn_ended(_d: int, _t: int) -> void:
	if k_chart: k_chart.queue_redraw()
func _on_day_started(_d: int) -> void: pass
func _on_day_ended(d: int) -> void:
	# 阶段4: 收盘后 game_state 自动进入 SHOP 阶段, 这里仅打日志
	_append_log("==== 第 %d 天 收盘 ====" % d)
func _on_candle_committed(_t: int) -> void:
	if k_chart: k_chart.queue_redraw()
func _on_intraday_updated() -> void:
	if k_chart: k_chart.queue_redraw()


func _on_end_turn_pressed() -> void:
	Game.end_turn()


# 空格 = 结束回合 (仅在主游戏 PLAY 阶段有效; 商店/结算 弹窗不触发)
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_SPACE:
			if shop_overlay != null and shop_overlay.visible:
				return
			if end_panel != null and end_panel.visible:
				return
			if Game.is_level_over:
				return
			if Game.phase != Game.Phase.PLAY:
				return
			Game.end_turn()
			get_viewport().set_input_as_handled()


func _on_level_finished(victory: bool, final_assets: float) -> void:
	if victory:
		lbl_end_title.text = "胜  利"
		lbl_end_title.add_theme_color_override("font_color", COL_UP)
	else:
		lbl_end_title.text = "失  败"
		lbl_end_title.add_theme_color_override("font_color", COL_DOWN)
	lbl_end_detail.text = "最终资产: ¥%s\n胜利目标: ¥%s" % [_fmt_money(final_assets), _fmt_money(Game.VICTORY_TARGET)]
	end_panel.visible = true


func _append_log(msg: String) -> void:
	if log_text == null: return
	var color := COL_TEXT_DIM
	if msg.begins_with("===="):
		color = COL_HIGHLIGHT
	elif msg.begins_with("---"):
		color = COL_GOLD
	elif msg.begins_with("[胜利]"):
		color = COL_UP
	elif msg.begins_with("[失败]"):
		color = COL_DOWN
	log_text.push_color(color)
	log_text.add_text(msg)
	log_text.pop()
	log_text.newline()


# ============================================================
# K 线绘制 — 上半: 回合 K (蜡烛); 下半: 分时 K (折线)
# ============================================================
func _on_draw_chart() -> void:
	if k_chart == null: return
	var w: float = k_chart.size.x
	var h: float = k_chart.size.y
	var split: float = h * 0.55 - 4.0
	var top := Rect2(0, 0, w, split)
	var bot := Rect2(0, split + 8, w, h - split - 8)
	_draw_section_label(top, "回合 K (本天蜡烛)", COL_GOLD)
	_draw_section_label(bot, "分时 K (本回合)", COL_HIGHLIGHT)
	_draw_daily_candles(top)
	_draw_intraday(bot)


func _draw_section_label(r: Rect2, txt: String, col: Color) -> void:
	k_chart.draw_rect(r, COL_BORDER, false, 1.0)
	k_chart.draw_string(
		ThemeDB.fallback_font, Vector2(r.position.x + 6, r.position.y + 14),
		txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


func _draw_daily_candles(r: Rect2) -> void:
	var draw_x: float = r.position.x + 8
	var draw_y: float = r.position.y + 22
	var draw_w: float = r.size.x - 70
	var draw_h: float = r.size.y - 36

	# 仅显示当天的蜡烛 (10 槽)
	var current_day: int = max(Game.day, 1)
	var todays: Array = []
	for c in Game.candles:
		if c["day"] == current_day:
			todays.append(c)
	# 加入"浮动蜡烛" (本回合还没结算, 但要显示)
	# 浮动蜡烛: 只要本回合有分时数据就显示, 不限阶段
	if not Game.is_level_over and Game.intraday_ticks.size() > 0:
		todays.append({
			"day": current_day,
			"turn_in_day": Game.turn_in_day,
			"open": Game.cur_open,
			"high": Game.cur_high,
			"low":  Game.cur_low,
			"close": Game.price,
			"_floating": true,
		})

	if todays.is_empty():
		k_chart.draw_string(
			ThemeDB.fallback_font, Vector2(r.position.x + 8, r.position.y + r.size.y * 0.55),
			"等待回合结算后生成回合 K...", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_TEXT_DIM)
		return

	# y 轴范围
	var p_min: float = todays[0]["low"]
	var p_max: float = todays[0]["high"]
	for c in todays:
		if c["low"] < p_min: p_min = c["low"]
		if c["high"] > p_max: p_max = c["high"]
	# 包含开盘价基准
	p_min = min(p_min, Game.INITIAL_PRICE)
	p_max = max(p_max, Game.INITIAL_PRICE)
	if p_max - p_min < 1.0:
		p_max += 1.0; p_min -= 1.0
	var pad: float = (p_max - p_min) * 0.1
	p_min -= pad; p_max += pad

	# 基准线
	var base_y: float = draw_y + draw_h - (Game.INITIAL_PRICE - p_min) / (p_max - p_min) * draw_h
	k_chart.draw_dashed_line(
		Vector2(draw_x, base_y), Vector2(draw_x + draw_w, base_y),
		COL_TEXT_DIM, 1.0, 4.0, true)
	k_chart.draw_string(
		ThemeDB.fallback_font, Vector2(draw_x + 2, base_y - 2),
		"¥%.0f" % Game.INITIAL_PRICE, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_TEXT_DIM)

	# 10 槽位
	var slot_w: float = draw_w / float(Game.TURNS_PER_DAY)
	var body_w: float = max(slot_w * 0.65, 6.0)
	for c in todays:
		var t: int = int(c["turn_in_day"])
		var slot_x: float = draw_x + (float(t) - 0.5) * slot_w
		var op: float = float(c["open"])
		var cl: float = float(c["close"])
		var hi: float = float(c["high"])
		var lo: float = float(c["low"])
		var up: bool = cl >= op
		var col := COL_UP if up else COL_DOWN
		var hi_y: float = draw_y + draw_h - (hi - p_min) / (p_max - p_min) * draw_h
		var lo_y: float = draw_y + draw_h - (lo - p_min) / (p_max - p_min) * draw_h
		k_chart.draw_line(Vector2(slot_x, hi_y), Vector2(slot_x, lo_y), col, 1.0)
		var op_y: float = draw_y + draw_h - (op - p_min) / (p_max - p_min) * draw_h
		var cl_y: float = draw_y + draw_h - (cl - p_min) / (p_max - p_min) * draw_h
		var top_y: float = min(op_y, cl_y)
		var body_h: float = max(abs(op_y - cl_y), 1.0)
		var rect2: Rect2 = Rect2(slot_x - body_w * 0.5, top_y, body_w, body_h)
		if c.has("_floating") and c["_floating"]:
			var fade: Color = Color(col.r, col.g, col.b, 0.4)
			k_chart.draw_rect(rect2, fade, true)
			k_chart.draw_rect(rect2, col, false, 1.0)
		else:
			k_chart.draw_rect(rect2, col, true)

	# Y 轴刻度
	for i in range(3):
		var ratio: float = float(i) / 2.0
		var y: float = draw_y + draw_h - ratio * draw_h
		var p: float = p_min + ratio * (p_max - p_min)
		k_chart.draw_string(
			ThemeDB.fallback_font, Vector2(draw_x + draw_w + 4, y + 4),
			"¥%.0f" % p, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_TEXT_DIM)
	# X 轴 1..10
	for tt in range(1, Game.TURNS_PER_DAY + 1):
		var x: float = draw_x + (float(tt) - 0.5) * slot_w
		var lc: Color = COL_HIGHLIGHT if tt == Game.turn_in_day else COL_TEXT_DIM
		k_chart.draw_string(
			ThemeDB.fallback_font, Vector2(x - 4, r.position.y + r.size.y - 2),
			"%d" % tt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, lc)


func _draw_intraday(r: Rect2) -> void:
	var draw_x: float = r.position.x + 8
	var draw_y: float = r.position.y + 22
	var draw_w: float = r.size.x - 70
	var draw_h: float = r.size.y - 30

	# 分时 K 数据: 来自 Game.intraday_candles (每次出牌一根 + 回合末自然波动一根)
	var candles: Array = Game.intraday_candles
	# 固定槽位 (左对齐, 不居中)
	# 估算上限: 行动力 3 + 过牌额外手牌(最多 ~3) + 自然波动 1 ≈ 8; 取 10 留余量
	var slot_count: int = 10
	var slot: float = draw_w / float(slot_count)
	var body_w: float = max(slot * 0.55, 3.0)

	if candles.is_empty():
		# 空状态: 在最左槽位画一根十字线代表"回合开始, 当前价"
		var y: float = draw_y + draw_h * 0.5    # 中线
		var cx: float = draw_x + slot * 0.5
		k_chart.draw_line(Vector2(cx - 4, y), Vector2(cx + 4, y), COL_TEXT_DIM, 1.0)
		k_chart.draw_line(Vector2(cx, y - 3), Vector2(cx, y + 3), COL_TEXT_DIM, 1.0)
		k_chart.draw_string(
			ThemeDB.fallback_font, Vector2(cx + 8, y - 4),
			"¥%.2f (回合开始)" % Game.cur_open, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_TEXT_DIM)
		# Y 轴刻度 (基于 cur_open 上下 ±10%)
		var min_span_e: float = max(Game.cur_open * 0.10, 2.0)
		var p_min_e: float = Game.cur_open - min_span_e * 0.5
		var p_max_e: float = Game.cur_open + min_span_e * 0.5
		for i in range(3):
			var ratio: float = float(i) / 2.0
			var yy: float = draw_y + draw_h - ratio * draw_h
			var pp: float = p_min_e + ratio * (p_max_e - p_min_e)
			k_chart.draw_string(
				ThemeDB.fallback_font, Vector2(draw_x + draw_w + 4, yy + 4),
				"¥%.1f" % pp, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_TEXT_DIM)
		return

	# y 范围: 取所有 candles 的 high/low + cur_open 作参考
	var p_min: float = float(candles[0]["low"])
	var p_max: float = float(candles[0]["high"])
	for c in candles:
		if float(c["low"]) < p_min: p_min = float(c["low"])
		if float(c["high"]) > p_max: p_max = float(c["high"])
	if Game.cur_open < p_min: p_min = Game.cur_open
	if Game.cur_open > p_max: p_max = Game.cur_open
	var min_span: float = max(Game.cur_open * 0.10, 2.0)
	if p_max - p_min < min_span:
		var mid: float = (p_max + p_min) * 0.5
		p_min = mid - min_span * 0.5
		p_max = mid + min_span * 0.5
	var pad: float = (p_max - p_min) * 0.15
	p_min -= pad; p_max += pad

	# 开盘基准虚线
	var base_y: float = draw_y + draw_h - (Game.cur_open - p_min) / (p_max - p_min) * draw_h
	k_chart.draw_dashed_line(
		Vector2(draw_x, base_y), Vector2(draw_x + draw_w, base_y),
		COL_TEXT_DIM, 1.0, 4.0, true)
	k_chart.draw_string(
		ThemeDB.fallback_font, Vector2(draw_x + 2, base_y - 2),
		"开 ¥%.2f" % Game.cur_open, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_TEXT_DIM)

	# 左对齐排布: 每根 K 占一个槽位
	for i in range(candles.size()):
		var c2: Dictionary = candles[i]
		var op: float = float(c2["open"])
		var cl: float = float(c2["close"])
		var hi: float = float(c2["high"])
		var lo: float = float(c2["low"])
		var slot_cx: float = draw_x + (float(i) + 0.5) * slot
		var col: Color
		if cl > op: col = COL_UP
		elif cl < op: col = COL_DOWN
		else: col = COL_TEXT_DIM
		# 影线 (high..low)
		var hi_y: float = draw_y + draw_h - (hi - p_min) / (p_max - p_min) * draw_h
		var lo_y: float = draw_y + draw_h - (lo - p_min) / (p_max - p_min) * draw_h
		k_chart.draw_line(Vector2(slot_cx, hi_y), Vector2(slot_cx, lo_y), col, 1.0)
		# 实体 (open..close)
		var op_y: float = draw_y + draw_h - (op - p_min) / (p_max - p_min) * draw_h
		var cl_y: float = draw_y + draw_h - (cl - p_min) / (p_max - p_min) * draw_h
		var top_y: float = min(op_y, cl_y)
		var body_h: float = max(abs(op_y - cl_y), 1.0)
		# 平 K: 画一条横线代替实体
		if abs(op - cl) < 0.01:
			k_chart.draw_line(
				Vector2(slot_cx - body_w * 0.5, op_y),
				Vector2(slot_cx + body_w * 0.5, op_y),
				col, 2.0)
		else:
			k_chart.draw_rect(
				Rect2(slot_cx - body_w * 0.5, top_y, body_w, body_h),
				col, true)
		# settle (自然波动 K) 加金边强调
		if c2.has("kind") and c2["kind"] == "settle":
			k_chart.draw_rect(
				Rect2(slot_cx - body_w * 0.5 - 1, top_y - 1, body_w + 2, body_h + 2),
				COL_GOLD, false, 1.0)

	# 当前价标注 (右侧)
	var last_price: float = float(candles[candles.size() - 1]["close"])
	var last_y: float = draw_y + draw_h - (last_price - p_min) / (p_max - p_min) * draw_h
	k_chart.draw_string(
		ThemeDB.fallback_font, Vector2(draw_x + draw_w + 4, last_y - 2),
		"¥%.2f" % last_price, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_HIGHLIGHT)

	# Y 轴刻度
	for i in range(3):
		var ratio: float = float(i) / 2.0
		var y: float = draw_y + draw_h - ratio * draw_h
		var p: float = p_min + ratio * (p_max - p_min)
		k_chart.draw_string(
			ThemeDB.fallback_font, Vector2(draw_x + draw_w + 4, y + 4),
			"¥%.1f" % p, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_TEXT_DIM)


# ============================================================
# UI 助手
# ============================================================
func _make_panel(pos: Vector2, sz: Vector2) -> Panel:
	# 使用 Panel (非 Container), 子节点不会被自动 stretch / layout.
	# 这样我们写绝对坐标的子节点 (ColorRect / Label / 嵌套 Panel) 才不会被强制铺满.
	var p := Panel.new()
	p.position = pos
	p.size = sz
	p.add_theme_stylebox_override("panel", _panel_stylebox())
	add_child(p)
	return p


func _panel_stylebox(border: Color = COL_BORDER) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = border
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	return sb


func _label(text: String, font_size: int = 14, color: Color = COL_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, color: Color = COL_TEXT, font_size: int = 14) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", color)
	var n := StyleBoxFlat.new()
	n.bg_color = COL_PANEL
	n.border_color = color
	n.border_width_left = 2
	n.border_width_right = 2
	n.border_width_top = 2
	n.border_width_bottom = 2
	n.corner_radius_top_left = 4
	n.corner_radius_top_right = 4
	n.corner_radius_bottom_left = 4
	n.corner_radius_bottom_right = 4
	b.add_theme_stylebox_override("normal", n)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(color.r, color.g, color.b, 0.18)
	b.add_theme_stylebox_override("hover", h)
	var p := n.duplicate() as StyleBoxFlat
	p.bg_color = Color(color.r, color.g, color.b, 0.32)
	b.add_theme_stylebox_override("pressed", p)
	var d := n.duplicate() as StyleBoxFlat
	d.border_color = COL_AP_OFF
	b.add_theme_stylebox_override("disabled", d)
	return b


func _sep_v() -> Label:
	return _label("|", 16, COL_TEXT_DIM)


func _h_sep() -> HSeparator:
	var s := HSeparator.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_BORDER
	s.add_theme_stylebox_override("separator", sb)
	s.custom_minimum_size = Vector2(0, 2)
	return s


# ============================================================
# 工具
# ============================================================
func _fmt_money(v: float) -> String:
	var n: int = int(round(v))
	var neg: bool = n < 0
	var s: String = str(abs(n))
	var out: String = ""
	var count: int = 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count == 3 and i > 0:
			out = "," + out
			count = 0
	if neg: out = "-" + out
	return out


func _ap_dots(n: int) -> String:
	var on_ := "●"
	var off_ := "○"
	var out := ""
	for i in range(Game.ACTION_POINTS_PER_TURN):
		out += on_ if i < n else off_
		if i < Game.ACTION_POINTS_PER_TURN - 1:
			out += " "
	return out


func _weekday_name(d: int) -> String:
	match d:
		1: return "(周一)"
		2: return "(周二)"
		3: return "(周三)"
		4: return "(周四)"
		5: return "(周五)"
	return ""
