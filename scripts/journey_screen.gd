class_name JourneyScreen
extends Control
## The Journey (replaces the old World Map): the five worlds as floating
## islands stacked up (JourneyTower), lit by the save's progress, under a night
## sky; beside them the worlds as a vertical timeline (JourneyTimeline). Up /
## down looks at the worlds (the camera glides to the selected island, its
## theme plays, muffled if it is still locked: JourneyMusic); Continue plays
## exactly where the save stopped (Game.play_current) or says the world is
## coming soon; Back / Main Menu returns. After a cleared stage
## (Game.journey_step_from) the island lights up one step first (any button
## skips it). Arabic mirrors the layout (the timeline on the left).
## Framing: the selected island (its whole drawn area) sits in the middle of
## the free area, below the title, above the bottom bar (prompts and buttons)
## and beside the timeline; the tower fades out softly before it reaches the
## title or the bottom bar, so no island is ever drawn over them.

## Fades the tower (a material on its holder, shared with use_parent_material)
## between screen rows: gone above top_clear, whole from top_full down to
## bottom_full, gone below bottom_clear.
const FADE_SHADER: String = """
shader_type canvas_item;

uniform float top_clear = -2.0;
uniform float top_full = -1.0;
uniform float bottom_full = 100000.0;
uniform float bottom_clear = 100001.0;

void fragment() {
	float y = FRAGCOORD.y;
	COLOR.a *= smoothstep(top_clear, top_full, y) * (1.0 - smoothstep(bottom_full, bottom_clear, y));
}
"""

@export_group("Layout")
## The biggest the tower is drawn (1 = full size); smaller only when the
## biggest island would not fit the free area.
@export var tower_scale: float = 1.0
## How fast the camera glides to the selected island (per second).
@export var camera_speed: float = 3.5
@export var screen_margin: Vector2 = Vector2(64.0, 44.0)
@export var timeline_width: float = 290.0
## Room kept between the island and the timeline (x) / the title and the
## bottom bar (y).
@export var frame_padding: Vector2 = Vector2(28.0, 14.0)
## Height over which the tower fades out above the bottom bar and under the title.
@export var fade_height: float = 60.0

@export_group("Step Animation")
## Seconds after opening before the island lights up (the screen fades in first).
@export var step_delay: float = 0.9

@export_group("Sound")
@export var step_sound: StringName = &"ui_press"

var _sky: NightSky
var _holder: Node2D
var _tower: JourneyTower
var _music: JourneyMusic
var _ui: Control
var _header: Control
var _bottom_bar: Control
var _fade: ShaderMaterial
var _timeline: JourneyTimeline
var _continue_button: GlowButton
var _menu_button: GlowButton
var _help: Label
var _prompt: InputPrompt
var _current_world: int = 0
var _selected: int = 0
var _camera: Vector2 = Vector2.ZERO
var _animating: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = Game.ui_theme
	_sky = NightSky.new()
	add_child(_sky)
	_holder = Node2D.new()
	_holder.scale = Vector2(tower_scale, tower_scale)
	add_child(_holder)
	_tower = JourneyTower.new()
	_holder.add_child(_tower)
	_tower.step_finished.connect(_on_step_finished)
	var shader := Shader.new()
	shader.code = FADE_SHADER
	_fade = ShaderMaterial.new()
	_fade.shader = shader
	_holder.material = _fade
	_tower.use_parent_material = true
	for island: JourneyIsland in _tower.islands:
		island.use_parent_material = true
	var glow := GlowEnvironment.new()
	add_child(glow)
	_music = JourneyMusic.new()
	add_child(_music)
	_build_ui()

	var world_count: int = Game.world_ids.size()
	_current_world = clampi(Game.get_world_index(Game.save.world_id), 0, world_count - 1)
	var from: Vector2i = Game.journey_step_from
	Game.journey_step_from = Vector2i(-1, -1)
	if from.x >= 0:
		_tower.set_progress(from.x, from.y)
		_animating = true
		get_tree().create_timer(step_delay).timeout.connect(_play_step.bind(from))
	else:
		_tower.set_progress(_current_world, Game.save.stage_index)
	_select(_current_world)
	_camera = _camera_target()
	_continue_button.focus_quietly()
	add_to_group(FocusKeeper.GROUP)
	Game.language_changed.connect(_refresh)
	_refresh()


