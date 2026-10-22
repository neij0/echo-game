class_name PlayerStatus
extends VBoxContainer
## One player's HUD block: depth, the health segments (HealthSegments), the
## world's pressure meter (Oxygen in the Ocean) and its low warning, and the
## distress pulse hint while a player who has one (the Echo) is downed. Created by Hud for every registered player
## (builds its UI in code). The meter's name and colour come from the WorldConfig.

@export var bar_size: Vector2 = Vector2(300.0, 18.0)
@export var low_color: Color = Color(1.0, 0.2, 0.15)
@export var bar_background_color: Color = Color(0.1, 0.12, 0.18, 0.85)
## Warning label blinks this many times per second.
@export var warning_blink_speed: float = 2.0
@export var distress_ready_color: Color = Color(0.55, 0.95, 1.0)
@export var distress_cooldown_color: Color = Color(0.5, 0.6, 0.7)

var player: Player
var level_builder: LevelBuilder
var pressure_color: Color = Color(0.35, 0.8, 1.0)

var _depth_label: Label
var _health_segments: HealthSegments
var _pressure_bar: ProgressBar
var _fill_style: StyleBoxFlat
var _warning_label: Label
var _distress_label: Label
var _distress: DistressPulse
var _time: float = 0.0


func setup(target_player: Player, target_level_builder: LevelBuilder, world: WorldConfig) -> void:
	player = target_player
	level_builder = target_level_builder
	if world:
		pressure_color = world.pressure_color


func _ready() -> void:
	_depth_label = Label.new()
	add_child(_depth_label)

	_health_segments = HealthSegments.new()
	_health_segments.setup(player.health)
	add_child(_health_segments)

	_pressure_bar = ProgressBar.new()
	_pressure_bar.custom_minimum_size = bar_size
	_pressure_bar.show_percentage = false
	_pressure_bar.max_value = 1.0
	_fill_style = StyleBoxFlat.new()
	_fill_style.bg_color = pressure_color
	_pressure_bar.add_theme_stylebox_override("fill", _fill_style)
	var background := StyleBoxFlat.new()
	background.bg_color = bar_background_color
	_pressure_bar.add_theme_stylebox_override("background", background)
	add_child(_pressure_bar)

	_warning_label = Label.new()
	_warning_label.add_theme_color_override("font_color", low_color)
	add_child(_warning_label)

	_distress = player.get_node_or_null("DistressPulse") as DistressPulse
	_distress_label = Label.new()
	_distress_label.visible = false
	add_child(_distress_label)


func _process(delta: float) -> void:
	if player == null:
		return
	_time += delta
	var depth: float = level_builder.depth_at(player.global_position.y) if level_builder else 0.0
	var pressure: PlayerPressure = player.pressure
	var ratio: float = pressure.get_ratio()
	var downed: String = "   DOWNED" if player.health.is_downed else ""
	_depth_label.text = "P%d %s   Depth: %d m   %s: %d%%%s" % [
		player.player_number, player.display_name, roundi(depth), pressure.pressure_name, roundi(ratio * 100.0), downed,
	]
	_pressure_bar.value = ratio
	var low: bool = pressure.is_low()
	_fill_style.bg_color = low_color if low else pressure_color
	_warning_label.text = "LOW %s" % pressure.pressure_name.to_upper()
	_warning_label.visible = low and fmod(_time * warning_blink_speed, 1.0) < 0.5
	_update_distress_hint()


func _update_distress_hint() -> void:
	_distress_label.visible = _distress != null and player.health.is_downed
	if not _distress_label.visible:
		return
	if _distress.is_ready():
		_distress_label.text = Game.text("distress_ready")
		_distress_label.add_theme_color_override("font_color", distress_ready_color)
	else:
		_distress_label.text = Game.text("distress_cooldown") % _distress.cooldown_left
		_distress_label.add_theme_color_override("font_color", distress_cooldown_color)
