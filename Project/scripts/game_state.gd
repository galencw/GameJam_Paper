# 《不要怕，是技术性调整！》核心规则数据层 (autoload: /root/Game)
# 阶段2: 仅做规则与状态; UI 在阶段3 接入.
extends Node

const Card = preload("res://scripts/card.gd")
const CardDatabase = preload("res://scripts/card_database.gd")
const Event = preload("res://scripts/event.gd")
const EventDatabase = preload("res://scripts/event_database.gd")

# ===== 关卡/天/回合 (新手关) =====
const DAYS_PER_LEVEL: int = 5
const TURNS_PER_DAY: int = 10

# ===== 经济参数 =====
const START_CASH: float = 100000.0
const VICTORY_TARGET: float = 120000.0          # 第一关
const INITIAL_PRICE: float = 100.0
const SETTLE_DISCOUNT: float = 0.5              # 周五未卖筹码强制折价
const FIRST_TURN_DRAW: int = 6                  # 第一回合摸 6 张 (保留常量给旧测试)
const TURN_DRAW: int = 6                        # 每回合统一抽 6 张 (策划改版)
const HAND_LIMIT: int = 10
const ACTION_POINTS_PER_TURN: int = 3

# ===== 情绪参数 =====
const INITIAL_BULL: int = 50                    # 初始上涨情绪
const EMOTION_TOTAL: int = 100                  # 上涨 + 下跌 = 100

# ===== 自然波动 (clamp 范围 / σ 可调) =====
const NATURAL_DRIFT_CLAMP: float = 0.10         # ±10% (策划 4.3)
const NATURAL_VOLATILITY_SIGMA_DEFAULT: float = 0.012   # σ 暂取 1.2%, 待数值组确认
var natural_volatility_sigma: float = NATURAL_VOLATILITY_SIGMA_DEFAULT

# ===== 突发事件 =====
const EVENT_TRIGGER_TURNS: Array = [1, 5]       # 每天开盘后触发的回合编号
# 事件池 / 数据定义已迁出至 scripts/event.gd + scripts/event_database.gd

# ===== 阶段 =====
enum Phase {
	PLAY = 0,    # 行动阶段, 可出牌
	SETTLE = 1,  # 价格 + 情绪结算 (瞬时, 没有玩家输入)
	SHOP = 2,    # 盘后商店 (阶段4 才接入)
	OVER = 3,    # 整局结束
}

# ===== 商店 =====
const SHOP_BUY_PRICE: int = 1000
const SHOP_UPGRADE_PRICE: int = 1000
const SHOP_DELETE_BASE_PRICE: int = 1000
const SHOP_DELETE_PRICE_INCREMENT: int = 1000   # 策划: 后续每次删卡价格+1000

var shop_offers: Array = []                     # 当前商店可购买的卡 (Card 实例数组)
var shop_delete_count: int = 0                  # 累计删卡次数, 用来计算下次删卡价
# 当日摘要 (day_open_price 在 _start_day 时记录, 其余在 _end_day 计算)
var day_open_price: float = INITIAL_PRICE
var day_open_assets: float = START_CASH
var day_close_summary: Dictionary = {}          # {day, open_price, close_price, day_pnl, total_assets, shares, holding_value}

# ===== 信号 =====
signal state_changed
signal hand_changed
signal turn_started(day: int, turn_in_day: int)
signal turn_ended(day: int, turn_in_day: int)
signal day_started(day: int)
signal day_ended(day: int)                       # 一天 10 回合打完, 进商店之前
signal shop_entered(day: int)                    # 已进入商店阶段
signal shop_changed                              # 商店内购买/升级/删卡后刷新
signal phase_changed(phase: int)
signal candle_committed(turn_global: int)        # 回合 K 入库
signal intraday_updated                          # 分时新点
signal level_finished(victory: bool, final_assets: float)
signal log_message(msg: String)
signal event_triggered(event)                    # 突发事件触发: Event 实例 (或 null 表示失效)

# ===== 局内状态 =====
var cash: float = START_CASH
var shares: int = 0
var price: float = INITIAL_PRICE
var bull: int = INITIAL_BULL                    # 上涨情绪
var bear: int = EMOTION_TOTAL - INITIAL_BULL    # 下跌情绪 (= 100 - bull)
var day: int = 0                                # 1..5
var turn_in_day: int = 0                        # 1..10
var turn_global: int = 0                        # 累计回合, 用于 K 线
var phase: int = Phase.PLAY
var action_points: int = 0
var hand: Array = []
var draw_pile: Array = []
var discard_pile: Array = []                    # 等待区 (类似杀戮尖塔), 抽牌堆空时洗回
var is_level_over: bool = false
var current_event: Event = null                 # 当前生效的突发事件 (null = 无)
var banned_effect_ids: Dictionary = {}          # {effect_id: true} ban 列表 (持续到下次事件刷新)
var event_modifiers: Dictionary = {}            # 当前活跃事件 modifier (倍率/限幅/标记)
var event_modifier_dur: int = -1                # >0: 剩余作用回合数; -1: 无限直到下次事件或日切
var triggered_event_ids_this_level: Dictionary = {} # 本关已触发事件 id (一周内同事件不再触发)
var skills_played_this_turn: int = 0            # 本回合已使用的技能牌数 (重点监控用)

