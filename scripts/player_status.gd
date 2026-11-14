class_name PlayerStatus
extends VBoxContainer
## One player's HUD block in the "silhouette + glow" style: the name in the
## character's colour (the Echo cyan, the Guardian gold) with the depth beside
## it, the health pips (HealthSegments), the world's pressure meter (HudMeter:
## Oxygen in the Ocean, the WorldConfig's name and colour) with its value and
## the blinking low warning, then the abilities (SkillIcon): the Echo's pulse
## and the active skill, each with the drawn button of the player's own device
## (InputPrompt), then small icons for the passive skills; and while a player
## who has one (the Echo) is downed, the distress pulse hint. Created by Hud for
## every registered player (builds its UI in code). Each block lines up on its
## own screen edge (the Echo top left, the Guardian top right, mirrored: side);
## the texts follow the language (right-to-left in Arabic).

enum ScreenSide { LEFT, RIGHT }

@export var bar_size: Vector2 = Vector2(230.0, 10.0)
@export var low_color: Color = Color(1.0, 0.25, 0.2)
## Warning label blinks this many times per second.
@export var warning_blink_speed: float = 2.0
@export var distress_ready_color: Color = Color(0.55, 0.95, 1.0)
@export var distress_cooldown_color: Color = Color(0.5, 0.6, 0.7)
@export var active_icon_size: float = 34.0
@export var passive_icon_size: float = 22.0
@export var name_font_size: int = 19
@export var small_font_size: int = 14
## The pulse's HUD icon (the Echo only).
@export var pulse_icon_shape: SkillIcon.Shape = SkillIcon.Shape.RINGS
@export var pulse_icon_color: Color = Color(0.45, 0.95, 1.0)

var player: Player
var level_builder: LevelBuilder
var pressure_color: Color = Color(0.35, 0.8, 1.0)
var world: WorldConfig
var side: ScreenSide = ScreenSide.LEFT

var _name_label: Label
var _depth_label: Label
var _health_segments: HealthSegments
var _pressure_bar: HudMeter
var _pressure_label: Label
var _distress_label: Label
## The distress hint's row: the player's own action button + the text.
var _distress_row: HBoxContainer
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
	side = ScreenSide.LEFT if player.skill_owner == SkillDefinition.Owner.ECHO else ScreenSide.RIGHT


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 5)
	# The block mirrors towards its screen edge; the texts keep the language's direction.
	layout_direction = Control.LAYOUT_DIRECTION_RTL if side == ScreenSide.RIGHT else Control.LAYOUT_DIRECTION_LTR
	var head := _row(10)
	_name_label = _label(head, _name_variation(), name_font_size)
	_depth_label = _label(head, &"DimLabel", small_font_size)

	_health_segments = HealthSegments.new()
	_health_segments.setup(player.health)
	add_child(_health_segments)

	var meter := _row(10)
	_pressure_bar = HudMeter.new()
	_pressure_bar.custom_minimum_size = bar_size
	_pressure_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meter.add_child(_pressure_bar)
	_pressure_label = _label(meter, &"DimLabel", small_font_size)

	_distress = player.get_node_or_null("DistressPulse") as DistressPulse
	_distress_row = _row(6)
	_distress_row.visible = false
	var distress_key := InputPrompt.new()
	distress_key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_distress_row.add_child(distress_key)
	distress_key.setup_for_player([{"actions": [StringName(player.input_prefix + "action")], "text": ""}], player.player_number)
	_distress_label = _label(_distress_row, &"Label", small_font_size)

	_skill_row = _row(6)
	_pulse = player.get_node_or_null("Pulse") as PulseAbility
	player.skills.changed.connect(_rebuild_skills)
	_rebuild_skills()


func _process(delta: float) -> void:
	if player == null:
		return
	_time += delta
	var depth: float = level_builder.depth_at(player.global_position.z) if level_builder else 0.0
	var pressure: PlayerPressure = player.pressure
	var ratio: float = pressure.get_ratio()
	var downed: bool = player.health.is_downed
	_name_label.text = _character_name()
	if downed:
		_name_label.text += "  ·  " + Game.text("hud_down")
	_name_label.theme_type_variation = &"DangerLabel" if downed else _name_variation()
	_name_label.add_theme_font_size_override("font_size", name_font_size)
	_depth_label.text = Game.text("hud_depth") % roundi(depth)
	_pressure_bar.ratio = ratio
	var low: bool = pressure.is_low()
	_pressure_bar.color = low_color if low else pressure_color
	_pressure_bar.pulsing = low
	var pressure_name: String = _pressure_name()
	if low:
		_pressure_label.text = Game.text("hud_low") % pressure_name
		_pressure_label.theme_type_variation = &"DangerLabel"
		_pressure_label.modulate.a = 1.0 if fmod(_time * warning_blink_speed, 1.0) < 0.6 else 0.35
	else:
		_pressure_label.text = "%s %d%%" % [pressure_name.capitalize() if not Game.is_rtl() else pressure_name, roundi(ratio * 100.0)]
		_pressure_label.theme_type_variation = &"DimLabel"
		_pressure_label.modulate.a = 1.0
	_pressure_label.add_theme_font_size_override("font_size", small_font_size)
	_update_distress_hint()
	_update_active_icon()


func _name_variation() -> StringName:
	return &"EchoLabel" if player.skill_owner == SkillDefinition.Owner.ECHO else &"GuardianLabel"


func _character_name() -> String:
	return Game.text("char_echo" if player.skill_owner == SkillDefinition.Owner.ECHO else "char_guardian")


func _pressure_name() -> String:
	var key: String = "pressure_" + player.pressure.pressure_name
	var translated: String = Game.text(key)
	return player.pressure.pressure_name.to_lower() if translated == key else translated


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
		_add_key(StringName(player.input_prefix + "action"))
	for definition: SkillDefinition in player.skills.get_owned():
		var icon := SkillIcon.new()
		var rank: int = player.skills.get_rank(definition.id)
		icon.setup(definition, rank, active_icon_size if definition.is_active() else passive_icon_size)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.tooltip_text = definition.display_name(Game.language, world)
		_skill_row.add_child(icon)
		if definition.is_active():
			_active_icon = icon
			_add_key(StringName(player.input_prefix + "skill"))


## The button of an ability, drawn for the player's own device.
func _add_key(action: StringName) -> void:
	var prompt := InputPrompt.new()
	prompt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_skill_row.add_child(prompt)
	prompt.setup_for_player([{"actions": [action], "text": ""}], player.player_number)


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
	_distress_row.visible = _distress != null and player.health.is_downed
	if not _distress_row.visible:
		return
	if _distress.is_ready():
		_distress_label.text = Game.text("distress_ready")
		_distress_label.add_theme_color_override("font_color", distress_ready_color)
	else:
		_distress_label.text = Game.text("distress_cooldown") % _distress.cooldown_left
		_distress_label.add_theme_color_override("font_color", distress_cooldown_color)


func _row(separation: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", separation)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	return row


func _label(parent: Control, variation: StringName, font_size: int) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# The language's direction, whatever side the block mirrors to.
	label.text_direction = Control.TEXT_DIRECTION_RTL if Game.is_rtl() else Control.TEXT_DIRECTION_LTR
	parent.add_child(label)
	return label
