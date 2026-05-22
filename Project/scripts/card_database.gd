# 卡牌数据库 - 阶段2/4 共用
# - 阶段2: 提供"新手关 Demo 第一关"的初始 12 张牌
# - 阶段4: 提供商店占位卡池 + 升级映射
# 依据: docs/传奇交易员--新乡2000_完整策划文档.md 附录B
extends RefCounted

const Card = preload("res://scripts/card.gd")

# 12 张初始牌组: 3 买入 + 3 卖出 + 3 内幕消息 + 3 大V吹票
static func build_starter_deck() -> Array:
	var deck: Array = []
	var defs: Array = [
		# [id_prefix, 显示名, kind, cost, 描述, effect_id, 数量]
		["buy",     "买入",       Card.Kind.BUY,   1, "消耗总资金 10% 买入筹码 (按当前股价), 不影响股价", "buy_basic",     3],
		["sell",    "卖出",       Card.Kind.SELL,  1, "卖出当前持仓 10% 换回金钱 (按当前股价), 不影响股价", "sell_basic",    3],
		["insider", "内幕消息",   Card.Kind.SKILL, 1, "直接拉升股价 +3%",                                 "insider_basic", 3],
		["hype",    "大V吹票",    Card.Kind.SKILL, 1, "上涨情绪 +5",                                      "hype_basic",    3],
	]
	for d in defs:
		for i in range(d[6]):
			deck.append(make_by_effect(d[5], "%s_%d" % [d[0], i]))
	return deck


# ---- 工厂: 按 effect_id 造一张新卡 (用 unique_id 区分实例) ----
static func make_by_effect(effect_id: String, unique_id: String) -> Card:
	match effect_id:
		"buy_basic":
			return Card.new(unique_id, "买入", Card.Kind.BUY, 1,
				"消耗总资金 10% 买入筹码 (按当前股价), 不影响股价", "buy_basic")
		"sell_basic":
			return Card.new(unique_id, "卖出", Card.Kind.SELL, 1,
				"卖出当前持仓 10% 换回金钱 (按当前股价), 不影响股价", "sell_basic")
		"insider_basic":
			return Card.new(unique_id, "内幕消息", Card.Kind.SKILL, 1,
				"直接拉升股价 +3%", "insider_basic")
		"hype_basic":
			return Card.new(unique_id, "大V吹票", Card.Kind.SKILL, 1,
				"上涨情绪 +5", "hype_basic")
		# ---- 升级版 ----
		"buy_plus":
			return Card.new(unique_id, "买入+", Card.Kind.BUY, 1,
				"消耗总资金 30% 买入筹码, 同时拉升股价 +3%", "buy_plus")
		"sell_plus":
			return Card.new(unique_id, "卖出+", Card.Kind.SELL, 1,
				"卖出当前持仓 30% 换回金钱, 同时压低股价 -3%", "sell_plus")
		"insider_plus":
			return Card.new(unique_id, "内幕消息+", Card.Kind.SKILL, 1,
				"直接拉升股价 +5%", "insider_plus")
		"hype_plus":
			return Card.new(unique_id, "大V吹票+", Card.Kind.SKILL, 1,
				"上涨情绪 +10", "hype_plus")
		# ---- 商店占位新卡 ----
		"crash_basic":
			return Card.new(unique_id, "打压消息", Card.Kind.SKILL, 1,
				"直接压低股价 -3%", "crash_basic")
		"panic_basic":
			return Card.new(unique_id, "恐慌消息", Card.Kind.SKILL, 1,
				"上涨情绪 -5, 股价 -2%", "panic_basic")
	push_warning("Unknown effect_id in factory: %s" % effect_id)
	return Card.new(unique_id, "未知", Card.Kind.SKILL, 1, "?", effect_id)


# ---- 升级映射: effect_id → 升级版 effect_id; null = 不能升级 ----
static func upgrade_target(effect_id: String) -> String:
	match effect_id:
		"buy_basic":     return "buy_plus"
		"sell_basic":    return "sell_plus"
		"insider_basic": return "insider_plus"
		"hype_basic":    return "hype_plus"
	return ""


# ---- 商店占位卡池: 阶段4 用固定列表 ----
# 返回每次进商店要展示的可购买卡牌; 暂不做随机刷新, 后续再迭代
static func build_shop_offers(seed_index: int) -> Array:
	var pool: Array = [
		"buy_basic", "sell_basic", "insider_basic", "hype_basic",
		"crash_basic", "panic_basic",
	]
	var offers: Array = []
	# 简单按 seed 选 4 张, 不做随机以便测试可重复
	for i in range(4):
		var eid: String = pool[(seed_index + i) % pool.size()]
		offers.append(make_by_effect(eid, "shop_%d_%s" % [seed_index, eid]))
	return offers