# ===== K线 =====
var candles: Array = []                         # 已结算回合 K, 每根 {turn_global, day, turn_in_day, open, high, low, close}
var intraday_ticks: Array[float] = []           # 当前回合分时 (每个价格变化点都 append)
var intraday_candles: Array = []                # 当前回合分时 K 事件序列, 每根 {open, high, low, close, kind}
												# kind: "play" (出牌) / "settle" (回合末自然波动)
var cur_open: float = 0.0
var cur_high: float = 0.0
var cur_low: float = 0.0


# ===========================================================
# 公共 API
# ===========================================================
func new_level() -> void:
	cash = START_CASH
	shares = 0
	price = INITIAL_PRICE
	bull = INITIAL_BULL
	bear = EMOTION_TOTAL - INITIAL_BULL
	day = 0
	turn_in_day = 0
	turn_global = 0
	action_points = 0
	hand.clear()
	discard_pile.clear()
	draw_pile = CardDatabase.build_starter_deck()
	draw_pile.shuffle()
	candles.clear()
	intraday_ticks.clear()
	intraday_candles.clear()
	cur_open = price
	cur_high = price
	cur_low = price
	is_level_over = false
	current_event = null
	banned_effect_ids = {}
	event_modifiers = {}
	event_modifier_dur = -1
	triggered_event_ids_this_level = {}
	skills_played_this_turn = 0
	phase = Phase.PLAY
	shop_offers.clear()
	shop_delete_count = 0
	day_open_price = INITIAL_PRICE
	day_open_assets = START_CASH
	day_close_summary = {}
	_log("新一关开始 - 资金 ¥%s, 目标 ¥%s, 5 天 × 10 回合" % [_fmt_money(START_CASH), _fmt_money(VICTORY_TARGET)])
	emit_signal("state_changed")
	_start_day()


# ----- 出牌 -----
func play_card(index: int) -> bool:
	if is_level_over: return false
	if phase != Phase.PLAY:
		_log("非行动阶段，无法出牌")
		return false
	if index < 0 or index >= hand.size():
		return false
	var c: Card = hand[index]
	if action_points < c.cost:
		_log("行动力不足，无法打出「%s」" % c.name)
		return false
	if banned_effect_ids.has(c.effect_id):
		_log("「%s」被突发事件禁用，无法打出" % c.name)
		return false
	# 重点监控: 本回合技能牌使用上限
	if c.is_skill() and event_modifiers.has("skill_cap_per_turn"):
		var cap_n: int = int(event_modifiers["skill_cap_per_turn"])
		if skills_played_this_turn >= cap_n:
			_log("[重点监控] 本回合已使用 %d 张技能牌, 达到上限" % cap_n)
			return false
	# 资源前置检查 (买入要现金, 卖出要持仓; 不满足直接拒绝, 不扣 AP / 不进弃牌堆)
	if c.effect_id == "buy_basic" or c.effect_id == "buy_plus":
		var need_cash: float = 100.0 * price
		if cash < need_cash:
			_log("现金不足 ¥%.2f, 无法打出「%s」" % [need_cash, c.name])
			return false
	elif c.effect_id == "sell_basic" or c.effect_id == "sell_plus":
		if shares < 100:
			_log("持仓不足 100 股, 无法打出「%s」" % c.name)
			return false
	action_points -= c.cost
	hand.remove_at(index)
	# 记录出牌前价位
	var price_before: float = price
	var hi_before: float = cur_high
	var lo_before: float = cur_low
	_dispatch_effect(c.effect_id)
	# 出牌后这一段时间内 (effect 可能多次调用 apply_price_change), 价格区间 = (hi_before..cur_high, lo_before..cur_low)
	# 计算这次出牌的 high/low: 取 dispatch 期间 cur_high/cur_low 的"增量"
	# 简单做法: high = max(open, close, cur_high in this play), low = min(open, close, cur_low in this play)
	# 由于 cur_high/cur_low 是本回合累计, 此次出牌的实际波动范围 = 出牌前后的 price 区间 + 出牌过程中 _track_price 经过的极值
	# 为不引入新的状态, 这里取 open/close 极值作为该 K 的 high/low (足够分时可视化)
	var price_after: float = price
	var k_open: float = price_before
	var k_close: float = price_after
	var k_high: float = max(k_open, k_close)
	var k_low:  float = min(k_open, k_close)
	# 若出牌中途价格穿越过 open/close 之外 (apply_price_change 多次调用), 取累计极值
	if cur_high > hi_before and cur_high > k_high: k_high = cur_high
	if cur_low  < lo_before and cur_low  < k_low:  k_low  = cur_low
	intraday_candles.append({
		"open":  k_open,
		"close": k_close,
		"high":  k_high,
		"low":   k_low,
		"kind":  "play",
	})
	discard_pile.append(c)
	_log("打出「%s」: %s" % [c.name, c.description])
	if c.is_skill():
		skills_played_this_turn += 1
	emit_signal("intraday_updated")
	emit_signal("hand_changed")
	emit_signal("state_changed")
	return true