func _process(delta: float) -> void:
	var free: Rect2 = _free_rect()
	var view_scale: float = _fit_scale(free)
	_camera = _camera.lerp(_camera_target(), clampf(camera_speed * delta, 0.0, 1.0))
	_holder.scale = Vector2(view_scale, view_scale)
	_holder.position = free.get_center() - _camera * view_scale
	_sky.scroll = _camera
	_update_fade()


## The control focused while this screen is up (FocusKeeper).
func get_default_focus() -> Control:
	return _continue_button


## Up / down look at the worlds; any press skips the step animation.
func _input(event: InputEvent) -> void:
	if _animating and _is_press(event):
		_tower.skip()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_up"):
		_select(mini(_selected + 1, Game.world_ids.size() - 1), true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_down"):
		_select(maxi(_selected - 1, 0), true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		Game.go_to_main_menu()


## Where the islands may be drawn (this screen's pixels): below the title,
## above the bottom bar and beside the timeline (right of it in Arabic).
func _free_rect() -> Rect2:
	var header: Rect2 = _local_rect(_header)
	var bar: Rect2 = _local_rect(_bottom_bar)
	var timeline: Rect2 = _local_rect(_timeline)
	var top: float = header.end.y + frame_padding.y
	var bottom: float = bar.position.y - frame_padding.y
	var left: float = screen_margin.x
	var right: float = size.x - screen_margin.x
	if timeline.get_center().x > size.x * 0.5:
		right = timeline.position.x - frame_padding.x
	else:
		left = timeline.end.x + frame_padding.x
	return Rect2(left, top, maxf(right - left, 1.0), maxf(bottom - top, 1.0))


func _local_rect(control: Control) -> Rect2:
	return get_global_transform().affine_inverse() * control.get_global_rect()


## tower_scale, or smaller so that even the biggest island fits the free area
## (one scale for all, so moving between islands never zooms).
func _fit_scale(free: Rect2) -> float:
	var need := Vector2.ONE
	for island: JourneyIsland in _tower.islands:
		var island_size: Vector2 = island.get_visual_rect().size
		need = Vector2(maxf(need.x, island_size.x), maxf(need.y, island_size.y))
	return minf(tower_scale, minf(free.size.x / need.x, free.size.y / need.y))


## The tower fades out over fade_height before the bottom bar (gone at its
## top edge) and under the title.
func _update_fade() -> void:
	var to_screen: Transform2D = get_global_transform_with_canvas()
	var title_bottom: float = (to_screen * _local_rect(_header).end).y
	var bar_top: float = (to_screen * _local_rect(_bottom_bar).position).y
	_fade.set_shader_parameter("top_clear", title_bottom - fade_height)
	_fade.set_shader_parameter("top_full", title_bottom)
	_fade.set_shader_parameter("bottom_full", bar_top - fade_height)
	_fade.set_shader_parameter("bottom_clear", bar_top)


## The middle of the selected island's drawn area (tower space).
func _camera_target() -> Vector2:
	return _tower.get_focus_point(_selected)


func _select(index: int, by_player: bool = false) -> void:
	if by_player and index != _selected:
		UiAudio.play_in(get_tree(), &"ui_focus")
	_selected = index
	_timeline.set_selected(index)
	var world_id: String = Game.world_ids[index]
	_music.play_world(world_id, index > _current_world)
	_help.text = ""


func _play_step(from: Vector2i) -> void:
	UiAudio.play_in(get_tree(), step_sound)
	_tower.play_step(from.x, from.y, _current_world, Game.save.stage_index)
	_refresh_prompt()


func _on_step_finished() -> void:
	_animating = false
	_refresh_prompt()


func _on_continue_pressed() -> void:
	if _animating:
		_tower.skip()
	if Game.can_play_current():
		Game.play_current()
		return
	var world: WorldConfig = Game.get_current_world()
	if world == null and _current_world < Game.world_ids.size():
		_help.text = Game.text("coming_soon") % Game.world_display_name(Game.save.world_id)
	else:
		_help.text = Game.text("journey_finished")


func _build_ui() -> void:
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, int(screen_margin.x))
	for side: String in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(screen_margin.y))
	_ui.add_child(margin)
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(rows)
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 2)
	rows.add_child(header)
	_header = header
	var title := Label.new()
	title.name = "Title"
	title.theme_type_variation = &"HeaderLabel"
	header.add_child(title)
	var rule := WaveRule.new()
	rule.custom_minimum_size = Vector2(150.0, 12.0)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	header.add_child(rule)
	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(middle)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.add_child(spacer)
	_timeline = JourneyTimeline.new()
	_timeline.custom_minimum_size.x = timeline_width
	_timeline.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_timeline.row_clicked.connect(_select.bind(true))
	middle.add_child(_timeline)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(bottom)
	_bottom_bar = bottom
	var bottom_text := VBoxContainer.new()
	bottom_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_text.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_child(bottom_text)
	_help = Label.new()
	_help.theme_type_variation = &"DimLabel"
	bottom_text.add_child(_help)
	_prompt = InputPrompt.new()
	bottom_text.add_child(_prompt)
	_menu_button = GlowButton.new()
	_menu_button.pressed.connect(Game.go_to_main_menu)
	bottom.add_child(_menu_button)
	_continue_button = GlowButton.new()
	_continue_button.pressed.connect(_on_continue_pressed)
	bottom.add_child(_continue_button)
	# Up / down belong to the worlds, so the buttons only lead to each other.
	for button: GlowButton in [_menu_button, _continue_button]:
		button.focus_neighbor_top = button.get_path()
		button.focus_neighbor_bottom = button.get_path()


