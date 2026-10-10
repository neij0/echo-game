class_name PlayerStatus
extends VBoxContainer
## One player's HUD block: depth, oxygen bar and the low-oxygen warning.
## Created by Hud for every registered player (builds its UI in code).

@export var bar_size: Vector2 = Vector2(300.0, 18.0)
@export var oxygen_color: Color = Color(0.35, 0.8, 1.0)
@export var low_oxygen_color: Color = Color(1.0, 0.2, 0.15)
@export var bar_background_color: Color = Color(0.1, 0.12, 0.18, 0.85)
@export var warning_text: String = "LOW OXYGEN"
## Warning label blinks this many times per second.
@export var warning_blink_speed: float = 2.0

var player: Player
var level: DescentLevel

var _depth_label: Label
var _oxygen_bar: ProgressBar
var _fill_style: StyleBoxFlat
var _warning_label: Label
var _time: float = 0.0


func setup(target_player: Player, target_level: DescentLevel) -> void:
	player = target_player
	level = target_level


func _ready() -> void:
	_depth_label = Label.new()
	add_child(_depth_label)

	_oxygen_bar = ProgressBar.new()
	_oxygen_bar.custom_minimum_size = bar_size
	_oxygen_bar.show_percentage = false
	_oxygen_bar.max_value = 1.0
	_fill_style = StyleBoxFlat.new()
	_fill_style.bg_color = oxygen_color
	_oxygen_bar.add_theme_stylebox_override("fill", _fill_style)
	var background := StyleBoxFlat.new()
	background.bg_color = bar_background_color
	_oxygen_bar.add_theme_stylebox_override("background", background)
	add_child(_oxygen_bar)

	_warning_label = Label.new()
	_warning_label.text = warning_text
	_warning_label.add_theme_color_override("font_color", low_oxygen_color)
	add_child(_warning_label)


func _process(delta: float) -> void:
	if player == null:
		return
	_time += delta
	var depth: float = level.depth_at(player.global_position.y) if level else 0.0
	var ratio: float = player.oxygen.get_ratio()
	_depth_label.text = "P%d   Depth: %d m   Oxygen: %d%%" % [player.player_number, roundi(depth), roundi(ratio * 100.0)]
	_oxygen_bar.value = ratio
	var low: bool = player.oxygen.is_low()
	_fill_style.bg_color = low_oxygen_color if low else oxygen_color
	_warning_label.visible = low and fmod(_time * warning_blink_speed, 1.0) < 0.5