# ----- 跳过本回合剩余出牌, 直接结算 -----
func end_turn() -> void:
	if is_level_over: return
	if phase != Phase.PLAY:
		return
	phase = Phase.SETTLE
	emit_signal("phase_changed", phase)
	_settle_turn()


# ===========================================================
# 卡牌效果分发
# ===========================================================
func _dispatch_effect(effect_id: String) -> void:
	match effect_id:
		"buy_basic":
			# 固定买 100 股, 股价 +1% × 涨市 trade_mul
			_buy_shares(100)
			apply_price_change(0.01 * _trade_price_mul(), true)
		"sell_basic":
			# 固定卖 100 股, 股价 -1% × 涨市 trade_mul
			_sell_shares(100, false)
			apply_price_change(-0.01 * _trade_price_mul(), true)
		"insider_basic":
			# 技能牌 → 走情绪倍率 + 火线预期 card_price_up_mul
			apply_price_change(0.03 * _card_price_dir_mul(1.0))
		"hype_basic":
			apply_emotion_delta_bull(5)
		# ---- 升级版 ----
		"buy_plus":
			_buy_shares(100)
			apply_price_change(0.03 * _trade_price_mul(), true)
		"sell_plus":
			_sell_shares(100, false)
			apply_price_change(-0.03 * _trade_price_mul(), true)
		"insider_plus":
			apply_price_change(0.05 * _card_price_dir_mul(1.0))
		"hype_plus":
			apply_emotion_delta_bull(10)
		# ---- 商店占位卡 ----
		"crash_basic":
			apply_price_change(-0.03 * _card_price_dir_mul(-1.0))
		"panic_basic":
			apply_emotion_delta_bull(-5)
			apply_price_change(-0.02 * _card_price_dir_mul(-1.0))
		_:
			push_warning("Unknown effect_id: %s" % effect_id)


# 事件 modifier 查询助手
func _trade_price_mul() -> float:
	return float(event_modifiers.get("card_trade_price_mul", 1.0))


# 技能牌的方向放大倍率: rate>0 → card_price_up_mul; rate<0 → card_price_down_mul
func _card_price_dir_mul(sign_rate: float) -> float:
	if sign_rate >= 0.0:
		return float(event_modifiers.get("card_price_up_mul", 1.0))
	return float(event_modifiers.get("card_price_down_mul", 1.0))


# ===========================================================
# 原子操作
# ===========================================================
# 影响股价 (rate 是相对当前价的百分比变化, 已考虑情绪倍率)
func apply_price_change(rate: float, ignore_emotion_modifier: bool = false) -> void:
	var eff_rate: float = rate
	if not ignore_emotion_modifier:
		eff_rate = rate * _emotion_modifier_for_price(rate)
	var old_price: float = price
	price = max(1.0, price * (1.0 + eff_rate))
	# 涨跌停: 限制相对本回合开盘 cur_open 的累计涨/跌幅 (事件 modifier)
	if event_modifiers.has("cap_drift_up"):
		var cap_up: float = float(event_modifiers["cap_drift_up"])
		var ceil_price: float = cur_open * (1.0 + cap_up)
		if price > ceil_price:
			price = ceil_price
	if event_modifiers.has("cap_drift_down"):
		var cap_dn: float = float(event_modifiers["cap_drift_down"])
		var floor_price: float = cur_open * (1.0 - cap_dn)
		if price < floor_price:
			price = floor_price
	_track_price()
	_log("  股价 %+.1f%% (¥%.2f → ¥%.2f)" % [eff_rate * 100.0, old_price, price])