func _refresh() -> void:
	Game.apply_direction(self)
	(_ui.find_child("Title", true, false) as Label).text = Game.text("journey_title")
	var names := PackedStringArray()
	var states: Array[JourneyTimeline.State] = []
	var accents: Array[Color] = []
	for i: int in Game.world_ids.size():
		var world_id: String = Game.world_ids[i]
		names.append(Game.world_display_name(world_id))
		accents.append(_tower.island_accents[i % _tower.island_accents.size()])
		if i < _current_world or Game.is_world_completed(world_id):
			states.append(JourneyTimeline.State.RESTORED)
		elif i == _current_world:
			states.append(JourneyTimeline.State.CURRENT)
		else:
			states.append(JourneyTimeline.State.LOCKED)
	_timeline.setup(names, states, accents, Game.text("journey_stage") % (Game.save.stage_index + 1))
	_timeline.set_selected(_selected)
	_continue_button.text = Game.text("continue")
	_menu_button.text = Game.text("main_menu")
	_refresh_prompt()


func _refresh_prompt() -> void:
	var entries: Array[Dictionary] = []
	if _animating:
		entries.append({"actions": [&"ui_accept"], "text": Game.text("prompt_skip")})
	else:
		entries.append({"actions": [&"ui_up", &"ui_down"], "text": Game.text("prompt_worlds")})
		entries.append({"actions": [&"ui_accept"], "text": Game.text("prompt_select")})
		entries.append({"actions": [&"ui_cancel"], "text": Game.text("prompt_back")})
	_prompt.setup(entries, InputDevices.menu_device, true)


func _is_press(event: InputEvent) -> bool:
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton:
		return event.is_pressed() and not event.is_echo()
	return false
