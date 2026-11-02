extends Control
## The Ocean island in the proposed art styles (tools/island_styles/: A Reef
## Dome, B Sea Globe, C Lagoon Falls), to pick the one every Journey island
## will follow. Run it (F6) to see them side by side; Up / Down lights them one
## step up / down (0 = locked .. 3). With a folder it saves one image of all of
## them, lit at stage 3 (top row) and at stage 1 (bottom row), and quits (needs
## a window); other rows: a list of lights after the folder (0 = locked):
##   godot --path . res://tools/island_style_preview.tscn -- <folder> [3,1,0]

const STYLES: Array[Script] = [
	preload("res://tools/island_styles/ocean_reef_dome.gd"), preload("res://tools/island_styles/ocean_sea_globe.gd"),
	preload("res://tools/island_styles/ocean_lagoon_falls.gd"),
]
const NAMES: PackedStringArray = ["A  Reef Dome", "B  Sea Globe", "C  Lagoon Falls"]

## One picture per style and light in the saved image (crop of the screen).
@export var cell_size: Vector2i = Vector2i(560, 700)
## The lights of the saved image's rows (stage 3, then stage 1).
@export var capture_lights: PackedFloat32Array = PackedFloat32Array([3.0, 1.0])
@export var view_scale: float = 0.72
@export var accent: Color = Color(0.45, 0.95, 1.0)
@export var top_color: Color = Color(0.02, 0.06, 0.09)
@export var step_time: float = 1.2

var _holder: Node2D
var _islands: Array[JourneyIsland] = []
var _labels: Array[Label] = []
var _light: float = 3.0
var _tween: Tween


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = Game.ui_theme
	add_child(NightSky.new())
	_holder = Node2D.new()
	add_child(_holder)
	for i: int in STYLES.size():
		var island := STYLES[i].new() as JourneyIsland
		island.seed_value = 11
		island.accent = accent
		island.top_color = top_color
		island.light = _light
		_holder.add_child(island)
		_islands.append(island)
		var label := Label.new()
		label.theme_type_variation = &"HeaderLabel"
		label.text = NAMES[i]
		add_child(label)
		_labels.append(label)
	add_child(GlowEnvironment.new())
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 1:
		capture_lights = PackedFloat32Array()
		for value: String in args[1].split(","):
			capture_lights.append(clampf(value.to_float(), 0.0, 3.0))
	if args.size() > 0:
		_capture.call_deferred(args[0])
	else:
		_layout_side_by_side()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"ui_down"):
		var target: float = clampf(_light + (1.0 if event.is_action_pressed(&"ui_up") else -1.0), 0.0, 3.0)
		if _tween:
			_tween.kill()
		_tween = create_tween().set_parallel(true)
		for island: JourneyIsland in _islands:
			_tween.tween_property(island, "light", target, step_time).set_trans(Tween.TRANS_SINE)
		_light = target
		for i: int in _labels.size():
			_labels[i].text = "%s   light %d" % [NAMES[i], int(_light)]


func _layout_side_by_side() -> void:
	for i: int in _islands.size():
		var island: JourneyIsland = _islands[i]
		var share: float = (float(i) + 0.5) / float(_islands.size())
		var rect: Rect2 = island.get_visual_rect()
		island.scale = Vector2(view_scale, view_scale)
		island.position = Vector2(size.x * share, size.y * 0.55) - rect.get_center() * view_scale
		_labels[i].position = Vector2(size.x * share - 90.0, size.y - 70.0)


func _capture(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	var sheet := Image.create_empty(cell_size.x * _islands.size(), cell_size.y * capture_lights.size(), false, Image.FORMAT_RGBA8)
	# The window's very first frames read back black.
	await _wait(1.0)
	for i: int in _islands.size():
		for row: int in capture_lights.size():
			for k: int in _islands.size():
				_islands[k].visible = k == i
				_labels[k].visible = k == i
			var island: JourneyIsland = _islands[i]
			island.light = capture_lights[row]
			var rect: Rect2 = island.get_visual_rect()
			var center: Vector2 = size * 0.5
			island.position = center - rect.get_center()
			var corner := Vector2i(center) - cell_size / 2
			var light: int = int(capture_lights[row])
			_labels[i].text = "%s   -   %s" % [NAMES[i], "locked" if light == 0 else "stage %d" % light]
			_labels[i].position = Vector2(corner) + Vector2(22.0, 14.0)
			await _wait(1.2)
			await RenderingServer.frame_post_draw
			var shot: Image = get_viewport().get_texture().get_image()
			var cell: Image = _to_srgb(shot.get_region(Rect2i(corner, cell_size)))
			sheet.blit_rect(cell, Rect2i(Vector2i.ZERO, cell_size), Vector2i(cell_size.x * i, cell_size.y * row))
			print("rendered ", NAMES[i], " light ", capture_lights[row])
	var path: String = folder.path_join("ocean_island_styles.png")
	sheet.save_png(path)
	print("saved ", path)
	get_tree().quit()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## An 8-bit sRGB copy (the viewport holds linear HDR values).
func _to_srgb(image: Image) -> Image:
	image.convert(Image.FORMAT_RGBAF)
	var data: PackedFloat32Array = image.get_data().to_float32_array()
	for i: int in range(0, data.size(), 4):
		for c: int in 3:
			var x: float = clampf(data[i + c], 0.0, 1.0)
			data[i + c] = 12.92 * x if x <= 0.0031308 else 1.055 * pow(x, 1.0 / 2.4) - 0.055
		data[i + 3] = 1.0
	var srgb := Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBAF, data.to_byte_array())
	srgb.convert(Image.FORMAT_RGBA8)
	return srgb