# 改变上涨情绪 (下跌情绪自动补足); 应用事件 floor/ceiling 锚定
func apply_emotion_delta_bull(delta: int) -> void:
	var old: int = bull
	var new_bull: int = bull + delta
	# 事件锚定 (信仰充值 / 信仰崩塌)
	var floor_v: int = int(event_modifiers.get("emotion_floor", 0))
	var ceil_v: int = int(event_modifiers.get("emotion_ceiling", EMOTION_TOTAL))
	new_bull = clamp(new_bull, floor_v, ceil_v)
	new_bull = clamp(new_bull, 0, EMOTION_TOTAL)
	bull = new_bull
	bear = EMOTION_TOTAL - bull
	_log("  情绪 上涨%+d → %d/%d" % [delta, bull, bear])
	if old == bull:
		return


# 固定股数买入 (买入卡固定 100 股); 不附带额外价格联动, 调用方自己 apply_price_change
func _buy_shares(n: int) -> void:
	if n <= 0 or price <= 0.0:
		return
	var cost: float = float(n) * price
	if cost > cash:
		# 理论上 play_card 已经前置检查, 这里只是兜底
		_log("  资金不足, 无法买入 %d 股" % n)
		return
	cash -= cost
	shares += n
	_log("  买入 %d 股 @ ¥%.2f, 花费 ¥%s" % [n, price, _fmt_money(cost)])


func _sell_shares(n: int, affect_price: bool) -> void:
	if n <= 0:
		_log("  持仓不足, 无法卖出")
		return
	if n > shares: n = shares
	var income: float = float(n) * price
	shares -= n
	cash += income
	_log("  卖出 %d 股 @ ¥%.2f, 收入 ¥%s" % [n, price, _fmt_money(income)])
	if affect_price:
		apply_price_change(-0.03)


# ===========================================================
# 抽牌 / 弃牌
# ===========================================================
func draw_cards(n: int) -> int:
	var got: int = 0
	for i in range(n):
		if hand.size() >= HAND_LIMIT: break
		if draw_pile.is_empty():
			if discard_pile.is_empty(): break
			draw_pile = discard_pile.duplicate()
			discard_pile.clear()
			draw_pile.shuffle()
			_log("  抽牌堆空, 等待区 %d 张洗回" % draw_pile.size())
		hand.append(draw_pile.pop_back())
		got += 1
	if got > 0:
		emit_signal("hand_changed")
	return got


# 首回合保底: 先种 1 买 + 1 卖 + 1 技能 (策划 7.2.8), 再由 _start_turn 补到 6 张
# 避免老版"先抽 6 再补 1"导致首回合 7 张的 bug
func _seed_first_turn_floor() -> void:
	_seed_one_of_kind(Card.Kind.BUY)
	_seed_one_of_kind(Card.Kind.SELL)
	_seed_one_of_kind(Card.Kind.SKILL)


func _seed_one_of_kind(kind: int) -> void:
	if hand.size() >= HAND_LIMIT: return
	# 已有该类型就跳过
	for c in hand:
		if c.kind == kind:
			return
	for i in range(draw_pile.size() - 1, -1, -1):
		if draw_pile[i].kind == kind:
			hand.append(draw_pile[i])
			draw_pile.remove_at(i)
			return


# (旧 API 保留, 仍可被外部 / 测试调用; 内部首回合流程不再使用)
func _ensure_first_turn_floor() -> void:
	var have_buy: bool = false
	var have_sell: bool = false
	var have_skill: bool = false
	for c in hand:
		if c.is_buy(): have_buy = true
		elif c.is_sell(): have_sell = true
		elif c.is_skill(): have_skill = true
	_force_one_into_hand_if_missing(have_buy, Card.Kind.BUY)
	_force_one_into_hand_if_missing(have_sell, Card.Kind.SELL)
	_force_one_into_hand_if_missing(have_skill, Card.Kind.SKILL)


func _force_one_into_hand_if_missing(have: bool, kind: int) -> void:
	if have: return
	if hand.size() >= HAND_LIMIT: return
	for i in range(draw_pile.size() - 1, -1, -1):
		if draw_pile[i].kind == kind:
			hand.append(draw_pile[i])
			draw_pile.remove_at(i)
			return


# ===========================================================
# 内部: 天 / 回合 / 结算
# ===========================================================
func _start_day() -> void:
	day += 1
	turn_in_day = 0
	day_open_price = price
	day_open_assets = get_total_assets()
	# 每天重置市场情绪到中性
	bull = INITIAL_BULL
	bear = EMOTION_TOTAL - INITIAL_BULL
	# 清掉上一天残留的事件 ban / modifier (triggered_event_ids 保留, 整关一周内不重复)
	current_event = null
	banned_effect_ids = {}
	event_modifiers = {}
	event_modifier_dur = -1
	_log("==== 第 %d / %d 天 开盘 ¥%.2f (情绪重置 %d/%d) ====" % [
		day, DAYS_PER_LEVEL, day_open_price, bull, bear])
	emit_signal("day_started", day)
	_start_turn()


