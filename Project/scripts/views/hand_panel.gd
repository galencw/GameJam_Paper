extends Panel

const UF = preload("res://scripts/views/ui_factory.gd")
const Card = preload("res://scripts/card.gd")
const CardButtonScene = preload("res://scenes/ui/card_button.tscn")

@onready var hand_box: HBoxContainer = $HandScroll/HandBox
@onready var lbl_draw_pile: Label = $LblDrawPile
@onready var lbl_discard_pile: Label = $LblDiscardPile
@onready var discard_pile_panel: Panel = $DiscardPile


func _ready() -> void:
	add_theme_stylebox_override("panel", UF.panel_stylebox())
	var disc_sb := UF.panel_stylebox(UF.COL_TEXT_DIM)
	discard_pile_panel.add_theme_stylebox_override("panel", disc_sb)
	Game.hand_changed.connect(_refresh_hand)
	Game.state_changed.connect(_refresh_state)


func _refresh_hand() -> void:
	for c in hand_box.get_children():
		c.queue_free()
	for i in range(Game.hand.size()):
		var card: Card = Game.hand[i]
		var btn = CardButtonScene.instantiate()
		hand_box.add_child(btn)
		btn.setup(card, i)


func _refresh_state() -> void:
	lbl_draw_pile.text = "%d" % Game.draw_pile.size()
	lbl_discard_pile.text = "%d" % Game.discard_pile.size()
	if hand_box == null:
		return
	var children: Array = hand_box.get_children()
	for i in range(min(children.size(), Game.hand.size())):
		var btn = children[i] as Button
		if btn == null:
			continue
		var c: Card = Game.hand[i]
		btn.disabled = (Game.action_points < c.cost) or (Game.phase != Game.Phase.PLAY) or Game.is_level_over
