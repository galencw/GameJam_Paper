extends Button

const UF = preload("res://scripts/views/ui_factory.gd")
const Card = preload("res://scripts/card.gd")

@onready var lbl_name: Label = $VBox/LblName
@onready var lbl_cost: Label = $VBox/LblCost
@onready var lbl_desc: Label = $VBox/LblDesc

var _card_index: int = -1


func setup(card: Card, index: int) -> void:
	_card_index = index
	lbl_name.text = card.name
	var col: Color = UF.kind_color(card.kind)
	lbl_cost.text = "耗 %d" % card.cost
	lbl_cost.add_theme_color_override("font_color", col)
	lbl_desc.text = card.description
	var sb := StyleBoxFlat.new()
	sb.bg_color = UF.COL_PANEL
	sb.border_color = col
	sb.border_width_top = 5
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	add_theme_stylebox_override("normal", sb)
	var hover_sb := sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = UF.COL_PANEL_LIGHT
	add_theme_stylebox_override("hover", hover_sb)
	var disabled_sb := sb.duplicate() as StyleBoxFlat
	disabled_sb.border_color = UF.COL_AP_OFF
	disabled_sb.bg_color = Color("#0a1422")
	add_theme_stylebox_override("disabled", disabled_sb)
	disabled = (Game.action_points < card.cost) or (Game.phase != Game.Phase.PLAY) or Game.is_level_over
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)


func _on_pressed() -> void:
	Game.play_card(_card_index)