func _start_turn() -> void:
	turn_in_day += 1
	turn_global += 1
	action_points = ACTION_POINTS_PER_TURN
	skills_played_this_turn = 0
	# 本回合 OHLC 初始化
	cur_open = price
	cur_high = price
	cur_low = price
	intraday_ticks.clear()
	intraday_ticks.append(price)
	intraday_candles.clear()
	# 阶段必须在抽牌前切回 PLAY, 否则 hand_changed 信号触发 UI 重建按钮时
	# UI 仍认为是 SETTLE 阶段而把所有手牌按钮 disable
	phase = Phase.PLAY
	# 抽牌 (会发 hand_changed)
	# 策划改版: 每回合统一抽 6 张. 首回合 (turn_global == 1) 额外做"1买+1卖+1技能"保底,
	# 实现方式为"先种 1+1+1 → 再补到 6 张", 避免老版"先抽 6 再补 1"导致 7 张的 bug.
	if turn_global == 1:
		_seed_first_turn_floor()
		var need: int = TURN_DRAW - hand.size()
		if need > 0:
			draw_cards(need)
		emit_signal("hand_changed")
	else:
		draw_cards(TURN_DRAW)
	# 突发事件: 每天的 EVENT_TRIGGER_TURNS 回合开盘抽牌后刷新一次
	if EVENT_TRIGGER_TURNS.has(turn_in_day):
		_trigger_random_event()
	# 账户审查: 每回合开始随机冻结 N 张手牌进弃牌堆
	if event_modifiers.has("freeze_per_turn") and not hand.is_empty():
		var fz: int = int(event_modifiers["freeze_per_turn"])
		fz = min(fz, hand.size())
		for i in range(fz):
			if hand.is_empty(): break
			var idx: int = randi() % hand.size()
			var fc: Card = hand[idx]
			hand.remove_at(idx)
			discard_pile.append(fc)
			_log("  [账户审查] 「%s」被冻结进弃牌堆" % fc.name)
		emit_signal("hand_changed")
	# 混乱之日: 每回合 50% AP+1 / 50% AP-1 (含事件触发回合)
	if event_modifiers.get("ap_chaos", false):
		_apply_ap_chaos()
	_log("--- 第 %d 天 第 %d 回合 [行动阶段] ---" % [day, turn_in_day])
	emit_signal("turn_started", day, turn_in_day)
	emit_signal("phase_changed", phase)
	emit_signal("intraday_updated")
	# 兜底再发一次 hand_changed, 确保 UI 用最新 phase/AP 重建所有手牌按钮
	emit_signal("hand_changed")
	emit_signal("state_changed")


func _settle_turn() -> void:
	# 0. 未打出的手牌按 hand[0..n-1] 顺序入弃牌堆 (策划: 先抽到的先进弃牌堆)
	if hand.size() > 0:
		for c in hand:
			discard_pile.append(c)
		_log("  弃 %d 张未打出手牌进弃牌堆" % hand.size())
		hand.clear()
		emit_signal("hand_changed")
	# 1. 自然波动 (μ 由情绪驱动, 不再叠加情绪倍率)
	var drift: float = _roll_natural_drift()
	# 神秘资金: 30% 概率叠加 ±5% 随机波动
	if event_modifiers.get("mystery_active", false):
		if randf() < 0.30:
			var extra: float = 0.05 if randf() < 0.5 else -0.05
			drift += extra
			drift = clamp(drift, -NATURAL_DRIFT_CLAMP - 0.05, NATURAL_DRIFT_CLAMP + 0.05)
			_log("  [神秘资金] 额外波动 %+.0f%%" % (extra * 100.0))
	var old_price: float = price
	apply_price_change(drift, true)
	_log("  回合末自然波动 %+.2f%% → ¥%.2f" % [drift * 100.0, price])
	# 1.5 自然波动作为分时 K 最后一根
	intraday_candles.append({
		"open":  old_price,
		"close": price,
		"high":  max(old_price, price),
		"low":   min(old_price, price),
		"kind":  "settle",
	})
	emit_signal("intraday_updated")
	# 2. 提交一根回合 K
	candles.append({
		"turn_global": turn_global,
		"day": day,
		"turn_in_day": turn_in_day,
		"open": cur_open,
		"high": cur_high,
		"low":  cur_low,
		"close": price,
	})
	emit_signal("candle_committed", turn_global)
	# 3. 触发回合结束
	emit_signal("turn_ended", day, turn_in_day)
	# 3.5 短期事件 modifier 倒计时 (超预期财报 / 财报逆袭等 dur_turns)
	if event_modifier_dur > 0:
		event_modifier_dur -= 1
		if event_modifier_dur == 0:
			if current_event != null:
				_log("  [事件失效] %s 持续效果到期" % current_event.name)
			current_event = null
			banned_effect_ids = {}
			event_modifiers = {}
			event_modifier_dur = -1
			emit_signal("event_triggered", null)
	# 4. 推进
	if turn_in_day >= TURNS_PER_DAY:
		_end_day()
	else:
		_start_turn()


