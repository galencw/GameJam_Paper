# 《不要怕，是技术性调整！》核心规则数据层 (autoload: /root/Game)
# 阶段2: 仅做规则与状态; UI 在阶段3 接入.
extends Node

const Card = preload("res://scripts/card.gd")
const CardDatabase = preload("res://scripts/card_database.gd")

# ===== 关卡/天/回合 (新手关) =====
const DAYS_PER_LEVEL: int = 5
const TURNS_PER_DAY: int = 10

# ===== 经济参数 =====
const START_CASH: float = 100000.0
const VICTORY_TARGET: float = 120000.0          # 第一关
const INITIAL_PRICE: float = 100.0
const SETTLE_DISCOUNT: float = 0.5              # 周五未卖筹码强制折价
const FIRST_TURN_DRAW: int = 6                  # 第一回合摸 6 张
const TURN_DRAW: int = 2                        # 此后每回合摸 2 张
const HAND_LIMIT: int = 10
const ACTION_POINTS_PER_TURN: int = 3

# ===== 情绪参数 =====
const INITIAL_BULL: int = 50                    # 初始上涨情绪
const EMOTION_TOTAL: int = 100                  # 上涨 + 下跌 = 100

# ===== 自然波动 (clamp 范围 / σ 可调) =====
const NATURAL_DRIFT_CLAMP: float = 0.03         # ±3%
const NATURAL_VOLATILITY_SIGMA_DEFAULT: float = 0.012   # σ 暂取 1.2%, 待数值组确认
var natural_volatility_sigma: float = NATURAL_VOLATILITY_SIGMA_DEFAULT

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
			# 消耗总资金的 10% 买入筹码, 不影响股价
			# "总资金" 在策划描述里没明确是 cash 还是 cash+持仓市值
			# 根据策划"金钱也是生命值"语境, 这里取手头现金的 10%
			var spend: float = cash * 0.10
			_buy_with_cash(spend, false)
		"sell_basic":
			# 卖出当前持仓的 10%, 不影响股价
			var n: int = int(floor(float(shares) * 0.10))
			_sell_shares(n, false)
		"insider_basic":
			apply_price_change(0.03)
		"hype_basic":
			apply_emotion_delta_bull(5)
		# ---- 升级版 ----
		"buy_plus":
			var spend2: float = cash * 0.30
			_buy_with_cash(spend2, true)   # 同时拉升 +3%
		"sell_plus":
			var n2: int = int(floor(float(shares) * 0.30))
			_sell_shares(n2, true)         # 同时压低 -3%
		"insider_plus":
			apply_price_change(0.05)
		"hype_plus":
			apply_emotion_delta_bull(10)
		# ---- 商店占位卡 ----
		"crash_basic":
			apply_price_change(-0.03)
		"panic_basic":
			apply_emotion_delta_bull(-5)
			apply_price_change(-0.02)
		_:
			push_warning("Unknown effect_id: %s" % effect_id)


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
	_track_price()
	_log("  股价 %+.1f%% (¥%.2f → ¥%.2f)" % [eff_rate * 100.0, old_price, price])


# 改变上涨情绪 (下跌情绪自动补足)
func apply_emotion_delta_bull(delta: int) -> void:
	var old: int = bull
	bull = clamp(bull + delta, 0, EMOTION_TOTAL)
	bear = EMOTION_TOTAL - bull
	_log("  情绪 上涨%+d → %d/%d" % [delta, bull, bear])
	if old == bull:
		return


func _buy_with_cash(spend: float, affect_price: bool) -> void:
	if spend <= 0.0 or price <= 0.0:
		return
	if spend > cash:
		spend = cash
	var n: int = int(floor(spend / price))
	if n <= 0:
		_log("  资金过少, 无法成交 1 股")
		return
	var cost: float = float(n) * price
	cash -= cost
	shares += n
	_log("  买入 %d 股 @ ¥%.2f, 花费 ¥%s" % [n, price, _fmt_money(cost)])
	if affect_price:
		apply_price_change(0.03)


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


# 第一回合保底: 至少 1 买 + 1 卖 + 1 技能 (策划 7.2.8)
# 在普通抽牌之后调用, 缺什么就从 draw_pile 里取一张顶上去
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
	_log("==== 第 %d / %d 天 开盘 ¥%.2f ====" % [day, DAYS_PER_LEVEL, day_open_price])
	emit_signal("day_started", day)
	_start_turn()


func _start_turn() -> void:
	turn_in_day += 1
	turn_global += 1
	action_points = ACTION_POINTS_PER_TURN
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
	# 每天第 1 回合摸 6 张 (首日及每天开始时的"起始手牌"); 其它回合摸 2 张.
	# 配合 leave_shop_to_next_day() / new_level() 的"手牌洗回"逻辑, 每天独立发起始手牌.
	if turn_in_day == 1:
		draw_cards(FIRST_TURN_DRAW)
		if turn_global == 1:
			_ensure_first_turn_floor()
			# 保底可能改了手牌, 再发一次 hand_changed
			emit_signal("hand_changed")
	else:
		draw_cards(TURN_DRAW)
	_log("--- 第 %d 天 第 %d 回合 [行动阶段] ---" % [day, turn_in_day])
	emit_signal("turn_started", day, turn_in_day)
	emit_signal("phase_changed", phase)
	emit_signal("intraday_updated")
	# 兜底再发一次 hand_changed, 确保 UI 用最新 phase/AP 重建所有手牌按钮
	emit_signal("hand_changed")
	emit_signal("state_changed")


func _settle_turn() -> void:
	# 1. 自然波动
	var drift: float = _roll_natural_drift()
	var old_price: float = price
	price = max(1.0, price * (1.0 + drift))
	_track_price()
	_log("  自然波动 %+.2f%% (¥%.2f → ¥%.2f)" % [drift * 100.0, old_price, price])
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
# 自然波动 / 情绪倍率
# ===========================================================
func _roll_natural_drift() -> float:
	var mu: float = (float(bull) - 50.0) / 50.0 * NATURAL_DRIFT_CLAMP
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
	if rate >= 0.0:
		# buy direction
		if bull <= 30: return 0.5
		elif bull <= 50: return 0.8
		elif bull <= 70: return 1.5
		else: return 2.0
	else:
		# sell / 砸盘 direction; 看下跌情绪 (=100-bull)
		var bear_v: int = EMOTION_TOTAL - bull
		if bear_v <= 30: return 0.5
		elif bear_v <= 50: return 0.8
		elif bear_v <= 70: return 1.5
		else: return 2.0


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
