class_name PlayerStatus
extends VBoxContainer
## One player's HUD block: depth, the health segments (HealthSegments), the
## world's pressure meter (Oxygen in the Ocean) and its low warning, and the
## distress pulse hint while a player who has one (the Echo) is downed, and the
## abilities (SkillIcon): the Echo's pulse and the active skill with their
## cooldown and button, then small icons for the passive skills. Created by Hud for every registered player
## (builds its UI in code). The meter's name and colour come from the WorldConfig.

@export var bar_size: Vector2 = Vector2(300.0, 18.0)
@export var low_color: Color = Color(1.0, 0.2, 0.15)
@export var bar_background_color: Color = Color(0.1, 0.12, 0.18, 0.85)
## Warning label blinks this many times per second.
@export var warning_blink_speed: float = 2.0
@export var distress_ready_color: Color = Color(0.55, 0.95, 1.0)
@export var distress_cooldown_color: Color = Color(0.5, 0.6, 0.7)
@export var active_icon_size: float = 34.0
@export var passive_icon_size: float = 22.0
@export var skill_key_color: Color = Color(0.6, 0.66, 0.78)
## The pulse's HUD icon (the Echo only).
@export var pulse_icon_shape: SkillIcon.Shape = SkillIcon.Shape.RINGS
@export var pulse_icon_color: Color = Color(0.45, 0.95, 1.0)

var player: Player
var level_builder: LevelBuilder
var pressure_color: Color = Color(0.35, 0.8, 1.0)
var world: WorldConfig

var _depth_label: Label
var _health_segments: HealthSegments
var _pressure_bar: ProgressBar
var _fill_style: StyleBoxFlat
var _warning_label: Label
var _distress_label: Label
var _distress: DistressPulse
var _skill_row: HBoxContainer
var _active_icon: SkillIcon
var _pulse_icon: SkillIcon
var _pulse: PulseAbility
var _time: float = 0.0


func setup(target_player: Player, target_level_builder: LevelBuilder, target_world: WorldConfig) -> void:
	player = target_player
	level_builder = target_level_builder
	world = target_world
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

	_skill_row = HBoxContainer.new()
	_skill_row.add_theme_constant_override("separation", 6)
	add_child(_skill_row)
	_pulse = player.get_node_or_null("Pulse") as PulseAbility
	player.skills.changed.connect(_rebuild_skills)
	_rebuild_skills()


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
	_update_active_icon()


## The pulse (Echo) and the active skill (with their buttons), then the passive skills.
func _rebuild_skills() -> void:
	for child: Node in _skill_row.get_children():
		child.queue_free()
	_active_icon = null
	_pulse_icon = null
	if _pulse:
		_pulse_icon = SkillIcon.new()
		_pulse_icon.setup_custom(pulse_icon_shape, pulse_icon_color, active_icon_size)
		_pulse_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_skill_row.add_child(_pulse_icon)
		_add_key_label(Game.text("pulse_key"))
	for definition: SkillDefinition in player.skills.get_owned():
		var icon := SkillIcon.new()
		var rank: int = player.skills.get_rank(definition.id)
		icon.setup(definition, rank, active_icon_size if definition.is_active() else passive_icon_size)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.tooltip_text = definition.display_name(Game.language, world)
		_skill_row.add_child(icon)
		if definition.is_active():
			_active_icon = icon
			_add_key_label(Game.text("skill_key_echo" if player.skill_owner == SkillDefinition.Owner.ECHO else "skill_key_guardian"))


func _add_key_label(text: String) -> void:
	var key := Label.new()
	key.text = text
	key.add_theme_color_override("font_color", skill_key_color)
	key.add_theme_font_size_override("font_size", 14)
	key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_skill_row.add_child(key)


func _update_active_icon() -> void:
	if _pulse_icon and _pulse:
		_pulse_icon.set_state(_pulse.get_cooldown_ratio(), false)
	var active: ActiveSkill = player.skills.active
	if _active_icon == null or active == null or not is_instance_valid(active):
		return
	# A hold skill without a cooldown (Shield) just lights up while held.
	if active.get_cooldown() > 0.0:
		_active_icon.set_state(active.get_cooldown_ratio(), active.is_in_use())
	elif active.is_in_use() != _active_icon.in_use:
		_active_icon.in_use = active.is_in_use()
		_active_icon.queue_redraw()


## The Echo's pulse icon (tests).
func get_pulse_icon() -> SkillIcon:
	return _pulse_icon


func get_active_icon() -> SkillIcon:
	return _active_icon


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