func _end_day() -> void:
	# 一天 10 回合打完
	_log("==== 第 %d 天 收盘 ¥%.2f ====" % [day, price])
	# 当日结算摘要
	day_close_summary = {
		"day": day,
		"open_price": day_open_price,
		"close_price": price,
		"price_change_pct": (price / day_open_price - 1.0) * 100.0,
		"day_pnl": get_total_assets() - day_open_assets,
		"total_assets": get_total_assets(),
		"shares": shares,
		"holding_value": get_holding_value(),
		"cash": cash,
	}
	emit_signal("day_ended", day)
	if day >= DAYS_PER_LEVEL:
		# 第 5 天直接进入最终结算 (策划文档未指定第 5 天后是否还有商店, 暂走结算)
		_settle_level()
	else:
		_enter_shop()


func _enter_shop() -> void:
	phase = Phase.SHOP
	shop_offers = CardDatabase.build_shop_offers(day)   # 用 day 作 seed, 不同天给不同四张
	_log("---- 进入第 %d 天 盘后商店 ----" % day)
	emit_signal("phase_changed", phase)
	emit_signal("shop_entered", day)
	emit_signal("shop_changed")
	emit_signal("state_changed")


# 玩家点 "离开商店" 进入下一天
func leave_shop_to_next_day() -> void:
	if phase != Phase.SHOP:
		return
	if day >= DAYS_PER_LEVEL:
		_settle_level()
		return
	_log("---- 离开商店, 进入第 %d 天 ----" % (day + 1))
	# 进入下一天前清空"等待区"和手牌, 让新一天从牌库重新抽 (策划: 玩家牌组保留)
	# 杀戮尖塔风格: 抽牌堆 = 自己的牌组, 等待区+手牌都洗回去
	for c in hand:
		discard_pile.append(c)
	hand.clear()
	# 把所有牌合并到抽牌堆, 重洗
	for c in discard_pile:
		draw_pile.append(c)
	discard_pile.clear()
	draw_pile.shuffle()
	_start_day()


func _settle_level() -> void:
	# 周五结算: 未卖筹码 × 当前股价 × 50% 强制折算
	var liquidation: float = float(shares) * price * SETTLE_DISCOUNT
	var final_assets: float = cash + liquidation
	is_level_over = true
	phase = Phase.OVER
	_log("==== 关卡结算 ====")
	_log("现金 ¥%s + 持仓折价 (¥%.2f × %d × %.0f%%) = ¥%s" % [
		_fmt_money(cash), price, shares, SETTLE_DISCOUNT * 100.0,
		_fmt_money(final_assets)
	])
	# 落清算金额; 持仓清零便于 UI 显示
	cash = final_assets
	shares = 0
	var victory: bool = final_assets >= VICTORY_TARGET
	if victory:
		_log("[胜利] 达到目标 ¥%s" % _fmt_money(VICTORY_TARGET))
	else:
		_log("[失败] 未达目标 ¥%s" % _fmt_money(VICTORY_TARGET))
	emit_signal("phase_changed", phase)
	emit_signal("state_changed")
	emit_signal("level_finished", victory, final_assets)


# ===========================================================
# 突发事件
# ===========================================================
func _trigger_random_event() -> void:
	var pool: Array = EventDatabase.build_event_pool()
	if pool.is_empty():
		return
	# 清掉上次事件的所有持续效果 (ban / modifier / 时长) — 新事件 = 旧事件全部失效
	banned_effect_ids = {}
	event_modifiers = {}
	event_modifier_dur = -1
	# 一周内同样事件不能触发超过一次: 过滤未触发的 id
	var candidates: Array = []
	for e in pool:
		if not triggered_event_ids_this_level.has(e.id):
			candidates.append(e)
	if candidates.is_empty():
		# 整池都触发过 (后期兜底), 退回完整池等概率抽
		candidates = pool
	var ev: Event = candidates[randi() % candidates.size()]
	current_event = ev
	triggered_event_ids_this_level[ev.id] = true
	_log("[突发事件] %s — %s" % [ev.name, ev.desc])
	_apply_event_effects(ev)
	emit_signal("event_triggered", ev)
	emit_signal("state_changed")


# 把 Event 实例字段落到 state.
# 支持组合: 一条事件可同时含 一次性效果 + 持续修饰 + ban + ap_chaos
func _apply_event_effects(ev: Event) -> void:
	# 1. 持续修饰 (modifiers) — 先写入, 后面的情绪 / 锚定都依赖它
	for k in ev.modifiers.keys():
		event_modifiers[k] = ev.modifiers[k]
	# 2. 短期持续回合 (>0 = 短期, -1 = 持续到下次事件 / 日切)
	event_modifier_dur = ev.dur_turns
	# 3. 情绪锚定
	if ev.emotion_floor >= 0:
		event_modifiers["emotion_floor"] = ev.emotion_floor
		if bull < ev.emotion_floor:
			apply_emotion_delta_bull(ev.emotion_floor - bull)
	if ev.emotion_ceiling >= 0:
		event_modifiers["emotion_ceiling"] = ev.emotion_ceiling
		if bull > ev.emotion_ceiling:
			apply_emotion_delta_bull(ev.emotion_ceiling - bull)
	# 4. 一次性情绪
	if ev.delta_bull != 0:
		apply_emotion_delta_bull(ev.delta_bull)
	# 5. 当回合情绪随机 ±N (意外事件)
	if ev.delta_bull_random > 0:
		apply_emotion_delta_bull(randi_range(-ev.delta_bull_random, ev.delta_bull_random))
	# 6. 一次性股价冲击
	if ev.price_rate != 0.0:
		apply_price_change(ev.price_rate, true)
	# 7. ban
	for eid in ev.banned_effect_ids:
		banned_effect_ids[String(eid)] = true
	# 8. 混乱之日: 写入持续 modifier; 实际 AP 调整由 _start_turn 末尾统一执行
	#    (包括事件触发当回合本身)
	if ev.ap_chaos:
		event_modifiers["ap_chaos"] = true


# 混乱之日: 当前 AP 上做一次 50% +1 / 50% -1 调整 (并 log)
func _apply_ap_chaos() -> void:
	if randf() < 0.5:
		action_points = max(0, action_points - 1)
		_log("  [混乱之日] 行动力 -1 → %d" % action_points)
	else:
		action_points += 1
		_log("  [混乱之日] 行动力 +1 → %d" % action_points)


# ===========================================================
# 自然波动 / 情绪倍率
# ===========================================================
func _roll_natural_drift() -> float:
	# 市场失真: 情绪与价格脱钩, μ 不再受情绪驱动 (退化为零均值高斯游走)
	var mu: float = 0.0
	if not event_modifiers.get("decouple", false):
		mu = (float(bull) - 50.0) / 50.0 * NATURAL_DRIFT_CLAMP
	var x: float = _gaussian(mu, natural_volatility_sigma)
	return clamp(x, -NATURAL_DRIFT_CLAMP, NATURAL_DRIFT_CLAMP)


# Box-Muller 正态分布 (Godot 没内建)
func _gaussian(mean: float, sigma: float) -> float:
	var u1: float = max(randf(), 1e-9)
	var u2: float = randf()
	var z: float = sqrt(-2.0 * log(u1)) * cos(TAU * u2)
	return mean + sigma * z


# 情绪对价格变化的倍率 (策划 3.4 表)
# rate>0 → 买入方向取 "买入上涨倍率"
# rate<0 → 卖出方向取 "卖出下跌倍率"
func _emotion_modifier_for_price(rate: float) -> float:
	# 市场失真: 情绪倍率完全脱钩 → 恒 1.0
	if event_modifiers.get("decouple", false):
		return 1.0
	var base: float
	if rate >= 0.0:
		# buy direction
		if bull <= 30: base = 0.5
		elif bull <= 50: base = 0.8
		elif bull <= 70: base = 1.5
		else: base = 2.0
	else:
		# sell / 砸盘 direction; 看下跌情绪 (=100-bull)
		var bear_v: int = EMOTION_TOTAL - bull
		if bear_v <= 30: base = 0.5
		elif bear_v <= 50: base = 0.8
		elif bear_v <= 70: base = 1.5
		else: base = 2.0
	# 风险警示: 情绪对价格影响 ×0.5
	var mul: float = float(event_modifiers.get("emotion_modifier_mul", 1.0))
	return base * mul


# ===========================================================
# 查询
# ===========================================================
func emotion_state() -> String:
	if bull <= 30: return "极度恐慌"
	elif bull <= 50: return "偏空"
	elif bull <= 70: return "偏多"
	else: return "极度狂热"


func get_holding_value() -> float:
	return float(shares) * price


func get_total_assets() -> float:
	return cash + get_holding_value()


# ===========================================================
# 内部辅助
# ===========================================================
func _track_price() -> void:
	intraday_ticks.append(price)
	if price > cur_high: cur_high = price
	if price < cur_low: cur_low = price
	emit_signal("intraday_updated")


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


func _log(msg: String) -> void:
	emit_signal("log_message", msg)
	print(msg)


# ===========================================================
# 商店 API (阶段4)
# ===========================================================
# 牌组聚合 (玩家拥有的全部卡牌, 包含手牌+抽牌堆+等待区)
func get_full_deck() -> Array:
	var all: Array = []
	for c in hand: all.append(c)
	for c in draw_pile: all.append(c)
	for c in discard_pile: all.append(c)
	return all


func get_deck_size() -> int:
	return hand.size() + draw_pile.size() + discard_pile.size()


# 当前删卡价 (基础 1000 + 已删次数 × 1000)
func current_delete_price() -> int:
	return SHOP_DELETE_BASE_PRICE + shop_delete_count * SHOP_DELETE_PRICE_INCREMENT


# 商店: 买卡 (从 shop_offers 拿一张)
func shop_buy_card(offer_index: int) -> bool:
	if phase != Phase.SHOP: return false
	if offer_index < 0 or offer_index >= shop_offers.size(): return false
	if cash < SHOP_BUY_PRICE:
		_log("现金不足, 无法购买 (需要 ¥%d)" % SHOP_BUY_PRICE)
		return false
	var card: Card = shop_offers[offer_index]
	cash -= SHOP_BUY_PRICE
	# 进入抽牌堆 (杀戮尖塔: 新卡进 deck, 下一次洗牌时随机)
	draw_pile.append(card)
	draw_pile.shuffle()
	shop_offers.remove_at(offer_index)
	_log("[商店] 买入「%s」, 花费 ¥%d" % [card.name, SHOP_BUY_PRICE])
	emit_signal("shop_changed")
	emit_signal("state_changed")
	return true


# 商店: 升级一张牌 (按"全牌组中的索引"操作)
# deck_index: 0..get_deck_size()-1, 顺序与 get_full_deck() 一致
func shop_upgrade_card(deck_index: int) -> bool:
	if phase != Phase.SHOP: return false
	if cash < SHOP_UPGRADE_PRICE:
		_log("现金不足, 无法升级 (需要 ¥%d)" % SHOP_UPGRADE_PRICE)
		return false
	var entry: Dictionary = _locate_in_deck(deck_index)
	if entry.is_empty(): return false
	var card: Card = entry["card"]
	var target_eid: String = CardDatabase.upgrade_target(card.effect_id)
	if target_eid == "":
		_log("「%s」无可升级目标" % card.name)
		return false
	# 替换
	var new_card: Card = CardDatabase.make_by_effect(target_eid, card.id + "_up")
	cash -= SHOP_UPGRADE_PRICE
	entry["pile"][entry["index"]] = new_card
	_log("[商店] 升级「%s」→「%s」, 花费 ¥%d" % [card.name, new_card.name, SHOP_UPGRADE_PRICE])
	emit_signal("hand_changed")
	emit_signal("shop_changed")
	emit_signal("state_changed")
	return true


# 商店: 删卡
func shop_delete_card(deck_index: int) -> bool:
	if phase != Phase.SHOP: return false
	var price: int = current_delete_price()
	if cash < price:
		_log("现金不足, 无法删卡 (需要 ¥%d)" % price)
		return false
	if get_deck_size() <= 1:
		_log("牌组至少保留 1 张")
		return false
	var entry: Dictionary = _locate_in_deck(deck_index)
	if entry.is_empty(): return false
	var card: Card = entry["card"]
	cash -= price
	(entry["pile"] as Array).remove_at(entry["index"])
	shop_delete_count += 1
	_log("[商店] 删除「%s」, 花费 ¥%d, 下次删卡 ¥%d" % [card.name, price, current_delete_price()])
	emit_signal("hand_changed")
	emit_signal("shop_changed")
	emit_signal("state_changed")
	return true


# 把"全牌组索引"映射回具体的 (pile, in-pile index)
# 顺序: hand → draw_pile → discard_pile
func _locate_in_deck(deck_index: int) -> Dictionary:
	if deck_index < 0:
		return {}
	if deck_index < hand.size():
		return {"pile": hand, "index": deck_index, "card": hand[deck_index]}
	var off: int = deck_index - hand.size()
	if off < draw_pile.size():
		return {"pile": draw_pile, "index": off, "card": draw_pile[off]}
	off -= draw_pile.size()
	if off < discard_pile.size():
		return {"pile": discard_pile, "index": off, "card": discard_pile[off]}
	return {}
